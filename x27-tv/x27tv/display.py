# Display settings backend: lists outputs and modes and applies resolution, refresh rate
# and scale with a timed revert. Uses wlr-randr in the x27-tv session, kscreen-doctor in KDE.

import json
import os
import shutil
import subprocess
from pathlib import Path

from PySide6.QtCore import Property, QObject, QTimer, Signal, Slot

from .prefs import Prefs
from .proc import run

REVERT_SECONDS = 15
OFF_STATE = Path(os.environ.get("XDG_CACHE_HOME", Path.home() / ".cache")) / "x27-tv/screen-off.json"


def pick_backend(session):
    if (session or os.environ.get("LABWC_PID")) and shutil.which("wlr-randr"):
        return "wlr"
    if "KDE" in os.environ.get("XDG_CURRENT_DESKTOP", "") and shutil.which("kscreen-doctor"):
        return "kde"
    return ""


def _dedupe(modes):
    seen, out = set(), []
    for m in sorted(modes, key=lambda m: (-m["w"] * m["h"], -m["r"])):
        key = (m["w"], m["h"], round(m["r"]))
        if key not in seen:
            seen.add(key)
            out.append(m)
    return out


def parse_wlr(text):
    outputs = []
    for o in json.loads(text or "[]"):
        modes = [{"w": m["width"], "h": m["height"], "r": m["refresh"], "id": ""} for m in o.get("modes", [])]
        cur = next((m for m in o.get("modes", []) if m.get("current")), None)
        outputs.append({
            "name": o["name"],
            "label": o.get("description") or o["name"],
            "enabled": o.get("enabled", True),
            "w": cur["width"] if cur else 0, "h": cur["height"] if cur else 0, "r": cur["refresh"] if cur else 0,
            "scale": o.get("scale", 1.0),
            "modes": _dedupe(modes),
        })
    return outputs


def parse_kde(text):
    outputs = []
    for o in json.loads(text or "{}").get("outputs", []):
        if not o.get("connected"):
            continue
        modes = [{"w": m["size"]["width"], "h": m["size"]["height"], "r": m["refreshRate"], "id": m["id"]} for m in o.get("modes", [])]
        cur = next((m for m in modes if m["id"] == o.get("currentModeId")), None)
        outputs.append({
            "name": o["name"],
            "label": o["name"],
            "enabled": o.get("enabled", True),
            "w": cur["w"] if cur else 0, "h": cur["h"] if cur else 0, "r": cur["r"] if cur else 0,
            "scale": o.get("scale", 1.0),
            "modes": _dedupe(modes),
        })
    return outputs


def wlr_args(name, w, h, r, scale):
    return ["--output", name, "--on", "--mode", f"{w}x{h}@{r:.3f}Hz", "--scale", f"{scale:g}"]


def _wlr_outputs():
    try:
        return parse_wlr(subprocess.run(["wlr-randr", "--json"], capture_output=True, text=True, timeout=3).stdout)
    except (OSError, subprocess.TimeoutExpired, ValueError):
        return []


def apply_saved(prefs=None):
    saved = (prefs or Prefs()).get("display", {})
    if not saved or not shutil.which("wlr-randr"):
        return
    args = []
    for o in _wlr_outputs():
        s = saved.get(o["name"])
        if s:
            args += wlr_args(o["name"], s["w"], s["h"], s["r"], s["scale"])
    if args:
        subprocess.run(["wlr-randr", *args], timeout=5)


def screen_off():
    outputs = [o["name"] for o in _wlr_outputs() if o["enabled"]]
    if outputs:
        OFF_STATE.parent.mkdir(parents=True, exist_ok=True)
        OFF_STATE.write_text(json.dumps(outputs))
        subprocess.run(["wlr-randr", *[a for n in outputs for a in ("--output", n, "--off")]], timeout=5)


def screen_on():
    try:
        outputs = json.loads(OFF_STATE.read_text())
    except (OSError, ValueError):
        return
    OFF_STATE.unlink(missing_ok=True)
    subprocess.run(["wlr-randr", *[a for n in outputs for a in ("--output", n, "--on")]], timeout=5)
    apply_saved()


class Display(QObject):
    outputsChanged = Signal()
    pendingChanged = Signal()
    secondsChanged = Signal()

    def __init__(self, prefs, session):
        super().__init__()
        self.prefs = prefs
        self.backend = pick_backend(session)
        self._outputs = []
        self._previous = None
        self._seconds = 0
        self._timer = QTimer(self, interval=1000, timeout=self._tick)

    @Property(bool, constant=True)
    def available(self):
        return bool(self.backend)

    @Property("QVariantList", notify=outputsChanged)
    def outputs(self):
        return self._outputs

    @Property(bool, notify=pendingChanged)
    def pending(self):
        return self._previous is not None

    @Property(int, notify=secondsChanged)
    def seconds(self):
        return self._seconds

    @Slot()
    def refresh(self):
        if self.backend == "wlr":
            run(self, "wlr-randr", ["--json"], lambda c, out, e: self._set(parse_wlr(out) if c == 0 else []))
        elif self.backend == "kde":
            run(self, "kscreen-doctor", ["-j"], lambda c, out, e: self._set(parse_kde(out) if c == 0 else []))

    def _set(self, outputs):
        self._outputs = outputs
        self.outputsChanged.emit()

    def _find(self, name):
        return next((o for o in self._outputs if o["name"] == name), None)

    def _command(self, name, w, h, r, scale):
        if self.backend == "wlr":
            return "wlr-randr", wlr_args(name, w, h, r, scale)
        out = self._find(name)
        mode = min(out["modes"], key=lambda m: (m["w"] != w or m["h"] != h, abs(m["r"] - r)))
        return "kscreen-doctor", [f"output.{name}.mode.{mode['id']}", f"output.{name}.scale.{scale:g}"]

    @Slot(str, int, int, float, float)
    def apply(self, name, w, h, r, scale):
        out = self._find(name)
        if not out:
            return
        program, args = self._command(name, w, h, r, scale)
        self._seconds = REVERT_SECONDS
        self.secondsChanged.emit()
        self._timer.start()
        if self._previous is None:
            self._previous = (name, out["w"], out["h"], out["r"], out["scale"])
            self.pendingChanged.emit()
        run(self, program, args, lambda *_: self.refresh())

    @Slot()
    def keep(self):
        self._timer.stop()
        self._previous = None
        self.pendingChanged.emit()
        saved = dict(self.prefs.get("display", {}))
        for o in self._outputs:
            saved[o["name"]] = {"w": o["w"], "h": o["h"], "r": o["r"], "scale": o["scale"]}
        self.prefs.set("display", saved)

    @Slot()
    def revert(self):
        self._timer.stop()
        prev, self._previous = self._previous, None
        self.pendingChanged.emit()
        if prev:
            program, args = self._command(*prev)
            run(self, program, args, lambda *_: self.refresh())

    def _tick(self):
        self._seconds -= 1
        self.secondsChanged.emit()
        if self._seconds <= 0:
            self.revert()
