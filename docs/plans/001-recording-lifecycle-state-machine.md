# Recording Lifecycle State Machine Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use
> `superpowers:subagent-driven-development` (recommended) or
> `superpowers:executing-plans` to implement this plan task-by-task. Steps use
> checkbox (`- [ ]`) syntax for tracking.
>
> **Executor instructions:** Follow this plan task by task. Run every
> verification command and confirm the expected result before moving on. If a
> STOP condition occurs, stop and report it instead of improvising. When done,
> update this plan's row in `docs/plans/README.md` unless a reviewer says they own
> the index.
>
> **Drift check (run first):**
>
> ```sh
> git diff --stat 3d0c0ad -- \
>   ScreenshotMaxxing/Capture/RecordingController.swift \
>   ScreenshotMaxxingTests/ScreenshotMaxxingTests.swift \
>   docs/ARCHITECTURE.md \
>   CHANGELOG.md
> ```
>
> If any in-scope file changed, compare the live code with the excerpts below.
> Stop if recording ownership, cancellation, or completion semantics no longer
> match this plan.

**Goal:** A second recording request must fail without stealing, clearing, or
resuming the first recording's continuation, including while the first request
is still starting.

**Architecture:** Replace `RecordingController`'s independently mutable
`activeSession` and `continuation` fields with one private lifecycle enum. Every
operation receives a stable identity and owns exactly one checked continuation.
Async session creation, ScreenCaptureKit callbacks, fallback tasks, stop,
restart, and cancellation may transition state only when their operation and
session identities still match the current state.

**Tech Stack:** Swift 5 language mode, Swift concurrency, ScreenCaptureKit,
Swift Testing, AppKit, AVFoundation.

## Global Constraints

- The Xcode project uses `SWIFT_VERSION = 5.0`,
  `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`, and
  `MACOSX_DEPLOYMENT_TARGET = 26.2`; do not change these build settings.
- Add no package, framework, account, telemetry, hosted storage, cloud sync, or
  network behavior.
- Preserve recording formats, audio options, selection UI, recovery retry
  counts, and completion delays.
- Keep `README.md`, `PRIVACY.md`, permission claims, and recording-output
  behavior unchanged; this plan changes lifecycle ownership only.
- Use `scripts/format.sh`, `scripts/lint.sh`, and `scripts/test.sh unit`; do not
  substitute the full UI-test scheme.
- The Xcode project uses file-system-synchronized groups, so creating a Swift
  file never requires editing `ScreenshotMaxxing.xcodeproj/project.pbxproj`.

---

## Status

- **Priority:** P1
- **Effort:** M
- **Risk:** MED
- **Depends on:** none
- **Category:** bug
- **Planned at:** commit `3d0c0ad`, 2026-07-18

## Why this matters

`record(options:)` currently stores a new continuation before checking whether
another recording is active. A second request can therefore replace the first
continuation, throw `RecordingError.alreadyRecording`, clear the shared field,
and leave the original request permanently suspended. The same two-field model
also permits ambiguous ownership while session creation is suspended at an
`await`.

The corrected invariant is:

1. Only `.idle` may accept a new `record(options:)` request.
2. A rejected request resumes only its own local continuation.
3. Every accepted operation has a stable identity from `.starting` through
   completion or cancellation.
4. Every accepted continuation is resumed exactly once.
5. A session or callback arriving after cancellation/replacement is cleaned up
   and cannot mutate the current operation.

## Current state

- `ScreenshotMaxxing/Capture/RecordingController.swift` owns recording setup,
  stop/restart, ScreenCaptureKit delegate routing, completion recovery, and the
  caller continuation.
- `ScreenshotMaxxingTests/ScreenshotMaxxingTests.swift` contains the
  deterministic controller tests and `SpyRecordingSession`.
- `docs/ARCHITECTURE.md` describes `RecordingController` as the recording owner.
- `CHANGELOG.md` records user-visible fixes under `Unreleased`.

The unsafe ownership is visible at
`ScreenshotMaxxing/Capture/RecordingController.swift:39-40`:

```swift
private var activeSession: (any RecordingSessionControlling)?
private var continuation: CheckedContinuation<RecordingResult, Error>?
```

The new request overwrites the shared continuation before
`beginRecording(...)` checks the existing session
(`ScreenshotMaxxing/Capture/RecordingController.swift:66-76`):

```swift
try await withCheckedThrowingContinuation { continuation in
    Task { @MainActor in
        do {
            self.continuation = continuation
            try await self.beginRecording(options: options, baseDirectory: baseDirectory)
        } catch {
            self.continuation = nil
            continuation.resume(throwing: error)
        }
    }
}
```

The current guard runs too late
(`ScreenshotMaxxing/Capture/RecordingController.swift:140-147`):

```swift
guard activeSession == nil else {
    throw RecordingError.alreadyRecording
}
```

Completion reads whichever continuation happens to occupy the shared field
(`ScreenshotMaxxing/Capture/RecordingController.swift:376-391`):

```swift
let continuation = continuation
activeSession = nil
self.continuation = nil
continuation?.resume(returning: result)
```

Tests use a controllable session and polling helper. Match the style of
`recordingControllerStopRecoversCompletedFileAndReturnsResult()` at
`ScreenshotMaxxingTests/ScreenshotMaxxingTests.swift:618-670` and
`waitForCondition(...)` at lines 4140-4157. Do not introduce sleeps with
wall-clock-sized delays.

