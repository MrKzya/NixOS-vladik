"""Render Nix internal-json activities while preserving the diagnostic log."""
import json
import os
import re
import selectors
import signal
import subprocess
import sys
import time

COPY_PATH, TRANSFER, COPY_PATHS, BUILDS, BUILD, SUBSTITUTE = 100, 101, 103, 104, 105, 108
BUILD_LINE, PROGRESS = 101, 105
MIB = 1024 ** 2
ANSI = re.compile(r"\x1b\[[0-?]*[ -/]*[@-~]")
RETRYABLE = re.compile(
    r"curl: \((?:5|6|7|18|28|52|55|56)\)|timed? out|timeout was reached|too slow|"
    r"transferred a partial file|could not resolve (?:host|proxy)|failed to connect|"
    r"connection (?:reset|refused)|temporary failure in name resolution|HTTP (?:error )?(?:429|50[0234])",
    re.IGNORECASE,
)
# fetchurl forwards curl's progress meter as individual Nix build log lines.
CURL_METER = re.compile(r"^\s*\d{1,3}\s+(\d+(?:\.\d+)?[kMGTP]?)\s+\d{1,3}\s+(\d+(?:\.\d+)?[kMGTP]?)\s")


def redact(line):
    line = re.sub(r"(https?://)[^/@\s]+@", r"\1[redacted]@", line)
    line = re.sub(r"(?i)([?&](?:token|access_token|sig|signature|x-amz-[^=&]+)=)[^&\s\"]+", r"\1[redacted]", line)
    return re.sub(r'(?i)(authorization:\s*(?:bearer|basic)\s+)[^\s"\\]+|\b(?:gh[pousr]_|github_pat_)\w+',
                  r"\1[redacted]", line)


def printable(text):
    return "".join(char if " " <= char <= "~" else "?" for char in ANSI.sub("", text))


def clock(seconds):
    minutes, seconds = divmod(int(seconds), 60)
    return f"{minutes // 60:02d}:{minutes % 60:02d}:{seconds:02d}"


def curl_bytes(value):
    if value[-1].isdigit():
        return int(float(value))
    return int(float(value[:-1]) * 1024 ** (1 + "kMGTP".index(value[-1])))


class Progress:
    def __init__(self):
        self.activities = {}
        self.totals = {}
        self.store_operations = {}
        self.transfer_bytes = 0
        self.fetchurl = {}
        self.observed_bytes = False
        self.last_activity = time.monotonic()
        self.current = "Waiting for Nix"
        self.retryable = False
        self.errors = []

    def update(self, line, now):
        if not line.startswith("@nix "):
            line = ANSI.sub("", line)
            if not line.strip():
                return
            self.retryable |= bool(RETRYABLE.search(line))
            if "error" in line.lower() or RETRYABLE.search(line):
                self.errors = (self.errors + [line.strip()])[-8:]
            self.current = line.strip()
            self.last_activity = now
            return
        try:
            event = json.loads(line[5:])
        except ValueError:
            return
        action, ident = event.get("action"), event.get("id")
        fields = event.get("fields", [])
        if action == "start":
            kind = event.get("type")
            self.activities[ident] = (kind, 0, 0)
            if kind in (BUILD, COPY_PATH, SUBSTITUTE) and fields:
                package = re.sub(r"^/nix/store/[a-z0-9]{32}-", "", str(fields[0]))
                verb = {BUILD: "Building", COPY_PATH: "Copying", SUBSTITUTE: "Substituting"}[kind]
                self.store_operations[ident] = f"{verb} {package}"
            if kind in (TRANSFER, BUILD):
                self.current = event.get("text") or (str(fields[0]) if fields else "Nix operation")
            self.last_activity = now
        elif action == "stop":
            activity = self.activities.pop(ident, None)
            self.store_operations.pop(ident, None)
            if activity and activity[0] == TRANSFER:
                self.transfer_bytes += activity[1]
            if ident in self.fetchurl:
                self.transfer_bytes += self.fetchurl.pop(ident)[0]
            self.last_activity = now
        elif action == "result":
            activity = self.activities.get(ident)
            if event.get("type") == PROGRESS and activity and len(fields) >= 4:
                kind, old_done, old_total = activity
                done, total, running, failed = fields[:4]
                self.activities[ident] = (kind, done, total)
                if kind == TRANSFER:
                    self.observed_bytes = True
                if kind in (COPY_PATHS, BUILDS):
                    self.totals[kind] = (done, total, running, failed)
                if (done, total) != (old_done, old_total):
                    self.last_activity = now
            elif event.get("type") == BUILD_LINE and fields:
                message = str(fields[0]).strip()
                meter = CURL_METER.match(message)
                if meter:
                    total, done = map(curl_bytes, meter.groups())
                    previous = self.fetchurl.get(ident, (0, 0))
                    self.fetchurl[ident] = (max(done, previous[0]), max(total, previous[1]))
                    self.observed_bytes = True
                    if self.fetchurl[ident] != previous:
                        self.last_activity = now
                    return
                failed_download = bool(RETRYABLE.search(message))
                self.retryable |= failed_download
                if message.startswith("trying ") or failed_download:
                    if message.startswith("trying "):
                        self.transfer_bytes += self.fetchurl.pop(ident, (0, 0))[0]
                    self.current = message
                    package = self.store_operations.get(ident, "")
                    if package:
                        self.store_operations[ident] = f"{package.split(' | ', 1)[0]} | {message}"
                    self.errors = (self.errors + [self.store_operations.get(ident, message)])[-8:]
                elif "error" in message.lower() or "hash mismatch" in message.lower():
                    self.errors = (self.errors + [message])[-8:]
                self.last_activity = now
        elif action == "msg":
            msg = ANSI.sub("", event.get("msg", ""))
            if msg:
                self.retryable |= bool(RETRYABLE.search(msg))
                self.current = msg.strip().splitlines()[0]
                if event.get("level") in (0, 1) or RETRYABLE.search(msg):
                    self.errors = (self.errors + [msg.strip()])[-8:]
                self.last_activity = now

    def downloaded(self):
        transfers = (entry[1] for entry in self.activities.values() if entry[0] == TRANSFER)
        return self.transfer_bytes + sum(transfers) + sum(done for done, _ in self.fetchurl.values())

    def status(self, started, now, rate):
        counts = []
        for kind, name in ((COPY_PATHS, "Copies"), (BUILDS, "Builds")):
            done, expected, running, failed = self.totals.get(kind, (0, 0, 0, 0))
            if expected:
                counts.append(f"{name}: {done}/{expected}, {max(0, expected - done - failed)} left, {running} active, {failed} failed")
        known = [values for values in self.totals.values() if values[1] > 0]
        overall = "Overall: estimating"
        if known:
            percent = min(100, int(100 * sum(x[0] for x in known) / sum(x[1] for x in known)))
            filled = percent // 5
            overall = f"[{'#' * filled}{'-' * (20 - filled)}] ~{percent}% of reported Nix operations"
        volume = "Downloaded: size unavailable"
        if self.observed_bytes:
            volume = f"Downloaded: {self.downloaded() / MIB:.2f} MiB observed, {rate / MIB:.2f} MiB/s"
        active = [(done, total) for kind, done, total in self.activities.values() if kind == TRANSFER]
        active.extend(self.fetchurl.values())
        measured = [(done, total) for done, total in active if total > 0]
        if measured:
            volume += f" | Active transfers: {sum(x[0] for x in measured) / MIB:.2f}/{sum(x[1] for x in measured) / MIB:.2f} MiB"
        current = next(reversed(self.store_operations.values()), self.current)
        return [
            overall,
            volume,
            *counts,
            "Current: " + printable(current)[:170],
            f"Elapsed: {clock(now - started)} | Last activity: {int(now - self.last_activity)}s ago",
        ]


