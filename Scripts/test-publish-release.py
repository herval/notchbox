#!/usr/bin/env python3
"""Exercise publishing boundaries in disposable Git repos with a fake GitHub CLI."""
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

SOURCE = Path(__file__).resolve().parent.parent


class PublisherTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.repo = self.root / "repo"
        self.repo.mkdir()
        self.bare = self.root / "origin.git"
        self.bin = self.root / "bin"
        self.bin.mkdir()
        self.log = self.root / "events"
        self.state = self.root / "state"
        self.env = dict(os.environ, PATH=f"{self.bin}:{os.environ['PATH']}",
                        EVENT_LOG=str(self.log), RELEASE_STATE=str(self.state),
                        GIT_CONFIG_GLOBAL="/dev/null", GIT_CONFIG_NOSYSTEM="1")
        self.run_git("init", "--bare", str(self.bare), cwd=self.root)
        self.run_git("init", "-b", "main")
        self.run_git("config", "user.name", "Release test")
        self.run_git("config", "user.email", "release-test@example.invalid")
        self.run_git("remote", "add", "origin", "https://github.com/herval/notchbox.git")
        self.run_git("config", f"url.{self.bare}.insteadOf", "https://github.com/herval/notchbox.git")
        (self.repo / "Scripts").mkdir()
        (self.repo / "Resources").mkdir()
        shutil.copy2(SOURCE / "Scripts/publish-release.sh", self.repo / "Scripts")
        shutil.copy2(SOURCE / "Resources/Info.plist", self.repo / "Resources")
        for name in ("release-secrets.sh", "package-release.sh", "check-release.sh"):
            self.executable(self.repo / "Scripts" / name, """#!/bin/bash
set -eu
stage="$(basename "$0")"
echo "$stage $*" >> "$EVENT_LOG"
[[ "${FAIL_STAGE:-}" != "$stage" ]] || exit 1
if [[ "$stage" == package-release.sh ]]; then
  mkdir -p build/release
  touch build/release/notchbox_0.1.5_universal.zip build/release/notchbox_0.1.5_universal.zip.sha256
fi
""")
        self.executable(self.bin / "swift", '#!/bin/bash\necho "unit tests" >> "$EVENT_LOG"\n')
        self.executable(self.bin / "gh", """#!/usr/bin/env python3
import json, os, pathlib, sys
args = sys.argv[1:]
if args[:2] == ['secret', 'list']:
    print('HOMEBREW_TAP_DEPLOY_KEY')
    sys.exit(0)
state = pathlib.Path(os.environ['RELEASE_STATE'])
operation = args[1]
with open(os.environ['EVENT_LOG'], 'a') as log:
    log.write('gh ' + ' '.join(args) + '\\n')
if operation == 'view':
    if not state.exists(): sys.exit(1)
    value = state.read_text()
    if os.environ.get('PUBLISHED_DURING_BUILD') and '--json' in args and value == 'draft':
        events = pathlib.Path(os.environ['EVENT_LOG']).read_text()
        if 'package-release.sh' in events: value = 'published'
    if '--json' in args:
        print('true' if value == 'draft' else 'false') if 'isDraft' in args else print('https://example.invalid/release')
elif operation == 'create': state.write_text('draft')
elif operation == 'upload':
    assert state.read_text() == 'draft'
    assert '--clobber' in args
    assert pathlib.Path(args[3]).is_file() and pathlib.Path(args[4]).is_file()
elif operation == 'edit': state.write_text('published')
else: sys.exit(1)
""")
        (self.repo / ".gitignore").write_text("build/\n")
        self.run_git("add", ".")
        self.run_git("commit", "-m", "Release fixture")

    def executable(self, path, content):
        path.write_text(content)
        path.chmod(0o755)

    def run_git(self, *args, cwd=None):
        return subprocess.run(["git", *args], cwd=cwd or self.repo, env=self.env,
                              check=True, capture_output=True, text=True).stdout.strip()

    def publish(self, *args, **env):
        return subprocess.run(["Scripts/publish-release.sh", *(args or ("v0.1.5",))],
                              cwd=self.repo, env=dict(self.env, **env), capture_output=True, text=True)

    def events(self):
        return self.log.read_text() if self.log.exists() else ""

    def assert_not_published(self, result):
        self.assertNotEqual(result.returncode, 0)
        self.assertNotIn("gh release upload", self.events())
        self.assertNotIn("gh release edit", self.events())

    def test_version_and_dirty_inputs_stop_before_building(self):
        self.assert_not_published(self.publish("v9.9.9"))
        (self.repo / "Scripts/extra.sh").write_text("untracked build input")
        self.assert_not_published(self.publish())
        self.assertEqual(self.events(), "")

    def test_preflight_build_and_validation_failures_never_push_a_tag(self):
        for stage in ("release-secrets.sh", "package-release.sh", "check-release.sh"):
            with self.subTest(stage=stage):
                self.assert_not_published(self.publish(FAIL_STAGE=stage))
                self.assertEqual(self.run_git("--git-dir", str(self.bare), "tag"), "")

    def test_published_release_is_immutable(self):
        self.state.write_text("published")
        self.assert_not_published(self.publish())
        self.assertNotIn("package-release.sh", self.events())

    def test_signing_identity_selection_requires_a_unique_keychain_identity(self):
        self.executable(self.bin / "security", '#!/bin/bash\nprintf "%s\\n" "$TEST_IDENTITIES"\n')
        first = "Developer ID Application: First (AAAAAAAAAA)"
        second = "Developer ID Application: Second (BBBBBBBBBB)"
        for names, selected, expected in (([], "", None), ([first], "", first),
                                          ([first, second], "", None),
                                          ([first, second], second, second), ([first], second, None)):
            with self.subTest(names=names, selected=selected):
                values = "\n".join(f'  {index}) FAKEHASH "{name}"' for index, name in enumerate(names))
                result = subprocess.run([str(SOURCE / "Scripts/signing-identity.sh")],
                                        env=dict(self.env, TEST_IDENTITIES=values, APPLE_SIGNING_IDENTITY=selected),
                                        capture_output=True, text=True)
                self.assertEqual(result.returncode == 0, expected is not None)
                if expected: self.assertEqual(result.stdout.strip(), expected)

    def test_setup_uses_keychain_and_requires_private_local_entry_when_missing(self):
        shutil.copy2(SOURCE / "Scripts/release-secrets.sh", self.repo / "Scripts")
        shutil.copy2(SOURCE / "Scripts/signing-identity.sh", self.repo / "Scripts")
        self.executable(self.bin / "security", '#!/bin/bash\nprintf \'  1) FAKEHASH "Developer ID Application: First (AAAAAAAAAA)"\\n\'\n')
        self.executable(self.bin / "xcrun", '#!/bin/bash\necho "xcrun $*" >> "$EVENT_LOG"\nexit "${NOTARY_RESULT:-0}"\n')
        for status in ("0", "1"):
            result = subprocess.run(["Scripts/release-secrets.sh"], cwd=self.repo,
                                    env=dict(self.env, NOTARY_RESULT=status, APPLE_SIGNING_IDENTITY=""),
                                    stdin=subprocess.DEVNULL, capture_output=True, text=True)
            self.assertEqual(result.returncode == 0, status == "0", result.stderr)
            self.assertNotIn(".p12", result.stdout + result.stderr)
            if status == "1": self.assertIn("in a terminal", result.stderr)
        self.assertIn("notarytool history --keychain-profile", self.events())
        self.assertNotIn("--password", self.events())

    def test_publication_during_build_is_not_overwritten(self):
        self.state.write_text("draft")
        self.assert_not_published(self.publish(PUBLISHED_DURING_BUILD="1"))

    def test_tag_at_another_commit_is_rejected(self):
        self.run_git("tag", "v0.1.5")
        (self.repo / "Resources/note").write_text("new commit")
        self.run_git("add", ".")
        self.run_git("commit", "-m", "Another commit")
        self.assert_not_published(self.publish())
        self.assertEqual(self.events(), "")

    def test_validated_release_publishes_exact_artifacts(self):
        (self.repo / "video").mkdir()
        (self.repo / "video/unrelated").write_text("not a build input")
        result = self.publish()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.state.read_text(), "published")
        self.assertEqual(self.run_git("--git-dir", str(self.bare), "rev-parse", "v0.1.5"), self.run_git("rev-parse", "HEAD"))
        self.assertIn("check-release.sh v0.1.5 build/release --notarized", self.events())
        self.assertLess(self.events().index("check-release.sh"), self.events().index("gh release create"))


if __name__ == "__main__":
    unittest.main()
