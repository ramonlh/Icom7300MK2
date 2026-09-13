# SPDX-License-Identifier: GPL-2.0-only
"""Loopback integration, using real captures without opening any serial device."""
import concurrent.futures
import json
import os
from pathlib import Path
import select
import socket
import subprocess
import sys
import tempfile

server_exe, probe_exe = sys.argv[1:3]
root = Path(__file__).resolve().parents[1]
token = 'offline-test-token-123456'
env = dict(os.environ, QDOCK_LAN_TOKEN=token)


def send(sock, obj):
    sock.sendall(json.dumps(obj).encode() + b'\n')


def receive(stream):
    return json.loads(stream.readline())


with tempfile.TemporaryDirectory() as directory:
    path = Path(directory) / 'screen.raw'
    path.write_bytes(bytes.fromhex((root / 'tests/fixtures/radio-screen.hex').read_text()))
    proc = subprocess.Popen([server_exe, '--replay', str(path), '--port', '0'],
                            env=env, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    try:
        assert select.select([proc.stdout], [], [], 5)[0], 'server startup timeout'
        startup = proc.stdout.readline()
        assert startup, proc.stderr.read().decode()
        ready = json.loads(startup)
        port = ready['port']

        def connect():
            return socket.create_connection(('127.0.0.1', port), timeout=10)

        # Fragmented hello followed by coalesced requests, all on one TCP stream.
        with connect() as sock, sock.makefile('rb') as stream:
            hello = json.dumps({'message': 'hello', 'protocol': 'qdock-lan/1', 'token': token}).encode() + b'\n'
            for byte in hello:
                sock.sendall(bytes([byte]))
            welcome = receive(stream)
            assert welcome['txControlAvailable'] is False
            assert welcome['serialAvailable'] is False
            sock.sendall(b'{"message":"ping"}\n{"message":"subscribe"}\n')
            assert receive(stream)['message'] == 'pong'
            started = receive(stream)
            events = []
            while True:
                message = receive(stream)
                assert message['session'] == started['session']
                if message['message'] == 'event':
                    assert message['source'] == 'replay' and message['quality'] == 'candidate'
                    assert message['sequence'] == str(len(events) + 1)
                    events.append(message['event'])
                if message['message'] == 'stats':
                    assert message['bytes'] == '16968' and message['pending'] == '0'
                if message.get('status') == 'ended':
                    break
            baseline = subprocess.run([probe_exe, '--replay', str(path)],
                                      capture_output=True, text=True, check=True)
            assert events == [json.loads(line) for line in baseline.stdout.splitlines()]
            assert len(events) == 286
            # Preserve the documented false positive, explicitly as a candidate.
            assert any(e.get('type') == 0 and e.get('field') == 181 for e in events)

        for payload, expected in [
            (b'[]\n', 'invalid_json'),
            (b'{broken}\n', 'invalid_json'),
            (b'x' * 4097, 'message_too_large'),
            (b'{"message":"subscribe"}\n', 'protocol_mismatch'),
            (b'{"message":"hello","protocol":"qdock-lan/1","token":"wrong"}\n', 'unauthorized'),
            (b'{"message":"hello","protocol":"qdock-lan/2"}\n', 'protocol_mismatch'),
        ]:
            with connect() as sock, sock.makefile('rb') as stream:
                sock.sendall(payload)
                assert receive(stream)['code'] == expected

        for command in ['transmit', 'ptt', 'write', 'hello_radio', 'eeprom']:
            with connect() as sock, sock.makefile('rb') as stream:
                send(sock, {'message': 'hello', 'protocol': 'qdock-lan/1', 'token': token})
                assert receive(stream)['message'] == 'welcome'
                send(sock, {'message': command})
                assert receive(stream)['code'] == 'unsupported_message'

        # Two independent clients receive complete replays; reconnect creates a new session.
        def run_client():
            result = subprocess.run([sys.executable, str(root / 'tools/lan_client.py'),
                                     '--port', str(port)], env=env, capture_output=True,
                                    text=True, timeout=15)
            assert result.returncode == 0, result.stderr
            messages = [json.loads(line) for line in result.stdout.splitlines()]
            assert sum(m['message'] == 'event' for m in messages) == 286
            assert messages[-1]['status'] == 'ended'
            return messages[-1]['session']

        with concurrent.futures.ThreadPoolExecutor(max_workers=2) as pool:
            sessions = list(pool.map(lambda _: run_client(), range(2)))
        assert len(set(sessions + [started['session']])) == 3
        with connect() as sock, sock.makefile('rb') as stream:
            assert receive(stream)['code'] == 'authentication_timeout'
        assert proc.poll() is None
    finally:
        proc.terminate()
        proc.communicate(timeout=5)

    # Invalid sources must never open a device or silently select a different mode.
    for args in [[], ['--replay', '/dev/null'], ['--replay', directory],
                 ['--replay', str(path), '--port', '65536']]:
        result = subprocess.run([server_exe, *args], env=env, capture_output=True, timeout=5)
        assert result.returncode != 0
