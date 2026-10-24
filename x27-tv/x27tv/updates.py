# Software updates: the installed and staged OS build from rpm-ostree, and an updater that
# downloads the next OS build (installed on the next restart) and updates system and user
# Flatpaks. It runs when asked and on its own once a day; sleep is blocked while it works.

import datetime
import json
import os
import re
import shutil
import time

from PySide6.QtCore import Property, QObject, QProcess, QTimer, Signal, Slot

from .proc import run

DAY = 24 * 3600
STATUS_EVERY = 15 * 60 * 1000
FIRST_RUN_DELAY = 10 * 60 * 1000

# Each step prints a "@@<step>" marker first so the UI can follow along. Exit status is
# nonzero if any step failed; the rest still run.
SCRIPT = r'''
fail=0
if [ -e /run/ostree-booted ] && command -v rpm-ostree >/dev/null; then
    echo @@os
    rpm-ostree upgrade 2>&1 || fail=1
fi
if command -v flatpak >/dev/null; then
    echo @@apps
    flatpak update --system -y --noninteractive 2>&1 || fail=1
    flatpak update --user -y --noninteractive 2>&1 || fail=1
fi
exit $fail
'''
STEPS = {"os": "Downloading system update…", "apps": "Updating apps…"}
# systemd-inhibit's own summary of the script's exit status, not a reason worth showing.
WRAPPER_LINE = re.compile(r"^\S+ failed with exit status \d+\.$")


def ostree_booted():
    return os.path.exists("/run/ostree-booted") and bool(shutil.which("rpm-ostree"))


def describe(d):
    when = datetime.date.fromtimestamp(d["timestamp"]).strftime("%-d %b %Y") if d.get("timestamp") else ""
    version = d.get("version") or ""
    return f"{version} ({when})" if version and when else version or when


def parse_status(text):
    try:
        deployments = json.loads(text).get("deployments", [])
    except ValueError:
        return "", ""
    booted = next((d for d in deployments if d.get("booted")), None)
    pending = deployments[0] if deployments and not deployments[0].get("booted") else None
    return (describe(booted) if booted else ""), (describe(pending) if pending else "")


def ago(stamp):
    if not stamp:
        return "Never"
    then = datetime.datetime.fromtimestamp(stamp)
    days = (datetime.date.today() - then.date()).days
    day = "Today" if days == 0 else "Yesterday" if days == 1 else then.strftime("%-d %b")
    return f"{day} {then.strftime('%H:%M')}"


class Updates(QObject):
    stateChanged = Signal()

    def __init__(self, prefs):
        super().__init__()
        self.prefs = prefs
        self._os = ostree_booted()
        self._current = ""
        self._pending = ""
        self._busy = ""
        self._error = ""
        self._proc = None
        self._background = False
        self._out = ""
        self._status_timer = QTimer(self, interval=STATUS_EVERY, timeout=self.refresh)
        self._status_timer.start()
        self._auto_timer = QTimer(self, interval=3600 * 1000, timeout=self._maybe_auto)
        self._auto_timer.start()
        QTimer.singleShot(FIRST_RUN_DELAY, self._maybe_auto)
        self.refresh()

    @Property(bool, constant=True)
    def systemUpdates(self):
        return self._os

    @Property(str, notify=stateChanged)
    def current(self):
        return self._current

    @Property(str, notify=stateChanged)
    def pending(self):
        return self._pending

    @Property(str, notify=stateChanged)
    def busy(self):
        return self._busy

    @Property(str, notify=stateChanged)
    def error(self):
        return self._error

    @Property(str, notify=stateChanged)
    def lastChecked(self):
        return ago(self.prefs.get("update_last", 0))

    @Slot()
    def refresh(self):
        if self._os:
            run(self, "rpm-ostree", ["status", "--json"], self._got_status)

    def _got_status(self, code, out, err):
        if code != 0:
            return
        current, pending = parse_status(out)
        if (current, pending) != (self._current, self._pending):
            self._current, self._pending = current, pending
            self.stateChanged.emit()

    def _maybe_auto(self):
        if time.time() - self.prefs.get("update_last", 0) >= DAY:
            self._update(background=True)

    @Slot()
    def checkNow(self):
        self._update(background=False)

    def _update(self, background):
        if self._proc:
            if not background:
                self._background = False
            return
        self._background = background
        self._busy, self._error, self._out = "Checking for updates…", "", ""
        self.stateChanged.emit()
        args = ["sh", "-c", SCRIPT]
        if shutil.which("systemd-inhibit"):
            args = ["systemd-inhibit", "--what=sleep", "--who=X27 TV", "--why=Installing updates", *args]
        self._proc = QProcess(self)
        self._proc.setProcessChannelMode(QProcess.MergedChannels)
        self._proc.readyReadStandardOutput.connect(self._read)
        self._proc.finished.connect(self._done)
        self._proc.start(args[0], args[1:])

    def _read(self):
        chunk = bytes(self._proc.readAllStandardOutput()).decode(errors="replace")
        self._out += chunk
        for line in chunk.splitlines():
            step = STEPS.get(line.strip().removeprefix("@@")) if line.startswith("@@") else None
            if step:
                self._busy = step
                self.stateChanged.emit()

    def _done(self, code, status):
        self._read()
        self._proc.deleteLater()
        self._proc = None
        self._busy = ""
        if code != 0 or status != QProcess.NormalExit:
            lines = [l.strip() for l in self._out.splitlines()
                     if l.strip() and not l.startswith("@@") and not WRAPPER_LINE.match(l.strip())]
            errors = [l for l in lines if "error" in l.lower() or "fail" in l.lower()]
            if not self._background:
                self._error = (errors or lines or ["Couldn't check for updates"])[-1][:200]
        else:
            self.prefs.set("update_last", int(time.time()))
        self.stateChanged.emit()
        self.refresh()
