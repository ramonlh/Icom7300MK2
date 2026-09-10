import json
import pathlib
import subprocess
import sys
import tempfile

exe = sys.argv[1]
with tempfile.TemporaryDirectory() as directory:
    capture = pathlib.Path(directory) / 'sample.raw'
    capture.write_bytes(bytes.fromhex('b5 06 02 00 00 c8 b5 00 00 01 00 03 31 34 35'))
    result = subprocess.run([exe, '--replay', str(capture)], capture_output=True, text=True)
    assert result.returncode == 0, result.stderr
    events = [json.loads(line) for line in result.stdout.splitlines()]
    assert len(events) == 2
    assert events[0]['state'] == 'RX' and events[0]['battery_volts'] == 8
    assert events[1]['text'] == '145'
    assert 'pendientes=0' in result.stderr
    for args in [[], ['--replay', str(capture), '--port', '/invalid'],
                 ['--port', '/invalid', '--seconds', '0'], ['--replay', '/nonexistent'],
                 ['--replay', str(capture), '--capture', str(capture)]]:
        assert subprocess.run([exe, *args], capture_output=True).returncode != 0
    capture.write_bytes(bytes.fromhex('b5 00'))
    result = subprocess.run([exe, '--replay', str(capture)], capture_output=True, text=True)
    assert 'pendientes=2' in result.stderr
    # Real capture excerpt, including the extra bytes after UI status packets.
    fixture = pathlib.Path(__file__).parent / 'fixtures' / 'radio-status.hex'
    capture.write_bytes(bytes.fromhex(fixture.read_text()))
    result = subprocess.run([exe, '--replay', str(capture)], capture_output=True, text=True)
    assert result.returncode == 0, result.stderr
    events = [json.loads(line) for line in result.stdout.splitlines()]
    assert [event['type'] for event in events] == [5, 6, 5, 6]
    assert all(event['state'] == 'power_save' and event['battery_volts'] == 7.88
               for event in events if event['type'] == 6)
    assert 'descartados=100 pendientes=0' in result.stderr
    # Full physical screen capture: retain surrounding noise to test recovery.
    capture.write_bytes(bytes.fromhex((fixture.parent / 'radio-screen.hex').read_text()))
    result = subprocess.run([exe, '--replay', str(capture)], capture_output=True, text=True)
    assert result.returncode == 0, result.stderr
    events = [json.loads(line) for line in result.stdout.splitlines()]
    texts = {event.get('text') for event in events}
    assert {'M1', 'VA.LEON', '145.67500', '110.937', 'AM', 'Sql', 'Step', 'TxPwr', '6.25kHz'} <= texts
    assert 'pendientes=0' in result.stderr
    # UI has no checksum: the current parser also emits one spurious text event.
    # Do not treat every decoded text as a validated radio state.
