# ScreenshotMaxxing PRD / Build Plan

## Product Summary

ScreenshotMaxxing is a native macOS screenshot utility. It lives in the menu bar, supports keyboard shortcuts, captures areas/windows/fullscreen, opens screenshots in a lightweight editor, supports privacy-safe blur/pixelation redaction, and stores captures locally with metadata.

## Technical Direction

- Platform: macOS
- Template: macOS App
- Language: Swift
- Interface: SwiftUI
- System integration: AppKit
- Persistence: SwiftData for metadata
- Image files: stored on disk
- Image rendering: CoreImage / CoreGraphics
- Initial capture mechanism: macOS `screencapture`
- Later capture mechanism: custom overlay or ScreenCaptureKit if needed

## Product Principles

- Fast capture comes before feature depth.
- The app should feel like a Mac utility, not a document editor.
- Screenshots are local-first.
- Image files stay on disk; metadata stays in SwiftData.
- Redaction must modify exported pixels, not just overlay a visual effect.
- Prefer small working vertical slices over broad unfinished systems.

## V1 Scope

### In Scope

- Menu bar app
- Capture area
- Capture window
- Capture fullscreen
- Editor window after capture
- Blur/pixelate redaction rectangle
- Basic annotation primitives
- Copy edited image
- Save edited image
- Local capture history
- SwiftData metadata
- Configurable capture shortcut, at least for area capture

### Out Of Scope For V1

- Cloud sync
- Accounts
- Video recording
- GIF recording
- Scrolling capture
- OCR
- Sharing links
- Team workflows
- Browser extension
- Advanced library search
- App Store release polish

## Data Model

### Capture Metadata

Use SwiftData for capture metadata.

```swift
@Model
final class Capture {
    var id: UUID
    var createdAt: Date
    var fileName: String
    var captureMode: String
    var width: Int
    var height: Int
    var originalFilePath: String
    var editedFilePath: String?
    var favorite: Bool

    init(
        id: UUID = UUID(),
        createdAt: Date = Date(),
        fileName: String,
        captureMode: String,
        width: Int,
        height: Int,
        originalFilePath: String,
        editedFilePath: String? = nil,
        favorite: Bool = false
    ) {
        self.id = id
        self.createdAt = createdAt
        self.fileName = fileName
        self.captureMode = captureMode
        self.width = width
        self.height = height
        self.originalFilePath = originalFilePath
        self.editedFilePath = editedFilePath
        self.favorite = favorite
    }
}
```

### File Storage

Store image files outside SwiftData.

Recommended location:

```text
~/Library/Application Support/ScreenshotMaxxing/Captures/
  originals/
  edited/
```

## Suggested Project Structure

```text
ScreenshotMaxxing/
  ScreenshotMaxxingApp.swift
  AppDelegate.swift

  MenuBar/
    MenuBarController.swift

  Capture/
    CaptureController.swift
    CaptureMode.swift
    CaptureFileStore.swift

  Editor/
    ScreenshotEditorView.swift
    EditorTool.swift
    Annotation.swift
    AnnotationCanvas.swift
    ImageRenderer.swift

  History/
    CaptureHistoryView.swift
    CapturePreviewView.swift

  Persistence/
    Capture.swift

  Shortcuts/
    HotKeyManager.swift
    ShortcutRecorderView.swift

  Preferences/
    PreferencesView.swift

  Utilities/
    FileLocations.swift
    Image+PNG.swift
```

## Build TODOs

