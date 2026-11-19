"""Measure deployed sleep-model reliance on the frozen UVA external cohort."""

import argparse
import hashlib
import json
from pathlib import Path

import numpy as np

from train import FEATURES, TARGET, UVA_REV, make_features, normalize_nights, uva_nights


REPEATS, SEED = 40, 20261120
META = {
    "median_minutes": ("实睡时长中位数", "分钟", "近七天有效夜晚的实睡时长中位数"),
    "mean_minutes": ("平均实睡时长", "分钟", "近七天有效夜晚的平均实睡时长"),
    "sd_minutes": ("实睡时长波动", "分钟", "近七天有效夜晚实睡时长的总体标准差"),
    "recent_two_mean": ("近两晚平均实睡", "分钟", "最近两个有效夜晚的平均实睡时长"),
    "last_minutes": ("上一晚实睡", "分钟", "最近一次有效主睡眠的实睡时长"),
    "median_start": ("常见主睡开始", "分钟", "主睡眠开始时刻的中位数，以午夜为零，午夜前为负数"),
    "median_end": ("常见主睡结束", "分钟", "主睡眠结束时刻的中位数，以午夜为零"),
    "nights": ("有效记录数量", "晚", "近七天符合主睡眠条件的夜晚数量"),
    "last_gap": ("最近记录间隔", "天", "最近有效记录的结束日期距离预测目标早晨的天数"),
    "weekend": ("次晨是否周末", "0 / 1", "预测目标的早晨是否为周末，1 为周末，0 为工作日"),
}


def tree_scores(tree, values):
    left, right, feature, threshold, leaf = tree
    rows = np.arange(len(values))
    nodes = np.zeros(len(values), dtype=np.intp)
    active = rows[left[nodes] >= 0]
    while len(active):
        branches = nodes[active]
        go_left = values[active, feature[branches]] <= threshold[branches]
        nodes[active] = np.where(go_left, left[branches], right[branches])
        active = active[left[nodes[active]] >= 0]
    return leaf[nodes]


def example_pair(records, target, predictions):
    error = np.abs(predictions - target)
    results = []
    for case_id, limits in (("near", error <= 30), ("far", error >= 90)):
        eligible = np.flatnonzero(limits)
        ranked = eligible[np.argsort(error[eligible], kind="stable")]
        example = ranked[len(ranked) // 2]
        results.append(dict(id=case_id, actual=float(target[example]), prediction=float(predictions[example]),
                            inputs=records.iloc[example][FEATURES].to_numpy(dtype=float).tolist()))
    return results


def histogram(values, field):
    if field in {"nights", "last_gap", "weekend"}:
        edges = np.arange(values.min() - 0.5, values.max() + 1, dtype=float)
        counts, edges = np.histogram(values, bins=edges)
    else:
        counts, edges = np.histogram(values, bins=8)
    return [dict(lower=float(a), upper=float(b), count=int(count))
            for a, b, count in zip(edges[:-1], edges[1:], counts, strict=True)]


def measure(model, records):
    if model["schemaVersion"] != 1 or model["model"] != "boosted_trees" or model["features"] != FEATURES:
        raise ValueError("Expected the deployed version 1 boosted-tree sleep model and its original feature order")

    trees = [tuple(np.asarray(item[key]) for key in ("left", "right", "feature", "threshold", "value"))
             for item in model["trees"]]
    values = records[FEATURES].to_numpy(dtype=np.float32, copy=True)
    target = records[TARGET].to_numpy(dtype=float)
    if not np.isfinite(values).all() or not np.isfinite(target).all():
        raise ValueError("Validation inputs and targets must be finite")
    rate = model["learningRate"]
    contributions = [rate * tree_scores(tree, values) for tree in trees]
    predictions = np.full(len(values), model["intercept"], dtype=float)
    for contribution in contributions:
        predictions += contribution
    baseline = float(np.abs(predictions - target).mean())
    rng = np.random.default_rng(SEED)
    rankings = []
    for index, field in enumerate(FEATURES):
        original = values[:, index].copy()
        affected = [i for i, tree in enumerate(trees) if index in tree[2]]
        unchanged = predictions.copy()
        for i in affected:
            unchanged -= contributions[i]
        changes = []
        for _ in range(REPEATS):
            values[:, index] = rng.permutation(original)
            estimate = unchanged.copy()
            for i in affected:
                estimate += rate * tree_scores(trees[i], values)
            changes.append(float(np.abs(estimate - target).mean() - baseline))
        values[:, index] = original
        title, unit, meaning = META[field]
        rankings.append(dict(id=field, title=title, unit=unit, meaning=meaning, index=index,
                             mean=float(np.mean(changes)), low=min(changes), high=max(changes),
                             repeats=changes, bins=histogram(original, field)))
    rankings.sort(key=lambda item: (-item["mean"], item["index"]))
    return baseline, rankings, example_pair(records, target, predictions)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--model", required=True, type=Path)
    parser.add_argument("--uva", required=True, type=Path)
    parser.add_argument("--output", required=True, type=Path)
    parser.add_argument("--include-cases", action="store_true", help="Add two de-identified course examples")
    args = parser.parse_args()

    raw, _ = uva_nights(args.uva)
    records = make_features(normalize_nights(raw))
    model_bytes = args.model.read_bytes()
    baseline, rankings, cases = measure(json.loads(model_bytes), records)
    overview = [item["id"] for item in rankings[:4]] + [rankings[-1]["id"]]
    payload = dict(schema=2, dataset="UVA Human Rhythms", split="external", datasetRevision=UVA_REV,
                   windows=len(records), people=int(records["person"].nunique()), baseline=baseline,
                   repeats=REPEATS, seed=SEED, overview=overview, features=rankings,
                   cases=cases if args.include_cases else [], modelSHA256=hashlib.sha256(model_bytes).hexdigest())
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(payload, ensure_ascii=False, indent=2, allow_nan=False) + "\n")
    print(f"{payload['people']} people, {payload['windows']} nights, baseline MAE {baseline:.6f} min")
    for row in rankings:
        print(f"{row['id']:18} {row['mean']:+.4f} min [{row['low']:+.4f}, {row['high']:+.4f}]")


if __name__ == "__main__":
    main()
