#!/usr/bin/env python3
"""Validate a complete, versioned release folder and write its SHA-256 manifest."""
import hashlib
from pathlib import Path
import re
import sys


def prepare(directory: Path, tag: str) -> Path:
    if not re.fullmatch(r"v\d+\.\d+\.\d+", tag):
        raise ValueError("Use a release tag such as v1.2.1")
    expected = {
        f"TokenCurrent-{tag}-macos-universal.dmg",
        f"TokenCurrent-{tag}-macos-universal.zip",
        f"TokenCurrent-{tag}-brand-kit.zip",
        *(f"TokenCurrent-{tag}-agent-{target}.{extension}" for target, extension in (
            ("linux-amd64", "tar.gz"), ("linux-arm64", "tar.gz"),
            ("windows-amd64", "zip"), ("windows-arm64", "zip"))),
        f"token-current-{tag}-relay-linux-amd64",
        f"token-current-{tag}-relay-linux-arm64",
    }
    manifest = directory / f"SHA256SUMS-{tag}.txt"
    actual = {p.name for p in directory.iterdir() if p.is_file() and p != manifest}
    if actual != expected:
        raise ValueError(f"Incomplete or incorrectly named release. Missing: {sorted(expected - actual)}; unexpected: {sorted(actual - expected)}")
    lines = []
    for name in sorted(expected):
        path = directory / name
        if path.is_symlink() or path.stat().st_size == 0:
            raise ValueError(f"Invalid release file: {name}")
        with path.open("rb") as stream:
            digest = hashlib.file_digest(stream, "sha256").hexdigest()
        lines.append(f"{digest}  {name}\n")
    manifest.write_text("".join(lines))
    return manifest


if __name__ == "__main__":
    if len(sys.argv) != 3:
        sys.exit("Usage: python3 Scripts/release_manifest.py RELEASE_DIRECTORY vX.Y.Z")
    print(prepare(Path(sys.argv[1]), sys.argv[2]))
