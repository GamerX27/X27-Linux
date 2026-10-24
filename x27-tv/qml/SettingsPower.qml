// Power section: screen-off and auto-sleep timers (run by swayidle in the X27 TV
// session) and an immediate Sleep.
import QtQuick

SettingsPane {
    id: page

    readonly property var screenChoices: [0, 10, 30, 60]
    readonly property var sleepChoices: [0, 30, 60, 120]

    function label(m) { return m === 0 ? "Never" : m < 60 ? m + " minutes" : (m / 60) + (m === 60 ? " hour" : " hours") }

    function cycle(list, value, d) {
        const i = Math.max(0, list.indexOf(value))
        return list[((i + d) % list.length + list.length) % list.length]
    }

    rows: {
        const r = []
        if (!idleSupported)
            r.push({ kind: "note", label: "These timers run in the X27 TV session (needs swayidle). Your choices are saved and apply there." })
        r.push({ kind: "option", glyph: "monitor", label: "Turn Off Screen", value: label(Prefs.screenOff),
                 change: d => Prefs.setScreenOff(page.cycle(page.screenChoices, Prefs.screenOff, d)) })
        r.push({ kind: "option", glyph: "moon", label: "Sleep After", value: label(Prefs.sleepAfter),
                 change: d => Prefs.setSleepAfter(page.cycle(page.sleepChoices, Prefs.sleepAfter, d)) })
        r.push({ kind: "note", label: "Playing video keeps the TV awake." })
        r.push({ kind: "header", label: "Now" })
        r.push({ kind: "action", glyph: "moon", label: "Sleep Now", run: () => System.suspend() })
        return r
    }
}
