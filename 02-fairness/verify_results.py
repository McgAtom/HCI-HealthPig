"""Independent checks against saved binary predictions and source baseline."""
from pathlib import Path
import json
import numpy as np
import pandas as pd
import joblib
from sklearn.metrics import confusion_matrix
from run_experiment import ROOT, SOURCE, FEATURES, PLAN, verify_source, from_counts, rate, audit

def main():
    data = verify_source()
    run = ROOT / 'runs/fairness-v1'
    predictions = pd.read_csv(run / 'predictions.csv')
    metrics = json.loads((run / 'metrics.json').read_text())
    baseline = joblib.load(SOURCE / 'models/random_forest.joblib')
    mitigated = joblib.load(run / 'mitigated.joblib')
    comparisons = 0
    for split in ['validation', 'test']:
        part = data[data.split == split].reset_index(drop=True)
        replay = {'baseline': (baseline.predict_proba(part[FEATURES])[:,1] >= .5).astype(int),
                  'mitigated': mitigated.predict(part[FEATURES], random_state=PLAN['seed'])}
        for name in ['baseline','mitigated','oracle_reference']:
            p = predictions[(predictions.split == split) & (predictions.model == name)].reset_index(drop=True)
            assert len(p) == len(part)
            assert np.array_equal(p[['subject','input_day','label']], part[['subject','input_day','label']])
            if name in replay: assert np.array_equal(p.prediction, replay[name])
            counts = confusion_matrix(p.label, p.prediction, labels=[0,1]).ravel()
            independent = from_counts(counts)
            for key in independent:
                assert np.isclose(independent[key], metrics[split][name]['sex']['overall'][key])
            for attr in PLAN['audit_attributes']:
                payload = metrics[split][name][attr]
                assert sum(g['samples'] for g in payload['groups']) == len(part)
                assert sum(g['subjects'] for g in payload['groups']) == part.subject.nunique()
                assert np.isclose(payload['eo_difference'], max(np.ptp([g['tpr'] for g in payload['groups']]), np.ptp([g['fpr'] for g in payload['groups']])))
                for group in payload['groups']:
                    mask = part[attr].astype(str) == group['group']
                    cm = confusion_matrix(part.loc[mask,'label'],p.loc[mask,'prediction'],labels=[0,1]).ravel()
                    for key, value in from_counts(cm).items():
                        assert np.isclose(value, group[key])
                        comparisons += 1
    old = json.loads((SOURCE / 'report/metrics.json').read_text())['models']['random_forest']['test']
    for key in ['accuracy','balanced_accuracy','f1_positive','f1_macro']:
        assert np.isclose(old[key],metrics['test']['baseline']['sex']['overall'][key])
    # Missing classes must never be rendered as perfect zero error rates.
    assert np.isnan(rate([0,0],[0,1],label=1,prediction=1))
    assert np.isnan(rate([1,1],[0,1],label=0,prediction=1))
    sparse = pd.DataFrame({'subject':[1,2,3,4],'label':[0,0,1,1],'sex':[1,1,2,2]})
    missing = audit(sparse,np.array([0,1,0,1]),'sex')
    assert missing['eo_difference'] is None and not missing['eo_estimable']
    assert missing['groups'][0]['tpr'] is None and missing['groups'][1]['fpr'] is None
    ci = json.loads((run / 'bootstrap.json').read_text())
    assert ci['paired'] and ci['unit']=='participant'
    assert all(v['valid_replicates'] == 500 for v in ci['paired_delta'].values())
    candidates = json.loads((run / 'validation-search.json').read_text())['candidates']
    expected = min([c for c in candidates if c['eligible']],key=lambda c:(c['eo_difference'],-c['f1_macro'],c['bound']))['bound']
    selected = json.loads((run / 'selection.json').read_text())
    assert expected == selected['bound']
    assert (run / 'selection.json').stat().st_mtime_ns < (run / 'metrics.json').stat().st_mtime_ns
    assert json.loads((run / 'completed.json').read_text())['source_unchanged']
    print(f'PASS: {comparisons} independent group metric comparisons; baseline parity; prediction replay; missing-class handling; paired cluster CI; validation selection; source hashes.')

if __name__ == '__main__': main()
