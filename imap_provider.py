"""TLS-only IMAP previews and verified read/unread changes; never fetch message bodies."""
from contextlib import contextmanager
import datetime as dt
import email
import email.header
import email.utils
import imaplib
import re
import ssl
from urllib.parse import urlparse

class ImapError(Exception):
    pass

def settings(args):
    host=str(args.get('host','')).strip()
    username=str(args.get('username','')).strip()
    password=str(args.get('password',''))
    folder=str(args.get('folder','INBOX')).strip() or 'INBOX'
    webmail=str(args.get('webmail_url','')).strip()
    try: port=int(args.get('port',993))
    except (ValueError,TypeError): raise ImapError('Enter a valid TLS port.') from None
    if not host or len(host)>253 or not re.fullmatch(r'[a-zA-Z0-9.:-]+',host) or not 1<=port<=65535:
        raise ImapError('Enter the IMAP server hostname and TLS port (usually 993).')
    if not username or not password or any(c in username+password+folder for c in '\r\n\x00'):
        raise ImapError('Enter your username, app password and mailbox without control characters.')
    if len(username)>512 or len(password)>1024 or len(folder)>512:
        raise ImapError('The account settings are too long.')
    if webmail:
        parsed=urlparse(webmail)
        if parsed.scheme!='https' or not parsed.hostname or parsed.username or parsed.password or any(c.isspace() for c in webmail):
            raise ImapError('The optional webmail address must be an HTTPS URL without a password.')
    return dict(host=host,port=port,username=username,password=password,folder=folder,webmail_url=webmail)

def mailbox_name(name):
    # Modified UTF-7 for IMAP4rev1 mailbox names, quoted to preserve spaces.
    import base64
    out=[]; run=[]
    def flush():
        if run:
            out.append('&'+base64.b64encode(''.join(run).encode('utf-16be')).decode().rstrip('=').replace('/',',')+'-');run.clear()
    for char in name:
        if 0x20<=ord(char)<=0x7e:
            flush();out.append('&-' if char=='&' else char)
        else:run.append(char)
    flush()
    return '"'+''.join(out).replace('\\','\\\\').replace('"','\\"')+'"'

@contextmanager
def mailbox(config,readonly=True):
    try:
        with imaplib.IMAP4_SSL(config['host'],config.get('port',993),ssl_context=ssl.create_default_context(),timeout=25) as client:
            client.login(config['username'],config['password'])
            status,_=client.select(mailbox_name(config.get('folder','INBOX')),readonly=readonly)
            if status!='OK':raise ImapError('Could not open that mailbox. Check its name.')
            _,validity=client.response('UIDVALIDITY')
            value=(validity or [None])[0]
            if not value or not value.isdigit():raise ImapError('The server did not provide a valid mailbox ID.')
            yield client,value.decode()
    except (imaplib.IMAP4.error,OSError,UnicodeError,KeyError):
        raise ImapError('Could not connect to IMAP. Check the TLS server, app password, mailbox and provider access settings.') from None

def check(config):
    with mailbox(config): pass

def decoded(value):
    try:return str(email.header.make_header(email.header.decode_header(value or '')))
    except (LookupError,UnicodeError):return str(value or '')

def list_mail(config):
    with mailbox(config) as (client,validity):
        status,data=client.uid('search',None,'UNSEEN')
        if status!='OK':raise ImapError('Could not list unread mail. Try again.')
        ids=(data[0] or b'').split()[-20:][::-1];messages=[]
        for ident in ids:
            if not ident.isdigit():continue
            status,data=client.uid('fetch',ident,'(UID FLAGS BODY.PEEK[HEADER.FIELDS (FROM SUBJECT DATE)])')
            if status!='OK':raise ImapError('Could not read message headers. Try refreshing.')
            pairs=[item for item in data if isinstance(item,tuple) and len(item)==2 and isinstance(item[1],bytes)]
            if not pairs:continue  # Message may have been deleted during refresh.
            metadata,raw=pairs[0]
            if len(raw)>65536:continue
            header=email.message_from_bytes(raw)
            name,address=email.utils.parseaddr(decoded(header.get('From','')))
            try:
                date=email.utils.parsedate_to_datetime(header.get('Date',''))
                if date.tzinfo is None:date=date.replace(tzinfo=dt.timezone.utc)
                timestamp=int(date.timestamp()*1000)
            except (TypeError,ValueError,OverflowError):timestamp=0
            messages.append({'id':ident.decode(),'uidvalidity':validity,'title':decoded(header.get('Subject'))[:256] or '(No subject)',
                'creator':(name or address)[:160],'excerpt':'Open your full mailbox to read this message.',
                'unread':b'\\Seen' not in imaplib.ParseFlags(metadata),'timestampMs':timestamp,'url':config.get('webmail_url','')})
        return {'connected':True,'notifications':messages}

def mark_seen(config,args):
    ident=str(args.get('id',''));validity=str(args.get('uidvalidity',''));seen=args.get('seen')
    if not re.fullmatch(r'[1-9][0-9]*',ident) or not validity.isdigit() or not isinstance(seen,bool):
        raise ImapError('Refresh IMAP before changing this message.')
    with mailbox(config,readonly=False) as (client,current):
        if current!=validity:raise ImapError('This mailbox has changed. Refresh before changing messages.')
        status,_=client.uid('store',ident,'+FLAGS.SILENT' if seen else '-FLAGS.SILENT',r'(\Seen)')
        if status!='OK':raise ImapError('The server did not accept the read change.')
        status,data=client.uid('fetch',ident,'(UID FLAGS)')
        rows=[r for r in data if isinstance(r,bytes)]
        if status!='OK' or not rows or (b'\\Seen' in imaplib.ParseFlags(rows[0]))!=seen:
            raise ImapError('Read state could not be confirmed. Refresh before retrying.')
        return {'seen':seen}
