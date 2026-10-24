// Bluetooth section: power, paired devices (connect/disconnect/forget) and searching
// for new controllers, headphones and remotes to pair.
import QtQuick

SettingsPane {
    id: page

    property string selected: ""

    readonly property var kinds: ({ gamepad: "Controller", audio: "Audio", remote: "Remote", phone: "Phone", other: "Device" })
    readonly property var glyphs: ({ gamepad: "game-controller", audio: "headphones", remote: "keyboard", phone: "device-mobile", other: "bluetooth" })

    function close() { selected = ""; reset() }

    backHandler: () => { if (selected) { close(); return true } return false }

    Component.onCompleted: { Bluetooth.clearError(); Bluetooth.refresh() }

    Timer { interval: 3000; running: !Bluetooth.scanning; repeat: true; onTriggered: Bluetooth.refresh() }

    rows: {
        const r = []
        if (Bluetooth.busy) r.push({ kind: "note", label: Bluetooth.busy })
        if (Bluetooth.error) r.push({ kind: "note", label: Bluetooth.error, danger: true })
        if (!Bluetooth.available && !Bluetooth.busy)
            return r.concat([{ kind: "note", label: "No Bluetooth adapter found." }])

        if (selected) {
            const d = Bluetooth.devices.find(x => x.mac === selected)
            if (!d) { Qt.callLater(page.close); return r }
            r.push({ kind: "header", label: d.name })
            if (d.connected) r.push({ kind: "action", label: "Disconnect", run: () => { Bluetooth.disconnectDevice(d.mac, d.name); page.close() } })
            else r.push({ kind: "action", label: "Connect", run: () => { Bluetooth.connectDevice(d.mac, d.name); page.close() } })
            r.push({ kind: "action", label: "Forget This Device", danger: true, confirm: "Press again to forget",
                     run: () => { Bluetooth.forget(d.mac, d.name); page.close() } })
            r.push({ kind: "action", label: "‹  Back", run: () => page.close() })
            return r
        }

        r.push({
            kind: "toggle", glyph: "bluetooth", label: "Bluetooth", checked: Bluetooth.powered,
            detail: Bluetooth.blocked && !Bluetooth.powered ? "Blocked (rfkill), turning on will unblock it" : "",
            run: () => Bluetooth.setPowered(!Bluetooth.powered)
        })
        if (!Bluetooth.powered) return r

        r.push({ kind: "header", label: "My Devices" })
        for (const d of Bluetooth.devices)
            r.push({
                kind: "value", glyph: glyphs[d.kind], label: d.name, value: d.connected ? "Connected" : "Not Connected",
                detail: kinds[d.kind], chevron: true, run: () => { page.selected = d.mac; page.reset() }
            })
        if (!Bluetooth.devices.length) r.push({ kind: "note", label: "No paired devices yet." })

        r.push({ kind: "header", label: "Other Devices" })
        r.push({
            kind: "action", glyph: "magnifying-glass",
            label: Bluetooth.scanning ? "Searching… " + Bluetooth.scanSeconds + " s" : "Search for Devices",
            detail: Bluetooth.scanning ? "" : "Put your controller or headphones in pairing mode first",
            run: () => Bluetooth.scan()
        })
        for (const d of Bluetooth.discovered)
            r.push({ kind: "value", glyph: glyphs[d.kind], label: d.name, detail: kinds[d.kind] + " · press OK to pair", run: () => Bluetooth.pair(d.mac, d.name) })
        return r
    }
}
