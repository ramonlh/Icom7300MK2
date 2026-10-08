# SPDX-License-Identifier: GPL-2.0-only
"""Shared serial acquisition over TCP. Opens only a newly allocated PTY."""
import json
import base64
import os
import pty
import select
import socket
import subprocess
import sys
import termios
import tempfile
import time
import resource
import signal
from contextlib import contextmanager
from pathlib import Path

exe = sys.argv[1]
token = 'serial-offline-test-token'
env = dict(os.environ, QDOCK_LAN_TOKEN=token)


@contextmanager
def server(device, seconds=10, capture=None, fail_writes=False, allow_eeprom=False,
           allow_frequency=False, allow_register=False):
    args = [exe, '--serial', device, '--seconds', str(seconds), '--port', '0']
    if capture is not None:
        args += ['--capture', str(capture)]
    if allow_eeprom:
        args += ['--allow-eeprom-query']
    if allow_frequency:
        args += ['--allow-frequency-control']
    if allow_register:
        args += ['--allow-register-query']
    def limit_file_writes():
        signal.signal(signal.SIGXFSZ, signal.SIG_IGN)
    state_dir = tempfile.TemporaryDirectory()
    server_env = dict(env, XDG_STATE_HOME=state_dir.name)
    proc = subprocess.Popen(args, env=server_env, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                            preexec_fn=limit_file_writes if fail_writes else None)
    try:
        assert select.select([proc.stdout], [], [], 5)[0], 'startup timeout'
        line = proc.stdout.readline()
        assert line, proc.stderr.read().decode()
        yield proc, json.loads(line)['port']
    finally:
        proc.terminate()
        proc.communicate(timeout=5)
        state_dir.cleanup()


@contextmanager
def client(port):
    with socket.create_connection(('127.0.0.1', port), timeout=5) as sock:
        with sock.makefile('rb') as stream:
            sock.sendall((json.dumps({'message': 'hello', 'protocol': 'qdock-lan/1',
                                     'token': token}) + '\n').encode())
            welcome = json.loads(stream.readline())
            assert welcome['source'] == 'serial' and welcome['serialAvailable']
            assert not welcome['txControlAvailable']
            sock.sendall(b'{"message":"subscribe"}\n')
            yield sock, stream, json.loads(stream.readline())


def until(stream, kind):
    for _ in range(20):
        line = stream.readline()
        assert line, 'unexpected disconnect'
        message = json.loads(line)
        if message['message'] == kind:
            return message
    raise AssertionError('message not received: ' + kind)


XOR_KEY = bytes.fromhex('16 6c 14 e6 2e 91 0d 40 21 35 d5 40 13 03 e9 80')
SERIAL_BUFFERS = {}


def radio_reply(payload):
    encoded = bytes(value ^ XOR_KEY[index % 16] for index, value in enumerate(payload))
    crc_at = len(payload)
    return (b'\xab\xcd' + len(payload).to_bytes(2, 'little') + encoded
            + bytes((0xff ^ XOR_KEY[crc_at % 16],
                     0xff ^ XOR_KEY[(crc_at + 1) % 16])) + b'\xdc\xba')


def read_serial_frame(master):
    data = SERIAL_BUFFERS.setdefault(master, bytearray())
    deadline = time.monotonic() + 2
    while len(data) < 4 or len(data) < int.from_bytes(data[2:4], 'little') + 8:
        assert time.monotonic() < deadline, 'serial request timeout'
        if select.select([master], [], [], 0.1)[0]:
            data.extend(os.read(master, 4096))
    size = int.from_bytes(data[2:4], 'little')
    payload = bytes(data[4 + i] ^ XOR_KEY[i % 16] for i in range(size))
    del data[:size + 8]
    return payload


