# X27-Linux

Custom Fedora Kinoite 45, built with [BlueBuild](https://blue-build.org/): a KDE Plasma
desktop with Jellyfin, Finamp, and VLC for a living-room media PC.

- Image: `ghcr.io/gamerx27/x27-linux` — [recipe.yml](recipes/recipe.yml)

The LTS, Gaming, Desktop, and Media PC images are no longer built, see
[Migrating from the other images](#migrating-from-the-other-images).

## What's in it

- Brave Origin (default browser), stock: no debloat policies
- Jellyfin Desktop, Finamp, and VLC, all native RPMs instead of Flatpaks:
  - Jellyfin Desktop and Finamp from [X27-Linux-Packages](https://git.xlabsx27.com/X27/X27-Linux-Packages).
    Jellyfin Desktop is built there from upstream's source, with HDMI-CEC support (control
    it with the TV remote)
  - VLC from Fedora
- Removed: Firefox, KHelpCenter, Discover, the extra Plasma wallpapers (the defaults stay),
  the AWS Python SDK (boto3), and the kernel build tools (no out-of-tree modules on an image)
- Dark theme, Papirus icons, Fish shell, Konsole terminal, fastfetch banner
- fastfetch, htop, nvtop, nano, pciutils, lm_sensors, topgrade,
  [X-Linuxtool](https://codeberg.org/X27/X-Linuxtool) (`x-linuxtool`)
- Bazaar replacing Discover, as an RPM from ublue-os/packages like Bazzite. Its
  apps show up in KRunner (`krunner-bazaar`)
- Kate, KWrite, Filelight, KCharSelect, KFind, and EasyEffects as Flatpaks instead of RPMs.
  The ISO carries them and installs them offline; rebased systems get them on first boot
- Full codecs: ffmpeg (x264, x265, fdk-aac, AV1), the full GStreamer plugins (bad, ugly,
  libav, openh264), and Cisco's openh264, from negativo17 and Fedora's Cisco repo
- Hardware video decode/encode on AMD and Intel through VA-API: Mesa's `radeonsi` for AMD,
  Intel's `iHD` media driver (Broadwell and newer) and `i965` (older), with H.264/HEVC/AV1
  where the GPU supports it. Check with `vainfo`. The build fails if any of these go missing
- Brave, Dolphin, Konsole, Bazaar, Jellyfin Desktop, Finamp, and VLC pinned to the
  taskbar (new accounts only)
- Hot corners and the shake-to-locate-cursor effect disabled (new accounts only)
- Stock Fedora kernel: works with Secure Boot and on any x86_64 CPU
- CachyOS tuning: sysctl, zram, I/O schedulers, `ntsync` (see [CachyOS tuning](#cachyos-tuning))
- Baloo file indexing off by default, so the first login doesn't index the whole disk.
  KRunner still finds apps and file names; Dolphin's search inside file contents needs it.
  Turn it on in System Settings → Search → File Search, or `balooctl6 enable`
- `dnf` disabled on the installed system (see [Installing software](#installing-software))
- Updates itself, see [Auto-updates](#auto-updates)
- `/etc/os-release` names the image and build, e.g. `X27-Linux 45 (2026-09-22)`

## Install

**Fresh machine:**
you can get the ISO file on [archive.org](https://archive.org/details/x27-linux), or
run the `build-iso` workflow (Actions → build-iso → Run workflow) and download the
ISO from the run's artifacts, or [build it locally](#build-iso-locally).

**Already on Fedora Kinoite:** rebase onto this image.

```
sudo rpm-ostree rebase ostree-unverified-registry:ghcr.io/gamerx27/x27-linux:45
systemctl reboot
```

Then switch to verified pulls:

```
sudo rpm-ostree rebase ostree-image-signed:docker://ghcr.io/gamerx27/x27-linux:45
systemctl reboot
```

### Image tags

- `:45` — follows Fedora 45, rebuilt weekly. Use this one.
- `:<date>-45` (e.g. `:20260922-45`) — one fixed build, for rolling back.
- `:latest` — the newest build, whatever Fedora version that is.

**Upgrading from Fedora 44:** `:44` is no longer rebuilt. Systems following it
move to `:45` with one rebase, then a reboot:

```
sudo rpm-ostree rebase ostree-image-signed:docker://ghcr.io/gamerx27/x27-linux:45
systemctl reboot
```

Systems on `:latest` move to 45 by themselves.

## Migrating from the other images

`x27-linux-lts`, `x27-linux-gaming`, `x27-linux-desktop`, and `x27-linux-media-pc`
are no longer rebuilt. Move to `x27-linux` with one rebase, then a reboot:

```
sudo rpm-ostree rebase ostree-image-signed:docker://ghcr.io/gamerx27/x27-linux:45
systemctl reboot
```

- **Gaming and Desktop** lose their extras (Steam, Heroic, Faugus, the sched-ext
  schedulers; Zed, Docker, Netbird, and the extra Flatpaks). Already-installed
  Flatpaks stay.
- **All of them** move from the CachyOS kernel to the stock Fedora kernel. If you
  turned off Secure Boot only for the CachyOS kernel, you can turn it back on.
- **Media PC** (X27 TV) goes back to a KDE Plasma desktop with an SDDM login. Its
  installer set the default boot target to text mode, since there was no display
  manager, so switch it back **before** rebooting into the new image:

  ```
  sudo systemctl set-default graphical.target
  ```

  Then log in to Plasma and follow [First login after rebasing](#first-login-after-rebasing).
  VacuumTube and LocalSend stay installed; remove them in Bazaar if you don't want them.

## Installing software

`dnf` is disabled on the installed system: the image is read-only and replaced
on every update, so anything installed with it wouldn't stick.

- Apps: Bazaar
- CLI and dev tools: `distrobox create && distrobox enter`, then use `dnf`
  inside the container
- System packages: `sudo rpm-ostree install <package>`, then reboot

## Update

### Auto-updates

New image builds download in the background (`rpm-ostreed-automatic.timer`,
policy `stage`) and are used on the next reboot; the system never reboots by
itself. System Flatpaks update daily (`x27-flatpak-update.timer`).

To update everything right away (image, Flatpaks, and the rest), run:

```
topgrade
```

To turn auto-updates off:

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

The stock Fedora kernel, signed by Fedora, so Secure Boot works. Earlier builds
shipped the CachyOS kernel instead.

## CachyOS tuning

`cachyos-settings` from the
[kernel-cachyos-addons](https://copr.fedorainfracloud.org/coprs/bieszczaders/kernel-cachyos-addons/)
COPR: CachyOS sysctl, zram (zstd, sized to RAM), udev I/O scheduler rules,
`ntsync`, and the `game-performance`, `zink-run`, and `kerver` commands. These
work on the stock kernel; there are no sched-ext schedulers.

## Build

Pushes to `main` build and publish automatically via GitHub Actions, which
also rebuilds weekly to pick up upstream Kinoite, Brave, kernel, and codec updates.
CI runs on GitHub only; Actions is turned off on the Forgejo mirror
(git.xlabsx27.com).

## Releases

Every image build publishes a [GitHub Release](../../releases) that lists what changed: key
versions (kernel, Plasma, Mesa, Brave, ...), repo commits, and the packages updated, added
or removed. The package list is attached to each release.

- `vYYYY.MM.DD` (e.g. `v2026.09.27`): the weekly rebuild
- `vYYYY.MM.DD.N` (e.g. `v2026.09.24.1`): minor releases for changes pushed in between

## Build ISO locally

Generates an installer ISO from the already-published `ghcr.io/gamerx27/x27-linux`
image, the same approach as the CI [`iso.yml`](.github/workflows/iso.yml)
workflow — nothing is built from local recipes, so this needs a network
connection to GHCR.

**Prerequisites:**
- docker
- sudo access
- ~20GB free disk (image pull + ISO — past ISOs have run ~6.5GB)

```
./scripts/build-iso.sh [--usb] [--tag TAG]
```

Runs [build-container-installer](https://github.com/JasonN3/build-container-installer)
v1.5.0 in docker. Output goes to `iso-out/` at the repo root: `x27-linux.iso` and
`x27-linux.iso.sha256sum`. The image pulled from GHCR is removed again when the script
exits, unless it was already on the system.

Each run first empties `iso-out/`.

`--tag` picks the image tag the ISO installs, and the installed system keeps
following it on updates: `45`, `latest`, or a dated tag (see [Image tags](#image-tags)).
Without it the script asks, defaulting to `45`. The `build-iso` workflow has the
same choice.

`--usb` writes the ISO to a USB drive after the build: it lists the USB drives,
asks which one to use, has you type the device path (e.g. `/dev/sdb`) to confirm,
and writes the ISO with `dd`. Everything on the drive is erased.
