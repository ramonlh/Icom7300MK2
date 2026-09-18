# SPDX-License-Identifier: GPL-2.0-only
"""PTT lifecycle against loopback TCP and a fresh PTY. Never opens a radio."""
import binascii
from contextlib import contextmanager
import json
import os
import pty
import select
import socket
import subprocess
import sys
import time

EXE = sys.argv[1]
TOKEN = 'ptt-offline-test-token'
KEY = bytes.fromhex('16 6c 14 e6 2e 91 0d 40 21 35 d5 40 13 03 e9 80')


class Client:
    def __init__(self, port, enabled=True, auth=True):
        self.sock = socket.create_connection(('127.0.0.1', port), timeout=3)
        self.stream = self.sock.makefile('rb')
        if auth:
            self.send(message='hello', protocol='qdock-lan/1', token=TOKEN)
            assert self.until('welcome')['txControlAvailable'] == enabled
            self.send(message='subscribe')
            self.until('source_status')

    def send(self, **obj):
        self.sock.sendall(json.dumps(obj).encode() + b'\n')

    def ptt(self, action, id='test'):
        self.send(message='ptt', action=action, id=id)

    def until(self, kind, **fields):
        deadline = time.monotonic() + 4
        while True:
            assert time.monotonic() < deadline, f'missing {kind}: {fields}'
            line = self.stream.readline()
            assert line, 'unexpected disconnect'
            obj = json.loads(line)
            if obj['message'] == kind and all(obj.get(k) == v for k, v in fields.items()):
                return obj

    def close(self):
        self.stream.close()
        self.sock.close()


class Serial:
    def __init__(self, fd):
        self.fd = fd
        self.buffer = bytearray()

    def state(self, tx=False):
        os.write(self.fd, bytes((0xb5, 6, 1 if tx else 2, 0, 0, 200)))

    def key(self, expected, timeout=2):
        deadline = time.monotonic() + timeout
        while len(self.buffer) < 14:
            assert time.monotonic() < deadline, 'missing PTT frame'
            if select.select([self.fd], [], [], 0.05)[0]:
                self.buffer.extend(os.read(self.fd, 4096))
        frame = self.buffer[:14]
        del self.buffer[:14]
        assert frame[:4] == bytes.fromhex('ab cd 06 00')
        assert frame[-2:] == bytes.fromhex('dc ba')
        decoded = bytes(v ^ KEY[i] for i, v in enumerate(frame[4:12]))
        assert decoded[:4] == bytes.fromhex('01 08 02 00')
        assert int.from_bytes(decoded[6:], 'little') == binascii.crc_hqx(decoded[:6], 0)
        assert decoded[5] == 0
        assert decoded[4] in expected, decoded.hex()
        return decoded[4]

    def released(self):
        for _ in range(100):
            if self.key((16, 19)) == 19:
                self.silent()
                return
        raise AssertionError('no release')

    def silent(self):
        assert not self.buffer, self.buffer.hex()
        assert not select.select([self.fd], [], [], 0.12)[0], 'unexpected serial output'


