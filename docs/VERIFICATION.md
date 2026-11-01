# Verification record

Implementation workspace: Linux x86_64, November 1, 2026. Tested with the official Swift 6.1.3 Linux toolchain and system SQLite.

## Completed

- `swift test`: 28 test cases; 27 passed and the Unix permission test skipped under root, with zero failures.
- Re-ran `testPermissionDeniedSource` as the unprivileged `nobody` account: passed. All 28 distinct scenarios have therefore passed.
- `swift build -c release`: passed for the cross-platform core and Linux executable fallback. This does not compile the macOS-only UI.
- Parsed every native application source plus the icon-generation script with Swift's `arm64-apple-macosx14.0` target: syntax passed. Parsing does not type-check Apple framework APIs.
- `bash -n` on packaging, launch, and notarization scripts: passed.
- Invoked packaging on Linux: correctly refused with its macOS requirement, rather than generating a misleading `.app` from a Linux executable.
- Confirmed that an idle monitoring tick leaves the SQLite WAL unchanged, and that a multi-chunk wake backlog never enters live throughput.
- `python3 -m unittest discover -s Tests/Installer -v`: six installer tests passed, covering new installation, app-only updates, bad checksums/signatures/identity, staging-copy failures, and unsupported platforms. These use simulated macOS commands and do not claim a real end-user installation was performed.
- Brand SVG files were parsed as XML. The macOS packaging workflow draws the matching native icon and exports its PNG and ICNS into a downloadable brand kit.

## macOS CI verification

The [complete macOS workflow](https://github.com/MrMohebi/token-current/actions/runs/41307988103) passed all 28 tests with no skips or failures, compiled the native SwiftUI application for arm64 and x86_64, verified the universal bundle's Info.plist and code signature, and launched the native app and confirmed it remained running. It produced the application ZIP used for release preparation. Release assets are published only after the workflow succeeds on the tagged revision. Tag pushes do not repeat a branch build.

## Pending interactive validation

Rendered screenshots/design review, keyboard/VoiceOver checks, login-item behavior, Instruments measurements, Developer ID signing, and notarization. Initial release assets are ad-hoc signed development bundles, not notarized distribution builds. Linux does not produce the `.app`; the workflow's macOS runner does.

Use `Scripts/compile_and_run.sh --test` on a Mac, then complete `MAC_VALIDATION.md`. Xcode previews are illustrative fixtures, not evidence of a running application.

## Version 1.1 networking verification

- Swift: 33 scenarios, including combined/per-machine accounting, duplicate instance IDs, stale rates, UTC rollover, malformed remote counters, and transport endpoint restrictions. [Native macOS run](https://github.com/MrMohebi/token-current/actions/runs/41315456144) compiled both architectures, checked signatures, launched the app, created a DMG, mounted it, and verified its app executable matches the ZIP build.
- Go: race-detector tests for parser/accounting, cached tokens, forks, partial lines, truncation, wake catch-up, restart, enrollment, unauthorized requests, stale snapshots, duplicate reports, retired boots, token rotation, removal, and persisted state. [Cross-platform run](https://github.com/MrMohebi/token-current/actions/runs/41315456276) passed on Linux, Windows, and macOS.
- Actual Windows scheduled-task installation and health endpoint passed on a Windows runner. Linux in-place updates were tested while the previous agent executable was running; pairing configuration was preserved.
- Black-box tests built and ran real agent/relay processes against synthetic JSONL logs. Direct and relayed totals/rates, process restart, and device/management credential separation passed.
- Tailscale CLI setup was tested with a controlled executable fixture: correct HTTPS Serve arguments, peer URL output, and refusal to overwrite another service's port. Commands were checked against Tailscale's official documentation. No authenticated tailnet is available in this workspace, so actual cross-machine Tailscale connectivity remains an external acceptance check.
- Docker Compose relay built and started locally, served its health endpoint, and ran as UID 10001 with a read-only root filesystem and persistent data volume. The optional HTTPS Compose overlay parsed successfully. Public DNS/certificate issuance and deployment on the user's server have not been performed; no host was supplied.
- Chromium browser checks used a running relay with synthetic usage. Login, empty state, enrollment, per-machine selection, provider filtering, token rotation/removal, and keyboard focus retention during polling were exercised. Desktop light/dark and 390-point mobile screenshots were captured; mobile page overflow was checked. After publishers stopped, all three machines became offline, the live rate became unavailable, and the last daily totals remained visible. Screenshots in `assets/screenshots` show illustrative readings, not a customer's usage.
- Mac Keychain prompts, native interactive network controls, real tailnet permissions, sleep/wake on physical machines, and native VoiceOver/performance review remain pending alongside the existing interactive Mac checklist. The Mac release remains ad-hoc signed and not notarized.

Version 1.1.0 release assets were built from commit `5c46a27d14c780883f546f85121a0520315f78a0`. The Mac bundle's embedded GitCommit and version were checked before publication. All nine download assets are covered by SHA256SUMS.txt. The final workflow also verified drag-to-Applications DMG mounting and app identity.
