# Implementation Plans

Refined with the Superpowers `writing-plans` rubric and the improve-plan
handoff standard on 2026-07-18. Baseline reviewed: `3d0c0ad`.

Execute in the order below unless dependency notes say otherwise. Every
executor must read its complete plan before starting, honor its STOP
conditions, use the required Superpowers execution skill, and update the
status row only after all Done criteria pass.

## Execution Order and Status

| Plan | Title | Priority | Effort | Depends on | Status |
|---|---|---:|---:|---|---|
| [001](001-recording-lifecycle-state-machine.md) | Recording lifecycle state machine | P1 | M | — | TODO |
| [002](002-unify-capture-deletion-lifecycle.md) | Unified capture deletion lifecycle | P1 | M | — | TODO |
| [003](003-file-backed-video-clipboard.md) | File-backed video clipboard | P1 | M | 002 | TODO |

Status values:

- `TODO`
- `IN PROGRESS`
- `DONE`
- `BLOCKED: <one-line reason>`
- `REJECTED: <one-line rationale>`

## Additional Plans and Specifications

- [Interactive area/window toggle](2026-07-16-interactive-space-window-toggle.md): implementation plan with its [design specification](../specs/2026-07-16-interactive-space-window-toggle-design.md).

## Dependency Notes

- Plans 001 and 002 are independent. They may be implemented in either order
  or on separate branches.
- Plan 003 requires Plan 002 because both modify
  `VideoEditorView.copyEditedVideoAndDeleteCapture()`. Plan 003 must preserve
  the `CaptureLifecycleService.deleteCaptures(_:from:)` call introduced by
  Plan 002.
- Keep each plan in its own branch and PR unless the operator explicitly
  chooses a combined implementation.

## Shared Execution Rules

- Invoke `superpowers:subagent-driven-development` for fresh-agent,
  task-by-task execution, or `superpowers:executing-plans` for inline batch
  execution with review checkpoints.
- Run each plan's drift check before editing source.
- Do not add accounts, telemetry, hosted capture storage, cloud sync, or
  broader network behavior.
- Keep behavior, architecture, privacy, and changelog documentation
  synchronized.
- Use the repository scripts for final deterministic verification:

```bash
scripts/lint.sh
scripts/test.sh unit
git diff --check
```

- Do not push, open a PR, or commit plan artifacts unless the operator
  explicitly asks.

## Expected Outcome

- Plan 001 makes every recording operation single-owner and identity-checked
  across startup, stop, restart, cancellation, callbacks, and completion.
- Plan 002 gives History and both editors one tested contract for related-file
  and linked-edit deletion.
- Plan 003 avoids eager video-sized clipboard allocations and gives temporary
  exports an explicit, non-dangling ownership lifetime.

## Findings Considered and Rejected

None in this refinement pass; the selected plans remain high-confidence and
in scope.
