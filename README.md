# Token Current

A native macOS menu bar meter for **reported AI token consumption**. Track Claude Code and Codex together, with a rolling rate, 60-second graph, provider filters, and today's input, output, and cached tokens.

**Requires macOS 14+ and a Swift 6 toolchain (Xcode 16+).** There is no web runtime, server, login, API key, or telemetry. This repository includes the application source and packaging workflow; a signed release is not included.

## Build and run on a Mac

```bash
swift test
Scripts/compile_and_run.sh
```

The script builds an ad-hoc signed `build/TokenCurrent.app`, launches it, and checks that the process stays running. Look for the arrow mark in your menu bar; the app has no Dock icon. Move the app to Applications if you want to keep it, and enable **Launch at login** in Settings if desired. Re-run the launch script after source changes.

To build without launching:

```bash
Scripts/package_app.sh release
open build/TokenCurrent.app
```

To produce a universal Apple silicon / Intel development build:

```bash
ARCHES="arm64 x86_64" SIGNING_MODE=adhoc Scripts/package_app.sh release
```

The scripts derive from the macOS SwiftPM packaging skill and generate the app icon from native drawing code. No image downloads or package dependencies are required.

## First use

1. Start a local Claude Code or Codex session.
2. Click the menu bar readout. Current-day logs load in the background; imported history does not enter the live rate.
3. Choose All, Claude, or Codex. The selection applies to the menu bar, headline rate, graph, provider rows, and today's totals.
4. Open Settings to change display density, data folders, or login launch. `⌘,` opens Settings; `⇧⌘P` pauses/resumes monitoring while the popover is open. The More menu includes Quit (`⌘Q`).

Default data homes are `~/.claude` and `~/.codex`. Claude transcripts are read under `projects/**/*.jsonl`; Codex rollouts under `sessions/**/*.jsonl` and `archived_sessions/**/*.jsonl`. Nested agent directories are included. For nonstandard installations, select the corresponding **data home**, not an individual transcript, and click **Apply folders**.

Waiting means no supported usage has been found yet. A missing folder, access failure, or unsupported record format has an explicit status. An em dash means no current measurement; zero means a connected source reported no new tokens in the last 10 seconds. If only one provider is connected, All shows that provider's rate and the other provider's status remains visible.

## What the rate means

The display updates once each second:

```text
reported tok/s = new input and output tokens observed in the last 10 seconds / 10
```

This is **reported consumption**, not model decoding speed. Usage may be written only at response boundaries. A large prompt/cache update therefore produces a visible burst, and a tool may be working while the meter waits for a usage record. The graph shows the same rolling measurement over the last 60 seconds. Pause/resume, restart, and sleep/wake backlogs do not produce fabricated live spikes.

Claude input includes its separate uncached, cache-read, and cache-creation fields. Codex cached input and reasoning are subsets of input/output and are not added a second time. Cached includes reads and writes when exposed by the source. Repeated/revised Claude message records and cumulative Codex snapshots are deduplicated. Modern Codex `token_usage_record` thread totals and legacy `event_msg/token_count` totals share one ledger.

Forked Codex sessions exclude inherited counters using session metadata and the latest request's usage when present. For older fork logs that lack both copied history and last-request usage, the first snapshot establishes a conservative baseline; its own first request may be undercounted. Decreasing/stale cumulative snapshots never subtract usage or generate a second charge. Unknown formats are reported rather than guessed. Compressed/non-JSONL session archives and remote sessions without local logs are not supported in v1.

The adapter contracts are based on [Claude cache accounting](https://platform.claude.com/docs/en/build-with-claude/prompt-caching), [Codex's protocol](https://github.com/openai/codex/blob/main/codex-rs/protocol/src/protocol.rs), and [Codex rollout serialization](https://github.com/openai/codex/blob/main/codex-rs/history/src/rollout_payload.rs).

## Local storage

Usage metadata lives in `~/Library/Application Support/Token Current/usage.sqlite`. Conversation bodies and credentials are never stored. Today follows the Mac's current calendar/time zone; older event history is pruned on the next day. High-water counters and file checkpoints survive restart and pruning so copied or archived logs do not count twice.

**Clear local usage history** removes stored token events and the live graph while preserving deduplication metadata and file positions. Already-read usage stays cleared. To remove all app state, quit Token Current and remove its Application Support directory and the preferences for bundle ID `app.tokencurrent.mac`; the next launch will import the current day again.

Log reads and parsing run on an actor outside the UI. Reads are bounded, incomplete lines wait for a newline, and unchanged checkpoints do not generate database writes. Directory notifications accelerate new-file discovery, backed by a 30-second scan. On very large trees, watchers are capped at 256 directories; newly created sessions may take up to that fallback interval to appear. The app scans only logs modified today, plus incremental contents of discovered files.

## Verification

```bash
swift test
bash -n Scripts/package_app.sh Scripts/compile_and_run.sh Scripts/sign-and-notarize.sh
```

The accounting library and its tests also build on Linux with Swift 6 and `libsqlite3-dev`. Linux builds intentionally exclude the SwiftUI/AppKit interface; they do not validate macOS APIs or rendering.

The GitHub Actions workflow runs tests on macOS, builds a universal app, checks its bundle/signature/architectures, and uploads a development ZIP. It runs after this repository is placed on GitHub; it has not been executed from this Linux workspace.

Before distributing, complete the [Mac acceptance checks](docs/MAC_VALIDATION.md). Xcode previews include explicitly illustrative light/dark readings; the running app never uses preview measurements.

## Signed releases

Configure your Developer ID Application signing identity and a `notarytool` Keychain profile, then run:

```bash
APP_IDENTITY="Developer ID Application: Your Name (TEAMID)" \
NOTARY_PROFILE="TokenCurrent" \
Scripts/sign-and-notarize.sh
```

The script builds a universal app with hardened runtime, notarizes and staples it, verifies Gatekeeper acceptance, and writes `build/TokenCurrent-1.0.0.zip`. It does not publish or upload a release to GitHub. Increment `version.env` before each release. The app uses direct distribution without App Sandbox; it needs read access to the selected log folders.

## Project layout

- `Sources/TokenCurrentCore`: narrow log decoders, normalized counters, SQLite ledger, bounded file tailer, discovery engine, and rolling-rate calculator.
- `Sources/TokenCurrent`: SwiftUI menu bar, popover, chart, settings, directory notifications, login-item integration, and Xcode previews.
- `Tests/TokenCurrentCoreTests`: synthetic provider records and filesystem integration scenarios.
- `Scripts`: app bundle assembly, code-native icon generation, local launch, and signing/notarization.

The approved product and interface decisions are recorded in `PRODUCT.md` and `DESIGN.md`.
