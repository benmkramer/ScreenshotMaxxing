# Changelog

Notable user-facing changes will be documented here.

This project uses GitHub Releases for official downloadable DMGs. The changelog gives a source-controlled summary of product, privacy, permission, and release-channel changes.

## Unreleased

- Added compact History filters for capture type and date ranges that compose with search.
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
