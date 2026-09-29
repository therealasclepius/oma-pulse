"""Build a source release from tracked files only; never include user state."""
from pathlib import Path
import hashlib
import json
import subprocess

root = Path(__file__).resolve().parent.parent
version = json.loads((root/'manifest.json').read_text())['version']
out = root/'dist'; out.mkdir(exist_ok=True)
artifact = out/f'oma-owl-{version}.tar.gz'
subprocess.run(['git', 'archive', '--format=tar.gz', f'--prefix=oma-owl-{version}/', '-o', str(artifact), 'HEAD'], cwd=root, check=True)
(out/'SHA256SUMS').write_text(f'{hashlib.sha256(artifact.read_bytes()).hexdigest()}  {artifact.name}\n')
print(artifact)