master, slave = pty.openpty()
serial_link_dir = tempfile.TemporaryDirectory()
serial_link = Path(serial_link_dir.name) / 'radio-serial'
serial_link.symlink_to(os.ttyname(slave))
try:
    with server(str(serial_link)) as (proc, port):
        attrs = termios.tcgetattr(slave)
        assert attrs[4] == attrs[5] == termios.B38400
        assert attrs[2] & termios.CSIZE == termios.CS8
        assert not attrs[2] & (termios.PARENB | termios.CSTOPB | termios.CRTSCTS)
        assert not attrs[0] & (termios.IXON | termios.IXOFF | termios.ISTRIP |
                               termios.INLCR | termios.IGNCR | termios.ICRNL)
        assert not attrs[3] & (termios.ICANON | termios.ECHO | termios.ISIG)
        with client(port) as (a, sa, first), client(port) as (b, sb, second):
            assert first['status'] == second['status'] == 'listening'
            assert first['portOpen'] and first['session'] == second['session']
            assert first['portState'] == 'open'
            assert first['portName'] == str(serial_link)
            assert first['nextSequence'] == '1'
            heartbeat = until(sa, 'serial_status')
            assert heartbeat['portState'] == 'open' and heartbeat['portOpen']
            assert heartbeat['portName'] == str(serial_link)
            assert heartbeat['status'] == 'listening'
            assert heartbeat['serialDisconnectCount'] == '0'
            assert heartbeat['serialRecoveryCount'] == '0'
            os.write(master, bytes.fromhex('b5 06'))
            os.write(master, bytes.fromhex('84 00 00 c5'))
            ea, eb = until(sa, 'event'), until(sb, 'event')
            assert ea == eb and ea['sequence'] == '1'
            assert ea['quality'] == 'candidate' and ea['event']['battery_volts'] == 7.88
            # One client sends a forbidden command: the other keeps receiving.
            a.sendall(b'{"message":"ptt"}\n')
            assert until(sa, 'error')['code'] == 'unsupported_message'
            os.write(master, bytes.fromhex('b5 06 84 00 00 c5'))
            assert until(sb, 'event')['sequence'] == '2'
            with client(port) as (_, sc, late):
                assert late['session'] == second['session'] and late['nextSequence'] == '3'
                os.write(master, bytes.fromhex('b5 05 00 00 00 00'))
                assert until(sc, 'event') == until(sb, 'event')
            assert not select.select([master], [], [], 0)[0], 'unexpected serial output'
            os.close(master)
            master = None
            disconnected = until(sb, 'source_status')
            assert disconnected['status'] == 'reconnecting' and not disconnected['portOpen']
            assert disconnected['serialDisconnectCount'] == '1'
            assert disconnected['serialRecoveryCount'] == '0'
            assert proc.poll() is None, 'serial failure killed LAN service'
            b.sendall(b'{"message":"ping"}\n')
            assert until(sb, 'pong')['message'] == 'pong'

            os.close(slave)
            master, slave = pty.openpty()
            serial_link.unlink()
            serial_link.symlink_to(os.ttyname(slave))
            deadline = time.monotonic() + 10
            while time.monotonic() < deadline:
                message = json.loads(sb.readline())
                if (message.get('message') == 'source_status'
                        and message.get('status') == 'listening'
                        and message.get('portOpen')):
                    break
            else:
                raise AssertionError('serial source did not reconnect')
            assert message['session'] == second['session']
            assert message['serialDisconnectCount'] == '1'
            assert message['serialRecoveryCount'] == '1'
            os.write(master, bytes.fromhex('b5 06 84 00 00 c5'))
            recovered_event = until(sb, 'event')
            assert recovered_event['sequence'] == '4'
            with client(port) as (_, _, after):
                assert after['status'] == 'listening' and after['session'] == second['session']
finally:
    if master is not None:
        os.close(master)
    os.close(slave)
    serial_link_dir.cleanup()

