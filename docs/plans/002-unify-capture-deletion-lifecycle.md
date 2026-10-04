# Unified Capture Deletion Lifecycle Implementation Plan

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
>   ScreenshotMaxxing/Persistence/CaptureLifecycleService.swift \
>   ScreenshotMaxxing/Persistence/CaptureMetadataStore.swift \
>   ScreenshotMaxxing/History/CaptureHistoryData.swift \
>   ScreenshotMaxxing/History/CaptureHistoryView.swift \
>   ScreenshotMaxxing/Editor/ScreenshotEditorView.swift \
>   ScreenshotMaxxing/Video/VideoEditorView.swift \
>   ScreenshotMaxxing/Editor/EditorToolbarAction.swift \
>   ScreenshotMaxxing/Utilities/FileLocations.swift \
>   ScreenshotMaxxingTests/ScreenshotMaxxingTests.swift \
>   PRIVACY.md \
>   docs/ARCHITECTURE.md \
>   CHANGELOG.md
> ```
>
> If any in-scope file changed, compare the live deletion paths and current
> excerpts below. Stop if a unified lifecycle service already exists or if
> Copy & Trash semantics were intentionally documented as different from
> History deletion.

**Goal:** History deletion and both editor Copy & Trash actions must use one
service that removes the selected capture, linked edited History entries, and
all related local files that still exist.

**Architecture:** Add a main-actor `CaptureLifecycleService` in `Persistence/`.
The service receives a `ModelContext`, fetches the complete capture set, expands
selected captures to linked edited versions, discovers related disk files,
moves existing files to Trash, and removes metadata. `CaptureHistoryData`
returns to presentation/filtering responsibilities; `CaptureMetadataStore`
returns to metadata creation responsibilities.

**Tech Stack:** SwiftData, Foundation file APIs, AppKit Trash integration,
SwiftUI, Swift Testing.

## Global Constraints

- The Xcode project uses `SWIFT_VERSION = 5.0`,
  `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`, and
  `MACOSX_DEPLOYMENT_TARGET = 26.2`; do not change these build settings.
- Add no package, framework, schema migration, account, telemetry, hosted
  storage, cloud sync, or network behavior.
- Continue moving files to macOS Trash; do not permanently delete files or
  empty Trash.
- Preserve the documented limit that backups, sync tools, recovery tools, and
  manually copied files remain outside the app's control.
- Keep copy-before-delete ordering. Clipboard failure must never delete capture
  files or History metadata.
- Update `PRIVACY.md`, `docs/ARCHITECTURE.md`, `CHANGELOG.md`, and the Copy &
  Trash descriptor in the same implementation.
- Use `scripts/format.sh`, `scripts/lint.sh`, and `scripts/test.sh unit`; UI
  automation is outside this plan.
- The Xcode project uses file-system-synchronized groups, so creating
  `CaptureLifecycleService.swift` never requires editing
  `ScreenshotMaxxing.xcodeproj/project.pbxproj`.

---

## Status

- **Priority:** P1
- **Effort:** M
- **Risk:** MED
- **Depends on:** none
- **Category:** bug
- **Planned at:** commit `3d0c0ad`, 2026-07-18

## Why this matters

The repository currently has two meanings for deletion. History deletion
recursively finds linked edited History rows and disk-only edited siblings.
Editor Copy & Trash calls a narrower `CaptureMetadataStore` method that knows
only the selected row's three stored paths. A user can therefore get different
cleanup depending on which screen initiated the same destructive action.

This plan intentionally chooses one contract: Copy & Trash matches History
deletion. After the clipboard write succeeds, deleting an original capture
also removes its linked edited versions and their related local files. This
preserves the product's local-first behavior and does not claim deletion of
Trash, backups, synced copies, or manually copied files.

## Current state

The narrow metadata-store path at
`ScreenshotMaxxing/Persistence/CaptureMetadataStore.swift:80-90`:

```swift
func deleteCaptureFromHistoryAndDisk(
    _ capture: Capture,
    fileManager: FileManager = .default,
    fileTrash: CaptureFileTrashing = FileManager.default
) throws {
    for filePath in uniqueFilePaths(for: capture) where fileManager.fileExists(atPath: filePath) {
        try fileTrash.moveItemToTrash(at: URL(fileURLWithPath: filePath))
    }

    modelContainer.mainContext.delete(capture)
    try modelContainer.mainContext.save()
}
```

History has the richer behavior at
`ScreenshotMaxxing/History/CaptureHistoryData.swift:242-339`:

```swift
static func capturesToDelete(from captures: [Capture], selectedIDs: Set<UUID>) -> [Capture]

static func deleteCaptures(
    _ capturesToDelete: [Capture],
    from modelContext: ModelContext,
    allCaptures: [Capture],
    fileManager: FileManager = .default,
    fileTrash: CaptureFileTrashing = FileManager.default
) throws

