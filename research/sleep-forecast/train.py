"""Predict tonight's main sleep minutes, with a frozen cross-campus evaluation."""

import argparse
import json
from pathlib import Path

import numpy as np
import pandas as pd
from sklearn.ensemble import GradientBoostingRegressor
from sklearn.linear_model import Ridge
from sklearn.model_selection import GroupShuffleSplit
from sklearn.pipeline import make_pipeline
from sklearn.preprocessing import StandardScaler

from download import NETHEALTH, UVA_REV, checksum

ROOT = Path(__file__).resolve().parent
SEED = 924
DAY = pd.Timedelta(days=1)
FEATURES = [
    "median_minutes", "mean_minutes", "sd_minutes", "recent_two_mean",
    "last_minutes", "median_start", "median_end", "nights", "last_gap", "weekend",
]
ACTIVITY = ["steps", "active_minutes", "average_bpm"]
TARGET = "asleep"


def nethealth_nights(path):
    raw = pd.read_csv(path, dtype={"egoid": "str"})
    end_day = pd.to_datetime(raw["dataDate"], errors="coerce")
    start_time = pd.to_timedelta(raw["timetobed"], errors="coerce")
    end_time = pd.to_timedelta(raw["timeoutofbed"], errors="coerce")
    start = end_day + start_time - pd.to_timedelta((start_time > end_time).astype(int), unit="D")
    end = end_day + end_time
    clock_span = (end - start).dt.total_seconds() / 60
    # Leave one hour of tolerance for clock changes and clock rounding.
    usable = (clock_span - pd.to_numeric(raw["bedtimedur"], errors="coerce")).abs() <= 61
    frame = pd.DataFrame({"person": raw["egoid"], "start": start, "end": end, TARGET: raw["minsasleep"]})
    return frame.loc[usable], len(raw)


def uva_nights(directory):
    files = sorted(directory.glob("*.csv"))
    if len(files) != 161:
        raise ValueError("Fetch the complete 161-file UVA sleep release before external evaluation")
    frames = [pd.read_csv(path) for path in files]
    raw = pd.concat(frames, ignore_index=True)
    main = raw["is_main_sleep"].astype("str").str.casefold().eq("true")
    picked = raw.loc[main]
    frame = pd.DataFrame({
        "person": picked["device_id"].astype("str"),
        "start": pd.to_datetime(picked["local_start_date_time"], format="ISO8601", errors="coerce"),
        "end": pd.to_datetime(picked["local_end_date_time"], format="ISO8601", errors="coerce"),
        TARGET: picked["minutes_asleep"],
    })
    return frame, len(raw)


def clock_minutes(stamps):
    return stamps.dt.hour * 60 + stamps.dt.minute


def normalize_nights(frame):
    result = frame.dropna().copy()
    result[TARGET] = pd.to_numeric(result[TARGET], errors="coerce")
    span = (result["end"] - result["start"]).dt.total_seconds() / 60
    result["wake_day"] = result["end"].dt.normalize()
    result["start_min"] = clock_minutes(result["start"])
    result["end_min"] = clock_minutes(result["end"])
    result["start_min"] = result["start_min"].where(result["start_min"] < 720, result["start_min"] - 1440)
    cutoff = result["wake_day"] - pd.Timedelta(hours=4)  # 20:00 on the previous local day
    next_morning = result["wake_day"] + pd.Timedelta(hours=6)
    result = result.loc[
        result[TARGET].between(180, 720)
        & span.between(180, 840)
        & (result[TARGET] <= span + 61)
        & (result["start"] >= cutoff)
        & (result["start"] < next_morning)
        & (result["end_min"] < 720)
    ]
    # NetHealth has no main-sleep flag in its CSV. Within the overnight window use the longest episode.
    return (
        result.sort_values([TARGET, "start"], ascending=[False, True])
        .drop_duplicates(["person", "wake_day"])
        .sort_values(["person", "wake_day"])
        .reset_index(drop=True)
    )


