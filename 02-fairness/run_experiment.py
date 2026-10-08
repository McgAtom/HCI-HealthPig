"""Person-separated fairness experiment. All selection precedes test evaluation."""
from pathlib import Path
from functools import partial
import argparse
import hashlib
import json
import platform
import time
from datetime import datetime, timezone
import numpy as np
import pandas as pd
import joblib
import sklearn
import scipy
import fairlearn
from sklearn.base import clone
from sklearn.metrics import accuracy_score, balanced_accuracy_score, f1_score, confusion_matrix
from fairlearn.metrics import MetricFrame, equalized_odds_difference, demographic_parity_difference
from fairlearn.reductions import ExponentiatedGradient, EqualizedOdds

ROOT = Path(__file__).resolve().parent
PLAN = json.loads((ROOT / 'experiment-plan.json').read_text())
SOURCE = (ROOT / PLAN['source_root']).resolve()
FEATURES = json.loads((SOURCE / 'experiment-plan.json').read_text())['features']

def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()

def clean(value):
    if isinstance(value, dict): return {str(k): clean(v) for k, v in value.items()}
    if isinstance(value, (list, tuple)): return [clean(v) for v in value]
    if isinstance(value, np.generic): return clean(value.item())
    if isinstance(value, float) and not np.isfinite(value): return None
    return value

def write(path, value):
    path.write_text(json.dumps(clean(value), indent=2, ensure_ascii=False, allow_nan=False) + '\n')

def rate(y, p, *, label, prediction):
    y, p = np.asarray(y), np.asarray(p)
    mask = y == label
    return float(np.mean(p[mask] == prediction)) if mask.any() else np.nan

def balanced(y, p):
    return balanced_accuracy_score(y, p) if len(np.unique(y)) == 2 else np.nan

METRICS = {
    'samples': lambda y, p: len(y),
    'positive': lambda y, p: int(np.sum(np.asarray(y) == 1)),
    'negative': lambda y, p: int(np.sum(np.asarray(y) == 0)),
    'label_positive_rate': lambda y, p: float(np.mean(y)),
    'accuracy': accuracy_score,
    'balanced_accuracy': balanced,
    'f1_positive': partial(f1_score, zero_division=0),
    'f1_macro': partial(f1_score, average='macro', labels=[0, 1], zero_division=0),
    'tpr': partial(rate, label=1, prediction=1),
    'fnr': partial(rate, label=1, prediction=0),
    'fpr': partial(rate, label=0, prediction=1),
    'selection_rate': lambda y, p: float(np.mean(p)),
}

def audit(part, prediction, attribute):
    frame = MetricFrame(metrics=METRICS, y_true=part.label, y_pred=prediction,
                        sensitive_features=part[attribute])
    groups = []
    for group, row in frame.by_group.iterrows():
        subset = part[part[attribute] == group]
        warning = []
        if row.positive == 0: warning.append('TPR/FNR不可估计：没有正类')
        if row.negative == 0: warning.append('FPR不可估计：没有负类')
        limits = PLAN['small_support_warning']
        if subset.subject.nunique() < limits['subjects'] or min(row.positive, row.negative) < limits['positive_or_negative_records']:
            warning.append('支持度较小，指标不稳定')
        groups.append({'group': str(group), 'subjects': int(subset.subject.nunique()),
                       **row.to_dict(), 'warnings': warning})
    complete = all(g['positive'] > 0 and g['negative'] > 0 for g in groups)
    differences = frame.difference(method='between_groups').to_dict()
    eo = float(equalized_odds_difference(part.label, prediction, sensitive_features=part[attribute])) if complete else None
    if complete:
        assert np.isclose(eo, max(differences['tpr'], differences['fpr']))
    return clean({'overall': {**frame.overall.to_dict(), 'subjects': int(part.subject.nunique())},
                  'groups': groups, 'difference': differences, 'eo_difference': eo,
                  'dp_difference': float(demographic_parity_difference(part.label, prediction, sensitive_features=part[attribute])),
                  'eo_estimable': complete})

def summary(part, prediction):
    a = audit(part, prediction, 'sex')
    return {**a['overall'], 'eo_difference': a['eo_difference'], 'dp_difference': a['dp_difference']}

