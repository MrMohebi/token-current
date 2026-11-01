#!/usr/bin/env bash
set -euo pipefail
if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "Notarization requires macOS." >&2
  exit 1
fi
ROOT_DIR=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT_DIR"
source "$ROOT_DIR/version.env"
: "${APP_IDENTITY:?Set APP_IDENTITY to your Developer ID Application identity.}"
: "${NOTARY_PROFILE:?Set NOTARY_PROFILE to a notarytool keychain profile.}"
export APP_IDENTITY
export ARCHES=${ARCHES:-"arm64 x86_64"}
export SIGNING_MODE=release
"$ROOT_DIR/Scripts/package_app.sh" release
APP="$ROOT_DIR/build/TokenCurrent.app"
ZIP="$ROOT_DIR/build/TokenCurrent-${MARKETING_VERSION}.zip"
TEMP_DIR=$(mktemp -d "${TMPDIR:-/tmp}/TokenCurrent-notary.XXXXXX")
trap 'rm -rf "$TEMP_DIR"' EXIT
ditto --norsrc -c -k --keepParent "$APP" "$TEMP_DIR/submit.zip"
xcrun notarytool submit "$TEMP_DIR/submit.zip" --keychain-profile "$NOTARY_PROFILE" --wait
xcrun stapler staple "$APP"
xcrun stapler validate "$APP"
codesign --verify --deep --strict --verbose=2 "$APP"
spctl --assess --type execute --verbose "$APP"
ditto --norsrc -c -k --keepParent "$APP" "$ZIP"
printf 'Notarized archive: %s\n' "$ZIP"
