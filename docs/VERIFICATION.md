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
