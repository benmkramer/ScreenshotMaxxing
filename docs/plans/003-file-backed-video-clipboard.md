# File-Backed Video Clipboard Implementation Plan

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
>   ScreenshotMaxxing/Editor/VideoPasteboardDataProvider.swift \
>   ScreenshotMaxxing/Editor/EditorClipboard.swift \
>   ScreenshotMaxxing/Video/VideoEditorView.swift \
>   ScreenshotMaxxingTests/ScreenshotMaxxingTests.swift \
>   PRIVACY.md \
>   docs/ARCHITECTURE.md \
>   CHANGELOG.md
> ```
>
> If any in-scope file changed, compare the live clipboard and temporary-file
> paths with the excerpts below. Stop if video copy is already file-backed, if
> clipboard temporary-file ownership has changed, or if Plan 002's lifecycle
> API differs from this plan's dependency assumptions.

**Goal:** Stop loading an entire exported video into application memory merely
to copy it. Publish a file-backed pasteboard item that supplies MPEG-4 bytes
lazily and exposes a file URL only when that file has an independent persistent
lifetime.

**Architecture:** Add an `NSPasteboardItemDataProvider` that owns the source
file's clipboard lifetime. `EditorClipboard` publishes lazy MPEG-4 and movie
representations. Persistent exports also advertise a file URL. Temporary Copy
& Trash exports do not advertise a URL that could dangle; they transfer cleanup
ownership to the provider after a successful pasteboard write.

**Tech Stack:** Swift 5 language mode, AppKit, UniformTypeIdentifiers,
Foundation file APIs, Swift Testing.

## Global Constraints

- Implement `docs/plans/002-unify-capture-deletion-lifecycle.md` first. Preserve its
  `CaptureLifecycleService` call in video Copy & Trash.
- The Xcode project uses `SWIFT_VERSION = 5.0`,
  `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`, and
  `MACOSX_DEPLOYMENT_TARGET = 26.2`; do not change these build settings.
- Add no package, framework, account, telemetry, hosted storage, cloud sync, or
  network behavior.
- Keep PNG and string clipboard APIs unchanged.
- Keep video codec, export preset, render quality, filename conventions, and
  copy-before-delete ordering unchanged.
- A clipboard failure must leave the capture and History metadata intact.
- A persistent export must never be removed by the clipboard provider.
- A clipboard-temporary export must not advertise a raw file URL that can
  become dangling after provider cleanup.
- Update `PRIVACY.md`, `docs/ARCHITECTURE.md`, and `CHANGELOG.md` in the same
  implementation.
- Use `scripts/format.sh`, `scripts/lint.sh`, and `scripts/test.sh unit`; manual
  destination compatibility remains a required release-readiness check.
- The Xcode project uses file-system-synchronized groups, so creating
  `VideoPasteboardDataProvider.swift` never requires editing
  `ScreenshotMaxxing.xcodeproj/project.pbxproj`.

---

## Status

- **Priority:** P1
- **Effort:** M
- **Risk:** MED
- **Depends on:** `docs/plans/002-unify-capture-deletion-lifecycle.md`
- **Category:** perf
- **Planned at:** commit `3d0c0ad`, 2026-07-18

## Objective

Stop loading an entire exported video into application memory merely to copy
it. Publish a file-backed pasteboard item that supplies MPEG-4 bytes lazily
only when a destination explicitly requests them.

The implementation must preserve the existing user contract:

- **Copy** exports the edited video and leaves the capture in history.
- **Copy & Trash** copies the edited video, then applies the unified deletion behavior from Plan 002.
- A temporary export used by **Copy & Trash** must remain available for as long as the pasteboard may request it.
- No clipboard action uploads media or introduces network behavior.

## Commands You Will Need

| Purpose | Command | Expected on success |
|---|---|---|
| Format changed Swift | `scripts/format.sh` | exit 0 |
| Check formatting | `scripts/lint.sh` | exit 0, no output |
| Deterministic tests | `scripts/test.sh unit` | exit 0, all tests pass |
| Find eager video reads | `rg -n -e copyMP4Data -e 'Data\\(contentsOf:.*fileURL' -e 'Data\\(contentsOf:.*temporaryFileURL' ScreenshotMaxxing ScreenshotMaxxingTests` | exit 1 after migration |
| Patch hygiene | `git diff --check` | exit 0, no output |
| Scope check | `git status --short` | only in-scope files plus plan artifacts |

## Why This Is High Impact

`VideoEditorView` currently reads the complete exported MP4 into a `Data` value on the main actor before placing it on the pasteboard:

```swift
let videoData = try Data(contentsOf: exportResult.fileURL)
EditorClipboard.copyMP4Data(videoData)
```

The same pattern appears in both video copy paths. A long or high-resolution recording can therefore cause a transient memory spike approximately equal to the exported file size, in addition to the memory already used by AVFoundation and the editor.

The **Copy & Trash** path also deletes its temporary export with a `defer`. Replacing the eager `Data` with a bare file URL without changing that lifetime would publish a clipboard reference to a file that no longer exists as soon as the action returns.

## Current State

### Clipboard helper

`ScreenshotMaxxing/Editor/EditorClipboard.swift` currently exposes an eager byte API:

```swift
static func copyMP4Data(
    _ data: Data,
    to pasteboard: NSPasteboard = .general
) {
    pasteboard.clearContents()
    pasteboard.setData(data, forType: NSPasteboard.PasteboardType(UTType.mpeg4Movie.identifier))
    pasteboard.setData(data, forType: NSPasteboard.PasteboardType(UTType.movie.identifier))
}
```

### Persistent edited copy

`ScreenshotMaxxing/Video/VideoEditorView.swift` exports the edited file and then reads it in full:

```swift
let exportResult = try await saveEditedVideoToDisk()
let videoData = try Data(contentsOf: exportResult.fileURL)

