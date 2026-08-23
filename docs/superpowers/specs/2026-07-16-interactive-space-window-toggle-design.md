# Interactive Area/Window Toggle Design

## Goal

Make screenshot capture launched through **Capture Area** start in drag-selection mode while allowing Space to toggle between area and window targeting in both directions, matching the native macOS screenshot interaction.

## Design

Keep the existing `CaptureController` and `CaptureMode` boundaries. Change only the arguments produced for `CaptureMode.area`: replace the `-s` option, which locks `screencapture` to mouse selection, with `-Jselection`, which starts interactive capture in selection mode without disabling the native Space-key toggle.

The resulting command is:

```text
/usr/sbin/screencapture -i -Jselection -x <output-path>
```

Dedicated **Capture Window** remains unchanged and continues to use `-w`, so it starts and stays in window-selection mode.

## Data Flow

The output path and post-capture flow do not change. `screencapture` writes to the existing unique file URL, `CaptureController` verifies that the file exists, and `AppCaptureOrchestrator` persists the capture and opens the screenshot editor.

Captures launched through **Capture Area** retain `.area` as their result mode, filename prefix, and History metadata even when the user presses Space and ultimately selects a window. The command-line tool does not report the final interactive selection mode, and accurate classification is outside this change's scope.

Escape and other no-output outcomes continue to use the existing cancellation handling.

## Testing

Use test-driven development:

1. Change the focused argument tests to require `["-i", "-Jselection", "-x", outputPath]` for area capture and verify that they fail against the current `-s` behavior.
2. Make the minimal production change in `CaptureMode`.
3. Run the deterministic unit-test script and formatting check.

The native `screencapture` process owns Space-key handling, so the automated regression boundary is the command configuration that enables it.

## Documentation

Add an Unreleased changelog entry describing the user-visible Space-key toggle. No privacy, permissions, storage, architecture, or support contract changes are required.
