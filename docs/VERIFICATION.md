# Verification record

Implementation workspace: Linux x86_64, November 1, 2026. Tested with the official Swift 6.1.3 Linux toolchain and system SQLite.

## Completed

- `swift test`: 25 test cases; 24 passed and the Unix permission test skipped under root, with zero failures.
- Re-ran `testPermissionDeniedSource` as the unprivileged `nobody` account: passed. All 25 distinct scenarios have therefore passed.
- `swift build -c release`: passed for the cross-platform core and Linux executable fallback. This does not compile the macOS-only UI.
- Parsed every native application source plus the icon-generation script with Swift's `arm64-apple-macosx14.0` target: syntax passed. Parsing does not type-check Apple framework APIs.
- `bash -n` on packaging, launch, and notarization scripts: passed.
- Invoked packaging on Linux: correctly refused with its macOS requirement, rather than generating a misleading `.app` from a Linux executable.
- Confirmed that an idle monitoring tick leaves the SQLite WAL unchanged, and that a multi-chunk wake backlog never enters live throughput.

## Pending on macOS

Native compilation, launch, rendered screenshots/design review, keyboard/VoiceOver checks, login-item behavior, Instruments measurements, universal bundle checks, signing, and notarization. No launchable macOS `.app`, screenshot, or notarized release has been produced on Linux. The macOS GitHub Actions workflow is configured but has not run here.

Use `Scripts/compile_and_run.sh --test` on a Mac, then complete `MAC_VALIDATION.md`. Xcode previews are illustrative fixtures, not evidence of a running application.
