import copy
import hashlib
import importlib.util
import json
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

spec = importlib.util.spec_from_file_location(
    "update_homebrew_cask", Path(__file__).parents[1] / "update-homebrew-cask.py"
)
cask = importlib.util.module_from_spec(spec)
spec.loader.exec_module(cask)


class HomebrewReleaseTests(unittest.TestCase):
    def setUp(self):
        self.asset = {
            "name": "ScreenshotMaxxing-2.0.9.dmg",
            "browser_download_url": "https://github.com/benmkramer/ScreenshotMaxxing/releases/download/v2.0.9/ScreenshotMaxxing-2.0.9.dmg",
            "size": 3,
            "digest": "sha256:" + hashlib.sha256(b"dmg").hexdigest(),
        }
        self.release = {
            "tag_name": "v2.0.9", "draft": False, "prerelease": False,
            "assets": [self.asset],
        }
        self.info = {
            "CFBundleIdentifier": cask.BUNDLE_ID, "CFBundlePackageType": "APPL",
            "CFBundleShortVersionString": "2.0.9", "CFBundleVersion": "14",
            "LSMinimumSystemVersion": "26.2",
        }

    def content(self, version="2.0.9", build="14"):
        return cask.render_cask(version, "a" * 64, self.asset["browser_download_url"],
                                build, "26.2", "tahoe", {"arm64", "x86_64"})

    def test_selects_the_exact_public_stable_asset(self):
        self.assertEqual(cask.release_asset(self.release, "v2.0.9"), ("2.0.9", self.asset))

    def test_draft_and_prerelease_skip_without_downloading_or_writing(self):
        for field in ("draft", "prerelease"):
            release = copy.deepcopy(self.release)
            release[field] = True
            with self.subTest(field=field), tempfile.TemporaryDirectory() as directory:
                with patch.object(cask, "run", return_value=json.dumps(release)) as command:
                    cask.update("v2.0.9", Path(directory))
                    self.assertEqual(command.call_count, 1)
                    self.assertEqual(list(Path(directory).iterdir()), [])

    def test_invalid_stable_tag_and_mismatched_release_rejected(self):
        with self.assertRaises(ValueError):
            cask.release_asset(self.release, "v2.0.8")
        self.release["tag_name"] = "v2.1.0-beta.1"
        with self.assertRaises(ValueError):
            cask.release_asset(self.release, "v2.1.0-beta.1")
        self.release["prerelease"] = True
        self.assertIsNone(cask.release_asset(self.release, "v2.1.0-beta.1"))

    def test_missing_duplicate_and_unexpected_asset_url_rejected(self):
        for assets in ([], [self.asset, self.asset], [{**self.asset, "browser_download_url": "https://example.org/app.dmg"}]):
            with self.subTest(assets=assets), self.assertRaises(ValueError):
                cask.release_asset({**self.release, "assets": assets}, "v2.0.9")

    def test_downloaded_bytes_must_match_published_size_and_digest(self):
        with tempfile.TemporaryDirectory() as directory:
            dmg = Path(directory) / "app.dmg"
            dmg.write_bytes(b"dmg")
            checksum = cask.verify_download(dmg, self.asset)
            self.assertEqual("sha256:" + checksum, self.asset["digest"])
            self.assertEqual(cask.verify_download(dmg, {**self.asset, "digest": None}), checksum)
            for asset in ({**self.asset, "size": 4}, {**self.asset, "digest": "sha256:" + "0" * 64}):
                with self.subTest(asset=asset), self.assertRaises(ValueError):
                    cask.verify_download(dmg, asset)

    def test_bundle_identity_version_and_requirements(self):
        self.assertEqual(cask.bundle_requirements(self.info, "2.0.9", {"arm64", "x86_64"}),
                         ("14", "26.2", "tahoe"))
        for key, value in (("CFBundleIdentifier", "unofficial.app"),
                           ("CFBundleShortVersionString", "2.0.8"),
                           ("CFBundleVersion", "beta"), ("LSMinimumSystemVersion", "99.0")):
            with self.subTest(key=key), self.assertRaises(ValueError):
                cask.bundle_requirements({**self.info, key: value}, "2.0.9", {"arm64"})
        for architectures in (set(), {"i386"}):
            with self.subTest(architectures=architectures), self.assertRaises(ValueError):
                cask.bundle_requirements(self.info, "2.0.9", architectures)

    def test_idempotency_build_only_updates_and_no_downgrades(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "Casks/screenshotmaxxing.rb"
            self.assertTrue(cask.write_cask(path, self.content()))
            self.assertFalse(cask.write_cask(path, self.content()))
            self.assertTrue(cask.write_cask(path, self.content(build="15")))
            self.assertFalse(cask.write_cask(path, self.content()))
            self.assertFalse(cask.write_cask(path, self.content(version="2.0.8", build="99")))
            self.assertIn('version "2.0.9,15"', path.read_text())

    def test_failed_gatekeeper_validation_does_not_write_cask(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory)
            with patch.object(cask, "run", side_effect=[json.dumps(self.release), None, None,
                                                       None, None, ValueError("Gatekeeper rejected")]):
                with patch.object(cask, "verify_download", return_value="a" * 64):
                    with self.assertRaisesRegex(ValueError, "Gatekeeper"):
                        cask.update("v2.0.9", path)
            self.assertFalse((path / "Casks/screenshotmaxxing.rb").exists())


if __name__ == "__main__":
    unittest.main()
