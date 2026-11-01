# Token Current

## Platform
Native macOS 14 and later.

## Stack
Approved: Swift 6, SwiftUI MenuBarExtra, SwiftPM, system SQLite. No third-party runtime dependencies.

## Users and purpose
People working with local Claude Code and Codex sessions want to glance at total token consumption as easily as network throughput. The menu bar shows reported tokens per second; a popover explains provider activity and today's input, output, and cache usage.

## Capabilities and constraints
Read existing local usage logs. Count input plus output, including cache exactly once. Refresh the display each second using a 10-second rolling average of reported usage. Logs arrive in batches; never claim true streaming generation speed. Include nested agents, deduplication, current-day backfill, configurable data directories, optional login launch, pause, and local history reset. No credentials, remote service, telemetry, billing estimates, or quota tracking. Menu bar and popover only in v1.

## Brand commitments
Token Current. A precise native instrument with restrained motion and no mascot. System appearance, system typography, cyan Claude and amber Codex, a monochrome menu bar mark. The user approved this direction and implementation plan before development.

## Accessibility
Keyboard operation, VoiceOver labels, non-color provider distinctions, Reduce Motion, and Reduce Transparency.