@contextmanager
def server(enabled=True, max_seconds=60, extra=()):
    master, slave = pty.openpty()
    args = [EXE, '--serial', os.ttyname(slave), '--seconds', '30', '--port', '0']
    if enabled:
        args += ['--allow-ptt', '--ptt-max-seconds', str(max_seconds)]
    proc = subprocess.Popen(args + list(extra), env=dict(os.environ, QDOCK_LAN_TOKEN=TOKEN),
                            stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    clients = []
    serial = Serial(master)
    try:
        assert select.select([proc.stdout], [], [], 3)[0]
        line = proc.stdout.readline()
        assert line, proc.stderr.read().decode()
        port = json.loads(line)['port']
        def connect(auth=True):
            client = Client(port, enabled, auth)
            clients.append(client)
            return client
        yield proc, serial, connect
    finally:
        for client in clients:
            client.close()
        proc.terminate()
        proc.communicate(timeout=3)
        if serial.fd >= 0:
            os.close(master)
        os.close(slave)


def observed(serial, client, tx=False):
    serial.state(tx)
    client.until('event')


with server(enabled=False) as (_, serial, connect):
    c = connect()
    observed(serial, c)
    c.ptt('press')
    assert c.until('ptt_status')['error'] == 'ptt_not_enabled'
    serial.silent()

with server(extra=('--allow-frequency-control', '--allow-eeprom-query')) as (_, serial, connect):
    unauth = connect(auth=False)
    unauth.ptt('press')
    assert unauth.until('error')['code'] == 'protocol_mismatch'
    serial.silent()
    c, other = connect(), connect()
    c.ptt('press')
    assert c.until('ptt_status')['error'] == 'radio_state_stale'
    observed(serial, c, tx=True)
    c.ptt('press')
    assert c.until('ptt_status')['error'] == 'radio_already_transmitting'
    observed(serial, c)
    c.ptt('press')
    c.until('ptt_state', active=True)
    serial.key((16,))
    other.ptt('press', 'other')
    assert other.until('ptt_status')['error'] == 'ptt_busy'
    other.ptt('release')
    assert other.until('ptt_status')['error'] == 'ptt_not_owner'
    c.send(message='set_frequency', frequencyHz=145675000)
    assert 'transmitting' in c.until('frequency_status')['error']
    c.send(message='read_eeprom')
    assert c.until('eeprom_status')['error'] == 'radio_control_busy'
    c.ptt('release')
    c.until('ptt_state', active=False, reason='released')
    serial.released()

with server() as (_, serial, connect):
    c, other = connect(), connect()
    observed(serial, c)
    c.ptt('press')
    c.until('ptt_state', active=True)
    serial.key((16,))
    # Heartbeats extend only the current owner, not the total duration.
    for _ in range(7):
        time.sleep(0.25)
        c.ptt('keepalive')
    c.ptt('release')
    c.until('ptt_state', active=False, reason='released')
    serial.released()
    c.ptt('press', 'second')
    c.until('ptt_state', active=True, id='second')
    serial.key((16,))
    c.close()
    other.until('ptt_state', active=False, reason='client_disconnected')
    serial.released()

with server() as (_, serial, connect):
    c = connect()
    observed(serial, c)
    c.ptt('press')
    c.until('ptt_state', active=False, reason='lease_expired')
    serial.released()
    c.ptt('keepalive')
    assert c.until('ptt_status')['error'] == 'ptt_not_owner'
    serial.silent()
    # An old hold ID cannot refresh or release a later press.
    observed(serial, c)
    c.ptt('press', 'new')
    c.until('ptt_state', active=True, id='new')
    c.ptt('release')
    assert c.until('ptt_status')['error'] == 'ptt_not_owner'
    c.ptt('release', 'new')
    c.until('ptt_state', active=False, id='new')
    serial.released()

with server(max_seconds=1) as (_, serial, connect):
    c = connect()
    observed(serial, c)
    c.ptt('press')
    c.until('ptt_state', active=True)
    for _ in range(5):
        time.sleep(0.25)
        c.ptt('keepalive')
    c.until('ptt_state', active=False, reason='max_duration')
    serial.released()

with server() as (proc, serial, connect):
    c = connect()
    observed(serial, c)
    c.ptt('press')
    c.until('ptt_state', active=True)
    proc.terminate()
    proc.wait(timeout=3)
    serial.released()

with server() as (_, serial, connect):
    c = connect()
    observed(serial, c)
    c.ptt('press')
    c.until('ptt_state', active=True)
    c.sock.sendall(b'not-json\n')
    c.until('error', code='invalid_json')
    serial.released()

with server() as (_, serial, connect):
    c = connect()
    observed(serial, c)
    time.sleep(5.2)
    c.ptt('press')
    assert c.until('ptt_status')['error'] == 'radio_state_stale'
    serial.silent()

with server() as (_, serial, connect):
    c = connect()
    observed(serial, c)
    c.ptt('press')
    c.until('ptt_state', active=True)
    serial.key((16,))
    os.close(serial.fd)  # Simulate USB/serial disappearance, still only a PTY.
    serial.fd = -1
    c.until('source_status', status='error')
    c.ptt('press', 'after-error')
    assert c.until('ptt_status')['error'] == 'ptt_not_enabled'

print('PTT: framing/CRC, opt-in, authentication, ownership, release, heartbeat, expiry, maximum and shutdown passed')
