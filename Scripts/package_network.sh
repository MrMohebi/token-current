#!/usr/bin/env bash
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
source "$ROOT/version.env"
RELEASE_TAG="v$MARKETING_VERSION"
OUT="$ROOT/build/network"
mkdir -p "$OUT"
cd "$ROOT/network"
for TARGET in linux-amd64 linux-arm64 windows-amd64 windows-arm64; do
  TARGET_OS=${TARGET%-*}; TARGET_ARCH=${TARGET#*-}
  STAGE=$(mktemp -d)
  SUFFIX=""; [[ "$TARGET_OS" != windows ]] || SUFFIX=.exe
  CGO_ENABLED=0 GOOS="$TARGET_OS" GOARCH="$TARGET_ARCH" go build -trimpath -ldflags='-s -w' -o "$STAGE/token-current-agent$SUFFIX" ./cmd/token-current-agent
  cp "$ROOT/THIRD_PARTY_NOTICES.md" "$STAGE/THIRD_PARTY_NOTICES.md"
  cp "$ROOT/docs/NETWORK.md" "$STAGE/README.md"
  if [[ "$TARGET_OS" == windows ]]; then
    cp install/install.ps1 "$STAGE/install.ps1"
    python3 - "$STAGE" "$OUT/TokenCurrent-$RELEASE_TAG-agent-$TARGET.zip" <<'PY'
import pathlib,sys,zipfile
with zipfile.ZipFile(sys.argv[2],'w',zipfile.ZIP_DEFLATED) as z:
    for p in pathlib.Path(sys.argv[1]).iterdir(): z.write(p,p.name)
PY
  else
    cp install/install.sh "$STAGE/install.sh"
    tar -czf "$OUT/TokenCurrent-$RELEASE_TAG-agent-$TARGET.tar.gz" -C "$STAGE" .
  fi
  rm -rf "$STAGE"
done
for TARGET in linux-amd64 linux-arm64; do
  CGO_ENABLED=0 GOOS=linux GOARCH="${TARGET#*-}" go build -trimpath -ldflags='-s -w' -o "$OUT/token-current-$RELEASE_TAG-relay-$TARGET" ./cmd/token-current-relay
done