| ID | Status | Chunk | Goal | Done When |
|---|---|---|---|---|
| 1 | Done | Project cleanup | Remove starter/sample code and establish folders | App builds after cleanup |
| 2 | Done | App shell | Add AppKit app delegate to SwiftUI app | App launches normally |
| 3 | Done | Menu bar | Add menu bar status item with basic menu | Menu shows Capture Area, Capture Window, Capture Fullscreen, History, Preferences, Quit |
| 4 | Done | Capture file storage | Create app support folders for original/edited captures | App can create and write to capture folders |
| 5 | Done | Area capture | Invoke macOS area selection and save PNG | Dragging an area creates a screenshot file |
| 6 | Done | Window/fullscreen capture | Add remaining capture modes | All three capture modes produce files |
| 7 | Done | SwiftData capture model | Replace starter model with `Capture` | Successful captures create persisted metadata |
| 8 | Done | Editor window | Open captured image in editor window | Capture immediately displays in editor |
| 9 | Done | Editor canvas | Display screenshot with correct scaling | Image fits window without distortion |
| 10 | Done | Blur annotation model | Represent blur rectangles separately from image pixels | Drawing state stores one or more blur rects |
| 11 | Pending | Draw blur rectangles | Let user drag to place blur regions | User can draw visible blur selection rectangles |
| 12 | Pending | Render redactions | Bake blur into exported bitmap | Saved/copied image contains actual blurred pixels |
| 13 | Pending | Copy action | Copy edited image to clipboard | Paste into another app shows edited image |
| 14 | Pending | Save action | Save edited image to `edited/` folder | Edited file path is written and metadata updates |
| 15 | Pending | Basic history | Show recent captures from SwiftData | Relaunch app and previous captures still appear |
| 16 | Pending | Reopen from history | Open a past capture in viewer/editor | Clicking history item opens its image |
| 17 | Pending | Global hotkey | Register default capture-area shortcut | Keyboard shortcut starts area capture |
| 18 | Pending | Preferences | Show shortcut and default save settings | Preferences window opens and displays app settings |
| 19 | Pending | Shortcut configuration | Let user change area capture shortcut | New shortcut persists and works after relaunch |
| 20 | Pending | Polish pass | Improve empty states, errors, menu labels, window titles | App feels coherent for local daily use |

## Chunk Details

### 1. Project Cleanup

Remove Xcode starter demo code that is not part of the app.

Tasks:

- Delete or repurpose starter `Item` model if SwiftData created one.
- Remove sample list views.
- Add initial folder structure.
- Confirm app builds.

### 2. App Shell

Add AppKit lifecycle integration.

Tasks:

- Keep SwiftUI `App` entry point.
- Add `NSApplicationDelegateAdaptor`.
- Create `AppDelegate`.
- Decide whether Dock icon stays visible during development.
- Later, set app activation policy for menu-bar-only behavior if desired.

### 3. Menu Bar

Create the first real product surface.

Tasks:

- Create `MenuBarController`.
- Add `NSStatusItem`.
- Add menu items:
  - Capture Area
  - Capture Window
  - Capture Fullscreen
  - Open History
  - Preferences
  - Quit
- Wire menu items to placeholder actions first.

### 4. Capture File Storage

Create a stable local storage location.

Tasks:

- Add `FileLocations`.
- Ensure app support directory exists.
- Ensure `originals/` and `edited/` folders exist.
- Generate unique filenames.

### 5. Area Capture

Implement first capture path.

Tasks:

- Create `CaptureController`.
- Use `/usr/sbin/screencapture`.
- For area capture, use interactive selection.
- Save output PNG to `originals/`.
- Handle cancellation cleanly.

Suggested initial command:

```sh
/usr/sbin/screencapture -i -s -x path/to/output.png
```

### 6. Window And Fullscreen Capture

Add complete capture coverage.

Tasks:

- Add `CaptureMode`.
- Add window capture.
- Add fullscreen capture.
- Normalize image loading after all capture modes.

Suggested commands:

```sh
/usr/sbin/screencapture -i -w -x path/to/output.png
/usr/sbin/screencapture -x path/to/output.png
```

### 7. SwiftData Capture Model

Persist capture metadata.

Tasks:

- Define `Capture`.
- Register model container.
- On capture success, read image dimensions.
- Insert capture metadata into SwiftData.
- Save context.

### 8. Editor Window

Open a screenshot immediately after capture.

Tasks:

- Create editor view.
- Pass captured image/file URL into editor.
- Open editor in a separate window.
- Set useful title and minimum size.

### 9. Editor Canvas

