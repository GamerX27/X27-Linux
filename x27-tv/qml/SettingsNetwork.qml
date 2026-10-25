// Network section: wired status, Wi-Fi toggle, network list, and connect (with an
// on-screen keyboard for passwords), disconnect or forget. Progress and errors also show on
// the network's own row, since the notes at the top are often scrolled out of view.
import QtQuick

SettingsPane {
    id: page

    property string selected: ""

    function strength(signal) {
        return signal > 66 ? "wifi-high" : signal > 40 ? "wifi-medium" : signal > 15 ? "wifi-low" : "wifi-none"
    }

    function close() { selected = ""; reset() }

    function askPassword(ssid) { host.askText("Password for " + ssid, true, pw => { if (pw) Network.connectTo(ssid, pw) }) }

    function choose(n) {
        if (Network.busy) return
        if (n.active || n.saved) { selected = n.ssid; reset(); return }
        if (n.secure) askPassword(n.ssid)
        else Network.connectTo(n.ssid, "")
    }

    function status(n) {
        if (Network.target === n.ssid && Network.busy) return Network.busy
        if (Network.failed === n.ssid) return Network.error
        if (n.active) return "Connected"
        return n.saved ? "Saved" : n.secure ? "Secured · press OK to enter the password" : "Open · press OK to connect"
    }

    backHandler: () => { if (selected) { close(); return true } return false }

    Component.onCompleted: { Network.clearError(); Network.refresh(); Network.scan() }

    Timer { interval: 15000; running: !page.selected; repeat: true; onTriggered: Network.scan() }

    rows: {
        const r = []
        if (Network.busy) r.push({ kind: "note", label: Network.busy })
        if (Network.error) r.push({ kind: "note", label: Network.error, danger: true })
        if (Network.notice) r.push({ kind: "note", label: "✓  " + Network.notice })

        if (selected) {
            const n = Network.networks.find(x => x.ssid === selected) || { ssid: selected, active: false }
            r.push({ kind: "header", label: selected })
            if (n.active) r.push({ kind: "action", label: "Disconnect", run: () => { Network.disconnectFrom(page.selected); page.close() } })
            else r.push({ kind: "action", label: "Connect", run: () => { Network.connectTo(page.selected, ""); page.close() } })
            if (n.secure !== false)
                r.push({ kind: "action", glyph: "lock", label: "Enter New Password",
                         run: () => { const ssid = page.selected; page.close(); page.askPassword(ssid) } })
            r.push({ kind: "action", label: "Forget This Network", danger: true, confirm: "Press again to forget",
                     run: () => { Network.forget(page.selected); page.close() } })
            r.push({ kind: "action", label: "‹  Back", run: () => page.close() })
            return r
        }

        if (Network.wired) r.push({ kind: "info", glyph: "ethernet", label: "Wired", value: "Connected · " + Network.ip })
        if (Network.hasWifi) {
            r.push({ kind: "toggle", glyph: "wifi-high", label: "Wi-Fi", checked: Network.wifiEnabled, run: () => Network.setWifi(!Network.wifiEnabled) })
            if (Network.wifiEnabled) {
                r.push({ kind: "header", label: Network.scanning ? "Networks · searching…" : "Networks" })
                for (const n of Network.networks)
                    r.push({
                        kind: "value", label: n.ssid, selected: n.active,
                        trail: n.secure ? ["lock", strength(n.signal)] : [strength(n.signal)],
                        detail: status(n), value: Network.target === n.ssid && Network.busy ? "…" : "",
                        chevron: n.active || n.saved, run: () => page.choose(n)
                    })
                if (!Network.networks.length && !Network.scanning) r.push({ kind: "note", label: "No networks found." })
                r.push({ kind: "action", glyph: "magnifying-glass", label: "Search Again", run: () => Network.scan() })
            }
        } else if (!Network.wired) {
            r.push({ kind: "note", label: "No network adapters found." })
        }
        return r
    }
}
