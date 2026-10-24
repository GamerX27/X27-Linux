# Persistent launcher settings (~/.config/x27-tv/settings.json) and the idle manager
# that runs swayidle for screen-off and auto-sleep in the x27-tv session.

import json
import os
import shlex
import shutil
from pathlib import Path

from PySide6.QtCore import Property, QObject, QProcess, Signal, Slot

CONFIG_DIR = Path(os.environ.get("XDG_CONFIG_HOME", Path.home() / ".config")) / "x27-tv"
PATH = CONFIG_DIR / "settings.json"


class Prefs(QObject):
    changed = Signal()

    def __init__(self):
        super().__init__()
        try:
            self._data = json.loads(PATH.read_text())
        except (OSError, ValueError):
            self._data = {}

    def get(self, key, default=None):
        return self._data.get(key, default)

    def set(self, key, value):
        if self._data.get(key) == value:
            return
        self._data[key] = value
        CONFIG_DIR.mkdir(parents=True, exist_ok=True)
        tmp = PATH.with_suffix(".tmp")
        tmp.write_text(json.dumps(self._data, indent=2))
        tmp.replace(PATH)
        self.changed.emit()

    @Property(int, notify=changed)
    def screenOff(self):
        return self.get("screen_off", 0)

    @Property(int, notify=changed)
    def sleepAfter(self):
        return self.get("sleep_after", 0)

    @Slot(int)
    def setScreenOff(self, minutes):
        self.set("screen_off", minutes)

    @Slot(int)
    def setSleepAfter(self, minutes):
        self.set("sleep_after", minutes)


class IdleManager(QObject):
    def __init__(self, prefs, session):
        super().__init__()
        self.prefs = prefs
        self.enabled = session and bool(shutil.which("swayidle"))
        self._proc = None
        self._args = None
        prefs.changed.connect(self.restart)
        self.restart()

    def restart(self):
        if not self.enabled:
            return
        ctl = shlex.quote(str(Path(os.environ.get("X27TV_HOME", Path(__file__).resolve().parent.parent)) / "bin/x27-tv-ctl"))
        args = ["-w"]
        if self.prefs.screenOff:
            args += ["timeout", str(self.prefs.screenOff * 60), f"{ctl} screen-off", "resume", f"{ctl} screen-on"]
        if self.prefs.sleepAfter:
            args += ["timeout", str(self.prefs.sleepAfter * 60), "systemctl suspend"]
        args += ["before-sleep", f"{ctl} screen-on"] if self.prefs.screenOff else []
        if args == self._args:
            return
        self._args = args
        if self._proc:
            self._proc.kill()
            self._proc.waitForFinished(1000)
            self._proc = None
        if len(args) > 1:
            self._proc = QProcess(self)
            self._proc.start("swayidle", args)
