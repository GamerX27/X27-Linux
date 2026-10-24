// Home Screen section: reorder the app row (OK to pick up, ▲▼ to move, OK to drop) and
// show or hide apps with ‹ ›.
import QtQuick

SettingsPane {
    rows: {
        const r = [{ kind: "note", label: "OK picks an app up, ▲ ▼ moves it, OK puts it down. ‹ › shows or hides it." }]
        for (const e of Apps.homeApps)
            r.push({
                kind: "app", label: e.name, icon: e.icon, dimmed: e.hidden,
                value: e.hidden ? "Hidden" : "Shown",
                move: d => Apps.moveApp(e.key, d),
                change: d => Apps.setHidden(e.key, !e.hidden)
            })
        r.push({ kind: "action", label: "Reset to Default", confirm: "Press again to reset the home row", run: () => Apps.resetHome() })
        return r
    }
}
