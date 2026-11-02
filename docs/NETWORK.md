# Connect your machines

Token Current can add up Claude Code and Codex usage across your Mac, Linux servers, and Windows PCs. Each machine reads its own local usage logs. You do not install anything into Claude Code or Codex.

Choose one connection method:

| | Direct / Tailscale | Self-hosted relay |
| --- | --- | --- |
| Best for | Your own machines on one tailnet | A central dashboard and fleet management |
| Token Current server needed | No | Yes, on your server |
| Combined Mac menu bar | Yes | Yes |
| Browser view | Each agent's own meter, no sign-in | Combined network and per-machine meters |
| Pairing | Click Connect; no token | One management token and separate device tokens |
| Network | Private Tailscale HTTPS | Your HTTPS domain, or private Tailscale Serve |

**Machine map lines show connections to the collector.** Tailscale handles the underlying mesh network; Token Current does not implement peer gossip or route traffic. You can select a single machine or **All machines** in the Mac popover. The same selection applies to the headline, graph, provider rows, and totals.

## Install an agent

Install an agent on every **remote machine that runs your AI tools**, as the same user who runs those tools. The native Mac app reads this Mac's logs itself, so do not also pair an agent watching the same Mac logs.

### Linux

Run as your ordinary user, without sudo:

```bash
curl -fsSL https://raw.githubusercontent.com/MrMohebi/token-current/main/Scripts/install_agent.sh | bash
```

This downloads the correct amd64/arm64 archive, verifies the release checksum, installs `~/.local/bin/token-current-agent`, and starts a systemd service. Root installs use a system service; regular user installs use a user service. Add `~/.local/bin` to PATH if your shell does not already include it. You can [read the installer](../Scripts/install_agent.sh) first.

For a server that should keep monitoring after logout:

```bash
sudo loginctl enable-linger "$USER"
```