def make_features(nights):
    """Lag by calendar day, so a missed night never widens the lookback beyond seven days."""
    index = pd.MultiIndex.from_frame(nights[["person", "wake_day"]])
    observed = nights.set_index(["person", "wake_day"])[[TARGET, "start_min", "end_min"]]
    lags = []
    for days in range(1, 8):
        earlier = pd.MultiIndex.from_arrays(
            [index.get_level_values("person"), index.get_level_values("wake_day") - days * DAY]
        )
        lags.append(observed.reindex(earlier).to_numpy())
    history = np.stack(lags, axis=1)
    durations = history[:, :, 0]
    counts = np.isfinite(durations).sum(axis=1)
    eligible = counts >= 3
    result = nights.loc[eligible, ["person", "wake_day", TARGET]].copy()
    history, durations = history[eligible], durations[eligible]
    mask = np.isfinite(durations)
    ranks = np.cumsum(mask, axis=1)
    recent_two = mask & (ranks <= 2)
    first = mask.argmax(axis=1)
    result["median_minutes"] = np.nanmedian(durations, axis=1)
    result["mean_minutes"] = np.nanmean(durations, axis=1)
    result["sd_minutes"] = np.nanstd(durations, axis=1)
    result["recent_two_mean"] = np.nanmean(np.where(recent_two, durations, np.nan), axis=1)
    result["last_minutes"] = durations[np.arange(len(result)), first]
    result["median_start"] = np.nanmedian(history[:, :, 1], axis=1)
    result["median_end"] = np.nanmedian(history[:, :, 2], axis=1)
    result["nights"] = counts[eligible]
    result["last_gap"] = first + 1
    result["weekend"] = (result["wake_day"].dt.dayofweek >= 5).astype(int)
    return result


def attach_activity(records, path):
    columns = ["egoid", "datadate", "complypercent", "steps", "meanrate", "fairlyactiveminutes", "veryactiveminutes"]
    raw = pd.read_csv(path, usecols=columns, dtype={"egoid": "str"})
    for key in columns[2:]:
        raw[key] = pd.to_numeric(raw[key], errors="coerce")
    raw["wake_day"] = pd.to_datetime(raw["datadate"], errors="coerce") + 2 * DAY
    raw["active_minutes"] = raw["fairlyactiveminutes"] + raw["veryactiveminutes"]
    values = (
        raw.loc[
            raw["complypercent"].between(60, 100) & raw["steps"].between(0, 120_000)
            & raw["meanrate"].between(35, 180) & raw["active_minutes"].between(0, 720)
        ]
        .rename(columns={"egoid": "person", "meanrate": "average_bpm"})
        .sort_values("complypercent", ascending=False)
        .drop_duplicates(["person", "wake_day"])
    )
    return records.merge(values[["person", "wake_day", *ACTIVITY]], how="inner", validate="one_to_one")


def split(records):
    # Two independent grouped splits, applying both before model fitting.
    groups = records["person"].to_numpy()
    keep, test = next(GroupShuffleSplit(n_splits=1, test_size=0.2, random_state=SEED).split(records, groups=groups))
    pool = records.iloc[keep]
    train, validation = next(
        GroupShuffleSplit(n_splits=1, test_size=0.25, random_state=SEED + 1).split(pool, groups=pool["person"])
    )
    held_out = pool.iloc[validation]
    select, calibrate = next(
        GroupShuffleSplit(n_splits=1, test_size=0.5, random_state=SEED + 2).split(held_out, groups=held_out["person"])
    )
    return {
        "train": pool.iloc[train], "validation": held_out.iloc[select],
        "calibration": held_out.iloc[calibrate], "test": records.iloc[test],
    }


def metrics(sample, prediction, baseline):
    error = np.asarray(prediction) - sample[TARGET].to_numpy()
    baseline_error = np.abs(np.asarray(baseline) - sample[TARGET].to_numpy())
    paired = pd.DataFrame({"person": sample["person"].to_numpy(), "gain": baseline_error - np.abs(error)})
    by_person = paired.groupby("person")["gain"].agg(["sum", "count"]).to_numpy()
    rng = np.random.default_rng(SEED)
    bootstrap = by_person[rng.integers(0, len(by_person), size=(1000, len(by_person)))].sum(axis=1)
    return {
        "people": len(by_person), "nights": len(sample), "mae_minutes": float(np.abs(error).mean()),
        "bias_minutes": float(error.mean()), "median_baseline_mae": float(baseline_error.mean()),
        "improvement_minutes": float(paired["gain"].mean()),
        "improvement_ci95": np.quantile(bootstrap[:, 0] / bootstrap[:, 1], [0.025, 0.975]).tolist(),
    }


def score(model, sample, columns, radius=None):
    baseline = sample["median_minutes"]
    predicted = baseline if model is None else model.predict(sample[columns])
    results = metrics(sample, predicted, baseline)
    if radius is not None:
        results["unrounded_interval_coverage"] = float((np.abs(predicted - sample[TARGET]) <= radius).mean())
    return results