static func fileURLsToDelete(
    for capturesToDelete: [Capture],
    allCaptures: [Capture],
    fileManager: FileManager = .default
) throws -> [URL]
```

It also scans edited directories using filename lineage
(`ScreenshotMaxxing/History/CaptureHistoryData.swift:486-554`):

```swift
private static func editedVersionPrefixes(for capture: Capture) -> [String]
private static func isEditedVersion(_ capture: Capture, matchingAnyOf prefixes: [String]) -> Bool
private static func editedVersionFileURLs(for capture: Capture, fileManager: FileManager) throws -> [URL]
```

Call sites currently diverge:

- `CaptureHistoryView.deletePendingCaptures()` calls
  `CaptureHistoryData.deleteCaptures(...)`.
- `CaptureHistoryView.removePendingMissingCapture()` calls
  `CaptureHistoryData.removeCapturesFromHistoryOnly(...)`.
- `ScreenshotEditorView.copyEditedImageAndDeleteCapture()` creates
  `CaptureMetadataStore()` and calls the narrow delete method.
- `VideoEditorView.copyEditedVideoAndDeleteCapture()` does the same.

The file-trash seam already exists at
`ScreenshotMaxxing/Utilities/FileLocations.swift:10-18`:

```swift
protocol CaptureFileTrashing {
    func moveItemToTrash(at fileURL: URL) throws
}