Render the screenshot correctly.

Tasks:

- Display image preserving aspect ratio.
- Track conversion between view coordinates and image coordinates.
- Prepare for annotations to be stored in image-space coordinates.

Important rule:

- Store annotation rectangles in image coordinates, not screen/view coordinates.

### 10. Blur Annotation Model

Define editor state.

Tasks:

- Add `EditorTool`.
- Add `Annotation`.
- Support at least `blurRect`.
- Keep original image immutable.
- Store current annotations in editor state.

Example:

```swift
enum EditorTool {
    case select
    case blur
    case rectangle
    case arrow
    case text
}

struct Annotation: Identifiable {
    var id: UUID
    var type: AnnotationType
    var rect: CGRect
}

enum AnnotationType {
    case blur
    case rectangle
    case arrow
    case text(String)
}
```

### 11. Draw Blur Rectangles

Let user create redaction regions.

Tasks:

- Add drag gesture to editor canvas.
- When blur tool is active, create rectangle from drag start/end.
- Show rectangle overlay while dragging.
- Add completed blur annotation on mouse up.
- Support delete/undo soon after.

### 12. Render Redactions

Bake redactions into actual pixels.

Tasks:

- Add `ImageRenderer`.
- Convert original image to `CIImage`.
- Apply Gaussian blur or pixelation.
- Crop blurred image to each redaction rectangle.
- Composite blurred region over original.
- Export PNG.

Acceptance requirement:

- The saved/copied image must contain blurred pixels even when opened outside the app.

### 13. Copy Action

Add clipboard export.

Tasks:

- Render current editor state.
- Put final image onto `NSPasteboard`.
- Show lightweight success state.

### 14. Save Action

Add edited file output.

Tasks:

- Render current editor state.
- Save PNG to `edited/`.
- Update `Capture.editedFilePath`.
- Keep original file unchanged.

### 15. Basic History

Create local capture history.

Tasks:

- Query captures with SwiftData.
- Show newest first.
- Display thumbnail, date, mode, dimensions.
- Handle missing files gracefully.

### 16. Reopen From History

Make history useful.

Tasks:

- Click capture row.
- Open original or edited image.
- Prefer edited image if present, but allow original later.

### 17. Global Hotkey

Add fast capture.

Tasks:

- Register default global shortcut for area capture.
- Suggested default: `Command+Shift+2`.
- Use Carbon hotkey APIs or a small Swift package if preferred.
- Handle registration failure.

### 18. Preferences

Add basic settings.

Tasks:

- Preferences window opens from menu.
- Display current shortcut.
- Display storage location.
- Add button to reveal capture folder in Finder.

### 19. Shortcut Configuration

Make shortcut configurable.

Tasks:

- Add shortcut recorder UI.
- Persist shortcut in UserDefaults.
- Re-register hotkey after change.
- Validate shortcut has at least one modifier.

### 20. Polish Pass

Make it usable.

Tasks:

- Error handling for missing screen recording permission.
- Friendly behavior when capture is canceled.
- Window titles.
- Disabled toolbar states.
- Empty history state.
- Sensible default sizes.
- Basic keyboard commands:
  - Escape closes/cancels
  - Command+C copies
  - Command+S saves
  - Delete removes selected annotation
  - Command+Z undo

## Recommended First Vertical Slice

Do these first, in order:

1. Project cleanup
2. App shell
3. Menu bar
4. Capture file storage
5. Area capture
6. SwiftData capture model
7. Editor window
8. Editor canvas
9. Blur annotation model
10. Draw blur rectangles
11. Render redactions
12. Copy action
13. Save action

After that, add history, shortcuts, preferences, and polish.

## Acceptance Criteria For First Milestone

The first milestone is complete when:

- App launches.
- Menu bar icon appears.
- User can choose Capture Area.
- User can drag-select part of the screen.
- Screenshot opens in editor.
- User can draw a blur rectangle.
- User can copy the edited image.
- User can save the edited image.
- Capture metadata persists in SwiftData.
- Original screenshot file remains unchanged.
