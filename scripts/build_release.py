"""Allowlist-based portable release archives. Requires only the Python standard library."""
from pathlib import Path
import hashlib
import json
import subprocess
import sys
import zipfile

root = Path(__file__).resolve().parents[1]
version = json.loads((root / 'package.json').read_text())['version']
subprocess.run([sys.executable, str(root / 'build.py')], check=True)
dist = root / 'dist'
dist.mkdir(exist_ok=True)
archives = []
for platform in ['macOS', 'Windows']:
    name = f'CodexUsageBadge-{platform}-{version}'
    dest = dist / name
    dest.mkdir(exist_ok=True)
    mapping = {'agent.cjs':'agent.cjs','README.md':'README.md','LICENSE':'LICENSE','SECURITY.md':'SECURITY.md','docs/windows.md':'docs/windows.md','assets/cover.png':'assets/cover.png'}
    modes = {}
    generated = {}
    if platform == 'macOS':
        mapping.update({'manage.cjs':'manage.cjs','scripts/mac-entry.sh':'scripts/mac-entry.sh'})
        modes['scripts/mac-entry.sh'] = 0o755
        for filename, action in [('安装.command','install'),('诊断.command','status'),('卸载.command','uninstall')]:
            generated[filename] = f'#!/bin/bash\nexec /bin/bash "$(dirname "$0")/scripts/mac-entry.sh" {action}\n'.encode()
            modes[filename] = 0o755
    else:
        mapping.update({'manage-windows.ps1':'windows/manage-windows.ps1','bridge.cjs':'windows/bridge.cjs','README-Windows.md':'docs/windows.md'})
        for action in ['Install','Launch','Status','Uninstall']:
            text = f'@echo off\nsetlocal\n"%SystemRoot%\\System32\\WindowsPowerShell\\v1.0\\powershell.exe" -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0manage-windows.ps1" -Action {action}\nset "BADGE_EXIT=%ERRORLEVEL%"\nif not "%BADGE_EXIT%"=="0" echo Operation failed. See the message above.\npause\nexit /b %BADGE_EXIT%\n'
            generated[action+'.cmd'] = text.replace('\n','\r\n').encode('ascii')
    payload = {file:(root / source).read_bytes() for file,source in mapping.items()}
    payload.update(generated)
    if platform == 'Windows':
        ps = payload['manage-windows.ps1'].decode('utf-8-sig').replace('\r\n','\n')
        payload['manage-windows.ps1'] = b'\xef\xbb\xbf' + ps.replace('\n','\r\n').encode('utf-8')
    payload['SHA256SUMS.txt'] = ''.join(f'{hashlib.sha256(data).hexdigest()}  {file}\n' for file,data in sorted(payload.items())).encode()
    archive = dist / (name+'.zip')
    with zipfile.ZipFile(archive, 'w', zipfile.ZIP_DEFLATED) as z:
        for file,data in sorted(payload.items()):
            target = dest / file
            target.parent.mkdir(parents=True,exist_ok=True)
            target.write_bytes(data)
            target.chmod(modes.get(file,0o644))
            info = zipfile.ZipInfo(name+'/'+file, date_time=(2026,1,1,0,0,0))
            info.create_system = 3
            info.external_attr = (0o100000 | modes.get(file,0o644)) << 16
            info.compress_type = zipfile.ZIP_DEFLATED
            z.writestr(info,data)
    archives.append(archive)
    print(archive.name)
(dist/'SHA256SUMS.txt').write_text(''.join(f'{hashlib.sha256(p.read_bytes()).hexdigest()}  {p.name}\n' for p in archives))
