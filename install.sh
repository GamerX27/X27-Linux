#!/usr/bin/env bash
# Installs x27-tv to /usr/local with its dependencies and registers the "X27 TV" Wayland
# session. Works from a CLI-only Fedora: sets up SDDM when no display manager is active.
# Usage: sudo ./install.sh [--autologin] [--apps] [--sddm] [--no-deps] | --uninstall

set -euo pipefail

PREFIX=/usr/local
SHARE="$PREFIX/share/x27-tv"
SESSIONS="$PREFIX/share/wayland-sessions"
SDDM_CONF=/etc/sddm.conf.d/x27-tv.conf
SRC="$(cd "$(dirname "$0")" && pwd)"
TARGET_USER="${SUDO_USER:-}"

PACKAGES=(
    labwc wlrctl wlr-randr swayidle
    python3 python3-pyside6 python3-evdev qt6-qtwayland qt6-qtsvg qt6-qtdeclarative
    pipewire wireplumber NetworkManager bluez util-linux dbus-tools glib2
    flatpak mesa-dri-drivers rsms-inter-fonts papirus-icon-theme polkit
)
SDDM_PACKAGES=(sddm sddm-wayland-generic sddm-themes)
FLATPAKS=(
    rocks.shy.VacuumTube org.jellyfin.JellyfinDesktop com.unicornsonlsd.finamp
    org.videolan.VLC org.localsend.localsend_app
)
BRAVE_REPO=https://brave-browser-rpm-release.s3.brave.com/brave-browser.repo
BRAVE_KEY=https://brave-browser-rpm-release.s3.brave.com/brave-core.asc

FORCE_SDDM=0
AUTOLOGIN=0
APPS=0
DEPS=1
UNINSTALL=0
for arg in "$@"; do
    case "$arg" in
        --sddm) FORCE_SDDM=1 ;;
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

if (( UNINSTALL )); then
    rm -rf "$SHARE" "$PREFIX/bin/x27-tv" "$PREFIX/bin/x27-tv-ctl" "$PREFIX/bin/x27-tv-session" \
        "$SESSIONS/x27-tv.desktop" "$SDDM_CONF"
    echo "x27-tv removed (packages and the display manager were left as they are)."
    exit 0
fi

ATOMIC=0
if [[ -e /run/ostree-booted ]]; then
    ATOMIC=1
fi

active_dm() {
    local unit
    unit="$(readlink -f /etc/systemd/system/display-manager.service 2>/dev/null || true)"
    if [[ -n "$unit" && -e "$unit" ]]; then
        basename "$unit" .service
    fi
}

DM="$(active_dm)"
WANT_SDDM=0
if (( FORCE_SDDM || AUTOLOGIN )) || [[ -z "$DM" || "$DM" == "sddm" ]]; then
    WANT_SDDM=1
fi

install_packages() {
    local pkgs=("${PACKAGES[@]}")
    if (( WANT_SDDM )); then
        pkgs+=("${SDDM_PACKAGES[@]}")
    fi
    if (( ATOMIC )); then
        log "Layering packages with rpm-ostree"
        rpm-ostree install --idempotent --allow-inactive "${pkgs[@]}"
    else
        log "Installing packages with dnf"
        dnf install -y "${pkgs[@]}"
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

setup_sddm() {
    if ! command -v sddm >/dev/null; then
        echo "SDDM isn't installed yet (on Fedora Atomic: reboot, then run this again)." >&2
        return
    fi
    log "Configuring SDDM"
    install -d /etc/sddm.conf.d
    {
        echo "[General]"
        echo "DisplayServer=wayland"
        echo
        echo "[Theme]"
        echo "Current=maya"
        echo
        echo "[Wayland]"
        echo "SessionDir=$SESSIONS,/usr/share/wayland-sessions"
        if (( AUTOLOGIN )); then
            echo
            echo "[Autologin]"
            echo "User=$TARGET_USER"
            echo "Session=x27-tv.desktop"
            echo "Relogin=false"
        fi
    } > "$SDDM_CONF"
    systemctl enable --force sddm.service
    systemctl set-default graphical.target
    if [[ -n "$DM" && "$DM" != "sddm" ]]; then
        echo "Replaced $DM with SDDM as the login screen."
    fi
}

if (( AUTOLOGIN )) && [[ -z "$TARGET_USER" || "$TARGET_USER" == "root" ]]; then
    echo "--autologin needs a normal user: run it with sudo from that user's account." >&2
    exit 1
fi

if (( DEPS )); then
    install_packages
fi
if (( APPS )); then
    install_apps
fi
install_files
if (( WANT_SDDM )); then
    setup_sddm
else
    log "Keeping $DM as the login screen (pass --sddm to switch to SDDM)"
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
    echo "Reboot and $TARGET_USER is signed straight into X27 TV."
else
    echo "Reboot (or log out) and pick \"X27 TV\" on the login screen."
fi
