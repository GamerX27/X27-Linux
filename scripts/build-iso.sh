#!/usr/bin/env bash
set -euo pipefail

REGISTRY="ghcr.io/gamerx27"
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT_DIR="${REPO_ROOT}/iso-out"
MIN_FREE_GB=20
INSTALLER_IMAGE="ghcr.io/jasonn3/build-container-installer:v1.5.0"

usage() {
  echo "Usage: $0 [base|lts|gaming|desktop|media-pc]"
  echo "  base      x27-linux (default)"
  echo "  lts       x27-linux-lts"
  echo "  gaming    x27-linux-gaming"
  echo "  desktop   x27-linux-desktop"
  echo "  media-pc  x27-linux-media-pc"
}

TARGET=""
for arg in "$@"; do
  case "$arg" in
    -h|--help)
      usage
      exit 0
      ;;
    *)
      if [ -n "$TARGET" ]; then
        echo "Unexpected extra argument: $arg" >&2
        usage >&2
        exit 1
      fi
      TARGET="$arg"
      ;;
  esac
done
TARGET="${TARGET:-base}"

case "$TARGET" in
  base)     IMAGE="x27-linux" ;;
  lts)      IMAGE="x27-linux-lts" ;;
  gaming)   IMAGE="x27-linux-gaming" ;;
  desktop)  IMAGE="x27-linux-desktop" ;;
  media-pc) IMAGE="x27-linux-media-pc" ;;
  *)
    echo "Unknown target: $TARGET" >&2
    usage >&2
    exit 1
    ;;
esac

ISO_NAME="${IMAGE}.iso"
IMAGE_REF="${REGISTRY}/${IMAGE}:latest"

if ! command -v docker >/dev/null 2>&1; then
  echo "docker not found on PATH." >&2
  exit 1
fi

mkdir -p "$OUT_DIR"

AVAIL_GB=$(( $(df --output=avail -k "$OUT_DIR" | tail -n1) / 1024 / 1024 ))
if [ "$AVAIL_GB" -lt "$MIN_FREE_GB" ]; then
  echo "WARNING: only ${AVAIL_GB}GB free at ${OUT_DIR}, ${MIN_FREE_GB}GB+ recommended."
fi

# Flatpaks in flatpak_refs/ plus their runtimes, pulled into an ostree repo by the image
# itself (same steps as build-container-installer's flatpaks/Makefile). Anaconda installs
# them offline from the ISO.
FLATPAK_REFS="$(cat "${REPO_ROOT}"/flatpak_refs/* | tr '\n' ' ')"
FLATPAK_DIR="${OUT_DIR}/flatpak"
sudo rm -rf "$FLATPAK_DIR"
mkdir -p "$FLATPAK_DIR"

# Removes the image pulled from GHCR (unless it was already here) and the Flatpak repo on
# exit, whether the build succeeded or not.
PULLED=0
sudo docker image inspect "$IMAGE_REF" >/dev/null 2>&1 || PULLED=1
cleanup() {
  sudo rm -rf "$FLATPAK_DIR"
  if [ "$PULLED" = 1 ]; then
    echo "Removing ${IMAGE_REF}"
    sudo docker rmi "$IMAGE_REF" >/dev/null 2>&1 || true
  fi
}
trap cleanup EXIT

# --network host on both containers: Docker's bridge network intermittently refused
# connections here (Flathub, ciscobinary.openh264.org) while the host reached them fine.
echo "Collecting Flatpaks: ${FLATPAK_REFS}"
sudo docker pull "$IMAGE_REF"
sudo docker run --rm --privileged --network host --entrypoint bash \
  -e FLATPAK_SYSTEM_DIR=/flatpak/flatpak \
  -e FLATPAK_TRIGGERSDIR=/flatpak/triggers \
  -e "REFS=${FLATPAK_REFS}" \
  -v "${FLATPAK_DIR}:/flatpak_dir" \
  "$IMAGE_REF" -euc '
    mkdir -p /flatpak/flatpak /flatpak/triggers /var/tmp
    chmod -R 1777 /var/tmp
    flatpak config --system --set languages "*"
    flatpak remote-add --system flathub https://flathub.org/repo/flathub.flatpakrepo
    flatpak install --system -y $REFS
    ostree init --repo=/flatpak_dir/repo --mode=archive-z2
    for i in $(ostree refs --repo=$FLATPAK_SYSTEM_DIR/repo | grep "^deploy/" | sed "s/^deploy\///"); do
      echo "Copying $i..."
      rev=$(ostree --repo=$FLATPAK_SYSTEM_DIR/repo rev-parse flathub/$i)
      ostree --repo=/flatpak_dir/repo pull-local $FLATPAK_SYSTEM_DIR/repo $rev
      mkdir -p $(dirname /flatpak_dir/repo/refs/heads/$i)
      echo $rev > /flatpak_dir/repo/refs/heads/$i
    done
    flatpak build-update-repo /flatpak_dir/repo
    ostree refs --repo=/flatpak_dir/repo | tee /flatpak_dir/list.txt'

# Not `bluebuild generate-iso`: BlueBuild CLI (v0.9.37) pins build-container-installer v1.4.0,
# whose lorax templates strip /usr/sbin/load_policy. Anaconda 44.30 runs it on exit, crashes,
# and hangs at the end-of-install Reboot button. v1.5.0 keeps it. Same args BlueBuild passed.
echo "Building ${ISO_NAME} from ${IMAGE_REF}"
rm -f "${OUT_DIR}/${ISO_NAME}" "${OUT_DIR}/${ISO_NAME}-CHECKSUM"
sudo docker run --rm --privileged --network host \
  -v "${OUT_DIR}:/build-container-installer/build" \
  -v dnf-cache:/cache/dnf/ \
  "${INSTALLER_IMAGE}" \
  VARIANT=kinoite \
  "ISO_NAME=build/${ISO_NAME}" \
  DNF_CACHE=/cache/dnf \
  SECURE_BOOT_KEY_URL=https://github.com/ublue-os/bazzite/raw/main/secure_boot.der \
  ENROLLMENT_PASSWORD=universalblue \
  WEB_UI=false \
  "IMAGE_NAME=${IMAGE}" \
  "IMAGE_REPO=${REGISTRY}" \
  IMAGE_TAG=latest \
  VERSION=44 \
  FLATPAK_REMOTE_NAME=flathub \
  FLATPAK_REMOTE_URL=https://flathub.org/repo/flathub.flatpakrepo \
  "FLATPAK_REMOTE_REFS=${FLATPAK_REFS}" \
  FLATPAK_DIR=/build-container-installer/build/flatpak
cd "$OUT_DIR"
sudo chown "$(id -un):$(id -gn)" "$ISO_NAME"

echo "Generating checksum"
sha256sum "$ISO_NAME" > "${ISO_NAME}.sha256sum"

echo "Done: ${OUT_DIR}/${ISO_NAME}"
echo "      ${OUT_DIR}/${ISO_NAME}.sha256sum"
