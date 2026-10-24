# Audio settings backend: lists PipeWire output devices from `wpctl status` and switches
# the default one.

import re

from PySide6.QtCore import Property, QObject, Signal, Slot

from .proc import run

SINK_LINE = re.compile(r"^[\s│├└─]*(\*)?\s*(\d+)\.\s+(.*?)\s*(?:\[vol: [\d.]+(?: MUTED)?\])?\s*$")


def parse_sinks(text):
    sinks, section, in_sinks = [], None, False
    for line in text.splitlines():
        stripped = line.strip(" │├└─")
        if line and not line[0].isspace() and stripped:
            section = stripped
            in_sinks = False
            continue
        if section != "Audio":
            continue
        if stripped.endswith(":"):
            in_sinks = stripped == "Sinks:"
            continue
        if in_sinks:
            m = SINK_LINE.match(line)
            if m:
                sinks.append({"id": int(m.group(2)), "name": m.group(3), "default": bool(m.group(1))})
    return sinks


class Audio(QObject):
    sinksChanged = Signal()
    defaultChanged = Signal()

    def __init__(self):
        super().__init__()
        self._sinks = []

    @Property("QVariantList", notify=sinksChanged)
    def sinks(self):
        return self._sinks

    @Slot()
    def refresh(self):
        run(self, "wpctl", ["status"], self._parsed)

    def _parsed(self, code, out, err):
        sinks = parse_sinks(out)
        if sinks != self._sinks:
            self._sinks = sinks
            self.sinksChanged.emit()

    @Slot(int)
    def setDefault(self, sink_id):
        for s in self._sinks:
            s["default"] = s["id"] == sink_id
        self.sinksChanged.emit()
        run(self, "wpctl", ["set-default", str(sink_id)], lambda *_: (self.refresh(), self.defaultChanged.emit()))
