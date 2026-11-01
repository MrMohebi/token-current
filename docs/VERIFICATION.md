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

## macOS CI verification

The [initial macOS workflow](https://github.com/MrMohebi/token-current/actions/runs/41307786824) compiled the native SwiftUI application, passed all 25 tests present in that revision, built both arm64 and x86_64 binaries, and passed Info.plist and code signature verification. Its final architecture assertion failed because the `lipo` command placed the input path after a variadic option; that command has been corrected. The workflow now also performs a native launch smoke test. Release assets are published only after the complete updated workflow succeeds.

## Pending interactive validation

Rendered screenshots/design review, keyboard/VoiceOver checks, login-item behavior, Instruments measurements, Developer ID signing, and notarization. Initial release assets are ad-hoc signed development bundles, not notarized distribution builds. Linux does not produce the `.app`; the workflow's macOS runner does.

Use `Scripts/compile_and_run.sh --test` on a Mac, then complete `MAC_VALIDATION.md`. Xcode previews are illustrative fixtures, not evidence of a running application.
