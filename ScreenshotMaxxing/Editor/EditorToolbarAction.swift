//
//  EditorToolbarAction.swift
//  ScreenshotMaxxing
//

import Foundation

struct EditorToolbarActionDescriptor: Equatable {
    enum VisualRole: Equatable {
        case standard
        case destructive
    }

    let systemImageName: String
    let visibleTitle: String?
    let accessibilityLabel: String
    let helpText: String
    let visualRole: VisualRole

    static func copyEdited(_ mediaType: CaptureMediaType) -> EditorToolbarActionDescriptor {
        let mediaName = mediaType.editorMediaName
        let label = "Save edited \(mediaName) and copy it to the clipboard"

        return EditorToolbarActionDescriptor(
            systemImageName: "doc.on.doc",
            visibleTitle: nil,
            accessibilityLabel: label,
            helpText: label,
            visualRole: .standard
        )
    }

    static func saveEdited(_ mediaType: CaptureMediaType) -> EditorToolbarActionDescriptor {
        let mediaName = mediaType.editorMediaName
        let label = "Save edited \(mediaName), reveal it in Finder, and copy the file path"

        return EditorToolbarActionDescriptor(
            systemImageName: "square.and.arrow.down",
            visibleTitle: nil,
            accessibilityLabel: label,
            helpText: label,
            visualRole: .standard
        )
    }

    static func copyAndMoveToTrash(_ mediaType: CaptureMediaType) -> EditorToolbarActionDescriptor {
        let mediaName = mediaType.editorMediaName
        let label =
            "Copy \(mediaName) to clipboard, then move its local capture files to Trash and remove it from History"

        return EditorToolbarActionDescriptor(
            systemImageName: "trash",
            visibleTitle: "Copy & Trash",
            accessibilityLabel: label,
            helpText: label,
            visualRole: .destructive
        )
    }
}

enum EditorCopyAndTrashStatus {
    static func copiedWithoutCaptureMessage(for mediaType: CaptureMediaType) -> String {
        "Copied \(mediaType.editorMediaName) to clipboard"
    }

    static func copiedAndMovedToTrashMessage(for mediaType: CaptureMediaType) -> String {
        "Copied \(mediaType.editorMediaName); moved files to Trash and removed History entry"
    }

    static func copiedButMoveToTrashFailedMessage(
        for mediaType: CaptureMediaType,
        errorDescription: String
    ) -> String {
        "Copied \(mediaType.editorMediaName), but moving files to Trash or removing History failed: \(errorDescription)"
    }
}

private extension CaptureMediaType {
    var editorMediaName: String {
        switch self {
        case .image:
            "image"
        case .video:
            "video"
        }
    }
}