## Commands you will need

| Purpose | Command | Expected on success |
|---|---|---|
| Format changed Swift | `scripts/format.sh` | exit 0 |
| Check formatting | `scripts/lint.sh` | exit 0, no output |
| Deterministic tests | `scripts/test.sh unit` | exit 0, all tests pass |
| Patch hygiene | `git diff --check` | exit 0, no output |
| Scope check | `git status --short` | only in-scope files plus `docs/plans/README.md` |

## Scope

**In scope:**

- `ScreenshotMaxxing/Capture/RecordingController.swift`
- `ScreenshotMaxxingTests/ScreenshotMaxxingTests.swift`
- `docs/ARCHITECTURE.md`
- `CHANGELOG.md`
- `docs/plans/README.md` for status only

**Out of scope:**

- `ScreenshotMaxxing/AppOrchestration.swift`; the controller must remain safe
  even if callers issue competing requests.
- Capture-options UI disabling or new busy-state UI.
- Screenshot capture concurrency.
- Changes to recording formats, audio behavior, selection UI, retry counts, or
  completion delays.
- Splitting `RecordingController.swift` or the monolithic test file.
- Plans 002 and 003.

## Git Workflow

- Branch: `codex-recording-lifecycle-state-machine`
- Commit style: conventional commits, matching
  `669cc0e fix: delete edited captures for missing originals (#90)`.
- Make the task-level commits listed below. Do not push or open a PR unless the
  operator explicitly asks.
- Do not commit files under `docs/plans/` unless the operator explicitly asks.

## Target code shape

Use one lifecycle value as the source of truth:

```swift
@MainActor
private final class RecordingOperation {
    let id: UUID
    var completionFallbackTask: Task<Void, Never>?
    private var continuation: CheckedContinuation<RecordingResult, Error>?

    init(id: UUID, continuation: CheckedContinuation<RecordingResult, Error>) {
        self.id = id
        self.continuation = continuation
    }

    func resume(returning result: RecordingResult) {
        let continuation = continuation
        self.continuation = nil
        continuation?.resume(returning: result)
    }

    func resume(throwing error: Error) {
        let continuation = continuation
        self.continuation = nil
        continuation?.resume(throwing: error)
    }
}

@MainActor
private enum RecordingLifecycleState {
    case idle
    case starting(RecordingOperation)
    case recording(RecordingOperation, any RecordingSessionControlling)
    case stopping(RecordingOperation, any RecordingSessionControlling)
    case restarting(RecordingOperation, any RecordingSessionControlling)
    case cancelling(RecordingOperation, (any RecordingSessionControlling)?)
}
```

Do not retain separate controller-level `activeSession` and `continuation`
fields alongside this enum. That recreates representable invalid states.

Refactor `beginRecording(...)` into a function that returns a session without
installing or showing it:

```swift
private func makeRecordingSession(
    options: RecordingOptions,
    baseDirectory: URL?
) async throws -> any RecordingSessionControlling
```

After it returns, install the session only if state is still `.starting` for
the same `RecordingOperation`. If the operation was cancelled while awaiting,
close and stop the late session, delete its output if present, and never show
its chrome.

## Tasks

### Task 1: Reproduce and contain continuation theft

**Files:**

- Modify: `ScreenshotMaxxingTests/ScreenshotMaxxingTests.swift:618-670`
- Modify: `ScreenshotMaxxingTests/ScreenshotMaxxingTests.swift:922-965`
- Modify: `ScreenshotMaxxing/Capture/RecordingController.swift:66-84`

**Interfaces:**

- Consumes:
  `RecordingController.record(options:baseDirectory:) async throws -> RecordingResult`,
  `RecordingController.stopActiveRecording() async`, `SpyRecordingSession`,
  `waitForCondition(_:)`, and `makeTestVideo(at:durationSeconds:size:)`.
- Produces:
  `RecordingCompletionProbe` and
  `recordingControllerRejectsSecondStartWithoutLosingFirstCompletion()`.

- [ ] **Step 1: Add the completion probe and failing regression test**

Add this helper beside `SpyRecordingSession`:

```swift
@MainActor
private final class RecordingCompletionProbe {
    var result: Result<RecordingResult, Error>?
}
```

Add this test immediately after
`recordingControllerStopRecoversCompletedFileAndReturnsResult()`:

