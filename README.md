# x27-tv

An Apple TV–style launcher for a living-room Linux box. It isn't a desktop: it's a
fullscreen home screen running in its own Wayland session (labwc), driven by gamepad,
TV remote or keyboard. Apps open fullscreen on top, and Home brings you back.

- **Top Shelf**: a full-bleed hero that follows the focused app (accent gradient,
  drifting blurred artwork, or your own hero image)
- **App row**: tiles that lift, tilt and catch light when focused, with a dot for
  apps that are already open (launching one again focuses it instead of starting it twice)
- **Control Center**: clock, network, volume, Sleep / Restart / Power Off / Exit to Console,
  and the way into Settings
- **Settings**: Audio (output device, volume), Display (resolution, refresh rate, scale,
  with a 15-second keep-or-revert), Network (Wi-Fi with an on-screen keyboard for
  passwords), Bluetooth (pair controllers, headphones and remotes), Home Screen (reorder
  and hide apps), Power (screen-off and auto-sleep timers), System (device info, restart)
- **Taskbar**: running apps along the bottom of the home screen. Switch to one or close it
- **All Apps**: every installed desktop app in a grid
- Missing Flatpaks show a **Get** badge, and pressing OK installs them from Flathub

## Install

```
sudo ./install.sh              # packages + x27-tv (+ an "X27 TV" entry for existing login screens)
sudo ./install.sh --autologin  # also boots straight into X27 TV, with no display manager
sudo ./install.sh --apps       # also installs the home row Flatpaks system-wide
sudo ./install.sh --no-deps    # only copy the launcher files
sudo ./install.sh --uninstall
```

The installer pulls in everything a CLI-only Fedora needs: labwc, wlrctl, wlr-randr,
swayidle, Xwayland, Python + PySide6 with Qt Wayland/SVG, PipeWire, NetworkManager, BlueZ,
polkit, Flatpak (adding Flathub) with xdg-desktop-portal, Mesa, Inter, Papirus, and Brave from Brave's own repository
(used for the browser and the web shortcuts). On Fedora Atomic, packages are layered
with rpm-ostree and arrive after a reboot.

There is no display manager. `--autologin` installs `x27-tv.service`, which logs your
user into X27 TV on tty1 at boot (the same way kiosk compositors like cage are run).
If the session crashes it restarts, and **Exit to Console** in the Control Center goes back
to the normal text login on tty1. Logs: `journalctl -u x27-tv` for the session, and
`~/.cache/x27-tv/logs/<app>.log` for each app (if an app doesn't show a window within
30 seconds, the launcher shows its last error line). Without `--autologin`,
log in on a console and run `x27-tv-session`.

The apps on the home row are Flatpaks, and the launcher offers to install missing ones
(**Get** badge), or use `--apps` to install them up front.

### Testing in a VM (from a CLI-only Fedora)

1. Install Fedora 44 Server, or Everything with "Minimal Install", with no desktop.
   Create a normal user with admin (sudo) rights during setup.
2. Log in on the console as that user:
   ```
   sudo dnf install -y git
   git clone https://git.xlabsx27.com/X27/X27-TV.git && cd X27-TV
   sudo ./install.sh --autologin --apps
   sudo reboot
   ```
3. The VM boots straight into X27 TV. A second console is on Ctrl+Alt+F3.

Enable 3D acceleration for the VM (virtio-gpu with GL, or VMware SVGA) so the blur
effects render smoothly.

## Try it without logging out

```
bin/x27-tv --windowed                          # inside your normal desktop
X27TV_HOME=$PWD labwc -C session/labwc         # the full session, nested in a window
```

## Controls

| Action | Gamepad | Remote / keyboard |
| --- | --- | --- |
| Move | D-pad / left stick | Arrows |
| Open | A | OK / Enter |
| Back | B | Back / Esc |
| Control Center | Start / Select | Menu / F1 |
| First / last app | LB / RB | Page Up / Page Down |
| Close app (taskbar or tile) | X / Y | Delete / X |
| Home (works from any app) | Guide | Home / Super |

Up from the row expands the Top Shelf. Press Up again to reach the Control Center button.
Down from the row moves to the taskbar (shown while apps are running). OK on an app there
opens **Open / Close**, and X closes it directly.

In Settings: Up/Down moves, Right/OK opens a section, ‹ › changes values, and Back goes
back. On Home Screen, OK picks an app up, Up/Down moves it, and OK puts it down.

Settings are saved in `~/.config/x27-tv/settings.json`. Display changes made in the X27 TV
session are re-applied at login. Screen-off and auto-sleep need the session (swayidle), and
playing video blocks both.

## Customizing the row

Copy `config/apps.toml` to `~/.config/x27-tv/apps.toml` and edit it. Each `[[app]]` is one of:

```toml
[[app]]
name = "Jellyfin"
flatpak = "org.jellyfin.JellyfinDesktop"   # run via flatpak, Get badge if missing

[[app]]
name = "Odysee"
url = "https://odysee.com/"                # opened as a browser app window

[[app]]
name = "Brave"
exec = "brave-browser"                     # any command
```

Optional keys: `tagline`, `accent = ["#top", "#bottom"]`, `icon` (theme name or file
path), `hero` (image shown behind the Top Shelf), and `app_id` (the Wayland app id, used
to detect and focus a running window, if the default guess is wrong). Web shortcuts
fetch the site's touch icon into `~/.cache/x27-tv/icons`. Set `browser = "..."` at the top
to use a different Chromium-based browser.

## Credits

UI icons are from [Phosphor Icons](https://phosphoricons.com) (fill and bold styles, MIT), and the
license is in `qml/icons/LICENSE`.
