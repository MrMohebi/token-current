#!/usr/bin/env bash
set -euo pipefail
# Run from an extracted release archive. Installs for the current user, never root.
cd "$(dirname "$0")"
BIN_DIR="${TOKEN_CURRENT_BIN_DIR:-$HOME/.local/bin}"
mkdir -p "$BIN_DIR"
STAGED_BINARY=$(mktemp "$BIN_DIR/.token-current-agent.XXXXXX")
trap 'rm -f "$STAGED_BINARY"' EXIT
install -m 755 token-current-agent "$STAGED_BINARY"
mv -f "$STAGED_BINARY" "$BIN_DIR/token-current-agent"
CONFIG_BASE="${XDG_CONFIG_HOME:-$HOME/.config}"
if [[ ! -f "$CONFIG_BASE/Token Current/agent.json" ]]; then
  "$BIN_DIR/token-current-agent" init
fi
if [[ "${1:-}" == "--no-service" ]]; then
  echo "Installed. Run: \"$BIN_DIR/token-current-agent\" run"
  exit 0
fi
if ! command -v systemctl >/dev/null || ! systemctl --user show-environment >/dev/null 2>&1; then
  echo "Installed. A systemd user session is unavailable. Run: \"$BIN_DIR/token-current-agent\" run"
  exit 0
fi
mkdir -p "$CONFIG_BASE/systemd/user"
# systemd expands %, so escape it in file paths.
SERVICE_BINARY="${BIN_DIR//%/%%}/token-current-agent"
SERVICE_CONFIG="${CONFIG_BASE//%/%%}/Token Current/agent.json"
cat > "$CONFIG_BASE/systemd/user/token-current-agent.service" <<UNIT
[Unit]
Description=Token Current usage agent
After=network-online.target
[Service]
ExecStart="$SERVICE_BINARY" run --config "$SERVICE_CONFIG"
Restart=on-failure
RestartSec=5
NoNewPrivileges=true
UMask=0077
[Install]
WantedBy=default.target
UNIT
systemctl --user daemon-reload
systemctl --user enable --now token-current-agent.service
systemctl --user restart token-current-agent.service
echo "Installed and running. Pairing token: $BIN_DIR/token-current-agent token"
echo "For Tailscale: $BIN_DIR/token-current-agent tailscale"
echo "For an always-on server: sudo loginctl enable-linger \"$USER\""
