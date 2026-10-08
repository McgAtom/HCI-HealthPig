"""Check the public file allowlist, contents and optionally all reachable Git history."""
from pathlib import Path
import argparse
import json
import re
import subprocess

ROOT = Path(__file__).resolve().parents[1]
PATTERNS = {
    'home directory': r'/(?:Users|home)/[^/\s]+/',
    'device identifier': r'\b0000[0-9a-fA-F]{4}-[0-9a-fA-F]{16}\b',
    'GitHub credential': r'\b(?:gh[pousr]_[A-Za-z0-9]{30,}|github_pat_[A-Za-z0-9_]{30,})\b',
    'API credential': r'\bsk-(?:proj-)?[A-Za-z0-9_-]{24,}\b',
    'private key': r'-----BEGIN (?:RSA |EC |OPENSSH )?PRIVATE KEY-----',
    'student number': r'(?<![\w.])\d{12}(?![\w.])',
}

def git(*args):
    return subprocess.check_output(['git',*args],cwd=ROOT,text=True)

def check(path, data, allowed):
    if path not in allowed: raise ValueError('File outside public allowlist: '+path)
    if len(data)>1_000_000: raise ValueError('Unexpected large file: '+path)
    text=data.decode('utf-8')
    for label,pattern in PATTERNS.items():
        if re.search(pattern,text): raise ValueError(f'{label} detected: {path}')
    if path.endswith('project.pbxproj'):
        if any(value.strip()!='org.example.HealthPig' for value in re.findall(r'PRODUCT_BUNDLE_IDENTIFIER\s*=([^;]+);',text)):
            raise ValueError('Personal bundle identifier: '+path)
        if any(value.strip()!='""' for value in re.findall(r'DEVELOPMENT_TEAM\s*=([^;]+);',text)):
            raise ValueError('Signing team: '+path)
    emails=re.findall(r'[A-Za-z0-9_.+\-]+@[A-Za-z0-9.\-]+\.[A-Za-z]{2,}',text)
    if any(not email.endswith('@users.noreply.github.com') and email!='noreply@github.com' for email in emails):
        raise ValueError('Email address detected: '+path)
    if path.endswith('.json'):
        def inspect(value):
            if isinstance(value,dict):
                forbidden={'pid','subject','timestamp','xyz','person_stats','participants_raw','device_id','apple_id','student_id','email'}
                if forbidden.intersection(value): raise ValueError('Individual or account data key: '+path)
                for item in value.values(): inspect(item)
            elif isinstance(value,list):
                for item in value: inspect(item)
        inspect(json.loads(text))

def main():
    parser=argparse.ArgumentParser()
    parser.add_argument('--working-tree',action='store_true')
    parser.add_argument('--history',action='store_true')
    args=parser.parse_args()
    allowed=set(json.loads((ROOT/'public-files.json').read_text())['files'])
    for relative in allowed:
        path=ROOT/relative
        if path.is_symlink() or not path.resolve().is_relative_to(ROOT.resolve()): raise ValueError('Unsafe path')
        check(relative,path.read_bytes(),allowed)
    if (ROOT/'.git').exists():
        for relative in git('ls-files','-z').split('\0'):
            if relative: check(relative,git('show',':'+relative).encode(),allowed)
        if args.history:
            seen=set()
            for commit in git('rev-list','--all').splitlines():
                for entry in git('ls-tree','-r',commit).splitlines():
                    metadata,relative=entry.split('\t',1)
                    mode,kind,oid=metadata.split()
                    if mode not in {'100644','100755'}: raise ValueError('Non-file Git entry: '+relative)
                    if (relative,oid) in seen: continue
                    seen.add((relative,oid))
                    check(relative,subprocess.check_output(['git','cat-file','blob',oid],cwd=ROOT),allowed)
                for email in git('show','-s','--format=%ae%n%ce',commit).splitlines():
                    if not email.endswith('@users.noreply.github.com') and email!='noreply@github.com':
                        raise ValueError('Non-public email in Git history')
    print(f'PASS: {len(allowed)} public files; allowlist and content checks'+('; reachable Git history checked' if args.history else ''))

if __name__=='__main__': main()
