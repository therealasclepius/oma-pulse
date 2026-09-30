import datetime as dt
import json
import os
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch
import providers as p

class ProviderTests(unittest.TestCase):
    def setUp(self):
        self.temp=tempfile.TemporaryDirectory()
        self.env=patch.dict(os.environ,{'XDG_CONFIG_HOME':self.temp.name});self.env.start()
    def tearDown(self):self.env.stop();self.temp.cleanup()
    def test_private_tokens_and_public_status(self):
        p.save_config('gmail',{'client_id':'client','refresh_token':'private','access_token':'secret'})
        path=p.config_path('gmail')
        self.assertEqual(path.stat().st_mode&0o777,0o600)
        self.assertEqual(path.parent.stat().st_mode&0o777,0o700)
        result=p.run({'provider':'gmail','action':'status'})
        self.assertTrue(result['connected']);self.assertNotIn('token',json.dumps(result))
    def test_refresh_preserves_rotation_and_secret(self):
        p.save_config('outlook',{'client_id':'test','refresh_token':'old'})
        with patch.object(p,'request',return_value={'access_token':'a','refresh_token':'new','expires_in':3600}) as request:
            self.assertEqual(p.access_token('outlook'),'a')
            self.assertEqual(request.call_args.kwargs['form']['refresh_token'],'old')
        self.assertEqual(p.read_config('outlook')['refresh_token'],'new')
        with patch.object(p,'request') as request:
            self.assertEqual(p.access_token('outlook'),'a');request.assert_not_called()
    def test_failed_connection_does_not_replace_account(self):
        p.save_config('gmail',{'refresh_token':'kept'})
        with self.assertRaises(p.ProviderError):p.save_tokens('gmail',{'client_id':'new'},{'access_token':'only'})
        self.assertEqual(p.read_config('gmail')['refresh_token'],'kept')
    def test_disconnect_only_selected_provider(self):
        for provider in ['gmail','google-calendar']:p.save_config(provider,{'refresh_token':'t'})
        p.run({'provider':'gmail','action':'disconnect'})
        self.assertEqual(p.read_config('gmail'),{});self.assertTrue(p.read_config('google-calendar'))
    def test_path_and_actions_restricted(self):
        for provider in ['../gmail','hey',None]:
            with self.assertRaises(p.ProviderError):p.run({'provider':provider,'action':'status'})
        with self.assertRaises(p.ProviderError):p.run({'provider':'google-calendar','action':'seen'})
    def test_gmail_normalized(self):
        m=p.gmail_message({'id':'a','threadId':'b','labelIds':['UNREAD'],'internalDate':'1000','snippet':'one &amp; two','payload':{'headers':[{'name':'From','value':'Alex <alex@example.com>'},{'name':'Subject','value':'Hi'}]}})
        self.assertEqual((m['creator'],m['excerpt'],m['unread']),('Alex','one & two',True))
    def test_read_changes_verified(self):
        with patch.object(p,'access_token',return_value='t'),patch.object(p,'request',side_effect=[{}, {'labelIds':[]}]) as r:
            self.assertTrue(p.mark_seen('gmail',{'id':'a/b','seen':True})['seen'])
            self.assertIn('a%2Fb/modify',r.call_args_list[0].args[0])
            self.assertEqual(r.call_args_list[0].kwargs['data'],{'removeLabelIds':['UNREAD']})
        with patch.object(p,'access_token',return_value='t'),patch.object(p,'request',side_effect=[{}, {'isRead':True}]):
            with self.assertRaises(p.ProviderError):p.mark_seen('outlook',{'id':'abc','seen':False})
    def test_calendar_spanning_midnight_and_exclusive_all_day(self):
        today=dt.datetime.now(dt.timezone.utc).date()
        tomorrow=today+dt.timedelta(days=1)
        events=[{'summary':'All day','start':{'date':str(today)},'end':{'date':str(tomorrow)}},
                {'summary':'Late work','start':{'dateTime':str(today)+'T23:30:00Z'},'end':{'dateTime':str(tomorrow)+'T00:30:00Z'}}]
        with patch.object(p,'access_token',return_value='t'),patch.object(p,'request',side_effect=[{'timeZone':'UTC','summary':'Test'},{'items':events},{'id':'user@example.com'}]):
            result=p.calendar_feed()
        self.assertEqual(len(result['days']),8)
        self.assertEqual(len(result['days'][0]['events']),2)
        self.assertEqual([e['title'] for e in result['days'][1]['events']],['Late work'])
        self.assertEqual(result['account_email'],'user@example.com')
    def test_calendar_paginates(self):
        with patch.object(p,'access_token',return_value='t'),patch.object(p,'request',side_effect=[{'timeZone':'UTC'},{'items':[],'nextPageToken':'second'},{'items':[]},{'id':'u'}]) as req:
            p.calendar_feed();self.assertIn('pageToken=second',req.call_args_list[2].args[0])
    def test_errors_do_not_echo_remote_secrets(self):
        self.assertNotIn('secret',str(p.ApiError(400,'secret')))

    def test_google_loopback_checks_state_and_uses_pkce(self):
        import threading
        import urllib.request
        from urllib.parse import urlparse,parse_qs,urlencode
        observations={}; threads=[]
        def auth(event):
            query=parse_qs(urlparse(event['auth_url']).query);observations.update(query)
            def callback():
                base=query['redirect_uri'][0]
                try:urllib.request.urlopen(base+'?'+urlencode({'code':'bad','state':'wrong'}))
                except urllib.error.HTTPError as error:
                    self.assertEqual(error.code,400);error.close()
                with urllib.request.urlopen(base+'?'+urlencode({'code':'correct','state':query['state'][0]})) as r:self.assertEqual(r.status,200)
            thread=threading.Thread(target=callback);thread.start();threads.append(thread)
        with patch.object(p,'emit',side_effect=auth),patch.object(p,'request',return_value={'access_token':'a','refresh_token':'r'}) as request:
            self.assertTrue(p.connect('gmail',{'client_id':'test','client_secret':'secret'})['connected'])
        for thread in threads:thread.join()
        form=request.call_args.kwargs['form']
        self.assertEqual(form['code'],'correct')
        self.assertEqual(observations['code_challenge_method'],['S256'])
        challenge=p.base64.urlsafe_b64encode(p.hashlib.sha256(form['code_verifier'].encode()).digest()).rstrip(b'=').decode()
        self.assertEqual(observations['code_challenge'],[challenge])
    def test_microsoft_pending_and_slow_down(self):
        responses=[{'user_code':'CODE','device_code':'d','expires_in':600,'interval':5},p.ApiError(400,'authorization_pending'),p.ApiError(400,'slow_down'),{'access_token':'a','refresh_token':'r'}]
        with patch.object(p,'request',side_effect=responses),patch.object(p.time,'sleep') as sleep,patch.object(p,'emit'):
            self.assertTrue(p.connect('outlook',{'client_id':'test'})['connected'])
        self.assertEqual([c.args[0] for c in sleep.call_args_list],[5,5,10])

if __name__=='__main__':unittest.main()
