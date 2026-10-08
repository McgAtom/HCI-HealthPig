from pathlib import Path
from itertools import product
import json, hashlib, time
import numpy as np
import pandas as pd
import joblib
import matplotlib
matplotlib.use('Agg')
import matplotlib.pyplot as plt
from sklearn.linear_model import LogisticRegression
from sklearn.ensemble import RandomForestClassifier
from sklearn.preprocessing import StandardScaler
from sklearn.pipeline import make_pipeline
from sklearn.metrics import accuracy_score, balanced_accuracy_score, f1_score, precision_score, recall_score, confusion_matrix, roc_auc_score, brier_score_loss
from features import NAMES

ROOT=Path(__file__).resolve().parent
def write(path,obj):path.write_text(json.dumps(obj,indent=2,ensure_ascii=False))
def metrics(y,p,t):
    pred=(p>=t).astype(int)
    tn,fp,fn,tp=confusion_matrix(y,pred,labels=[0,1]).ravel()
    return {'accuracy':float(accuracy_score(y,pred)), 'balanced_accuracy':float(balanced_accuracy_score(y,pred)),
        'precision':float(precision_score(y,pred,zero_division=0)), 'recall':float(recall_score(y,pred,zero_division=0)),
        'f1_positive':float(f1_score(y,pred,zero_division=0)), 'macro_f1':float(f1_score(y,pred,average='macro',zero_division=0)),
        'confusion_matrix':[[int(tn),int(fp)],[int(fn),int(tp)]], 'fpr':float(fp/(fp+tn)) if fp+tn else None,
        'fnr':float(fn/(fn+tp)) if fn+tp else None, 'predicted_positive_rate':float(pred.mean()),
        'roc_auc':float(roc_auc_score(y,p)) if len(np.unique(y))==2 else None,'brier':float(brier_score_loss(y,p))}

def rank(m,t,family):return (m['balanced_accuracy'],m['macro_f1'],m['accuracy'],-abs(t-.5),family=='logistic_regression')

def export_model(name,model,threshold):
    out={'name':name,'threshold':threshold,'features':NAMES,'target':'walking=1 vs sit-stand=0; other activities out of scope','source':'CAPTURE-24','units':'g','sample_hz':20,'window_samples':200}
    if name=='logistic_regression':
        scaler,lr=model.steps[0][1],model.steps[1][1]
        out.update(kind='logistic',mean=scaler.mean_.tolist(),scale=scaler.scale_.tolist(),coefficients=lr.coef_[0].tolist(),intercept=float(lr.intercept_[0]))
    else:
        out.update(kind='forest',trees=[])
        for tree in model.estimators_:
            q=tree.tree_;probs=q.value[:,0,:];pos=probs[:,1]/probs.sum(axis=1)
            out['trees'].append({'left':q.children_left.tolist(),'right':q.children_right.tolist(),'feature':q.feature.tolist(),'threshold':q.threshold.tolist(),'positive_probability':pos.tolist()})
    return out

