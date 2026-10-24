# App catalog: the curated home row from apps.toml, every installed .desktop app for
# "All Apps", icon resolution and cached touch-icons for web shortcuts.

import configparser
import html.parser
import os
import re
import shutil
import threading
import tomllib
import urllib.parse
import urllib.request
from pathlib import Path

from PySide6.QtCore import Property, QObject, Signal, Slot
from PySide6.QtGui import QIcon, QImage

ROOT = Path(__file__).resolve().parent.parent
HOME = Path.home()
CONFIG_DIR = Path(os.environ.get("XDG_CONFIG_HOME", HOME / ".config")) / "x27-tv"
CACHE_DIR = Path(os.environ.get("XDG_CACHE_HOME", HOME / ".cache")) / "x27-tv"
FLATPAK_DIRS = [Path("/var/lib/flatpak"), HOME / ".local/share/flatpak"]


def data_dirs():
    dirs = [Path(os.environ.get("XDG_DATA_HOME", HOME / ".local/share"))]
    dirs += [Path(d) for d in os.environ.get("XDG_DATA_DIRS", "/usr/local/share:/usr/share").split(":") if d]
    dirs += [d / "exports/share" for d in FLATPAK_DIRS]
    seen, out = set(), []
    for d in dirs:
        if d not in seen:
            seen.add(d)
            out.append(d)
    return out


def flatpak_installed(app_id):
    return any((d / "app" / app_id).is_dir() for d in FLATPAK_DIRS)


def resolve_icon(name):
    if not name:
        return ""
    if name.startswith("/"):
        return name if Path(name).is_file() else ""
    return name if QIcon.hasThemeIcon(name) else ""


def browser_app_id(browser, url):
    prefix = Path(browser).name.removesuffix("-stable").removesuffix("-browser")
    parts = urllib.parse.urlsplit(url)
    name = f"{parts.hostname}_{parts.path or '/'}".replace("/", "_")
    return f"{prefix}-{name}-Default"


class _IconLinks(html.parser.HTMLParser):
    def __init__(self):
        super().__init__()
        self.links = []

    def handle_starttag(self, tag, attrs):
        if tag != "link":
            return
        a = dict(attrs)
        rel = (a.get("rel") or "").lower()
        if "icon" in rel and a.get("href"):
            size = max((int(n) for n in re.findall(r"(\d+)x\d+", a.get("sizes") or "")), default=0)
            score = size + (1000 if "apple-touch-icon" in rel else 0)
            self.links.append((score, a["href"]))


def _fetch(url, limit=2_000_000):
    req = urllib.request.Request(url, headers={"User-Agent": "Mozilla/5.0 (X11; Linux x86_64) x27-tv"})
    with urllib.request.urlopen(req, timeout=8) as r:
        return r.read(limit)


def fetch_touch_icon(url, dest):
    candidates = []
    try:
        parser = _IconLinks()
        parser.feed(_fetch(url).decode("utf-8", "replace"))
        candidates = [urllib.parse.urljoin(url, h) for _, h in sorted(parser.links, reverse=True)]
    except Exception:
        pass
    candidates += [urllib.parse.urljoin(url, "/apple-touch-icon.png"), urllib.parse.urljoin(url, "/favicon.ico")]
    for c in candidates:
        try:
            img = QImage.fromData(_fetch(c))
        except Exception:
            continue
        if not img.isNull() and img.width() >= 64:
            dest.parent.mkdir(parents=True, exist_ok=True)
            img.save(str(dest), "PNG")
            return True
    return False


def load_config():
    for path in (CONFIG_DIR / "apps.toml", ROOT / "config/apps.toml"):
        if path.is_file():
            with open(path, "rb") as f:
                return tomllib.load(f)
    return {"app": []}


def slug(name):
    return re.sub(r"[^a-z0-9]+", "-", name.lower()).strip("-")


def build_entry(raw, browser, index):
    accent = raw.get("accent") or ["#3a3a3c", "#1c1c1e"]
    e = {
        "key": "app-" + (slug(raw.get("name", "")) or str(index)),
        "name": raw.get("name", "App"),
        "tagline": raw.get("tagline", ""),
        "accent1": accent[0],
        "accent2": accent[-1],
        "hero": raw.get("hero", ""),
        "flatpak": "",
        "url": "",
        "command": [],
        "installed": True,
    }
    if "flatpak" in raw:
        fid = raw["flatpak"]
        e.update(flatpak=fid, command=["flatpak", "run", fid], installed=flatpak_installed(fid))
        e["appId"] = raw.get("app_id", fid)
        e["icon"] = resolve_icon(raw.get("icon", fid))
    elif "url" in raw:
        url = raw["url"]
        e.update(url=url, command=[browser, f"--app={url}"], installed=bool(shutil.which(browser)))
        e["appId"] = raw.get("app_id", browser_app_id(browser, url))
        cached = CACHE_DIR / "icons" / f"{urllib.parse.urlsplit(url).hostname}.png"
        e["icon"] = resolve_icon(raw.get("icon", str(cached)))
    else:
        cmd = raw.get("exec", "").split()
        e.update(command=cmd, installed=bool(cmd and shutil.which(cmd[0])))
        e["appId"] = raw.get("app_id", Path(cmd[0]).name if cmd else "")
        e["icon"] = resolve_icon(raw.get("icon", Path(cmd[0]).name if cmd else ""))
    return e