def train_models(training, columns):
    models = {
        "median": None,
        "ridge": make_pipeline(StandardScaler(), Ridge(alpha=10)),
        "boosted_trees": GradientBoostingRegressor(
            n_estimators=70, max_depth=3, min_samples_leaf=80, loss="absolute_error", random_state=SEED
        ),
    }
    for model in models.values():
        if model is not None:
            model.fit(training[columns], training[TARGET])
    return models


def export_model(model_name, model, radius):
    result = {"schemaVersion": 1, "model": model_name, "features": FEATURES, "radiusMinutes": radius}
    if model_name == "ridge":
        scaler, ridge = model.steps[0][1], model.steps[1][1]
        weights = ridge.coef_ / scaler.scale_
        result["intercept"] = float(ridge.intercept_ - np.dot(weights, scaler.mean_))
        result["weights"] = weights.tolist()
    elif model_name == "boosted_trees":
        result["intercept"] = float(model.init_.constant_.item())
        result["learningRate"] = model.learning_rate
        result["trees"] = [{
            "left": est.tree_.children_left.tolist(),
            "right": est.tree_.children_right.tolist(),
            "feature": est.tree_.feature.tolist(),
            "threshold": est.tree_.threshold.tolist(),
            "value": est.tree_.value[:, 0, 0].tolist(),
        } for est in model.estimators_[:, 0]]
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--data", type=Path, default=ROOT / "data")
    parser.add_argument("--output", type=Path, default=ROOT / "runs" / "campus-v1")
    args = parser.parse_args()
    for key, (_, digest) in NETHEALTH.items():
        if checksum(args.data / f"nethealth-{key}.csv") != digest:
            raise ValueError(f"Unexpected NetHealth {key} file. Run download.py to verify it.")
    raw, net_count = nethealth_nights(args.data / "nethealth-sleep.csv")
    nights = normalize_nights(raw)
    records = make_features(nights)
    splits = split(records)
    models = train_models(splits["train"], FEATURES)
    validation = {name: score(model, splits["validation"], FEATURES) for name, model in models.items()}
    chosen = min(models, key=lambda name: validation[name]["mae_minutes"])
    model = models[chosen]
    calibration = splits["calibration"]
    calibration_prediction = calibration["median_minutes"] if model is None else model.predict(calibration[FEATURES])
    radius = int(np.ceil(np.quantile(np.abs(calibration_prediction - calibration[TARGET]), 0.8, method="higher")))
    testing = score(model, splits["test"], FEATURES, radius)
    print(f"NetHealth chosen model: {chosen} ({testing['mae_minutes']:.2f} min held-out MAE)", flush=True)

    uva_raw, uva_count = uva_nights(args.data / "uva-sleep")
    uva = normalize_nights(uva_raw)
    uva_records = make_features(uva)
    external = score(model, uva_records, FEATURES, radius)
    print(f"UVA frozen model: {external['mae_minutes']:.2f} min MAE", flush=True)

    # Isolate the effect of activity by comparing both models on the same eligible people and nights.
    activity_path = args.data / "nethealth-activity.csv"
    matched = {part: attach_activity(splits[part], activity_path) for part in ("train", "validation", "test")}
    activity_model = train_models(matched["train"], FEATURES + ACTIVITY)["boosted_trees"]
    sleep_model = train_models(matched["train"], FEATURES)["boosted_trees"]
    activity = {
        "train_nights": len(matched["train"]),
        "validation_sleep_only": score(sleep_model, matched["validation"], FEATURES),
        "validation_sleep_and_activity": score(activity_model, matched["validation"], FEATURES + ACTIVITY),
        "test_sleep_only": score(sleep_model, matched["test"], FEATURES),
        "test_sleep_and_activity": score(activity_model, matched["test"], FEATURES + ACTIVITY),
    }

    results = {
        "dataset": {
            "nethealth": {"raw_rows": net_count, "usable_nights": len(nights), "usable_people": nights["person"].nunique()},
            "uva": {"revision": UVA_REV, "raw_rows": uva_count, "usable_nights": len(uva), "usable_people": uva["person"].nunique()},
        },
        "features": FEATURES,
        "train": {"people": splits["train"]["person"].nunique(), "nights": len(splits["train"])},
        "calibration": {"people": calibration["person"].nunique(), "nights": len(calibration), "radius_minutes": radius},
        "validation": validation, "selected": chosen, "nethealth_test": testing,
        "uva_external": external, "activity_experiment": activity,
    }
    args.output.mkdir(parents=True, exist_ok=False)
    (args.output / "metrics.json").write_text(json.dumps(results, indent=2) + "\n")
    (args.output / "model.json").write_text(json.dumps(export_model(chosen, model, radius), separators=(",", ":")) + "\n")


if __name__ == "__main__":
    main()
