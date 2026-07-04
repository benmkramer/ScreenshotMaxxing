# Changelog

Notable user-facing changes will be documented here.

This project uses GitHub Releases for official downloadable DMGs. The changelog gives a source-controlled summary of product, privacy, permission, and release-channel changes.

## Unreleased

## 2.0.7 - 2026-07-04

- Fixed History deletion so deleting a capture whose original file is already missing also removes linked edited captures and trashes related local files that still exist.
- Fixed screenshot and video editor windows to promote the menu bar app before bringing captures or recordings to the front.
- Hardened the Release DMG workflow to mount the notarized DMG and verify the contained app signature and bundle versions before upload or publication.

## 2.0.6 - 2026-06-13

- Improved the project website download section with clearer latest-release metadata, GitHub Release links, and official-build signing/notarization context.
- Added compact History filters for capture type and date ranges that compose with search.
- Remember the last selected Capture Options pane so the panel reopens on Screenshot or Record.
- Clarified screenshot and video editor copy/save toolbar actions, including a visually distinct `Copy & Trash` action for copying to the clipboard before moving local capture files to Trash and removing History metadata.
- Added explicit History actions for missing local capture files, including metadata-only removal, storage-folder reveal, and copying the last known path.
- Changed screenshot blur annotations to render as pixelated mosaic blocks sampled from the underlying image colors.

## 2.0.5

- Open sourced the repository with MIT licensing guidance and added open-source readiness docs: privacy, contributing, security, support, architecture, changelog, agent instructions, and issue templates.
- Added a static project website with GitHub Pages deployment.
- Added rectangle and text annotation tools to the screenshot editor.
- Added a global keyboard shortcut for opening capture history.
- Fixed duplicate screenshot and video editor windows when reopening the same capture.
- Fixed capture deletion to move local files to Trash.
- Hardened local-secret ignores and enabled Xcode CI on pull requests.
- Documented local storage, Screen Recording permission, optional microphone audio, optional system audio, and blur/redaction limitations.

## 2.0.4

- Current public release version in the Xcode project.
- Official builds are distributed as signed and notarized Developer ID DMGs through GitHub Releases.

Earlier changes were tracked through the repository history and GitHub Releases.