def main():
    global ROOT
    import argparse
    parser = argparse.ArgumentParser(description='Reproduce the frozen experiment in a fresh output directory.')
    parser.add_argument('--output-dir',type=Path)
    args=parser.parse_args()
    source=ROOT
    if args.output_dir:
        ROOT=args.output_dir.resolve()
        ROOT.mkdir(parents=True,exist_ok=False)
        (ROOT/'data').symlink_to(source/'data',target_is_directory=True)
        (ROOT/'experiment-plan.json').write_bytes((source/'experiment-plan.json').read_bytes())
    elif (ROOT/'report/metrics.json').exists():
        parser.error('Historical results already exist. Use --output-dir with a new directory to preserve them.')
    for directory in ['models','report','figures']:(ROOT/directory).mkdir(exist_ok=True)
    started=time.monotonic()
    plan=json.loads((ROOT/'experiment-plan.json').read_text());frozen=json.loads((ROOT/'data/frozen-splits.json').read_text())
    assert hashlib.sha256((ROOT/'experiment-plan.json').read_bytes()).hexdigest()==frozen['plan_sha256']
    data=pd.read_csv(ROOT/'data/shared-activity-data.csv')
    assert np.isfinite(data[NAMES].to_numpy()).all()
    for split in ['train','validation','test']:
        assert set(data[data.split==split].pid).issubset(set(frozen[split]))
    assert all(not set(frozen[a])&set(frozen[b]) for a,b in [('train','validation'),('train','test'),('validation','test')])
    tr=data[data.split=='train'];va=data[data.split=='validation'];te=data[data.split=='test']
    candidates=[]
    for c in plan['models']['logistic_regression']['C']:
        candidates.append(('logistic_regression',{'C':c},make_pipeline(StandardScaler(),LogisticRegression(C=c,class_weight='balanced',max_iter=2000,random_state=20261009))))
    rf=plan['models']['random_forest']
    for depth,leaf in product(rf['max_depth'],rf['min_samples_leaf']):
        candidates.append(('random_forest',{'max_depth':depth,'min_samples_leaf':leaf},RandomForestClassifier(n_estimators=120,max_depth=depth,min_samples_leaf=leaf,class_weight='balanced',random_state=20261009,n_jobs=4)))
    search=[];best={}
    for family,config,model in candidates:
        model.fit(tr[NAMES].to_numpy(),tr.label)
        p=model.predict_proba(va[NAMES].to_numpy())[:,1]
        for threshold in plan['threshold_grid']:
            m=metrics(va.label.to_numpy(),p,threshold)
            result={'family':family,'config':config,'threshold':threshold,'validation':m};search.append(result)
            key=rank(m,threshold,family)
            if family not in best or key>best[family]['rank']:best[family]={'rank':key,'result':result,'model':model}
        print(family,config,'validation best',best[family]['result']['validation']['balanced_accuracy'],flush=True)
    selected=max(best,key=lambda f:best[f]['rank'])
    selection={'selected':selected,'families':{f:b['result'] for f,b in best.items()},'chosen_before_test':True,'plan_sha256':frozen['plan_sha256']}
    # This artifact is written before any test-set prediction or metric.
    write(ROOT/'models/selection.json',selection);write(ROOT/'report/validation-search.json',search)
    for family,b in best.items():joblib.dump(b['model'],ROOT/'models'/f'{family}.joblib',compress=3)
    chosen=best[selected];model=export_model(selected,chosen['model'],chosen['result']['threshold'])
    write(ROOT/'models/model.json',model)
    # Deployment is a separately recorded decision; reproducing an experiment
    # must not silently replace the model in the current Watch app.
    output={'source':'CAPTURE-24','task':plan['target'],'selected':selected,'test_previously_seen':False,
            'splits':{s:{'people':int(d.pid.nunique()),'samples':len(d),'positive':int(d.label.sum()),'negative':int((d.label==0).sum())} for s,d in [('train',tr),('validation',va),('test',te)]},'test':{},'validation':{f:b['result']['validation'] for f,b in best.items()}}
    predictions=te[['pid','timestamp','sex','age','label']].copy()
    for family,b in best.items():
        p=b['model'].predict_proba(te[NAMES].to_numpy())[:,1];t=b['result']['threshold']
        output['test'][family]=metrics(te.label.to_numpy(),p,t)
        predictions[family+'_score']=p;predictions[family+'_prediction']=(p>=t).astype(int)
    majority=int(tr.label.mean()>=.5)
    output['test']['training_majority']=metrics(te.label.to_numpy(),np.full(len(te),majority),.5)
    selected_pred=predictions[selected+'_prediction'].to_numpy();y=te.label.to_numpy()
    # Participant-cluster Bootstrap, preserving within-person dependence.
    counts=predictions.assign(correct=(y==selected_pred)).groupby('pid').correct.agg(['sum','count'])
    rng=np.random.default_rng(20261009);rep=[]
    for _ in range(300):
        sampled=counts.iloc[rng.integers(0,len(counts),len(counts))];rep.append(float(sampled['sum'].sum()/sampled['count'].sum()))
    output['accuracy_cluster_bootstrap_95ci']=np.quantile(rep,[.025,.975]).tolist()
    output['meets_accuracy_85']=output['test'][selected]['accuracy']>=.85
    output['training_seconds']=time.monotonic()-started
    support=[];group_results=[]
    for split,d in [('train',tr),('validation',va),('test',te)]:
        for attribute in ['sex','age']:
            for group,g in d.groupby(attribute):
                support.append({'split':split,'attribute':attribute,'group':group,'people':int(g.pid.nunique()),'samples':len(g),'positive':int(g.label.sum()),'negative':int((g.label==0).sum())})
    for attribute in ['sex','age']:
        for group,g in predictions.groupby(attribute):
            group_results.append({'attribute':attribute,'group':group,'people':int(g.pid.nunique()),'samples':len(g),'metrics':metrics(g.label.to_numpy(),g[selected+'_score'].to_numpy(),chosen['result']['threshold'])})
    pd.DataFrame(support).to_csv(ROOT/'report/group-support.csv',index=False)
    write(ROOT/'report/initial-group-metrics.json',group_results)
    predictions.to_csv(ROOT/'report/test-predictions.csv',index=False)
    predictions[predictions.label!=predictions[selected+'_prediction']].groupby('label').head(5).to_csv(ROOT/'report/error-cases.csv',index=False)
    write(ROOT/'report/metrics.json',output)
    # Raw validation windows and scores for real Swift numerical checks only.
    parity=[]
    for pid in frozen['validation']:
        f=ROOT/'data/parity-raw'/f'{pid}.npz'
        if not f.exists():continue
        windows=np.load(f)
        for x,features in zip(windows['xyz'],windows['features']):
            parity.append({'xyz':x.tolist(),'features':features.tolist(),'score':float(chosen['model'].predict_proba(features.reshape(1,-1))[0,1])})
    write(ROOT/'report/runtime-parity-input.json',parity)
    (ROOT/'figures').mkdir(exist_ok=True)
    fig,axs=plt.subplots(1,2,figsize=(10,4))
    names=list(output['test']);axs[0].bar(range(len(names)),[output['test'][n]['accuracy'] for n in names],color=['#9370aa','#a55578','#aaa'])
    axs[0].set_xticks(range(len(names)),['Logistic','Forest','Majority']);axs[0].set_ylim(0,1);axs[0].set_ylabel('Test accuracy');axs[0].axhline(.85,color='black',linestyle='--',label='85% target');axs[0].legend()
    cm=np.array(output['test'][selected]['confusion_matrix']);axs[1].imshow(cm,cmap='Purples')
    for i,j in product(range(2),repeat=2):axs[1].text(j,i,str(cm[i,j]),ha='center',va='center',color='white' if cm[i,j]>cm.max()/2 else 'black')
    axs[1].set_xticks([0,1],['Sit/stand','Walking']);axs[1].set_yticks([0,1],['Sit/stand','Walking']);axs[1].set_xlabel('Predicted');axs[1].set_ylabel('Actual');axs[1].set_title(selected)
    fig.suptitle('CAPTURE-24 · held-out participants · guided binary activity task');fig.tight_layout()
    fig.savefig(ROOT/'figures/model-results.png',dpi=180);fig.savefig(ROOT/'figures/model-results.pdf');plt.close(fig)
    print(json.dumps(output,indent=2),flush=True)

if __name__=='__main__':main()
