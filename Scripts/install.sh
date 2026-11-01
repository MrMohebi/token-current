#!/usr/bin/env bash
# Install a checksum-verified GitHub release. No sudo, agent hooks, or extra runtime required.
set -euo pipefail

fail() { printf 'Token Current: %s\n' "$*" >&2; exit 1; }
[[ "$(uname -s)" == "Darwin" ]] || fail "This app requires macOS 14 or later."
mac_version=$(sw_vers -productVersion)
[[ "${mac_version%%.*}" -ge 14 ]] || fail "macOS 14 or later is required (found $mac_version)."

release_version=${TOKEN_CURRENT_VERSION:-latest}
if [[ "$release_version" == "latest" ]]; then
  release_base="https://github.com/MrMohebi/token-current/releases/latest/download"
else
  [[ "$release_version" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]] || fail "TOKEN_CURRENT_VERSION must be a tag such as v1.0.0."
  release_base="https://github.com/MrMohebi/token-current/releases/download/$release_version"
fi

install_dir=${TOKEN_CURRENT_INSTALL_DIR:-"$HOME/Applications"}
[[ "$install_dir" == /* ]] || fail "The installation directory must be an absolute path."
work_dir=$(mktemp -d "${TMPDIR:-/tmp}/TokenCurrent-install.XXXXXX")
staging=""
backup=""
destination="$install_dir/TokenCurrent.app"
cleanup() {
  local result=$?
  if [[ -n "$backup" && -d "$backup" && ! -e "$destination" ]]; then
    mv "$backup" "$destination" || true
  fi
  [[ -z "$staging" ]] || rm -rf "$staging"
  rm -rf "$work_dir"
  return "$result"
}
trap cleanup EXIT

printf 'Downloading Token Current (%s)…\n' "$release_version"
curl --fail --silent --show-error --location --proto '=https' --tlsv1.2 \
  "$release_base/TokenCurrent-macos-universal.zip" -o "$work_dir/TokenCurrent-macos-universal.zip"
curl --fail --silent --show-error --location --proto '=https' --tlsv1.2 \
  "$release_base/SHA256SUMS.txt" -o "$work_dir/SHA256SUMS.txt"
checksum=$(awk '$2 == "TokenCurrent-macos-universal.zip" && length($1) == 64 { print $1 }' "$work_dir/SHA256SUMS.txt")
[[ "$checksum" =~ ^[0-9a-fA-F]{64}$ ]] || fail "The release does not contain a valid app checksum."
printf '%s  %s\n' "$checksum" 'TokenCurrent-macos-universal.zip' > "$work_dir/app.sha256"
(cd "$work_dir" && shasum -a 256 -c app.sha256) || fail "Download checksum failed; the installed app has not been changed."

ditto -x -k "$work_dir/TokenCurrent-macos-universal.zip" "$work_dir/extracted"
bundle="$work_dir/extracted/TokenCurrent.app"
[[ -d "$bundle" && -x "$bundle/Contents/MacOS/TokenCurrent" ]] || fail "The download does not contain the expected app."
bundle_id=$(plutil -extract CFBundleIdentifier raw -o - "$bundle/Contents/Info.plist")
[[ "$bundle_id" == "app.tokencurrent.mac" ]] || fail "The downloaded app has an unexpected bundle identifier."
codesign --verify --deep --strict "$bundle" || fail "The downloaded app's signature is invalid."

mkdir -p "$install_dir"
[[ -w "$install_dir" ]] || fail "Cannot write to $install_dir. Choose a writable TOKEN_CURRENT_INSTALL_DIR."
staging=$(mktemp -d "$install_dir/.TokenCurrent-install.XXXXXX")
ditto "$bundle" "$staging/TokenCurrent.app"
codesign --verify --deep --strict "$staging/TokenCurrent.app"
pkill -x TokenCurrent > /dev/null 2>&1 || true
if [[ -e "$destination" ]]; then
  [[ -d "$destination" && ! -L "$destination" ]] || fail "The destination is not an ordinary app folder."
  backup=$(mktemp -d "$install_dir/.TokenCurrent-previous.XXXXXX")
  rmdir "$backup"
  mv "$destination" "$backup"
fi
mv "$staging/TokenCurrent.app" "$destination"
if [[ -n "$backup" ]]; then rm -rf "$backup"; backup=""; fi
printf '\nInstalled: %s\n' "$destination"
printf 'This release is ad-hoc signed and is not Apple-notarized.\n'
if ! open "$destination"; then
  printf 'Open the app in Finder. If blocked, use System Settings → Privacy & Security → Open Anyway.\n'
fi
printf 'Look for the up/down arrows in your menu bar. Start a Claude Code or Codex session to see usage.\n'
