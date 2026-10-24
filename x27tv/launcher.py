# Starts apps, focuses ones that are already open, installs missing Flatpaks and
# handles Home, using wlrctl (wlr-foreign-toplevel) when the compositor supports it.

import shutil
import subprocess

from PySide6.QtCore import Property, QObject, QProcess, QTimer, Signal, Slot

SELF_ID = "x27-tv"
FLATHUB = "https://dl.flathub.org/repo/flathub.flatpakrepo"


def wlrctl(*args):
    if not shutil.which("wlrctl"):
        return False
    try:
        return subprocess.run(["wlrctl", "toplevel", *args], capture_output=True, timeout=2).returncode == 0
    except subprocess.TimeoutExpired:
        return False


def go_home():
    if not wlrctl("find", f"app_id:{SELF_ID}", "state:focused"):
        wlrctl("minimize", "state:focused")
    return wlrctl("focus", f"app_id:{SELF_ID}")


class Launcher(QObject):
    runningChanged = Signal()
    installingChanged = Signal()
    launched = Signal(str)
    installFinished = Signal(str)

    def __init__(self, store):
        super().__init__()
        self.store = store
        self._running = []
        self._installing = []
        self._poll = None
        if shutil.which("wlrctl"):
            self._timer = QTimer(self, interval=2000, timeout=self._poll_running)
            self._timer.start()
            self._poll_running()

    @Property("QVariantList", notify=runningChanged)
    def running(self):
        return self._running

    @Property("QVariantList", notify=installingChanged)
    def installing(self):
        return self._installing

    def _poll_running(self):
        if self._poll is not None:
            return
        self._poll = QProcess(self)
        self._poll.finished.connect(self._poll_done)
        self._poll.start("wlrctl", ["toplevel", "list"])

    def _poll_done(self):
        out = bytes(self._poll.readAllStandardOutput()).decode(errors="replace")
        self._poll.deleteLater()
        self._poll = None
        ids = sorted({line.split(":", 1)[0].strip() for line in out.splitlines() if ":" in line} - {SELF_ID})
        if ids != self._running:
            self._running = ids
            self.runningChanged.emit()

    @Slot(str)
    def launch(self, key):
        e = self.store.find(key)
        if not e:
            return
        if not e["installed"]:
            if e["flatpak"]:
                self.install(key)
            return
        if e["appId"] in self._running and wlrctl("focus", f"app_id:{e['appId']}"):
            self.launched.emit(key)
            return
        if e["command"] and QProcess.startDetached(e["command"][0], e["command"][1:])[0]:
            self.launched.emit(key)

    @Slot(str)
    def install(self, key):
        e = self.store.find(key)
        if not e or not e["flatpak"] or key in self._installing:
            return
        self._installing.append(key)
        self.installingChanged.emit()
        proc = QProcess(self)
        script = (f"flatpak remote-add --user --if-not-exists flathub {FLATHUB} && "
                  f"flatpak install --user -y --noninteractive flathub {e['flatpak']}")
        proc.finished.connect(lambda *_: self._install_done(key, proc))
        proc.start("sh", ["-c", script])

    def _install_done(self, key, proc):
        proc.deleteLater()
        self._installing.remove(key)
        self.installingChanged.emit()
        self.store.refresh()
        self.installFinished.emit(key)

    @Slot()
    def home(self):
        go_home()
