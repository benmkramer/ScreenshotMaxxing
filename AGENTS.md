# Agent Instructions

Before changing behavior, read the docs that define the relevant contract:

- User-facing and privacy claims: `README.md`, `PRIVACY.md`
- Contributions and local development: `CONTRIBUTING.md`
- Security-sensitive behavior: `SECURITY.md`
- Support expectations and issue routing: `SUPPORT.md`
- Architecture and module boundaries: `docs/ARCHITECTURE.md`
- Release behavior: `docs/RELEASING.md`
- User-visible changes: `CHANGELOG.md`

Keep docs and behavior in sync. If a change affects capture, recording, permissions, local storage, deletion, privacy, redaction/blur semantics, release signing, updates, or contributor workflow, update the relevant docs in the same PR.

Do not add accounts, telemetry, hosted capture storage, cloud sync, or broader network behavior unless explicitly requested.

Do not strengthen redaction, privacy, or security claims beyond what the code actually guarantees.

For local-only ScreenshotMaxxing security reviews, do not over-rank issues that only produce visible local output the user can inspect and delete. Treat wrong-window or wrong-region capture outcomes as product correctness or privacy UX bugs unless there is a path to silent persistence, disclosure outside the Mac, or misleading deletion/redaction behavior.

When editing GitHub issue forms, validate the YAML.

For local verification, prefer the project scripts over long inline commands:

- Build and launch the Debug app with `scripts/build-and-run.sh`.
- Format Swift code with `scripts/format.sh`; check formatting with `scripts/lint.sh`.
- Run deterministic unit tests with `scripts/test.sh`.
- Run the full Xcode scheme, including UI tests, with `scripts/test.sh --all` only when UI automation is intended.
