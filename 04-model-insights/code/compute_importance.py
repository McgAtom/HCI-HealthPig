"""Reproduce the deployed binary classifier's validation-set permutation experiment."""
import argparse
import hashlib
import json
from pathlib import Path

import numpy as np
import pandas as pd
from sklearn.base import BaseEstimator, ClassifierMixin
from sklearn.inspection import permutation_importance
from sklearn.metrics import balanced_accuracy_score

ROOT = next((parent for parent in Path(__file__).resolve().parents
             if (parent / "apps").is_dir()), Path.cwd())
LOCAL = (ROOT / "assignments").is_dir()
WALK = ROOT / ("assignments/01-health-model" if LOCAL else "01-lesson-1") / "capture24-walking"
APP = ROOT / ("apps/healthpig-watch/native-app" if LOCAL else "apps/healthpig-native")
REPEATS, SEED = 40, 20261115
# Compute all 24. The overview includes the global maximum and minimum and the
# strongest remaining member of three distinct input families (skip duplicates).
FAMILIES = [
    ["mag_std", "diff_std", "mag_abs_dev", "mag_range", "diff_abs_mean", "axis_std_total", "axis_std_min", "axis_std_max"],
    ["acf1", "acf10", "acf20", "acf40"],
    ["peak_hz", "power_low", "power_walk", "power_high", "spectral_entropy"],
]
META = {
    "mag_mean": ("平均幅值", "g", "整段加速度幅值的平均"),
    "mag_std": ("幅值波动", "g", "加速度幅值的标准差"),
    "mag_p10": ("幅值低位", "g", "加速度幅值的第 10 百分位数"),
    "mag_p50": ("幅值中位", "g", "加速度幅值的中位数"),
    "mag_p90": ("幅值高位", "g", "加速度幅值的第 90 百分位数"),
    "mag_range": ("幅值范围", "g", "最大与最小加速度幅值之差"),
    "mag_abs_dev": ("平均偏差", "g", "幅值离各段平均值的平均绝对距离"),
    "mag_rms": ("幅值均方根", "g", "幅值平方的平均再开方"),
    "diff_abs_mean": ("相邻变化", "g", "相邻采样幅值差的平均绝对值"),
    "diff_std": ("变化波动", "g", "相邻采样幅值差的标准差"),
    "acf1": ("短时相似度", "无单位", "幅值信号错开 0.05 秒后的相似程度"),
    "acf10": ("半秒相似度", "无单位", "幅值信号错开 0.5 秒后的相似程度"),
    "acf20": ("一秒相似度", "无单位", "幅值信号错开 1 秒后的相似程度"),
    "acf40": ("两秒相似度", "无单位", "幅值信号错开 2 秒后的相似程度"),
    "peak_hz": ("主频", "Hz", "幅值信号能量最高的频率；无有效频谱时为 0"),
    "power_low": ("低频能量占比", "%", "0.2–0.8 Hz（不含上限）内的频谱能量比例"),
    "power_walk": ("步频能量占比", "%", "0.8–3 Hz（不含上限）内的频谱能量比例"),
    "power_high": ("高频能量占比", "%", "3–8 Hz 内的频谱能量比例"),
    "spectral_entropy": ("频谱分散度", "无单位", "幅值信号能量在频率上的分散程度"),
    "mean_vector_norm": ("平均向量长度", "g", "先按三轴分别取均值，再计算向量长度"),
    "axis_std_total": ("三轴总波动", "g", "三轴标准差组成的向量长度"),
    "axis_std_min": ("最小轴波动", "g", "三轴标准差中最小的一项"),
    "axis_std_max": ("最大轴波动", "g", "三轴标准差中最大的一项"),
    "mag_skew": ("幅值偏态", "无单位", "单窗口内幅值分布的不对称程度"),
}


class FrozenMotionClassifier(ClassifierMixin, BaseEstimator):
    def __init__(self, model):
        self.model = model
        self.classes_ = np.array([0, 1])
        self.offset = np.array(model["mean"], dtype=float)
        self.scale = np.array(model["scale"], dtype=float)
        self.weights = np.array(model["coefficients"], dtype=float)

    def fit(self, X, y=None):
        raise RuntimeError("Deployment parameters are frozen; this estimator never fits.")

    def scores(self, X):
        z = ((np.asarray(X) - self.offset) / self.scale) @ self.weights + self.model["intercept"]
        return np.exp(-np.logaddexp(0, -z))

    def predict(self, X):
        return (self.scores(X) >= self.model["threshold"]).astype(int)


