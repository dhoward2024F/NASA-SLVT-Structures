"""Download the pinned official JAR and verify its published SHA-256 digest."""
import hashlib
from pathlib import Path
import urllib.request
from common import ROOT, read_json


def fetch(root=ROOT):
    cfg=read_json(root/'config/automation.json')['openrocket']
    version=cfg['version']
    if version!='24.12': raise ValueError('This adapter is tested against OpenRocket 24.12')
    path=root/'.tools'/f'OpenRocket-{version}.jar'
    path.parent.mkdir(exist_ok=True)
    if path.is_file() and hashlib.sha256(path.read_bytes()).hexdigest()==cfg['jar_sha256']: return path
    url=f'https://github.com/openrocket/openrocket/releases/download/release-{version}/OpenRocket-{version}.jar'
    temp=path.with_suffix('.download')
    try:
        with urllib.request.urlopen(url, timeout=180) as source, temp.open('wb') as dest:
            while chunk:=source.read(1024*1024): dest.write(chunk)
        if hashlib.sha256(temp.read_bytes()).hexdigest()!=cfg['jar_sha256']: raise ValueError('OpenRocket JAR checksum mismatch')
        temp.replace(path)
    finally:
        temp.unlink(missing_ok=True)
    return path

if __name__=='__main__': print(fetch())
