# Gamepad as mouse and keyboard, for apps that don't support a gamepad: a virtual uinput
# device the compositor treats like any other mouse/keyboard. The left stick moves the
# pointer (hold the right trigger for slow, precise movement), the right stick scrolls,
# A/X click left/right (A held drags), B is Escape, the
# D-pad arrow keys, Start Enter, Select Tab, LB Backspace, RB Space, and Y asks for the
# on-screen keyboard, whose text is then typed here. Gamepad events arrive on the gamepad
# thread (handle/tick); typing comes from the UI thread, hence the lock.

import threading

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
TYPE_DELAY_MS = 300  # lets focus get back to the app after the keyboard closes

if UInput:
    BUTTONS = {e.BTN_SOUTH: e.BTN_LEFT, e.BTN_WEST: e.BTN_RIGHT, e.BTN_EAST: e.KEY_ESC,
               e.BTN_START: e.KEY_ENTER, e.BTN_SELECT: e.KEY_TAB, e.BTN_TL: e.KEY_BACKSPACE, e.BTN_TR: e.KEY_SPACE}
    HAT = {(e.ABS_HAT0X, -1): e.KEY_LEFT, (e.ABS_HAT0X, 1): e.KEY_RIGHT, (e.ABS_HAT0Y, -1): e.KEY_UP, (e.ABS_HAT0Y, 1): e.KEY_DOWN}

    # Characters the on-screen keyboard can produce, on the US layout the session uses:
    # (key, shift).
    CHARS = {" ": (e.KEY_SPACE, False)}
    for ch in "abcdefghijklmnopqrstuvwxyz":
        CHARS[ch] = (getattr(e, f"KEY_{ch.upper()}"), False)
        CHARS[ch.upper()] = (getattr(e, f"KEY_{ch.upper()}"), True)
    for plain, shifted in zip("1234567890", "!@#$%^&*()"):
        key = getattr(e, f"KEY_{plain}")
        CHARS[plain], CHARS[shifted] = (key, False), (key, True)
    for plain, shifted, key in (("-", "_", e.KEY_MINUS), ("=", "+", e.KEY_EQUAL), ("[", "{", e.KEY_LEFTBRACE),
                                ("]", "}", e.KEY_RIGHTBRACE), ("\\", "|", e.KEY_BACKSLASH), (";", ":", e.KEY_SEMICOLON),
                                ("'", '"', e.KEY_APOSTROPHE), (",", "<", e.KEY_COMMA), (".", ">", e.KEY_DOT),
                                ("/", "?", e.KEY_SLASH), ("`", "~", e.KEY_GRAVE)):
        CHARS[plain], CHARS[shifted] = (key, False), (key, True)
    KEYS = sorted({k for k, _ in CHARS.values()} | set(BUTTONS.values()) | set(HAT.values()) | {e.KEY_LEFTSHIFT})


def curve(v):
    a = max(0.0, abs(v) - DEADZONE) / (1 - DEADZONE)
    return a ** CURVE * (1 if v > 0 else -1)


class MouseMode(QObject):
    changed = Signal()
    typeRequested = Signal()

    def __init__(self):
        super().__init__()
        self._enabled = False
        self._dev = None
        self._lock = threading.Lock()
        self._sticks = {}
        self._frac = [0.0, 0.0, 0.0, 0.0]
        self._hat = {}
        self._trigger = 0.0

    @staticmethod
    def supported():
        return UInput is not None

    @Property(bool, notify=changed)
    def available(self):
        return UInput is not None

    @Property(bool, notify=changed)
    def enabled(self):
        return self._enabled

    @Slot(bool)
    def setEnabled(self, on):
        if on and not self._open():
            on = False
        self._enabled = on
        if not on:
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
        if self._dev:
            self._emit([(e.EV_KEY, k, 0) for k in set(BUTTONS.values()) | set(HAT.values())])

    # Gamepad thread.
    def handle(self, dev, ev):
        if ev.type == e.EV_KEY and ev.code == e.BTN_NORTH:
            if ev.value == 1:
                self.typeRequested.emit()
        elif ev.type == e.EV_KEY and ev.code in BUTTONS and ev.value in (0, 1):
            self._emit([(e.EV_KEY, BUTTONS[ev.code], ev.value)])
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

    # Gamepad thread, every few ms: pointer motion and scrolling from the stick positions.
    def tick(self, dt):
        s = self._sticks
        speed = SPEED * (PRECISION if self._trigger > 0.5 else 1)
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

    @Slot(str)
    def typeText(self, text):
        QTimer.singleShot(TYPE_DELAY_MS, lambda: self._type(text))

    def _type(self, text):
        if not self._open():
            return
        for ch in text:
            if ch not in CHARS:
                continue
            key, shift = CHARS[ch]
            if shift:
                self._emit([(e.EV_KEY, e.KEY_LEFTSHIFT, 1)])
            self._emit([(e.EV_KEY, key, 1)])
            self._emit([(e.EV_KEY, key, 0)])
            if shift:
                self._emit([(e.EV_KEY, e.KEY_LEFTSHIFT, 0)])