```swift
@MainActor
@Test func recordingControllerRejectsSecondStartWithoutLosingFirstCompletion() async throws {
    let fileManager = FileManager.default
    let baseDirectory = fileManager.temporaryDirectory
        .appendingPathComponent("ScreenshotMaxxingTests-\(UUID().uuidString)", isDirectory: true)
    let outputURL = baseDirectory.appendingPathComponent("recording.mp4")
    let options = RecordingOptions(mode: .area, microphoneEnabled: false, systemAudioEnabled: true)
    let session = SpyRecordingSession(
        options: options,
        outputURL: outputURL,
        dimensions: CGSize(width: 96, height: 64),
        thumbnailBaseDirectory: baseDirectory
    )
    let probe = RecordingCompletionProbe()
    defer {
        try? fileManager.removeItem(at: baseDirectory)
    }

    try fileManager.createDirectory(at: baseDirectory, withIntermediateDirectories: true)
    let controller = RecordingController(
        fileManager: fileManager,
        sessionFactory: { _, _ in session },
        recoveryRetryCount: 1,
        recoveryRetryDelayNanoseconds: 0,
        completionFallbackDelayNanoseconds: 0,
        sleep: { _ in }
    )
    let firstTask = Task { @MainActor in
        do {
            probe.result = .success(
                try await controller.record(options: options, baseDirectory: baseDirectory)
            )
        } catch {
            probe.result = .failure(error)
        }
    }
    defer {
        firstTask.cancel()
    }

    try await waitForCondition(session.showCount == 1)

    do {
        _ = try await controller.record(options: options, baseDirectory: baseDirectory)
        Issue.record("Expected a second recording request to be rejected")
    } catch {
        #expect(error as? RecordingError == .alreadyRecording)
    }

    try await makeTestVideo(
        at: outputURL,
        durationSeconds: 0.25,
        size: CGSize(width: 96, height: 64)
    )
    await controller.stopActiveRecording()
    try await waitForCondition(probe.result != nil)

    let firstResult = try #require(probe.result)
    #expect(try firstResult.get().fileURL == outputURL)
}
```

- [ ] **Step 2: Run the test suite and observe the regression**

Run: `scripts/test.sh unit`

Expected: exit nonzero; the new test reaches
`TestFixtureError.conditionTimedOut` because the second request replaced and
cleared the first request's continuation.

- [ ] **Step 3: Reject overlap before assigning shared state**

Replace the opening of `record(options:baseDirectory:)` with this temporary
containment guard:

```swift
func record(options: RecordingOptions, baseDirectory: URL? = nil) async throws -> RecordingResult {
    guard activeSession == nil, continuation == nil else {
        throw RecordingError.alreadyRecording
    }

    return try await withTaskCancellationHandler {
        try await withCheckedThrowingContinuation { continuation in
            Task { @MainActor in
                do {
                    self.continuation = continuation
                    try await self.beginRecording(options: options, baseDirectory: baseDirectory)
                } catch {
                    self.continuation = nil
                    continuation.resume(throwing: error)
                }
            }
        }
    } onCancel: {
        Task { @MainActor in
            await self.cancelActiveRecording()
        }
    }
}
```

This guard is deliberately replaced by the state machine in Task 3. It makes
Task 1 independently safe without changing stop/restart behavior.

- [ ] **Step 4: Format the containment fix**

Run: `scripts/format.sh`

Expected: exit 0.

- [ ] **Step 5: Verify the containment fix**

Run: `scripts/test.sh unit`

Expected: exit 0; the new overlap test and all existing unit tests pass.

- [ ] **Step 6: Commit Task 1**

```bash
git add \
  ScreenshotMaxxing/Capture/RecordingController.swift \
  ScreenshotMaxxingTests/ScreenshotMaxxingTests.swift
git commit -m "fix: reject overlapping recording requests"
```

Expected: commit succeeds and `git status --short` lists only pre-existing plan
artifacts.

### Task 2: Characterize overlap during asynchronous session creation

**Files:**

- Modify: `ScreenshotMaxxingTests/ScreenshotMaxxingTests.swift:618-726`
- Modify: `ScreenshotMaxxingTests/ScreenshotMaxxingTests.swift:922-965`

**Interfaces:**

- Consumes: Task 1's `RecordingCompletionProbe`, the injected
  `RecordingController.sessionFactory`, and existing video-fixture helpers.
- Produces: `RecordingSessionFactoryGate` and
  `recordingControllerRejectsSecondStartWhileFirstSessionIsBeingCreated()`.

- [ ] **Step 1: Add a deterministic asynchronous gate**

Add this helper beside `RecordingCompletionProbe`:

```swift
@MainActor
private final class RecordingSessionFactoryGate {
    private(set) var isWaiting = false
    private var continuation: CheckedContinuation<Void, Never>?

    func wait() async {
        isWaiting = true
        await withCheckedContinuation { continuation in
            self.continuation = continuation
        }
    }

    func open() {
        let continuation = continuation
        self.continuation = nil
        continuation?.resume()
    }
}
```

- [ ] **Step 2: Add the starting-phase characterization test**

```swift
@MainActor
@Test func recordingControllerRejectsSecondStartWhileFirstSessionIsBeingCreated() async throws {
    let fileManager = FileManager.default
    let baseDirectory = fileManager.temporaryDirectory
        .appendingPathComponent("ScreenshotMaxxingTests-\(UUID().uuidString)", isDirectory: true)
    let outputURL = baseDirectory.appendingPathComponent("recording.mp4")
    let options = RecordingOptions(mode: .window, microphoneEnabled: false)
    let session = SpyRecordingSession(
        options: options,
        outputURL: outputURL,
        dimensions: CGSize(width: 96, height: 64),
        thumbnailBaseDirectory: baseDirectory
    )
    let gate = RecordingSessionFactoryGate()
    let probe = RecordingCompletionProbe()
    defer {
        try? fileManager.removeItem(at: baseDirectory)
    }

    try fileManager.createDirectory(at: baseDirectory, withIntermediateDirectories: true)
    let controller = RecordingController(
        fileManager: fileManager,
        sessionFactory: { _, _ in
            await gate.wait()
            return session
        },
        recoveryRetryCount: 1,
        recoveryRetryDelayNanoseconds: 0,
        completionFallbackDelayNanoseconds: 0,
        sleep: { _ in }
    )
    let firstTask = Task { @MainActor in
        do {
            probe.result = .success(
                try await controller.record(options: options, baseDirectory: baseDirectory)
            )
        } catch {
            probe.result = .failure(error)
        }
    }
    defer {
        firstTask.cancel()
    }

    try await waitForCondition(gate.isWaiting)

    do {
        _ = try await controller.record(options: options, baseDirectory: baseDirectory)
        Issue.record("Expected a second recording request to be rejected during startup")
    } catch {
        #expect(error as? RecordingError == .alreadyRecording)
    }

    gate.open()
    try await waitForCondition(session.showCount == 1)
    try await makeTestVideo(
        at: outputURL,
        durationSeconds: 0.25,
        size: CGSize(width: 96, height: 64)
    )
    await controller.stopActiveRecording()
    try await waitForCondition(probe.result != nil)

    #expect(try #require(probe.result).get().fileURL == outputURL)
}
```

