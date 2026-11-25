#!/usr/bin/env python3
"""Runs sync_test.mjs: the streak bot's /api/sync and /api/unlink against a real SQLite database built from schema.sql.

macOS only, no Node needed: the worker runs in the system's JavaScriptCore shell (jsc), with a fake D1 whose queries
this script answers from an in-memory SQLite database. The JS side prints '@@{json}' requests and reads one JSON line
back. The worker and the test are copied to a temporary folder, so nothing is written beside them.

usage: python3 astragram/streak-bot/test/run_sync_test.py
"""
import hashlib
import json
import os
import shutil
import sqlite3
import subprocess
import hmac
import time
import urllib.parse
import sys
import tempfile

JSC = '/System/Library/Frameworks/JavaScriptCore.framework/Versions/Current/Helpers/jsc'
here = os.path.dirname(os.path.abspath(__file__))
bot = os.path.dirname(here)

db = sqlite3.connect(':memory:')
db.row_factory = sqlite3.Row
with open(os.path.join(bot, 'schema.sql')) as f:
    db.executescript(f.read())

# Devices A and B link the same account (100); C is another account (200). The tokens match sync_test.mjs.
TOKENS = {'A': 'a' * 48, 'B': 'b' * 48, 'C': 'c' * 48}
for name, token in TOKENS.items():
    owner = 100 if name != 'C' else 200
    db.execute('INSERT INTO owners (token_hash, tg_id, name, created_at) VALUES (?, ?, ?, 0)',
               (hashlib.sha256(token.encode()).hexdigest(), owner, 'Owner' + name))
db.commit()


def handle(req):
    op = req['op']
    if op == 'sha256':
        return hashlib.sha256(bytes(req['bytes'])).hexdigest()
    if op == 'hmac':
        return list(hmac.new(bytes(req['key']), bytes(req['bytes']), hashlib.sha256).digest())
    if op == 'webappdata':
        # Signed the way Telegram's documentation describes (bot token 'x', as in the test env).
        fields = {'auth_date': str(int(time.time()) - req.get('age', 0)), 'query_id': 'AAE',
                  'user': json.dumps({'id': req['id'], 'first_name': 'Тест'}, ensure_ascii=False, separators=(',', ':'))}
        check = '\n'.join(f'{k}={v}' for k, v in sorted(fields.items()))
        secret = hmac.new(b'WebAppData', b'x', hashlib.sha256).digest()
        fields['hash'] = hmac.new(secret, check.encode(), hashlib.sha256).hexdigest()
        if req.get('forge'):
            fields['user'] = fields['user'].replace(str(req['id']), str(req['forge']))
        return urllib.parse.urlencode(fields)
    if op == 'reset':
        # The server refuses a sync within 20 s of the last one.
        db.execute('UPDATE owners SET last_sync = 0')
        db.commit()
        return True
    if op == 'query':
        rows = [dict(r) for r in db.execute(req['sql'], req.get('args', [])).fetchall()]
        db.commit()
        return rows
    if op in ('first', 'all', 'run'):
        cur = db.execute(req['sql'], req['args'])
        rows = [dict(r) for r in cur.fetchall()]
        db.commit()
        if op == 'first':
            return rows[0] if rows else None
        if op == 'all':
            return {'results': rows}
        return {'meta': {'last_row_id': cur.lastrowid, 'changes': cur.rowcount}}
    if op == 'batch':
        out = []
        for s in req['statements']:
            cur = db.execute(s['sql'], s['args'])
            out.append({'results': [dict(r) for r in cur.fetchall()]})
        db.commit()
        return out
    raise SystemExit('unknown op ' + op)


with tempfile.TemporaryDirectory() as work:
    shutil.copy(os.path.join(bot, 'worker.js'), os.path.join(work, 'worker.mjs'))
    shutil.copy(os.path.join(here, 'sync_test.mjs'), os.path.join(work, 'sync_test.mjs'))
    proc = subprocess.Popen([JSC, '-m', os.path.join(work, 'sync_test.mjs')], cwd=work, stdin=subprocess.PIPE,
                            stdout=subprocess.PIPE, text=True, bufsize=1)
    failed = False
    for line in proc.stdout:
        if line.startswith('@@'):
            proc.stdin.write(json.dumps(handle(json.loads(line[2:]))) + '\n')
            proc.stdin.flush()
        else:
            sys.stdout.write(line)
            if line.startswith('FAIL') or line.startswith('Exception'):
                failed = True
    proc.wait()
sys.exit(1 if failed or proc.returncode else 0)