# Active memory navigation is opt-in and must not close the LAN connection.
master, slave = pty.openpty()
try:
    with server(os.ttyname(slave), seconds=30, allow_frequency=True) as (proc, port):
        with client(port) as (sock, stream, _):
            sock.sendall(b'{"message":"set_mode","vfo":"A","mode":"FM"}\n')
            unknown_vfo = until(stream, 'vfo_status')
            assert unknown_vfo['status'] == 'error'
            assert unknown_vfo['error'] == 'active_vfo_unknown'
            assert not select.select([master], [], [], 0)[0], 'mode command toggled an unknown VFO'
            os.write(master, bytes.fromhex('b5 07 01 01 00 00'))
            selected = until(stream, 'display_state')
            assert selected['activeVfo'] == 'A'
            sock.sendall(b'{"message":"step_frequency","vfo":"A","direction":"up"}\n')
            rejected_step = until(stream, 'vfo_status')
            assert rejected_step['status'] == 'error'
            assert rejected_step['error'] == 'frequency_vfo_required'
            assert not select.select([master], [], [], 0)[0], 'frequency step bypassed VFO-mode check'
            sock.sendall(b'{"message":"memory_step","vfo":"A","direction":"up"}\n')
            assert until(stream, 'vfo_status')['status'] == 'starting'
            expected_keys = [11, 19]
            for expected in expected_keys:
                assert read_serial_frame(master) == bytes((1, 8, 2, 0, expected, 0))
            assert until(stream, 'vfo_status')['status'] in ('sent', 'complete')
            while True:
                status = until(stream, 'vfo_status')
                if status['status'] == 'complete':
                    break
            sock.sendall(b'{"message":"set_mode","vfo":"A","mode":"RAW"}\n')
            assert until(stream, 'vfo_status')['status'] == 'starting'
            expected_mode_keys = [10, 19, 1, 19, 3, 19, 10, 19,
                                  4, 19, 10, 19, 13, 19]
            for expected in expected_mode_keys:
                assert read_serial_frame(master) == bytes((1, 8, 2, 0, expected, 0))
            while True:
                status = until(stream, 'vfo_status')
                if status['status'] == 'complete':
                    break
            sock.sendall(b'{"message":"set_dual_watch","enabled":true}\n')
            assert until(stream, 'vfo_status')['status'] == 'starting'
            for expected in [10, 19, 5, 19, 9, 19, 10, 19,
                             1, 19, 10, 19, 13, 19]:
                assert read_serial_frame(master) == bytes((1, 8, 2, 0, expected, 0))
            while until(stream, 'vfo_status')['status'] != 'complete':
                pass
            sock.sendall(b'{"message":"set_squelch","level":7}\n')
            assert until(stream, 'vfo_status')['status'] == 'starting'
            for expected in [10, 19, 6, 19, 1, 19, 10, 19,
                             7, 19, 10, 19, 13, 19]:
                assert read_serial_frame(master) == bytes((1, 8, 2, 0, expected, 0))
            while until(stream, 'vfo_status')['status'] != 'complete':
                pass
            sock.sendall(b'{"message":"set_vox","level":5}\n')
            assert until(stream, 'vfo_status')['status'] == 'starting'
            for expected in [10, 19, 5, 19, 7, 19, 10, 19,
                             5, 19, 10, 19, 13, 19]:
                assert read_serial_frame(master) == bytes((1, 8, 2, 0, expected, 0))
            while until(stream, 'vfo_status')['status'] != 'complete':
                pass
            sock.sendall(b'{"message":"set_menu","menu":29,"value":3,"control":"tx_timeout"}\n')
            assert until(stream, 'vfo_status')['status'] == 'starting'
            for expected in [10, 19, 2, 19, 9, 19, 10, 19,
                             3, 19, 10, 19, 13, 19]:
                assert read_serial_frame(master) == bytes((1, 8, 2, 0, expected, 0))
            while until(stream, 'vfo_status')['status'] != 'complete':
                pass
            sock.sendall(b'{"message":"set_menu","menu":29,"value":10,"control":"tx_timeout"}\n')
            assert until(stream, 'vfo_status')['status'] == 'starting'
            for expected in [10, 19, 2, 19, 9, 19, 10, 19,
                             1, 19, 0, 19, 10, 19, 13, 19]:
                assert read_serial_frame(master) == bytes((1, 8, 2, 0, expected, 0))
            while until(stream, 'vfo_status')['status'] != 'complete':
                pass
            sock.sendall(b'{"message":"set_menu","menu":8,"value":60000,"control":"repeater_offset"}\n')
            assert until(stream, 'vfo_status')['status'] == 'starting'
            for expected in [10, 19, 8, 19, 10, 19,
                             0, 19, 0, 19, 0, 19, 6, 19, 0, 19, 0, 19,
                             10, 19, 13, 19]:
                assert read_serial_frame(master) == bytes((1, 8, 2, 0, expected, 0))
            while until(stream, 'vfo_status')['status'] != 'complete':
                pass
            sock.sendall(b'{"message":"set_menu","menu":8,"value":60001,"control":"invalid_offset"}\n')
            invalid = until(stream, 'vfo_status')
            assert invalid['status'] == 'error' and invalid['error'] == 'menu_unavailable'
            assert proc.poll() is None, 'memory step killed LAN service'
            sock.sendall(b'{"message":"ping"}\n')
            assert until(stream, 'pong')['message'] == 'pong'
finally:
    os.close(master)
    os.close(slave)

