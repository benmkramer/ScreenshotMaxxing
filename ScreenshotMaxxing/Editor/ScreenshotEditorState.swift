//
//  ScreenshotEditorState.swift
//  ScreenshotMaxxing
//
//  Created by Ben Kramer on 5/26/26.
//

import CoreGraphics
import Foundation

enum AnnotationResizeHandle: CaseIterable, Hashable {
    case topLeft
    case top
    case topRight
    case right
    case bottomRight
    case bottom
    case bottomLeft
    case left
}

struct ScreenshotEditorState: Equatable {
    static let minimumAnnotationSideLength: CGFloat = 8

    let originalImageURL: URL
    var selectedTool: EditorTool
    var annotations: [Annotation]
    var selectedAnnotationID: UUID?

    init(
        originalImageURL: URL,
        selectedTool: EditorTool = .blur,
        annotations: [Annotation] = [],
        selectedAnnotationID: UUID? = nil
    ) {
        self.originalImageURL = originalImageURL
        self.selectedTool = selectedTool
        self.annotations = annotations
        self.selectedAnnotationID = selectedAnnotationID
    }

    @discardableResult
    mutating func addBlurRect(_ rect: CGRect, id: UUID = UUID()) -> Annotation? {
        guard rect.width > 0, rect.height > 0 else {
            return nil
        }

        let annotation = Annotation(id: id, type: .blur, rect: rect)
        annotations.append(annotation)
        selectedAnnotationID = annotation.id
        return annotation
    }

    mutating func removeAnnotation(id: UUID) {
        annotations.removeAll { $0.id == id }
        if selectedAnnotationID == id {
            selectedAnnotationID = nil
        }
    }

    mutating func removeSelectedAnnotation() {
        guard let selectedAnnotationID else {
            return
        }

        removeAnnotation(id: selectedAnnotationID)
    }

    mutating func selectAnnotation(id: UUID?) {
        selectedAnnotationID = id
    }

    @discardableResult
    mutating func selectAnnotation(containing imagePoint: CGPoint) -> UUID? {
        let annotationID = annotationID(containing: imagePoint)
        selectedAnnotationID = annotationID
        return annotationID
    }

    func annotationID(containing imagePoint: CGPoint) -> UUID? {
        annotations.reversed().first { annotation in
            annotation.type == .blur && annotation.rect.standardized.contains(imagePoint)
        }?.id
    }

    func annotation(id: UUID) -> Annotation? {
        annotations.first { $0.id == id }
    }

    mutating func moveAnnotation(id: UUID, from originalRect: CGRect, by translation: CGSize, within imageSize: CGSize) {
        let imageBounds = CGRect(origin: .zero, size: imageSize)
        let movedRect = originalRect.offsetBy(dx: translation.width, dy: translation.height)

        updateAnnotation(id: id, rect: movedRect.clamped(within: imageBounds))
    }

    mutating func resizeAnnotation(
        id: UUID,
        from originalRect: CGRect,
        handle: AnnotationResizeHandle,
        by translation: CGSize,
        within imageSize: CGSize
    ) {
        let imageBounds = CGRect(origin: .zero, size: imageSize)
        let resizedRect = originalRect.resized(
            by: translation,
            handle: handle,
            within: imageBounds,
            minimumSideLength: Self.minimumAnnotationSideLength
        )

        updateAnnotation(id: id, rect: resizedRect)
    }

    mutating func undoLastAnnotation() {
        let removedAnnotation = annotations.popLast()

        if selectedAnnotationID == removedAnnotation?.id {
            selectedAnnotationID = nil
        }
    }

    private mutating func updateAnnotation(id: UUID, rect: CGRect) {
        guard let annotationIndex = annotations.firstIndex(where: { $0.id == id }) else {
            return
        }

        annotations[annotationIndex].rect = rect
        selectedAnnotationID = id
    }
}

private extension CGRect {
    func clamped(within bounds: CGRect) -> CGRect {
        let rect = standardized
        let bounds = bounds.standardized

        guard bounds.width > 0, bounds.height > 0 else {
            return rect
        }

        let clampedSize = CGSize(
            width: min(rect.width, bounds.width),
            height: min(rect.height, bounds.height)
        )
        let x = min(max(rect.minX, bounds.minX), bounds.maxX - clampedSize.width)
        let y = min(max(rect.minY, bounds.minY), bounds.maxY - clampedSize.height)

        return CGRect(origin: CGPoint(x: x, y: y), size: clampedSize)
    }

    func resized(
        by translation: CGSize,
        handle: AnnotationResizeHandle,
        within bounds: CGRect,
        minimumSideLength: CGFloat
    ) -> CGRect {
        let rect = standardized
        let bounds = bounds.standardized

        guard bounds.width > 0, bounds.height > 0 else {
            return rect
        }

        let minimumWidth = min(minimumSideLength, bounds.width)
        let minimumHeight = min(minimumSideLength, bounds.height)
        var minX = rect.minX
        var minY = rect.minY
        var maxX = rect.maxX
        var maxY = rect.maxY

        switch handle {
        case .topLeft, .left, .bottomLeft:
            minX = clamped(rect.minX + translation.width, minimum: bounds.minX, maximum: maxX - minimumWidth)
        case .top, .bottom:
            break
        case .topRight, .right, .bottomRight:
            maxX = clamped(rect.maxX + translation.width, minimum: minX + minimumWidth, maximum: bounds.maxX)
        }

        switch handle {
        case .topLeft, .top, .topRight:
            minY = clamped(rect.minY + translation.height, minimum: bounds.minY, maximum: maxY - minimumHeight)
        case .left, .right:
            break
        case .bottomLeft, .bottom, .bottomRight:
            maxY = clamped(rect.maxY + translation.height, minimum: minY + minimumHeight, maximum: bounds.maxY)
        }

        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }

    private func clamped(_ value: CGFloat, minimum: CGFloat, maximum: CGFloat) -> CGFloat {
        let lowerBound = min(minimum, maximum)
        let upperBound = max(minimum, maximum)

        return min(max(value, lowerBound), upperBound)
    }
}
