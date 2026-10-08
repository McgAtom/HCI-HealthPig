"""Chunked processing of the full archive; no label-selective temporal sampling."""
from pathlib import Path
import hashlib, json, zipfile, gzip, time, io
from concurrent.futures import ProcessPoolExecutor, as_completed
import numpy as np
import pandas as pd
from features import NAMES, extract_batch

ROOT=Path(__file__).resolve().parent
ARCHIVE=ROOT.parent/'stress-study/data/raw/capture24/capture24.zip'
DOC=ROOT.parent/'stress-study/data/source-docs/capture24'

def worker(pid):
    start=time.monotonic()
    mapping=pd.read_csv(DOC/'annotation-label-dictionary.csv').set_index('annotation')['label:Willetts2018'].map({'walking':1,'sit-stand':0}).to_dict()
    rows=[]; raw_rows=0; candidates=0; rejected=0; retained=0; remaining=None; index=0
    with zipfile.ZipFile(ARCHIVE) as archive:
        member=archive.getinfo(f'capture24/{pid}.csv.gz')
        with archive.open(member) as source, gzip.open(source,'rb') as zipped:
            for chunk in pd.read_csv(zipped,chunksize=600000,low_memory=False,dtype={'x':'float32','y':'float32','z':'float32','annotation':'object'}):
                raw_rows += len(chunk)
                if remaining is not None: chunk=pd.concat([remaining,chunk],ignore_index=True)
                n=len(chunk)//1000
                remaining=chunk.iloc[n*1000:].copy()
                if n==0: continue
                selected=np.flatnonzero((np.arange(index,index+n)%6)==0); index+=n; candidates+=len(selected)
                xyz=chunk[['x','y','z']].iloc[:n*1000].to_numpy().reshape(n,1000,3)[selected]
                annot=pd.to_numeric(chunk.annotation.map(mapping),errors='coerce').to_numpy(dtype=float)[:n*1000].reshape(n,1000)[selected]
                c0=(annot==0).sum(axis=1); c1=(annot==1).sum(axis=1)
                eligible=np.maximum(c0,c1)>=900
                eligible &= np.isfinite(xyz).all(axis=(1,2))
                rejected += int((~eligible).sum())
                if not eligible.any(): continue
                source_times=chunk.time.iloc[:n*1000].to_numpy().reshape(n,1000)[selected][eligible]
                timestamps=pd.to_datetime(source_times.reshape(-1),format='ISO8601').as_unit('ns').asi8.reshape(-1,1000)
                gaps=np.diff(timestamps,axis=1)
                valid=(gaps>0).all(axis=1)&(gaps<=25000000).all(axis=1)&((timestamps[:,-1]-timestamps[:,0])>=9980000000)&((timestamps[:,-1]-timestamps[:,0])<=10010000000)
                rejected+=int((~valid).sum())
                xyz=xyz[eligible][valid].astype(float).reshape(-1,200,5,3).mean(axis=2)
                y=(c1[eligible][valid]>c0[eligible][valid]).astype(int)
                if len(xyz)==0:continue
                feats=extract_batch(xyz)
                frame=pd.DataFrame(feats,columns=NAMES)
                frame.insert(0,'timestamp',source_times[valid,0]);frame.insert(0,'pid',pid);frame['label']=y
                rows.append(frame);retained+=len(frame)
                # Validation raw windows solely for numerical deployment parity.
                parity_dir=ROOT/'data/parity-raw'; parity_dir.mkdir(exist_ok=True)
                parity_file=parity_dir/f'{pid}.npz'
                if not parity_file.exists(): np.savez_compressed(parity_file,xyz=xyz[:2],features=feats[:2])
    out=pd.concat(rows,ignore_index=True) if rows else pd.DataFrame(columns=['pid','timestamp',*NAMES,'label'])
    (ROOT/'data/participant-features').mkdir(exist_ok=True)
    out.to_csv(ROOT/'data/participant-features'/f'{pid}.csv',index=False)
    return {'pid':pid,'raw_rows':raw_rows,'candidates_every_sixth':candidates,'rejected':rejected,'samples':len(out),
            'positive':int(out.label.sum()),'negative':int(len(out)-out.label.sum()),'seconds':round(time.monotonic()-start,2),'zip_crc32':f'{member.CRC:08x}'}

def main():
    frozen=json.loads((ROOT/'data/frozen-splits.json').read_text())
    assert hashlib.sha256((ROOT/'experiment-plan.json').read_bytes()).hexdigest()==frozen['plan_sha256']
    with zipfile.ZipFile(ARCHIVE) as archive:
        metadata=archive.read('capture24/metadata.csv')
        assert hashlib.sha256(metadata).hexdigest()==frozen['metadata_sha256']
        assert archive.read('capture24/annotation-label-dictionary.csv')==(DOC/'annotation-label-dictionary.csv').read_bytes()
    pids=sorted(sum([frozen[k] for k in ['train','validation','test']],[]))
    stats=[]
    with ProcessPoolExecutor(max_workers=4) as pool:
        futures=[pool.submit(worker,p) for p in pids]
        for future in as_completed(futures):
            stat=future.result();stats.append(stat);print(json.dumps(stat),flush=True)
            (ROOT/'report/preparation-progress.json').write_text(json.dumps(stats,indent=2))
    data=pd.concat([pd.read_csv(ROOT/'data/participant-features'/f'{p}.csv') for p in pids],ignore_index=True)
    meta=pd.read_csv(io.BytesIO(metadata));data=data.merge(meta,on='pid',validate='many_to_one')
    ids={p:k for k in ['train','validation','test'] for p in frozen[k]};data['split']=data.pid.map(ids)
    data.to_csv(ROOT/'data/shared-activity-data.csv',index=False)
    manifest={'source':'Oxford CAPTURE-24','url':'https://ora.ox.ac.uk/objects/uuid:99d7c092-d865-4a19-b096-cc16440cd001','license':'CC BY4.0','archive_bytes':ARCHIVE.stat().st_size,'archive_sha256':file_sha(ARCHIVE),'people_raw':151,'people_eligible':int(data.pid.nunique()),'samples':len(data),'positive':int(data.label.sum()),'negative':int((data.label==0).sum()),'features':NAMES,'person_stats':sorted(stats,key=lambda x:x['pid'])}
    (ROOT/'data/source-manifest.json').write_text(json.dumps(manifest,indent=2))
    print('FINISHED',len(data),data.pid.nunique(),data.groupby('split').label.agg(['count','sum']).to_dict(),flush=True)

def file_sha(path):
    h=hashlib.sha256()
    with path.open('rb') as f:
        for b in iter(lambda:f.read(8*1024*1024),b''):h.update(b)
    return h.hexdigest()

if __name__=='__main__':main()
