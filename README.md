# X27-Linux

Custom Fedora Kinoite 44, built with [BlueBuild](https://blue-build.org/).

- Base: `ghcr.io/gamerx27/x27-linux` — [recipe.yml](recipes/recipe.yml)
- LTS kernel: `ghcr.io/gamerx27/x27-linux-lts` — [recipe-lts.yml](recipes/recipe-lts.yml)
- Gaming: `ghcr.io/gamerx27/x27-linux-gaming` — [recipe-gaming.yml](recipes/recipe-gaming.yml), built on Base
- Desktop: `ghcr.io/gamerx27/x27-linux-desktop` — [recipe-desktop.yml](recipes/recipe-desktop.yml), built on Base
- Media PC: `ghcr.io/gamerx27/x27-linux-media-pc` — [recipe-media-pc.yml](recipes/recipe-media-pc.yml), built on LTS kernel

Base and LTS build first; Gaming, Desktop, and Media PC build on top of them once they finish.

## What's in it

- Brave (default browser), debranded with [X-Linuxtool](https://codeberg.org/X27/X-Linuxtool)
- Removed: Firefox, KHelpCenter, Discover
- Dark theme, Papirus icons, Fish shell, Konsole terminal, fastfetch banner
- fastfetch, htop, nvtop, nano, pciutils, lm_sensors, topgrade
- Bazaar replacing Discover, as an RPM from ublue-os/packages like Bazzite. Its
  apps show up in KRunner (`krunner-bazaar`)
- VLC (Flatpak). The ISO carries it and installs it offline; rebased systems get
  it on first boot
- Kate, KWrite, Filelight, KCharSelect, KFind, and EasyEffects as Flatpaks instead of RPMs,
  installed on first boot
- Full codecs (ffmpeg, x264/x265, fdk-aac) and hardware video decode/encode on AMD
  and Intel (Mesa VA-API/Vulkan with H.264/HEVC/AV1, Intel media driver), from the
  negativo17 multimedia packages in the BlueBuild base image. Check with `vainfo`
- Brave, Dolphin, Konsole, and Bazaar pinned to the taskbar (new accounts only)
- Hot corners and the shake-to-locate-cursor effect disabled (new accounts only)
- CachyOS kernel (BORE scheduler); LTS variant published separately
- CachyOS tuning: sysctl, zram, I/O schedulers, `ntsync`, sched-ext schedulers (see [CachyOS tuning](#cachyos-tuning))
- `dnf` disabled on the installed system (see [Installing software](#installing-software))
- Auto-updates off — update manually with `topgrade` (Gaming and Media PC
  update themselves, see [Auto-updates](#auto-updates))
- `/etc/os-release` names the image and build, e.g. `X27-Linux 44 Gaming (2026-09-22)`

## Install

**Fresh machine:**
you can get the ISO file on [archive.org](https://archive.org/details/x27-linux).
For the other images, run the `build-iso` workflow (Actions → build-iso → Run
workflow), pick the image, and download the ISO from the run's artifacts, or
[build it locally](#build-iso-locally).

**Already on Fedora Kinoite:** rebase onto this image.

```
sudo rpm-ostree rebase ostree-unverified-registry:ghcr.io/gamerx27/x27-linux:44
systemctl reboot
```

Then switch to verified pulls:

```
sudo rpm-ostree rebase ostree-image-signed:docker://ghcr.io/gamerx27/x27-linux:44
systemctl reboot
```

Swap `x27-linux` for `x27-linux-lts` (LTS kernel), `x27-linux-gaming`
(Steam/gaming, see below), `x27-linux-desktop` (daily use, see below), or
`x27-linux-media-pc` (media center, see below) in
the commands above.

### Image tags

- `:44` — follows Fedora 44, rebuilt weekly. Use this one.
- `:<date>-44` (e.g. `:20260922-44`) — one fixed build, for rolling back.
- `:latest` — the newest build, whatever Fedora version that is.

## Installing software

`dnf` is disabled on the installed system: the image is read-only and replaced
on every update, so anything installed with it wouldn't stick.

- Apps: Bazaar
- CLI and dev tools: `distrobox create && distrobox enter`, then use `dnf`
  inside the container
- System packages: `sudo rpm-ostree install <package>`, then reboot
- Updates: `topgrade`

## Update

```
topgrade
```

Updates the system image, Flatpaks, and everything else in one command.
Nothing updates on its own — you always run this yourself. Gaming and Media PC
are the exception:

### Auto-updates

Gaming and Media PC download new image builds in the background
(`rpm-ostreed-automatic.timer`, policy `stage`) and switch to them on the next
reboot; they never reboot by themselves. System Flatpaks update daily
(`x27-flatpak-update.timer`). There's no weekly topgrade reminder on these two.
To turn it off:

```
sudo systemctl disable --now rpm-ostreed-automatic.timer x27-flatpak-update.timer
```

## First login after rebasing

Theme, icons, shell, and the hot-corners/shake-cursor settings only apply to
new accounts. Run once as
yourself, no `sudo`:

```
plasma-apply-lookandfeel -a org.kde.breezedark.desktop
chsh -s /usr/bin/fish "$USER"
kquitapp6 plasmashell; kstart plasmashell >/dev/null 2>&1 &
```

`plasma-apply-lookandfeel` now brings Papirus-Dark icons with it (our
`org.kde.breezedark.desktop` package overrides the upstream defaults, which
otherwise apply `breeze-dark`).

Log out and back in afterward for the shell change to take effect.

Remove leftover Anaconda KDE games if you have them:

```
sudo flatpak remove --noninteractive org.kde.elisa org.kde.kmahjongg org.kde.kolourpaint org.kde.kmines
sudo flatpak remote-modify --disable fedora fedora-testing
```

## Kernel

`x27-linux` and `x27-linux-gaming` ship the
[CachyOS kernel](https://copr.fedorainfracloud.org/coprs/bieszczaders/kernel-cachyos/)
(BORE scheduler); `x27-linux-lts` and `x27-linux-media-pc` ship its LTS variant
instead. All replace the stock Fedora kernel.

- **Needs an x86_64-v3 CPU** (Zen-family AMD, Haswell+ Intel). Older CPUs
  won't boot it. Check with:
  `/lib64/ld-linux-x86-64.so.2 --help | grep "(supported, searched)"`
- **Unsigned.** Turn off Secure Boot, or sign it yourself with
  `sbsigntools`/`mokutil` (both included).

## CachyOS tuning

All images include packages from the
[kernel-cachyos-addons](https://copr.fedorainfracloud.org/coprs/bieszczaders/kernel-cachyos-addons/)
COPR:

- `cachyos-settings`: CachyOS sysctl, zram (zstd, sized to RAM), udev I/O
  scheduler rules, `ntsync`, and the `game-performance`, `zink-run`, and
  `kerver` commands
- `scx-scheds` and `scx-tools`: sched-ext schedulers, `scxctl`, `scxtui`

On all images except gaming, no sched-ext scheduler runs by default; BORE from
the kernel handles scheduling. To try one:

```
sudo systemctl start scx_loader
scxctl start -s scx_bpfland
```

To load one on every boot, set `default_sched` in
`/etc/scx_loader/config.toml` and run `sudo systemctl enable --now scx_loader`.

## Gaming variant

Everything above, plus:

- Steam, GameMode, Gamescope, MangoHud, GOverlay
- Faugus Launcher, Heroic Games Launcher (latest GitHub release, updated with each weekly build)
- Full GStreamer codecs (bad, ugly, openh264) on top of the base image's codecs,
  and 32-bit Mesa/libva matching the 64-bit drivers, all from negativo17
- Desktop animations off (animation speed set to Instant)
- `proton-cachyos-install` — run it yourself to install or update
  [Proton-CachyOS](https://github.com/CachyOS/proton-cachyos) into Steam
- Steam, Dolphin, Konsole, Brave, and Bazaar pinned to the taskbar (new accounts only)
- `scx_lavd` sched-ext scheduler in Gaming mode, running by default. Switch
  with scx-manager or `scxctl switch -s <scheduler>`; turn it off with
  `sudo systemctl disable --now scx_loader`
- ananicy-cpp with CachyOS rules. If games stutter, try turning this off
  first: `sudo systemctl disable --now ananicy-cpp`
- power-profiles-daemon instead of tuned-ppd, so `game-performance` works.
  In Steam, set a game's launch options to `game-performance %command%` to
  use the performance power profile while it runs
- Updates itself, see [Auto-updates](#auto-updates)

## Desktop variant

Everything in the base image, plus:

- Zed editor (native, not Flatpak, so its terminal and agents run on the host;
  updated with each weekly build). Its own updater and the sign-in button are off
- Docker, with `docker.service` enabled. Add yourself to the `docker` group
  once, then log out and back in: `sudo usermod -aG docker $USER`
- Netbird client and tray app, with `netbird.service` enabled
- GNOME Disks
- Flatpaks: Vivaldi, LibreWolf, Chromium, Tor Browser Launcher, Nextcloud,
  Cryptomator, Bitwarden, LocalSend, SyncThingy, Jellyfin Desktop, Finamp,
  Iotas, sshPilot, Web App Hub, Mission Center, Gwenview

## Media PC variant

Everything in the base image, plus:

- LTS kernel (see above)
- Jellyfin Desktop and Finamp (Flatpak) for media playback
- LocalSend (Flatpak) for quick file transfers
- Dolphin, Jellyfin Desktop, VLC, Finamp, and Bazaar pinned to the taskbar (new accounts only)
- Updates itself, see [Auto-updates](#auto-updates)

## Build

Pushes to `main` build and publish automatically via GitHub Actions, which
also rebuilds weekly to pick up upstream Kinoite/Brave/kernel updates.
CI runs on GitHub only; Actions is turned off on the Forgejo mirror
(git.xlabsx27.com).

## Releases

Every image build publishes a [GitHub Release](../../releases) that lists what changed: key
versions (kernels, Plasma, Mesa, Brave, ...), repo commits, and the packages updated, added
or removed in each image. The package lists are attached to each release.

- `vYYYY.MM.DD` (e.g. `v2026.09.27`): the weekly rebuild
- `vYYYY.MM.DD.N` (e.g. `v2026.09.24.1`): minor releases for changes pushed in between

## Build ISO locally

Generates an installer ISO from the already-published `ghcr.io/gamerx27`
image, the same approach as the CI [`iso.yml`](.github/workflows/iso.yml)
workflow — nothing is built from local recipes, so this needs a network
connection to GHCR.

**Prerequisites:**
- docker
- sudo access
- ~20GB free disk (image pull + ISO — past ISOs have run ~6.5GB)
- x86_64-v3 CPU to boot the resulting image (see [Kernel](#kernel) above)

```
./scripts/build-iso.sh [--usb] [--tag TAG] [base|lts|gaming|desktop|media-pc]
```

Defaults to `base` if no argument is given. Runs
[build-container-installer](https://github.com/JasonN3/build-container-installer)
v1.5.0 in docker. Output goes to `iso-out/` at the repo root: `<name>.iso` and
`<name>.iso.sha256sum`. The image pulled from GHCR is removed again when the script
exits, unless it was already on the system.

Each run first empties `iso-out/`, removing the ISOs of every image, not just the
one being built.

`--tag` picks the image tag the ISO installs, and the installed system keeps
following it on updates: `44`, `latest`, or a dated tag (see [Image tags](#image-tags)).
Without it the script asks, defaulting to `44`. The `build-iso` workflow has the
same choice.

`--usb` writes the ISO to a USB drive after the build: it lists the USB drives,
asks which one to use, has you type the device path (e.g. `/dev/sdb`) to confirm,
and writes the ISO with `dd`. Everything on the drive is erased.
