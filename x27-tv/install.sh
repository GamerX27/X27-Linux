#!/usr/bin/env bash
# Installs x27-tv to /usr/local with its dependencies. Works from a CLI-only Fedora: with
# --autologin a systemd service boots straight into X27 TV on tty1, with no display manager.
# Usage: sudo ./install.sh [--autologin] [--apps] [--no-deps] | --uninstall

set -euo pipefail

PREFIX=/usr/local
SHARE="$PREFIX/share/x27-tv"
SESSIONS="$PREFIX/share/wayland-sessions"
UNIT=/etc/systemd/system/x27-tv.service
PAM=/etc/pam.d/x27-tv
OLD_SDDM_CONF=/etc/sddm.conf.d/x27-tv.conf
SRC="$(cd "$(dirname "$0")" && pwd)"
TARGET_USER="${SUDO_USER:-}"

PACKAGES=(
    labwc xorg-x11-server-Xwayland wlrctl wlr-randr swayidle
    python3 python3-pyside6 python3-evdev qt6-qtwayland qt6-qtsvg qt6-qtdeclarative layer-shell-qt
    pipewire wireplumber NetworkManager bluez util-linux dbus-tools glib2
    flatpak xdg-desktop-portal xdg-desktop-portal-gtk
    mesa-dri-drivers rsms-inter-fonts papirus-icon-theme polkit
)
FLATPAKS=(
    rocks.shy.VacuumTube org.jellyfin.JellyfinDesktop com.unicornsonlsd.finamp
    org.videolan.VLC org.localsend.localsend_app
)
BRAVE_REPO=https://brave-browser-rpm-release.s3.brave.com/brave-browser.repo
BRAVE_KEY=https://brave-browser-rpm-release.s3.brave.com/brave-core.asc

AUTOLOGIN=0
APPS=0
DEPS=1
UNINSTALL=0
for arg in "$@"; do
    case "$arg" in
        --autologin) AUTOLOGIN=1 ;;
        --apps) APPS=1 ;;
        --no-deps) DEPS=0 ;;
        --uninstall) UNINSTALL=1 ;;
        -h|--help) sed -n '2,4p' "$0"; exit 0 ;;
        *) echo "Unknown option: $arg" >&2; exit 2 ;;
    esac
done

if [[ $EUID -ne 0 ]]; then
    echo "Please run as root: sudo $0 $*" >&2
    exit 1
fi

log() {
    echo -e "\n\033[1;32m==>\033[0m \033[1m$*\033[0m"
}

ATOMIC=0
if [[ -e /run/ostree-booted ]]; then
    ATOMIC=1
fi

remove_old_sddm() {
    if [[ ! -e "$OLD_SDDM_CONF" ]]; then
        return
    fi
    log "Removing the SDDM setup from an earlier install"
    systemctl disable sddm.service 2>/dev/null || true
    rm -f "$OLD_SDDM_CONF"
    if (( ! ATOMIC )) && rpm -q sddm >/dev/null 2>&1; then
        dnf remove -y sddm sddm-wayland-generic sddm-themes || true
    fi
}

remove_autologin() {
    if [[ -e "$UNIT" ]]; then
        systemctl disable x27-tv.service 2>/dev/null || true
        rm -f "$UNIT" "$PAM"
        systemctl daemon-reload
    fi
}

if (( UNINSTALL )); then
    remove_autologin
    remove_old_sddm
    rm -rf "$SHARE" "$PREFIX/bin/x27-tv" "$PREFIX/bin/x27-tv-ctl" "$PREFIX/bin/x27-tv-session" \
        "$SESSIONS/x27-tv.desktop"
    echo "x27-tv removed (packages were left installed)."
    exit 0
fi

if (( AUTOLOGIN )) && [[ -z "$TARGET_USER" || "$TARGET_USER" == "root" ]]; then
    echo "--autologin needs a normal user: run it with sudo from that user's account." >&2
    exit 1
fi

install_packages() {
    if (( ATOMIC )); then
        log "Layering packages with rpm-ostree"
        rpm-ostree install --idempotent --allow-inactive "${PACKAGES[@]}"
    else
        log "Installing packages with dnf"
        dnf install -y "${PACKAGES[@]}"
    fi
    if (( ! ATOMIC )) && ! command -v brave-browser >/dev/null; then
        log "Adding Brave's repository (browser and web shortcuts)"
        rpm --import "$BRAVE_KEY"
        curl -fsSL "$BRAVE_REPO" -o /etc/yum.repos.d/brave-browser.repo
        dnf install -y brave-browser
    fi
    log "Adding Flathub"
    flatpak remote-add --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo || true
}

install_apps() {
    log "Installing the home row apps from Flathub"
    flatpak install -y --noninteractive --system flathub "${FLATPAKS[@]}"
}

install_files() {
    log "Installing x27-tv to $SHARE"
    rm -rf "$SHARE"
    install -d "$SHARE" "$PREFIX/bin" "$SESSIONS"
    cp -r "$SRC/x27tv" "$SRC/qml" "$SRC/config" "$SRC/session" "$SRC/bin" "$SHARE/"
    find "$SHARE" -name __pycache__ -prune -exec rm -rf {} +
    ln -sf "$SHARE/bin/x27-tv" "$PREFIX/bin/x27-tv"
    ln -sf "$SHARE/bin/x27-tv-ctl" "$PREFIX/bin/x27-tv-ctl"
    ln -sf "$SHARE/session/x27-tv-session" "$PREFIX/bin/x27-tv-session"
    install -m 644 "$SRC/session/x27-tv.desktop" "$SESSIONS/x27-tv.desktop"
    if command -v restorecon >/dev/null; then
        restorecon -R "$SHARE" "$SESSIONS" "$PREFIX/bin" 2>/dev/null || true
    fi
}

setup_autologin() {
    log "Setting up autologin for $TARGET_USER on tty1"
    install -m 644 "$SRC/session/x27-tv.pam" "$PAM"
    sed "s/@USER@/$TARGET_USER/g" "$SRC/session/x27-tv.service" > "$UNIT"
    chmod 644 "$UNIT"
    if command -v restorecon >/dev/null; then
        restorecon "$PAM" "$UNIT" 2>/dev/null || true
    fi
    systemctl daemon-reload
    systemctl enable x27-tv.service
    systemctl set-default graphical.target
}

if (( DEPS )); then
    install_packages
fi
if (( APPS )); then
    install_apps
fi
remove_old_sddm
install_files
if (( AUTOLOGIN )); then
    setup_autologin
fi

missing=()
for cmd in labwc wlrctl wlr-randr swayidle nmcli bluetoothctl wpctl; do
    command -v "$cmd" >/dev/null || missing+=("$cmd")
done
python3 -c "import PySide6" 2>/dev/null || missing+=("python3-pyside6")
python3 -c "import evdev" 2>/dev/null || missing+=("python3-evdev")

log "Done"
if (( ${#missing[@]} )); then
    echo "Still missing: ${missing[*]}"
    if (( ATOMIC )); then
        echo "On Fedora Atomic, layered packages arrive after a reboot."
    fi
fi
if (( AUTOLOGIN )); then
    echo "Reboot and $TARGET_USER goes straight into X27 TV."
    echo "Exit in the Control Center returns to the console; logs: journalctl -u x27-tv"
else
    echo "Start it from a console login with: x27-tv-session"
    echo "(or pick \"X27 TV\" on an existing login screen)"
fi