# Register telemetry no longer polls the synthesizer frequency registers.
master, slave = pty.openpty()
try:
    with server(os.ttyname(slave), seconds=10, allow_register=True) as (_, port):
        with client(port):
            time.sleep(2.5)
            assert not select.select([master], [], [], 0)[0], 'unexpected 2 s internal-frequency query'
            assert select.select([master], [], [], 2)[0], 'diagnostic register query not sent'
            request = read_serial_frame(master)
            assert request[:2] == bytes.fromhex('51 08')
            count = request[4]
            addresses = [request[6 + index * 2] for index in range(count)]
            assert count == 46
            assert 0x38 not in addresses and 0x39 not in addresses
            assert 0x4d not in addresses and 0x4f not in addresses
            assert 0x63 not in addresses and 0x65 not in addresses
finally:
    os.close(master)
    os.close(slave)

# Duration closes the serial port; incomplete bytes remain visible in final stats.
master, slave = pty.openpty()
try:
    with server(os.ttyname(slave), 1) as (proc, port):
        with client(port) as (_, stream, _):
            os.write(master, bytes.fromhex('b5 06'))
            last_stats = None
            while True:
                message = json.loads(stream.readline())
                if message['message'] == 'stats':
                    last_stats = message
                if message.get('status') == 'ended':
                    assert not message['portOpen']
                    break
            assert last_stats['pending'] == '2' and last_stats['events'] == '0'
            assert proc.poll() is None
            assert not select.select([master], [], [], 0)[0], 'unexpected serial output'
finally:
    os.close(master)
    os.close(slave)

# The enabled EEPROM mode first reads only the block containing the squelch level
# and retains it for clients that connect afterwards.
master, slave = pty.openpty()
try:
    with server(os.ttyname(slave), seconds=10, allow_eeprom=True) as (_, port):
        hello = read_serial_frame(master)
        assert hello == bytes.fromhex('14 05 04 00 78 56 34 12')
        os.write(master, radio_reply(bytes.fromhex('15 05 04 00 54 45 53 54')))
        request = read_serial_frame(master)
        assert request[:4] == bytes.fromhex('1b 05 08 00')
        assert int.from_bytes(request[4:6], 'little') == 0x0e00
        assert request[6:8] == bytes((128, 0))
        block = bytearray(128)
        block[0x71] = 7
        payload = (bytes.fromhex('1c 05') + (132).to_bytes(2, 'little')
                   + (0x0e00).to_bytes(2, 'little') + bytes((128, 0)) + block)
        os.write(master, radio_reply(payload))
        time.sleep(0.1)
        with client(port) as (sock, stream, _):
            sock.sendall(b'{"message":"subscribe"}\n')
            messages = [json.loads(stream.readline()), json.loads(stream.readline())]
            display = next(message for message in messages
                           if message['message'] == 'display_state')
            assert display['squelchLevel'] == 7
        assert not select.select([master], [], [], 0)[0], 'unexpected extra serial output'
finally:
    os.close(master)
    os.close(slave)

