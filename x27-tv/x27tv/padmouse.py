# Gamepad as mouse and keyboard, for apps that don't support a gamepad: a virtual uinput
# device the compositor treats like any other mouse/keyboard. The left stick moves the
# pointer (hold the right trigger for slow, precise movement), the right stick scrolls,
# A/X click left/right (A held drags; buttons by their Xbox letters), B is Escape, the
# D-pad arrow keys, Start Enter, Select Tab, LB Backspace, RB Space, and Y opens the typing
# keyboard (TypeKeyboard.qml). While it's open the left stick and D-pad move across its keys
# (sent to it as typingKey), A presses one, X is Shift, B/Y close it, and each key is typed
# into the app straight away. Gamepad events arrive on the gamepad thread (handle/tick);
# typing comes from the UI thread, hence the lock.

import time

import threading
from pathlib import Path

from PySide6.QtCore import Property, QObject, QTimer, Signal, Slot

try:
    from evdev import UInput, ecodes as e
except ImportError:
    UInput = None

SPEED = 2400.0      # pointer px/s at full tilt
PRECISION = 0.35    # speed factor while the right trigger is held
CURVE = 1.6         # stick response: 1 is linear, higher is finer near the center
SCROLL = 14.0       # wheel notches/s at full tilt
DEADZONE = 0.15
REPEAT_DELAY, REPEAT_RATE = 0.28, 0.07  # typing keyboard navigation, as in the launcher

# Xbox drivers report face buttons by letter, and BTN_X/BTN_Y are the same codes as
# BTN_NORTH/BTN_WEST, so on those pads "north" is the left button (X) and "west" the top (Y).
LETTER_DRIVERS = {"xpad", "xpadneo", "microsoft"}
MICROSOFT = 0x045E

if UInput:
    BUTTONS = {e.BTN_SOUTH: e.BTN_LEFT, e.BTN_WEST: e.BTN_RIGHT, e.BTN_EAST: e.KEY_ESC,
               e.BTN_START: e.KEY_ENTER, e.BTN_SELECT: e.KEY_TAB, e.BTN_TL: e.KEY_BACKSPACE, e.BTN_TR: e.KEY_SPACE}
    HAT = {(e.ABS_HAT0X, -1): e.KEY_LEFT, (e.ABS_HAT0X, 1): e.KEY_RIGHT, (e.ABS_HAT0Y, -1): e.KEY_UP, (e.ABS_HAT0Y, 1): e.KEY_DOWN}
    # While typing: buttons that type straight away, and ones the on-screen keyboard handles.
    TYPING_KEYS = {e.BTN_START: e.KEY_ENTER, e.BTN_SELECT: e.KEY_TAB, e.BTN_TL: e.KEY_BACKSPACE, e.BTN_TR: e.KEY_SPACE}
    TYPING_ACTIONS = {e.BTN_SOUTH: "press", e.BTN_WEST: "shift", e.BTN_EAST: "close", e.BTN_NORTH: "close"}
    MODIFIERS = {"shift": e.KEY_LEFTSHIFT, "ctrl": e.KEY_LEFTCTRL, "alt": e.KEY_LEFTALT, "super": e.KEY_LEFTMETA}
    # Every key the typing keyboard has (it names them as in evdev, e.g. "KEY_A").
    TYPABLE = [getattr(e, f"KEY_{n}") for n in (*"ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789",
               "MINUS", "EQUAL", "LEFTBRACE", "RIGHTBRACE", "BACKSLASH", "SEMICOLON", "APOSTROPHE", "COMMA",
               "DOT", "SLASH", "GRAVE", "SPACE", "ESC", "TAB", "ENTER", "BACKSPACE", "DELETE", "HOME", "END",
               "UP", "DOWN", "LEFT", "RIGHT")]
    KEYS = sorted(set(TYPABLE) | set(BUTTONS.values()) | set(HAT.values()) | set(MODIFIERS.values()))


def curve(v):
    a = max(0.0, abs(v) - DEADZONE) / (1 - DEADZONE)
    return a ** CURVE * (1 if v > 0 else -1)