extension FileManager: CaptureFileTrashing {
    func moveItemToTrash(at fileURL: URL) throws {
        var trashedURL: NSURL?
        try trashItem(at: fileURL, resultingItemURL: &trashedURL)
    }
}
```

Tests at `ScreenshotMaxxingTests/ScreenshotMaxxingTests.swift:3430-3708`
already cover linked edited rows, disk-only edited files, missing originals,
metadata-only removal, and nonexistent files. Preserve those cases while
moving their subject to the new service.

Relevant documented contracts:

- `PRIVACY.md:50-54` says History deletion attempts to remove related files and
  metadata, while external copies may remain.
- `EditorToolbarAction.swift:46-56` says Copy & Trash copies first, then moves
  local capture files to Trash and removes History metadata.
- `CHANGELOG.md:20` describes Copy & Trash as a user-visible action.
- `docs/ARCHITECTURE.md:65-72` currently splits persistence/deletion ownership
  between `CaptureMetadataStore` and `CaptureHistoryData`.

## Commands you will need

| Purpose | Command | Expected on success |
|---|---|---|
| Format changed Swift | `scripts/format.sh` | exit 0 |
| Check formatting | `scripts/lint.sh` | exit 0, no output |
| Deterministic tests | `scripts/test.sh unit` | exit 0, all tests pass |
| Patch hygiene | `git diff --check` | exit 0, no output |
| Old-path check | `rg -n -e deleteCaptureFromHistoryAndDisk -e 'CaptureHistoryData\\.deleteCaptures' -e 'CaptureHistoryData\\.removeCapturesFromHistoryOnly' -e 'CaptureHistoryData\\.fileURLsToDelete' -e 'CaptureHistoryData\\.capturesToDelete' ScreenshotMaxxing ScreenshotMaxxingTests` | exit 1, no matches |

## Scope

**Create:**

- `ScreenshotMaxxing/Persistence/CaptureLifecycleService.swift`

**Modify:**

- `ScreenshotMaxxing/Persistence/CaptureMetadataStore.swift`
- `ScreenshotMaxxing/History/CaptureHistoryData.swift`
- `ScreenshotMaxxing/History/CaptureHistoryView.swift`
- `ScreenshotMaxxing/Editor/ScreenshotEditorView.swift`
- `ScreenshotMaxxing/Video/VideoEditorView.swift`
- `ScreenshotMaxxing/Editor/EditorToolbarAction.swift`
- `ScreenshotMaxxingTests/ScreenshotMaxxingTests.swift`
- `PRIVACY.md`
- `docs/ARCHITECTURE.md`
- `CHANGELOG.md`
- `docs/plans/README.md` for status only

**Modify only if the protocol must move beside its sole domain owner:**

- `ScreenshotMaxxing/Utilities/FileLocations.swift`

**Out of scope:**

- Changing Trash to permanent deletion.
- Emptying Trash or claiming deletion from backups, sync tools, or recovery.
- Changing clipboard representation; that is Plan 003.
- Changing save/export naming conventions.
- Replacing filename-based edit lineage with a SwiftData relationship or
  schema migration. That is a valid later project, not part of this fix.
- Reordering Trash and SwiftData operations to invent cross-filesystem
  transactions.
- Refactoring editor view structure beyond dependency/call-site changes.
- UI automation.

## Git Workflow

- Branch: `codex-unified-capture-deletion`
- Commit style: conventional commits, matching
  `669cc0e fix: delete edited captures for missing originals (#90)`.
- Make the task-level commits listed below. Do not push or open a PR unless the
  operator explicitly asks.
- Do not commit files under `docs/plans/` unless the operator explicitly asks.

## Target interfaces

Create this production interface in
`ScreenshotMaxxing/Persistence/CaptureLifecycleService.swift`:

```swift
@MainActor
struct CaptureLifecycleService {
    private let fileManager: FileManager
    private let fileTrash: any CaptureFileTrashing

    init(
        fileManager: FileManager = .default,
        fileTrash: any CaptureFileTrashing = FileManager.default
    ) {
        self.fileManager = fileManager
        self.fileTrash = fileTrash
    }

    func deleteCaptures(
        _ selectedCaptures: [Capture],
        from modelContext: ModelContext
    ) throws

    func removeMissingCapturesFromHistory(
        _ captures: [Capture],
        from modelContext: ModelContext
    ) throws
}
```

The service itself must fetch the complete model set:

```swift
let allCaptures = try modelContext.fetch(FetchDescriptor<Capture>())
```

Do not require callers to provide `allCaptures`; that permits partial query
results to silently weaken deletion semantics.

Keep lineage and disk-discovery helpers private to this service. If tests need
to inspect behavior, assert observable trashed URLs and remaining SwiftData
rows rather than making the helpers public.

Use `CaptureLifecycleError.captureFileAvailableAgain(fileName:)` for the
metadata-only guard. Move or rename the current `CaptureHistoryError`; do not
leave the domain error in presentation-only `CaptureHistoryData`.

## Tasks

### Task 1: Create the lifecycle service around the rich deletion contract

**Files:**

- Create: `ScreenshotMaxxing/Persistence/CaptureLifecycleService.swift`
- Modify: `ScreenshotMaxxingTests/ScreenshotMaxxingTests.swift:3430-3526`

**Interfaces:**

- Consumes: `Capture`, `ModelContext`, `FetchDescriptor<Capture>`,
  `CaptureFileTrashing.moveItemToTrash(at:)`, `URL.fileSystemPath`, and the
  existing filename convention `<original-stem>-edited-<suffix>`.
- Produces:
  `CaptureLifecycleService.init(fileManager:fileTrash:)` and
  `CaptureLifecycleService.deleteCaptures(_:from:)`.

- [ ] **Step 1: Change the rich deletion test to the target service API**

Rename
`captureHistoryDeletionTrashesSelectedCaptureAndEditedVersions()` to
`captureLifecycleDeletionOfOriginalIncludesLinkedEditedVersions()`. Keep its
existing arrange block through `modelContainer.mainContext.save()`. Replace
the direct helper inspection and deletion block with:

```swift
let service = CaptureLifecycleService(
    fileManager: fileManager,
    fileTrash: fileTrash
)
try service.deleteCaptures(
    [originalCapture],
    from: modelContainer.mainContext
)
let remainingCaptures = try modelContainer.mainContext.fetch(FetchDescriptor<Capture>())

#expect(remainingCaptures.map(\.fileName) == [unrelatedURL.lastPathComponent])
#expect(
    Set(fileTrash.trashedFileURLs.map(\.fileSystemPath)) == [
        originalURL.fileSystemPath,
        editedURL.fileSystemPath,
        diskOnlyEditedURL.fileSystemPath,
        thumbnailURL.fileSystemPath,
    ])
#expect(fileManager.fileExists(atPath: unrelatedURL.fileSystemPath))
```

The arrange block must still create the original row, linked edited row,
disk-only edited sibling, thumbnail, and unrelated row/file shown in the
current test at lines 3431-3483.

- [ ] **Step 2: Run the test suite to verify the new API is absent**

Run: `scripts/test.sh unit`

Expected: exit nonzero with a compiler error that
`CaptureLifecycleService` is not in scope.

- [ ] **Step 3: Create the deletion service**

Create `ScreenshotMaxxing/Persistence/CaptureLifecycleService.swift` with this
complete initial implementation:

```swift
import Foundation
import SwiftData

@MainActor
struct CaptureLifecycleService {
    private let fileManager: FileManager
    private let fileTrash: any CaptureFileTrashing

    init(
        fileManager: FileManager = .default,
        fileTrash: any CaptureFileTrashing = FileManager.default
    ) {
        self.fileManager = fileManager
        self.fileTrash = fileTrash
    }

    func deleteCaptures(
        _ selectedCaptures: [Capture],
        from modelContext: ModelContext
    ) throws {
        let allCaptures = try modelContext.fetch(FetchDescriptor<Capture>())
        let capturesToDelete = expandedCaptures(
            from: allCaptures,
            selectedIDs: Set(selectedCaptures.map(\.id))
        )
        let fileURLs = try fileURLsToDelete(
            for: capturesToDelete,
            allCaptures: allCaptures
        )

        for fileURL in fileURLs where fileManager.fileExists(atPath: fileURL.fileSystemPath) {
            try fileTrash.moveItemToTrash(at: fileURL)
        }

        let idsToDelete = Set(capturesToDelete.map(\.id))
        for capture in allCaptures where idsToDelete.contains(capture.id) {
            modelContext.delete(capture)
        }

        try modelContext.save()
    }

    private func expandedCaptures(
        from captures: [Capture],
        selectedIDs: Set<UUID>
    ) -> [Capture] {
        var idsToDelete = selectedIDs
        var changed = true

        while changed {
            changed = false
            let selectedCaptures = captures.filter { idsToDelete.contains($0.id) }
            let editedPrefixes = selectedCaptures.flatMap(editedVersionPrefixes)

            for capture in captures where !idsToDelete.contains(capture.id) {
                if isEditedVersion(capture, matchingAnyOf: editedPrefixes) {
                    idsToDelete.insert(capture.id)
                    changed = true
                }
            }
        }

        return captures.filter { idsToDelete.contains($0.id) }
    }

    private func fileURLsToDelete(
        for capturesToDelete: [Capture],
        allCaptures: [Capture]
    ) throws -> [URL] {
        let expanded = expandedCaptures(
            from: allCaptures,
            selectedIDs: Set(capturesToDelete.map(\.id))
        )
        var fileURLs = Set<URL>()

        for capture in expanded {
            fileURLs.insert(canonicalFileURL(URL(fileURLWithPath: capture.originalFilePath)))

            if let editedFilePath = capture.editedFilePath {
                fileURLs.insert(canonicalFileURL(URL(fileURLWithPath: editedFilePath)))
            }
            if let thumbnailFilePath = capture.thumbnailFilePath {
                fileURLs.insert(canonicalFileURL(URL(fileURLWithPath: thumbnailFilePath)))
            }
            for editedFileURL in try editedVersionFileURLs(for: capture) {
                fileURLs.insert(canonicalFileURL(editedFileURL))
            }
        }

        return fileURLs.sorted { $0.fileSystemPath < $1.fileSystemPath }
    }

    private func editedVersionPrefixes(for capture: Capture) -> [String] {
        filePaths(for: capture).map { filePath in
            "\(URL(fileURLWithPath: filePath).deletingPathExtension().lastPathComponent)-edited-"
        }
    }

    private func isEditedVersion(
        _ capture: Capture,
        matchingAnyOf prefixes: [String]
    ) -> Bool {
        filePaths(for: capture).contains { filePath in
            let fileName = URL(fileURLWithPath: filePath).lastPathComponent
            return prefixes.contains { fileName.hasPrefix($0) }
        }
    }

    private func filePaths(for capture: Capture) -> [String] {
        [capture.originalFilePath, capture.editedFilePath].compactMap { $0 }
    }

    private func editedVersionFileURLs(for capture: Capture) throws -> [URL] {
        var fileURLs = [URL]()

        for editedDirectory in editedDirectories(for: capture) {
            guard fileManager.fileExists(atPath: editedDirectory.fileSystemPath) else {
                continue
            }
            let candidates = try fileManager.contentsOfDirectory(
                at: editedDirectory,
                includingPropertiesForKeys: nil
            )
            let prefixes = editedVersionPrefixes(for: capture)
            fileURLs.append(
                contentsOf: candidates.filter { candidate in
                    prefixes.contains { candidate.lastPathComponent.hasPrefix($0) }
                }
            )
        }

        return fileURLs
    }

    private func editedDirectories(for capture: Capture) -> [URL] {
        let directories = filePaths(for: capture).map { filePath in
            let containingDirectory = URL(fileURLWithPath: filePath).deletingLastPathComponent()

            if containingDirectory.lastPathComponent == "originals" {
                return containingDirectory
                    .deletingLastPathComponent()
                    .appendingPathComponent("edited", isDirectory: true)
            }
            return containingDirectory
        }

        return Array(Set(directories))
    }

    private func canonicalFileURL(_ fileURL: URL) -> URL {
        fileURL.resolvingSymlinksInPath()
    }
}
```

- [ ] **Step 4: Format the service**

Run: `scripts/format.sh`

Expected: exit 0.

- [ ] **Step 5: Verify the service**

Run: `scripts/test.sh unit`

Expected: exit 0; the renamed lifecycle test passes and unrelated files/rows
remain untouched.

- [ ] **Step 6: Commit Task 1**

```bash
git add \
  ScreenshotMaxxing/Persistence/CaptureLifecycleService.swift \
  ScreenshotMaxxingTests/ScreenshotMaxxingTests.swift
git commit -m "refactor: add capture lifecycle deletion service"
```

Expected: commit succeeds.

### Task 2: Move metadata-only removal into the lifecycle service

**Files:**

- Modify: `ScreenshotMaxxing/Persistence/CaptureLifecycleService.swift`
- Modify: `ScreenshotMaxxingTests/ScreenshotMaxxingTests.swift:3528-3679`

**Interfaces:**

- Consumes: Task 1's `CaptureLifecycleService` and `Capture` path fields.
- Produces:
  `CaptureLifecycleError.captureFileAvailableAgain(fileName:)` and
  `removeMissingCapturesFromHistory(_:from:)`.

- [ ] **Step 1: Point metadata-removal tests at the new API**

In `captureHistoryRemovesMissingCaptureMetadataWithoutTrashingFiles()`, remove
the unused `SpyFileTrash` and create:

```swift
let service = CaptureLifecycleService()
```

In `captureHistoryMetadataOnlyRemovalRefusesAvailableFiles()`, create:

```swift
let service = CaptureLifecycleService(fileManager: fileManager)
```

In the missing-capture test, replace the old mutation call with:

```swift
try service.removeMissingCapturesFromHistory(
    [missingCapture],
    from: modelContainer.mainContext
)
```

In the available-capture test, replace it with:

```swift
try service.removeMissingCapturesFromHistory(
    [availableCapture],
    from: modelContainer.mainContext
)
```

Rename the tests to:

```swift
captureLifecycleRemovesMissingMetadataWithoutTrashingFiles
captureLifecycleRefusesMetadataOnlyRemovalWhenFileIsAvailable
```

- [ ] **Step 2: Verify the missing method fails compilation**

Run: `scripts/test.sh unit`

Expected: exit nonzero with no member
`removeMissingCapturesFromHistory`.

- [ ] **Step 3: Add the error and method**

Add above the service:

```swift
enum CaptureLifecycleError: LocalizedError, Equatable {
    case captureFileAvailableAgain(fileName: String)

    var errorDescription: String? {
        switch self {
        case .captureFileAvailableAgain(let fileName):
            "The file for \(fileName) is available again. Use Delete if you want to move it to the Trash."
        }
    }
}
```

Add inside the service:

```swift
func removeMissingCapturesFromHistory(
    _ captures: [Capture],
    from modelContext: ModelContext
) throws {
    for capture in captures where fileExists(for: capture) {
        throw CaptureLifecycleError.captureFileAvailableAgain(fileName: capture.fileName)
    }

    for capture in captures {
        modelContext.delete(capture)
    }

    try modelContext.save()
}

private func fileExists(for capture: Capture) -> Bool {
    let contentFilePath = capture.editedFilePath ?? capture.originalFilePath
    return fileManager.fileExists(atPath: contentFilePath)
}
```

- [ ] **Step 4: Format the metadata-removal change**

Run: `scripts/format.sh`

Expected: exit 0.

- [ ] **Step 5: Verify metadata-only removal**

Run: `scripts/test.sh unit`

Expected: exit 0; metadata-only removal deletes missing rows, rejects available
files, and never calls Trash.

- [ ] **Step 6: Commit Task 2**

```bash
git add \
  ScreenshotMaxxing/Persistence/CaptureLifecycleService.swift \
  ScreenshotMaxxingTests/ScreenshotMaxxingTests.swift
git commit -m "refactor: centralize missing capture removal"
```

Expected: commit succeeds.

### Task 3: Migrate deletion-domain tests away from History and metadata storage

**Files:**

- Modify: `ScreenshotMaxxingTests/ScreenshotMaxxingTests.swift:1525-1570`
- Modify: `ScreenshotMaxxingTests/ScreenshotMaxxingTests.swift:3370-3708`

**Interfaces:**

- Consumes: Tasks 1-2's two service methods.
- Produces: service-level coverage for known paths, linked edits, disk-only
  edits, missing originals, nonexistent files, and unrelated rows.

- [ ] **Step 1: Move the metadata-store deletion test**

Rename
`captureMetadataStoreDeletesCaptureHistoryAndTrashesLocalFiles()` to
`captureLifecycleServiceDeletesKnownLocalFilesAndMetadata()`.

Replace:

```swift
let store = CaptureMetadataStore(modelContainer: modelContainer)
try store.deleteCaptureFromHistoryAndDisk(
    capture,
    fileManager: fileManager,
    fileTrash: fileTrash
)
```

with:

```swift
let service = CaptureLifecycleService(
    fileManager: fileManager,
    fileTrash: fileTrash
)
try service.deleteCaptures(
    [capture],
    from: modelContainer.mainContext
)
```

Keep the existing assertions for original, edited, thumbnail, metadata, and
the spy Trash calls.

- [ ] **Step 2: Move missing-original and nonexistent-file tests**

In
`captureHistoryDeletionOfMissingOriginalDeletesLinkedExistingEditedCaptures()`,
replace the old call with:

```swift
let service = CaptureLifecycleService(
    fileManager: fileManager,
    fileTrash: fileTrash
)
try service.deleteCaptures(
    [missingOriginalCapture],
    from: modelContainer.mainContext
)
```

In `captureHistoryDeletionSkipsTrashForNonexistentFiles()`, replace the old
call with:

```swift
let service = CaptureLifecycleService(
    fileManager: fileManager,
    fileTrash: fileTrash
)
try service.deleteCaptures(
    [missingCapture],
    from: modelContainer.mainContext
)
```

Rename both tests with the `captureLifecycle` prefix.

- [ ] **Step 3: Keep selection tests presentation-only**

In `captureHistorySelectionAndDeletionUseFilteredResultSet()`, remove:

```swift
let capturesToDelete = CaptureHistoryData.capturesToDelete(
    from: captures,
    selectedIDs: selectedVisibleIDs
)
```

and replace its final deletion assertion with:

```swift
#expect(selectedVisibleIDs == Set([recordingCapture.id]))
```

Do not expose the service's recursive expansion helpers for this test.

- [ ] **Step 4: Format the migrated tests**

Run: `scripts/format.sh`

Expected: exit 0.

- [ ] **Step 5: Verify all deletion tests use the service**

Run: `scripts/test.sh unit`

Expected: exit 0; all deletion-domain tests call
`CaptureLifecycleService`.

Run:

```bash
rg -n 'CaptureHistoryData\\.(deleteCaptures|removeCapturesFromHistoryOnly|fileURLsToDelete|capturesToDelete)' \
  ScreenshotMaxxingTests
```

Expected: exit 1 with no matches.

- [ ] **Step 6: Commit Task 3**

```bash
git add ScreenshotMaxxingTests/ScreenshotMaxxingTests.swift
git commit -m "test: move deletion coverage to lifecycle service"
```

Expected: commit succeeds.

### Task 4: Route History mutations through the service

**Files:**

- Modify: `ScreenshotMaxxing/History/CaptureHistoryView.swift:12-30`
- Modify: `ScreenshotMaxxing/History/CaptureHistoryView.swift:356-392`

**Interfaces:**

- Consumes:
  `CaptureLifecycleService.deleteCaptures(_:from:)` and
  `removeMissingCapturesFromHistory(_:from:)`.
- Produces: one injected `captureLifecycleService` used by both History
  mutation actions.

- [ ] **Step 1: Add the service dependency**

Replace the stored dependencies and initializer with:

```swift
private let fileManager: FileManager
private let captureLifecycleService: CaptureLifecycleService
private let openCapture: (Capture) -> Void

init(
    fileManager: FileManager = .default,
    captureLifecycleService: CaptureLifecycleService? = nil,
    openCapture: @escaping (Capture) -> Void = { _ in }
) {
    self.fileManager = fileManager
    self.captureLifecycleService =
        captureLifecycleService ?? CaptureLifecycleService(fileManager: fileManager)
    self.openCapture = openCapture
}
```

- [ ] **Step 2: Replace both mutation calls**

Replace `deletePendingCaptures()` with:

```swift
private func deletePendingCaptures() {
    let selectedCaptures = captures.filter { pendingDeletionIDs.contains($0.id) }

    do {
        try captureLifecycleService.deleteCaptures(
            selectedCaptures,
            from: modelContext
        )
        selectedCaptureIDs.subtract(pendingDeletionIDs)
        pendingDeletionIDs.removeAll()
    } catch {
        deleteErrorMessage = error.localizedDescription
    }
}
```

Replace the `do` block in `removePendingMissingCapture()` with:

```swift
do {
    try captureLifecycleService.removeMissingCapturesFromHistory(
        [capture],
        from: modelContext
    )
    selectedCaptureIDs.remove(capture.id)
    self.pendingMetadataRemovalID = nil
} catch {
    deleteErrorMessage = error.localizedDescription
}
```

- [ ] **Step 3: Format the History call-site change**

Run: `scripts/format.sh`

Expected: exit 0.

- [ ] **Step 4: Verify the History call sites**

Run: `scripts/test.sh unit`

Expected: exit 0.

- [ ] **Step 5: Commit Task 4**

```bash
git add ScreenshotMaxxing/History/CaptureHistoryView.swift
git commit -m "refactor: route history deletion through lifecycle service"
```

Expected: commit succeeds.

### Task 5: Route both editor actions through the service

**Files:**

- Modify: `ScreenshotMaxxing/Editor/ScreenshotEditorView.swift:10-49`
- Modify: `ScreenshotMaxxing/Editor/ScreenshotEditorView.swift:257-288`
- Modify: `ScreenshotMaxxing/Video/VideoEditorView.swift:12-54`
- Modify: `ScreenshotMaxxing/Video/VideoEditorView.swift:255-305`

**Interfaces:**

- Consumes: `CaptureLifecycleService.deleteCaptures(_:from:)` and
  `PersistenceController.sharedModelContainer.mainContext`.
- Produces: one lifecycle-service dependency in each editor, used only after a
  successful clipboard write and non-nil `Capture`.

- [ ] **Step 1: Inject the service into the screenshot editor**

Add:

```swift
private let captureLifecycleService: CaptureLifecycleService
```

Add this parameter before `closeAction`:

```swift
captureLifecycleService: CaptureLifecycleService = CaptureLifecycleService(),
```

Assign it in the initializer:

```swift
self.captureLifecycleService = captureLifecycleService
```

Replace the nested deletion call with:

```swift
do {
    try captureLifecycleService.deleteCaptures(
        [capture],
        from: PersistenceController.sharedModelContainer.mainContext
    )
    statusMessage = EditorCopyAndTrashStatus.copiedAndMovedToTrashMessage(for: .image)
    closeAfterShowingSuccess()
} catch {
    statusMessage = EditorCopyAndTrashStatus.copiedButMoveToTrashFailedMessage(
        for: .image,
        errorDescription: error.localizedDescription
    )
}
```

- [ ] **Step 2: Inject the service into the video editor**

Add the same stored property and initializer parameter/assignment to
`VideoEditorView`. Replace its nested deletion call with:

```swift
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
```

Do not move either service call above the existing successful clipboard guard.

- [ ] **Step 3: Format the editor call-site changes**

Run: `scripts/format.sh`

Expected: exit 0.

- [ ] **Step 4: Verify the editor call sites**

Run: `scripts/test.sh unit`

Expected: exit 0.

Run:

```bash
rg -n 'CaptureMetadataStore\\(\\)\\.deleteCaptureFromHistoryAndDisk' \
  ScreenshotMaxxing/Editor/ScreenshotEditorView.swift \
  ScreenshotMaxxing/Video/VideoEditorView.swift
```

Expected: exit 1 with no matches.

- [ ] **Step 5: Commit Task 5**

```bash
git add \
  ScreenshotMaxxing/Editor/ScreenshotEditorView.swift \
  ScreenshotMaxxing/Video/VideoEditorView.swift
git commit -m "fix: unify editor copy and trash deletion"
```

Expected: commit succeeds.

### Task 6: Remove duplicate deletion implementations

**Files:**

- Modify: `ScreenshotMaxxing/Persistence/CaptureMetadataStore.swift:80-91`
- Modify: `ScreenshotMaxxing/Persistence/CaptureMetadataStore.swift:132-146`
- Modify: `ScreenshotMaxxing/History/CaptureHistoryData.swift:76-85`
- Modify: `ScreenshotMaxxing/History/CaptureHistoryData.swift:242-340`
- Modify: `ScreenshotMaxxing/History/CaptureHistoryData.swift:486-559`

**Interfaces:**

- Consumes: all callers and tests migrated in Tasks 3-5.
- Produces: `CaptureMetadataStore` with save behavior only and
  `CaptureHistoryData` with presentation/filtering behavior only.

- [ ] **Step 1: Delete metadata-store mutation code**

Delete the complete methods:

```swift
func deleteCaptureFromHistoryAndDisk(
    _ capture: Capture,
    fileManager: FileManager = .default,
    fileTrash: CaptureFileTrashing = FileManager.default
) throws

private func uniqueFilePaths(for capture: Capture) -> [String]
```

Do not change any `saveCapture`, `saveEditedCapture`, or
`saveEditedVideoCapture` method.

- [ ] **Step 2: Delete History-domain mutation code**

Delete `CaptureHistoryError` and these complete static methods from
`CaptureHistoryData`:

```swift
capturesToDelete(from:selectedIDs:)
deleteCaptures(_:from:allCaptures:fileManager:fileTrash:)
removeCapturesFromHistoryOnly(_:from:fileManager:)
fileURLsToDelete(for:allCaptures:fileManager:)
```

Delete private helpers that become unused:

```swift
editedVersionPrefixes(for:)
isEditedVersion(_:matchingAnyOf:)
editedVersionFileURLs(for:fileManager:)
editedDirectories(for:)
canonicalFileURL(_:)
```

Keep `filePaths(for:)` because `isEditedCapture(_:)` still uses it. Keep
`lastKnownFilePaths(for:)` because `storageFolderURL(for:fileManager:)` still
uses it.

- [ ] **Step 3: Prove the old API is gone**

Run: `scripts/format.sh`

Expected: exit 0.

Run: `scripts/test.sh unit`

Expected: exit 0.

Run:

```bash
rg -n \
  'deleteCaptureFromHistoryAndDisk|CaptureHistoryData\\.(deleteCaptures|removeCapturesFromHistoryOnly|fileURLsToDelete|capturesToDelete)' \
  ScreenshotMaxxing ScreenshotMaxxingTests
```

Expected: exit 1 with no matches.

- [ ] **Step 4: Commit Task 6**

```bash
git add \
  ScreenshotMaxxing/Persistence/CaptureMetadataStore.swift \
  ScreenshotMaxxing/History/CaptureHistoryData.swift
git commit -m "refactor: remove duplicate capture deletion paths"
```

Expected: commit succeeds.

### Task 7: Align copy, privacy, architecture, and changelog text

**Files:**

- Modify: `ScreenshotMaxxing/Editor/EditorToolbarAction.swift:46-75`
- Modify: `ScreenshotMaxxingTests/ScreenshotMaxxingTests.swift:382-423`
- Modify: `PRIVACY.md:50-54`
- Modify: `docs/ARCHITECTURE.md:65-72`
- Modify: `CHANGELOG.md:7-9`

**Interfaces:**

- Consumes: the shared linked-edit deletion behavior from Tasks 1-6.
- Produces: user-facing and architectural text that describes that behavior
  without claiming permanent or external deletion.

- [ ] **Step 1: Tighten the descriptor and status text**

Replace the Copy & Trash label with:

```swift
let label =
    "Copy \(mediaName) to clipboard, then move its local capture files and linked edited versions to Trash and remove them from History"
```

Replace the success message with:

```swift
"Copied \(mediaType.editorMediaName); moved related files to Trash and removed related History entries"
```

Update the existing test assertions to:

```swift
#expect(copyAndTrashAction.helpText.contains("linked edited versions"))
#expect(copyAndTrashAction.helpText.contains("remove them from History"))

#expect(
    EditorCopyAndTrashStatus.copiedAndMovedToTrashMessage(for: .image)
        == "Copied image; moved related files to Trash and removed related History entries"
)
#expect(
    EditorCopyAndTrashStatus.copiedAndMovedToTrashMessage(for: .video)
        == "Copied video; moved related files to Trash and removed related History entries"
)
```

- [ ] **Step 2: Replace the deletion privacy paragraph**

Replace `PRIVACY.md:52` with:

```markdown
When you delete captures from History or use Copy & Trash in an editor,
ScreenshotMaxxing attempts to move the selected capture's related local files,
linked edited versions, and thumbnails to macOS Trash and remove their History
metadata. macOS Trash, backups, sync tools, file recovery tools, or manually
copied files may retain separate copies outside the app's control.
```

- [ ] **Step 3: Update architecture ownership**

Replace `docs/ARCHITECTURE.md:67-70` with:

```markdown
- `Persistence/Capture.swift` is the SwiftData model for local capture metadata.
- `Persistence/CaptureMetadataStore.swift` creates and updates capture metadata.
- `Persistence/CaptureLifecycleService.swift` owns capture-file discovery, moves existing files to Trash, and removes SwiftData metadata.
- `History/CaptureHistoryView.swift` renders local history and delegates deletion to `CaptureLifecycleService`.
- `History/CaptureHistoryData.swift` centralizes history display, filtering, selection, and path-presentation helpers.
```

- [ ] **Step 4: Add the changelog entry**

Under `## Unreleased`, add:

```markdown
- Made History deletion and editor Copy & Trash consistently remove linked edited History entries and move their related local files to Trash.
```

- [ ] **Step 5: Format and run final gates**

Run: `scripts/format.sh`

Expected: exit 0.

Run: `scripts/lint.sh`

Expected: exit 0.

Run: `scripts/test.sh unit`

Expected: exit 0.

Run: `git diff --check`

Expected: exit 0 with no output.

Run:

```bash
rg -n 'CaptureLifecycleService|linked edited|Copy & Trash' \
  PRIVACY.md docs/ARCHITECTURE.md CHANGELOG.md \
  ScreenshotMaxxing/Editor/EditorToolbarAction.swift
```

Expected: every changed contract is represented in the output.

- [ ] **Step 6: Commit Task 7**

```bash
git add \
  ScreenshotMaxxing/Editor/EditorToolbarAction.swift \
  ScreenshotMaxxingTests/ScreenshotMaxxingTests.swift \
  PRIVACY.md \
  docs/ARCHITECTURE.md \
  CHANGELOG.md
git commit -m "docs: align linked capture deletion behavior"
```

Expected: commit succeeds.

- [ ] **Step 7: Update the plan index**

Change Plan 002's status in `docs/plans/README.md` from `TODO` to `DONE` only after
all Done criteria below pass. Do not include the index in a source commit
unless the operator explicitly requested plan-file commits.

## Test plan

The service tests, not SwiftUI interaction tests, are the regression anchor.
They must prove the behavior shared by all callers.

Required cases:

1. Single original input expands to linked edited metadata and disk files.
2. Known original/edited/thumbnail paths are unique and trashed.
3. Missing original still removes existing linked files and metadata.
4. Nonexistent files are not sent to Trash.
5. Unrelated captures survive.
6. Metadata-only removal rejects a file that reappears.
7. Metadata-only removal performs no Trash calls.
8. Copy & Trash descriptor tells the truth about linked edits.

## Done criteria

- [ ] `rg -n 'captureLifecycleService\\.(deleteCaptures|removeMissingCapturesFromHistory)' ScreenshotMaxxing/History/CaptureHistoryView.swift ScreenshotMaxxing/Editor/ScreenshotEditorView.swift ScreenshotMaxxing/Video/VideoEditorView.swift` finds both History paths and both editor deletion paths.
- [ ] Callers do not provide a possibly filtered `allCaptures` array.
- [ ] `rg -n 'deleteCaptureFromHistoryAndDisk' ScreenshotMaxxing ScreenshotMaxxingTests` exits 1.
- [ ] `rg -n 'CaptureHistoryData\\.(deleteCaptures|removeCapturesFromHistoryOnly|fileURLsToDelete|capturesToDelete)' ScreenshotMaxxing ScreenshotMaxxingTests` exits 1.
- [ ] Copy & Trash removes linked edited rows/files under the same rules as
      History deletion.
- [ ] Clipboard success still precedes deletion.
- [ ] Privacy, architecture, toolbar copy, and changelog match behavior.
- [ ] `scripts/lint.sh` exits 0.
- [ ] `scripts/test.sh unit` exits 0 with all eight deletion/copy cases.
- [ ] `git diff --check` exits 0.
- [ ] `git status --short` lists no SwiftData schema, migration, or out-of-scope source file changes.
- [ ] The `docs/plans/README.md` row is updated.

## STOP conditions

Stop and report if:

- Product direction requires editor Copy & Trash to preserve linked edited
  versions while History deletes them.
- Live code has introduced an explicit parent/child identifier or SwiftData
  relationship that supersedes filename lineage.
- Moving the behavior requires a SwiftData schema migration.
- `ModelContext.fetch(FetchDescriptor<Capture>())` cannot safely fetch the
  complete capture set for this local app.
- The change would permanently delete files instead of moving them to Trash.
- A test requires asserting deletion from Trash, backups, or external sync.
- An in-scope test fails twice for an unrelated reason.

## Maintenance notes

- Filename lineage remains a pragmatic compatibility mechanism. A future
  schema migration may replace it, but all callers should still go through
  `CaptureLifecycleService`.
- Reviewers should scrutinize copy-before-delete ordering and the exact file
  set sent to Trash.
- Never strengthen privacy claims to imply secure erasure.
- Any future bulk-delete, retention, or cleanup feature must call this service
  rather than reimplement discovery.
