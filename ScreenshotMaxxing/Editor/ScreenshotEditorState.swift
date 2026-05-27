//
//  ScreenshotEditorState.swift
//  ScreenshotMaxxing
//
//  Created by Ben Kramer on 5/26/26.
//

import CoreGraphics
import Foundation

struct ScreenshotEditorState: Equatable {
    let originalImageURL: URL
    var selectedTool: EditorTool
    var annotations: [Annotation]

    init(
        originalImageURL: URL,
        selectedTool: EditorTool = .blur,
        annotations: [Annotation] = []
    ) {
        self.originalImageURL = originalImageURL
        self.selectedTool = selectedTool
        self.annotations = annotations
    }

    @discardableResult
    mutating func addBlurRect(_ rect: CGRect, id: UUID = UUID()) -> Annotation? {
        guard rect.width > 0, rect.height > 0 else {
            return nil
        }

        let annotation = Annotation(id: id, type: .blur, rect: rect)
        annotations.append(annotation)
        return annotation
    }

    mutating func removeAnnotation(id: UUID) {
        annotations.removeAll { $0.id == id }
    }

    mutating func undoLastAnnotation() {
        _ = annotations.popLast()
    }
}
