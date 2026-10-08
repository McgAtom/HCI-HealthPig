"""Get the four adopted public CDC XPTs and verify their frozen checksums."""
import hashlib, json, urllib.request
from pathlib import Path

ROOT=Path(__file__).resolve().parent
DEST=ROOT.parent/'stress-study/data/raw/nhanes-2011-2014-audit'
SOURCES=ROOT/'source-files.json'

def main():
    DEST.mkdir(parents=True,exist_ok=True)
    for item in json.loads(SOURCES.read_text())['sources']:
        path=DEST/item['file']
        if not path.exists():
            partial=path.with_suffix('.xpt.partial')
            urllib.request.urlretrieve(item['url'],partial)
            if hashlib.sha256(partial.read_bytes()).hexdigest()!=item['sha256']:
                raise ValueError('Source checksum changed: '+item['file'])
            partial.rename(path)
        if hashlib.sha256(path.read_bytes()).hexdigest()!=item['sha256']:
            raise ValueError('Source checksum mismatch: '+item['file'])
        print('Verified:',item['file'])

if __name__=='__main__':main()