Without a usable service manager, installation reports a failure and explains how to run the agent in the foreground. For manual installation, download the Linux archive from [Releases](https://github.com/MrMohebi/token-current/releases/latest), extract it, then run `bash install.sh` (or `bash install.sh --no-service`).

### Windows

1. Download **TokenCurrent-agent-windows-amd64.zip** from [Releases](https://github.com/MrMohebi/token-current/releases/latest). Use arm64 for a Windows on ARM PC.
2. Extract the ZIP.
3. Open PowerShell in the extracted folder and run:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\install.ps1
```

The script installs in `%LOCALAPPDATA%\TokenCurrent\bin`, protects the configuration folder, and creates a **Token Current Agent** scheduled task for your account. It runs now and when you sign in. It does not require administrator access. This per-user task runs while your user is signed in; it is not a Windows SYSTEM service.

Use the installed executable in the remaining commands:

```powershell
$Agent = "$env:LOCALAPPDATA\TokenCurrent\bin\token-current-agent.exe"
& $Agent token
```

Agents have no AI provider API keys. Their pairing tokens authorize Token Current access only.

## Direct Tailscale mode

**No Token Current relay, pairing token, HTTPS certificates, or Tailscale Serve is needed.** Tailscale handles encryption and access. Your tailnet rules must allow the Mac to reach the agent on port **8791**.

### On the server

With Tailscale already signed in, run or re-run the Linux installer:

```bash
curl -fsSL https://raw.githubusercontent.com/MrMohebi/token-current/main/Scripts/install_agent.sh | bash
```

The installer enables Tailscale access and restarts the agent automatically. Root installs on headless servers use a boot-persistent system service; regular signed-in users use their systemd user service. Run it as the account whose Claude/Codex logs you want to measure. An update preserves your existing paths, history, and legacy tokens.

If you installed the binary manually:

```bash
token-current-agent tailscale
systemctl --user restart token-current-agent
```

For a root/system install, use `systemctl restart token-current-agent` instead. On Windows, run the updated `install.ps1`; it enables Tailscale automatically when its CLI is installed. You can also run `& $Agent tailscale`, then restart the scheduled task.

### On the Mac

1. Update to **Token Current 1.2 or later**.
2. Open **Settings → Network** and choose **Tailscale**.
3. Click **Find machines**, then **Connect** beside your server.

That is all. You can also enter its **100.x.y.z Tailscale IP** directly and click Connect. Token Current checks the agent before saving the connection. Its browser meter opens at `http://100.x.y.z:8791` with no sign-in form.

Direct connections use the machine's private IP, so MagicDNS and tailnet HTTPS do not have to be enabled. The agent binds its tokenless, read-only endpoint only to its own Tailscale addresses. Its authenticated local API on port 8790 and the public relay's tokens remain available for advanced setups. Only devices allowed by your tailnet's network policy can reach the private endpoint.

### Updating from 1.1

Update the server agent and re-run the installer; then replace the Mac app using the new DMG. Remove the old paired entry in Network settings and click Connect beside the discovered server. The old token-based flow is kept under **Advanced: older agents with tokens**.

Existing Tailscale Serve mappings are left alone. You can remove a mapping you no longer use yourself. Version 1.2 never requires creating or modifying a Serve mapping.

### If the server appears but will not connect

Discovery shows that Tailscale knows the machine; it does not prove its agent is running. Check the service:

```bash
# Root/system install:
systemctl status token-current-agent
journalctl -u token-current-agent -n 30 --no-pager
# Regular user install:
systemctl --user status token-current-agent
journalctl --user -u token-current-agent -n 30 --no-pager
```

A 1.1 installer could finish on a headless server with no user bus and leave no running agent. Version 1.2 fixes root installs and reports a clear failure if it cannot create a background service. For a non-root SSH account without a user bus, enable lingering and establish a systemd user session, or supervise `token-current-agent run` with your server's process manager.

From the Mac, open `http://SERVER_TAILSCALE_IP:8791/healthz`: it should return `{"ok":true}`. If it does not, check that both devices are online in Tailscale, that the service is running, and that port 8791 is allowed by the tailnet and host firewall. No token should be pasted for the new Tailscale connection.

## Self-hosted relay and combined browser dashboard

The relay stores the last usage snapshot from each enrolled machine, serves the dashboard, and accepts reports. It never needs access to your source logs.

### Start with Docker Compose

On your own Linux server with Docker Compose:

```bash
git clone https://github.com/MrMohebi/token-current.git
cd token-current/network/deploy
docker compose up -d --build
```

The dashboard listens on **127.0.0.1:8787**, and relay data persists in the `relay-data` Docker volume. The container runs as a non-root user. By default the service is private to the server.

Choose how to reach it:

**Private Tailscale access**, on a server already in your tailnet:

```bash
tailscale serve --bg http://127.0.0.1:8787
```

Use the HTTPS URL Tailscale prints. Check existing Serve configuration first if another service already uses port 443.

**Public HTTPS domain**, pointing DNS at your server, with ports 80/443 reachable:

```bash
export TOKEN_CURRENT_DOMAIN=tokens.example.com
docker compose -f compose.yaml -f compose.https.yaml up -d --build
```

The Caddy overlay obtains HTTPS certificates and proxies to the relay. Use `https://tokens.example.com`. Keep your domain variable set (or in a private local `.env`) when running Compose commands using that overlay.

Read your management token on the server:

```bash
docker compose exec relay /token-current-relay token --state /data/relay.json
```

This intentionally prints a secret in your terminal. Do not paste it into issues or screenshots.

### Pair and manage machines

1. Open the relay URL in your browser. Enter its **management token**.
2. Click **Add machine**, enter a name, and copy the generated **device token**. It is shown once.
3. On that machine, run:

```bash
~/.local/bin/token-current-agent configure
systemctl --user restart token-current-agent
```

Enter the relay URL, then its device token when prompted. Windows:

```powershell
& $Agent configure
Stop-ScheduledTask -TaskName 'Token Current Agent'
Start-ScheduledTask -TaskName 'Token Current Agent'
```

4. Repeat for other machines. The dashboard updates automatically.

To manage the same relay from your Mac, choose **Self-hosted relay** in **Settings → Network**, enter its URL and management token, then **Save relay connection**. Click **Add this Mac to relay** to publish your Mac's local usage too. You can create device tokens, rotate tokens, and remove machines from the Mac app or the browser dashboard.

**Remove** revokes that device immediately. **Rotate token** replaces its publishing token; configure and restart the agent with the replacement. Device tokens cannot list machines or manage the relay. The relay supports up to 128 devices. The management token is saved in the Mac Keychain and held only in memory in a browser tab; reload the browser to sign in again.

### Run without Docker

Download `token-current-relay-linux-amd64` (or arm64), make it executable, and run as an ordinary user:

```bash
chmod +x token-current-relay-linux-amd64
./token-current-relay-linux-amd64 serve --state "$HOME/.config/token-current-relay/state.json"
```

Use your own process manager for unattended operation. It binds loopback by default; put Tailscale Serve or an HTTPS reverse proxy in front. Read the management token with the same binary's `token --state ...` command.

## Understand combined numbers

- The headline adds **reported input + output tokens**, including cache input once, over the preceding 10 seconds. Each machine computes its rate locally; consumers add the latest fresh rates.
- Every agent refreshes each second. Discovery scans for new log files every five seconds. Network delays can make readings arrive later.
- **Network “Today” uses UTC on all machines.** Local-only Mac mode uses the Mac's local day. Separate local/UTC ledgers avoid changing the meaning of existing history when you switch modes.
- An agent is offline after **15 seconds** without a fresh report. Its stale rate contributes nothing. Its last reported UTC-day totals remain visible until midnight UTC. The app may show a partial total while a machine is offline.
- On restart or wake, historical usage loads into totals without a live spike. Unsent samples are not replayed as live activity. Absolute counters prevent retransmission from adding duplicate usage.
- Each machine is counted once by its instance ID. **Do not monitor synchronized copies of the same session logs on multiple machines.** Cross-machine copies with different IDs cannot be automatically recognized as the same usage.
- This is usage metering, not billing or quota tracking. Prompts, responses, repository names, model credentials, and source file paths are not sent. Machine names, OS, source status, UTC-day totals, rate, timestamps, and random instance identifiers are sent.

## Configuration, updates, and removal

Agent configuration lives at `~/.config/Token Current/agent.json` on Linux (`XDG_CONFIG_HOME` respected) or `%APPDATA%\Token Current\agent.json` on Windows. `usage-state.json` alongside it contains token counters, deduplication keys, and file checkpoints; no conversation text is retained. Config files contain pairing credentials: keep them private and include them only in protected backups. The Go collector uses a private atomic JSON ledger; the Mac app uses SQLite.

To choose nonstandard data folders, initialize before installing the background task:

```bash
token-current-agent init --claude-home /path/to/.claude --codex-home /path/to/.codex
```

`CLAUDE_CONFIG_DIR` and `CODEX_HOME` are respected at initialization. Claude's XDG folder is detected if the default folder is absent. You can edit paths in `agent.json` while the agent is stopped; restart afterward. The agent must be able to read its user's source logs. WSL logs require accessible Windows paths when using the Windows agent; running the Linux agent inside WSL is usually simpler.

Run the same installer again to update the binary; configuration and history remain. Linux logs: `journalctl --user -u token-current-agent -f` (omit `--user` for a root/system install). Windows task status: `Get-ScheduledTaskInfo -TaskName 'Token Current Agent'`. To troubleshoot foreground output, stop its background task and run `token-current-agent run`.

Linux removal (omit `--user` and use `/etc/systemd/system/token-current-agent.service` for root/system installs):

```bash
systemctl --user disable --now token-current-agent
rm -f ~/.config/systemd/user/token-current-agent.service ~/.local/bin/token-current-agent
systemctl --user daemon-reload
```

Windows removal:

```powershell
Stop-ScheduledTask -TaskName 'Token Current Agent'
Unregister-ScheduledTask -TaskName 'Token Current Agent' -Confirm:$false
Remove-Item "$env:LOCALAPPDATA\TokenCurrent" -Recurse
```

These keep configuration and history. Delete the Token Current config directory yourself if you also want to erase credentials and history. Remove the device from your relay or unpair it from the Mac. If configured, disable only this service's Tailscale Serve mapping (`tailscale serve --https=8790 off`); do not reset other Serve mappings.

Back up the relay's `/data/relay.json` securely; it includes the management token and last known device snapshots. Losing it requires enrolling agents again. Stop the relay before manually replacing its state. To change a lost/exposed management token, stop the relay, replace the `adminToken` JSON value with a cryptographically random 64-character hex secret, and restart. Device enrollment hashes remain valid.

## Build and verify

```bash
cd network
go test -race ./...
go vet ./...
go build ./cmd/token-current-agent
go build ./cmd/token-current-relay
```

Go 1.24+ is required to build. Release archives are standalone binaries; users do not need Go, Node.js, or Python. From the repository root, `Scripts/package_network.sh` produces Linux/Windows amd64/arm64 agent archives and Linux relay binaries. GitHub Actions tests the networking code on Linux, Windows, and macOS. Native Mac UI builds and launch checks run separately on a Mac runner.

For native Mac connection diagnostics, quit the app, then run:

```bash
/Applications/TokenCurrent.app/Contents/MacOS/TokenCurrent --check-tailnet 100.x.y.z
```

This tests the same URLSession connection and macOS transport policy used by the menu bar app, prints a short result, and exits. It does not print tokens or conversation data. If macOS requests Local Network access, allow it for Token Current in System Settings → Privacy & Security → Local Network.
