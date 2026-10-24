# Control Center and System settings backend: volume via wpctl, network status via
# nmcli, device info, and power and session actions.

import ctypes
import gc
import os
import platform
import re
import socket
import sys

from PySide6.QtCore import Property, QCoreApplication, QObject, QProcess, QTimer, Signal, Slot

from .proc import run

SINK = "@DEFAULT_AUDIO_SINK@"
VERSION = "0.2"


def primary_ip():
    try:
        with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as s:
            s.connect(("192.0.2.1", 9))
            return s.getsockname()[0]
    except OSError:
        return ""


def _meminfo():
    info = {}
    with open("/proc/meminfo") as f:
        for line in f:
            key, value = line.split(":", 1)
            info[key] = int(value.split()[0]) * 1024
    return info


def _gib(n):
    return f"{n / 1024 ** 3:.1f} GB"


def _os_name():
    try:
        with open("/etc/os-release") as f:
            for line in f:
                if line.startswith("PRETTY_NAME="):
                    return line.split("=", 1)[1].strip().strip('"')
    except OSError:
        pass
    return platform.system()


def _cpu():
    try:
        with open("/proc/cpuinfo") as f:
            for line in f:
                if line.startswith("model name"):
                    return re.sub(r"\s+", " ", line.split(":", 1)[1]).strip()
    except OSError:
        pass
    return platform.processor()


def _uptime():
    with open("/proc/uptime") as f:
        secs = int(float(f.read().split()[0]))
    days, rem = divmod(secs, 86400)
    hours, rem = divmod(rem, 3600)
    return (f"{days} d " if days else "") + f"{hours} h {rem // 60} min"


class System(QObject):
    volumeChanged = Signal()
    networkChanged = Signal()
    infoChanged = Signal()

    def __init__(self, session):
        super().__init__()
        self.session = session
        self._volume = 0.0
        self._muted = False
        self._network = ""
        self._info = {}
        self._timer = QTimer(self, interval=10000, timeout=self.refresh)
        self._timer.start()
        self.refresh()

    def _run(self, program, args, callback=None):
        run(self, program, args, (lambda code, out, err: callback(out)) if callback else None)

    @Property(float, notify=volumeChanged)
    def volume(self):
        return self._volume

    @Property(bool, notify=volumeChanged)
    def muted(self):
        return self._muted

    @Property(str, notify=networkChanged)
    def network(self):
        return self._network

    @Property("QVariantMap", notify=infoChanged)
    def info(self):
        return self._info

    @Property(bool, constant=True)
    def sessionMode(self):
        return bool(self.session)

    @Slot()
    def refresh(self):
        self._run("wpctl", ["get-volume", SINK], self._parse_volume)
        self._run("nmcli", ["-t", "-f", "NAME,TYPE", "connection", "show", "--active"], self._parse_network)

    def _parse_volume(self, out):
        m = re.search(r"([\d.]+)", out)
        if m:
            self._volume = min(float(m.group(1)), 1.0)
            self._muted = "MUTED" in out
            self.volumeChanged.emit()

    def _parse_network(self, out):
        names = []
        for line in out.splitlines():
            name, _, kind = line.rpartition(":")
            if kind in ("802-11-wireless", "802-3-ethernet"):
                names.append(("Wi-Fi: " if kind == "802-11-wireless" else "Wired: ") + name.replace("\\:", ":"))
        value = names[0] if names else "Not connected"
        if value != self._network:
            self._network = value
            self.networkChanged.emit()

    @Slot()
    def refreshInfo(self):
        mem = _meminfo()
        disk = os.statvfs(os.path.expanduser("~"))
        self._info = {
            "name": socket.gethostname(),
            "os": _os_name(),
            "kernel": platform.release(),
            "cpu": _cpu(),
            "memory": f"{_gib(mem['MemTotal'] - mem['MemAvailable'])} used of {_gib(mem['MemTotal'])}",
            "storage": f"{_gib(disk.f_bavail * disk.f_frsize)} free of {_gib(disk.f_blocks * disk.f_frsize)}",
            "ip": primary_ip() or "Not connected",
            "uptime": _uptime(),
            "version": f"x27-tv {VERSION}",
        }
        self.infoChanged.emit()

    @Slot(float)
    def setVolume(self, value):
        self._volume = max(0.0, min(1.0, value))
        self._muted = False
        self.volumeChanged.emit()
        self._run("wpctl", ["set-mute", SINK, "0"])
        self._run("wpctl", ["set-volume", SINK, f"{self._volume:.2f}"])

    @Slot()
    def toggleMute(self):
        self._muted = not self._muted
        self.volumeChanged.emit()
        self._run("wpctl", ["set-mute", SINK, "toggle"])

    @Slot()
    def trimMemory(self):
        gc.collect()
        try:
            ctypes.CDLL("libc.so.6").malloc_trim(0)
        except (OSError, AttributeError):
            pass

    @Slot()
    def restartLauncher(self):
        os.execv(sys.executable, [sys.executable, "-m", "x27tv", *sys.argv[1:]])

    @Slot()
    def suspend(self):
        QProcess.startDetached("systemctl", ["suspend"])

    @Slot()
    def reboot(self):
        QProcess.startDetached("systemctl", ["reboot"])

    @Slot()
    def poweroff(self):
        QProcess.startDetached("systemctl", ["poweroff"])

    @Slot()
    def exitSession(self):
        if self.session and os.environ.get("LABWC_PID"):
            QProcess.startDetached("labwc", ["--exit"])
        else:
            QCoreApplication.quit()