- [ ] **Step 3: Verify startup overlap is covered**

Run: `scripts/format.sh`

Expected: exit 0.

Run: `scripts/test.sh unit`

Expected: exit 0; both overlap tests pass without sleeps longer than the
existing one-millisecond polling interval.

- [ ] **Step 4: Commit Task 2**

```bash
git add ScreenshotMaxxingTests/ScreenshotMaxxingTests.swift
git commit -m "test: cover overlap during recording startup"
```

Expected: commit succeeds.

### Task 3: Replace split continuation/session ownership

**Files:**

- Modify: `ScreenshotMaxxing/Capture/RecordingController.swift:28-166`
- Modify: `ScreenshotMaxxing/Capture/RecordingController.swift:364-392`

**Interfaces:**

- Consumes: Task 2's two overlap regressions and the existing
  `RecordingSessionControlling` protocol.
- Produces: `RecordingOperation`, `RecordingLifecycleState`,
  `state`, `makeRecordingSession(options:baseDirectory:)`,
  `install(_:for:)`, and `cancelRecording(operationID:)`.

- [ ] **Step 1: Add the operation and lifecycle types**

Insert these types above `RecordingController`:

```swift
@MainActor
private final class RecordingOperation {
    let id: UUID
    private var continuation: CheckedContinuation<RecordingResult, Error>?

    init(id: UUID, continuation: CheckedContinuation<RecordingResult, Error>) {
        self.id = id
        self.continuation = continuation
    }

    func resume(returning result: RecordingResult) {
        let continuation = continuation
        self.continuation = nil
        continuation?.resume(returning: result)
    }

    func resume(throwing error: Error) {
        let continuation = continuation
        self.continuation = nil
        continuation?.resume(throwing: error)
    }
}

@MainActor
private enum RecordingLifecycleState {
    case idle
    case starting(RecordingOperation)
    case recording(RecordingOperation, any RecordingSessionControlling)
    case stopping(RecordingOperation, any RecordingSessionControlling)
    case restarting(RecordingOperation, any RecordingSessionControlling)
    case cancelling(RecordingOperation, (any RecordingSessionControlling)?)

    var operation: RecordingOperation? {
        switch self {
        case .idle:
            nil
        case .starting(let operation),
            .recording(let operation, _),
            .stopping(let operation, _),
            .restarting(let operation, _),
            .cancelling(let operation, _):
            operation
        }
    }

    var session: (any RecordingSessionControlling)? {
        switch self {
        case .idle, .starting:
            nil
        case .recording(_, let session),
            .stopping(_, let session),
            .restarting(_, let session):
            session
        case .cancelling(_, let session):
            session
        }
    }
}
```

- [ ] **Step 2: Replace the two controller fields**

Replace:

```swift
private var activeSession: (any RecordingSessionControlling)?
private var continuation: CheckedContinuation<RecordingResult, Error>?
```

with:

```swift
private var state: RecordingLifecycleState = .idle

private var activeSession: (any RecordingSessionControlling)? {
    state.session
}
```

The computed `activeSession` is a temporary compatibility bridge for the
existing stop/restart code. Task 4 removes it after every transition uses
`state`.

- [ ] **Step 3: Replace request acceptance and startup**

Replace `record(options:baseDirectory:)` and `beginRecording` with:

```swift
func record(options: RecordingOptions, baseDirectory: URL? = nil) async throws -> RecordingResult {
    let operationID = UUID()

    return try await withTaskCancellationHandler {
        try await withCheckedThrowingContinuation { continuation in
            guard case .idle = state else {
                continuation.resume(throwing: RecordingError.alreadyRecording)
                return
            }

            let operation = RecordingOperation(id: operationID, continuation: continuation)
            state = .starting(operation)

            if Task.isCancelled {
                state = .idle
                operation.resume(throwing: RecordingSelectionError.cancelled)
                return
            }

            Task { @MainActor in
                do {
                    let session = try await self.makeRecordingSession(
                        options: options,
                        baseDirectory: baseDirectory
                    )
                    await self.install(session, for: operation)
                } catch {
                    self.finish(operation, throwing: error)
                }
            }
        }
    } onCancel: {
        Task { @MainActor in
            await self.cancelRecording(operationID: operationID)
        }
    }
}

private func makeRecordingSession(
    options: RecordingOptions,
    baseDirectory: URL?
) async throws -> any RecordingSessionControlling {
    if let sessionFactory {
        return try await sessionFactory(options, baseDirectory)
    }

    if options.microphoneEnabled {
        try await requestMicrophoneAccessIfNeeded()
    }

    let shareableContent = try await SCShareableContent.current
    let target = try await recordingTarget(for: options.mode, in: shareableContent)
    return try await makeActiveSession(
        options: options,
        target: target,
        baseDirectory: baseDirectory
    )
}

private func install(
    _ session: any RecordingSessionControlling,
    for operation: RecordingOperation
) async {
    guard case .starting(let currentOperation) = state,
        currentOperation === operation
    else {
        session.closeChrome()
        try? await session.stopCapture()
        try? fileManager.removeItem(at: session.outputURL)
        return
    }

    state = .recording(operation, session)
    session.showChrome()
}
```

