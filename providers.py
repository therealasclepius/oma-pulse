"""User-owned OAuth connections. JSON lines in/out; credentials never leave this helper."""
import imap_provider
import base64
import datetime as dt
import email.utils
import hashlib
import html
import http.server
import json
import os
from pathlib import Path
import re
import secrets
import sys
import tempfile
import time
import urllib.error
import urllib.parse as url
import urllib.request
from zoneinfo import ZoneInfo

PROVIDERS = {
    'imap': (None, None),
    'gmail': ('https://oauth2.googleapis.com/token', 'https://www.googleapis.com/auth/gmail.modify'),
    'google-calendar': ('https://oauth2.googleapis.com/token', 'https://www.googleapis.com/auth/calendar.readonly'),
    'outlook': ('https://login.microsoftonline.com/common/oauth2/v2.0/token', 'offline_access https://graph.microsoft.com/Mail.ReadWrite'),
}

class ProviderError(Exception):
    pass

class ApiError(ProviderError):
    def __init__(self, status, code=''):
        self.status, self.code = status, code
        super().__init__('Sign in again in Connections.' if status == 401 or code == 'invalid_grant' else
                         'Access denied. Check app permissions and enabled APIs.' if status == 403 else
                         'Too many requests. Try again shortly.' if status == 429 else
                         'The provider could not complete this request. Check connection setup and try again.')

class NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, *args, **kwargs):
        return None

def request(endpoint, *, token=None, data=None, form=None, method=None):
    headers = {'Accept': 'application/json'}
    if token: headers['Authorization'] = 'Bearer ' + token
    body = None
    if form is not None:
        body = url.urlencode(form).encode(); headers['Content-Type'] = 'application/x-www-form-urlencoded'
    elif data is not None:
        body = json.dumps(data).encode(); headers['Content-Type'] = 'application/json'
    req = urllib.request.Request(endpoint, data=body, headers=headers, method=method)
    try:
        with urllib.request.build_opener(NoRedirect).open(req, timeout=25) as r:
            raw = r.read(4_194_305)
            if len(raw) > 4_194_304: raise ProviderError('Provider response was too large.')
            return json.loads(raw) if raw else {}
    except urllib.error.HTTPError as e:
        try:
            error = json.loads(e.read(16384)).get('error', '')
            code = error.get('code', '') if isinstance(error, dict) else error
        except (ValueError, AttributeError): code = ''
        raise ApiError(e.code, code) from None
    except (OSError, ValueError):
        raise ProviderError('Could not reach the provider. Check your connection and try again.') from None

def config_path(provider):
    if provider not in PROVIDERS: raise ProviderError('Unknown provider.')
    return Path(os.environ.get('XDG_CONFIG_HOME', str(Path.home()/'.config')))/'omaowl'/'connections'/(provider+'.json')

def read_config(provider):
    try: return json.loads(config_path(provider).read_text())
    except FileNotFoundError: return {}
    except (OSError, ValueError): raise ProviderError('Could not read connection settings; the original file was preserved.') from None

def save_config(provider, config):
    path = config_path(provider)
    path.parent.mkdir(parents=True, exist_ok=True, mode=0o700)
    os.chmod(path.parent, 0o700)
    fd, temp = tempfile.mkstemp(dir=path.parent)
    try:
        with os.fdopen(fd, 'w') as f:
            json.dump(config, f); f.flush(); os.fsync(f.fileno())
        os.replace(temp, path)
    finally:
        if os.path.exists(temp): os.unlink(temp)

def public_status(config):
    return {'connected': bool(config.get('refresh_token') or config.get('password')), 'configured': bool(config.get('client_id') or config.get('host')),
            'webmail_url': config.get('webmail_url',''),
            'calendar_id': config.get('calendar_id', 'primary')}

