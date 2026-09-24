# SPDX-License-Identifier: GPL-2.0-only
"""Offline menu firmware emulator: only a fresh PTY, never a physical radio."""
import binascii
import json
import os
import pty
import select
import socket
import subprocess
import sys
import threading
import tempfile
import time

KEY = bytes.fromhex('16 6c 14 e6 2e 91 0d 40 21 35 d5 40 13 03 e9 80')
TOKEN = 'tones-offline-test-token'


def ui(kind, x=0, line=0, text='', field=None):
    data = text.encode('ascii')
    return bytes((0xb5, kind, x, line, 8 if kind == 0 else 0,
                  len(data) if field is None else field)) + data


class Radio:
    def __init__(self, fd):
        self.fd = fd
        self.done = False
        self.error = None
        self.menu = None
        self.edit = False
        self.digits = ''
        self.selection = 0
        self.values = {3: 0, 4: 9, 5: 105, 6: 0}
        self.keys = []
        self.commits = []
        self.silent = False
        self.ignore_commit = False
        self.tx = False
        self.vfo = 'A'

    def main(self):
        os.write(self.fd, ui(5, 1, 7) + ui(7, 1 if self.vfo == 'A' else 5, 1)
                 + ui(1, 2, 1, 'F6') + ui(1, 36, 1, '145.67500')
                 + ui(1, 2, 5, 'M2') + ui(3, 32, 4, '435.500')
                 + ui(1, 113, 5, '00'))

    def draw(self):
        if self.silent:
            return
        if self.menu is None:
            self.main()
            return
        names = {3: 'RxDCS', 4: 'RxCTCS', 5: 'TxDCS', 6: 'TxCTCS'}
        if self.menu not in names:
            return
        value = self.selection if self.edit else self.values[self.menu]
        # Independent known vectors from the firmware tables, including limits.
        labels = {0: 'OFF'}
        if self.menu % 2 == 0:
            labels.update({1: '67.0Hz', 9: '88.5Hz', 50: '254.1Hz'})
        else:
            labels.update({1: 'D023N', 104: 'D754N', 105: 'D023I', 208: 'D754I'})
        text = labels.get(value, 'invalid')
        frame = (ui(5, 1, 7) + ui(0, 0, 0, 'adjacent')
                 + ui(0, 0, 2, names[self.menu]) + ui(0, 64, 2, text)
                 + ui(1, 105, 0, str(value)))
        # Exercise incremental parsing with split UI frames.
        os.write(self.fd, frame[:7])
        os.write(self.fd, frame[7:])

    def key(self, key):
        self.keys.append(key)
        assert key not in (16, 15), 'unexpected PTT/F key'
        if key == 19:
            return
        if key == 13:
            if self.edit:
                self.edit = False
            else:
                self.menu = None
            self.digits = ''
        elif key == 10:
            if self.menu is None:
                self.menu = 3
            elif not self.edit:
                self.edit = True
                self.selection = self.values.get(self.menu, 0)
            else:
                self.commits.append((self.menu, self.selection))
                if not self.ignore_commit:
                    self.values[self.menu] = self.selection
                    if self.selection:
                        other = self.menu + 1 if self.menu % 2 else self.menu - 1
                        self.values[other] = 0
                self.edit = False
            self.digits = ''
        elif 0 <= key <= 9:
            self.digits += str(key)
            if self.edit:
                self.selection = int(self.digits)
                width = 2 if self.menu % 2 == 0 else 3
                if len(self.digits) == width:
                    self.digits = ''
            elif self.menu is not None:
                if int(self.digits) > 0:
                    self.menu = int(self.digits)
                if len(self.digits) == 2:
                    self.digits = ''
        else:
            raise AssertionError(f'unexpected key {key}')
        self.draw()

    def run(self):
        buffer = bytearray()
        last_state = 0
        try:
            while not self.done:
                if time.monotonic() - last_state > 0.25:
                    os.write(self.fd, ui(6, 1 if self.tx else 2, field=200))
                    last_state = time.monotonic()
                if select.select([self.fd], [], [], 0.02)[0]:
                    buffer.extend(os.read(self.fd, 4096))
                while len(buffer) >= 14:
                    frame = bytes(buffer[:14])
                    del buffer[:14]
                    assert frame[:4] == bytes.fromhex('ab cd 06 00')
                    assert frame[-2:] == bytes.fromhex('dc ba')
                    payload = bytes(v ^ KEY[i] for i, v in enumerate(frame[4:12]))
                    assert payload[:4] == bytes.fromhex('01 08 02 00')
                    assert payload[5] == 0
                    assert int.from_bytes(payload[6:], 'little') == binascii.crc_hqx(payload[:6], 0)
                    self.key(payload[4])
        except BaseException as error:
            self.error = error


master, slave = pty.openpty()
server_log = tempfile.TemporaryFile()
proc = subprocess.Popen([sys.argv[1], '--serial', os.ttyname(slave), '--port', '0',
                         '--seconds', '180', '--allow-frequency-control'],
                        env=dict(os.environ, QDOCK_LAN_TOKEN=TOKEN),
                        stdout=subprocess.PIPE, stderr=server_log)
