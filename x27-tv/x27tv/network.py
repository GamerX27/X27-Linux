# Network settings backend via nmcli: Wi-Fi radio, wired status, scanning, connecting
# with or without a password, disconnecting and forgetting networks. `target` is the network
# being acted on, so the page can show progress and errors on its row.

import re

from PySide6.QtCore import Property, QObject, QTimer, Signal, Slot

from .proc import run
from .system import primary_ip

NOTICE_MS = 6000
# nmcli's activation errors, as something to tell the person holding the remote.
FRIENDLY = [
    (re.compile(r"Secrets were required|802-1X|psk|password", re.I), "Wrong password for {ssid}. Press OK on it to try again."),
    (re.compile(r"No network with SSID", re.I), "{ssid} isn't in range anymore."),
    (re.compile(r"timeout|timed out", re.I), "{ssid} didn't answer. Try again closer to the router."),
]


def split_terse(line):
    return [p.replace("\\:", ":") for p in re.split(r"(?<!\\):", line)]


class Network(QObject):
    stateChanged = Signal()

    def __init__(self):
        super().__init__()
        self._wifi_enabled = False
        self._has_wifi = False
        self._wired = ""
        self._networks = []
        self._saved = set()
        self._busy = ""
        self._error = ""
        self._scanning = False
        self._target = ""
        self._failed = ""
        self._notice = ""
        self._new = False
        self._replace_args = []
        self._notice_timer = QTimer(self, singleShot=True, interval=NOTICE_MS, timeout=self._clear_notice)

    @Property(bool, notify=stateChanged)
    def wifiEnabled(self):
        return self._wifi_enabled

    @Property(bool, notify=stateChanged)
    def hasWifi(self):
        return self._has_wifi

    @Property(str, notify=stateChanged)
    def wired(self):
        return self._wired

    @Property(str, notify=stateChanged)
    def ip(self):
        return primary_ip()

    @Property("QVariantList", notify=stateChanged)
    def networks(self):
        return self._networks

    @Property(str, notify=stateChanged)
    def busy(self):
        return self._busy

    @Property(str, notify=stateChanged)
    def error(self):
        return self._error

    @Property(bool, notify=stateChanged)
    def scanning(self):
        return self._scanning

    @Property(str, notify=stateChanged)
    def target(self):
        return self._target

    @Property(str, notify=stateChanged)
    def failed(self):
        return self._failed

    @Property(str, notify=stateChanged)
    def notice(self):
        return self._notice

    def _clear_notice(self):
        self._notice = ""
        self.stateChanged.emit()

    @Slot()
    def refresh(self):
        run(self, "nmcli", ["-t", "-f", "WIFI", "radio"], self._radio)
        run(self, "nmcli", ["-t", "-f", "TYPE,STATE,CONNECTION", "device"], self._devices)
        run(self, "nmcli", ["-t", "-f", "NAME,TYPE", "connection", "show"], self._connections)
        self._list("no")

    @Slot()
    def scan(self):
        self._scanning = True
        self.stateChanged.emit()
        self._list("yes")

    def _list(self, rescan):
        run(self, "nmcli", ["-t", "-f", "IN-USE,SSID,SIGNAL,SECURITY", "device", "wifi", "list", "--rescan", rescan],
            lambda code, out, err: self._wifi_list(code, out, err, rescan == "yes"))

    def _radio(self, code, out, err):
        self._wifi_enabled = out.strip() == "enabled"
        self.stateChanged.emit()

    def _devices(self, code, out, err):
        self._has_wifi, self._wired = False, ""
        for line in out.splitlines():
            kind, state, conn = (split_terse(line) + ["", "", ""])[:3]
            if kind == "wifi":
                self._has_wifi = True
            elif kind == "ethernet" and state == "connected":
                self._wired = conn
        self.stateChanged.emit()

    def _connections(self, code, out, err):
        self._saved = {split_terse(l)[0] for l in out.splitlines() if l.endswith(":802-11-wireless")}
        for n in self._networks:
            n["saved"] = n["ssid"] in self._saved
        self.stateChanged.emit()

    def _wifi_list(self, code, out, err, partial=False):
        best = {}
        for line in out.splitlines():
            in_use, ssid, signal, security = (split_terse(line) + ["", "", "", ""])[:4]
            if not ssid:
                continue
            entry = {
                "ssid": ssid,
                "signal": int(signal or 0),
                "secure": bool(security.strip()) and security.strip() != "--",
                "active": in_use.strip() == "*",
                "saved": ssid in self._saved,
            }
            prev = best.get(ssid)
            if not prev or entry["active"] or (entry["signal"] > prev["signal"] and not prev["active"]):
                best[ssid] = entry
        if partial:
            for n in self._networks:
                best.setdefault(n["ssid"], dict(n, active=False))
            QTimer.singleShot(4000, lambda: self._list("no"))
        self._networks = sorted(best.values(), key=lambda n: (not n["active"], not n["saved"], -n["signal"]))
        self._scanning = False
        self.stateChanged.emit()

    def _finish(self, action, code, out, err):
        if action == "replace":
            self._saved.discard(self._target)
            self._busy = ""
            self._start(f"Connecting to {self._target}…", self._replace_args, "connect", self._target)
            return
        ssid, self._busy = self._target, ""
        if code != 0:
            msg = (err or out).strip().splitlines()
            raw = re.sub(r"^Error:\s*", "", msg[-1] if msg else "Something went wrong")
            self._error = next((text.format(ssid=ssid) for pattern, text in FRIENDLY if pattern.search(raw)), raw)
            self._failed = ssid
            # A first connect that fails still leaves a profile with the wrong password behind,
            # which would then show as Saved and never ask for the password again.
            if action == "connect" and self._new:
                run(self, "nmcli", ["connection", "delete", "id", ssid])
        elif action == "connect":
            self._notice, self._failed = f"Connected to {ssid}", ""
            self._notice_timer.start()
        self._target = ""
        self.refresh()

    def _start(self, message, args, action="", target=""):
        self._busy, self._error, self._target, self._notice = message, "", target, ""
        self.stateChanged.emit()
        run(self, "nmcli", args, lambda code, out, err: self._finish(action, code, out, err))

    @Slot(bool)
    def setWifi(self, on):
        self._wifi_enabled = on
        self._start("Turning Wi-Fi on…" if on else "Turning Wi-Fi off…", ["radio", "wifi", "on" if on else "off"])

    @Slot(str, str)
    def connectTo(self, ssid, password):
        if self._busy:
            return
        self._new = ssid not in self._saved
        args = ["device", "wifi", "connect", ssid] + (["password", password] if password else [])
        if ssid in self._saved and not password:
            args = ["connection", "up", "id", ssid]
        elif ssid in self._saved:
            # New password for a saved network: replace its profile rather than add a second.
            self._new = True
            self._start(f"Connecting to {ssid}…", ["connection", "delete", "id", ssid], "replace", ssid)
            self._replace_args = ["--wait", "30", *args]
            return
        self._start(f"Connecting to {ssid}…", ["--wait", "30", *args], "connect", ssid)

    @Slot(str)
    def disconnectFrom(self, ssid):
        self._start(f"Disconnecting from {ssid}…", ["connection", "down", "id", ssid], "disconnect", ssid)

    @Slot(str)
    def forget(self, ssid):
        self._start(f"Forgetting {ssid}…", ["connection", "delete", "id", ssid], "forget", ssid)

    @Slot()
    def clearError(self):
        self._error, self._failed = "", ""
        self.stateChanged.emit()