def save_tokens(provider, config, result):
    if not result.get('access_token'): raise ProviderError('Sign-in did not return an access token.')
    updated = dict(config, access_token=result['access_token'], expires_at=time.time()+int(result.get('expires_in',3600)))
    if result.get('refresh_token'): updated['refresh_token'] = result['refresh_token']
    if not updated.get('refresh_token'): raise ProviderError('No offline access was granted. Reconnect and approve access.')
    save_config(provider, updated)
    return updated

def access_token(provider):
    config = read_config(provider)
    if not config.get('refresh_token'): raise ProviderError('Connect this account in Connections first.')
    if config.get('access_token') and config.get('expires_at',0) > time.time()+60: return config['access_token']
    form = {'client_id':config['client_id'], 'refresh_token':config['refresh_token'], 'grant_type':'refresh_token'}
    if config.get('client_secret'): form['client_secret']=config['client_secret']
    updated=save_tokens(provider, config, request(PROVIDERS[provider][0], form=form))
    return updated['access_token']

def emit(value):
    print(json.dumps(value), flush=True)

def connect(provider, args):
    client = str(args.get('client_id','')).strip()
    secret = str(args.get('client_secret','')).strip()
    if not client or len(client)>512 or len(secret)>512: raise ProviderError('Enter a valid OAuth client ID.')
    config = {'client_id':client, 'calendar_id':str(args.get('calendar_id','primary')).strip() or 'primary'}
    if secret: config['client_secret']=secret
    if provider == 'outlook':
        reply = request('https://login.microsoftonline.com/common/oauth2/v2.0/devicecode', form={'client_id':client,'scope':PROVIDERS[provider][1]})
        emit({'auth_url':'https://microsoft.com/devicelogin','user_code':reply['user_code']})
        interval=max(5,int(reply.get('interval',5))); deadline=time.monotonic()+min(600,int(reply['expires_in']))
        while time.monotonic()<deadline:
            time.sleep(interval)
            try:
                result=request(PROVIDERS[provider][0],form={'client_id':client,'grant_type':'urn:ietf:params:oauth:grant-type:device_code','device_code':reply['device_code']})
                return public_status(save_tokens(provider,config,result))
            except ApiError as e:
                if e.code=='authorization_pending': continue
                if e.code=='slow_down': interval+=5; continue
                raise
        raise ProviderError('Sign-in timed out. Try again.')
    state=secrets.token_urlsafe(32); verifier=secrets.token_urlsafe(64)
    challenge=base64.urlsafe_b64encode(hashlib.sha256(verifier.encode()).digest()).rstrip(b'=').decode()
    result={}
    class Callback(http.server.BaseHTTPRequestHandler):
        def log_message(self,*args): pass
        def do_GET(self):
            parsed=url.urlparse(self.path); params=url.parse_qs(parsed.query)
            if parsed.path!='/callback' or not secrets.compare_digest(params.get('state',[''])[0],state):
                self.send_error(400); return
            result.update({k:v[0] for k,v in params.items()})
            self.send_response(200); self.send_header('Content-Type','text/plain; charset=utf-8'); self.end_headers()
            self.wfile.write(b'Return to Oma Pulse to finish connecting. You can close this tab.')
    with http.server.HTTPServer(('127.0.0.1',0),Callback) as server:
        server.timeout=1; redirect=f'http://127.0.0.1:{server.server_port}/callback'
        params={'client_id':client,'redirect_uri':redirect,'response_type':'code','scope':PROVIDERS[provider][1],
                'access_type':'offline','prompt':'consent','state':state,'code_challenge':challenge,'code_challenge_method':'S256'}
        emit({'auth_url':'https://accounts.google.com/o/oauth2/v2/auth?'+url.urlencode(params)})
        deadline=time.monotonic()+300
        while not result and time.monotonic()<deadline: server.handle_request()
        if not result.get('code'): raise ProviderError('Sign-in was cancelled or timed out. Try again.')
        form={'client_id':client,'code':result['code'],'redirect_uri':redirect,'grant_type':'authorization_code','code_verifier':verifier}
        if secret: form['client_secret']=secret
        return public_status(save_tokens(provider,config,request(PROVIDERS[provider][0],form=form)))

