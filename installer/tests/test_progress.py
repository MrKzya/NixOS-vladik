import json
import os
from pathlib import Path
import pty
import subprocess
import sys
import tempfile
import unittest

INSTALLER = Path(__file__).resolve().parents[1]
sys.dont_write_bytecode = True
sys.path.insert(0, str(INSTALLER))
from progress import Progress


def event(action, ident, kind=0, fields=(), **values):
    return "@nix " + json.dumps(dict(action=action, id=ident, type=kind, fields=fields, **values))


class InstallerProgressTest(unittest.TestCase):
    def test_nix_counters_and_curl_meter(self):
        state = Progress()
        for message in (
            event("start", 1, 103),
            event("result", 1, 105, [2, 4, 1, 0]),
            event("start", 2, 104),
            event("result", 2, 105, [1, 2, 1, 0]),
            event("start", 3, 101),
            event("result", 3, 105, [1048576, 2097152, 0, 0]),
            event("start", 4, 105, ["vscode.drv"], text="building vscode.drv"),
            event("result", 4, 101, ["  1  1024k  1  12k   0     0  1000     0  0:00:12"]),
        ):
            state.update(message, now=10)
        self.assertEqual(state.downloaded(), 1048576 + 12 * 1024)
        view = "\n".join(state.status(0, 25, 1048576))
        for text in ("~50%", "Copies: 2/4", "Builds: 1/2", "1.00 MiB/s", "vscode.drv", "15s ago"):
            self.assertIn(text, view)
        state.update(message, now=26)
        self.assertEqual(state.last_activity, 10)
        state.update(event("stop", 3), now=30)
        self.assertEqual(state.downloaded(), 1048576 + 12 * 1024)

    def test_fetch_failure_log_and_child_exit(self):
        for message, retry in (("curl: (28) Operation too slow", True),
                               ("curl error: Transferred a partial file", True), ("hash mismatch", False)):
            with self.subTest(message=message), tempfile.TemporaryDirectory() as directory:
                log, marker, errors = (Path(directory) / name for name in ("log", "retry", "errors"))
                lines = [
                    event("start", 4, 105, ["vscode.drv"], text="building vscode.drv"),
                    event("result", 4, 101, ["trying https://example.test/vscode?token=PRIVATE"]),
                    event("result", 4, 101, [message]),
                    "error: builder for vscode.drv failed",
                ]
                cmd = [sys.executable, "-c", f"print({chr(10).join(lines)!r}); raise SystemExit(17)"]
                result = subprocess.run([sys.executable, str(INSTALLER / "progress.py"), str(log), str(marker),
                                         str(errors), "15", *cmd], text=True, capture_output=True, timeout=10)
                self.assertEqual(result.returncode, 17, result.stderr)
                self.assertEqual(marker.is_file(), retry)
                self.assertIn("vscode.drv", result.stdout)
                self.assertIn("size unavailable", result.stdout)
                self.assertIn(message, errors.read_text())
                self.assertNotIn("PRIVATE", log.read_text() + errors.read_text() + result.stdout)

    def test_legacy_dry_run_exits_before_menus(self):
        master, slave = pty.openpty()
        cmd = ["bash", "-c", 'source "$1"; uname() { case "$1" in -s) printf Linux;; -m) printf x86_64;; esac; }; '
               'test() { [[ "$*" != "-d /sys/firmware/efi" ]]; }; main --dry-run',
               "bash", str(INSTALLER.parent / "install.sh")]
        try:
            result = subprocess.run(cmd, stdin=slave, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=10)
        finally:
            os.close(slave)
            os.close(master)
        self.assertEqual(result.returncode, 1)
        self.assertIn(b"Legacy BIOS detected", result.stdout)
        self.assertNotIn(b"Hardware profile", result.stdout)


if __name__ == "__main__":
    unittest.main()
