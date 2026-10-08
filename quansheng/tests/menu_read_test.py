# SPDX-License-Identifier: GPL-2.0-only
"""Offline menu readback emulator using a PTY, never a physical radio."""
import binascii
import json
import os
import pty
import select
import socket
import subprocess
import sys
import tempfile
import threading
import time

KEY = bytes.fromhex('16 6c 14 e6 2e 91 0d 40 21 35 d5 40 13 03 e9 80')
TOKEN = 'menu-read-offline-test-token'


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
        self.digits = ''
        self.keys = []

    def draw(self):
        if self.menu is None:
            os.write(self.fd, ui(5, 1, 7) + ui(7, 1, 1) + ui(1, 36, 1, '145.67500'))
            return
        title, value = {1: ('Step', '0.01 kHz'), 2: ('TxPwr', 'HIGH'),
                        7: ('TxODir', '+'), 8: ('TxOffs', '0.60000')}.get(
            self.menu, ('Unknown', ''))
        screen = ui(5, 1, 7) + ui(0, 0, 2, title) + ui(0, 64, 2, value)
        if self.menu == 8:
            screen += ui(0, 112, 2, 'MHz')
        os.write(self.fd, screen)

    def key(self, key):
        self.keys.append(key)
        if key == 19:
            return
        if key == 13:
            self.menu = None
            self.digits = ''
        elif key == 10:
            self.menu = 0
            self.digits = ''
        elif 0 <= key <= 9:
            self.digits += str(key)
            value = int(self.digits)
            if 1 <= value <= 61:
                self.menu = value
        else:
            raise AssertionError(f'unexpected key {key}')
        self.draw()

    def run(self):
        buffer = bytearray()
        last_state = 0
        try:
            while not self.done:
                if time.monotonic() - last_state > .2:
                    os.write(self.fd, ui(6, 2, field=200))
                    last_state = time.monotonic()
                if select.select([self.fd], [], [], .02)[0]:
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
log = tempfile.TemporaryFile()
proc = subprocess.Popen([sys.argv[1], '--serial', os.ttyname(slave), '--port', '0',
                         '--seconds', '60', '--allow-frequency-control'],
                        env=dict(os.environ, QDOCK_LAN_TOKEN=TOKEN),
                        stdout=subprocess.PIPE, stderr=log)
radio = Radio(master)
thread = threading.Thread(target=radio.run)
sock = None
try:
    assert select.select([proc.stdout], [], [], 3)[0], 'server did not start'
    startup = proc.stdout.readline()
    if not startup:
        log.seek(0)
        raise AssertionError(log.read().decode())
    port = json.loads(startup)['port']
    sock = socket.create_connection(('127.0.0.1', port), timeout=10)
    stream = sock.makefile('rb')

    def send(**obj):
        sock.sendall(json.dumps(obj).encode() + b'\n')

    def until(kind, **fields):
        deadline = time.monotonic() + 15
        while time.monotonic() < deadline:
            assert radio.error is None, radio.error
            line = stream.readline()
            assert line, 'unexpected disconnect'
            obj = json.loads(line)
            if obj.get('message') == kind and all(obj.get(k) == v for k, v in fields.items()):
                return obj
        raise AssertionError(f'timeout: {kind} {fields}')

    send(message='hello', protocol='qdock-lan/1', token=TOKEN)
    assert until('welcome')['menuReadAvailable']
    send(message='subscribe')
    until('source_status')
    thread.start()
    radio.draw()
    until('display_state')
    send(message='read_menu_values', menus=[1, 2, 7, 8])
    until('menu_read_status', status='starting')
    one = until('menu_value', menu=1)
    two = until('menu_value', menu=2)
    assert one['confirmed'] and one['title'] == 'Step' and one['displayValue'] == '0.01 kHz'
    assert two['confirmed'] and two['title'] == 'TxPwr' and two['displayValue'] == 'HIGH'
    direction = until('menu_value', menu=7)
    offset = until('menu_value', menu=8)
    assert direction['confirmed'] and direction['title'] == 'TxODir' and direction['displayValue'] == '+'
    assert offset['confirmed'] and offset['title'] == 'TxOffs' and offset['displayValue'] == '0.60000 MHz'
    until('menu_read_status', status='complete')
    assert radio.keys.count(10) == 4, f'reading should only open each menu once: {radio.keys}'
finally:
    if sock:
        sock.close()
    radio.done = True
    if thread.is_alive():
        thread.join(timeout=2)
    proc.terminate()
    try:
        proc.wait(timeout=3)
    except subprocess.TimeoutExpired:
        proc.kill()
        proc.wait(timeout=3)