def clean(value, limit=512):
    return re.sub(r'\s+',' ',html.unescape(str(value or ''))).strip()[:limit]

def gmail_message(m):
    headers={h['name'].lower():h['value'] for h in m.get('payload',{}).get('headers',[])}
    name,address=email.utils.parseaddr(headers.get('from',''))
    return {'id':m['id'],'title':clean(headers.get('subject') or '(No subject)',256),'creator':clean(name or address,160),
            'excerpt':clean(m.get('snippet')),'unread':'UNREAD' in m.get('labelIds',[]),
            'timestampMs':int(m.get('internalDate',0)), 'url':'https://mail.google.com/mail/u/0/#inbox/'+url.quote(m.get('threadId',m['id']),safe='')}

def list_mail(provider):
    token=access_token(provider)
    if provider=='gmail':
        base='https://gmail.googleapis.com/gmail/v1/users/me/messages'
        profile=request('https://gmail.googleapis.com/gmail/v1/users/me/profile',token=token)
        ids=request(base+'?'+url.urlencode({'q':'in:inbox is:unread','maxResults':20}),token=token).get('messages',[])
        from concurrent.futures import ThreadPoolExecutor
        def get(m):
            message=gmail_message(request(base+'/'+url.quote(m['id'],safe='')+'?format=metadata',token=token))
            message['url']=message['url'].replace('/mail/u/0/', '/mail/?'+url.urlencode({'authuser':profile.get('emailAddress','')}))
            return message
        with ThreadPoolExecutor(max_workers=4) as pool: messages=list(pool.map(get,ids))
    else:
        query={'$filter':'receivedDateTime ge 1970-01-01T00:00:00Z and isRead eq false','$orderby':'receivedDateTime desc','$top':20,'$select':'id,subject,from,bodyPreview,receivedDateTime,isRead,webLink'}
        rows=request('https://graph.microsoft.com/v1.0/me/mailFolders/inbox/messages?'+url.urlencode(query),token=token).get('value',[])
        messages=[{'id':m['id'],'title':clean(m.get('subject') or '(No subject)',256),
            'creator':clean(m.get('from',{}).get('emailAddress',{}).get('name'),160),
            'excerpt':clean(m.get('bodyPreview')),'unread':not m.get('isRead',False),
            'timestampMs':int(dt.datetime.fromisoformat(m['receivedDateTime'].replace('Z','+00:00')).timestamp()*1000),
            'url':m.get('webLink','https://outlook.office.com/mail/')} for m in rows]
        messages.sort(key=lambda m:m['timestampMs'],reverse=True)
    return {'notifications':messages,'connected':True}

def mark_seen(provider,args):
    ident=str(args.get('id',''))
    if not ident or len(ident)>2048: raise ProviderError('Invalid message.')
    seen=args.get('seen')
    if not isinstance(seen,bool): raise ProviderError('Invalid read state.')
    token=access_token(provider)
    if provider=='gmail':
        base='https://gmail.googleapis.com/gmail/v1/users/me/messages/'+url.quote(ident,safe='')
        request(base+'/modify',token=token,data={'removeLabelIds':['UNREAD']} if seen else {'addLabelIds':['UNREAD']})
        result=request(base+'?format=minimal',token=token)
        verified=('UNREAD' not in result.get('labelIds',[]))==seen
    else:
        base='https://graph.microsoft.com/v1.0/me/messages/'+url.quote(ident,safe='')
        request(base,token=token,data={'isRead':seen},method='PATCH')
        result=request(base+'?$select=isRead',token=token)
        verified=result.get('isRead') is seen
    if not verified: raise ProviderError('Read state could not be confirmed. Refresh before retrying.')
    return {'seen':seen}

