"""Portable executor/gate tests; these are not Swift or simulator test results."""
import json
import os
from pathlib import Path
import runpy
import signal
import subprocess
import sys
import tempfile
import time
import unittest
from unittest.mock import patch

SCRIPTS = Path(__file__).resolve().parent


class BoundedCommandTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.root = Path(self.temporary.name)
        self.record = self.root / 'record.json'

    def tearDown(self):
        self.temporary.cleanup()

    def command(self, source, seconds=3):
        return [sys.executable, str(SCRIPTS/'run-bounded.py'), '--seconds', str(seconds),
                '--grace-seconds', '0.2', '--record', str(self.record), '--', sys.executable, '-c', source]

    def test_exit_statuses_are_preserved(self):
        for expected in (0, 7):
            result = subprocess.run(self.command(f'raise SystemExit({expected})'), capture_output=True, timeout=5)
            self.assertEqual(result.returncode, expected)
            self.assertEqual(json.loads(self.record.read_text())['command_exit'], expected)

    def test_timeout_never_becomes_a_pass(self):
        source = 'import time,signal,sys; signal.signal(signal.SIGINT, lambda *args: sys.exit(0)); time.sleep(60)'
        result = subprocess.run(self.command(source, .4), capture_output=True, timeout=5)
        self.assertEqual(result.returncode, 124)
        record = json.loads(self.record.read_text())
        self.assertTrue(record['timed_out'])
        self.assertEqual(record['command_exit'], 0)

    def test_expired_deadline_does_not_launch(self):
        marker = self.root/'must-not-exist'
        command = self.command(f'open({str(marker)!r}, "w").write("bad")')
        command[2:4] = ['--deadline-epoch', str(time.time() - 10)]
        result = subprocess.run(command, capture_output=True, timeout=5)
        self.assertEqual(result.returncode, 124)
        self.assertFalse(marker.exists())
        self.assertTrue(json.loads(self.record.read_text())['not_started'])

    def test_cancellation_stays_nonzero(self):
        ready = self.root/'ready'
        source = f'import time; open({str(ready)!r}, "w").write("ready"); time.sleep(60)'
        proc = subprocess.Popen(self.command(source), stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        try:
            deadline = time.monotonic()+3
            while not ready.exists() and time.monotonic() < deadline:
                time.sleep(.02)
            self.assertTrue(ready.exists())
            proc.send_signal(signal.SIGTERM)
            proc.communicate(timeout=5)
            self.assertEqual(proc.returncode, 143)
            self.assertEqual(json.loads(self.record.read_text())['cancel_signal'], signal.SIGTERM)
        finally:
            if proc.poll() is None:
                proc.kill(); proc.communicate()

    def test_timeout_kills_descendant_even_after_leader_exits(self):
        pid_file = self.root/'child.pid'
        source = f'''import os, signal, sys, time
child = os.fork()
if child == 0:
    signal.signal(signal.SIGINT, signal.SIG_IGN)
    signal.signal(signal.SIGTERM, signal.SIG_IGN)
    while True: time.sleep(.1)
open({str(pid_file)!r}, 'w').write(str(child))
signal.signal(signal.SIGINT, lambda *args: sys.exit(0))
time.sleep(60)
'''
        child = None
        try:
            result = subprocess.run(self.command(source, .4), capture_output=True, timeout=5)
            self.assertEqual(result.returncode, 124)
            child = int(pid_file.read_text())
            deadline = time.monotonic()+2
            while time.monotonic() < deadline:
                status = subprocess.run(['ps', '-o', 'stat=', '-p', str(child)], capture_output=True, text=True).stdout.strip()
                if not status or status.startswith('Z'):
                    break
                time.sleep(.02)
            self.assertTrue(not status or status.startswith('Z'), 'Owned descendant is still running: '+status)
        finally:
            if child:
                try: os.kill(child, signal.SIGKILL)
                except ProcessLookupError: pass


class ResultSnapshotTests(unittest.TestCase):
    def test_completed_and_incomplete_snapshots_remain_distinct(self):
        snapshot = runpy.run_path(str(SCRIPTS/'snapshot-native-results.py'))['snapshot']
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory); source = root/'source'; destination = root/'snapshot'
            complete = source/'full-first.xcresult'; complete.mkdir(parents=True)
            (complete/'Info.plist').write_bytes(b'finalized')
            pending = source/'focused.xcresult'; pending.mkdir()
            (pending/'partial.log').write_bytes(b'partial')
            records = snapshot(source, destination)
            by_name = {record['bundle']: record for record in records}
            self.assertTrue(by_name['full-first.xcresult']['complete_copy'])
            self.assertFalse(by_name['focused.xcresult']['complete_copy'])
            (complete/'Info.plist').unlink()
            self.assertEqual((destination/'full-first.xcresult/Info.plist').read_bytes(), b'finalized')

    def test_disappearing_source_file_is_recorded_without_uploading_live_tree(self):
        namespace = runpy.run_path(str(SCRIPTS/'snapshot-native-results.py'))
        snapshot = namespace['snapshot']; copyfile = namespace['shutil'].copyfile
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory); source = root/'source'; destination = root/'snapshot'
            bundle = source/'focused.xcresult'; bundle.mkdir(parents=True)
            (bundle/'Info.plist').write_bytes(b'finalized')
            (bundle/'vanished').write_bytes(b'partial')
            def copy_or_vanish(path, target):
                if path.name == 'vanished':
                    raise FileNotFoundError('synthetic staging move')
                return copyfile(path, target)
            with patch.object(namespace['shutil'], 'copyfile', side_effect=copy_or_vanish):
                records = snapshot(source, destination)
            self.assertFalse(records[0]['complete_copy'])
            self.assertEqual(records[0]['copy_errors'][0]['path'], 'vanished')
            self.assertFalse((destination/'focused.xcresult/vanished').exists())


class CoverageGateTests(unittest.TestCase):
    def test_first_pass_validation_rejects_missing_failed_skipped_and_unknown_cases(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory); source = root/'tests.swift'; log = root/'first.log'
            source.write_text('func testA() {}\nfunc testB() {}\n')
            terminal = lambda name, state: f"Test Case '-[BubuTimeMachineUITests.BubuTimeMachineUITests {name}]' {state} (1 seconds).\n"
            command = [sys.executable, str(SCRIPTS/'select-ui-retries.py'), '--validate-only', '--device', 'iPad',
                       '--source', str(source), '--first-log', str(log), '--output', str(root/'result')]
            for text, expected in ((terminal('testA','passed')+terminal('testB','passed'), 0),
                                   (terminal('testA','passed'), 1),
                                   (terminal('testA','passed')+terminal('testB','failed'), 1),
                                   (terminal('testA','passed')+terminal('testB','skipped'), 1),
                                   (terminal('testA','passed')+terminal('testX','passed'), 1)):
                log.write_text(text)
                result = subprocess.run(command, capture_output=True, timeout=5)
                self.assertEqual(result.returncode == 0, expected == 0)
            log.write_text(terminal('testA','passed'))
            self.assertEqual(subprocess.run(command+['--only-case','testA'], capture_output=True).returncode, 0)
            self.assertNotEqual(subprocess.run(command+['--only-case','testAbsent'], capture_output=True).returncode, 0)


if __name__ == '__main__':
    unittest.main()
