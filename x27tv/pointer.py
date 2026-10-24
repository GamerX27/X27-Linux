# Tracks whether the mouse or the remote/gamepad/keyboard is in use: hover only steers
# focus after a real mouse movement, and the cursor hides while keys are being used.

from PySide6.QtCore import Property, QEvent, QObject, Qt, Signal
from PySide6.QtGui import QGuiApplication

MOVE_THRESHOLD = 4


class Pointer(QObject):
    activeChanged = Signal()

    def __init__(self):
        super().__init__()
        self._active = False
        self._last = None
        self._hidden = False
        self._hide()

    @Property(bool, notify=activeChanged)
    def active(self):
        return self._active

    def _hide(self):
        if not self._hidden:
            QGuiApplication.setOverrideCursor(Qt.BlankCursor)
            self._hidden = True

    def _show(self):
        if self._hidden:
            QGuiApplication.restoreOverrideCursor()
            self._hidden = False

    def _set(self, active):
        if active == self._active:
            return
        self._active = active
        self._show() if active else self._hide()
        self.activeChanged.emit()

    def eventFilter(self, obj, event):
        t = event.type()
        if t == QEvent.KeyPress:
            self._set(False)
        elif obj.isWindowType():
            if t == QEvent.MouseMove:
                pos = event.globalPosition()
                if self._last is not None and (abs(pos.x() - self._last.x()) + abs(pos.y() - self._last.y())) >= MOVE_THRESHOLD:
                    self._set(True)
                self._last = pos
            elif t in (QEvent.MouseButtonPress, QEvent.Wheel):
                self._set(True)
        return False
