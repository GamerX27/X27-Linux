// Network section: wired status, Wi-Fi toggle, network list, and connect (with an
// on-screen keyboard for passwords), disconnect or forget.
import QtQuick

SettingsPane {
    id: page

    property string selected: ""

    function strength(signal) {
        return signal > 66 ? "wifi-high" : signal > 40 ? "wifi-medium" : signal > 15 ? "wifi-low" : "wifi-none"
    }

    function close() { selected = ""; reset() }

    function choose(n) {
        if (n.active || n.saved) { selected = n.ssid; reset(); return }
        if (n.secure) host.askText("Password for " + n.ssid, true, pw => Network.connectTo(n.ssid, pw))
        else Network.connectTo(n.ssid, "")
    }

    backHandler: () => { if (selected) { close(); return true } return false }

    Component.onCompleted: { Network.clearError(); Network.refresh(); Network.scan() }

    Timer { interval: 15000; running: !page.selected; repeat: true; onTriggered: Network.scan() }

    rows: {
        const r = []
        if (Network.busy) r.push({ kind: "note", label: Network.busy })
        if (Network.error) r.push({ kind: "note", label: Network.error, danger: true })

        if (selected) {
            const n = Network.networks.find(x => x.ssid === selected) || { ssid: selected, active: false }
            r.push({ kind: "header", label: selected })
            if (n.active) r.push({ kind: "action", label: "Disconnect", run: () => { Network.disconnectFrom(page.selected); page.close() } })
            else r.push({ kind: "action", label: "Connect", run: () => { Network.connectTo(page.selected, ""); page.close() } })
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
                        detail: n.active ? "Connected" : n.saved ? "Saved" : n.secure ? "Secured" : "Open",
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
