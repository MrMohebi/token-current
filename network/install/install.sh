#!/usr/bin/env bash
set -euo pipefail
# Run from an extracted release archive. Monitors the installing user’s logs.
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
# A headless/root SSH session often has no systemd user bus. Use a system
# service for root installs, rather than reporting success with no running agent.
SERVICE_MODE=user
UNIT_DIR="$CONFIG_BASE/systemd/user"
SERVICE_ACCOUNT=""
WANTED_BY=default.target
if [[ "$EUID" == 0 && -d /run/systemd/system ]]; then
  SERVICE_MODE=system
  UNIT_DIR=/etc/systemd/system
  SERVICE_ACCOUNT="User=root"
  WANTED_BY=multi-user.target
elif ! command -v systemctl >/dev/null || ! systemctl --user show-environment >/dev/null 2>&1; then
  echo 'Agent installed, but no background service could be started: this SSH session has no systemd user bus.' >&2
  echo "Run \"$BIN_DIR/token-current-agent\" run, or install from a systemd user session after enabling linger." >&2
  exit 1
fi
mkdir -p "$UNIT_DIR"
SERVICE_BINARY="${BIN_DIR//%/%%}/token-current-agent"
SERVICE_CONFIG="${CONFIG_BASE//%/%%}/Token Current/agent.json"
cat > "$UNIT_DIR/token-current-agent.service" <<UNIT
[Unit]
Description=Token Current usage agent
After=network-online.target tailscaled.service
[Service]
$SERVICE_ACCOUNT
ExecStart="$SERVICE_BINARY" run --config "$SERVICE_CONFIG"
Restart=on-failure
RestartSec=5
NoNewPrivileges=true
UMask=0077
[Install]
WantedBy=$WANTED_BY
UNIT
service_control() {
  if [[ "$SERVICE_MODE" == system ]]; then systemctl "$@"; else systemctl --user "$@"; fi
}
service_control daemon-reload
service_control enable --now token-current-agent.service
service_control restart token-current-agent.service
# Enabling Tailscale on an already-signed-in machine needs no credentials.
if command -v tailscale >/dev/null 2>&1 && "$BIN_DIR/token-current-agent" tailscale; then
  service_control restart token-current-agent.service
fi
if ! service_control is-active --quiet token-current-agent.service; then
  echo 'Agent service failed to start. Check: journalctl -u token-current-agent' >&2
  exit 1
fi
echo "Installed and running ($SERVICE_MODE service). On your Mac: Settings → Network → Tailscale → Connect."
