"""Restore local support files from the official archive without publishing subject IDs."""
from pathlib import Path
import argparse
import csv
import hashlib
import io
import json
import zipfile

ROOT=Path(__file__).resolve().parent

def main():
    parser=argparse.ArgumentParser()
    parser.add_argument('--archive',type=Path,default=ROOT.parent/'stress-study/data/raw/capture24/capture24.zip')
    args=parser.parse_args()
    lock=json.loads((ROOT/'split-lock.json').read_text())
    if hashlib.sha256((ROOT/'experiment-plan.json').read_bytes()).hexdigest()!=lock['plan_sha256']:
        raise ValueError('Experiment plan changed; create a new version.')
    archive=args.archive.resolve()
    with zipfile.ZipFile(archive) as source:
        metadata=source.read('capture24/metadata.csv')
        dictionary=source.read('capture24/annotation-label-dictionary.csv')
    if hashlib.sha256(metadata).hexdigest()!=lock['metadata_sha256']:
        raise ValueError('Unexpected source metadata.')
    persons=list(csv.DictReader(io.StringIO(metadata.decode())))
    lookup={hashlib.sha256(person['pid'].encode()).hexdigest():person['pid'] for person in persons}
    frozen={key:lock[key] for key in ['seed','metadata_sha256','plan_sha256']}
    for split in ['train','validation','test']:
        frozen[split]=[lookup[digest] for digest in lock['membership_sha256'][split]]
    if sum(map(len,[frozen[s] for s in ['train','validation','test']]))!=len(lookup):
        raise ValueError('Incomplete split lock.')
    for folder in ['data','report']: (ROOT/folder).mkdir(exist_ok=True)
    path=ROOT/'data/frozen-splits.json'
    if path.exists() and json.loads(path.read_text())!=frozen: raise ValueError('Refusing to replace a different split.')
    path.write_text(json.dumps(frozen,indent=2)+'\n')
    docs=ROOT.parent/'stress-study/data/source-docs/capture24'
    docs.mkdir(parents=True,exist_ok=True)
    (docs/'annotation-label-dictionary.csv').write_bytes(dictionary)
    expected=ROOT.parent/'stress-study/data/raw/capture24/capture24.zip'
    if archive!=expected.resolve():
        expected.parent.mkdir(parents=True,exist_ok=True)
        if not expected.exists(): expected.symlink_to(archive)
        elif expected.resolve()!=archive: raise ValueError('Different archive already configured.')
    print('Created local label dictionary and frozen split: 90/30/31 participants. Raw archive checksum is recorded in split-lock.json; preparation records the actual archive checksum.')

if __name__=='__main__': main()