EditorClipboard.copyMP4Data(videoData)
```

### Copy & Trash

The temporary path currently guarantees immediate cleanup:

```swift
let temporaryURL = try await exportEditedVideoToTemporaryFile()
defer {
    try? FileManager.default.removeItem(at: temporaryURL)
}

let videoData = try Data(contentsOf: temporaryURL)
EditorClipboard.copyMP4Data(videoData)
```

This cleanup strategy is correct only while the pasteboard owns an independent byte copy.

## Target Design

### 1. Add a pasteboard data-provider object

Create `ScreenshotMaxxing/Editor/VideoPasteboardDataProvider.swift`.

Define an internal reference type conforming to `NSPasteboardItemDataProvider`:

```swift
final class VideoPasteboardDataProvider: NSObject, NSPasteboardItemDataProvider {
    let sourceURL: URL

    init(
        sourceURL: URL,
        removesSourceWhenFinished: Bool,
        fileManager: FileManager = .default
    )

    func pasteboard(
        _ pasteboard: NSPasteboard?,
        item: NSPasteboardItem,
        provideDataForType type: NSPasteboard.PasteboardType
    )

    func pasteboardFinishedWithDataProvider(_ pasteboard: NSPasteboard)

    func cancel()
}
```

Responsibilities:

- Retain the source URL for the lifetime of the clipboard representation.
- Register as the lazy provider for both `UTType.mpeg4Movie` and `UTType.movie`.
- Read the source using `Data(contentsOf:options: .mappedIfSafe)` only inside `provideDataForType`.
- Ignore unsupported requested types instead of manufacturing a representation.
- Delete the source exactly once on `pasteboardFinishedWithDataProvider` when `removesSourceWhenFinished` is true.
- Delete an owned source on `cancel()` if the pasteboard write fails.
- Never delete persistent exports used by the normal **Copy** action.

The cleanup path must be thread-safe because pasteboard provider callbacks are not guaranteed to arrive through the view's main-actor call path. Protect the one-time cleanup state with a small lock or an equivalent serial primitive; do not place UI state in this provider.

### 2. Publish one item with immediate and lazy representations

Replace `EditorClipboard.copyMP4Data` with:

```swift
typealias PasteboardWriter =
    (NSPasteboard, [NSPasteboardWriting]) -> Bool

