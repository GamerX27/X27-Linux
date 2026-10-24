// Software Update section: the installed build, a downloaded update waiting for a restart,
// and checking now. Updates also download on their own once a day.
import QtQuick

SettingsPane {
    Component.onCompleted: Updates.refresh()

    rows: {
        const r = []
        if (Updates.busy) r.push({ kind: "note", label: Updates.busy })
        if (Updates.error) r.push({ kind: "note", label: Updates.error, danger: true })

        r.push({ kind: "header", label: "This TV" })
        if (Updates.systemUpdates) r.push({ kind: "info", label: "Installed", value: Updates.current || "…" })
        if (Updates.pending) {
            r.push({ kind: "info", label: "Ready to Install", value: Updates.pending })
            r.push({ kind: "action", glyph: "arrow-fat-up", label: "Restart to Install", detail: "Takes a minute longer than a normal restart",
                     confirm: "Press again to restart and update", run: () => System.reboot() })
        }
        r.push({ kind: "info", label: "Last Checked", value: Updates.lastChecked })
        r.push({
            kind: "action", glyph: "arrow-clockwise",
            label: Updates.busy ? "Checking…" : "Check for Updates",
            run: () => Updates.checkNow()
        })
        r.push({ kind: "note", label: Updates.systemUpdates
            ? "The system and your apps update on their own every day. System updates download in the background and install the next time the TV restarts."
            : "Your apps update on their own every day. System updates are managed outside X27 TV on this computer." })
        return r
    }
}
