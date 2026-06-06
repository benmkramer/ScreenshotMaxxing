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
    static let arrowSelectionHitPadding: CGFloat = 6
    static let minimumBlurRadius = AnnotationBlur.minimumRadius
    static let maximumBlurRadius = AnnotationBlur.maximumRadius

    let originalImageURL: URL
    var selectedTool: EditorTool
    var annotations: [Annotation]
    var selectedAnnotationID: UUID?
    var strokeToolSettings: StrokeToolSettings
    var blurToolSettings: AnnotationBlur
    var rectangleToolSettings: AnnotationRectangle
    var textToolSettings: AnnotationText

    var selectedAnnotationUsesStrokeStyle: Bool {
        guard let selectedAnnotationID,
              let annotation = annotation(id: selectedAnnotationID) else {
            return false
        }

        switch annotation.type {
        case .stroke, .arrow:
            return true
        case .blur, .rectangle, .text:
            return false
        }
    }

    var selectedAnnotationUsesBlurStyle: Bool {
        guard let selectedAnnotationID,
              let annotation = annotation(id: selectedAnnotationID) else {
            return false
        }

        switch annotation.type {
        case .blur:
            return true
        case .stroke, .arrow, .rectangle, .text:
            return false
        }
    }

    var selectedAnnotationUsesTextContent: Bool {
        guard let selectedAnnotationID,
              case .text = annotation(id: selectedAnnotationID)?.type else {
            return false
        }

        return true
    }

    var selectedAnnotationUsesRectangleStyle: Bool {
        guard let selectedAnnotationID,
              case .rectangle = annotation(id: selectedAnnotationID)?.type else {
            return false
        }

        return true
    }

    var selectedAnnotationUsesTextStyle: Bool {
        selectedAnnotationUsesTextContent
    }

    var selectedText: String {
        guard let selectedAnnotationID,
              case .text(let text) = annotation(id: selectedAnnotationID)?.type else {
            return AnnotationText.defaultText
        }

        return text.content
    }

    var selectedRectangleColor: AnnotationColor {
        selectedRectangleAnnotation()?.color ?? rectangleToolSettings.color
    }

    var selectedRectangleLineWidth: CGFloat {
        selectedRectangleAnnotation()?.lineWidth ?? rectangleToolSettings.lineWidth
    }

    var selectedTextColor: AnnotationColor {
        selectedTextAnnotation()?.color ?? textToolSettings.color
    }

    var selectedTextFontSize: CGFloat {
        selectedTextAnnotation()?.fontSize ?? textToolSettings.fontSize
    }

    var selectedStrokeColor: AnnotationColor {
        selectedStrokeStyle.color
    }

    var selectedStrokeLineWidth: CGFloat {
        selectedStrokeStyle.lineWidth
    }

    var selectedBlurRadius: Double {
        selectedBlurAnnotation()?.radius ?? blurToolSettings.radius
    }

    init(
        originalImageURL: URL,
        selectedTool: EditorTool = .select,
        annotations: [Annotation] = [],
        selectedAnnotationID: UUID? = nil,
        strokeToolSettings: StrokeToolSettings = .defaultSettings,
        blurToolSettings: AnnotationBlur = AnnotationBlur(),
        rectangleToolSettings: AnnotationRectangle = AnnotationRectangle(),
        textToolSettings: AnnotationText = AnnotationText()
    ) {
        self.originalImageURL = originalImageURL
        self.selectedTool = selectedTool
        self.annotations = annotations
        self.selectedAnnotationID = selectedAnnotationID
        self.strokeToolSettings = strokeToolSettings.normalized
        self.blurToolSettings = blurToolSettings.normalized
        self.rectangleToolSettings = rectangleToolSettings.normalized
        self.textToolSettings = textToolSettings.normalized
    }

    @discardableResult
    mutating func addBlurRect(_ rect: CGRect, radius: Double? = nil, id: UUID = UUID()) -> Annotation? {
        guard rect.width > 0, rect.height > 0 else {
            return nil
        }

        let blur = AnnotationBlur(radius: radius ?? selectedBlurRadius)
        let annotation = Annotation(id: id, type: .blur(blur), rect: rect)
        annotations.append(annotation)
        blurToolSettings = blur
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

    @discardableResult
    mutating func addArrow(
        from startPoint: CGPoint,
        to endPoint: CGPoint,
        color: AnnotationColor,
        lineWidth: CGFloat,
        id: UUID = UUID()
    ) -> Annotation? {
        let arrow = AnnotationArrow(
            startPoint: startPoint,
            endPoint: endPoint,
            color: color,
            lineWidth: AnnotationStrokeStyle.clampedLineWidth(lineWidth)
        )

        guard arrow.hasVisibleLength else {
            return nil
        }

        let annotation = Annotation(id: id, type: .arrow(arrow), rect: arrow.visibleBounds)
        annotations.append(annotation)
        strokeToolSettings.update(arrow.style, for: .pen)
        selectAnnotation(id: annotation.id)
        return annotation
    }

    @discardableResult
    mutating func addRectangle(_ rect: CGRect, id: UUID = UUID()) -> Annotation? {
        guard rect.width > 0, rect.height > 0 else {
            return nil
        }

        let rectangle = rectangleToolSettings.normalized
        let annotation = Annotation(id: id, type: .rectangle(rectangle), rect: rect)
        annotations.append(annotation)
        selectAnnotation(id: annotation.id)
        return annotation
    }

    @discardableResult
    mutating func addText(_ text: String = AnnotationText.defaultText, rect: CGRect, id: UUID = UUID()) -> Annotation? {
        guard rect.width > 0, rect.height > 0 else {
            return nil
        }

        let textAnnotation = AnnotationText(
            content: Self.normalizedText(text),
            color: textToolSettings.color,
            fontSize: textToolSettings.fontSize
        )
        let annotation = Annotation(id: id, type: .text(textAnnotation), rect: rect)
        annotations.append(annotation)
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
        guard let id else {
            return
        }

        switch annotation(id: id)?.type {
        case .blur(let blur):
            blurToolSettings = blur.normalized
        case .rectangle(let rectangle):
            rectangleToolSettings = rectangle.normalized
        case .text(let text):
            textToolSettings = text.normalized
        case .stroke, .arrow, nil:
            break
        }
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
            case .arrow(let arrow):
                arrow.contains(imagePoint, hitPadding: Self.arrowSelectionHitPadding)
            case .rectangle, .text:
                annotation.rect.standardized.contains(imagePoint)
            }
        }?.id
    }

    func annotation(id: UUID) -> Annotation? {
        annotations.first { $0.id == id }
    }

    func textContent(id: UUID) -> String? {
        guard case .text(let text) = annotation(id: id)?.type else {
            return nil
        }

        return text.content
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
        updateSelectedArrow { arrow in
            arrow.color = color
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
        updateSelectedArrow { arrow in
            arrow.lineWidth = clampedLineWidth
        }
    }

    mutating func updateSelectedBlurRadius(_ radius: Double) {
        let blur = AnnotationBlur(radius: radius)
        blurToolSettings = blur
        updateSelectedBlur { selectedBlur in
            selectedBlur = blur
        }
    }

    mutating func updateSelectedText(_ text: String) {
        guard let selectedAnnotationID else {
            return
        }

        updateText(id: selectedAnnotationID, text)
    }

    mutating func updateText(id: UUID, _ text: String) {
        guard
              let annotationIndex = annotations.firstIndex(where: { $0.id == id }),
              case .text(var textAnnotation) = annotations[annotationIndex].type else {
            return
        }

        textAnnotation.content = Self.editableText(text)
        annotations[annotationIndex].type = .text(textAnnotation.normalized)
        textToolSettings = textAnnotation.normalized
    }

    mutating func updateSelectedRectangleColor(_ color: AnnotationColor) {
        rectangleToolSettings.color = color
        updateSelectedRectangle { rectangle in
            rectangle.color = color
        }
    }

    mutating func updateSelectedRectangleLineWidth(_ lineWidth: CGFloat) {
        let clampedLineWidth = AnnotationRectangle.clampedLineWidth(lineWidth)
        rectangleToolSettings.lineWidth = clampedLineWidth
        updateSelectedRectangle { rectangle in
            rectangle.lineWidth = clampedLineWidth
        }
    }

    mutating func updateSelectedTextColor(_ color: AnnotationColor) {
        textToolSettings.color = color
        updateSelectedTextAnnotation { text in
            text.color = color
        }
    }

    mutating func updateSelectedTextFontSize(_ fontSize: CGFloat) {
        let clampedFontSize = AnnotationText.clampedFontSize(fontSize)
        textToolSettings.fontSize = clampedFontSize
        updateSelectedTextAnnotation { text in
            text.fontSize = clampedFontSize
        }
    }

    func strokeStyle(for kind: AnnotationStrokeKind) -> AnnotationStrokeStyle {
        strokeToolSettings.style(for: kind)
    }

    static func textRect(startingAt origin: CGPoint, within imageSize: CGSize) -> CGRect {
        let imageBounds = CGRect(origin: .zero, size: imageSize)
        let preferredRect = CGRect(origin: origin, size: AnnotationText.defaultSize)
        return preferredRect.clamped(within: imageBounds)
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
        case .arrow(var arrow):
            arrow.transformPoints(from: originalAnnotation.rect, to: rect)
            annotations[annotationIndex].type = .arrow(arrow)
            annotations[annotationIndex].rect = arrow.visibleBounds
        case .blur, .rectangle, .text:
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

    private mutating func updateSelectedArrow(_ update: (inout AnnotationArrow) -> Void) {
        guard let selectedAnnotationID,
              let annotationIndex = annotations.firstIndex(where: { $0.id == selectedAnnotationID }),
              case .arrow(var arrow) = annotations[annotationIndex].type else {
            return
        }

        update(&arrow)
        annotations[annotationIndex].type = .arrow(arrow)
        annotations[annotationIndex].rect = arrow.visibleBounds
    }

    private mutating func updateSelectedBlur(_ update: (inout AnnotationBlur) -> Void) {
        guard let selectedAnnotationID,
              let annotationIndex = annotations.firstIndex(where: { $0.id == selectedAnnotationID }),
              case .blur(var blur) = annotations[annotationIndex].type else {
            return
        }

        update(&blur)
        annotations[annotationIndex].type = .blur(blur.normalized)
    }

    private mutating func updateSelectedRectangle(_ update: (inout AnnotationRectangle) -> Void) {
        guard let selectedAnnotationID,
              let annotationIndex = annotations.firstIndex(where: { $0.id == selectedAnnotationID }),
              case .rectangle(var rectangle) = annotations[annotationIndex].type else {
            return
        }

        update(&rectangle)
        annotations[annotationIndex].type = .rectangle(rectangle.normalized)
    }

    private mutating func updateSelectedTextAnnotation(_ update: (inout AnnotationText) -> Void) {
        guard let selectedAnnotationID,
              let annotationIndex = annotations.firstIndex(where: { $0.id == selectedAnnotationID }),
              case .text(var text) = annotations[annotationIndex].type else {
            return
        }

        update(&text)
        annotations[annotationIndex].type = .text(text.normalized)
    }

    private func selectedBlurAnnotation() -> AnnotationBlur? {
        guard let selectedAnnotationID,
              case .blur(let blur) = annotation(id: selectedAnnotationID)?.type else {
            return nil
        }

        return blur
    }

    private func selectedStrokeAnnotation() -> AnnotationStroke? {
        guard let selectedAnnotationID,
              case .stroke(let stroke) = annotation(id: selectedAnnotationID)?.type else {
            return nil
        }

        return stroke
    }

    private func selectedArrowAnnotation() -> AnnotationArrow? {
        guard let selectedAnnotationID,
              case .arrow(let arrow) = annotation(id: selectedAnnotationID)?.type else {
            return nil
        }

        return arrow
    }

    private func selectedRectangleAnnotation() -> AnnotationRectangle? {
        guard let selectedAnnotationID,
              case .rectangle(let rectangle) = annotation(id: selectedAnnotationID)?.type else {
            return nil
        }

        return rectangle
    }

    private func selectedTextAnnotation() -> AnnotationText? {
        guard let selectedAnnotationID,
              case .text(let text) = annotation(id: selectedAnnotationID)?.type else {
            return nil
        }

        return text
    }

    private var activeStrokeStyleKind: AnnotationStrokeKind? {
        if selectedArrowAnnotation() != nil || selectedTool == .arrow {
            return .pen
        }

        return selectedStrokeAnnotation()?.kind ?? selectedTool.strokeKind
    }

    private var selectedStrokeStyle: AnnotationStrokeStyle {
        if let selectedArrow = selectedArrowAnnotation() {
            return selectedArrow.style
        }

        if let selectedStroke = selectedStrokeAnnotation() {
            return selectedStroke.style
        }

        guard let strokeKind = selectedTool.strokeKind else {
            return strokeToolSettings.style(for: .pen)
        }

        return strokeToolSettings.style(for: strokeKind)
    }

    private static func normalizedText(_ text: String) -> String {
        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedText.isEmpty ? AnnotationText.defaultText : trimmedText
    }

    private static func editableText(_ text: String) -> String {
        text
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