- [ ] **Step 4: Replace cancellation and terminal completion**

Replace `cancelActiveRecording`, `completeWithResult`, and
`completeWithError` with:

```swift
private func cancelRecording(operationID: UUID) async {
    guard let operation = state.operation, operation.id == operationID else {
        return
    }

    guard let session = state.session else {
        state = .idle
        operation.resume(throwing: RecordingSelectionError.cancelled)
        return
    }

    state = .cancelling(operation, session)
    session.closeChrome()
    try? await session.stopCapture()
    try? fileManager.removeItem(at: session.outputURL)

    guard case .cancelling(let currentOperation, _) = state,
        currentOperation === operation
    else {
        return
    }

    state = .idle
    operation.resume(throwing: RecordingSelectionError.cancelled)
}

private func finish(_ operation: RecordingOperation, returning result: RecordingResult) {
    guard state.operation === operation else {
        return
    }

    state.session?.completionFallbackTask?.cancel()
    state.session?.closeChrome()
    state = .idle
    operation.resume(returning: result)
}

private func finish(_ operation: RecordingOperation, throwing error: Error) {
    guard state.operation === operation else {
        return
    }

    state.session?.completionFallbackTask?.cancel()
    state.session?.closeChrome()
    state = .idle
    operation.resume(throwing: error)
}

private func completeWithResult(_ result: RecordingResult) {
    guard let operation = state.operation else {
        return
    }

    finish(operation, returning: result)
}

private func completeWithError(_ error: Error) {
    guard let operation = state.operation else {
        return
    }

    finish(operation, throwing: error)
}
```

In `restartActiveRecording`, replace
`self.activeSession = restartedSession` with:

```swift
guard let operation = state.operation else {
    restartedSession.closeChrome()
    try? await restartedSession.stopCapture()
    try? fileManager.removeItem(at: restartedSession.outputURL)
    return
}

state = .recording(operation, restartedSession)
```

- [ ] **Step 5: Format the ownership refactor**

Run: `scripts/format.sh`

Expected: exit 0.

- [ ] **Step 6: Verify single ownership**

Run: `scripts/test.sh unit`

Expected: exit 0; both overlap tests and the existing stop/restart tests pass.

Run:

```bash
rg -n 'private var continuation|private var activeSession:' \
  ScreenshotMaxxing/Capture/RecordingController.swift
```

Expected: exit 1 with no stored controller-level continuation or mutable
controller-level session field. The temporary computed `activeSession` may
match only if the search expression is broadened.

- [ ] **Step 7: Commit Task 3**

```bash
git add ScreenshotMaxxing/Capture/RecordingController.swift
git commit -m "refactor: make recording ownership explicit"
```

Expected: commit succeeds.

### Task 4: Encode stop, restart, and fallback phases in the state

**Files:**

- Modify: `ScreenshotMaxxing/Capture/RecordingController.swift:12-26`
- Modify: `ScreenshotMaxxing/Capture/RecordingController.swift:86-138`
- Modify: `ScreenshotMaxxing/Capture/RecordingController.swift:245-334`
- Modify: `ScreenshotMaxxing/Capture/RecordingController.swift:612-626`
- Modify: `ScreenshotMaxxingTests/ScreenshotMaxxingTests.swift:618-726`
- Modify: `ScreenshotMaxxingTests/ScreenshotMaxxingTests.swift:922-965`

**Interfaces:**

- Consumes: Task 3's `RecordingLifecycleState` and `RecordingOperation`.
- Produces: state-aware `stopActiveRecording`, `restartActiveRecording`,
  `scheduleRecordingCompletionFallback(for:session:)`, and
  `recoverCompletedRecordingIfPossible(for:session:)`.

- [ ] **Step 1: Add a repeated-stop regression**

Add this test beside the other recording-controller tests:

