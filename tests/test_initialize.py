from pathlib import Path
import importlib.util
import json
import tempfile
import unittest

spec = importlib.util.spec_from_file_location('initialize', Path(__file__).resolve().parent.parent/'initialize.py')
module = importlib.util.module_from_spec(spec); spec.loader.exec_module(module)

class InitializeTests(unittest.TestCase):
    def test_new_workspace_and_permissions(self):
        with tempfile.TemporaryDirectory() as temp:
            folder = Path(temp)/'new'/'omaowl'
            module.initialize(folder)
            state = json.loads((folder/'workspace.json').read_text())
            self.assertEqual(state['tasks'], [])
            self.assertFalse(state['focus']['running'])
            self.assertEqual(folder.stat().st_mode & 0o777, 0o700)
            self.assertEqual((folder/'workspace.json').stat().st_mode & 0o777, 0o600)
    def test_existing_or_invalid_data_never_replaced(self):
        with tempfile.TemporaryDirectory() as temp:
            path = Path(temp)/'workspace.json'
            for text in ['{"notes":{"today":"Keep my note"}}', 'damaged but recoverable']:
                path.write_text(text)
                module.initialize(temp)
                self.assertEqual(path.read_text(), text)
