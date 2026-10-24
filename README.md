# x27-tv

An Apple TV–style launcher for a living-room Linux box. It isn't a desktop: it's a
fullscreen home screen running in its own Wayland session (labwc), driven by gamepad,
TV remote or keyboard. Apps open fullscreen on top, and Home brings you back.

- **Top Shelf**: a full-bleed hero that follows the focused app (accent gradient,
  drifting blurred artwork, or your own hero image)
- **App row**: tiles that lift, tilt and catch light when focused, with a dot for
  apps that are already open (launching one again focuses it instead of starting it twice)
- **Control Center**: clock, network, volume, Sleep / Restart / Power Off / Exit to Login,
  and the way into Settings
- **Settings**: Audio (output device, volume), Display (resolution, refresh rate, scale,
  with a 15-second keep-or-revert), Network (Wi-Fi with an on-screen keyboard for
  passwords), Bluetooth (pair controllers, headphones and remotes), Home Screen (reorder
  and hide apps), Power (screen-off and auto-sleep timers), System (device info, restart)
- **All Apps**: every installed desktop app in a grid
- Missing Flatpaks show a **Get** badge, and pressing OK installs them from Flathub

## Requirements

```
sudo dnf install labwc wlrctl wlr-randr swayidle python3-pyside6 python3-evdev
flatpak install flathub rocks.shy.VacuumTube org.jellyfin.JellyfinDesktop com.unicornsonlsd.finamp org.videolan.VLC org.localsend.localsend_app
```

On Fedora Atomic, use `rpm-ostree install` for the first line and reboot.

## Install

```
sudo ./install.sh            # installs to /usr/local and adds the "X27 TV" session
sudo ./install.sh --uninstall
```

Log out and pick **X27 TV** on the login screen.

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
| Home (works from any app) | Guide | Home / Super |

Up from the row expands the Top Shelf. Press Up again to reach the Control Center button.

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