```swift
@MainActor
@Test func recordingControllerIgnoresRepeatedStopRequest() async throws {
    let fileManager = FileManager.default
    let baseDirectory = fileManager.temporaryDirectory
        .appendingPathComponent("ScreenshotMaxxingTests-\(UUID().uuidString)", isDirectory: true)
    let outputURL = baseDirectory.appendingPathComponent("recording.mp4")
    let options = RecordingOptions(mode: .area, microphoneEnabled: false)
    let session = SpyRecordingSession(options: options, outputURL: outputURL)
    defer {
        try? fileManager.removeItem(at: baseDirectory)
    }

    try fileManager.createDirectory(at: baseDirectory, withIntermediateDirectories: true)
    let controller = RecordingController(
        fileManager: fileManager,
        sessionFactory: { _, _ in session },
        recoveryRetryCount: 1,
        recoveryRetryDelayNanoseconds: 0,
        completionFallbackDelayNanoseconds: 0,
        sleep: { _ in }
    )
    let recordTask = Task {
        try await controller.record(options: options, baseDirectory: baseDirectory)
    }
    defer {
        recordTask.cancel()
    }
    try await waitForCondition(session.showCount == 1)
    try await makeTestVideo(
        at: outputURL,
        durationSeconds: 0.25,
        size: CGSize(width: 96, height: 64)
    )

    async let firstStop: Void = controller.stopActiveRecording()
    async let secondStop: Void = controller.stopActiveRecording()
    _ = await (firstStop, secondStop)
    _ = try await recordTask.value

    #expect(session.stopCount == 1)
}
```

- [ ] **Step 2: Verify the new phase test is meaningful**

Run: `scripts/test.sh unit`

Expected: exit 0 or a failure showing `stopCount == 2`. If it passes because
the old boolean already serializes stop, continue: the test is a
characterization that protects the state-machine migration.

- [ ] **Step 3: Move fallback ownership to the operation**

Add to `RecordingOperation`:

```swift
var completionFallbackTask: Task<Void, Never>?
```

Remove `didRequestStop`, `didRequestRestart`, and `completionFallbackTask` from
`RecordingSessionControlling`, `ActiveRecordingSession`, and
`SpyRecordingSession`.

Replace `stopActiveRecording()` with:

```swift
func stopActiveRecording() async {
    guard case .recording(let operation, let session) = state else {
        return
    }

    state = .stopping(operation, session)
    session.closeChrome()

    do {
        try await session.stopCapture()
        guard isCurrentStopping(operation: operation, session: session) else {
            return
        }
        scheduleRecordingCompletionFallback(for: operation, session: session)
    } catch {
        guard isCurrentStopping(operation: operation, session: session) else {
            return
        }
        if await recoverCompletedRecordingIfPossible(for: operation, session: session) {
            return
        }
        finish(operation, throwing: recordingFailureError(error, options: session.options))
    }
}

private func isCurrentStopping(
    operation: RecordingOperation,
    session: any RecordingSessionControlling
) -> Bool {
    guard case .stopping(let currentOperation, let currentSession) = state else {
        return false
    }
    return currentOperation === operation && currentSession === session
}
```

- [ ] **Step 4: Make restart an identity-checked transition**

Replace `restartActiveRecording()` with:

```swift
func restartActiveRecording() async {
    guard case .recording(let operation, let session) = state else {
        return
    }

    state = .restarting(operation, session)
    session.closeChrome()

    do {
        try await session.stopCapture()
        try? fileManager.removeItem(at: session.outputURL)
        let restartedSession = try await makeRestartedSession(from: session)

        guard case .restarting(let currentOperation, let currentSession) = state,
            currentOperation === operation,
            currentSession === session
        else {
            restartedSession.closeChrome()
            try? await restartedSession.stopCapture()
            try? fileManager.removeItem(at: restartedSession.outputURL)
            return
        }

        state = .recording(operation, restartedSession)
        restartedSession.showChrome()
    } catch {
        try? fileManager.removeItem(at: session.outputURL)
        guard case .restarting(let currentOperation, let currentSession) = state,
            currentOperation === operation,
            currentSession === session
        else {
            return
        }
        finish(operation, throwing: error)
    }
}
```

- [ ] **Step 5: Make recovery and fallback operation-specific**

Replace the fallback and recovery methods with:

```swift
private func scheduleRecordingCompletionFallback(
    for operation: RecordingOperation,
    session: any RecordingSessionControlling
) {
    operation.completionFallbackTask?.cancel()
    operation.completionFallbackTask = Task { @MainActor [weak self, weak session] in
        guard let self else {
            return
        }

        await sleep(completionFallbackDelayNanoseconds)

        guard let session,
            isCurrentStopping(operation: operation, session: session)
        else {
            return
        }

        if await recoverCompletedRecordingIfPossible(for: operation, session: session) {
            return
        }
        finish(operation, throwing: RecordingError.recordingDidNotFinish)
    }
}

private func recoverCompletedRecordingIfPossible(
    for operation: RecordingOperation,
    session: any RecordingSessionControlling
) async -> Bool {
    for _ in 0..<recoveryRetryCount {
        guard state.operation === operation, state.session === session else {
            return true
        }

        if fileManager.fileExists(atPath: session.outputURL.fileSystemPath),
            let result = try? makeRecordingResult(for: session)
        {
            finish(operation, returning: result)
            return true
        }

        await sleep(recoveryRetryDelayNanoseconds)
    }

    return false
}
```

Update every caller to pass its captured `operation` and `session`. In
`finish(_:returning:)` and `finish(_:throwing:)`, replace session fallback
cleanup with:

```swift
operation.completionFallbackTask?.cancel()
operation.completionFallbackTask = nil
```

- [ ] **Step 6: Route delegate callbacks by lifecycle phase**

Replace the opening guards in `completeRecording` and
`handleRecordingOutputFailure` with a helper that rejects restarting,
cancelling, and stale sessions:

