# SPDX-License-Identifier: GPL-2.0-only
"""Shared serial acquisition over TCP. Opens only a newly allocated PTY."""
import json
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
def server(device, seconds=10, capture=None, fail_writes=False):
    args = [exe, '--serial', device, '--seconds', str(seconds), '--port', '0']
    if capture is not None:
        args += ['--capture', str(capture)]
    def limit_file_writes():
        signal.signal(signal.SIGXFSZ, signal.SIG_IGN)
    proc = subprocess.Popen(args, env=env, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                            preexec_fn=limit_file_writes if fail_writes else None)
    try:
        assert select.select([proc.stdout], [], [], 5)[0], 'startup timeout'
        line = proc.stdout.readline()
        assert line, proc.stderr.read().decode()
        yield proc, json.loads(line)['port']
    finally:
        proc.terminate()
        proc.communicate(timeout=5)


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


master, slave = pty.openpty()
try:
    with server(os.ttyname(slave)) as (proc, port):
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
            assert first['nextSequence'] == '1'
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
            error = until(sb, 'source_status')
            assert error['status'] == 'error' and not error['portOpen']
            assert proc.poll() is None, 'serial failure killed LAN service'
            b.sendall(b'{"message":"ping"}\n')
            assert until(sb, 'pong')['message'] == 'pong'
            with client(port) as (_, _, after):
                assert after['status'] == 'error' and after['session'] == second['session']
finally:
    if master is not None:
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

# Opening failure is reported to subscribers, including by the shipped CLI.
with server('/nonexistent/qdock-test-port') as (proc, port):
    with client(port) as (_, _, status):
        assert status['status'] == 'error' and not status['portOpen']
    cli = Path(__file__).resolve().parents[1] / 'tools/lan_client.py'
    result = subprocess.run([sys.executable, str(cli), '--port', str(port)],
                            env=env, capture_output=True, text=True, timeout=5)
    assert result.returncode == 1 and 'Fuente serie:' in result.stderr
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
