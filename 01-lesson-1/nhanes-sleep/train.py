"""Frozen, person-separated NHANES sleep classification experiment."""
from pathlib import Path
import hashlib, json, platform, time
from datetime import datetime, timezone
import numpy as np
import pandas as pd
import pyreadstat, sklearn, joblib
import matplotlib
matplotlib.use('Agg')
import matplotlib.pyplot as plt
from sklearn.model_selection import train_test_split, ParameterGrid
from sklearn.pipeline import make_pipeline
from sklearn.preprocessing import StandardScaler
from sklearn.linear_model import LogisticRegression
from sklearn.ensemble import RandomForestClassifier
from sklearn.metrics import accuracy_score, balanced_accuracy_score, precision_score, recall_score, f1_score, confusion_matrix, brier_score_loss, roc_auc_score

ROOT = Path(__file__).resolve().parent
RAW = ROOT.parent / 'stress-study/data/raw/nhanes-2011-2014-audit'
PLAN = json.loads((ROOT / 'experiment-plan.json').read_text())
FEATURES = PLAN['features']

def write(path, obj):
    path.write_text(json.dumps(obj, indent=2, ensure_ascii=False, allow_nan=False)+'\n')

def sha(path): return hashlib.sha256(path.read_bytes()).hexdigest()

def prepare():
    rows, audit, sources = [], [], []
    for suffix in ['G','H']:
        demo = pyreadstat.read_xport(RAW / f'DEMO_{suffix}.xpt')[0]
        day = pyreadstat.read_xport(RAW / f'PAXDAY_{suffix}.xpt')[0]
        # CDC stores the day index as a character variable in the XPT.
        for col in ['PAXDAYD','PAXDAYWD']:
            day[col]=pd.to_numeric(day[col],errors='raise')
        assert demo.SEQN.is_unique and not day.duplicated(['SEQN','PAXDAYD']).any()
        for name in ['DEMO','PAXDAY']:
            file = RAW / f'{name}_{suffix}.xpt'
            sources.append({'file': file.name, 'sha256': sha(file), 'bytes': file.stat().st_size,
                            'url': f'https://wwwn.cdc.gov/Nchs/Data/Nhanes/Public/{2011 if suffix=="G" else 2013}/DataFiles/{file.name}'})
        day = day.merge(demo[['SEQN','RIAGENDR','RIDAGEYR']], on='SEQN', validate='many_to_one')
        adults = day[day.RIDAGEYR>=18].copy()
        q = PLAN['quality']
        mask = adults.PAXDAYD.between(q['day_min'],q['day_max']) & (adults.PAXVMD>=q['valid_minutes_min']) & (adults.PAXUMD<=q['unknown_minutes_max']) & (adults.PAXNWMD<=q['nonwear_minutes_max']) & adults.PAXSWMD.between(*q['sleep_minutes_range'])
        mask &= adults[['PAXSWMD','PAXDAYWD','PAXDAYD','RIAGENDR','RIDAGEYR']].apply(lambda c: np.isfinite(c)).all(axis=1)
        valid = adults[mask].copy()
        assert valid.RIAGENDR.isin([1,2]).all() and valid.PAXDAYWD.isin(range(1,8)).all()
        audit.append({'cycle':suffix,'sensor_people':int(day.SEQN.nunique()),'sensor_rows':len(day),'adult_people':int(adults.SEQN.nunique()),'adult_rows':len(adults),'qc_days':len(valid),'qc_people':int(valid.SEQN.nunique()),'excluded_adult_days':int((~mask).sum())})
        for subject, group in valid.groupby('SEQN'):
            records = {int(r.PAXDAYD): r for r in group.itertuples()}
            for d, current in sorted(records.items()):
                if d+1 not in records: continue
                target = records[d+1]
                assert int(target.PAXDAYWD)==int(current.PAXDAYWD)%7+1
                history=[]
                for back in range(3):
                    if d-back not in records: break
                    history.append(float(records[d-back].PAXSWMD))
                history.reverse()
                weekday=int(current.PAXDAYWD)%7+1
                rows.append({'subject':int(subject),'cycle':suffix,'input_day':d,'target_day':d+1,
                    'sex':int(current.RIAGENDR),'age':int(current.RIDAGEYR),
                    'age_group': '18-29' if current.RIDAGEYR<30 else '30-44' if current.RIDAGEYR<45 else '45-59' if current.RIDAGEYR<60 else '60+',
                    'sleep_last':history[-1],'sleep_mean':float(np.mean(history)),'sleep_std':float(np.std(history)),
                    'sleep_delta':history[-1]-history[-2] if len(history)>1 else 0.,'history_days':len(history),
                    'next_day_sin':float(np.sin(2*np.pi*(weekday-1)/7)),'next_day_cos':float(np.cos(2*np.pi*(weekday-1)/7)),
                    'next_weekday':weekday,'history_minutes':json.dumps(history),'target_sleep_minutes':float(target.PAXSWMD),
                    'label':int(target.PAXSWMD<420)})
    frame=pd.DataFrame(rows)
    assert not frame.duplicated(['subject','input_day']).any()
    assert frame[FEATURES].notna().all().all() and np.isfinite(frame[FEATURES]).all().all()
    persons=frame[['subject','sex']].drop_duplicates().sort_values('subject')
    assert persons.subject.is_unique
    train, rest=train_test_split(persons,test_size=.4,stratify=persons.sex,random_state=PLAN['split']['seed'])
    val, test=train_test_split(rest,test_size=.5,stratify=rest.sex,random_state=PLAN['split']['seed'])
    split_ids={name:sorted(part.subject.astype(int).tolist()) for name,part in [('train',train),('validation',val),('test',test)]}
    lock={'sources':sources,'plan_sha256':sha(ROOT/'experiment-plan.json'),'subjects':split_ids}
    path=ROOT/'data/frozen-splits.json'
    if path.exists() and json.loads(path.read_text())!=lock: raise ValueError('Frozen data/plan changed; create a new version instead.')
    write(path,lock)
    for name,ids in split_ids.items(): frame.loc[frame.subject.isin(ids),'split']=name
    frame.to_csv(ROOT/'data/shared-sleep-data.csv',index=False)
    write(ROOT/'data/source-manifest.json',{'sources':sources,'audit':audit,'label':PLAN['target']})
    support=[]
    for split, part in frame.groupby('split'):
        for attr in ['sex','age_group']:
            for group,p in part.groupby(attr):
                support.append({'split':split,'attribute':attr,'group':str(group),'subjects':int(p.subject.nunique()),'samples':len(p),'positive':int(p.label.sum()),'negative':int((p.label==0).sum()),'positive_rate':float(p.label.mean())})
    pd.DataFrame(support).to_csv(ROOT/'report/group-support.csv',index=False)
    return frame, audit, split_ids

