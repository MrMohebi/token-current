"""Exercise installation and failure recovery without touching real apps or making network calls."""
import hashlib
import os
from pathlib import Path
import subprocess
import tempfile
import unittest


TOOL = '''#!/usr/bin/env python3
import hashlib, os, pathlib, plistlib, shutil, sys
name = pathlib.Path(sys.argv[0]).name
args = sys.argv[1:]
mode = os.environ.get("MOCK_FAILURE", "")
root = pathlib.Path(os.environ["MOCK_ROOT"])
with (root / "trace").open("a") as trace:
    trace.write(name + "\\n")
if name == "uname":
    print("Linux" if mode == "platform" else "Darwin")
elif name == "sw_vers":
    print("14.0")
elif name == "curl":
    output = pathlib.Path(args[args.index("-o") + 1])
    if output.name == "SHA256SUMS.txt":
        digest = "0" * 64 if mode == "checksum" else hashlib.sha256(b"synthetic archive").hexdigest()
        output.write_text(digest + "  TokenCurrent-macos-universal.zip\\n")
    else:
        output.write_bytes(b"synthetic archive")
elif name == "shasum":
    expected, filename = pathlib.Path(args[-1]).read_text().split()
    sys.exit(0 if hashlib.sha256(pathlib.Path(filename).read_bytes()).hexdigest() == expected else 1)
elif name == "ditto":
    if args[0] == "-x":
        bundle = pathlib.Path(args[-1]) / "TokenCurrent.app" / "Contents"
        (bundle / "MacOS").mkdir(parents=True)
        binary = bundle / "MacOS" / "TokenCurrent"
        binary.write_text("new app")
        binary.chmod(0o755)
        with (bundle / "Info.plist").open("wb") as file:
            plistlib.dump({"CFBundleIdentifier": "wrong.app" if mode == "identity" else "app.tokencurrent.mac"}, file)
    elif mode == "copy":
        sys.exit(1)
    else:
        shutil.copytree(args[0], args[1])
elif name == "plutil":
    with pathlib.Path(args[-1]).open("rb") as file:
        print(plistlib.load(file)["CFBundleIdentifier"])
elif name == "codesign":
    sys.exit(1 if mode == "signature" else 0)
elif name in ("open", "pkill"):
    sys.exit(0)
else:
    raise RuntimeError(name)
'''


class InstallerTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix="TokenCurrent-installer-test-")
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        self.install_dir = self.root / "Applications"
        binary_dir = self.root / "bin"
        binary_dir.mkdir()
        tool = binary_dir / "tool"
        tool.write_text(TOOL)
        tool.chmod(0o755)
        for name in ["uname", "sw_vers", "curl", "shasum", "ditto", "plutil", "codesign", "open", "pkill"]:
            (binary_dir / name).symlink_to(tool)
        self.environment = dict(os.environ, MOCK_ROOT=str(self.root),
                                TOKEN_CURRENT_INSTALL_DIR=str(self.install_dir),
                                PATH=str(binary_dir) + os.pathsep + os.environ["PATH"])
        self.script = Path(__file__).resolve().parents[2] / "Scripts" / "install.sh"

    def run_installer(self, failure=""):
        self.environment["MOCK_FAILURE"] = failure
        return subprocess.run(["bash", str(self.script)], env=self.environment, capture_output=True, text=True)

    def existing_app(self):
        destination = self.install_dir / "TokenCurrent.app"
        destination.mkdir(parents=True)
        marker = destination / "old-version"
        marker.write_text("keep me on failure")
        return marker

    def test_installs_verified_app_and_opens_it(self):
        result = self.run_installer()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertTrue((self.install_dir / "TokenCurrent.app/Contents/MacOS/TokenCurrent").is_file())
        self.assertIn("open", (self.root / "trace").read_text().splitlines())

    def test_update_replaces_only_app_and_preserves_other_files(self):
        old = self.existing_app()
        other = self.install_dir / "another-file"
        other.write_text("unrelated")
        result = self.run_installer()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertFalse(old.exists())
        self.assertEqual(other.read_text(), "unrelated")
        self.assertEqual(list(self.install_dir.glob(".TokenCurrent-*")), [])

    def test_bad_checksum_keeps_existing_app_and_never_stops_it(self):
        old = self.existing_app()
        result = self.run_installer("checksum")
        self.assertNotEqual(result.returncode, 0)
        self.assertTrue(old.exists())
        self.assertNotIn("pkill", (self.root / "trace").read_text().splitlines())

    def test_invalid_signature_or_identity_keeps_existing_app(self):
        old = self.existing_app()
        for mode in ["signature", "identity"]:
            with self.subTest(mode=mode):
                self.assertNotEqual(self.run_installer(mode).returncode, 0)
                self.assertTrue(old.exists())

    def test_staging_copy_failure_keeps_existing_app(self):
        old = self.existing_app()
        result = self.run_installer("copy")
        self.assertNotEqual(result.returncode, 0)
        self.assertTrue(old.exists())
        self.assertEqual(list(self.install_dir.glob(".TokenCurrent-install.*")), [])

    def test_unsupported_platform_never_downloads(self):
        result = self.run_installer("platform")
        self.assertNotEqual(result.returncode, 0)
        self.assertNotIn("curl", (self.root / "trace").read_text().splitlines())


if __name__ == "__main__":
    unittest.main()
