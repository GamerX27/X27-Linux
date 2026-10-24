// System section: device information plus restart/power actions.
import QtQuick

SettingsPane {
    Component.onCompleted: System.refreshInfo()

    rows: {
        const i = System.info
        return [
            { kind: "header", label: "About" },
            { kind: "info", label: "Name", value: i.name || "" },
            { kind: "info", label: "Software", value: i.os || "" },
            { kind: "info", label: "Launcher", value: i.version || "" },
            { kind: "info", label: "Kernel", value: i.kernel || "" },
            { kind: "info", label: "Processor", value: i.cpu || "" },
            { kind: "info", label: "Memory", value: i.memory || "" },
            { kind: "info", label: "Storage", value: i.storage || "" },
            { kind: "info", label: "IP Address", value: i.ip || "" },
            { kind: "info", label: "Uptime", value: i.uptime || "" },
            { kind: "header", label: "Actions" },
            { kind: "action", glyph: "arrow-clockwise", label: "Restart Launcher", run: () => System.restartLauncher() },
            { kind: "action", glyph: "arrow-clockwise", label: "Restart", confirm: "Press again to restart", run: () => System.reboot() },
            { kind: "action", glyph: "power", label: "Power Off", danger: true, confirm: "Press again to power off", run: () => System.poweroff() }
        ]
    }
}