def verify_source():
    for name, expected in PLAN['source_sha256'].items():
        if sha(SOURCE / name) != expected:
            raise ValueError(f'Frozen source changed: {name}; create a new version.')
    data = pd.read_csv(SOURCE / 'data/shared-sleep-data.csv')
    lock = json.loads((SOURCE / 'data/frozen-splits.json').read_text())['subjects']
    assert data.groupby('subject').split.nunique().eq(1).all()
    for split, ids in lock.items():
        assert set(data.loc[data.split == split, 'subject']) == set(ids)
    assert data.label.isin([0, 1]).all() and data.sex.isin([1, 2]).all()
    assert np.array_equal(data.label, (data.target_sleep_minutes < 420).astype(int))
    ages = np.select([data.age < 30, data.age < 45, data.age < 60], ['18-29', '30-44', '45-59'], default='60+')
    assert data.age.ge(18).all() and np.array_equal(data.age_group, ages)
    assert data.groupby('subject')[['sex', 'age_group']].nunique().eq(1).all().all()
    assert not data.duplicated(['subject', 'input_day']).any()
    assert np.isfinite(data[FEATURES].to_numpy()).all()
    data['intersection'] = data.sex.map({1: 'Male', 2: 'Female'}) + ' / ' + data.age_group
    return data

def from_counts(counts):
    tn, fp, fn, tp = np.moveaxis(np.asarray(counts, dtype=float), -1, 0)
    with np.errstate(divide='ignore', invalid='ignore'):
        tpr, fpr = tp / (tp + fn), fp / (fp + tn)
        ba = (tpr + 1 - fpr) / 2
        f1p, f1n = 2 * tp / (2 * tp + fp + fn), 2 * tn / (2 * tn + fp + fn)
        return {'accuracy': (tn + tp) / (tn + fp + fn + tp), 'balanced_accuracy': ba,
                'f1_macro': (np.nan_to_num(f1p) + np.nan_to_num(f1n)) / 2,
                'tpr': tpr, 'fnr': 1 - tpr, 'fpr': fpr}

