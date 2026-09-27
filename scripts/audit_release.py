"""Fail publication on private artifacts, literal home paths, or likely credentials."""
from pathlib import Path
import hashlib
import re
import subprocess
import zipfile

root = Path(__file__).resolve().parents[1]
patterns = [
    re.compile(rb'/Users/[A-Za-z0-9_. -]+/'),
    re.compile(rb'/home/[A-Za-z0-9_.-]+/'),
    re.compile(rb'/var/folders/[A-Za-z0-9_/.-]+'),
    re.compile(rb'[A-Za-z]:\\Users\\[^\\\r\n]+\\'),
    re.compile(rb'gh[pousr]_[A-Za-z0-9]{20,}'),
    re.compile(rb'github_pat_[A-Za-z0-9_]{20,}'),
    re.compile(rb'sk-[A-Za-z0-9_-]{24,}'),
    re.compile(rb'-----BEGIN (?:RSA |EC |OPENSSH )?PRIVATE KEY-----'),
]
forbidden_parts = {'node_modules','vendor','backups','.devtools','__MACOSX'}
forbidden_suffixes = {'.png','.jpg','.jpeg','.webp','.sqlite','.db','.log'}
forbidden_names = {'auth.json','config.json','worker.json','.DS_Store','stop.request'}

def inspect(name, data):
    p = Path(name)
    if forbidden_parts.intersection(p.parts) or p.suffix.lower() in forbidden_suffixes or p.name in forbidden_names or p.name.startswith('.env'):
        raise SystemExit('Forbidden artifact: '+name)
    if any(pattern.search(data) for pattern in patterns):
        raise SystemExit('Potential secret/personal path (content withheld): '+name)

tracked = subprocess.check_output(['git','ls-files','-z'],cwd=root).decode().split('\0')
count = 0
for name in filter(None,tracked):
    inspect(name,(root/name).read_bytes()); count += 1
if not count:
    raise SystemExit('No tracked files: stage the reviewed source before auditing')
for archive in sorted((root/'dist').glob('*.zip')):
    with zipfile.ZipFile(archive) as z:
        if z.testzip(): raise SystemExit('Corrupt archive: '+archive.name)
        sums = [n for n in z.namelist() if n.endswith('/SHA256SUMS.txt')]
        if len(sums)!=1: raise SystemExit('Missing checksum manifest: '+archive.name)
        prefix=sums[0].rsplit('/',1)[0]+'/'
        expected=[]
        for line in z.read(sums[0]).decode().splitlines():
            digest,name=line.split('  ',1);expected.append(prefix+name)
            if hashlib.sha256(z.read(prefix+name)).hexdigest()!=digest: raise SystemExit('Hash mismatch: '+name)
        if set(z.namelist())!=set(expected+[sums[0]]): raise SystemExit('Unexpected archive file')
        for info in z.infolist():
            inspect(info.filename,z.read(info.filename))
            if '..' in Path(info.filename).parts or info.filename.startswith('/'): raise SystemExit('Unsafe ZIP entry')
            if info.filename.endswith('.ps1') and not z.read(info.filename).startswith(b'\xef\xbb\xbf'): raise SystemExit('Missing PowerShell BOM')
    print('PASS archive privacy, allowlist and checksums:',archive.name)
print(f'PASS source privacy scan: {count} tracked files')