def sha(path):
    with path.open("rb") as stream:
        return hashlib.file_digest(stream, "sha256").hexdigest()


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--data", type=Path, default=WALK / "data/shared-activity-data.csv")
    ap.add_argument("--splits", type=Path, default=WALK / "data/frozen-splits.json")
    ap.add_argument("--model", type=Path, default=APP / "Resources/motion-model.json")
    ap.add_argument("--output", type=Path, required=True)
    ap.add_argument("--include-cases", action="store_true", help="Include two de-identified validation examples in a local artifact.")
    args = ap.parse_args()
    model = json.loads(args.model.read_text())
    assert model["kind"] == "logistic" and list(META) == model["features"]
    data = pd.read_csv(args.data)
    splits = json.loads(args.splits.read_text())
    persons = [set(splits[s]) for s in ("train", "validation", "test")]
    assert not any(a & b for i, a in enumerate(persons) for b in persons[i + 1:])
    names = model["features"]
    valid = data.loc[data.split.eq("validation")].reset_index(drop=True)
    assert set(valid.pid) == persons[1]
    x = valid[names].to_numpy(dtype=float)
    y = valid.label.to_numpy(dtype=int)
    assert set(y) == {0, 1} and np.isfinite(x).all()
    classifier = FrozenMotionClassifier(model)
    scores = classifier.scores(x)
    predicted = classifier.predict(x)
    baseline = balanced_accuracy_score(y, predicted)
    # sklearn shuffles exactly one column per repeat, scores the fixed estimator,
    # and returns baseline minus shuffled score. We report percentage points.
    result = permutation_importance(classifier, x, y, scoring="balanced_accuracy",
                                    n_repeats=REPEATS, random_state=SEED, n_jobs=1)
    rows = []
    for i, name in enumerate(names):
        title, unit, meaning = META[name]
        values = x[:, i] * (100 if unit == "%" else 1)
        # Eight equal-width bins over the full observed range (no clipping).
        counts, edges = np.histogram(values, bins=8)
        drops = result.importances[i] * 100
        rows.append(dict(id=name, title=title, unit=unit, meaning=meaning, index=i,
                         mean=float(drops.mean()), low=float(drops.min()),
                         high=float(drops.max()), repeats=drops.tolist(),
                         bins=[dict(lower=float(a), upper=float(b), count=int(n))
                               for a, b, n in zip(edges[:-1], edges[1:], counts)],
                         median=float(np.median(values))))
    ranked = sorted(rows, key=lambda row: (-row["mean"], row["index"]))
    selected = {ranked[0]["id"], ranked[-1]["id"]}
    for group in FAMILIES:
        selected.add(next(row["id"] for row in ranked if row["id"] in group and row["id"] not in selected))
    cases = []
    if args.include_cases:
        # Same true class; choose the middle score among each outcome outside the
        # UI's uncertainty band. This keeps the app outcome and binary metric aligned.
        for correct in [True, False]:
            eligible = np.flatnonzero((y == 1) & ((predicted == y) == correct)
                                      & (np.abs(scores - model["threshold"]) >= 0.1))
            eligible = eligible[np.argsort(scores[eligible], kind="stable")]
            j = eligible[len(eligible) // 2]
            cases.append(dict(id="correct" if correct else "wrong",
                              actual=int(y[j]), prediction=int(predicted[j]),
                              score=float(scores[j]), inputs=x[j].tolist()))
    payload = dict(schema=1, dataset="CAPTURE-24", split="validation", windows=len(valid),
                   people=valid.pid.nunique(), walking=int((y == 1).sum()),
                   still=int((y == 0).sum()), baseline=float(baseline * 100),
                   threshold=model["threshold"], repeats=REPEATS, seed=SEED,
                   overview=[row["id"] for row in ranked if row["id"] in selected],
                   features=ranked, cases=cases, modelSHA256=sha(args.model),
                   dataSHA256=sha(args.data), splitSHA256=sha(args.splits))
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(payload, ensure_ascii=False, allow_nan=False,
                                      indent=2) + "\n")
    print(f"Validation: {payload['people']} people, {len(valid)} windows, BA={baseline:.4%}")
    for row in ranked:
        print(f"{'*' if row['id'] in selected else ' '} {row['id']:18} {row['mean']:+7.3f} pp [{row['low']:+.3f}, {row['high']:+.3f}]")


if __name__ == "__main__":
    main()