def metrics(y,p,score=None):
    m={'accuracy':float(accuracy_score(y,p)),'balanced_accuracy':float(balanced_accuracy_score(y,p)),
       'precision_positive':float(precision_score(y,p,zero_division=0)),'recall_positive':float(recall_score(y,p,zero_division=0)),
       'f1_positive':float(f1_score(y,p,zero_division=0)),'f1_macro':float(f1_score(y,p,average='macro',zero_division=0)),
       'confusion_matrix':confusion_matrix(y,p,labels=[0,1]).tolist()}
    if score is not None: m.update(brier=float(brier_score_loss(y,score)),roc_auc=float(roc_auc_score(y,score)))
    return m

def export(model,name,threshold):
    document={'schema_version':1,'name':name,'feature_names':FEATURES,'threshold':float(threshold),
              'label':PLAN['target'],'score_is_calibrated':False,'history_max_days':3,'source_device':'ActiGraph GT3X+',
              'app_input':'manual calendar-day total sleep history; not live HealthKit validation'}
    if name=='logistic_regression':
        scaler,clf=model.steps[0][1],model.steps[1][1]
        document.update(kind='logistic',mean=scaler.mean_.tolist(),scale=scaler.scale_.tolist(),coefficients=clf.coef_[0].tolist(),intercept=float(clf.intercept_[0]))
    else:
        trees=[]
        for e in model.estimators_:
            t=e.tree_; p=t.value[:,0,1]/t.value[:,0].sum(axis=1)
            trees.append({'left':t.children_left.tolist(),'right':t.children_right.tolist(),'feature':t.feature.tolist(),'threshold':t.threshold.tolist(),'positive_probability':p.tolist()})
        document.update(kind='forest',trees=trees)
    return document

