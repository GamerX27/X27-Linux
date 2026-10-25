# x27-tv entry point: sets up Qt, exposes the backends to QML, loads the UI, routes gamepad
# input into the window (or the Quick Menu when it's open), and answers x27-tv-ctl over the
# session bus (org.x27tv.Launcher).

import argparse
import signal
import sys
import urllib.parse
from pathlib import Path

from PySide6.QtCore import ClassInfo, QByteArray, QEvent, QObject, QSize, Qt, QUrl, Signal, Slot
from PySide6.QtDBus import QDBusConnection
from PySide6.QtGui import QColor, QGuiApplication, QIcon, QKeyEvent, QPainter, QPixmap
from PySide6.QtSvg import QSvgRenderer
from PySide6.QtQml import QQmlApplicationEngine
from PySide6.QtQuick import QQuickImageProvider

from .apps import ROOT, AppStore, data_dirs
from .audio import Audio
from .bluetooth import Bluetooth
from .display import Display, apply_saved
from .gamepad import Gamepad
from .launcher import SELF_ID, Launcher
from .network import Network
from .padmouse import MouseMode
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


@ClassInfo({"D-Bus Interface": "org.x27tv.Launcher"})
class Remote(QObject):
    quick = Signal()

    @Slot()
    def QuickMenu(self):
        self.quick.emit()


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
    mouse = MouseMode()
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
    ctx.setContextProperty("Mouse", mouse)
    ctx.setContextProperty("idleSupported", idle.enabled)
    ctx.setContextProperty("startWindowed", args.windowed)
    engine.load(QUrl.fromLocalFile(str(ROOT / "qml/Main.qml")))
    if not engine.rootObjects():
        return 1
    window = engine.rootObjects()[0]
    window.activeChanged.connect(lambda: window.isActive() and store.refresh())

    def inject(key):
        menu = window.property("quickMenu")
        target = menu if menu is not None and menu.isVisible() else window
        if not target.isActive():
            return
        for kind in (QEvent.KeyPress, QEvent.KeyRelease):
            QGuiApplication.sendEvent(target, QKeyEvent(kind, key, Qt.NoModifier))

    def home():
        launcher.home()
        window.requestActivate()
        window.goHome()

    # Guide/Home (gamepad, remote, Super, Super+Q): closes the Quick Menu if it's open, opens it
    # over the app in front, or goes Home in the launcher.
    def guide():
        menu = window.property("quickMenu")
        if menu is not None and menu.isVisible():
            menu.close()
        elif window.isActive():
            window.goHome()
        else:
            app_id = launcher.front_app()
            if app_id and menu is not None:
                window.quick(app_id)
            else:
                home()

    remote = Remote()
    remote.quick.connect(guide)
    bus = QDBusConnection.sessionBus()
    if bus.isConnected() and bus.registerService("org.x27tv.Launcher"):
        bus.registerObject("/", remote, QDBusConnection.ExportAllSlots)

    def type_into_app():
        menu = window.property("quickMenu")
        if menu is not None:
            app_id = launcher.front_app()
            w = next((x for x in launcher.windows if x["appId"] == app_id), None)
            menu.openKeyboard(w["name"] if w else "")

    mouse.typeRequested.connect(type_into_app)

    pad = None
    if Gamepad.available():
        pad = Gamepad(mouse if MouseMode.supported() else None)
        pad.key.connect(inject)
        pad.home.connect(guide)
        pad.mouseToggle.connect(mouse.toggle)
        menu = window.property("quickMenu")

        # The pads drive the virtual mouse only with an app in front; in the launcher and the
        # Quick Menu they navigate as usual.
        def route():
            overlay = menu is not None and menu.isVisible()
            pad.set_grab(overlay)
            on = mouse.enabled and not overlay and not window.isActive()
            if pad.route_mouse and not on:
                mouse.release_all()
            pad.set_route_mouse(on)

        if menu is not None:
            menu.visibleChanged.connect(route)
        window.activeChanged.connect(route)
        mouse.changed.connect(route)
        pad.start()

    window.activeChanged.connect(lambda: launcher.set_background(not window.isActive()))
    app.aboutToQuit.connect(launcher.resume_all)

    code = app.exec()
    if pad:
        pad.requestInterruption()
        pad.wait(500)
    return code


if __name__ == "__main__":
    sys.exit(main())