radio = Radio(master)
thread = threading.Thread(target=radio.run)
sock = None
try:
    assert select.select([proc.stdout], [], [], 3)[0], 'server failed to start'
    startup = proc.stdout.readline()
    if not startup:
        server_log.seek(0)
        raise AssertionError(server_log.read().decode())
    port = json.loads(startup)['port']
    sock = socket.create_connection(('127.0.0.1', port), timeout=25)
    stream = sock.makefile('rb')

    def send(**obj):
        sock.sendall(json.dumps(obj).encode() + b'\n')

    def until(kind, **fields):
        deadline = time.monotonic() + 25
        while time.monotonic() < deadline:
            assert radio.error is None, radio.error
            line = stream.readline()
            assert line, 'unexpected disconnect'
            obj = json.loads(line)
            if kind == 'tone_state' and obj['message'] == 'tone_status' and obj.get('status') in ('error', 'rejected'):
                raise AssertionError(f'{obj}; keys={radio.keys}; values={radio.values}')
            if obj['message'] == kind and all(obj.get(k) == v for k, v in fields.items()):
                return obj
        raise AssertionError(f'timeout: {kind} {fields}')

    send(message='hello', protocol='qdock-lan/1', token=TOKEN)
    assert until('welcome')['toneControlAvailable']
    send(message='subscribe')
    until('source_status')
    thread.start()
    radio.main()
    until('display_state', activeVfo='A')
    until('event')
    # Strict validation and inactive-VFO rejection, without any serial write.
    for bad in ({'type': 1, 'index': 50}, {'type': 2, 'index': 104},
                {'type': 4, 'index': 0}, {'type': 0, 'index': 1},
                {'type': 1.5, 'index': 0}, {'type': '1', 'index': 0}):
        send(message='set_tone', vfo='A', direction='RX', **bad)
        until('tone_status', status='rejected')
    send(message='read_tones', vfo='B')
    until('tone_status', status='rejected')
    assert not radio.keys

    send(message='read_tones', vfo='A')
    until('tone_status', status='starting')
    send(message='set_mode', vfo='A', mode='AM')
    until('vfo_status', status='error')
    state = until('tone_state')
    assert state['rx'] == {'type': 1, 'index': 8, 'text': '88.5 Hz'}
    assert state['tx'] == {'type': 3, 'index': 0, 'text': 'D023I'}
    until('tone_status', status='complete')
    assert not radio.commits, 'reading must never accept a setting'

    radio.vfo = 'B'
    radio.main()
    until('display_state', activeVfo='B')
    send(message='read_tones', vfo='B')
    state = until('tone_state')
    assert state['vfo'] == 'B' and state['memory'] == 'M2' and state['frequency'] == '435.50000'
    until('tone_status', status='complete')
    radio.vfo = 'A'
    radio.main()
    until('display_state', activeVfo='A')

    for direction, tone_type, index, label in (
        ('TX', 1, 49, '254.1 Hz'), ('RX', 2, 103, 'D754N'),
        ('RX', 3, 103, 'D754I'), ('RX', 0, 0, 'OFF'), ('TX', 0, 0, 'OFF')):
        send(message='set_tone', vfo='A', direction=direction, type=tone_type, index=index)
        state = until('tone_state')
        assert state[direction.lower()] == {'type': tone_type, 'index': index, 'text': label}, state
        until('tone_status', status='complete')

    radio.ignore_commit = True
    send(message='set_tone', vfo='A', direction='RX', type=1, index=0)
    error = until('tone_status', status='error')['error']
    assert 'distinto' in error, error
    radio.ignore_commit = False

    radio.silent = True
    before = len(radio.commits)
    send(message='set_tone', vfo='A', direction='RX', type=1, index=0)
    assert 'timeout' in until('tone_status', status='error')['error']
    assert len(radio.commits) == before, 'no writes without menu confirmation'
    radio.silent = False
    radio.main()
    until('display_state', activeVfo='A')

    radio.tx = True
    time.sleep(0.3)
    send(message='read_tones', vfo='A')
    until('tone_status', status='rejected', error='tone_while_transmitting')
    radio.tx = False
    time.sleep(0.3)
    radio.main()
    send(message='set_tone', vfo='A', direction='RX', type=1, index=0)
    until('tone_status', status='starting')
    before = len(radio.commits)
    stream.close()
    sock.close()
    sock = None
    time.sleep(1)
    assert len(radio.commits) == before, 'disconnect must cancel before commit'
    assert radio.error is None, radio.error
finally:
    radio.done = True
    if thread.is_alive():
        thread.join(2)
    if sock:
        sock.close()
    proc.terminate()
    proc.communicate(timeout=3)
    server_log.close()
    os.close(master)
    os.close(slave)

master, slave = pty.openpty()
with tempfile.TemporaryFile() as log:
    proc = subprocess.Popen([sys.argv[1], '--serial', os.ttyname(slave), '--port', '0', '--seconds', '10'],
                            env=dict(os.environ, QDOCK_LAN_TOKEN=TOKEN),
                            stdout=subprocess.PIPE, stderr=log)
    try:
        assert select.select([proc.stdout], [], [], 3)[0]
        port = json.loads(proc.stdout.readline())['port']
        with socket.create_connection(('127.0.0.1', port), timeout=3) as client:
            with client.makefile('rb') as incoming:
                def request(obj):
                    client.sendall(json.dumps(obj).encode() + b'\n')
                request({'message': 'hello', 'protocol': 'qdock-lan/1', 'token': TOKEN})
                assert not json.loads(incoming.readline())['toneControlAvailable']
                request({'message': 'subscribe'})
                request({'message': 'read_tones', 'vfo': 'A'})
                while True:
                    response = json.loads(incoming.readline())
                    if response['message'] == 'tone_status':
                        assert response['status'] == 'rejected'
                        assert response['error'] == 'radio_control_not_enabled'
                        break
                assert not select.select([master], [], [], 0.2)[0], 'read-only must remain silent'
    finally:
        proc.terminate()
        proc.communicate(timeout=3)
        os.close(master)
        os.close(slave)

print('Tone read/write/verification, guards and cancellation passed (PTY only).')
