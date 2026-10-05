"""Real TCP sockets and disposable child processes; no existing service is stopped."""
import json
import os
from pathlib import Path
import signal
import subprocess
import sys
import tempfile
import unittest

APP = Path(__file__).resolve().parents[1] / "build/MyPorts.app/Contents/MacOS/MyPorts"
FIXTURE = r'''
import json, os, signal, socket, sys
mode = sys.argv[1]
sockets = []
one = socket.socket()
one.bind(("127.0.0.1", 0)); one.listen()
sockets.append(one)
if mode == "dual":
    six = socket.socket(socket.AF_INET6)
    six.setsockopt(socket.IPPROTO_IPV6, socket.IPV6_V6ONLY, 1)
    six.bind(("::1", one.getsockname()[1])); six.listen()
    sockets.append(six)
if mode == "multi":
    two = socket.socket(); two.bind(("127.0.0.1", 0)); two.listen()
    sockets.append(two)
udp = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
udp.bind(("127.0.0.1", 0))
def term(*_):
    open("terminated", "w").write("SIGTERM")
    sys.exit(0)
signal.signal(signal.SIGTERM, signal.SIG_IGN if mode == "stubborn" else term)
print(json.dumps({"pid": os.getpid(), "ports": [s.getsockname()[1] for s in sockets], "udp": udp.getsockname()[1]}), flush=True)
while True: signal.pause()
'''


class Integration(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="puertos prueba á ")
        self.children = []

    def tearDown(self):
        for child in self.children:
            if child.poll() is None:
                child.kill()
            child.wait(timeout=5)
            child.stdout.close()
            child.stderr.close()
        self.temp.cleanup()

    def fixture(self, mode="normal"):
        child = subprocess.Popen([sys.executable, "-u", "-c", FIXTURE, mode], cwd=self.temp.name,
                                 stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
        self.children.append(child)
        info = json.loads(child.stdout.readline())
        return child, info

    def rows(self, pid):
        result = subprocess.run([APP, "--list"], capture_output=True, text=True, check=True, timeout=10)
        return [row for row in json.loads(result.stdout) if row["pid"] == pid]

    def stop(self, row, force=False, **override):
        row = dict(row, **override)
        args = [APP, "--stop", str(row["pid"]), str(row["startSec"]), str(row["startUsec"]), str(row["port"])]
        if force:
            args.append("--force")
        return subprocess.run(args, capture_output=True, text=True, timeout=10)

    def test_appear_and_disappear_with_external_stop(self):
        child, info = self.fixture()
        rows = self.rows(child.pid)
        self.assertEqual(len(rows), 1)
        self.assertEqual(rows[0]["port"], info["ports"][0])
        self.assertEqual(rows[0]["directory"], os.path.realpath(self.temp.name))
        self.assertEqual(rows[0]["addresses"], ["127.0.0.1"])
        self.assertNotEqual(rows[0]["port"], info["udp"])
        child.terminate(); child.wait(timeout=5)
        self.assertEqual(self.rows(child.pid), [])

    def test_ipv4_ipv6_are_grouped(self):
        child, _ = self.fixture("dual")
        rows = self.rows(child.pid)
        self.assertEqual(len(rows), 1)
        self.assertEqual(rows[0]["addresses"], ["127.0.0.1", "::1"])

    def test_graceful_stop_releases_all_process_ports(self):
        child, _ = self.fixture("multi")
        rows = self.rows(child.pid)
        self.assertEqual(len(rows), 2)
        self.assertEqual(self.stop(rows[0]).returncode, 0)
        self.assertEqual(child.wait(timeout=5), 0)
        self.assertEqual((Path(self.temp.name) / "terminated").read_text(), "SIGTERM")
        self.assertEqual(self.rows(child.pid), [])

    def test_stale_identity_and_unrelated_port_are_rejected(self):
        child, _ = self.fixture()
        row = self.rows(child.pid)[0]
        self.assertNotEqual(self.stop(row, startSec=row["startSec"] + 1).returncode, 0)
        self.assertIsNone(child.poll())
        self.assertNotEqual(self.stop(row, startUsec=row["startUsec"] + 1).returncode, 0)
        self.assertIsNone(child.poll())
        self.assertNotEqual(self.stop(row, port=1).returncode, 0)
        self.assertIsNone(child.poll())

    def test_force_only_after_explicit_request(self):
        child, _ = self.fixture("stubborn")
        row = self.rows(child.pid)[0]
        self.assertEqual(self.stop(row).returncode, 0)
        self.assertIsNone(child.poll())
        self.assertEqual(len(self.rows(child.pid)), 1)
        self.assertEqual(self.stop(row, force=True).returncode, 0)
        self.assertEqual(child.wait(timeout=5), -signal.SIGKILL)
        self.assertEqual(self.rows(child.pid), [])


if __name__ == "__main__":
    unittest.main(verbosity=2)
