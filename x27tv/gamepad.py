# Gamepad input via evdev, with hotplug and key repeat. D-pad/stick/A/B/X/Y/Start are turned
# into Qt keys for the launcher, and the Guide button acts as a global Home.

import select
import time

from PySide6.QtCore import QThread, Qt, Signal

try:
    import evdev
    from evdev import ecodes
except ImportError:
    evdev = None

BUTTONS = {
    "BTN_SOUTH": Qt.Key_Return,
    "BTN_EAST": Qt.Key_Escape,
    "BTN_WEST": Qt.Key_Delete,
    "BTN_NORTH": Qt.Key_Delete,
    "BTN_START": Qt.Key_Menu,
    "BTN_SELECT": Qt.Key_Menu,
    "BTN_TL": Qt.Key_PageUp,
    "BTN_TR": Qt.Key_PageDown,
}
DIRS = {(-1, 0): Qt.Key_Left, (1, 0): Qt.Key_Right, (0, -1): Qt.Key_Up, (0, 1): Qt.Key_Down}
REPEAT_DELAY, REPEAT_RATE = 0.40, 0.11


class Gamepad(QThread):
    key = Signal(int)
    home = Signal()

    def __init__(self):
        super().__init__()
        self.devices = {}
        self.axes = {}
        self.held = None
        self.next_repeat = 0.0
        self.buttons = {getattr(ecodes, n): k for n, k in BUTTONS.items()} if evdev else {}

    @staticmethod
    def available():
        return evdev is not None

    def _rescan(self):
        known = {d.path for d in self.devices.values()}
        for path in evdev.list_devices():
            if path in known:
                continue
            try:
                dev = evdev.InputDevice(path)
            except OSError:
                continue
            keys = dev.capabilities().get(ecodes.EV_KEY, [])
            if ecodes.BTN_SOUTH in keys:
                self.devices[dev.fd] = dev
            else:
                dev.close()

    def _axis(self, dev, code, value):
        info = dev.absinfo(code)
        if code in (ecodes.ABS_HAT0X, ecodes.ABS_HAT0Y):
            return value
        mid = (info.max + info.min) / 2
        span = (info.max - info.min) / 2 or 1
        norm = (value - mid) / span
        return -1 if norm < -0.55 else 1 if norm > 0.55 else 0

    def _direction(self):
        x = self.axes.get(ecodes.ABS_HAT0X) or self.axes.get(ecodes.ABS_X, 0)
        y = self.axes.get(ecodes.ABS_HAT0Y) or self.axes.get(ecodes.ABS_Y, 0)
        if x and y:
            y = 0
        return DIRS.get((x, y))

    def _handle(self, dev, ev):
        if ev.type == ecodes.EV_KEY and ev.value == 1:
            if ev.code == ecodes.BTN_MODE:
                self.home.emit()
            elif ev.code in self.buttons:
                self.key.emit(self.buttons[ev.code])
        elif ev.type == ecodes.EV_ABS and ev.code in (ecodes.ABS_X, ecodes.ABS_Y, ecodes.ABS_HAT0X, ecodes.ABS_HAT0Y):
            self.axes[ev.code] = self._axis(dev, ev.code, ev.value)
            direction = self._direction()
            if direction != self.held:
                self.held = direction
                if direction:
                    self.key.emit(direction)
                    self.next_repeat = time.monotonic() + REPEAT_DELAY

    def run(self):
        last_scan = 0.0
        while not self.isInterruptionRequested():
            now = time.monotonic()
            if now - last_scan > 2:
                self._rescan()
                last_scan = now
            try:
                ready, _, _ = select.select(list(self.devices), [], [], 0.05)
            except (OSError, ValueError):
                ready = []
            for fd in ready:
                dev = self.devices.get(fd)
                try:
                    for ev in dev.read():
                        self._handle(dev, ev)
                except OSError:
                    self.devices.pop(fd, None)
                    self.axes.clear()
                    self.held = None
            if self.held and time.monotonic() >= self.next_repeat:
                self.key.emit(self.held)
                self.next_repeat = time.monotonic() + REPEAT_RATE
