#!/usr/bin/env python3
"""The other side of the chat for AstraGram's UI tests (Telegram/Tests/Sources/AstraGramTests.swift).

Runs on the host next to the iOS simulator and serves HTTP on 127.0.0.1:8765. It logs in to a test account on
Telegram's test servers with Telethon and, on request of the UI test, sends, edits and deletes messages and reports
what this side sees of the app's account. It also collects the test's screenshots and results into OUT_DIR.

usage: peer_controller.py OUT_DIR   (TELEGRAM_API_ID and TELEGRAM_API_HASH in the environment)
"""
import asyncio
import json
import os
import random
import struct
import sys
import time
import zlib

from aiohttp import web
from telethon import TelegramClient, events, functions, types, errors
from telethon.sessions import MemorySession

TEST_DC = 2
TEST_DC_IP = '149.154.167.40'
TEST_DC_PORT = 443
PEER_NAME = 'AstraPeer'

OUT_DIR = sys.argv[1] if len(sys.argv) > 1 else 'uitest-out'
API_ID = int(os.environ['TELEGRAM_API_ID'])
API_HASH = os.environ['TELEGRAM_API_HASH']

state = {
    'peer': None,          # TelegramClient of the peer account
    'app_phone': None,
    'app_user': None,      # InputUser of the app's account, as seen by the peer
    'typing': 0,
    'results': [],
    'log': [],
}


def log(message):
    line = '{} {}'.format(time.strftime('%H:%M:%S'), message)
    print(line, flush=True)
    state['log'].append(line)
    with open(os.path.join(OUT_DIR, 'controller.log'), 'a', encoding='utf-8') as f:
        f.write(line + '\n')


def random_test_phone():
    return '99966{}{:04d}'.format(TEST_DC, random.randint(0, 9999))


def test_code():
    return str(TEST_DC) * 5


async def login(phone, first_name):
    """Logs in to (signing up if needed) a test account. Returns the client, or None if the account cannot be used
    (for example someone set a cloud password on this shared test number)."""
    client = TelegramClient(MemorySession(), API_ID, API_HASH)
    client.session.set_dc(TEST_DC, TEST_DC_IP, TEST_DC_PORT)
    await client.connect()
    try:
        await client.send_code_request(phone)
        try:
            await client.sign_in(phone, code=test_code())
        except errors.PhoneNumberUnoccupiedError:
            await client.sign_up(test_code(), first_name=first_name)
    except errors.SessionPasswordNeededError:
        log('{}: has a cloud password, skipping'.format(phone))
        await client.disconnect()
        return None
    except errors.FloodWaitError as e:
        log('{}: flood wait {}s, skipping'.format(phone, e.seconds))
        await client.disconnect()
        return None
    except Exception as e:  # noqa: BLE001 - any failure means "try another number"
        log('{}: login failed: {!r}'.format(phone, e))
        await client.disconnect()
        return None
    return client


async def setup(request):
    if state['peer'] is not None:
        return web.json_response({'app_phone': state['app_phone'], 'code': test_code(), 'peer_name': PEER_NAME})

    # The peer account.
    for _ in range(10):
        peer = await login(random_test_phone(), PEER_NAME)
        if peer is not None:
            break
    else:
        return web.json_response({'error': 'could not log in the peer account'})
    await peer(functions.account.UpdateProfileRequest(first_name=PEER_NAME, last_name=''))
    me = await peer.get_me()
    log('peer account: id {}'.format(me.id))

    @peer.on(events.Raw(types.UpdateUserTyping))
    async def on_typing(update):
        if state['app_user'] is not None and update.user_id == state['app_user'].user_id:
            state['typing'] += 1
            log('typing update: {}'.format(type(update.action).__name__))

    # The app's account: signed up here (so the app only has to log in), checked to have no cloud password, then
    # logged out again so this session does nothing on its behalf.
    for _ in range(10):
        phone = random_test_phone()
        client = await login(phone, 'AstraTester')
        if client is not None:
            await client.log_out()
            state['app_phone'] = phone
            break
    else:
        return web.json_response({'error': 'could not prepare the app account'})
    log('app account phone: {}'.format(state['app_phone']))

    state['peer'] = peer
    return web.json_response({'app_phone': state['app_phone'], 'code': test_code(), 'peer_name': PEER_NAME})


async def start_chat(request):
    peer = state['peer']
    result = await peer(functions.contacts.ImportContactsRequest(contacts=[
        types.InputPhoneContact(client_id=random.randint(1, 1 << 30), phone=state['app_phone'], first_name='App', last_name='')
    ]))
    if not result.users:
        log('start_chat: the app account was not found by phone')
        return web.json_response({'error': 'app account not found'})
    user = result.users[0]
    state['app_user'] = types.InputUser(user_id=user.id, access_hash=user.access_hash)
    message = await peer.send_message(state['app_user'], 'hello from the peer')
    log('start_chat: app user id {}, sent {}'.format(user.id, message.id))
    return web.json_response({'ok': True, 'id': message.id})


async def send_text(request):
    message = await state['peer'].send_message(state['app_user'], request.query['text'])
    log('sent "{}" as {}'.format(request.query['text'], message.id))
    return web.json_response({'id': message.id})