# Explicitly requested full EEPROM reads use Hello + 64 ReadEeprom blocks and never write EEPROM.
master, slave = pty.openpty()
try:
    with server(os.ttyname(slave), seconds=10, allow_eeprom=True) as (_, port):
        with client(port) as (sock, stream, status):
            assert status['status'] == 'listening'
            sock.sendall(b'{"message":"read_eeprom"}\n')
            hello = read_serial_frame(master)
            assert hello == bytes.fromhex('14 05 04 00 78 56 34 12')
            os.write(master, radio_reply(bytes.fromhex('15 05 04 00 54 45 53 54')))
            expected = bytearray()
            for offset in range(0, 0x2000, 128):
                request = read_serial_frame(master)
                assert request[:4] == bytes.fromhex('1b 05 08 00')
                assert int.from_bytes(request[4:6], 'little') == offset
                assert request[6:8] == bytes((128, 0))
                assert request[8:12] == bytes.fromhex('78 56 34 12')
                block = bytes((offset // 128 + index) & 0xff for index in range(128))
                expected.extend(block)
                payload = (bytes.fromhex('1c 05') + (132).to_bytes(2, 'little')
                           + offset.to_bytes(2, 'little') + bytes((128, 0)) + block)
                os.write(master, radio_reply(payload))
            dump = None
            complete = None
            for _ in range(160):
                message = json.loads(stream.readline())
                if message['message'] == 'eeprom_dump':
                    dump = message
                if message['message'] == 'eeprom_status' and message['status'] == 'complete':
                    complete = message
                    break
            assert dump is not None and base64.b64decode(dump['dataBase64']) == expected
            assert dump['size'] == 0x2000 and complete['bytesRead'] == 0x2000
            assert len(dump['channels']) == 200
            sections = {row['section'] for row in dump['settings']}
            assert {'VFO y bandas', 'Radio FM', 'Ajustes generales', 'DTMF',
                    'Contactos DTMF', 'Calibración'} <= sections
            assert any(row['field'] == 'Clave AES personalizada'
                       and row['detail'] == 'Valor oculto' for row in dump['settings'])
            assert not select.select([master], [], [], 0)[0], 'unexpected extra serial output'
finally:
    os.close(master)
    os.close(slave)

# Shipped CLI consumes live observations and exits at the shared deadline.
master, slave = pty.openpty()
try:
    with server(os.ttyname(slave), 2) as (_, port):
        cli = Path(__file__).resolve().parents[1] / 'tools/lan_client.py'
        consumer = subprocess.Popen([sys.executable, str(cli), '--port', str(port)],
                                    env=env, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        try:
            assert select.select([consumer.stdout], [], [], 5)[0]
            assert json.loads(consumer.stdout.readline())['message'] == 'welcome'
            assert json.loads(consumer.stdout.readline())['status'] == 'listening'
            os.write(master, bytes.fromhex('b5 06 84 00 00 c5'))
            output, errors = consumer.communicate(timeout=5)
            assert consumer.returncode == 0, errors
            messages = [json.loads(line) for line in output.splitlines()]
            assert any(m['message'] == 'event' and m['source'] == 'serial' for m in messages)
            assert messages[-1]['status'] == 'ended'
        finally:
            if consumer.poll() is None:
                consumer.kill()
                consumer.communicate()
finally:
    os.close(master)
    os.close(slave)

# Opening failure keeps the LAN service alive while the serial path is retried.
with server('/nonexistent/qdock-test-port') as (proc, port):
    with client(port) as (_, _, status):
        assert status['status'] == 'reconnecting' and not status['portOpen']
        assert status['portState'] == 'reconnecting'
        assert status['portName'] == '/nonexistent/qdock-test-port'
    assert proc.poll() is None

# Raw capture includes noise and partial frames even before any LAN subscription.
with tempfile.TemporaryDirectory() as directory:
    capture = Path(directory) / 'received.raw'
    master, slave = pty.openpty()
    data = bytes.fromhex('42 43 b5 06 84 00 00 c4 b5')
    try:
        with server(os.ttyname(slave), 2, capture) as (_, port):
            os.write(master, data)
            deadline = time.monotonic() + 1
            while capture.stat().st_size != len(data) and time.monotonic() < deadline:
                time.sleep(0.01)
            assert capture.read_bytes() == data
            with client(port) as (_, stream, status):
                assert status['captureRequested'] and status['captureOpen']
                assert status['nextSequence'] == '2'
                last_stats = None
                while True:
                    message = json.loads(stream.readline())
                    if message['message'] == 'stats':
                        last_stats = message
                    if message.get('status') == 'ended':
                        assert not message['captureOpen']
                        break
                assert last_stats['bytes'] == last_stats['capturedBytes'] == str(len(data))
                assert last_stats['discarded'] == '2' and last_stats['pending'] == '1'
                assert capture.read_bytes() == data
                assert not select.select([master], [], [], 0)[0]
    finally:
        os.close(master)
        os.close(slave)

    # Existing evidence is never overwritten; serial configuration stays untouched.
    master, slave = pty.openpty()
    try:
        before = termios.tcgetattr(slave)
        with server(os.ttyname(slave), capture=capture) as (_, port):
            with client(port) as (_, _, status):
                assert status['status'] == 'error' and not status['portOpen']
                assert 'captura nueva' in status['error']
            assert capture.read_bytes() == data
            assert termios.tcgetattr(slave) == before
        with server(os.ttyname(slave), capture=Path(directory) / 'missing' / 'file') as (_, port):
            with client(port) as (_, _, status):
                assert status['status'] == 'error' and not status['portOpen']
            assert termios.tcgetattr(slave) == before
        with server(os.ttyname(slave), capture=Path(directory) / 'full.raw', fail_writes=True) as (proc, port):
            with client(port) as (_, stream, status):
                assert status['status'] == 'listening', status
                # Qt must create its serial lock file before simulating a full disk.
                resource.prlimit(proc.pid, resource.RLIMIT_FSIZE, (0, 0))
                os.write(master, data)
                error = until(stream, 'source_status')
                assert error['status'] == 'error' and not error['portOpen']
                assert not error['captureOpen'] and 'captura' in error['error']
                assert not select.select([master], [], [], 0)[0]
    finally:
        os.close(master)
        os.close(slave)
