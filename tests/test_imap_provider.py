import unittest
from unittest.mock import patch
import imap_provider as p

class Mailbox:
    def __init__(self):self.calls=[];self.flags=b'1 (UID 42 FLAGS ())';self.validity=b'99'
    def __enter__(self):return self
    def __exit__(self,*args):pass
    def login(self,*args):self.calls.append(('login',args))
    def select(self,*args,**kwargs):self.calls.append(('select',args,kwargs));return 'OK',[b'1']
    def response(self,*args):return 'UIDVALIDITY',[self.validity]
    def uid(self,*args):
        self.calls.append(args)
        if args[0]=='search':return 'OK',[b'42']
        if args[0]=='store':
            self.flags=b'1 (UID 42 FLAGS (\\Seen))' if args[2]=='+FLAGS.SILENT' else b'1 (UID 42 FLAGS ())'
            return 'OK',[]
        if 'BODY.PEEK' in args[2]:
            return 'OK',[(b'1 (UID 42 FLAGS () BODY[HEADER.FIELDS] {80}',b'From: Alex <alex@example.com>\r\nSubject: =?utf-8?b?SGVsbMOz?=\r\nDate: Wed, 30 Sep 2026 10:00:00 +0000\r\n\r\n'),b')']
        return 'OK',[self.flags]

class ImapTests(unittest.TestCase):
    def setUp(self):self.cfg={'host':'imap.example.com','port':993,'username':'u','password':'p','folder':'INBOX','webmail_url':''}
    def test_validates_server_and_safe_webmail(self):
        for change in [{'host':'https://bad'},{'port':0},{'username':'u\r\nLOGOUT'},{'webmail_url':'javascript:alert(1)'},{'webmail_url':'https://u:p@example.com'}]:
            with self.assertRaises(p.ImapError):p.settings(dict(self.cfg,**change))
    def test_lists_only_headers_using_peek_over_verified_tls(self):
        client=Mailbox()
        with patch.object(p.imaplib,'IMAP4_SSL',return_value=client) as conn:
            result=p.list_mail(self.cfg)
        ctx=conn.call_args.kwargs['ssl_context'];self.assertTrue(ctx.check_hostname)
        self.assertEqual(result['notifications'][0]['title'],'Helló')
        self.assertEqual(result['notifications'][0]['uidvalidity'],'99')
        self.assertEqual(client.calls[1][2],{'readonly':True})
        self.assertFalse(any(c[0]=='store' for c in client.calls))
    def test_read_and_undo_verify_flags(self):
        client=Mailbox()
        with patch.object(p.imaplib,'IMAP4_SSL',return_value=client):
            for seen in [True,False]:self.assertEqual(p.mark_seen(self.cfg,{'id':'42','uidvalidity':'99','seen':seen}),{'seen':seen})
        self.assertTrue(any(c[0]=='store' for c in client.calls))
    def test_uidvalidity_change_prevents_wrong_message_write(self):
        client=Mailbox();client.validity=b'100'
        with patch.object(p.imaplib,'IMAP4_SSL',return_value=client):
            with self.assertRaises(p.ImapError):p.mark_seen(self.cfg,{'id':'42','uidvalidity':'99','seen':True})
        self.assertFalse(any(c[0]=='store' for c in client.calls))
    def test_uid_ranges_cannot_modify_multiple_messages(self):
        with self.assertRaises(p.ImapError):p.mark_seen(self.cfg,{'id':'1:*','uidvalidity':'99','seen':True})
    def test_mailbox_spaces_and_unicode(self):
        self.assertEqual(p.mailbox_name('My & Stuff'),'"My &- Stuff"')
        self.assertEqual(p.mailbox_name('旅行'),'"&ZcWITA-"')

if __name__=='__main__':unittest.main()
