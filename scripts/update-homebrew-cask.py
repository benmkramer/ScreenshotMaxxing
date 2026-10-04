#!/usr/bin/env python3
"""Verify a public stable release and update only its cask in an existing tap."""

import argparse
import hashlib
import json
import plistlib
import re
import subprocess
import tempfile
from pathlib import Path

REPOSITORY = "benmkramer/ScreenshotMaxxing"
TOKEN = "screenshotmaxxing"
APP_NAME = "ScreenshotMaxxing.app"
BUNDLE_ID = "com.benmkramer.ScreenshotMaxxing"
TEAM_ID = "76UV94T5E2"
VERSION_PATTERN = r"\d+(?:\.\d+){0,2}"
# Homebrew expresses macOS dependencies by major release. The caveat preserves
# the bundle's exact minimum, which Launch Services also enforces on launch.
MACOS_RELEASES = {26: "tahoe"}


def run(*args, capture=False):
    return subprocess.run(args, check=True, text=True, capture_output=capture).stdout


def release_asset(release, tag):
    if release["tag_name"] != tag:
        raise ValueError("Release tag does not match the requested tag")
    if release["draft"] or release["prerelease"]:
        return None
    if not re.fullmatch(r"v" + VERSION_PATTERN, tag):
        raise ValueError("Stable release tags must contain a numeric marketing version")
    version = tag[1:]
    name = f"ScreenshotMaxxing-{version}.dmg"
    assets = [asset for asset in release["assets"] if asset["name"] == name]
    if len(assets) != 1:
        raise ValueError(f"Expected exactly one published {name} asset")
    asset = assets[0]
    expected_url = f"https://github.com/{REPOSITORY}/releases/download/{tag}/{name}"
    if asset["browser_download_url"] != expected_url:
        raise ValueError("Unexpected published asset URL")
    return version, asset


def verify_download(path, asset):
    if path.stat().st_size != asset["size"]:
        raise ValueError("Downloaded size differs from the published asset")
    checksum = hashlib.sha256(path.read_bytes()).hexdigest()
    # Older GitHub releases may not have a digest. Always hash the public bytes.
    if asset.get("digest") and asset["digest"] != f"sha256:{checksum}":
        raise ValueError("Downloaded SHA-256 differs from the published asset digest")
    return checksum


def bundle_requirements(info, version, architectures):
    if info["CFBundleIdentifier"] != BUNDLE_ID or info["CFBundlePackageType"] != "APPL":
        raise ValueError("Unexpected app bundle identity or type")
    if info["CFBundleShortVersionString"] != version:
        raise ValueError("Bundle marketing version differs from the release tag")
    build = str(info["CFBundleVersion"])
    if not re.fullmatch(r"\d+", build):
        raise ValueError("Expected a numeric bundle build number")
    minimum = info["LSMinimumSystemVersion"]
    if not re.fullmatch(r"\d+(?:\.\d+){0,2}", minimum):
        raise ValueError("Unexpected minimum macOS version")
    major = int(minimum.split(".")[0])
    if major not in MACOS_RELEASES:
        raise ValueError(f"Add the Homebrew macOS symbol for {minimum} before publishing")
    if not architectures or not architectures <= {"arm64", "x86_64"}:
        raise ValueError(f"Unsupported executable architectures: {architectures}")
    return build, minimum, MACOS_RELEASES[major]


def render_cask(version, checksum, url, build, minimum, macos, architectures):
    # The URL comes from GitHub's published asset metadata. Interpolation keeps
    # the cask idiomatic while retaining the exact versioned asset location.
    url = url.replace(f"/v{version}/", "/v#{version.csv.first}/")
    url = url.replace(f"ScreenshotMaxxing-{version}.dmg", "ScreenshotMaxxing-#{version.csv.first}.dmg")
    arch = ":arm64" if architectures == {"arm64"} else ":x86_64"
    if len(architectures) == 2:
        arch = "[:arm64, :x86_64]"
    return f'''cask "{TOKEN}" do
  version "{version},{build}"
  sha256 "{checksum}"

  url "{url}"
  name "ScreenshotMaxxing"
  desc "Menu bar screenshot and screen recording utility"
  homepage "https://github.com/{REPOSITORY}"

  livecheck do
    skip "Updated by the ScreenshotMaxxing release workflow with bundle build numbers"
  end

  depends_on arch: {arch}
  depends_on macos: :{macos}

  app "{APP_NAME}"

  caveats do
    "Requires macOS {minimum} or later. Captures and preferences are preserved on uninstall."
  end
end
'''


