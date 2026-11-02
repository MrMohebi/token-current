# Project conventions

- Every public release download must include its release tag in the filename, including DMG, ZIP, agent archives, relay executables, brand kits, and SHA256SUMS manifests. Use `TokenCurrent-vX.Y.Z-…`, `token-current-vX.Y.Z-relay-…`, and `SHA256SUMS-vX.Y.Z.txt`.
- Keep the installed app and executable names stable. Resolve latest to a specific tag before downloading assets and checksums. Update direct download links when bumping `version.env`.
- Preserve existing agent configuration, usage history, and service settings when updating the live installation. Never print pairing tokens or conversation content.
- A zero 10-second reported rate between usage batches is expected. Never invent live tokens or replay backfills to hide reporting gaps.
