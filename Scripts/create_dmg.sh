#!/usr/bin/env bash
# Make a standard drag-to-Applications disk image, without third-party packaging tools.
set -euo pipefail
trap 'printf "DMG packaging failed at line %s\n" "$LINENO" >&2' ERR
[[ "$(uname -s)" == "Darwin" ]] || { echo "DMG packaging requires macOS." >&2; exit 1; }
ROOT_DIR=$(cd "$(dirname "$0")/.." && pwd)
APP=${1:-"$ROOT_DIR/build/TokenCurrent.app"}
[[ -d "$APP" && -x "$APP/Contents/MacOS/TokenCurrent" ]] || { echo "Build or supply TokenCurrent.app first." >&2; exit 1; }
VERSION=$(plutil -extract CFBundleShortVersionString raw -o - "$APP/Contents/Info.plist")
[[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || { echo 'Invalid bundle version' >&2; exit 1; }
OUTPUT=${2:-"$ROOT_DIR/build/TokenCurrent-v$VERSION-macos-universal.dmg"}
codesign --verify --deep --strict "$APP"
mkdir -p "$(dirname "$OUTPUT")"
WORK_DIR=$(mktemp -d "${TMPDIR:-/tmp}/TokenCurrent-dmg.XXXXXX")
MOUNT_DIR="$WORK_DIR/mount"
mounted=0
cleanup() {
  if [[ "$mounted" == 1 ]]; then
    hdiutil detach "$MOUNT_DIR" -quiet || hdiutil detach "$MOUNT_DIR" -force -quiet || true
  fi
  rm -rf "$WORK_DIR"
}
trap cleanup EXIT
mkdir -p "$WORK_DIR/stage" "$MOUNT_DIR"
ditto "$APP" "$WORK_DIR/stage/TokenCurrent.app"
ln -s /Applications "$WORK_DIR/stage/Applications"

app_kb=$(du -sk "$APP" | awk '{print $1}')
size_mb=$((app_kb / 1024 + 32))
if [[ "$size_mb" -lt 64 ]]; then size_mb=64; fi
# DiskImages services can briefly be busy on fresh hosted Macs. Keep diagnostics
# visible and retry the idempotent create operation before failing the build.
create_image() {
  local attempt
  for attempt in 1 2 3; do
    if hdiutil create -ov -fs HFS+ -size "${size_mb}m" -volname "Token Current" \
      -srcfolder "$WORK_DIR/stage" -format UDRW "$WORK_DIR/writable.dmg"; then return 0; fi
    echo "Disk image creation attempt $attempt failed; retrying…" >&2
    sleep "$attempt"
  done
  return 1
}
create_image
hdiutil attach -readwrite -noverify -noautoopen -mountpoint "$MOUNT_DIR" "$WORK_DIR/writable.dmg"
mounted=1

# Finder customization is optional: a plain disk image still has the app and Applications shortcut.
# Bound Apple Events execution because GUI automation can be unavailable on a build machine.
cat > "$WORK_DIR/layout.applescript" <<'APPLESCRIPT'
on run arguments
  set imageFolder to POSIX file (item 1 of arguments) as alias
  tell application "Finder"
    open imageFolder
    set imageWindow to front Finder window
    set current view of imageWindow to icon view
    set toolbar visible of imageWindow to false
    set statusbar visible of imageWindow to false
    set bounds of imageWindow to {200, 200, 800, 580}
    set options to icon view options of imageWindow
    set arrangement of options to not arranged
    set icon size of options to 112
    set text size of options to 14
    set position of item "TokenCurrent.app" of imageFolder to {155, 155}
    set position of item "Applications" of imageFolder to {435, 155}
    update imageFolder without registering applications
    delay 1
    close imageWindow
  end tell
end run
APPLESCRIPT
osascript "$WORK_DIR/layout.applescript" "$MOUNT_DIR" > "$WORK_DIR/layout.log" 2>&1 &
layout_pid=$!
(sleep 15; kill "$layout_pid" > /dev/null 2>&1 || true) &
watchdog_pid=$!
if wait "$layout_pid"; then
  echo "Finder drag-to-Applications layout applied."
else
  echo "Finder customization unavailable; using the standard app + Applications layout."
  cat "$WORK_DIR/layout.log"
fi
kill "$watchdog_pid" > /dev/null 2>&1 || true
wait "$watchdog_pid" 2>/dev/null || true
sync
hdiutil detach "$MOUNT_DIR" -quiet
mounted=0
hdiutil convert "$WORK_DIR/writable.dmg" -ov -format UDZO -imagekey zlib-level=9 -o "$OUTPUT"
hdiutil verify "$OUTPUT"
printf 'Created %s\n' "$OUTPUT"