def calendar_feed():
    provider='google-calendar'; token=access_token(provider); config=read_config(provider)
    base='https://www.googleapis.com/calendar/v3/calendars/'+url.quote(config.get('calendar_id','primary'),safe='')
    info=request(base,token=token); zone=ZoneInfo(info.get('timeZone','UTC'))
    now=dt.datetime.now(zone); start=now.replace(hour=0,minute=0,second=0,microsecond=0); end=start+dt.timedelta(days=8)
    query={'singleEvents':'true','orderBy':'startTime','timeMin':start.isoformat(),'timeMax':end.isoformat(),'maxResults':2500}
    rows=[]
    while True:
        response=request(base+'/events?'+url.urlencode(query),token=token)
        rows.extend(response.get('items',[]))
        if not response.get('nextPageToken'): break
        if len(rows)>20000: raise ProviderError('Too many events in this calendar; choose a smaller calendar.')
        query['pageToken']=response['nextPageToken']
    days=[{'date':(start+dt.timedelta(days=i)).date().isoformat(),'label':(start+dt.timedelta(days=i)).strftime('%b %-d, %Y'),'events':[]} for i in range(8)]
    clocks={}; events=[]
    for event in rows:
        if event.get('status')=='cancelled': continue
        first,last=event.get('start',{}),event.get('end',{})
        if not first or not last: continue
        all_day='date' in first
        a=dt.datetime.fromisoformat(first.get('dateTime',first.get('date')).replace('Z','+00:00'))
        b=dt.datetime.fromisoformat(last.get('dateTime',last.get('date')).replace('Z','+00:00'))
        if a.tzinfo is None: a=a.replace(tzinfo=zone)
        if b.tzinfo is None: b=b.replace(tzinfo=zone)
        a=a.astimezone(zone); b=b.astimezone(zone)
        row={'title':clean(event.get('summary') or '(Untitled event)',256),'start_ms':int(a.timestamp()*1000),
             'end_ms':int(b.timestamp()*1000),'all_day':all_day,'calendar':clean(info.get('summary','Google Calendar'),160),'url':event.get('htmlLink','')}
        events.append(row)
        for day in days:
            d=dt.date.fromisoformat(day['date'])
            if a.date()<=d and (b-dt.timedelta(microseconds=1)).date()>=d: day['events'].append(row)
        clocks[str(row['start_ms'])]=a.strftime('%-I:%M %p');clocks[str(row['end_ms'])]=b.strftime('%-I:%M %p')
    return {'days':days,'events':events,'clocks':clocks,'today':start.date().isoformat(),'timezone':str(zone),'connected':True,'account_email':request('https://www.googleapis.com/calendar/v3/calendars/primary',token=token).get('id','')}

def run(args):
    provider=args.get('provider')
    config_path(provider)
    action=args.get('action')
    if action=='status': return public_status(read_config(provider))
    if provider=='imap' and action in ['connect','sync','seen']:
        try:
            if action=='connect':
                config=imap_provider.settings(args);imap_provider.check(config);save_config(provider,config)
                return public_status(config)
            config=read_config(provider)
            if not config.get('password'):raise ProviderError('Connect IMAP in Connections first.')
            return imap_provider.list_mail(config) if action=='sync' else imap_provider.mark_seen(config,args)
        except imap_provider.ImapError as e:raise ProviderError(str(e)) from None
    if action=='connect': return connect(provider,args)
    if action=='disconnect':
        config_path(provider).unlink(missing_ok=True)
        return {'connected':False,'configured':False}
    if action=='sync': return calendar_feed() if provider=='google-calendar' else list_mail(provider)
    if action=='seen' and provider!='google-calendar': return mark_seen(provider,args)
    raise ProviderError('Unsupported action.')

if __name__=='__main__':
    try:
        raw=sys.stdin.readline(16385)
        if len(raw)>16384: raise ProviderError('Request too large.')
        emit(dict(ok=True,**run(json.loads(raw))))
    except ProviderError as e: emit({'ok':False,'error':str(e)})
    except Exception: emit({'ok':False,'error':'Could not complete the connection request. Check setup and try again.'})
