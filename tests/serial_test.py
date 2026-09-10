"""Exercise serial input and prove no transmitted bytes using a pseudo-terminal only."""
import json
import os
import pathlib
import pty
import select
import subprocess
import sys
import tempfile
import termios

master, slave = pty.openpty()
try:
    with tempfile.TemporaryDirectory() as directory:
        capture = pathlib.Path(directory) / 'capture.raw'
        proc = subprocess.Popen([sys.argv[1], '--port', os.ttyname(slave), '--seconds', '1',
                                 '--capture', str(capture)], stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        try:
            assert select.select([proc.stderr], [], [], 5)[0], 'no startup message'
            startup = proc.stderr.readline()
            assert b'READ-ONLY' in startup, startup
            attrs = termios.tcgetattr(slave)
            assert attrs[4] == attrs[5] == termios.B38400
            assert attrs[2] & termios.CSIZE == termios.CS8
            assert not attrs[2] & (termios.PARENB | termios.CSTOPB | termios.CRTSCTS)
            assert not attrs[0] & (termios.IXON | termios.IXOFF | termios.ISTRIP | termios.INLCR | termios.IGNCR | termios.ICRNL)
            assert not attrs[3] & (termios.ICANON | termios.ECHO | termios.ISIG)
            data = bytes.fromhex('b5 06 02 00 00 c8')
            os.write(master, data)
            stdout, stderr = proc.communicate(timeout=5)
            assert proc.returncode == 0, stderr
            assert json.loads(stdout)['state'] == 'RX'
            assert capture.read_bytes() == data
            assert not select.select([master], [], [], 0)[0], 'unexpected transmitted bytes'
        finally:
            if proc.poll() is None:
                proc.kill()
                proc.wait()
finally:
    os.close(master)
    os.close(slave)
