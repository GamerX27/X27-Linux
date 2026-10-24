# x27-tv entry point: sets up Qt, exposes the backends to QML, loads the UI and
# routes gamepad input into the window.

import argparse
import signal
import sys
import urllib.parse
from pathlib import Path

from PySide6.QtCore import QByteArray, QEvent, QSize, Qt, QUrl
from PySide6.QtGui import QColor, QGuiApplication, QIcon, QKeyEvent, QPainter, QPixmap
from PySide6.QtSvg import QSvgRenderer
from PySide6.QtQml import QQmlApplicationEngine
from PySide6.QtQuick import QQuickImageProvider

from .apps import ROOT, AppStore, data_dirs
from .audio import Audio
from .bluetooth import Bluetooth
from .display import Display, apply_saved
from .gamepad import Gamepad
from .launcher import SELF_ID, Launcher, go_home
from .network import Network
from .pointer import Pointer
from .prefs import IdleManager, Prefs
from .system import System
from .updates import Updates


UI_ICONS = ROOT / "qml/icons"


def render_ui_icon(name, color, side):
    pm = QPixmap(side, side)
    pm.fill(Qt.transparent)
    path = UI_ICONS / f"{Path(name).name}.svg"
    if not path.is_file():
        return pm
    c = QColor(color)
    svg = path.read_text().replace('fill="currentColor"', f'fill="{c.name()}" fill-opacity="{c.alphaF():.3f}"')
    painter = QPainter(pm)
    QSvgRenderer(QByteArray(svg.encode())).render(painter)
    painter.end()
    return pm


class IconProvider(QQuickImageProvider):
    def __init__(self):
        super().__init__(QQuickImageProvider.ImageType.Pixmap)

    def requestPixmap(self, id, size, requested):
        name = urllib.parse.unquote(id)
        side = min(max(requested.width(), requested.height()) or 256, 512)
        if name.startswith("ui:"):
            _, icon, color = name.split(":", 2)
            pm = render_ui_icon(icon, color, side)
        elif name.startswith("/"):
            pm = QPixmap(name)
            if not pm.isNull():
                pm = pm.scaled(side, side, Qt.KeepAspectRatio, Qt.SmoothTransformation)
        else:
            pm = QIcon.fromTheme(name).pixmap(QSize(side, side))
        if size is not None:
            size.setWidth(pm.width())
            size.setHeight(pm.height())
        return pm


def setup_icons():
    paths = QIcon.themeSearchPaths()
    for d in data_dirs():
        p = str(d / "icons")
        if p not in paths:
            paths.append(p)
    QIcon.setThemeSearchPaths(paths)
    QIcon.setFallbackThemeName("hicolor")
    if QIcon.themeName() in ("", "hicolor"):
        for theme in ("Papirus-Dark", "breeze-dark", "Adwaita"):
            if any(Path(p, theme, "index.theme").is_file() for p in paths):
                QIcon.setThemeName(theme)
                break


def main():
    parser = argparse.ArgumentParser(prog="x27-tv")
    parser.add_argument("--windowed", action="store_true", help="run in a window (for testing)")
    parser.add_argument("--session", action="store_true", help="running as the x27-tv labwc session")
    args = parser.parse_args()

    QGuiApplication.setDesktopFileName(SELF_ID)
    QGuiApplication.setApplicationName("x27-tv")
    app = QGuiApplication(sys.argv)
    signal.signal(signal.SIGINT, signal.SIG_DFL)
    setup_icons()
    pointer = Pointer()
    app.installEventFilter(pointer)

    prefs = Prefs()
    if args.session:
        apply_saved(prefs)
    store = AppStore(prefs)
    launcher = Launcher(store)
    system = System(args.session)
    audio = Audio()
    audio.defaultChanged.connect(system.refresh)
    display = Display(prefs, args.session)
    network = Network()
    bluetooth = Bluetooth()
    updates = Updates(prefs)
    idle = IdleManager(prefs, args.session)
    store.refresh()

    engine = QQmlApplicationEngine()
    engine.addImageProvider("icon", IconProvider())
    ctx = engine.rootContext()
    ctx.setContextProperty("Apps", store)
    ctx.setContextProperty("Launcher", launcher)
    ctx.setContextProperty("System", system)
    ctx.setContextProperty("Pointer", pointer)
    ctx.setContextProperty("Prefs", prefs)
    ctx.setContextProperty("Audio", audio)
    ctx.setContextProperty("Display", display)
    ctx.setContextProperty("Network", network)
    ctx.setContextProperty("Bluetooth", bluetooth)
    ctx.setContextProperty("Updates", updates)
    ctx.setContextProperty("idleSupported", idle.enabled)
    ctx.setContextProperty("startWindowed", args.windowed)
    engine.load(QUrl.fromLocalFile(str(ROOT / "qml/Main.qml")))
    if not engine.rootObjects():
        return 1
    window = engine.rootObjects()[0]
    window.activeChanged.connect(lambda: window.isActive() and store.refresh())

    def inject(key):
        if not window.isActive():
            return
        for kind in (QEvent.KeyPress, QEvent.KeyRelease):
            QGuiApplication.sendEvent(window, QKeyEvent(kind, key, Qt.NoModifier))

    def home():
        if not go_home():
            window.requestActivate()
        window.goHome()

    pad = None
    if Gamepad.available():
        pad = Gamepad()
        pad.key.connect(inject)
        pad.home.connect(home)
        pad.start()

    code = app.exec()
    if pad:
        pad.requestInterruption()
        pad.wait(500)
    return code


if __name__ == "__main__":
    sys.exit(main())
