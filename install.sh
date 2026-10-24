#!/usr/bin/env bash
# Installs x27-tv to /usr/local (writable on Fedora Atomic too) and registers the
# "X27 TV" Wayland session for SDDM/GDM. Run with sudo; pass --uninstall to remove.

set -euo pipefail

PREFIX=/usr/local
SHARE="$PREFIX/share/x27-tv"
SESSIONS="$PREFIX/share/wayland-sessions"
SRC="$(cd "$(dirname "$0")" && pwd)"

if [[ $EUID -ne 0 ]]; then
    echo "Please run as root: sudo $0 $*" >&2
    exit 1
fi

if [[ "${1:-}" == "--uninstall" ]]; then
    rm -rf "$SHARE" "$PREFIX/bin/x27-tv" "$PREFIX/bin/x27-tv-ctl" "$PREFIX/bin/x27-tv-session" "$SESSIONS/x27-tv.desktop"
    echo "x27-tv removed."
    exit 0
fi

rm -rf "$SHARE"
install -d "$SHARE" "$PREFIX/bin" "$SESSIONS"
cp -r "$SRC/x27tv" "$SRC/qml" "$SRC/config" "$SRC/session" "$SRC/bin" "$SHARE/"
find "$SHARE" -name __pycache__ -prune -exec rm -rf {} +
ln -sf "$SHARE/bin/x27-tv" "$PREFIX/bin/x27-tv"
ln -sf "$SHARE/bin/x27-tv-ctl" "$PREFIX/bin/x27-tv-ctl"
ln -sf "$SHARE/session/x27-tv-session" "$PREFIX/bin/x27-tv-session"
install -m 644 "$SRC/session/x27-tv.desktop" "$SESSIONS/x27-tv.desktop"

missing=()
for cmd in labwc wlrctl wlr-randr swayidle nmcli bluetoothctl wpctl python3; do
    command -v "$cmd" >/dev/null || missing+=("$cmd")
done
python3 -c "import PySide6" 2>/dev/null || missing+=("python3-pyside6")
python3 -c "import evdev" 2>/dev/null || missing+=("python3-evdev (gamepad support)")

echo "x27-tv installed. Log out and pick \"X27 TV\" on the login screen."
if (( ${#missing[@]} )); then
    echo
    echo "Missing: ${missing[*]}"
    if [[ -e /run/ostree-booted ]]; then
        echo "Install with: rpm-ostree install labwc wlrctl wlr-randr swayidle python3-evdev python3-pyside6 (then reboot)"
    else
        echo "Install with: dnf install labwc wlrctl wlr-randr swayidle python3-evdev python3-pyside6"
    fi
fi