```swift
private func operationAndSession(
    matching recordingOutput: SCRecordingOutput?
) -> (RecordingOperation, any RecordingSessionControlling)? {
    let operation: RecordingOperation
    let session: any RecordingSessionControlling

    switch state {
    case .recording(let currentOperation, let currentSession),
        .stopping(let currentOperation, let currentSession):
        operation = currentOperation
        session = currentSession
    case .idle, .starting, .restarting, .cancelling:
        return nil
    }

    if let recordingOutput {
        guard let activeSession = session as? ActiveRecordingSession,
            activeSession.recordingOutput === recordingOutput
        else {
            return nil
        }
    }

    return (operation, session)
}
```

Replace both callback methods with:

```swift
private func completeRecording(from recordingOutput: SCRecordingOutput? = nil) {
    guard let (operation, session) = operationAndSession(matching: recordingOutput) else {
        return
    }

    Task { @MainActor in
        if await recoverCompletedRecordingIfPossible(for: operation, session: session) {
            return
        }
        finish(operation, throwing: RecordingError.recordingDidNotFinish)
    }
}

private func handleRecordingOutputFailure(
    _ error: Error,
    from recordingOutput: SCRecordingOutput
) {
    guard let (operation, session) = operationAndSession(matching: recordingOutput) else {
        return
    }

    if case .recording = state {
        finish(operation, throwing: recordingFailureError(error, options: session.options))
        return
    }

    Task { @MainActor in
        if await recoverCompletedRecordingIfPossible(for: operation, session: session) {
            return
        }
        finish(operation, throwing: recordingFailureError(error, options: session.options))
    }
}
```

- [ ] **Step 7: Remove the compatibility bridge and update assertions**

Delete the computed `activeSession`. Replace the two obsolete assertions:

```swift
#expect(session.didRequestStop)
#expect(firstSession.didRequestRestart)
```

with behavior assertions already present in those tests:

```swift
#expect(session.stopCount == 1)
#expect(firstSession.stopCount == 1)
#expect(restartedSession.showCount == 1)
```

- [ ] **Step 8: Format the lifecycle phase refactor**

Run: `scripts/format.sh`

Expected: exit 0.

- [ ] **Step 9: Verify lifecycle phases**

Run: `scripts/test.sh unit`

Expected: exit 0; stop, restart, fallback, cancellation, and overlap tests pass.

Run:

```bash
rg -n 'didRequestStop|didRequestRestart|private var activeSession|private var continuation' \
  ScreenshotMaxxing/Capture/RecordingController.swift \
  ScreenshotMaxxingTests/ScreenshotMaxxingTests.swift
```

Expected: exit 1 with no matches.

- [ ] **Step 10: Commit Task 4**

```bash
git add \
  ScreenshotMaxxing/Capture/RecordingController.swift \
  ScreenshotMaxxingTests/ScreenshotMaxxingTests.swift
git commit -m "refactor: encode recording lifecycle phases"
```

Expected: commit succeeds.

### Task 5: Prove cancellation cleans up a late startup session

**Files:**

- Modify: `ScreenshotMaxxingTests/ScreenshotMaxxingTests.swift:618-760`
- Modify: `ScreenshotMaxxing/Capture/RecordingController.swift:66-180`

**Interfaces:**

- Consumes: Task 2's `RecordingSessionFactoryGate` and Task 3's
  operation-specific cancellation.
- Produces:
  `recordingControllerCancellationDuringSessionCreationCleansUpLateSession()`.

- [ ] **Step 1: Add the cancellation regression**

```swift
@MainActor
@Test func recordingControllerCancellationDuringSessionCreationCleansUpLateSession() async throws {
    let fileManager = FileManager.default
    let baseDirectory = fileManager.temporaryDirectory
        .appendingPathComponent("ScreenshotMaxxingTests-\(UUID().uuidString)", isDirectory: true)
    let outputURL = baseDirectory.appendingPathComponent("late-recording.mp4")
    let options = RecordingOptions(mode: .fullscreen, microphoneEnabled: false)
    let session = SpyRecordingSession(options: options, outputURL: outputURL)
    let gate = RecordingSessionFactoryGate()
    defer {
        try? fileManager.removeItem(at: baseDirectory)
    }

    try fileManager.createDirectory(at: baseDirectory, withIntermediateDirectories: true)
    try Data("late".utf8).write(to: outputURL)
    let controller = RecordingController(
        fileManager: fileManager,
        sessionFactory: { _, _ in
            await gate.wait()
            return session
        },
        sleep: { _ in }
    )
    let recordTask = Task {
        try await controller.record(options: options, baseDirectory: baseDirectory)
    }

    try await waitForCondition(gate.isWaiting)
    recordTask.cancel()

    do {
        _ = try await recordTask.value
        Issue.record("Expected cancellation during startup")
    } catch RecordingSelectionError.cancelled {
    } catch is CancellationError {
    }

    gate.open()
    try await waitForCondition(session.stopCount == 1)

    #expect(session.showCount == 0)
    #expect(session.closeCount >= 1)
    #expect(!fileManager.fileExists(atPath: outputURL.fileSystemPath))
}
```

- [ ] **Step 2: Run the regression**

Run: `scripts/test.sh unit`

Expected: exit 0. If it fails because the late session shows chrome or remains
on disk, continue to Step 3. If it fails for another reason twice, stop.