def tiny_png(width=320, height=240):
    rows = b''.join(
        b'\x00' + b''.join(bytes([x * 255 // width, y * 255 // height, 160]) for x in range(width))
        for y in range(height))

    def chunk(kind, data):
        return struct.pack('>I', len(data)) + kind + data + struct.pack('>I', zlib.crc32(kind + data) & 0xffffffff)

    return (b'\x89PNG\r\n\x1a\n' + chunk(b'IHDR', struct.pack('>IIBBBBB', width, height, 8, 2, 0, 0, 0))
            + chunk(b'IDAT', zlib.compress(rows, 9)) + chunk(b'IEND', b''))


async def send_view_once(request):
    peer = state['peer']
    path = os.path.join(OUT_DIR, 'view-once.png')
    with open(path, 'wb') as f:
        f.write(tiny_png())
    uploaded = await peer.upload_file(path)
    # A TTL of 0x7FFFFFFF is how Telegram marks view-once media.
    media = types.InputMediaUploadedPhoto(file=uploaded, ttl_seconds=0x7FFFFFFF)
    message = await peer.send_file(state['app_user'], media)
    log('sent a view-once photo as {}'.format(message.id))
    return web.json_response({'id': message.id})


async def delete(request):
    message_id = int(request.query['id'])
    await state['peer'].delete_messages(state['app_user'], [message_id], revoke=True)
    log('deleted {}'.format(message_id))
    return web.json_response({'ok': True})


async def edit(request):
    message_id = int(request.query['id'])
    await state['peer'].edit_message(state['app_user'], message_id, request.query['text'])
    log('edited {} to "{}"'.format(message_id, request.query['text']))
    return web.json_response({'ok': True})


async def read_state(request):
    result = await state['peer'](functions.messages.GetPeerDialogsRequest(peers=[types.InputDialogPeer(peer=state['app_user'])]))
    value = result.dialogs[0].read_outbox_max_id if result.dialogs else -1
    log('read_outbox_max_id = {}'.format(value))
    return web.json_response({'read_outbox_max_id': value})


async def status(request):
    users = await state['peer'](functions.users.GetUsersRequest(id=[state['app_user']]))
    value = type(users[0].status).__name__ if users and users[0].status is not None else 'None'
    log('app account status: {}'.format(value))
    return web.json_response({'status': value})


async def reset_typing(request):
    state['typing'] = 0
    return web.json_response({'ok': True})


async def typing(request):
    return web.json_response({'count': state['typing']})


async def last_incoming(request):
    messages = await state['peer'].get_messages(state['app_user'], limit=5)
    for message in messages:
        if not message.out:
            return web.json_response({'id': message.id, 'text': message.message or ''})
    return web.json_response({'id': 0, 'text': ''})


async def message_state(request):
    message_id = int(request.query['id'])
    message = await state['peer'].get_messages(state['app_user'], ids=message_id)
    if message is None:
        return web.json_response({'exists': False})
    log('message {}: media_unread={}'.format(message_id, message.media_unread))
    return web.json_response({'exists': True, 'media_unread': bool(message.media_unread)})


async def log_handler(request):
    log('[test] ' + request.query.get('message', ''))
    return web.json_response({'ok': True})


async def screenshot(request):
    name = ''.join(c for c in request.query.get('name', 'shot') if c.isalnum() or c in '-_')
    data = await request.read()
    os.makedirs(os.path.join(OUT_DIR, 'screenshots'), exist_ok=True)
    with open(os.path.join(OUT_DIR, 'screenshots', name + '.png'), 'wb') as f:
        f.write(data)
    return web.json_response({'ok': True})


def write_report():
    lines = ['# AstraGram UI test', '']
    for result in state['results']:
        lines.append('- {} **{}**: {}'.format('PASS' if result['passed'] else 'FAIL', result['name'], result['detail']))
    with open(os.path.join(OUT_DIR, 'report.md'), 'w', encoding='utf-8') as f:
        f.write('\n'.join(lines) + '\n')
    with open(os.path.join(OUT_DIR, 'results.json'), 'w', encoding='utf-8') as f:
        json.dump(state['results'], f, indent=2)


async def result(request):
    state['results'].append({
        'name': request.query['name'],
        'passed': request.query.get('passed') == '1',
        'detail': request.query.get('detail', ''),
    })
    write_report()
    return web.json_response({'ok': True})


async def finish(request):
    write_report()
    log('finished')
    return web.json_response({'ok': True})


@web.middleware
async def errors_middleware(request, handler):
    try:
        return await handler(request)
    except Exception as e:  # noqa: BLE001 - report every failure to the test instead of a bare 500
        log('{} failed: {!r}'.format(request.path, e))
        return web.json_response({'error': repr(e)})


def main():
    os.makedirs(OUT_DIR, exist_ok=True)
    app = web.Application(middlewares=[errors_middleware], client_max_size=64 * 1024 * 1024)
    app.add_routes([
        web.get('/setup', setup),
        web.get('/start_chat', start_chat),
        web.get('/send_text', send_text),
        web.get('/send_view_once', send_view_once),
        web.get('/delete', delete),
        web.get('/edit', edit),
        web.get('/read_state', read_state),
        web.get('/status', status),
        web.get('/reset_typing', reset_typing),
        web.get('/typing', typing),
        web.get('/last_incoming', last_incoming),
        web.get('/message', message_state),
        web.get('/log', log_handler),
        web.post('/screenshot', screenshot),
        web.get('/result', result),
        web.get('/finish', finish),
    ])
    log('listening on 127.0.0.1:8765')
    web.run_app(app, host='127.0.0.1', port=8765, print=None)


if __name__ == '__main__':
    main()
