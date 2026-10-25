# Starts apps (in the x27-tv session via the user's systemd, so they get a clean user context;
# output logged to ~/.cache/x27-tv/logs), focuses ones that are already open,
# installs missing Flatpaks and handles Home, using wlrctl (wlr-foreign-toplevel) when available.
# It also tracks which app is in front, and pauses (cgroup-freezes) it behind the Quick Menu.

import os
import shutil
import subprocess
from pathlib import Path

from PySide6.QtCore import Property, QObject, QProcess, QTimer, Signal, Slot

from .apps import resolve_icon

SELF_ID = "x27-tv"
FLATHUB = "https://dl.flathub.org/repo/flathub.flatpakrepo"
LOG_DIR = Path(os.environ.get("XDG_CACHE_HOME", Path.home() / ".cache")) / "x27-tv/logs"


def wlrctl(*args):
    if not shutil.which("wlrctl"):
        return False
    try:
        return subprocess.run(["wlrctl", "toplevel", *args], capture_output=True, timeout=2).returncode == 0
    except subprocess.TimeoutExpired:
        return False


def wlrctl_detached(*args):
    # Fire and forget, so the UI never waits on wlrctl.
    if not shutil.which("wlrctl"):
        return False
    subprocess.Popen(["wlrctl", "toplevel", *args], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    return True


def go_home():
    # labwc raises on focus, so focusing the launcher is enough to bring it in front.
    return wlrctl_detached("focus", f"app_id:{SELF_ID}")


def thaw_all():
    # Undoes any pause left behind by a launcher that crashed with the Quick Menu open.
    subprocess.run(["systemctl", "--user", "thaw", "app-flatpak-*.scope", "x27-*.service"],
                   stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=5)


class Launcher(QObject):
    runningChanged = Signal()
    installingChanged = Signal()
    launched = Signal(str)
    installFinished = Signal(str)

    def __init__(self, store):
        super().__init__()
        self.store = store
        self._running = []
        self._windows = []
        self._installing = []
        self._poll = None
        self._front = ""
        self._paused = {}
        self._ctl = []
        if shutil.which("systemctl"):
            thaw_all()
        if shutil.which("wlrctl"):
            self._timer = QTimer(self, interval=2000, timeout=self._poll_running)
            self._timer.start()
            self._poll_running()

    @Property("QVariantList", notify=runningChanged)
    def running(self):
        return self._running

    @Property("QVariantList", notify=runningChanged)
    def windows(self):
        return self._windows

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
        titles = {}
        for line in out.splitlines():
            app_id, sep, title = line.partition(":")
            app_id = app_id.strip()
            if sep and app_id and app_id != SELF_ID:
                titles.setdefault(app_id, title.strip())
        ids = sorted(titles)
        if self._front in self._running and self._front not in titles:
            self._front = ""
        order = [w["appId"] for w in self._windows if w["appId"] in titles]
        order += [i for i in titles if i not in order]
        windows = [self._describe(i, titles[i]) for i in order]
        if ids != self._running or windows != self._windows:
            self._running = ids
            self._windows = windows
            self.runningChanged.emit()

    def _describe(self, app_id, title):
        e = next((a for a in self.store.apps + self.store.allApps if a.get("appId") == app_id), None)
        if e:
            return {"appId": app_id, "title": title, "name": e["name"], "icon": e["icon"]}
        return {"appId": app_id, "title": title, "name": title or app_id, "icon": resolve_icon(app_id)}

    def front_app(self):
        # The app last launched or switched to from the launcher, so the Quick Menu needn't ask
        # the compositor; only if that's unknown, one wlrctl call per running app.
        if self._front:
            return self._front
        return next((i for i in self._running if wlrctl("find", f"app_id:{i}", "state:focused")), "")

    def set_background(self, background):
        # Polling for open windows is only needed often while the taskbar is on screen.
        if hasattr(self, "_timer"):
            self._timer.setInterval(5000 if background else 2000)

    def _units(self, app_id):
        units = [f"app-flatpak-{app_id}-*.scope"]
        e = next((a for a in self.store.apps + self.store.allApps if a.get("appId") == app_id), None)
        if e:
            units.append(f"x27-{e['key']}-*.service")
        return units

    def _systemctl(self, *args):
        # One systemctl at a time, in order, so a thaw never overtakes its freeze.
        self._ctl.append(["--user", *args])
        if len(self._ctl) == 1:
            self._next_ctl()

    def _next_ctl(self):
        if not self._ctl:
            return
        proc = QProcess(self)

        def done(*_):
            proc.deleteLater()
            self._ctl.pop(0)
            self._next_ctl()

        proc.finished.connect(done)
        proc.start("systemctl", self._ctl[0])

    @Slot(str)
    def pauseApp(self, app_id):
        if app_id and app_id not in self._paused and shutil.which("systemctl"):
            self._paused[app_id] = self._units(app_id)
            self._systemctl("freeze", *self._paused[app_id])

    @Slot(str)
    def resumeApp(self, app_id):
        units = self._paused.pop(app_id, None)
        if units:
            self._systemctl("thaw", *units)

    def resume_all(self):
        for app_id in list(self._paused):
            subprocess.run(["systemctl", "--user", "thaw", *self._paused.pop(app_id)],
                           stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=5)

    @Slot(str)
    def focusApp(self, app_id):
        self._front = app_id
        wlrctl_detached("focus", f"app_id:{app_id}")

    @Slot(str)
    def closeApp(self, app_id):
        self.resumeApp(app_id)
        if app_id == self._front:
            self._front = ""
        wlrctl("close", f"app_id:{app_id}")
        QTimer.singleShot(400, self._poll_running)
        QTimer.singleShot(1500, self._poll_running)

    @Slot(str)
    def launch(self, key):
        e = self.store.find(key)
        if not e:
            return
        if not e["installed"]:
            if e["flatpak"]:
                self.install(key)
            return
        if e["appId"] in self._running:
            self.focusApp(e["appId"])
            self.launched.emit(key)
            return
        if not e["command"]:
            return
        self._front = e["appId"]
        LOG_DIR.mkdir(parents=True, exist_ok=True)
        log = str(LOG_DIR / f"{key}.log")
        cmd = list(e["command"])
        if os.environ.get("LABWC_PID") and shutil.which("systemd-run"):
            env = [a for v in ("WAYLAND_DISPLAY", "DISPLAY", "XDG_DATA_DIRS", "XDG_CURRENT_DESKTOP", "XDG_SESSION_TYPE",
                               "QT_QPA_PLATFORM", "MOZ_ENABLE_WAYLAND", "ELECTRON_OZONE_PLATFORM_HINT") if v in os.environ
                   for a in ("-E", v)]
            cmd = ["systemd-run", "--user", "--collect", "--quiet", "--unit", f"x27-{key}-{os.getpid()}-{len(os.listdir(LOG_DIR))}",
                   "-p", f"StandardOutput=truncate:{log}", "-p", f"StandardError=append:{log}", *env, "--", *cmd]
        proc = QProcess()
        proc.setProgram(cmd[0])
        proc.setArguments(cmd[1:])
        proc.setStandardOutputFile(log)
        proc.setStandardErrorFile(log)
        if proc.startDetached():
            self.launched.emit(key)

    @Slot(str, result=str)
    def lastError(self, key):
        try:
            lines = [l.strip() for l in (LOG_DIR / f"{key}.log").read_text(errors="replace").splitlines() if l.strip()]
        except OSError:
            return ""
        errors = [l for l in lines if any(w in l.lower() for w in ("error", "fail", "cannot", "not found", "denied"))]
        return (errors or lines or [""])[-1][:200]

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
        self._front = ""
        go_home()