- [ ] **Step 3: Keep late-session disposal behind the identity guard**

Confirm `install(_:for:)` has this complete mismatch branch:

```swift
guard case .starting(let currentOperation) = state,
    currentOperation === operation
else {
    session.closeChrome()
    try? await session.stopCapture()
    try? fileManager.removeItem(at: session.outputURL)
    return
}
```

Confirm `cancelRecording(operationID:)` sets `.idle` and resumes only the
matching operation when state is `.starting`. Do not cancel a newer operation
whose `id` differs.

- [ ] **Step 4: Format the cancellation coverage**

Run: `scripts/format.sh`

Expected: exit 0.

- [ ] **Step 5: Verify cancellation**

Run: `scripts/test.sh unit`

Expected: exit 0; all four new lifecycle tests pass.

- [ ] **Step 6: Commit Task 5**

```bash
git add \
  ScreenshotMaxxing/Capture/RecordingController.swift \
  ScreenshotMaxxingTests/ScreenshotMaxxingTests.swift
git commit -m "test: cover recording cancellation during startup"
```

Expected: commit succeeds.

### Task 6: Document and verify the lifecycle contract

**Files:**

- Modify: `docs/ARCHITECTURE.md:31-42`
- Modify: `CHANGELOG.md:7-9`

**Interfaces:**

- Consumes: Tasks 1-5's final single-operation behavior.
- Produces: architecture and Unreleased changelog text matching that behavior.

- [ ] **Step 1: Update Recording Flow documentation**

Add this paragraph after the `RecordingController` bullet list:

```markdown
`RecordingController` owns one explicit recording lifecycle from startup
through recording, stop, restart, cancellation, and completion. Overlapping
start requests are rejected without replacing or completing the active
operation.
```

- [ ] **Step 2: Add the user-visible changelog entry**

Under `## Unreleased`, add:

```markdown
- Fixed overlapping recording requests so they no longer interrupt or leave the active recording waiting indefinitely.
```

- [ ] **Step 3: Verify docs and deterministic gates**

Run:

```bash
rg -n 'explicit recording lifecycle|Overlapping start requests|overlapping recording requests' \
  docs/ARCHITECTURE.md CHANGELOG.md
```

Expected: three matching lines across the two files.

Run: `scripts/lint.sh`

Expected: exit 0.

Run: `scripts/test.sh unit`

Expected: exit 0.

Run: `git diff --check`

Expected: exit 0 with no output.

- [ ] **Step 4: Commit Task 6**

```bash
git add docs/ARCHITECTURE.md CHANGELOG.md
git commit -m "docs: describe recording lifecycle ownership"
```

Expected: commit succeeds.

- [ ] **Step 5: Update the plan index**

Change Plan 001's status in `docs/plans/README.md` from `TODO` to `DONE` only after
all Done criteria below pass. Do not include the index in a source commit
unless the operator explicitly requested plan-file commits.

## Test plan

Add these deterministic Swift Testing cases:

1. `recordingControllerRejectsSecondStartWithoutLosingFirstCompletion`
2. `recordingControllerRejectsSecondStartWhileFirstSessionIsBeingCreated`
3. `recordingControllerIgnoresRepeatedStopRequest`
4. `recordingControllerCancellationDuringSessionCreationCleansUpLateSession`

Keep and re-run the existing successful stop and restart/cancellation tests.
No UI automation or real ScreenCaptureKit recording is required.

## Done criteria

- [ ] A second request in either `.starting` or `.recording` throws
      `RecordingError.alreadyRecording`.
- [ ] The rejected request cannot replace or clear the accepted operation.
- [ ] The accepted first request completes after stop.
- [ ] Cancellation during session creation cannot show late recording chrome
      or leave a late output file.
- [ ] `RecordingController` has one lifecycle-state field and no separate
      controller-level continuation/session ownership.
- [ ] `rg -n 'didRequestStop|didRequestRestart|private var activeSession|private var continuation' ScreenshotMaxxing/Capture/RecordingController.swift ScreenshotMaxxingTests/ScreenshotMaxxingTests.swift` exits 1.
- [ ] Architecture and changelog describe the corrected behavior.
- [ ] `scripts/lint.sh` exits 0.
- [ ] `scripts/test.sh unit` exits 0 with all four new lifecycle tests.
- [ ] `git diff --check` exits 0.
- [ ] `git status --short` lists no out-of-scope source files.
- [ ] The `docs/plans/README.md` row is updated.

## STOP conditions

Stop and report if:

- The live controller already rejects a second request before assigning shared
  ownership.
- Swift's checked continuation or existential restrictions make the target
  enum impossible without changing public controller APIs.
- Correct cleanup requires changing ScreenCaptureKit output format, recording
  selection behavior, or user-facing controls.
- A late session cannot be stopped safely using
  `RecordingSessionControlling.stopCapture()`.
- Any new deterministic test requires real Screen Recording or Microphone
  permission.
- An in-scope test fails twice for reasons unrelated to lifecycle ownership.

## Maintenance notes

- Any future pause/resume feature must add explicit states rather than new
  independent booleans.
- Reviewers should trace every `await` and callback to an operation-identity
  check.
- Keep fallback timing and output-recovery behavior unchanged; this plan is
  about ownership, not tuning.
- UI busy-state improvements can follow later, but the controller must remain
  correct without them.
