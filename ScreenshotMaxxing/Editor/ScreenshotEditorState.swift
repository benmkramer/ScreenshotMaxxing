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
    static let minimumStrokeLineWidth = AnnotationStrokeStyle.minimumLineWidth
    static let maximumStrokeLineWidth = AnnotationStrokeStyle.maximumLineWidth
    static let strokeSelectionHitPadding: CGFloat = 6

    let originalImageURL: URL
    var selectedTool: EditorTool
    var annotations: [Annotation]
    var selectedAnnotationID: UUID?
    var strokeToolSettings: StrokeToolSettings

    var selectedAnnotationUsesStrokeStyle: Bool {
        guard let selectedAnnotationID,
              case .stroke = annotation(id: selectedAnnotationID)?.type else {
            return false
        }

        return true
    }

    var selectedStrokeColor: AnnotationColor {
        selectedStrokeStyle.color
    }

    var selectedStrokeLineWidth: CGFloat {
        selectedStrokeStyle.lineWidth
    }

    init(
        originalImageURL: URL,
        selectedTool: EditorTool = .blur,
        annotations: [Annotation] = [],
        selectedAnnotationID: UUID? = nil,
        strokeToolSettings: StrokeToolSettings = .defaultSettings
    ) {
        self.originalImageURL = originalImageURL
        self.selectedTool = selectedTool
        self.annotations = annotations
        self.selectedAnnotationID = selectedAnnotationID
        self.strokeToolSettings = strokeToolSettings.normalized
    }

    @discardableResult
    mutating func addBlurRect(_ rect: CGRect, id: UUID = UUID()) -> Annotation? {
        guard rect.width > 0, rect.height > 0 else {
            return nil
        }

        let annotation = Annotation(id: id, type: .blur, rect: rect)
        annotations.append(annotation)
        selectAnnotation(id: annotation.id)
        return annotation
    }

    @discardableResult
    mutating func addStroke(
        kind: AnnotationStrokeKind,
        points: [CGPoint],
        color: AnnotationColor,
        lineWidth: CGFloat,
        id: UUID = UUID()
    ) -> Annotation? {
        let clampedLineWidth = AnnotationStrokeStyle.clampedLineWidth(lineWidth)
        let stroke = AnnotationStroke(
            kind: kind,
            points: points,
            color: color,
            lineWidth: clampedLineWidth
        )

        guard stroke.points.count >= 2, stroke.hasVisibleLength else {
            return nil
        }

        let annotation = Annotation(id: id, type: .stroke(stroke), rect: stroke.visibleBounds)
        annotations.append(annotation)
        strokeToolSettings.update(stroke.style, for: kind)
        selectAnnotation(id: annotation.id)
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
        selectAnnotation(id: annotationID)
        return annotationID
    }

    func annotationID(containing imagePoint: CGPoint) -> UUID? {
        annotations.reversed().first { annotation in
            switch annotation.type {
            case .blur:
                annotation.rect.standardized.contains(imagePoint)
            case .stroke(let stroke):
                stroke.contains(imagePoint, hitPadding: Self.strokeSelectionHitPadding)
            case .rectangle, .arrow, .text:
                false
            }
        }?.id
    }

    func annotation(id: UUID) -> Annotation? {
        annotations.first { $0.id == id }
    }

    mutating func moveAnnotation(id: UUID, from originalRect: CGRect, by translation: CGSize, within imageSize: CGSize) {
        guard let annotation = annotation(id: id) else {
            return
        }

        moveAnnotation(id: id, from: annotation.withRect(originalRect), by: translation, within: imageSize)
    }

    mutating func moveAnnotation(id: UUID, from originalAnnotation: Annotation, by translation: CGSize, within imageSize: CGSize) {
        let imageBounds = CGRect(origin: .zero, size: imageSize)
        let movedRect = originalAnnotation.rect.offsetBy(dx: translation.width, dy: translation.height)

        updateAnnotation(id: id, from: originalAnnotation, to: movedRect.clamped(within: imageBounds))
    }

    mutating func resizeAnnotation(
        id: UUID,
        from originalRect: CGRect,
        handle: AnnotationResizeHandle,
        by translation: CGSize,
        within imageSize: CGSize
    ) {
        guard let annotation = annotation(id: id) else {
            return
        }

        resizeAnnotation(id: id, from: annotation.withRect(originalRect), handle: handle, by: translation, within: imageSize)
    }

    mutating func resizeAnnotation(
        id: UUID,
        from originalAnnotation: Annotation,
        handle: AnnotationResizeHandle,
        by translation: CGSize,
        within imageSize: CGSize
    ) {
        let imageBounds = CGRect(origin: .zero, size: imageSize)
        let resizedRect = originalAnnotation.rect.resized(
            by: translation,
            handle: handle,
            within: imageBounds,
            minimumSideLength: Self.minimumAnnotationSideLength
        )

        updateAnnotation(id: id, from: originalAnnotation, to: resizedRect)
    }

    mutating func undoLastAnnotation() {
        let removedAnnotation = annotations.popLast()

        if selectedAnnotationID == removedAnnotation?.id {
            selectedAnnotationID = nil
        }
    }

    mutating func updateSelectedStrokeColor(_ color: AnnotationColor) {
        let kind = activeStrokeStyleKind ?? .pen
        var style = selectedStrokeStyle
        style.color = color
        strokeToolSettings.update(style, for: kind)
        updateSelectedStroke { stroke in
            stroke.color = color
        }
    }

    mutating func updateSelectedStrokeLineWidth(_ lineWidth: CGFloat) {
        let kind = activeStrokeStyleKind ?? .pen
        let clampedLineWidth = AnnotationStrokeStyle.clampedLineWidth(lineWidth)
        var style = selectedStrokeStyle
        style.lineWidth = clampedLineWidth
        strokeToolSettings.update(style, for: kind)
        updateSelectedStroke { stroke in
            stroke.lineWidth = clampedLineWidth
        }
    }

    func strokeStyle(for kind: AnnotationStrokeKind) -> AnnotationStrokeStyle {
        strokeToolSettings.style(for: kind)
    }

    private mutating func updateAnnotation(id: UUID, from originalAnnotation: Annotation, to rect: CGRect) {
        guard let annotationIndex = annotations.firstIndex(where: { $0.id == id }) else {
            return
        }

        switch originalAnnotation.type {
        case .stroke(var stroke):
            stroke.transformPoints(from: originalAnnotation.rect, to: rect)
            annotations[annotationIndex].type = .stroke(stroke)
            annotations[annotationIndex].rect = stroke.visibleBounds
        case .blur, .rectangle, .arrow, .text:
            annotations[annotationIndex].rect = rect
        }

        selectedAnnotationID = id
    }

    private mutating func updateSelectedStroke(_ update: (inout AnnotationStroke) -> Void) {
        guard let selectedAnnotationID,
              let annotationIndex = annotations.firstIndex(where: { $0.id == selectedAnnotationID }),
              case .stroke(var stroke) = annotations[annotationIndex].type else {
            return
        }

        update(&stroke)
        annotations[annotationIndex].type = .stroke(stroke)
        annotations[annotationIndex].rect = stroke.visibleBounds
    }

    private func selectedStrokeAnnotation() -> AnnotationStroke? {
        guard let selectedAnnotationID,
              case .stroke(let stroke) = annotation(id: selectedAnnotationID)?.type else {
            return nil
        }

        return stroke
    }

    private var activeStrokeStyleKind: AnnotationStrokeKind? {
        selectedStrokeAnnotation()?.kind ?? selectedTool.strokeKind
    }

    private var selectedStrokeStyle: AnnotationStrokeStyle {
        if let selectedStroke = selectedStrokeAnnotation() {
            return selectedStroke.style
        }

        guard let strokeKind = selectedTool.strokeKind else {
            return strokeToolSettings.style(for: .pen)
        }

        return strokeToolSettings.style(for: strokeKind)
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
