// Display section: resolution, refresh rate and scale, edited as a draft and applied
// with a "keep or revert" countdown.
import QtQuick

SettingsPane {
    id: page

    property int outIndex: 0
    property var draft: null

    readonly property var out: Display.outputs.length ? Display.outputs[Math.min(outIndex, Display.outputs.length - 1)] : null
    readonly property var scales: [1, 1.25, 1.5, 1.75, 2]

    function current() {
        return draft || (out ? { w: out.w, h: out.h, r: out.r, scale: out.scale } : null)
    }

    function resolutions() {
        const seen = [], list = []
        for (const m of out.modes) {
            const k = m.w + "x" + m.h
            if (seen.indexOf(k) < 0) { seen.push(k); list.push({ w: m.w, h: m.h }) }
        }
        return list
    }

    function rates(w, h) {
        return out.modes.filter(m => m.w === w && m.h === h).map(m => m.r)
    }

    function wrap(i, n) { return (i % n + n) % n }

    function changeResolution(d) {
        const c = current(), list = resolutions()
        const i = list.findIndex(x => x.w === c.w && x.h === c.h)
        const next = list[wrap(i + d, list.length)]
        const rs = rates(next.w, next.h)
        const r = rs.reduce((best, x) => Math.abs(x - c.r) < Math.abs(best - c.r) ? x : best, rs[0])
        draft = { w: next.w, h: next.h, r: r, scale: c.scale }
    }

    function changeRate(d) {
        const c = current(), rs = rates(c.w, c.h)
        const i = rs.findIndex(x => Math.round(x) === Math.round(c.r))
        draft = { w: c.w, h: c.h, r: rs[wrap(i + d, rs.length)], scale: c.scale }
    }

    function changeScale(d) {
        const c = current()
        const i = scales.findIndex(x => Math.abs(x - c.scale) < 0.01)
        draft = { w: c.w, h: c.h, r: c.r, scale: scales[wrap((i < 0 ? 0 : i) + d, scales.length)] }
    }

    function apply() {
        const c = current()
        Display.apply(out.name, c.w, c.h, c.r, c.scale)
        draft = null
    }

    Component.onCompleted: Display.refresh()
    onOutIndexChanged: draft = null

    Connections {
        target: Display
        function onPendingChanged() { page.reset() }
    }

    rows: {
        if (!Display.available)
            return [{ kind: "note", label: "Display settings need wlr-randr (in the X27 TV session) or KDE's kscreen-doctor." }]
        if (Display.pending)
            return [
                { kind: "note", label: "Keep these display settings? Reverting in " + Display.seconds + " s." },
                { kind: "action", label: "Keep Settings", run: () => Display.keep() },
                { kind: "action", label: "Revert", run: () => Display.revert() }
            ]
        if (!out)
            return [{ kind: "note", label: "Looking for displays…" }]
        const c = current(), n = Display.outputs.length, dirty = draft !== null
        const r = []
        if (n > 1)
            r.push({ kind: "option", label: "Display", value: out.label, change: d => page.outIndex = wrap(outIndex + d, n) })
        r.push({ kind: "option", label: "Resolution", value: c.w + " × " + c.h, change: d => page.changeResolution(d) })
        r.push({ kind: "option", label: "Refresh Rate", value: Math.round(c.r) + " Hz", change: d => page.changeRate(d) })
        r.push({ kind: "option", label: "Scale", value: Math.round(c.scale * 100) + "%", change: d => page.changeScale(d) })
        r.push({
            kind: "action", label: dirty ? "Apply Changes" : "No Changes",
            detail: dirty ? "You'll have 15 seconds to keep or revert" : "",
            run: () => { if (dirty) page.apply() }
        })
        r.push({ kind: "note", label: "Use ‹ › to change a value, then choose Apply Changes." })
        return r
    }
}
