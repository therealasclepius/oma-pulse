#!/usr/bin/python3
"""Mark a HEY box posting read/unread and verify the remote state."""
import json
import os
import re
import subprocess
import sys

class MailError(Exception):
    pass

def run(args):
    try:
        result = subprocess.run(['hey', *args, '--json'], capture_output=True, text=True,
                                timeout=25, env={**os.environ, 'HEY_NONINTERACTIVE': '1'})
        response = json.loads(result.stdout)
    except (OSError, ValueError, subprocess.TimeoutExpired):
        raise MailError('HEY did not respond. Refresh to check the email before retrying.') from None
    if result.returncode or response.get('ok') is not True:
        if response.get('code') in ['auth', 'auth_required']:
            raise MailError('Sign in with hey auth login, then retry.')
        raise MailError('HEY could not update this email. Refresh and try again.')
    return response

def mark(payload):
    posting_id, account_id, seen = payload.get('id'), payload.get('account_id'), payload.get('seen')
    if not all(isinstance(v, str) and re.fullmatch(r'[1-9][0-9]*', v) for v in [posting_id, account_id]) or type(seen) is not bool:
        raise MailError('Refresh HEY to get a valid email and account.')
    run(['--account', account_id, 'seen' if seen else 'unseen', posting_id])
    # HEY reports success even for nonexistent IDs: read back the actual posting.
    cursor = None
    for _ in range(10):
        args = ['--account', account_id, 'box', 'view', 'imbox', '--limit', '50']
        if cursor: args += ['--page', cursor]
        response = run(args)
        data = response.get('data', {})
        for posting in data.get('postings', []):
            if str(posting.get('id')) == posting_id:
                if (posting.get('seen') is True) != seen:
                    raise MailError('HEY has not confirmed the change. Refresh before retrying.')
                return {'ok': True, 'id': posting_id, 'account_id': account_id, 'seen': seen}
        cursor = data.get('next_page')
        if not cursor: break
    raise MailError('Could not confirm this email’s read status. Refresh before retrying.')

def main():
    try:
        payload = json.loads(sys.stdin.read(4096))
        if not isinstance(payload, dict): raise MailError('Invalid email request.')
        result = mark(payload)
    except MailError as e: result = {'ok': False, 'error': str(e)}
    except Exception: result = {'ok': False, 'error': 'Could not update HEY. Please refresh and retry.'}
    print(json.dumps(result))

if __name__ == '__main__': main()