def bootstrap(part,p,persistence):
    grouped=pd.DataFrame({'subject':part.subject.to_numpy(),'correct':(part.label.to_numpy()==p).astype(int),'baseline_correct':(part.label.to_numpy()==persistence).astype(int)}).groupby('subject').agg(n=('correct','size'),correct=('correct','sum'),baseline=('baseline_correct','sum'))
    a=grouped.to_numpy(); rng=np.random.default_rng(PLAN['bootstrap']['seed']); values=[]
    for _ in range(PLAN['bootstrap']['replicates']):
        n,correct,base=a[rng.integers(0,len(a),len(a))].sum(axis=0)
        values.append([correct/n,(correct-base)/n])
    values=np.array(values)
    return {'accuracy_interval95':np.quantile(values[:,0],[.025,.975]).tolist(),'paired_accuracy_gain_over_persistence_interval95':np.quantile(values[:,1],[.025,.975]).tolist(),'unit':'participant','replicates':len(values)}

def main():
    for folder in ['data','models','report','figures','prototype','watch-app/Resources']: (ROOT/folder).mkdir(parents=True,exist_ok=True)
    tic=time.perf_counter(); frame,audit,ids=prepare()
    sets={name:frame[frame.split==name].copy() for name in ids}
    train,val=sets['train'],sets['validation']; models={}; search=[]; bestkeys={}; thresholds={}
    for family in ['logistic_regression','random_forest']:
        fixed=PLAN['models'][family]
        grid={k:v for k,v in fixed.items() if isinstance(v,list)}
        constants={k:v for k,v in fixed.items() if not isinstance(v,list)}
        for config in ParameterGrid(grid):
            clf=LogisticRegression(**constants,**config) if family=='logistic_regression' else RandomForestClassifier(**constants,**config,n_jobs=-1)
            model=make_pipeline(StandardScaler(),clf) if family=='logistic_regression' else clf
            model.fit(train[FEATURES],train.label)
            score=model.predict_proba(val[FEATURES])[:,1]
            for threshold in PLAN['threshold_grid']:
                m=metrics(val.label,score>=threshold,score)
                entry={'family':family,'config':config,'threshold':threshold,**m}; search.append(entry)
                key=(m['f1_macro'],m['balanced_accuracy'],-abs(threshold-.5))
                if family not in bestkeys or key>bestkeys[family]:
                    bestkeys[family]=key; models[family]=model; thresholds[family]=threshold
    selected=max(models,key=lambda n:(bestkeys[n][0],bestkeys[n][1],n=='logistic_regression'))
    # Frozen selection and config are written BEFORE computing any test prediction.
    chosen={name:next(e for e in search if e['family']==name and (e['f1_macro'],e['balanced_accuracy'],-abs(e['threshold']-.5))==bestkeys[name]) for name in models}
    write(ROOT/'models/selection.json',{'selected_model':selected,'basis':PLAN['selection'],'configurations':chosen})
    write(ROOT/'report/validation-search.json',search)
    majority=int(train.label.mean()>=.5); results={}; predictions=[]
    for name in [*models,'training_majority','last_day_label_persistence']:
        results[name]={}
        for split in ['validation','test']:
            p=sets[split].copy()
            if name in models:
                score=models[name].predict_proba(p[FEATURES])[:,1]; pred=(score>=thresholds[name]).astype(int)
            else:
                pred=np.full(len(p),majority) if name=='training_majority' else (p.sleep_last.to_numpy()<420).astype(int);score=pred.astype(float)
            results[name][split]=metrics(p.label,pred,score)
            p['prediction']=pred;p['score']=score;p['model']=name;predictions.append(p)
    allp=pd.concat(predictions,ignore_index=True);allp.to_csv(ROOT/'report/predictions.csv',index=False)
    for name,model in models.items(): joblib.dump(model,ROOT/f'models/{name}.joblib')
    doc=export(models[selected],selected,thresholds[selected])
    for file in ['models/model.json','prototype/model.json','watch-app/Resources/model.json']: write(ROOT/file,doc)
    valid=allp[(allp.model==selected)&(allp.split=='validation')]
    demos=pd.concat([valid[valid.label==label].sort_values(['subject','input_day']).head(3) for label in [0,1]])
    examples=[{'title':f'公开验证记录 {i+1}','history':json.loads(r.history_minutes),'weekday':int(r.next_weekday),'label':int(r.label),'score':float(r.score)} for i,r in enumerate(demos.itertuples())]
    for file in ['prototype/samples.json','watch-app/Resources/samples.json']: write(ROOT/file,examples)
    write(ROOT/'report/runtime-parity-input.json',[{'values':[float(r[f]) for f in FEATURES],'score':float(r.score)} for _,r in valid.iterrows()])
    test=allp[(allp.model==selected)&(allp.split=='test')].copy()
    errors=test[test.label!=test.prediction].copy();errors['error_type']=np.where(errors.label==1,'false_negative','false_positive');errors.to_csv(ROOT/'report/error-cases.csv',index=False)
    group_metrics=[]
    for attr in ['sex','age_group']:
        for group,p in test.groupby(attr):
            group_metrics.append({'attribute':attr,'group':str(group),'people':int(p.subject.nunique()),'samples':len(p),**metrics(p.label,p.prediction,p.score)})
    write(ROOT/'report/initial-group-metrics.json',group_metrics)
    bins=[]
    for interval,p in test.groupby(pd.cut(test.score,np.linspace(0,1,6),include_lowest=True),observed=True):
        bins.append({'bin':str(interval),'samples':len(p),'score_mean':float(p.score.mean()),'observed_positive':float(p.label.mean())})
    payload={'at_utc':datetime.now(timezone.utc).isoformat(),'selected_model':selected,'models':results,
        'subjects':int(frame.subject.nunique()),'samples':len(frame),'positive_samples':int(frame.label.sum()),'source_audit':audit,
        'splits':{name:{'people':len(people),'samples':len(sets[name])} for name,people in ids.items()},
        'test_participant_mean_accuracy':float((test.label==test.prediction).groupby(test.subject).mean().mean()),
        'bootstrap':bootstrap(test,test.prediction.to_numpy(),(test.sleep_last.to_numpy()<420).astype(int)),
        'score_reliability_bins':bins,'elapsed_seconds':time.perf_counter()-tic,
        'versions':{'python':platform.python_version(),'sklearn':sklearn.__version__,'pandas':pd.__version__,'numpy':np.__version__,'pyreadstat':pyreadstat.__version__},
        'device_transfer_validated':False,'human_testing_completed':False}
    write(ROOT/'report/metrics.json',payload)
    fig,axes=plt.subplots(1,3,figsize=(13,4));cm=np.array(results[selected]['test']['confusion_matrix'])
    axes[0].imshow(cm,cmap='Blues')
    for i in range(2):
        for j in range(2):axes[0].text(j,i,str(cm[i,j]),ha='center',va='center',fontsize=18)
    axes[0].set(xticks=[0,1],yticks=[0,1],xticklabels=['>=7h','<7h'],yticklabels=['>=7h','<7h'],xlabel='Prediction',ylabel='Algorithm label',title='Held-out people')
    names=list(results);x=np.arange(len(names))
    axes[1].bar(x-.18,[results[n]['validation']['f1_macro'] for n in names],width=.36,label='Validation')
    axes[1].bar(x+.18,[results[n]['test']['f1_macro'] for n in names],width=.36,label='Test')
    axes[1].set(xticks=x,xticklabels=['Logistic','Forest','Majority','Persistence'],ylim=(0,1),ylabel='Macro F1',title='Frozen model comparison');axes[1].tick_params(axis='x',rotation=25);axes[1].legend()
    axes[2].plot([0,1],[0,1],'--',color='gray');axes[2].plot([b['score_mean'] for b in bins],[b['observed_positive'] for b in bins],'o-')
    axes[2].set(xlim=(0,1),ylim=(0,1),xlabel='Uncalibrated score',ylabel='Observed <7h fraction',title='Reliability on test')
    fig.tight_layout();fig.savefig(ROOT/'figures/model-results.png',dpi=160);fig.savefig(ROOT/'figures/model-results.pdf');plt.close(fig)
    print(json.dumps({'selected':selected,'people':payload['subjects'],'samples':len(frame),'splits':payload['splits'],'models':results,'bootstrap':payload['bootstrap'],'seconds':payload['elapsed_seconds']},indent=2))

if __name__=='__main__': main()
