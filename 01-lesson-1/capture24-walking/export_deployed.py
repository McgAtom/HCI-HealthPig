"""Recreate the explicitly recorded deployment; never selects or tunes a model."""
import json
from pathlib import Path
import joblib
import numpy as np
import pandas as pd
from train import export_model, metrics

ROOT=Path(__file__).resolve().parent
def write(path,value): path.write_text(json.dumps(value,ensure_ascii=False,indent=2))
def main():
    decision=json.loads((ROOT/'deployment-decision.json').read_text())
    selection=json.loads((ROOT/'models/selection.json').read_text())
    # The current recorded deployment is the original frozen LR candidate.
    family='logistic_regression'
    fitted=joblib.load(ROOT/'models/logistic_regression.joblib')
    threshold=selection['families'][family]['threshold']
    assert threshold == 0.5
    model=export_model(family,fitted,threshold)
    write(ROOT/'models/deployed-model.json',model)
    write(ROOT.parent/'watch-pig-live/Resources/motion-model.json',model)
    predictions=pd.read_csv(ROOT/'report/test-predictions.csv')
    y=predictions.label.to_numpy();p=predictions[family+'_score'].to_numpy()
    counts=predictions.assign(correct=(y==(p>=threshold))).groupby('pid').correct.agg(['sum','count'])
    rng=np.random.default_rng(20261009);rep=[]
    for _ in range(300):
        sample=counts.iloc[rng.integers(0,len(counts),len(counts))]
        rep.append(float(sample['sum'].sum()/sample['count'].sum()))
    original=json.loads((ROOT/'report/metrics.json').read_text())
    write(ROOT/'report/deployed-metrics.json',{'deployed':family,'threshold':threshold,'metrics':metrics(y,p,threshold),
        'majority_metrics':original['test']['training_majority'],'accuracy_cluster_bootstrap_95ci':np.quantile(rep,[.025,.975]).tolist(),
        'deployment_decision_after_test_seen':True,'parameters_frozen_before_test':True,'watch_accuracy_measured':False})
    groups=[]
    for attribute in ['sex','age']:
        for group,g in predictions.groupby(attribute):
            groups.append({'attribute':attribute,'group':group,'people':int(g.pid.nunique()),'samples':len(g),
                'positive':int(g.label.sum()),'negative':int((g.label==0).sum()),'metrics':metrics(g.label.to_numpy(),g[family+'_score'].to_numpy(),threshold)})
    write(ROOT/'report/deployed-group-metrics.json',groups)
    parity=json.loads((ROOT/'report/runtime-parity-input.json').read_text())
    for row in parity:
        row['score']=float(fitted.predict_proba(np.array(row['features']).reshape(1,-1))[0,1])
    write(ROOT/'report/deployed-runtime-parity-input.json',parity)
    print('Exported the previously frozen LR deployment; no training or selection performed.')

if __name__=='__main__':main()