def bootstrap(part, predictions):
    """Paired stratified participant cluster bootstrap; predictions stay fixed."""
    people = part[['subject', 'sex', 'age_group', 'intersection']].drop_duplicates().sort_values('subject').reset_index(drop=True)
    index = people.set_index('subject').index.get_indexer(part.subject)
    matrices = {}
    for name, pred in predictions.items():
        counts = np.zeros((len(people), 4), dtype=int)
        cell = part.label.to_numpy() * 2 + pred  # TN, FP, FN, TP
        np.add.at(counts, (index, cell), 1)
        matrices[name] = counts
    strata = [np.asarray(ids) for ids in people.groupby('intersection').indices.values()]
    rng = np.random.default_rng(PLAN['bootstrap']['seed'])
    store = {name: {'overall': [], **{a: [] for a in PLAN['audit_attributes']}} for name in predictions}
    labels = {a: sorted(people[a].unique(), key=str) for a in PLAN['audit_attributes']}
    for _ in range(PLAN['bootstrap']['replicates']):
        sampled = np.concatenate([rng.choice(ids, size=len(ids), replace=True) for ids in strata])
        weights = np.bincount(sampled, minlength=len(people))
        for name, matrix in matrices.items():
            weighted = matrix * weights[:, None]
            store[name]['overall'].append(from_counts(weighted.sum(axis=0)))
            for attr in PLAN['audit_attributes']:
                grouped = np.array([weighted[people[attr].to_numpy() == group].sum(axis=0) for group in labels[attr]])
                m = from_counts(grouped)
                eo = max(np.ptp(m['tpr']), np.ptp(m['fpr'])) if np.isfinite(m['tpr']).all() and np.isfinite(m['fpr']).all() else np.nan
                store[name][attr].append({'eo_difference': eo, 'groups': m})
    def interval(values):
        a = np.asarray(values, dtype=float)
        valid = np.isfinite(a)
        return {'interval95': np.quantile(a[valid], [.025, .975]).tolist() if valid.any() else None,
                'valid_replicates': int(valid.sum())}
    result = {'unit': 'participant', 'stratify': 'sex x age', 'replicates': PLAN['bootstrap']['replicates'],
              'paired': True, 'conditional_on_fixed_prediction_draw': True, 'models': {}, 'paired_delta': {}}
    for name in predictions:
        result['models'][name] = {'overall': {key: interval([r[key] for r in store[name]['overall']]) for key in ['accuracy', 'balanced_accuracy', 'f1_macro']}}
        for attr in PLAN['audit_attributes']:
            result['models'][name][attr] = {'eo_difference': interval([r['eo_difference'] for r in store[name][attr]]),
                'groups': {str(group): {key: interval([r['groups'][key][i] for r in store[name][attr]]) for key in ['tpr', 'fnr', 'fpr']}
                           for i, group in enumerate(labels[attr])}}
    for key in ['accuracy', 'balanced_accuracy', 'f1_macro']:
        result['paired_delta'][key] = interval([f[key] - b[key] for f, b in zip(store['mitigated']['overall'], store['baseline']['overall'])])
    for attr in PLAN['audit_attributes']:
        result['paired_delta'][attr + '_eo_difference'] = interval([f['eo_difference'] - b['eo_difference'] for f, b in zip(store['mitigated'][attr], store['baseline'][attr])])
    return clean(result)

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--run-id', default=PLAN['version'])
    parser.add_argument('--verify-only', action='store_true')
    args = parser.parse_args()
    if not args.run_id.replace('-', '').replace('_', '').isalnum(): raise ValueError('Invalid run-id')
    data = verify_source()
    if args.verify_only:
        print('Source hashes, person separation, labels, age/sex and finite features verified.')
        return
    run = ROOT / 'runs' / args.run_id
    if run.exists(): raise FileExistsError('Preserve existing run; use a new --run-id for reproducibility replay.')
    run.mkdir(parents=True)
    write(run / 'frozen-plan.json', PLAN)
    write(run / 'provenance.json', {'at_utc': datetime.now(timezone.utc).isoformat(), 'plan_sha256': sha(ROOT / 'experiment-plan.json'),
          'code_sha256': sha(Path(__file__)), 'source_sha256': PLAN['source_sha256'],
          'versions': {name: module.__version__ for name, module in [('numpy', np), ('pandas', pd), ('sklearn', sklearn), ('scipy', scipy), ('fairlearn', fairlearn), ('joblib', joblib)]}, 'python': platform.python_version()})
    sets = {s: data[data.split == s].reset_index(drop=True) for s in ['train', 'validation', 'test']}
    support = []
    for split, part in sets.items():
        for attr in PLAN['audit_attributes']:
            for group, p in part.groupby(attr):
                support.append({'split': split, 'attribute': attr, 'group': str(group), 'subjects': p.subject.nunique(),
                                'samples': len(p), 'positive': int(p.label.sum()), 'negative': int((p.label == 0).sum()), 'label_positive_rate': p.label.mean()})
    pd.DataFrame(support).to_csv(run / 'group-support.csv', index=False)
    baseline = joblib.load(SOURCE / 'models/random_forest.joblib')
    selection1 = json.loads((SOURCE / 'models/selection.json').read_text())
    threshold = selection1['configurations']['random_forest']['threshold']
    assert threshold == 0.5 and selection1['selected_model'] == 'random_forest'
    train, val = sets['train'], sets['validation']
    base_val = (baseline.predict_proba(val[FEATURES])[:, 1] >= threshold).astype(int)
    base_summary = summary(val, base_val)
    # Remove class balancing so that the oracle follows EG's cost-sensitive weights.
    oracle = clone(baseline).set_params(class_weight=None, n_jobs=-1)
    oracle.fit(train[FEATURES], train.label)
    oracle_val = oracle.predict(val[FEATURES])
    candidates, models = [], {}
    tic = time.perf_counter()
    for bound in PLAN['difference_bounds']:
        start = time.perf_counter()
        print(f'Training EO difference_bound={bound}', flush=True)
        model = ExponentiatedGradient(clone(oracle), EqualizedOdds(difference_bound=bound), eps=PLAN['eps'], max_iter=PLAN['max_iter'])
        model.fit(train[FEATURES], train.label, sensitive_features=train.sex)
        pred = model.predict(val[FEATURES], random_state=PLAN['seed'])
        m = summary(val, pred)
        eligible = all(m[key] >= base_summary[key] - PLAN['performance_loss_budget'] for key in ['balanced_accuracy', 'f1_macro'])
        entry = {'bound': bound, **m, 'eligible': eligible, 'elapsed_seconds': time.perf_counter() - start,
                 'best_gap': model.best_gap_, 'best_iter': model.best_iter_, 'last_iter': model.last_iter_,
                 'oracle_calls': model.n_oracle_calls_, 'weights': model.weights_.to_dict(),
                 'predictor_count': len(model.predictors_)}
        candidates.append(clean(entry)); models[bound] = model
        write(run / 'validation-search.json', {'baseline': base_summary, 'oracle_reference': summary(val, oracle_val), 'candidates': candidates})
        joblib.dump(model, run / f'candidate-{bound:.2f}.joblib')
        print(json.dumps(clean(entry)), flush=True)
    eligible = [m for m in candidates if m['eligible']]
    selected = min(eligible, key=lambda m: (m['eo_difference'], -m['f1_macro'], m['bound'])) if eligible else min(candidates, key=lambda m: (-m['balanced_accuracy'], m['eo_difference'], m['bound']))
    model = models[selected['bound']]
    # This file is written before any fairness test prediction/evaluation.
    write(run / 'selection.json', {'selection_at_utc': datetime.now(timezone.utc).isoformat(), 'bound': selected['bound'],
          'rule': PLAN['selection'], 'performance_budget_passed': bool(eligible),
          'recommended_on_validation': bool(eligible) and selected['eo_difference'] < base_summary['eo_difference'],
          'selected_validation': selected, 'baseline_validation': base_summary})
    joblib.dump(model, run / 'mitigated.joblib')
    results, prediction_tables = {}, []
    test_predictions = None
    for split in ['validation', 'test']:
        part = sets[split]
        preds = {'baseline': (baseline.predict_proba(part[FEATURES])[:, 1] >= threshold).astype(int),
                 'mitigated': model.predict(part[FEATURES], random_state=PLAN['seed']),
                 'oracle_reference': oracle.predict(part[FEATURES])}
        results[split] = {name: {attr: audit(part, pred, attr) for attr in PLAN['audit_attributes']} for name, pred in preds.items()}
        for name, pred in preds.items():
            table = part[['subject', 'split', 'input_day', 'sex', 'age_group', 'intersection', 'label']].copy()
            table['model'] = name; table['prediction'] = pred
            prediction_tables.append(table)
        if split == 'test': test_predictions = preds
    pd.concat(prediction_tables, ignore_index=True).to_csv(run / 'predictions.csv', index=False)
    grouped = []
    for split, models_result in results.items():
        for name, audits in models_result.items():
            for attr, payload in audits.items():
                grouped += [{'split': split, 'model': name, 'attribute': attr, **g, 'warnings': '; '.join(g['warnings'])} for g in payload['groups']]
    pd.DataFrame(grouped).to_csv(run / 'group-metrics.csv', index=False)
    write(run / 'metrics.json', results)
    print('Paired participant bootstrap...', flush=True)
    ci = bootstrap(sets['test'], {name: test_predictions[name] for name in ['baseline', 'mitigated']})
    write(run / 'bootstrap.json', ci)
    sensitivity = []
    for seed in range(PLAN['seed'], PLAN['seed'] + 10):
        pred = model.predict(sets['test'][FEATURES], random_state=seed)
        sensitivity.append({'seed': seed, **summary(sets['test'], pred)})
    write(run / 'randomization-sensitivity.json', sensitivity)
    write(run / 'completed.json', {'elapsed_seconds': time.perf_counter() - tic, 'human_testing_completed': False,
                                  'source_unchanged': all(sha(SOURCE / n) == h for n, h in PLAN['source_sha256'].items())})
    print(json.dumps({'selected_bound': selected['bound'], 'test_baseline': results['test']['baseline']['sex'],
                      'test_mitigated': results['test']['mitigated']['sex'], 'paired_delta': ci['paired_delta']}, ensure_ascii=False, indent=2), flush=True)

if __name__ == '__main__': main()