@discardableResult
static func copyVideoFile(
    at sourceURL: URL,
    sourceLifetime: VideoClipboardSourceLifetime,
    to pasteboard: NSPasteboard = .general,
    writeObjects: PasteboardWriter = { pasteboard, objects in
        pasteboard.writeObjects(objects)
    }
) -> Bool
```

Use an explicit lifetime rather than a cleanup boolean:

```swift
enum VideoClipboardSourceLifetime: Equatable {
    case persistent
    case clipboardTemporary
}
```

Implementation shape:

1. Verify that `sourceURL` is a readable regular file before clearing the existing pasteboard.
2. Create a `VideoPasteboardDataProvider`.
3. Create one `NSPasteboardItem`.
4. For `.persistent`, set its `.fileURL` representation to
   `sourceURL.absoluteString`.
5. For `.clipboardTemporary`, do not advertise `.fileURL`; AppKit may finish
   the provider after promised bytes are materialized, and deleting the
   temporary source at that point would leave a URL representation dangling.
6. Register the provider for the MPEG-4 and generic movie pasteboard types.
7. Clear the pasteboard and call `writeObjects([item])`.
8. If the write fails, call `provider.cancel()` and return `false`.
9. If the write succeeds, return `true`; the pasteboard item/provider
   relationship owns the lazy delivery lifetime.

Persistent items contain all three representations. File-aware destinations
can consume `.fileURL` without allocating a full video-sized buffer, while
destinations that require movie bytes can request a compatible representation.
Temporary items contain only the two promised movie representations, matching
the existing clipboard types without publishing a path whose lifetime cannot
be guaranteed.

Do not silently fall back to eager loading if `writeObjects` fails. Surface failure to the caller.

The item must retain its provider for as long as AppKit may request promised
data. Confirm this behavior with a focused lifetime test rather than depending
on an undocumented assumption. Do not add a second, unrelated global retention
mechanism unless the test shows one is required.

### 3. Transfer temporary-file ownership explicitly

Update both video editor actions in `ScreenshotMaxxing/Video/VideoEditorView.swift`.

For normal **Copy**:

```swift
let exportResult = try await saveEditedVideoToDisk()
if EditorClipboard.copyVideoFile(
    at: exportResult.fileURL,
    sourceLifetime: .persistent
) {
    statusMessage = "Saved and copied video to clipboard"
    closeAfterShowingSuccess()
} else {
    statusMessage = "Saved, but copy failed"
}
```

The exported file is persistent, so the provider must not remove it.

For **Copy & Trash**:

```swift
let exportResult = try await exportEditedVideoToTemporaryFile()
temporaryFileURL = exportResult.fileURL
guard EditorClipboard.copyVideoFile(
    at: exportResult.fileURL,
    sourceLifetime: .clipboardTemporary
) else {
    statusMessage = "Copy failed"
    return
}
temporaryFileURL = nil
```

Keep the existing `defer` as a pre-transfer failure cleanup, but set
`temporaryFileURL = nil` immediately after a successful pasteboard write. Once
that assignment occurs, the provider owns cleanup. If publication fails,
`copyVideoFile` cancels the provider and the `defer` is a harmless idempotent
fallback.

Only proceed to the Plan 002 lifecycle-service deletion after the pasteboard write succeeds. A clipboard failure must leave the capture and history entry intact.

### 4. Preserve the Plan 002 deletion boundary

This plan is intentionally sequenced after `docs/plans/002-unify-capture-deletion-lifecycle.md` because both plans change `copyEditedVideoAndDeleteCapture`.

Before editing that method, confirm that it calls the shared capture lifecycle service introduced by Plan 002. Retain that service call. Do not restore direct use of `CaptureMetadataStore.deleteCaptureFromHistoryAndDisk`.

If Plan 002 has not landed, stop and either:

- implement Plan 002 first, or
- rebase this plan onto the actual deletion API and update this document before coding.

## Scope

**In scope:**

- Create `ScreenshotMaxxing/Editor/VideoPasteboardDataProvider.swift`
- Modify `ScreenshotMaxxing/Editor/EditorClipboard.swift`
- Modify `ScreenshotMaxxing/Video/VideoEditorView.swift`
- Modify `ScreenshotMaxxingTests/ScreenshotMaxxingTests.swift`
- Modify `docs/ARCHITECTURE.md`
- Modify `PRIVACY.md`
- Modify `CHANGELOG.md`
- Modify `docs/plans/README.md` for status only

**Out of scope:**

- Changing image clipboard behavior.
- Changing video codecs, export presets, or render quality.
- Streaming arbitrary media from the network.
- Persisting clipboard exports outside existing app and operating-system
  temporary locations.
- Changing the unified deletion semantics defined by Plan 002.
- Broad abstractions over every pasteboard type.
- Editing `ScreenshotMaxxing.xcodeproj/project.pbxproj`.

## Git Workflow

- Branch: `codex-file-backed-video-clipboard`
- Commit style: conventional commits, matching
  `c6e2242 feat: add mono audio export option for edited videos (#91)`.
- Make the task-level commits listed below. Do not push or open a PR unless the
  operator explicitly asks.
- Do not commit files under `docs/plans/` unless the operator explicitly asks.

## Tasks

### Task 1: Implement thread-safe source ownership in the data provider

**Files:**

- Create: `ScreenshotMaxxing/Editor/VideoPasteboardDataProvider.swift`
- Modify: `ScreenshotMaxxingTests/ScreenshotMaxxingTests.swift:2995-3008`

**Interfaces:**

- Consumes: `NSPasteboardItemDataProvider`,
  `NSPasteboard.PasteboardType`, `UTType.mpeg4Movie`, `UTType.movie`,
  `FileManager`, and `Data(contentsOf:options:)`.
- Produces:
  `VideoPasteboardDataProvider.init(sourceURL:removesSourceWhenFinished:fileManager:)`,
  `pasteboard(_:item:provideDataForType:)`,
  `pasteboardFinishedWithDataProvider(_:)`, and `cancel()`.

- [ ] **Step 1: Replace the eager MP4 test with provider lifecycle tests**

Delete `editorClipboardWritesMP4DataToPasteboard()`. Add:

```swift
@MainActor
@Test func videoPasteboardProviderRemovesOwnedTemporaryFileWhenFinished() throws {
    let fileManager = FileManager.default
    let sourceURL = fileManager.temporaryDirectory
        .appendingPathComponent("ScreenshotMaxxingTests-\(UUID().uuidString).mp4")
    let pasteboard = NSPasteboard(
        name: NSPasteboard.Name("ScreenshotMaxxingTests-\(UUID().uuidString)")
    )
    defer {
        try? fileManager.removeItem(at: sourceURL)
        pasteboard.releaseGlobally()
    }
    try Data("mp4".utf8).write(to: sourceURL)
    let provider = VideoPasteboardDataProvider(
        sourceURL: sourceURL,
        removesSourceWhenFinished: true,
        fileManager: fileManager
    )

    provider.pasteboardFinishedWithDataProvider(pasteboard)
    provider.pasteboardFinishedWithDataProvider(pasteboard)
    provider.cancel()

    #expect(!fileManager.fileExists(atPath: sourceURL.fileSystemPath))
}

@MainActor
@Test func videoPasteboardProviderPreservesPersistentSourceWhenFinished() throws {
    let fileManager = FileManager.default
    let sourceURL = fileManager.temporaryDirectory
        .appendingPathComponent("ScreenshotMaxxingTests-\(UUID().uuidString).mp4")
    let pasteboard = NSPasteboard(
        name: NSPasteboard.Name("ScreenshotMaxxingTests-\(UUID().uuidString)")
    )
    defer {
        try? fileManager.removeItem(at: sourceURL)
        pasteboard.releaseGlobally()
    }
    try Data("mp4".utf8).write(to: sourceURL)
    let provider = VideoPasteboardDataProvider(
        sourceURL: sourceURL,
        removesSourceWhenFinished: false,
        fileManager: fileManager
    )

    provider.pasteboardFinishedWithDataProvider(pasteboard)
    provider.cancel()

    #expect(fileManager.fileExists(atPath: sourceURL.fileSystemPath))
}
```

- [ ] **Step 2: Verify the provider type is missing**

Run: `scripts/test.sh unit`

Expected: exit nonzero with a compiler error that
`VideoPasteboardDataProvider` is not in scope.

- [ ] **Step 3: Create the provider**

Create `ScreenshotMaxxing/Editor/VideoPasteboardDataProvider.swift`:

```swift
import AppKit
import Foundation
import UniformTypeIdentifiers

final class VideoPasteboardDataProvider: NSObject, NSPasteboardItemDataProvider {
    nonisolated let sourceURL: URL
    nonisolated(unsafe) private let fileManager: FileManager
    nonisolated private let removesSourceWhenFinished: Bool
    nonisolated private let cleanupLock = NSLock()
    nonisolated(unsafe) private var didCleanUp = false

    init(
        sourceURL: URL,
        removesSourceWhenFinished: Bool,
        fileManager: FileManager = .default
    ) {
        self.sourceURL = sourceURL
        self.removesSourceWhenFinished = removesSourceWhenFinished
        self.fileManager = fileManager
        super.init()
    }

    nonisolated func pasteboard(
        _ pasteboard: NSPasteboard?,
        item: NSPasteboardItem,
        provideDataForType type: NSPasteboard.PasteboardType
    ) {
        let supportedTypes = [
            NSPasteboard.PasteboardType(UTType.mpeg4Movie.identifier),
            NSPasteboard.PasteboardType(UTType.movie.identifier),
        ]
        guard supportedTypes.contains(type),
            let data = try? Data(contentsOf: sourceURL, options: .mappedIfSafe)
        else {
            return
        }

        item.setData(data, forType: type)
    }

    nonisolated func pasteboardFinishedWithDataProvider(_ pasteboard: NSPasteboard) {
        cleanUpOwnedSource()
    }

    nonisolated func cancel() {
        cleanUpOwnedSource()
    }

    nonisolated private func cleanUpOwnedSource() {
        guard removesSourceWhenFinished else {
            return
        }

        cleanupLock.lock()
        let shouldRemove = !didCleanUp
        didCleanUp = true
        cleanupLock.unlock()

        if shouldRemove {
            try? fileManager.removeItem(at: sourceURL)
        }
    }
}
```

The `nonisolated` annotations are required because the target uses
`SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`, while AppKit may invoke data
provider callbacks outside the view's main-actor call path.

- [ ] **Step 4: Format the provider**

Run: `scripts/format.sh`

Expected: exit 0.

- [ ] **Step 5: Verify provider cleanup**

Run: `scripts/test.sh unit`

Expected: exit 0; both provider lifecycle tests pass. If the SDK rejects the
shown isolation annotations, stop and report the exact compiler diagnostic
instead of making cleanup main-thread-only.

- [ ] **Step 6: Commit Task 1**

```bash
git add \
  ScreenshotMaxxing/Editor/VideoPasteboardDataProvider.swift \
  ScreenshotMaxxingTests/ScreenshotMaxxingTests.swift
git commit -m "refactor: add file-backed video pasteboard provider"
```

Expected: commit succeeds.

### Task 2: Publish persistent and temporary video representations lazily

**Files:**

- Modify: `ScreenshotMaxxing/Editor/EditorClipboard.swift:12-42`
- Modify: `ScreenshotMaxxingTests/ScreenshotMaxxingTests.swift:2966-3010`

**Interfaces:**

- Consumes: Task 1's `VideoPasteboardDataProvider`.
- Produces: `VideoClipboardSourceLifetime`,
  `EditorClipboard.copyVideoFile(at:sourceLifetime:to:writeObjects:) -> Bool`,
  and a deterministic failed-write seam.

- [ ] **Step 1: Add representation and laziness tests**

Add these tests beside the PNG and string clipboard tests:

```swift
@MainActor
@Test func editorClipboardPublishesPersistentFileURLAndMovieTypes() throws {
    let fileManager = FileManager.default
    let sourceURL = fileManager.temporaryDirectory
        .appendingPathComponent("ScreenshotMaxxingTests-\(UUID().uuidString).mp4")
    let pasteboard = NSPasteboard(
        name: NSPasteboard.Name("ScreenshotMaxxingTests-\(UUID().uuidString)")
    )
    defer {
        try? fileManager.removeItem(at: sourceURL)
        pasteboard.releaseGlobally()
    }
    try Data("mp4".utf8).write(to: sourceURL)

    let copied = EditorClipboard.copyVideoFile(
        at: sourceURL,
        sourceLifetime: .persistent,
        to: pasteboard
    )
    let item = try #require(pasteboard.pasteboardItems?.first)

    #expect(copied)
    #expect(item.types.contains(.fileURL))
    #expect(item.types.contains(NSPasteboard.PasteboardType(UTType.mpeg4Movie.identifier)))
    #expect(item.types.contains(NSPasteboard.PasteboardType(UTType.movie.identifier)))
    #expect(item.string(forType: .fileURL) == sourceURL.absoluteString)
}

@MainActor
@Test func editorClipboardTemporarySourceOmitsFileURL() throws {
    let fileManager = FileManager.default
    let sourceURL = fileManager.temporaryDirectory
        .appendingPathComponent("ScreenshotMaxxingTests-\(UUID().uuidString).mp4")
    let pasteboard = NSPasteboard(
        name: NSPasteboard.Name("ScreenshotMaxxingTests-\(UUID().uuidString)")
    )
    defer {
        try? fileManager.removeItem(at: sourceURL)
        pasteboard.releaseGlobally()
    }
    try Data("mp4".utf8).write(to: sourceURL)

    let copied = EditorClipboard.copyVideoFile(
        at: sourceURL,
        sourceLifetime: .clipboardTemporary,
        to: pasteboard
    )
    let item = try #require(pasteboard.pasteboardItems?.first)

    #expect(copied)
    #expect(!item.types.contains(.fileURL))
    #expect(item.types.contains(NSPasteboard.PasteboardType(UTType.mpeg4Movie.identifier)))
    #expect(item.types.contains(NSPasteboard.PasteboardType(UTType.movie.identifier)))
    #expect(fileManager.fileExists(atPath: sourceURL.fileSystemPath))
}

@MainActor
@Test func editorClipboardLoadsMovieBytesOnlyWhenRequested() throws {
    let fileManager = FileManager.default
    let sourceURL = fileManager.temporaryDirectory
        .appendingPathComponent("ScreenshotMaxxingTests-\(UUID().uuidString).mp4")
    let pasteboard = NSPasteboard(
        name: NSPasteboard.Name("ScreenshotMaxxingTests-\(UUID().uuidString)")
    )
    defer {
        try? fileManager.removeItem(at: sourceURL)
        pasteboard.releaseGlobally()
    }
    try Data("first".utf8).write(to: sourceURL)
    #expect(
        EditorClipboard.copyVideoFile(
            at: sourceURL,
            sourceLifetime: .persistent,
            to: pasteboard
        )
    )

    try Data("second".utf8).write(to: sourceURL)
    let movieType = NSPasteboard.PasteboardType(UTType.mpeg4Movie.identifier)

    #expect(pasteboard.data(forType: movieType) == Data("second".utf8))
}

@MainActor
@Test func editorClipboardFailedWriteCleansOwnedTemporarySource() throws {
    let fileManager = FileManager.default
    let sourceURL = fileManager.temporaryDirectory
        .appendingPathComponent("ScreenshotMaxxingTests-\(UUID().uuidString).mp4")
    let pasteboard = NSPasteboard(
        name: NSPasteboard.Name("ScreenshotMaxxingTests-\(UUID().uuidString)")
    )
    defer {
        try? fileManager.removeItem(at: sourceURL)
        pasteboard.releaseGlobally()
    }
    try Data("mp4".utf8).write(to: sourceURL)

    let copied = EditorClipboard.copyVideoFile(
        at: sourceURL,
        sourceLifetime: .clipboardTemporary,
        to: pasteboard,
        writeObjects: { _, _ in false }
    )

    #expect(!copied)
    #expect(!fileManager.fileExists(atPath: sourceURL.fileSystemPath))
}
```

- [ ] **Step 2: Verify the new API is missing**

Run: `scripts/test.sh unit`

Expected: exit nonzero with missing `copyVideoFile` and
`VideoClipboardSourceLifetime` diagnostics.

- [ ] **Step 3: Replace the eager video clipboard API**

Keep `copyPNGData` and `copyString` unchanged. Replace `copyMP4Data` with:

```swift
enum VideoClipboardSourceLifetime {
    case persistent
    case clipboardTemporary

    var removesSourceWhenFinished: Bool {
        self == .clipboardTemporary
    }
}

@MainActor
enum EditorClipboard {
    typealias PasteboardWriter =
        (NSPasteboard, [NSPasteboardWriting]) -> Bool

    // Keep copyPNGData(_:to:) and copyString(_:to:) exactly as they are.

    static func copyVideoFile(
        at sourceURL: URL,
        sourceLifetime: VideoClipboardSourceLifetime,
        to pasteboard: NSPasteboard = .general,
        writeObjects: PasteboardWriter = { pasteboard, objects in
            pasteboard.writeObjects(objects)
        }
    ) -> Bool {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(
            atPath: sourceURL.fileSystemPath,
            isDirectory: &isDirectory
        ), !isDirectory.boolValue
        else {
            return false
        }

        let provider = VideoPasteboardDataProvider(
            sourceURL: sourceURL,
            removesSourceWhenFinished: sourceLifetime.removesSourceWhenFinished
        )
        let item = NSPasteboardItem()
        let movieTypes = [
            NSPasteboard.PasteboardType(UTType.mpeg4Movie.identifier),
            NSPasteboard.PasteboardType(UTType.movie.identifier),
        ]
        item.setDataProvider(provider, forTypes: movieTypes)

        if sourceLifetime == .persistent {
            item.setString(sourceURL.absoluteString, forType: .fileURL)
        }

        pasteboard.clearContents()
        guard writeObjects(pasteboard, [item]) else {
            provider.cancel()
            return false
        }

        return true
    }
}
```

Place `VideoClipboardSourceLifetime` above `EditorClipboard`; do not nest it in
the enum because `VideoEditorView` supplies the lifetime.

- [ ] **Step 4: Add the provider-retention integration test**

Add:

```swift
@MainActor
@Test func editorClipboardRetainsTemporarySourceUntilProviderFinishes() async throws {
    let fileManager = FileManager.default
    let sourceURL = fileManager.temporaryDirectory
        .appendingPathComponent("ScreenshotMaxxingTests-\(UUID().uuidString).mp4")
    let pasteboard = NSPasteboard(
        name: NSPasteboard.Name("ScreenshotMaxxingTests-\(UUID().uuidString)")
    )
    defer {
        try? fileManager.removeItem(at: sourceURL)
        pasteboard.releaseGlobally()
    }
    try Data("mp4".utf8).write(to: sourceURL)

    #expect(
        EditorClipboard.copyVideoFile(
            at: sourceURL,
            sourceLifetime: .clipboardTemporary,
            to: pasteboard
        )
    )
    #expect(fileManager.fileExists(atPath: sourceURL.fileSystemPath))

    pasteboard.clearContents()
    try await waitForCondition(
        !fileManager.fileExists(atPath: sourceURL.fileSystemPath)
    )
}
```

- [ ] **Step 5: Format the clipboard API**

Run: `scripts/format.sh`

Expected: exit 0.

- [ ] **Step 6: Verify lazy publication**

Run: `scripts/test.sh unit`

Expected: exit 0; persistent items advertise three types, temporary items omit
`.fileURL`, changed file bytes are read on demand, and failed writes clean owned
temporary sources.

- [ ] **Step 7: Commit Task 2**

```bash
git add \
  ScreenshotMaxxing/Editor/EditorClipboard.swift \
  ScreenshotMaxxingTests/ScreenshotMaxxingTests.swift
git commit -m "refactor: publish video clipboard data lazily"
```

Expected: commit succeeds.

### Task 3: Switch normal video Copy to the persistent file API

**Files:**

- Modify: `ScreenshotMaxxing/Video/VideoEditorView.swift:226-253`

**Interfaces:**

- Consumes:
  `EditorClipboard.copyVideoFile(at:sourceLifetime:to:writeObjects:)` with
  `.persistent`.
- Produces: normal Copy without `Data(contentsOf:)`; the saved edited export
  remains on disk.

- [ ] **Step 1: Replace the eager persistent copy block**

Replace the body of the `do` block in `copyEditedVideo()` with:

```swift
let exportResult = try await saveEditedVideoToDisk()

if EditorClipboard.copyVideoFile(
    at: exportResult.fileURL,
    sourceLifetime: .persistent
) {
    statusMessage = "Saved and copied video to clipboard"
    closeAfterShowingSuccess()
} else {
    statusMessage = "Saved, but copy failed"
}
```

- [ ] **Step 2: Prove normal Copy no longer reads the file eagerly**

Run:

```bash
rg -n 'Data\\(contentsOf: exportResult\\.fileURL\\)' \
  ScreenshotMaxxing/Video/VideoEditorView.swift
```

Expected: exit 1 with no matches.

- [ ] **Step 3: Format the persistent Copy change**

Run: `scripts/format.sh`

Expected: exit 0.

- [ ] **Step 4: Verify persistent Copy**

Run: `scripts/test.sh unit`

Expected: exit 0.

- [ ] **Step 5: Commit Task 3**

```bash
git add ScreenshotMaxxing/Video/VideoEditorView.swift
git commit -m "perf: copy saved videos from file"
```

Expected: commit succeeds.

### Task 4: Transfer Copy & Trash temporary-file ownership to the provider

**Files:**

- Modify: `ScreenshotMaxxing/Video/VideoEditorView.swift:255-305`

**Interfaces:**

- Consumes: Task 2's `.clipboardTemporary` lifetime and Plan 002's
  `captureLifecycleService.deleteCaptures(_:from:)`.
- Produces: temporary export cleanup on failed publication or provider
  completion, while preserving copy-before-delete ordering.

- [ ] **Step 1: Confirm the Plan 002 dependency**

Run:

```bash
rg -n 'captureLifecycleService\\.deleteCaptures' \
  ScreenshotMaxxing/Video/VideoEditorView.swift
```

Expected: one match inside `copyEditedVideoAndDeleteCapture()`. If there is no
match, stop and implement/reconcile Plan 002 first.

- [ ] **Step 2: Replace the temporary export ownership block**

Replace the complete `Task` body in
`copyEditedVideoAndDeleteCapture()` with:

```swift
Task {
    var temporaryFileURL: URL?
    defer {
        if let temporaryFileURL {
            try? FileManager.default.removeItem(at: temporaryFileURL)
        }
        isExporting = false
    }

    do {
        let exportResult = try await exportEditedVideoToTemporaryFile()
        temporaryFileURL = exportResult.fileURL

        guard EditorClipboard.copyVideoFile(
            at: exportResult.fileURL,
            sourceLifetime: .clipboardTemporary
        ) else {
            statusMessage = "Copy failed"
            return
        }
        temporaryFileURL = nil

        guard let capture else {
            statusMessage = EditorCopyAndTrashStatus.copiedWithoutCaptureMessage(for: .video)
            closeAfterShowingSuccess()
            return
        }

        do {
            try captureLifecycleService.deleteCaptures(
                [capture],
                from: PersistenceController.sharedModelContainer.mainContext
            )
            statusMessage = EditorCopyAndTrashStatus.copiedAndMovedToTrashMessage(for: .video)
            closeAfterShowingSuccess()
        } catch {
            statusMessage = EditorCopyAndTrashStatus.copiedButMoveToTrashFailedMessage(
                for: .video,
                errorDescription: error.localizedDescription
            )
        }
    } catch {
        statusMessage = error.localizedDescription
    }
}
```

Setting `temporaryFileURL = nil` is the ownership-transfer line: after a
successful pasteboard write, only the provider may remove that file.

- [ ] **Step 3: Prove eager copy and legacy deletion did not return**

Run:

```bash
rg -n \
  'copyMP4Data|Data\\(contentsOf:.*(fileURL|temporaryFileURL)|deleteCaptureFromHistoryAndDisk' \
  ScreenshotMaxxing/Video/VideoEditorView.swift \
  ScreenshotMaxxing/Editor/EditorClipboard.swift \
  ScreenshotMaxxingTests/ScreenshotMaxxingTests.swift
```

Expected: exit 1 with no matches.

- [ ] **Step 4: Format the Copy & Trash change**

Run: `scripts/format.sh`

Expected: exit 0.

- [ ] **Step 5: Verify Copy & Trash**

Run: `scripts/test.sh unit`

Expected: exit 0.

- [ ] **Step 6: Commit Task 4**

```bash
git add ScreenshotMaxxing/Video/VideoEditorView.swift
git commit -m "perf: transfer temporary video clipboard ownership"
```

Expected: commit succeeds.

### Task 5: Document, manually verify, and close the loop

**Files:**

- Modify: `docs/ARCHITECTURE.md:44-63`
- Modify: `PRIVACY.md:7-24`
- Modify: `PRIVACY.md:44-54`
- Modify: `CHANGELOG.md:7-9`

**Interfaces:**

- Consumes: Tasks 1-4's persistent and clipboard-temporary lifetimes.
- Produces: narrow local-storage claims and recorded destination compatibility.

- [ ] **Step 1: Add the architecture paragraph**

Add after the `EditorClipboard` bullet:

```markdown
Video clipboard writes are file-backed. Persistent edited exports advertise a
file URL plus lazy MPEG-4/movie representations. Copy & Trash temporary exports
advertise only lazy movie representations so provider cleanup cannot leave a
dangling file URL; the provider removes the local temporary export after
AppKit finishes with it or if publication fails.
```

- [ ] **Step 2: Add the privacy paragraph**

Add after the local-data paragraph ending at `PRIVACY.md:24`:

```markdown
Copying an edited video may keep a temporary local export available while the
macOS clipboard needs it. ScreenshotMaxxing does not upload that export.
Clipboard-temporary exports are removed after AppKit finishes with their
promised movie data or if clipboard publication fails; operating-system
temporary-file cleanup may handle remnants left by an unexpected process exit.
```

Do not describe this as immediate or guaranteed secure deletion.

- [ ] **Step 3: Add the changelog entry**

Under `## Unreleased`, add:

```markdown
- Reduced memory spikes when copying edited videos by publishing file-backed clipboard representations instead of loading the full export up front.
```

- [ ] **Step 4: Run deterministic gates**

Run: `scripts/format.sh`

Expected: exit 0.

Run: `scripts/lint.sh`

Expected: exit 0.

Run: `scripts/test.sh unit`

Expected: exit 0.

Run: `git diff --check`

Expected: exit 0 with no output.

- [ ] **Step 5: Run the manual compatibility matrix**

Build and launch with:

```bash
scripts/build-and-run.sh
```

Expected: Debug app launches.

Record the macOS version and results for all five checks in the PR description:

1. Normal **Copy** pastes a short edited recording into Finder.
2. Normal **Copy** pastes into one application that consumes video clipboard
   content.
3. **Copy & Trash** pastes into an application that consumed the old eager
   MPEG-4/movie representations.
4. Replacing clipboard contents removes the clipboard-temporary export, while
   the normal Copy export remains in the app's edited folder.
5. Clicking Copy for a large recording does not immediately allocate memory
   approximately equal to the MP4 size; a later destination request may.

If Finder support is required for a clipboard-temporary item, stop and design
an `NSFilePromiseProvider` follow-up. Do not expose a temporary raw file URL.

- [ ] **Step 6: Commit Task 5**

```bash
git add docs/ARCHITECTURE.md PRIVACY.md CHANGELOG.md
git commit -m "docs: explain video clipboard file lifetime"
```

Expected: commit succeeds.

- [ ] **Step 7: Update the plan index**

Change Plan 003's status in `docs/plans/README.md` from `TODO` to `DONE` only after
all Done criteria below pass. Do not include the index in a source commit
unless the operator explicitly requested plan-file commits.

## Test Plan

Add these deterministic Swift Testing cases in
`ScreenshotMaxxingTests/ScreenshotMaxxingTests.swift`, beside the current
clipboard tests:

1. `videoPasteboardProviderRemovesOwnedTemporaryFileWhenFinished`
2. `videoPasteboardProviderPreservesPersistentSourceWhenFinished`
3. `editorClipboardPublishesPersistentFileURLAndMovieTypes`
4. `editorClipboardTemporarySourceOmitsFileURL`
5. `editorClipboardLoadsMovieBytesOnlyWhenRequested`
6. `editorClipboardFailedWriteCleansOwnedTemporarySource`
7. `editorClipboardRetainsTemporarySourceUntilProviderFinishes`

Model named-pasteboard setup and `releaseGlobally()` cleanup on
`editorClipboardWritesPNGDataToPasteboard()` at
`ScreenshotMaxxingTests/ScreenshotMaxxingTests.swift:2966-2979`. Use the
existing bounded `waitForCondition(_:)` helper for provider completion; do not
add fixed-duration sleeps.

Verification: `scripts/test.sh unit` exits 0 with all seven new tests.

## Risks and Mitigations

- **Destination compatibility:** Advertise a file URL for persistent sources and the existing MPEG-4/movie types for both lifetimes; require manual checks in representative destinations.
- **Dangling temporary URL:** Never advertise `.fileURL` for a source the provider is expected to delete.
- **Premature temporary-file deletion:** Transfer ownership to the provider only after a successful pasteboard write and remove the current `defer`.
- **Leaked temporary exports:** Clean owned files on provider completion and write failure; make cleanup idempotent.
- **Concurrency during cleanup:** Protect cleanup state independently of UI actor isolation.
- **A hidden eager fallback reintroduces the spike:** Assert lazy behavior in tests and reject eager fallback in code review.
- **Conflict with Plan 002:** Execute after Plan 002 and preserve the shared lifecycle-service call.

## Done Criteria

- [ ] `rg -n 'copyMP4Data|Data\\(contentsOf:.*(fileURL|temporaryFileURL)' ScreenshotMaxxing ScreenshotMaxxingTests` exits 1.
- [ ] Persistent clipboard tests prove `.fileURL`, MPEG-4, and generic movie representations are advertised.
- [ ] Clipboard-temporary tests prove MPEG-4 and generic movie representations are advertised without `.fileURL`.
- [ ] The laziness test reads bytes written after `copyVideoFile` returns.
- [ ] Provider tests prove temporary cleanup is idempotent and persistent sources survive completion.
- [ ] A failed pasteboard write removes its owned temporary source.
- [ ] `rg -n 'captureLifecycleService\\.deleteCaptures' ScreenshotMaxxing/Video/VideoEditorView.swift` finds the Plan 002 deletion call.
- [ ] `scripts/lint.sh` exits 0.
- [ ] `scripts/test.sh unit` exits 0.
- [ ] `git diff --check` exits 0.
- [ ] Manual results record Finder normal-Copy compatibility, one video-capable destination, Copy & Trash compatibility, cleanup, and memory behavior.
- [ ] Architecture, privacy, and changelog documentation match the actual lifetime guarantees.
- [ ] `git status --short` lists no out-of-scope source files.
- [ ] The `docs/plans/README.md` row is updated.

## Stop Conditions

Stop implementation and revise the design if:

- AppKit does not retain the data provider for the required pasteboard lifetime.
- A required destination cannot consume the representations appropriate to the source lifetime.
- Provider completion is not reliably delivered enough to support the documented cleanup claim.
- Plan 002's deletion API differs materially from the assumed lifecycle service.
- Tests reveal that AppKit requests movie bytes synchronously during `writeObjects`, eliminating the expected memory benefit.

If completion callbacks are unreliable, choose and document a conservative cleanup fallback before proceeding, such as retaining clipboard temporary files in an app-owned cache with bounded age-based cleanup on launch. Do not restore immediate deletion or claim stronger cleanup guarantees than the implementation provides.

## Maintenance Notes

- Keep the provider internal unless a second concrete file-backed clipboard use case appears.
- Treat temporary-file ownership as part of the clipboard API contract; callers must never independently delete an owned source after a successful write.
- If supported paste destinations change, extend compatibility tests before changing advertised representations.
- If future profiling shows on-demand movie requests still create unacceptable allocations, evaluate a true file-promise representation as a separate plan rather than complicating this provider silently.
