# Token Current

## Platform
Native macOS 14 and later.

## Stack
Approved: Swift 6, SwiftUI MenuBarExtra, SwiftPM, system SQLite. No third-party runtime dependencies.

## Users and purpose
People working with local Claude Code and Codex sessions want to glance at total token consumption as easily as network throughput. The menu bar shows reported tokens per second; a popover explains provider activity and today's input, output, and cache usage.

## Capabilities and constraints
Read existing local usage logs. Count input plus output, including cache exactly once. Refresh the display each second using a 10-second rolling average of reported usage. Logs arrive in batches; never claim true streaming generation speed. Include nested agents, deduplication, current-day backfill, configurable data directories, optional login launch, pause, and local history reset. Local-only mode needs no credentials or remote service. No telemetry, billing estimates, or quota tracking. Version 1.1 adds optional cross-machine usage: standalone Go agents for Linux/Windows, direct Tailscale pairing, and a self-hosted relay with a browser dashboard. Network pairing tokens authorize metadata access; provider account credentials never leave their machines. The Mac menu bar combines selected machines; network-day accounting uses UTC.

## Brand commitments
Token Current. A precise native instrument with restrained motion and no mascot. System appearance, system typography, cyan Claude and amber Codex, a monochrome menu bar mark. The user approved this direction and implementation plan before development.

## Accessibility
Keyboard operation, VoiceOver labels, non-color provider distinctions, Reduce Motion, and Reduce Transparency.
