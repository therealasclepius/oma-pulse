from pathlib import Path
import ast
import json
import subprocess

root = Path(__file__).resolve().parent.parent
for path in root.glob('*.py'):
    ast.parse(path.read_text(), filename=str(path))
for path in [root/'install.sh', *root.glob('scripts/*.sh'), root/'bin/omaowl', root/'bin/omapulse']:
    subprocess.run(['bash', '-n', str(path)], check=True)
for path in [root/'site/site.js', root/'scripts/build-site.cjs']:
    subprocess.run(['node', '--check', str(path)], check=True)
manifest = json.loads((root/'manifest.json').read_text())
assert manifest['version'] == json.loads((root/'package.json').read_text())['version']
for path in manifest['entryPoints'].values():
    assert (root/path).is_file()
print('Python, shell, website syntax and package metadata passed.')
