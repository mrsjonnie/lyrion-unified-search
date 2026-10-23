#!/bin/sh
# Safely refresh the LMS YouTube plugin's yt-dlp_linux from the verified
# upstream release. This avoids yt-dlp's self-updater, which may fail on
# QNAP QPKG/chroot systems when its bundled Python cannot load libutil.so.1.
set -eu

TARGET=${1:-/share/CACHEDEV1_DATA/.qpkg/LogitechMediaServer/SlimServer/Cache/InstalledPlugins/Plugins/YouTube/Bin/yt-dlp_linux}
WORKDIR=${TMPDIR:-/tmp}/lms-ytdlp-update.$$
BASE_API=https://api.github.com/repos/yt-dlp/yt-dlp/releases/latest
BASE_RELEASE=https://github.com/yt-dlp/yt-dlp/releases/download
cleanup() { rm -rf "$WORKDIR"; }
trap cleanup EXIT HUP INT TERM

for cmd in curl sha256sum awk sed mktemp; do
  command -v "$cmd" >/dev/null 2>&1 || { echo "ERROR: required command not found: $cmd" >&2; exit 1; }
done
[ -f "$TARGET" ] || { echo "ERROR: target binary not found: $TARGET" >&2; exit 1; }
mkdir -p "$WORKDIR"
chmod 700 "$WORKDIR"

TAG=$(curl -fsSL --retry 3 "$BASE_API" | sed -n 's/.*"tag_name":[[:space:]]*"([^"]*)".*/\1/p' | head -n 1)
[ -n "$TAG" ] || { echo "ERROR: unable to determine upstream release tag" >&2; exit 1; }
case "$TAG" in *[!A-Za-z0-9._-]*) echo "ERROR: unexpected release tag: $TAG" >&2; exit 1;; esac

URL="$BASE_RELEASE/$TAG"
curl -fL --retry 3 "$URL/yt-dlp_linux" -o "$WORKDIR/yt-dlp_linux"
curl -fL --retry 3 "$URL/SHA2-256SUMS" -o "$WORKDIR/SHA2-256SUMS"
EXPECTED=$(awk '$2 == "yt-dlp_linux" {print $1; exit}' "$WORKDIR/SHA2-256SUMS")
ACTUAL=$(sha256sum "$WORKDIR/yt-dlp_linux" | awk '{print $1}')
[ -n "$EXPECTED" ] && [ "$EXPECTED" = "$ACTUAL" ] || {
  echo "ERROR: SHA-256 verification failed; installed binary was not changed." >&2
  exit 1
}
chmod 755 "$WORKDIR/yt-dlp_linux"

# Preserve the previous binary and only swap after verification.
BACKUP="${TARGET}.bak.$(date +%Y%m%d%H%M%S)"
cp -p "$TARGET" "$BACKUP"
NEW="${TARGET}.new.$$"
cp "$WORKDIR/yt-dlp_linux" "$NEW"
chmod 755 "$NEW"
mv -f "$NEW" "$TARGET"

# Smoke test the binary itself. If the test fails, restore the backup.
if ! "$TARGET" --version; then
  echo "ERROR: new binary failed its version check; restoring backup." >&2
  cp -p "$BACKUP" "$TARGET"
  exit 1
fi
printf 'Updated yt-dlp to %s\nBackup: %s\n' "$TAG" "$BACKUP"
echo "Note: this updates the binary only; it does not patch the LMS plugin's own Update button."
