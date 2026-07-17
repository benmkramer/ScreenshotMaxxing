# Interactive Area/Window Toggle Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let Capture Area begin in drag-selection mode and use macOS's native Space-key toggle between area and window targeting.

**Architecture:** Keep the existing capture pipeline and change only the `screencapture` arguments for `CaptureMode.area`. Replace the selection-locking `-s` option with the `-Jselection` start style, leaving file creation, cancellation, persistence, editor presentation, and dedicated window capture unchanged.

**Tech Stack:** Swift, Swift Testing, AppKit application orchestration, macOS `/usr/sbin/screencapture`

## Global Constraints

- Capture Area must start in drag-selection mode.
- Space must toggle area to window targeting, and a second Space press must toggle back to area targeting.
- Capture Window must remain locked to window selection through `-w`.
- A capture launched through Capture Area must retain `.area` result mode, filename prefix, and History metadata even if Space is used to select a window.
- Do not add a custom selection overlay, event monitor, dependency, permission, storage path, or network behavior.
- Add an Unreleased changelog entry for the user-visible change.
- Use `scripts/test.sh` for deterministic unit tests and `scripts/lint.sh` for Swift formatting checks.

---

### Task 1: Enable the native interactive capture toggle

**Files:**
- Modify: `ScreenshotMaxxingTests/ScreenshotMaxxingTests.swift:103-216`
- Modify: `ScreenshotMaxxing/Capture/CaptureMode.swift:39-47`
- Modify: `CHANGELOG.md:7-9`

**Interfaces:**
- Consumes: `CaptureMode.screencaptureArguments(outputURL: URL) -> [String]`
- Produces: Area arguments `["-i", "-Jselection", "-x", outputURL.fileSystemPath]`; no new types or public interfaces.

- [ ] **Step 1: Change the tests to require an interactive selection start style**

In `areaCaptureRunsInteractiveSelectionAndReturnsFile`, replace the command expectation with:

```swift
#expect(recordedCommand.arguments == ["-i", "-Jselection", "-x", result.fileURL.fileSystemPath])
```

In `captureModesBuildExpectedScreencaptureArguments`, replace only the area expectation with:

```swift
#expect(
    CaptureMode.area.screencaptureArguments(outputURL: outputURL) == [
        "-i", "-Jselection", "-x", "/tmp/Application Support/screenshot.png",
    ])
```

Keep the `.window` and `.fullscreen` expectations unchanged. The first test protects the complete `CaptureController` command path and output placement; the second protects mode-specific argument construction.

- [ ] **Step 2: Run the deterministic unit suite and verify the new expectations fail**

Run:

```bash
scripts/test.sh
```

Expected: exit nonzero with failures in `areaCaptureRunsInteractiveSelectionAndReturnsFile` and `captureModesBuildExpectedScreencaptureArguments`, showing actual `-s` where the tests require `-Jselection`. No compile error should occur.

- [ ] **Step 3: Make the minimal production change**

In `CaptureMode.screencaptureArguments(outputURL:)`, change the area branch and leave the other branches intact:

```swift
func screencaptureArguments(outputURL: URL) -> [String] {
    switch self {
    case .area:
        ["-i", "-Jselection", "-x", outputURL.fileSystemPath]
    case .window:
        ["-i", "-w", "-x", outputURL.fileSystemPath]
    case .fullscreen:
        ["-x", outputURL.fileSystemPath]
    }
}
```

- [ ] **Step 4: Run the deterministic unit suite and verify it passes**

Run:

```bash
scripts/test.sh
```

Expected: exit zero with all tests in the `ScreenshotMaxxing-UnitTests` scheme passing. This includes the existing orchestration tests that cover metadata persistence and editor presentation after a successful capture.

- [ ] **Step 5: Document the user-visible behavior**

Under `## Unreleased` in `CHANGELOG.md`, add:

```markdown
- Added the native Space-key toggle between area and window targeting while selecting an area screenshot.
```

- [ ] **Step 6: Verify formatting and patch hygiene**

Run:

```bash
scripts/lint.sh
git diff --check
git diff -- ScreenshotMaxxing/Capture/CaptureMode.swift ScreenshotMaxxingTests/ScreenshotMaxxingTests.swift CHANGELOG.md
```

Expected: both checks exit zero. The diff must contain only the two `-s` to `-Jselection` test expectation changes, the matching production change, and the Unreleased changelog entry.

- [ ] **Step 7: Commit the implementation**

Run:

```bash
git add ScreenshotMaxxing/Capture/CaptureMode.swift ScreenshotMaxxingTests/ScreenshotMaxxingTests.swift CHANGELOG.md
git commit -m "feat: toggle window targeting from area capture"
```

Expected: one implementation commit containing the tested behavior and its changelog entry.