def monitor(log, retry_marker, errors_path, started, command):
    state = Progress()
    last_screen = time.monotonic()
    last_bytes = 0
    selector = selectors.DefaultSelector()
    with open(log, "a", encoding="utf-8") as output, subprocess.Popen(
        command, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, start_new_session=True,
        env={**os.environ, "NO_COLOR": "1"},
    ) as process:
        interrupted = None

        def stop(_signal, _frame):
            nonlocal interrupted
            if interrupted is None:
                interrupted = time.monotonic()
            try:
                os.killpg(process.pid, signal.SIGTERM)
            except ProcessLookupError:
                pass

        signal.signal(signal.SIGINT, stop)
        signal.signal(signal.SIGTERM, stop)
        signal.signal(signal.SIGHUP, stop)
        selector.register(process.stdout, selectors.EVENT_READ)
        pending = b""
        while selector.get_map() or process.poll() is None:
            events = selector.select(1) if selector.get_map() else ()
            if not selector.get_map():
                time.sleep(0.1)
            for key, _ in events:
                chunk = os.read(key.fd, 65536)
                if chunk:
                    pending += chunk
                else:
                    selector.unregister(key.fileobj)
                    pending += b"\n"
                lines = pending.split(b"\n")
                pending = lines.pop()
                now = time.monotonic()
                for raw in lines:
                    line = redact(raw.decode("utf-8", errors="replace"))
                    output.write(line + "\n")
                    state.update(line, now)
                output.flush()
            now = time.monotonic()
            if interrupted is not None and now - interrupted >= 5:
                try:
                    os.killpg(process.pid, signal.SIGKILL)
                except ProcessLookupError:
                    pass
            if now - last_screen >= 5 or not selector.get_map() and process.poll() is not None:
                downloaded = state.downloaded()
                rate = max(0, downloaded - last_bytes) / max(0.01, now - last_screen)
                print("\n".join(state.status(started, now, rate)), flush=True)
                last_screen, last_bytes = now, downloaded
        code = process.wait()
    selector.close()
    if code and not interrupted:
        with open(errors_path, "w", encoding="ascii", errors="replace") as errors:
            errors.write("\n".join(printable(line) for error in state.errors for line in error.splitlines()) + "\n")
        if state.retryable:
            with open(retry_marker, "w", encoding="ascii"):
                pass
    return 130 if interrupted else code if code >= 0 else 128 - code


if __name__ == "__main__":
    log_path, marker, errors_path, elapsed, *args = sys.argv[1:]
    sys.exit(monitor(log_path, marker, errors_path, time.monotonic() - float(elapsed), args))
