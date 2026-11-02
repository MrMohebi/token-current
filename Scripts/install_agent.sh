#!/usr/bin/env bash
set -euo pipefail
[[ "$(uname -s)" == Linux ]] || { echo 'Use the Windows archive installer or Mac DMG on other systems.' >&2; exit 1; }
case "$(uname -m)" in x86_64) PLATFORM=linux-amd64;; aarch64|arm64) PLATFORM=linux-arm64;; *) echo 'Supported Linux architectures: amd64, arm64' >&2; exit 1;; esac
STAGE=$(mktemp -d)
trap 'rm -rf "$STAGE"' EXIT
VERSION=${TOKEN_CURRENT_VERSION:-latest}
if [[ "$VERSION" == latest ]]; then
  RESOLVED=$(curl --fail --silent --show-error --head --location --proto '=https' --tlsv1.2 -o /dev/null -w '%{url_effective}' "https://github.com/MrMohebi/token-current/releases/latest")
  VERSION=${RESOLVED##*/}
fi
[[ "$VERSION" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]] || { echo 'Invalid release version' >&2; exit 1; }
BASE="https://github.com/MrMohebi/token-current/releases/download/$VERSION"
ASSET="TokenCurrent-$VERSION-agent-$PLATFORM.tar.gz"
curl --fail --location --silent --show-error "$BASE/$ASSET" -o "$STAGE/$ASSET"
curl --fail --location --silent --show-error "$BASE/SHA256SUMS-$VERSION.txt" -o "$STAGE/checksums"
EXPECTED=$(awk -v asset="$ASSET" '$2 == asset {print $1}' "$STAGE/checksums")
[[ "$EXPECTED" =~ ^[a-fA-F0-9]{64}$ ]] || { echo 'Release checksum missing' >&2; exit 1; }
printf '%s  %s\n' "$EXPECTED" "$STAGE/$ASSET" | sha256sum --check --status
tar -xzf "$STAGE/$ASSET" -C "$STAGE"
bash "$STAGE/install.sh"
