// Audio section: pick the output device, set volume and mute.
import QtQuick

SettingsPane {
    Component.onCompleted: { Audio.refresh(); System.refresh() }

    Timer { interval: 4000; running: true; repeat: true; onTriggered: Audio.refresh() }

    rows: {
        const r = [{ kind: "header", label: "Output" }]
        for (const s of Audio.sinks)
            r.push({ kind: "value", label: s.name, selected: s.default, run: () => Audio.setDefault(s.id) })
        if (!Audio.sinks.length)
            r.push({ kind: "note", label: "No audio outputs found." })
        r.push({ kind: "header", label: "Volume" })
        r.push({
            kind: "slider", glyph: System.muted ? "speaker-slash" : "speaker-high", label: "Volume", value: System.muted ? 0 : System.volume,
            valueText: System.muted ? "Muted" : Math.round(System.volume * 100) + "%",
            change: d => System.setVolume(System.volume + d * 0.05)
        })
        r.push({ kind: "toggle", label: "Mute", checked: System.muted, run: () => System.toggleMute() })
        return r
    }
}