def scan_desktop_entries():
    found = {}
    for d in reversed(data_dirs()):
        appdir = d / "applications"
        if not appdir.is_dir():
            continue
        for path in appdir.rglob("*.desktop"):
            found[str(path.relative_to(appdir)).replace("/", "-")] = path
    entries = []
    for desktop_id, path in found.items():
        cp = configparser.ConfigParser(interpolation=None, strict=False)
        try:
            cp.read(path, encoding="utf-8")
            de = cp["Desktop Entry"]
        except Exception:
            continue
        if de.get("Type") != "Application" or de.get("NoDisplay") == "true" or de.get("Hidden") == "true":
            continue
        if de.get("OnlyShowIn") and "x27-tv" not in de.get("OnlyShowIn"):
            continue
        if "Exec" not in de or "Name" not in de:
            continue
        entries.append({
            "key": f"desktop-{desktop_id}",
            "name": de["Name"],
            "tagline": de.get("Comment", ""),
            "icon": resolve_icon(de.get("Icon", "")),
            "appId": de.get("StartupWMClass", desktop_id.removesuffix(".desktop")),
            "command": ["gio", "launch", str(path)],
            "accent1": "#3a3a3c",
            "accent2": "#1c1c1e",
            "hero": "", "flatpak": "", "url": "", "installed": True,
        })
    entries.sort(key=lambda e: e["name"].lower())
    return entries


class AppStore(QObject):
    appsChanged = Signal()
    allAppsChanged = Signal()
    _iconReady = Signal(str, str)

    def __init__(self, prefs):
        super().__init__()
        self.prefs = prefs
        cfg = load_config()
        self.browser = cfg.get("browser", "brave-browser")
        self._apps = [build_entry(raw, self.browser, i) for i, raw in enumerate(cfg.get("app", []))]
        self._all = []
        self._iconReady.connect(self._set_icon)
        for e in self._apps:
            if e["url"] and not e["icon"]:
                threading.Thread(target=self._fetch_icon, args=(e["key"], e["url"]), daemon=True).start()

    def _fetch_icon(self, key, url):
        dest = CACHE_DIR / "icons" / f"{urllib.parse.urlsplit(url).hostname}.png"
        if fetch_touch_icon(url, dest):
            self._iconReady.emit(key, str(dest))

    @Slot(str, str)
    def _set_icon(self, key, path):
        for e in self._apps:
            if e["key"] == key:
                e["icon"] = path
        self.appsChanged.emit()

    def _ordered(self):
        rank = {k: i for i, k in enumerate(self.prefs.get("home_order", []))}
        return sorted(self._apps, key=lambda e: rank.get(e["key"], len(rank) + self._apps.index(e)))

    @Property("QVariantList", notify=appsChanged)
    def apps(self):
        hidden = set(self.prefs.get("home_hidden", []))
        return [e for e in self._ordered() if e["key"] not in hidden]

    @Property("QVariantList", notify=appsChanged)
    def homeApps(self):
        hidden = set(self.prefs.get("home_hidden", []))
        return [dict(e, hidden=e["key"] in hidden) for e in self._ordered()]

    @Slot(str, int)
    def moveApp(self, key, delta):
        keys = [e["key"] for e in self._ordered()]
        i = keys.index(key)
        j = max(0, min(len(keys) - 1, i + delta))
        keys.insert(j, keys.pop(i))
        self.prefs.set("home_order", keys)
        self.appsChanged.emit()

    @Slot(str, bool)
    def setHidden(self, key, hidden):
        keys = [k for k in self.prefs.get("home_hidden", []) if k != key] + ([key] if hidden else [])
        self.prefs.set("home_hidden", keys)
        self.appsChanged.emit()

    @Slot()
    def resetHome(self):
        self.prefs.set("home_order", [])
        self.prefs.set("home_hidden", [])
        self.appsChanged.emit()

    @Property("QVariantList", notify=allAppsChanged)
    def allApps(self):
        return self._all

    @Slot()
    def refresh(self):
        for e in self._apps:
            if e["flatpak"]:
                e["installed"] = flatpak_installed(e["flatpak"])
                e["icon"] = e["icon"] or resolve_icon(e["flatpak"])
        self.appsChanged.emit()
        self._all = scan_desktop_entries()
        self.allAppsChanged.emit()

    def find(self, key):
        return next((e for e in self._apps + self._all if e["key"] == key), None)
