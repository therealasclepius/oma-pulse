import importlib.util
import json
from datetime import datetime, timedelta, timezone
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch
from urllib.error import HTTPError

spec = importlib.util.spec_from_file_location('adapter', str(Path(__file__).resolve().parent.parent / 'todoist.py'))
api = importlib.util.module_from_spec(spec); spec.loader.exec_module(api)

class TodoistTest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        api.CONFIG = Path(self.temp.name) / 'config'
        api.DATA = Path(self.temp.name) / 'data'
        api.atomic(api.CONFIG / 'todoist.json', {'token': 'fixture-token-never-sent'})
    def tearDown(self): self.temp.cleanup()
    def test_request_finishes_without_waiting_for_stdin_eof(self):
        import select
        import subprocess
        import sys
        script = "import todoist; todoist.run=lambda p: {'ok':True,'closed':p['id']}; todoist.main()"
        proc = subprocess.Popen([sys.executable, '-c', script], cwd=Path(__file__).resolve().parent.parent,
                                stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
        try:
            proc.stdin.write(json.dumps({'action':'close','id':'fixture-123'})+'\n'); proc.stdin.flush()
            ready, _, _ = select.select([proc.stdout], [], [], 2)
            self.assertTrue(ready, 'A complete JSON-line request must not wait for stdin to close')
            self.assertEqual(json.loads(proc.stdout.readline())['closed'], 'fixture-123')
            proc.wait(timeout=2)
        finally:
            if proc.poll() is None: proc.kill()
            proc.communicate()

    def test_pagination(self):
        with patch.object(api, 'request', side_effect=[{'results':[{'id':'a'}], 'next_cursor':'cursor / 2'}, {'results':[{'id':'b'}], 'next_cursor':None}]) as request:
            self.assertEqual(len(api.pages('fixture','tasks')),2)
            self.assertIn('cursor=cursor+%2F+2',request.call_args.args[1])
    def test_looped_cursor(self):
        with patch.object(api, 'request', return_value={'results':[], 'next_cursor':'repeat'}):
            with self.assertRaises(api.ApiError): api.pages('fixture','tasks')
    def test_sync_maps_and_filters(self):
        with patch.object(api,'pages',side_effect=[[{'id':'a','content':'First','project_id':'p','due':{'date':'2026-09-28','is_recurring':True}}, {'id':'b','content':'Done','checked':True}], [{'id':'p','name':'Work'}]]):
            rows=api.sync('fixture'); self.assertEqual(len(rows),1); self.assertEqual(rows[0]['project'],'Work'); self.assertTrue(rows[0]['recurring'])
    def test_invalid_key_does_not_replace(self):
        with self.assertRaises(api.ApiError): api.run({'action':'connect','token':'bad'})
        self.assertEqual(api.saved_token(),'fixture-token-never-sent')
    def test_failed_auth_does_not_replace(self):
        with patch.object(api,'sync',side_effect=api.ApiError('rejected')):
            with self.assertRaises(api.ApiError): api.run({'action':'connect','token':'a'*40})
        self.assertEqual(api.saved_token(),'fixture-token-never-sent')
    def test_verified_connection_permissions(self):
        with patch.object(api,'sync',return_value=[]): self.assertTrue(api.run({'action':'connect','token':'a'*40})['connected'])
        self.assertEqual((api.CONFIG/'todoist.json').stat().st_mode & 0o777,0o600)
    def test_add_retry_keeps_idempotency_key(self):
        with patch.object(api,'request',side_effect=api.ApiError('network lost')) as request:
            for _ in range(2):
                with self.assertRaises(api.ApiError): api.run({'action':'add','title':'Fixture tomorrow #Work'})
            self.assertEqual(request.call_args_list[0].args[3],request.call_args_list[1].args[3])
        with patch.object(api,'request',return_value={'id':'new'}): self.assertTrue(api.run({'action':'add','title':'Fixture tomorrow #Work'})['created'])
        self.assertFalse((api.DATA/'todoist-pending.json').exists())
    def test_close_endpoint(self):
        with patch.object(api,'request',return_value=None) as request:
            self.assertEqual(api.run({'action':'close','id':'abc123'})['closed'],'abc123')
            self.assertEqual(request.call_args.args[1],'tasks/abc123/close')
    def test_reminder_creates_absolute_push_without_changing_task(self):
        when = (datetime.now(timezone.utc) + timedelta(hours=2)).isoformat()
        with patch.object(api, 'request', return_value={'id':'reminder-new','due':{'date':when}}) as request:
            result = api.run({'action':'remind','id':'task-a','when':when})
            self.assertEqual(result['reminder']['id'], 'reminder-new')
            request.assert_called_once()
            self.assertEqual(request.call_args.args[1], 'reminders')
            body = request.call_args.args[2]
            self.assertEqual(body['task_id'], 'task-a')
            self.assertEqual(body['reminder_type'], 'absolute')
            self.assertEqual(body['service'], 'push')
            self.assertTrue(body['due']['date'].endswith('Z'))
    def test_reminder_rejects_past_invalid_or_ambiguous_time(self):
        for when in ['invalid', '2001-01-01T10:00:00Z', '2099-01-01T10:00:00']:
            with self.subTest(when=when), patch.object(api,'request') as request:
                with self.assertRaises(api.ApiError): api.run({'action':'remind','id':'task-a','when':when})
                request.assert_not_called()
    def test_reminder_retry_reuses_key(self):
        when = (datetime.now(timezone.utc) + timedelta(hours=2)).isoformat()
        with patch.object(api, 'request', side_effect=api.ApiError('network lost')) as request:
            for _ in range(2):
                with self.assertRaises(api.ApiError): api.run({'action':'remind','id':'task-a','when':when})
            self.assertEqual(request.call_args_list[0].args[3], request.call_args_list[1].args[3])
    def test_reminder_list_filters_deleted_and_scopes_task(self):
        with patch.object(api, 'request', return_value={'results':[{'id':'keep'},{'id':'gone','is_deleted':True}], 'next_cursor':None}) as request:
            result = api.run({'action':'reminders','id':'task-a'})
            self.assertEqual(result['reminders'], [{'id':'keep'}])
            self.assertIn('task_id=task-a', request.call_args.args[1])
    def test_undated_task_defaults_to_today(self):
        with patch.object(api, 'request', side_effect=[{'id':'new','due':None}, {'id':'new','due':{'date':'2026-09-27'}}]) as request:
            self.assertTrue(api.run({'action':'add','title':'Buy milk #Shopping p1 // Get two'})['created'])
            self.assertEqual(request.call_args_list[0].args[2], {'text':'Buy milk #Shopping p1 // Get two'})
            self.assertEqual(request.call_args.args[1:3], ('tasks/new', {'due_string':'today','due_lang':'en'}))
    def test_explicit_date_and_recurrence_are_preserved(self):
        for title, due in [('Buy milk tomorrow', {'date':'2026-09-28'}), ('Read every Friday', {'date':'2026-10-02','is_recurring':True})]:
            with self.subTest(title=title), patch.object(api, 'request', return_value={'id':'new','due':due}) as request:
                self.assertTrue(api.run({'action':'add','title':title})['created'])
                request.assert_called_once()
                self.assertEqual(request.call_args.args[2], {'text':title})
    def test_failed_today_update_retries_without_recreating(self):
        with patch.object(api, 'request', side_effect=[{'id':'new','due':None}, api.ApiError('network lost')]) as request:
            with self.assertRaisesRegex(api.ApiError, 'Task created'): api.run({'action':'add','title':'Buy milk'})
            update_key = request.call_args.args[3]
        with patch.object(api, 'request', return_value={'id':'new','due':{'date':'2026-09-27'}}) as request:
            self.assertTrue(api.run({'action':'add','title':'Buy milk'})['created'])
            request.assert_called_once()
            self.assertEqual(request.call_args.args[1], 'tasks/new')
            self.assertEqual(request.call_args.args[3], update_key)
        self.assertFalse((api.DATA/'todoist-pending.json').exists())
    def test_http_auth_error_is_sanitized(self):
        with patch.object(api.urllib.request,'urlopen',side_effect=HTTPError('https://api.todoist.com',401,'secret',{},None)):
            with self.assertRaisesRegex(api.ApiError,'API key rejected'): api.request('fixture','tasks')
    def test_disconnect_keeps_workspace(self):
        api.atomic(api.DATA/'workspace.json',{'notes':'keep'})
        self.assertFalse(api.run({'action':'disconnect'})['connected'])
        self.assertTrue((api.DATA/'workspace.json').exists())

if __name__ == '__main__': unittest.main()
