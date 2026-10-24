# Bluetooth settings backend via bluetoothctl: power (unblocking rfkill if needed),
# paired devices, scanning, and pair/connect/disconnect/forget. bluetoothctl exits 0 even
# when a command fails, so pairing and connecting check the result with `bluetoothctl info`.

import re

from PySide6.QtCore import Property, QObject, QTimer, Signal, Slot

from .proc import run

MAC = re.compile(r"^[0-9A-F]{2}(:[0-9A-F]{2}){5}$")
UNNAMED = re.compile(r"^[0-9A-F]{2}(-[0-9A-F]{2}){5}$")
SCAN_SECONDS = 15

# Pairs $1, keeping a discovery session open throughout so the device stays known to BlueZ
# (it drops unpaired devices shortly after a scan ends). Trusted first: with no agent to answer,
# an untrusted device's own connection back (controllers do this) would be rejected.
PAIR = r'''
m=$1
bluetoothctl --timeout 60 scan on >/dev/null 2>&1 &
scan=$!
trap 'kill $scan 2>/dev/null' EXIT
i=0
until bluetoothctl info "$m" >/dev/null 2>&1; do
    i=$((i + 1))
    [ $i -ge 10 ] && { echo "Failed: $2 wasn't found. Make sure it's still in pairing mode." >&2; exit 1; }
    sleep 1
done
bluetoothctl trust "$m" >/dev/null
out=$(bluetoothctl --timeout 25 pair "$m" 2>&1)
if ! bluetoothctl info "$m" | grep -q "Paired: yes"; then
    bluetoothctl untrust "$m" >/dev/null
    echo "$out" >&2
    echo "Failed to pair with $2. Put it in pairing mode and try again." >&2
    exit 1
fi
kill $scan 2>/dev/null
'''

# Connects $1 and fails unless it really ended up connected.
CONNECT = r'''
out=$(bluetoothctl --timeout 15 connect "$1" 2>&1)
bluetoothctl info "$1" | grep -q "Connected: yes" && exit 0
echo "$out" >&2
echo "Failed to connect to $2. Make sure it's on and nearby." >&2
exit 1
'''


def kind_of(name):
    n = name.lower()
    if any(k in n for k in ("controller", "gamepad", "xbox", "dualsense", "dualshock", "joy-con", "8bitdo", "pro controller")):
        return "gamepad"
    if any(k in n for k in ("remote", "keyboard", "mouse")):
        return "remote"
    if any(k in n for k in ("wh-", "wf-", "ear", "buds", "headphone", "headset", "airpods", "speaker", "soundbar", "jbl", "bose")):
        return "audio"
    if any(k in n for k in ("galaxy", "iphone", "pixel", "phone")):
        return "phone"
    return "other"


def parse_devices(text):
    out = []
    for line in text.splitlines():
        parts = line.strip().split(" ", 2)
        if len(parts) == 3 and parts[0] == "Device" and MAC.match(parts[1]):
            out.append((parts[1], parts[2]))
    return out


class Bluetooth(QObject):
    stateChanged = Signal()

    def __init__(self):
        super().__init__()
        self._available = False
        self._powered = False
        self._blocked = False
        self._paired = []
        self._discovered = []
        self._busy = ""
        self._error = ""
        self._scan_left = 0
        self._connected = set()
        self._paired_macs = set()
        self._timer = QTimer(self, interval=1000, timeout=self._scan_tick)

    @Property(bool, notify=stateChanged)
    def available(self):
        return self._available

    @Property(bool, notify=stateChanged)
    def powered(self):
        return self._powered

    @Property(bool, notify=stateChanged)
    def blocked(self):
        return self._blocked

    @Property("QVariantList", notify=stateChanged)
    def devices(self):
        return self._paired

    @Property("QVariantList", notify=stateChanged)
    def discovered(self):
        return self._discovered

    @Property(bool, notify=stateChanged)
    def scanning(self):
        return self._scan_left > 0

    @Property(int, notify=stateChanged)
    def scanSeconds(self):
        return self._scan_left

    @Property(str, notify=stateChanged)
    def busy(self):
        return self._busy

    @Property(str, notify=stateChanged)
    def error(self):
        return self._error

    @Slot()
    def refresh(self):
        run(self, "bluetoothctl", ["show"], self._show)

    def _show(self, code, out, err):
        self._available = code == 0 and "Controller" in out
        self._powered = "Powered: yes" in out
        self._blocked = "off-blocked" in out
        self.stateChanged.emit()
        if self._available:
            run(self, "bluetoothctl", ["devices", "Connected"], self._got_connected)

    def _got_connected(self, code, out, err):
        self._connected = {mac for mac, _ in parse_devices(out)}
        run(self, "bluetoothctl", ["devices", "Paired"], self._got_paired)

    def _got_paired(self, code, out, err):
        devs = parse_devices(out)
        self._paired_macs = {mac for mac, _ in devs}
        self._paired = sorted(
            ({"mac": mac, "name": name, "kind": kind_of(name), "connected": mac in self._connected} for mac, name in devs),
            key=lambda d: (not d["connected"], d["name"].lower()))
        self.stateChanged.emit()
        run(self, "bluetoothctl", ["devices"], self._got_all)

    def _got_all(self, code, out, err):
        self._discovered = [
            {"mac": mac, "name": name, "kind": kind_of(name)}
            for mac, name in parse_devices(out)
            if mac not in self._paired_macs and not UNNAMED.match(name)
        ]
        self.stateChanged.emit()

    def _start(self, message, script, *args):
        if self._busy:
            return
        self._busy, self._error = message, ""
        self.stateChanged.emit()
        run(self, "sh", ["-c", script, "sh", *args], self._finish)

    def _finish(self, code, out, err):
        self._busy = ""
        if code != 0:
            lines = [l for l in (out + "\n" + err).splitlines() if "Failed" in l or "rror" in l or "not available" in l]
            self._error = lines[-1].strip() if lines else "Something went wrong"
        self.refresh()

    @Slot(bool)
    def setPowered(self, on):
        if on and self._blocked:
            self._start("Turning Bluetooth on…", "rfkill unblock bluetooth; sleep 1; bluetoothctl power on")
        else:
            self._start("Turning Bluetooth on…" if on else "Turning Bluetooth off…", f"bluetoothctl power {'on' if on else 'off'}")

    @Slot()
    def scan(self):
        if self._scan_left:
            return
        self._scan_left = SCAN_SECONDS
        self._timer.start()
        self.stateChanged.emit()
        run(self, "bluetoothctl", ["--timeout", str(SCAN_SECONDS), "scan", "on"])

    def _scan_tick(self):
        self._scan_left -= 1
        if self._scan_left <= 0:
            self._timer.stop()
        if self._scan_left % 2 == 0:
            self.refresh()
        self.stateChanged.emit()

    @Slot(str, str)
    def pair(self, mac, name):
        self._start(f"Pairing with {name}…", PAIR + CONNECT, mac, name)

    @Slot(str, str)
    def connectDevice(self, mac, name):
        self._start(f"Connecting to {name}…", CONNECT, mac, name)

    @Slot(str, str)
    def disconnectDevice(self, mac, name):
        self._start(f"Disconnecting {name}…", 'bluetoothctl disconnect "$1"', mac, name)

    @Slot(str, str)
    def forget(self, mac, name):
        self._start(f"Forgetting {name}…", 'bluetoothctl remove "$1"', mac, name)

    @Slot()
    def clearError(self):
        self._error = ""
        self.stateChanged.emit()