def version_key(version):
    marketing, build = version.split(",")
    parts = [int(part) for part in marketing.split(".")]
    return tuple(parts + [0] * (3 - len(parts)) + [int(build)])


def write_cask(path, content):
    if path.exists():
        previous = path.read_text()
        old_version = re.search(r'^  version "([\d.,]+)"$', previous, re.MULTILINE)
        new_version = re.search(r'^  version "([\d.,]+)"$', content, re.MULTILINE)
        if not old_version or not new_version:
            raise ValueError("Cannot compare the existing cask version")
        if version_key(old_version[1]) > version_key(new_version[1]):
            print("Skipping an older release; the tap already has a newer version/build.")
            return False
        if previous == content:
            print("Cask already matches the published release.")
            return False
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(content)
    print(f"Updated {path}")
    return True


def update(tag, tap_path):
    if not re.fullmatch(r"v[A-Za-z0-9][A-Za-z0-9.+-]*", tag):
        raise ValueError("Invalid release tag")
    release = json.loads(run("gh", "api", f"repos/{REPOSITORY}/releases/tags/{tag}", capture=True))
    selected = release_asset(release, tag)
    if selected is None:
        print("Skipping draft/prerelease: the tap follows stable releases only.")
        return
    version, asset = selected
    with tempfile.TemporaryDirectory(prefix="screenshotmaxxing-cask-") as directory:
        root = Path(directory)
        dmg = root / asset["name"]
        mount = root / "mount"
        mount.mkdir()
        # curl receives no Authorization header, so public accessibility is tested.
        run("curl", "--fail", "--location", "--retry", "3", "--silent", "--show-error",
            "--proto", "=https", "--proto-redir", "=https",
            asset["browser_download_url"], "--output", str(dmg))
        checksum = verify_download(dmg, asset)
        run("hdiutil", "verify", str(dmg))
        run("codesign", "--verify", "--strict", str(dmg))
        run("xcrun", "stapler", "validate", str(dmg))
        run("spctl", "--assess", "--verbose=2", "--type", "open",
            "--context", "context:primary-signature", str(dmg))
        run("hdiutil", "attach", str(dmg), "-readonly", "-nobrowse", "-noautoopen",
            "-mountpoint", str(mount))
        try:
            app = mount / APP_NAME
            info = plistlib.loads((app / "Contents/Info.plist").read_bytes())
            executable_name = info["CFBundleExecutable"]
            if Path(executable_name).name != executable_name:
                raise ValueError("Unexpected bundle executable path")
            executable = app / "Contents/MacOS" / executable_name
            architectures = set(run("lipo", "-archs", str(executable), capture=True).split())
            build, minimum, macos = bundle_requirements(info, version, architectures)
            run("codesign", "--verify", "--deep", "--strict", str(app))
            # codesign emits display details on stderr.
            signature = subprocess.run(
                ["codesign", "--display", "--verbose=4", str(app)],
                check=True, text=True, capture_output=True,
            ).stderr
            if f"TeamIdentifier={TEAM_ID}" not in signature or "Authority=Developer ID Application:" not in signature:
                raise ValueError("Expected the project's Developer ID Application signature")
            if "(runtime)" not in signature:
                raise ValueError("Expected hardened runtime signing")
            run("spctl", "--assess", "--verbose=2", "--type", "execute", str(app))
            content = render_cask(version, checksum, asset["browser_download_url"],
                                  build, minimum, macos, architectures)
        finally:
            run("hdiutil", "detach", str(mount), "-quiet")
    write_cask(tap_path / "Casks" / f"{TOKEN}.rb", content)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("tag", help="Published GitHub release tag, e.g. v2.0.9")
    parser.add_argument("tap_path", type=Path, help="Clean checkout of benmkramer/homebrew-tap")
    args = parser.parse_args()
    try:
        update(args.tag, args.tap_path)
    except (ValueError, KeyError, subprocess.CalledProcessError) as error:
        parser.exit(1, f"error: {error}\n")