def _stick_dir(v):
    return -1 if v < -0.55 else 1 if v > 0.55 else 0


class MouseMode(QObject):
    changed = Signal()
    typeRequested = Signal()
    typingKey = Signal(str)

    def __init__(self):
        super().__init__()
        self._enabled = False
        self._dev = None
        self._lock = threading.Lock()
        self._sticks = {}
        self._frac = [0.0, 0.0, 0.0, 0.0]
        self._hat = {}
        self._trigger = 0.0
        self._letters = {}
        self._active = False
        self._typing = False
        self._nav = None
        self._next_nav = 0.0

    @staticmethod
    def supported():
        return UInput is not None

    @Property(bool, notify=changed)
    def available(self):
        return UInput is not None

    @Property(bool, notify=changed)
    def enabled(self):
        return self._enabled

    # Enabled and actually driving an app (an app in front, no overlay), for the indicator.
    @Property(bool, notify=changed)
    def active(self):
        return self._active

    def set_active(self, on):
        if on != self._active:
            self._active = on
            if not on:
                self.set_typing(False)
            self.changed.emit()

    # The typing keyboard is open: the pads drive it instead of the pointer.
    @Property(bool, notify=changed)
    def typing(self):
        return self._typing

    @Slot(bool)
    def set_typing(self, on):
        on = bool(on and self._enabled and self._active)
        if on != self._typing:
            self.release_all()
            self._typing = on
            self.changed.emit()

    @Slot(bool)
    def setEnabled(self, on):
        if on and not self._open():
            on = False
        self._enabled = on
        if not on:
            self._typing = False
            self.release_all()
        self.changed.emit()

    @Slot()
    def toggle(self):
        self.setEnabled(not self._enabled)

    def _open(self):
        if self._dev or not UInput:
            return bool(self._dev)
        caps = {e.EV_KEY: KEYS + [e.BTN_LEFT, e.BTN_RIGHT, e.BTN_MIDDLE], e.EV_REL: [e.REL_X, e.REL_Y, e.REL_WHEEL, e.REL_HWHEEL]}
        try:
            self._dev = UInput(caps, name="X27 TV Gamepad Mouse")
        except OSError:
            return False
        return True

    def _emit(self, events):
        with self._lock:
            if not self._dev:
                return
            for etype, code, value in events:
                self._dev.write(etype, code, value)
            self._dev.syn()

    def release_all(self):
        self._sticks.clear()
        self._hat.clear()
        self._trigger = 0.0
        self._nav = None
        if self._dev:
            self._emit([(e.EV_KEY, k, 0) for k in set(BUTTONS.values()) | set(HAT.values()) | set(TYPING_KEYS.values())])

    def _by_letter(self, dev):
        if dev.path not in self._letters:
            try:
                driver = Path(f"/sys/class/input/{Path(dev.path).name}/device/device/driver").resolve().name
            except OSError:
                driver = ""
            self._letters[dev.path] = dev.info.vendor == MICROSOFT or driver in LETTER_DRIVERS
        return self._letters[dev.path]

    # Gamepad thread.
    def handle(self, dev, ev):
        code = ev.code
        if ev.type == e.EV_KEY and code in (e.BTN_NORTH, e.BTN_WEST) and self._by_letter(dev):
            code = e.BTN_WEST if code == e.BTN_NORTH else e.BTN_NORTH
        if self._typing:
            self._handle_typing(dev, ev, code)
        elif ev.type == e.EV_KEY and code == e.BTN_NORTH:
            if ev.value == 1:
                self.typeRequested.emit()
        elif ev.type == e.EV_KEY and code in BUTTONS and ev.value in (0, 1):
            self._emit([(e.EV_KEY, BUTTONS[code], ev.value)])
        elif ev.type == e.EV_ABS and ev.code in (e.ABS_HAT0X, e.ABS_HAT0Y):
            prev = self._hat.get(ev.code, 0)
            out = []
            if prev:
                out.append((e.EV_KEY, HAT[(ev.code, prev)], 0))
            if ev.value:
                out.append((e.EV_KEY, HAT[(ev.code, ev.value)], 1))
            self._hat[ev.code] = ev.value
            if out:
                self._emit(out)
        elif ev.type == e.EV_ABS and ev.code in (e.ABS_X, e.ABS_Y, e.ABS_RX, e.ABS_RY):
            info = dev.absinfo(ev.code)
            mid, span = (info.max + info.min) / 2, ((info.max - info.min) / 2) or 1
            self._sticks[ev.code] = (ev.value - mid) / span
        elif ev.type == e.EV_ABS and ev.code in (e.ABS_RZ, e.ABS_GAS):
            info = dev.absinfo(ev.code)
            self._trigger = (ev.value - info.min) / ((info.max - info.min) or 1)

    def _handle_typing(self, dev, ev, code):
        if ev.type == e.EV_KEY and code in TYPING_KEYS and ev.value in (0, 1):
            self._emit([(e.EV_KEY, TYPING_KEYS[code], ev.value)])
        elif ev.type == e.EV_KEY and code in TYPING_ACTIONS and ev.value == 1:
            self.typingKey.emit(TYPING_ACTIONS[code])
        elif ev.type == e.EV_ABS and ev.code in (e.ABS_HAT0X, e.ABS_HAT0Y):
            self._hat[ev.code] = ev.value
        elif ev.type == e.EV_ABS and ev.code in (e.ABS_X, e.ABS_Y, e.ABS_RX, e.ABS_RY):
            info = dev.absinfo(ev.code)
            mid, span = (info.max + info.min) / 2, ((info.max - info.min) / 2) or 1
            self._sticks[ev.code] = (ev.value - mid) / span

    def _navigate(self):
        s = self._sticks
        x = self._hat.get(e.ABS_HAT0X) or _stick_dir(s.get(e.ABS_X, 0))
        y = self._hat.get(e.ABS_HAT0Y) or _stick_dir(s.get(e.ABS_Y, 0))
        direction = "left" if x < 0 else "right" if x > 0 else "up" if y < 0 else "down" if y > 0 else None
        now = time.monotonic()
        if direction != self._nav:
            self._nav = direction
            self._next_nav = now + REPEAT_DELAY
        elif not direction or now < self._next_nav:
            return
        else:
            self._next_nav = now + REPEAT_RATE
        if direction:
            self.typingKey.emit(direction)

    # Gamepad thread, every few ms: pointer motion and scrolling from the stick positions
    # (only scrolling while typing, where the left stick moves across the keyboard).
    def tick(self, dt):
        s = self._sticks
        if self._typing:
            self._navigate()
        speed = 0 if self._typing else SPEED * (PRECISION if self._trigger > 0.5 else 1)
        motion = (curve(s.get(e.ABS_X, 0)) * speed * dt, curve(s.get(e.ABS_Y, 0)) * speed * dt,
                  -curve(s.get(e.ABS_RY, 0)) * SCROLL * dt, curve(s.get(e.ABS_RX, 0)) * SCROLL * dt)
        out = []
        for i, (code, v) in enumerate(zip((e.REL_X, e.REL_Y, e.REL_WHEEL, e.REL_HWHEEL), motion)):
            self._frac[i] += v
            whole = int(self._frac[i])
            if whole:
                self._frac[i] -= whole
                out.append((e.EV_REL, code, whole))
            elif not v:
                self._frac[i] = 0.0
        if out:
            self._emit(out)

    # From the typing keyboard: tap one key ("KEY_A"), with the given modifiers held.
    @Slot(str, "QVariantList")
    def tapKey(self, name, mods):
        if not UInput or getattr(e, name, None) not in TYPABLE or not self._open():
            return
        key = getattr(e, name)
        held = [MODIFIERS[m] for m in mods if m in MODIFIERS]
        self._emit([(e.EV_KEY, m, 1) for m in held])
        self._emit([(e.EV_KEY, key, 1)])
        self._emit([(e.EV_KEY, key, 0)])
        self._emit([(e.EV_KEY, m, 0) for m in held])
