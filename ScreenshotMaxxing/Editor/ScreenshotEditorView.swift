//
//  ScreenshotEditorView.swift
//  ScreenshotMaxxing
//
//  Created by Ben Kramer on 5/26/26.
//

import SwiftUI

struct ScreenshotEditorView: View {
    let imageURL: URL
    private let capture: Capture?
    private let image: NSImage?
    private let editorSettingsStore: EditorSettingsStore
    private let savedFilePresenter: SavedFilePresenter
    private let closeAction: () -> Void
    @State private var editorState: ScreenshotEditorState
    @State private var draftBlurRect: CGRect?
    @State private var draftStroke: AnnotationStroke?
    @State private var draftArrow: AnnotationArrow?
    @State private var draftRectangleRect: CGRect?
    @State private var draftTextRect: CGRect?
    @State private var zoomScale: CGFloat = 1
    @State private var magnificationGestureBaseZoomScale: CGFloat?
    @State private var editingTextAnnotationID: UUID?
    @State private var statusMessage: String?
    private static let successfulActionCloseDelay: TimeInterval = 0.6
    private static let minimumZoomScale: CGFloat = 0.5
    private static let maximumZoomScale: CGFloat = 8

    init(
        imageURL: URL,
        capture: Capture? = nil,
        editorSettingsStore: EditorSettingsStore = EditorSettingsStore(),
        savedFilePresenter: SavedFilePresenter = SavedFilePresenter(),
        closeAction: @escaping () -> Void = {}
    ) {
        self.imageURL = imageURL
        self.capture = capture
        self.editorSettingsStore = editorSettingsStore
        self.savedFilePresenter = savedFilePresenter
        self.closeAction = closeAction
        self.image = NSImage(contentsOf: imageURL)
        self._editorState = State(
            initialValue: ScreenshotEditorState(
                originalImageURL: imageURL,
                strokeToolSettings: editorSettingsStore.strokeToolSettings()
            ))
    }

    var body: some View {
        Group {
            if let image {
                VStack(spacing: 0) {
                    EditorToolbar(
                        selectedTool: $editorState.selectedTool,
                        selectedStrokeColor: Binding(
                            get: { editorState.selectedStrokeColor },
                            set: {
                                editorState.updateSelectedStrokeColor($0)
                                persistStrokeToolSettings()
                            }
                        ),
                        selectedStrokeLineWidth: Binding(
                            get: { editorState.selectedStrokeLineWidth },
                            set: {
                                editorState.updateSelectedStrokeLineWidth($0)
                                persistStrokeToolSettings()
                            }
                        ),
                        selectedBlurRadius: Binding(
                            get: { editorState.selectedBlurRadius },
                            set: { editorState.updateSelectedBlurRadius($0) }
                        ),
                        showsStrokeControls: editorState.selectedTool.showsStrokeControls
                            || editorState.selectedAnnotationUsesStrokeStyle,
                        showsBlurControls: editorState.selectedTool == .blur
                            || editorState.selectedAnnotationUsesBlurStyle,
                        showsTextControls: editorState.selectedTool == .text
                            || editorState.selectedAnnotationUsesTextContent,
                        showsRectangleControls: editorState.selectedTool == .rectangle
                            || editorState.selectedAnnotationUsesRectangleStyle,
                        selectedAnnotationID: editorState.selectedAnnotationID,
                        selectedRectangleColor: Binding(
                            get: { editorState.selectedRectangleColor },
                            set: { editorState.updateSelectedRectangleColor($0) }
                        ),
                        selectedRectangleLineWidth: Binding(
                            get: { editorState.selectedRectangleLineWidth },
                            set: { editorState.updateSelectedRectangleLineWidth($0) }
                        ),
                        selectedTextColor: Binding(
                            get: { editorState.selectedTextColor },
                            set: { editorState.updateSelectedTextColor($0) }
                        ),
                        selectedTextFontSize: Binding(
                            get: { editorState.selectedTextFontSize },
                            set: { editorState.updateSelectedTextFontSize($0) }
                        ),
                        statusMessage: statusMessage,
                        deleteAction: removeSelectedAnnotation,
                        copyAction: copyEditedImage,
                        copyAndDeleteAction: copyEditedImageAndDeleteCapture,
                        saveAction: saveEditedImage
                    )
                    Divider()
                    ScreenshotImageCanvas(
                        image: image,
                        editorState: $editorState,
                        draftBlurRect: $draftBlurRect,
                        draftStroke: $draftStroke,
                        draftArrow: $draftArrow,
                        draftRectangleRect: $draftRectangleRect,
                        draftTextRect: $draftTextRect,
                        editingTextAnnotationID: $editingTextAnnotationID,
                        zoomScale: zoomScale,
                        scrollZoomAction: zoomByScroll
                    )
                    .simultaneousGesture(canvasMagnificationGesture)
                    .overlay(alignment: .bottomTrailing) {
                        if showsResetZoomButton {
                            resetZoomButton
                        }
                    }
                }
            } else {
                unavailableImageView
            }
        }
        .frame(minWidth: 640, minHeight: 420)
        .background(Color(nsColor: .windowBackgroundColor))
        .overlay(alignment: .topLeading) {
            Group {
                undoCommandButton
                zoomOutCommandButton
                resetZoomCommandButton
                zoomInCommandButton
            }
        }
        .onChange(of: editorState.selectedTool) { _, selectedTool in
            guard selectedTool != .text, editingTextAnnotationID != nil else {
                return
            }

            editingTextAnnotationID = nil
            editorState.selectAnnotation(id: nil)
        }
    }

    private var undoCommandButton: some View {
        Button("Undo Annotation", action: undoLastAnnotation)
            .keyboardShortcut("z", modifiers: .command)
            .disabled(editorState.annotations.isEmpty)
            .frame(width: 0, height: 0)
            .opacity(0)
            .accessibilityHidden(true)
    }

    private var zoomOutCommandButton: some View {
        Button("Zoom Out", action: zoomOut)
            .keyboardShortcut("-", modifiers: .command)
            .disabled(zoomScale <= Self.minimumZoomScale)
            .frame(width: 0, height: 0)
            .opacity(0)
            .accessibilityHidden(true)
    }

    private var resetZoomCommandButton: some View {
        Button("Actual Size", action: resetZoom)
            .keyboardShortcut("0", modifiers: .command)
            .disabled(zoomScale == 1)
            .frame(width: 0, height: 0)
            .opacity(0)
            .accessibilityHidden(true)
    }

    private var zoomInCommandButton: some View {
        Button("Zoom In", action: zoomIn)
            .keyboardShortcut("+", modifiers: .command)
            .disabled(zoomScale >= Self.maximumZoomScale)
            .frame(width: 0, height: 0)
            .opacity(0)
            .accessibilityHidden(true)
    }

    private var showsResetZoomButton: Bool {
        abs(zoomScale - 1) > 0.001
    }

    private var resetZoomButton: some View {
        Button(action: resetZoom) {
            HStack(spacing: 6) {
                Image(systemName: "arrow.counterclockwise")
                Text("\(Int((zoomScale * 100).rounded()))%")
                    .monospacedDigit()
            }
            .font(.caption)
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
        .help("Reset zoom")
        .padding(12)
    }

    private var canvasMagnificationGesture: some Gesture {
        MagnificationGesture()
            .onChanged { value in
                if magnificationGestureBaseZoomScale == nil {
                    magnificationGestureBaseZoomScale = zoomScale
                }

                zoomScale = clampedZoomScale((magnificationGestureBaseZoomScale ?? zoomScale) * value)
            }
            .onEnded { _ in
                magnificationGestureBaseZoomScale = nil
            }
    }

    private var unavailableImageView: some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 36, weight: .medium))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.secondary)

            Text("Could not load \(imageURL.lastPathComponent)")
                .font(.headline)
                .lineLimit(1)

            Text("The file may have been moved or deleted.")
                .foregroundStyle(.secondary)
        }
        .padding(32)
    }

    private func copyEditedImage() {
        do {
            let pngData = try ImageRenderer().renderPNG(
                imageURL: imageURL,
                annotations: editorState.annotations
            )
            _ = try saveEditedPNG(pngData)

            if EditorClipboard.copyPNGData(pngData) {
                statusMessage = "Saved and copied image to clipboard"
                closeAfterShowingSuccess()
            } else {
                statusMessage = "Saved, but copy failed"
            }
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    private func copyEditedImageAndDeleteCapture() {
        do {
            let pngData = try ImageRenderer().renderPNG(
                imageURL: imageURL,
                annotations: editorState.annotations
            )

            guard EditorClipboard.copyPNGData(pngData) else {
                statusMessage = "Copy failed"
                return
            }

            guard let capture else {
                statusMessage = EditorCopyAndTrashStatus.copiedWithoutCaptureMessage(for: .image)
                closeAfterShowingSuccess()
                return
            }

            do {
                try CaptureMetadataStore().deleteCaptureFromHistoryAndDisk(capture)
                statusMessage = EditorCopyAndTrashStatus.copiedAndMovedToTrashMessage(for: .image)
                closeAfterShowingSuccess()
            } catch {
                statusMessage = EditorCopyAndTrashStatus.copiedButMoveToTrashFailedMessage(
                    for: .image,
                    errorDescription: error.localizedDescription
                )
            }
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    private func saveEditedImage() {
        do {
            let pngData = try ImageRenderer().renderPNG(
                imageURL: imageURL,
                annotations: editorState.annotations
            )
            let editedFileURL = try saveEditedPNG(pngData)
            savedFilePresenter.revealInFinder(editedFileURL)

            if EditorClipboard.copyString(editedFileURL.fileSystemPath) {
                statusMessage = "Saved; opened in Finder and path copied"
                closeAfterShowingSuccess()
            } else {
                statusMessage = "Saved and opened in Finder, but path copy failed"
            }
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    private func saveEditedPNG(_ pngData: Data) throws -> URL {
        try EditorFileSaver().saveEditedPNG(
            pngData,
            originalFileName: capture?.fileName ?? imageURL.lastPathComponent,
            capture: capture
        )
    }

    private func closeAfterShowingSuccess() {
        let closeAction = closeAction

        DispatchQueue.main.asyncAfter(deadline: .now() + Self.successfulActionCloseDelay) {
            closeAction()
        }
    }

    private func removeSelectedAnnotation() {
        if editingTextAnnotationID == editorState.selectedAnnotationID {
            editingTextAnnotationID = nil
        }

        editorState.removeSelectedAnnotation()
    }

    private func undoLastAnnotation() {
        editorState.undoLastAnnotation()

        if let editingTextAnnotationID,
            editorState.annotation(id: editingTextAnnotationID) == nil
        {
            self.editingTextAnnotationID = nil
        }
    }

    private func zoomOut() {
        zoomScale = clampedZoomScale(zoomScale / 1.25)
    }

    private func resetZoom() {
        zoomScale = 1
    }

    private func zoomIn() {
        zoomScale = clampedZoomScale(zoomScale * 1.25)
    }

    private func zoomByScroll(_ scrollDelta: CGFloat) {
        guard scrollDelta.isFinite, scrollDelta != 0 else {
            return
        }

        let scrollDirection: CGFloat = scrollDelta > 0 ? 1 : -1
        let scrollAmount = min(max(abs(scrollDelta), 1), 12)
        let zoomMultiplier = pow(1.015, scrollDirection * scrollAmount)
        zoomScale = clampedZoomScale(zoomScale * zoomMultiplier)
    }

    private func clampedZoomScale(_ scale: CGFloat) -> CGFloat {
        min(max(scale, Self.minimumZoomScale), Self.maximumZoomScale)
    }

    private func persistStrokeToolSettings() {
        do {
            try editorSettingsStore.saveStrokeToolSettings(editorState.strokeToolSettings)
        } catch {
            statusMessage = error.localizedDescription
        }
    }
}

struct ScreenshotImageCanvas: View {
    let image: NSImage
    @Binding var editorState: ScreenshotEditorState
    @Binding var draftBlurRect: CGRect?
    @Binding var draftStroke: AnnotationStroke?
    @Binding var draftArrow: AnnotationArrow?
    @Binding var draftRectangleRect: CGRect?
    @Binding var draftTextRect: CGRect?
    @Binding var editingTextAnnotationID: UUID?
    let zoomScale: CGFloat
    let scrollZoomAction: (CGFloat) -> Void
    @Environment(\.displayScale) private var displayScale
    @State private var activeAnnotationDrag: AnnotationDrag?
    @State private var pendingSingleTapWorkItem: DispatchWorkItem?
    @State private var suppressSingleTapUntil: Date = .distantPast

    var body: some View {
        GeometryReader { proxy in
            let geometry = ImageCanvasGeometry(
                imageSize: image.pixelSize,
                containerSize: proxy.size,
                displayScale: displayScale,
                zoomScale: zoomScale
            )
            let draftPreviewBlurRadius = geometry.viewDistance(forImageDistance: editorState.selectedBlurRadius)

            ScrollView([.horizontal, .vertical]) {
                ZStack(alignment: .topLeading) {
                    Color(nsColor: .underPageBackgroundColor)

                    Image(nsImage: image)
                        .resizable()
                        .interpolation(.high)
                        .frame(width: geometry.imageRect.width, height: geometry.imageRect.height)
                        .position(x: geometry.imageRect.midX, y: geometry.imageRect.midY)
                        .accessibilityLabel("Screenshot")

                    ForEach(editorState.annotations) { annotation in
                        AnnotationPreviewOverlay(
                            annotation: annotation,
                            image: image,
                            imageFrame: geometry.imageRect,
                            containerSize: geometry.contentSize,
                            geometry: geometry,
                            isSelected: annotation.id == editorState.selectedAnnotationID,
                            isEditingText: annotation.id == editingTextAnnotationID,
                            textContent: Binding(
                                get: { editorState.textContent(id: annotation.id) ?? AnnotationText.defaultText },
                                set: { editorState.updateText(id: annotation.id, $0) }
                            )
                        )
                    }

                    if let draftBlurRect {
                        BlurPreviewOverlay(
                            image: image,
                            imageFrame: geometry.imageRect,
                            containerSize: geometry.contentSize,
                            rect: geometry.viewRect(forImageRect: draftBlurRect),
                            blurRadius: draftPreviewBlurRadius,
                            isSelected: false,
                            isDraft: true
                        )
                    }

                    if let draftStroke {
                        StrokePreviewOverlay(
                            stroke: draftStroke,
                            geometry: geometry,
                            selectionRect: geometry.viewRect(forImageRect: draftStroke.visibleBounds),
                            isSelected: false,
                            isDraft: true
                        )
                    }

                    if let draftArrow {
                        ArrowPreviewOverlay(
                            arrow: draftArrow,
                            geometry: geometry,
                            selectionRect: geometry.viewRect(forImageRect: draftArrow.visibleBounds),
                            isSelected: false,
                            isDraft: true
                        )
                    }

                    if let draftRectangleRect {
                        RectanglePreviewOverlay(
                            rectangle: editorState.rectangleToolSettings,
                            rect: geometry.viewRect(forImageRect: draftRectangleRect),
                            isSelected: false,
                            isDraft: true
                        )
                    }

                    if let draftTextRect {
                        TextPreviewOverlay(
                            text: AnnotationText(
                                content: AnnotationText.defaultText,
                                color: editorState.textToolSettings.color,
                                fontSize: editorState.textToolSettings.fontSize
                            ),
                            textContent: .constant(AnnotationText.defaultText),
                            rect: geometry.viewRect(forImageRect: draftTextRect),
                            geometry: geometry,
                            isSelected: false,
                            isEditing: false,
                            isDraft: true
                        )
                    }
                }
                .frame(width: geometry.contentSize.width, height: geometry.contentSize.height)
                .contentShape(Rectangle())
                .gesture(canvasDragGesture(geometry: geometry))
                .simultaneousGesture(selectTapGesture(geometry: geometry))
                .simultaneousGesture(textEditDoubleTapGesture(geometry: geometry))
            }
            .background(Color(nsColor: .underPageBackgroundColor))
            .background(CanvasScrollZoomView(scrollZoomAction: scrollZoomAction))
        }
    }

    private func canvasDragGesture(geometry: ImageCanvasGeometry) -> some Gesture {
        DragGesture(minimumDistance: 1, coordinateSpace: .local)
            .onChanged { value in
                if activeAnnotationDrag == nil,
                    let activeDrag = annotationDrag(startingAt: value.startLocation, geometry: geometry)
                {
                    activeAnnotationDrag = activeDrag
                    editorState.selectAnnotation(id: activeDrag.annotationID)
                }

                if let activeAnnotationDrag {
                    editingTextAnnotationID = nil
                    let translation = geometry.imageTranslation(
                        fromViewStart: value.startLocation,
                        toViewEnd: value.location
                    )
                    updateActiveAnnotationDrag(activeAnnotationDrag, by: translation)
                    draftBlurRect = nil
                    draftStroke = nil
                    draftArrow = nil
                    draftRectangleRect = nil
                    draftTextRect = nil
                    return
                }

                switch editorState.selectedTool {
                case .blur:
                    draftStroke = nil
                    draftArrow = nil
                    draftRectangleRect = nil
                    draftTextRect = nil
                    draftBlurRect = geometry.imageRect(
                        fromViewStart: value.startLocation,
                        toViewEnd: value.location
                    )
                case .pen, .highlighter:
                    draftBlurRect = nil
                    draftArrow = nil
                    draftRectangleRect = nil
                    draftTextRect = nil
                    updateDraftStroke(with: value, geometry: geometry)
                case .arrow:
                    draftBlurRect = nil
                    draftStroke = nil
                    draftRectangleRect = nil
                    draftTextRect = nil
                    updateDraftArrow(with: value, geometry: geometry)
                case .rectangle:
                    draftBlurRect = nil
                    draftStroke = nil
                    draftArrow = nil
                    draftTextRect = nil
                    draftRectangleRect = geometry.imageRect(
                        fromViewStart: value.startLocation,
                        toViewEnd: value.location
                    )
                case .text:
                    draftBlurRect = nil
                    draftStroke = nil
                    draftArrow = nil
                    draftRectangleRect = nil
                    draftTextRect = geometry.imageRect(
                        fromViewStart: value.startLocation,
                        toViewEnd: value.location
                    )
                case .select:
                    draftBlurRect = nil
                    draftStroke = nil
                    draftArrow = nil
                    draftRectangleRect = nil
                    draftTextRect = nil
                }
            }
            .onEnded { value in
                defer {
                    activeAnnotationDrag = nil
                    draftBlurRect = nil
                    draftStroke = nil
                    draftArrow = nil
                    draftRectangleRect = nil
                    draftTextRect = nil
                }

                guard activeAnnotationDrag == nil else {
                    return
                }

                if editorState.selectedTool == .blur,
                    let imageRect = geometry.imageRect(
                        fromViewStart: value.startLocation,
                        toViewEnd: value.location
                    )
                {
                    editorState.addBlurRect(imageRect, radius: editorState.selectedBlurRadius)
                    return
                }

                if editorState.selectedTool == .arrow {
                    let arrowStyle = editorState.strokeStyle(for: .pen)
                    let arrowPoints = arrowPoints(from: value, geometry: geometry)
                    if let startPoint = arrowPoints.first,
                        let endPoint = arrowPoints.last
                    {
                        editorState.addArrow(
                            from: startPoint,
                            to: endPoint,
                            color: arrowStyle.color,
                            lineWidth: arrowStyle.lineWidth
                        )
                    }
                    return
                }

                if editorState.selectedTool == .rectangle,
                    let imageRect = geometry.imageRect(
                        fromViewStart: value.startLocation,
                        toViewEnd: value.location
                    )
                {
                    editorState.addRectangle(imageRect)
                    return
                }

                if editorState.selectedTool == .text,
                    let imageRect = geometry.imageRect(
                        fromViewStart: value.startLocation,
                        toViewEnd: value.location
                    )
                {
                    editingTextAnnotationID = editorState.addText(rect: imageRect)?.id
                    return
                }

                guard let strokeKind = editorState.selectedTool.strokeKind else {
                    return
                }

                let strokeStyle = editorState.strokeStyle(for: strokeKind)
                let strokePoints = draftStroke?.points ?? strokePoints(from: value, geometry: geometry)
                editorState.addStroke(
                    kind: strokeKind,
                    points: strokePoints,
                    color: strokeStyle.color,
                    lineWidth: strokeStyle.lineWidth
                )
            }
    }

    private func updateDraftStroke(with value: DragGesture.Value, geometry: ImageCanvasGeometry) {
        guard let strokeKind = editorState.selectedTool.strokeKind,
            let imagePoint = geometry.imagePoint(forViewPoint: value.location)
        else {
            return
        }

        if var draftStroke {
            if draftStroke.points.last != imagePoint {
                draftStroke.points.append(imagePoint)
                self.draftStroke = draftStroke
            }
            return
        }

        guard let startImagePoint = geometry.imagePoint(forViewPoint: value.startLocation) else {
            return
        }

        let strokeStyle = editorState.strokeStyle(for: strokeKind)
        draftStroke = AnnotationStroke(
            kind: strokeKind,
            points: [startImagePoint, imagePoint],
            color: strokeStyle.color,
            lineWidth: strokeStyle.lineWidth
        )
    }

    private func updateDraftArrow(with value: DragGesture.Value, geometry: ImageCanvasGeometry) {
        let points = arrowPoints(from: value, geometry: geometry)
        guard let startPoint = points.first,
            let endPoint = points.last
        else {
            return
        }

        let arrowStyle = editorState.strokeStyle(for: .pen)
        draftArrow = AnnotationArrow(
            startPoint: startPoint,
            endPoint: endPoint,
            color: arrowStyle.color,
            lineWidth: arrowStyle.lineWidth
        )
    }

    private func arrowPoints(from value: DragGesture.Value, geometry: ImageCanvasGeometry) -> [CGPoint] {
        guard let startImagePoint = geometry.imagePoint(forViewPoint: value.startLocation),
            let endImagePoint = geometry.imagePoint(forViewPoint: value.location)
        else {
            return []
        }

        return [startImagePoint, endImagePoint]
    }

    private func strokePoints(from value: DragGesture.Value, geometry: ImageCanvasGeometry) -> [CGPoint] {
        guard let startImagePoint = geometry.imagePoint(forViewPoint: value.startLocation),
            let endImagePoint = geometry.imagePoint(forViewPoint: value.location)
        else {
            return []
        }

        return [startImagePoint, endImagePoint]
    }

    private func selectTapGesture(geometry: ImageCanvasGeometry) -> some Gesture {
        SpatialTapGesture(coordinateSpace: .local)
            .onEnded { value in
                guard Date() >= suppressSingleTapUntil else {
                    return
                }

                pendingSingleTapWorkItem?.cancel()
                let workItem = DispatchWorkItem {
                    handleSelectTap(at: value.location, geometry: geometry)
                }
                pendingSingleTapWorkItem = workItem
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.18, execute: workItem)
            }
    }

    private func textEditDoubleTapGesture(geometry: ImageCanvasGeometry) -> some Gesture {
        SpatialTapGesture(count: 2, coordinateSpace: .local)
            .onEnded { value in
                pendingSingleTapWorkItem?.cancel()
                pendingSingleTapWorkItem = nil
                suppressSingleTapUntil = Date().addingTimeInterval(0.24)

                guard let imagePoint = geometry.imagePoint(forViewPoint: value.location),
                    let annotationID = editorState.annotationID(containing: imagePoint),
                    case .text = editorState.annotation(id: annotationID)?.type
                else {
                    editingTextAnnotationID = nil
                    return
                }

                editorState.selectAnnotation(id: annotationID)
                editingTextAnnotationID = annotationID
            }
    }

    private func handleSelectTap(at viewPoint: CGPoint, geometry: ImageCanvasGeometry) {
        pendingSingleTapWorkItem = nil
        guard Date() >= suppressSingleTapUntil else {
            return
        }

        if resizeHandle(at: viewPoint, geometry: geometry) != nil {
            return
        }

        guard let imagePoint = geometry.imagePoint(forViewPoint: viewPoint) else {
            editorState.selectAnnotation(id: nil)
            editingTextAnnotationID = nil
            return
        }

        if editingTextAnnotationID != nil {
            editorState.selectAnnotation(containing: imagePoint)
            editingTextAnnotationID = nil
            return
        }

        if editorState.selectedTool == .text,
            editorState.annotationID(containing: imagePoint) == nil
        {
            let textAnnotation = editorState.addText(
                rect: ScreenshotEditorState.textRect(
                    startingAt: imagePoint,
                    within: image.pixelSize
                )
            )
            editingTextAnnotationID = textAnnotation?.id
            return
        }

        let selectedAnnotationID = editorState.selectAnnotation(containing: imagePoint)
        if selectedAnnotationID != editingTextAnnotationID {
            editingTextAnnotationID = nil
        }
    }

    private func annotationDrag(startingAt startLocation: CGPoint, geometry: ImageCanvasGeometry) -> AnnotationDrag? {
        if let selectedAnnotationID = editorState.selectedAnnotationID,
            let annotation = editorState.annotation(id: selectedAnnotationID),
            let resizeHandle = resizeHandle(at: startLocation, geometry: geometry)
        {
            return AnnotationDrag(
                annotationID: selectedAnnotationID,
                originalAnnotation: annotation,
                resizeHandle: resizeHandle
            )
        }

        guard let startImagePoint = geometry.imagePoint(forViewPoint: startLocation),
            let annotationID = editorState.annotationID(containing: startImagePoint),
            let annotation = editorState.annotation(id: annotationID)
        else {
            return nil
        }

        return AnnotationDrag(annotationID: annotationID, originalAnnotation: annotation)
    }

    private func resizeHandle(at viewPoint: CGPoint, geometry: ImageCanvasGeometry) -> AnnotationResizeHandle? {
        guard let selectedAnnotationID = editorState.selectedAnnotationID,
            let annotation = editorState.annotation(id: selectedAnnotationID)
        else {
            return nil
        }

        let viewRect = geometry.viewRect(forImageRect: annotation.rect)

        return AnnotationResizeHandle.allCases.first { handle in
            handle.hitRect(in: viewRect).contains(viewPoint)
        }
    }

    private func updateActiveAnnotationDrag(_ annotationDrag: AnnotationDrag, by translation: CGSize) {
        if let resizeHandle = annotationDrag.resizeHandle {
            editorState.resizeAnnotation(
                id: annotationDrag.annotationID,
                from: annotationDrag.originalAnnotation,
                handle: resizeHandle,
                by: translation,
                within: image.pixelSize
            )
        } else {
            editorState.moveAnnotation(
                id: annotationDrag.annotationID,
                from: annotationDrag.originalAnnotation,
                by: translation,
                within: image.pixelSize
            )
        }
    }
}

private struct AnnotationDrag: Equatable {
    let annotationID: UUID
    let originalAnnotation: Annotation
    var resizeHandle: AnnotationResizeHandle? = nil
}

private struct CanvasScrollZoomView: NSViewRepresentable {
    let scrollZoomAction: (CGFloat) -> Void

    func makeNSView(context: Context) -> CanvasScrollZoomNSView {
        let view = CanvasScrollZoomNSView()
        view.scrollZoomAction = scrollZoomAction
        return view
    }

    func updateNSView(_ nsView: CanvasScrollZoomNSView, context: Context) {
        nsView.scrollZoomAction = scrollZoomAction
    }
}

private final class CanvasScrollZoomNSView: NSView {
    var scrollZoomAction: (CGFloat) -> Void = { _ in }
    private var scrollWheelMonitor: Any?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        updateScrollWheelMonitor()
    }

    deinit {
        if let scrollWheelMonitor {
            NSEvent.removeMonitor(scrollWheelMonitor)
        }
    }

    private func updateScrollWheelMonitor() {
        if let scrollWheelMonitor {
            NSEvent.removeMonitor(scrollWheelMonitor)
            self.scrollWheelMonitor = nil
        }

        guard window != nil else {
            return
        }

        scrollWheelMonitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
            guard let self,
                event.window === self.window,
                self.bounds.contains(self.convert(event.locationInWindow, from: nil))
            else {
                return event
            }

            let scrollDelta = event.scrollingDeltaY != 0 ? event.scrollingDeltaY : -event.scrollingDeltaX
            guard scrollDelta != 0 else {
                return event
            }

            self.scrollZoomAction(scrollDelta)
            return nil
        }
    }
}

private enum EditorCanvasMetrics {
    static let resizeHandleVisualSize: CGFloat = 8
    static let resizeHandleHitSize: CGFloat = 18
}

private extension AnnotationResizeHandle {
    func viewPosition(in rect: CGRect) -> CGPoint {
        switch self {
        case .topLeft:
            CGPoint(x: rect.minX, y: rect.minY)
        case .top:
            CGPoint(x: rect.midX, y: rect.minY)
        case .topRight:
            CGPoint(x: rect.maxX, y: rect.minY)
        case .right:
            CGPoint(x: rect.maxX, y: rect.midY)
        case .bottomRight:
            CGPoint(x: rect.maxX, y: rect.maxY)
        case .bottom:
            CGPoint(x: rect.midX, y: rect.maxY)
        case .bottomLeft:
            CGPoint(x: rect.minX, y: rect.maxY)
        case .left:
            CGPoint(x: rect.minX, y: rect.midY)
        }
    }

    func hitRect(in rect: CGRect) -> CGRect {
        let center = viewPosition(in: rect)
        let hitSize = EditorCanvasMetrics.resizeHandleHitSize

        return CGRect(
            x: center.x - hitSize / 2,
            y: center.y - hitSize / 2,
            width: hitSize,
            height: hitSize
        )
    }
}

private struct AnnotationPreviewOverlay: View {
    let annotation: Annotation
    let image: NSImage
    let imageFrame: CGRect
    let containerSize: CGSize
    let geometry: ImageCanvasGeometry
    let isSelected: Bool
    let isEditingText: Bool
    @Binding var textContent: String

    var body: some View {
        switch annotation.type {
        case .blur(let blur):
            BlurPreviewOverlay(
                image: image,
                imageFrame: imageFrame,
                containerSize: containerSize,
                rect: geometry.viewRect(forImageRect: annotation.rect),
                blurRadius: geometry.viewDistance(forImageDistance: blur.radius),
                isSelected: isSelected,
                isDraft: false
            )
        case .stroke(let stroke):
            StrokePreviewOverlay(
                stroke: stroke,
                geometry: geometry,
                selectionRect: geometry.viewRect(forImageRect: annotation.rect),
                isSelected: isSelected,
                isDraft: false
            )
        case .arrow(let arrow):
            ArrowPreviewOverlay(
                arrow: arrow,
                geometry: geometry,
                selectionRect: geometry.viewRect(forImageRect: annotation.rect),
                isSelected: isSelected,
                isDraft: false
            )
        case .rectangle(let rectangle):
            RectanglePreviewOverlay(
                rectangle: rectangle,
                rect: geometry.viewRect(forImageRect: annotation.rect),
                isSelected: isSelected,
                isDraft: false
            )
        case .text(let text):
            TextPreviewOverlay(
                text: text,
                textContent: $textContent,
                rect: geometry.viewRect(forImageRect: annotation.rect),
                geometry: geometry,
                isSelected: isSelected,
                isEditing: isEditingText,
                isDraft: false
            )
        }
    }
}

private struct RectanglePreviewOverlay: View {
    let rectangle: AnnotationRectangle
    let rect: CGRect
    let isSelected: Bool
    let isDraft: Bool

    var body: some View {
        Path { path in
            path.addRect(rect)
        }
        .stroke(
            Color(annotationColor: rectangle.color),
            lineWidth: rectangle.lineWidth
        )
        .overlay(alignment: .topLeading) {
            if isSelected || isDraft {
                Rectangle()
                    .strokeBorder(
                        Color.accentColor,
                        style: StrokeStyle(lineWidth: 2, dash: isDraft ? [6, 4] : [])
                    )
                    .frame(width: rect.width, height: rect.height)
                    .offset(x: rect.minX, y: rect.minY)
            }
        }
        .overlay(alignment: .topLeading) {
            if isSelected && !isDraft {
                ForEach(AnnotationResizeHandle.allCases, id: \.self) { handle in
                    ResizeHandleView()
                        .position(handle.viewPosition(in: rect))
                }
            }
        }
        .allowsHitTesting(false)
    }
}

private struct TextPreviewOverlay: View {
    let text: AnnotationText
    @Binding var textContent: String
    let rect: CGRect
    let geometry: ImageCanvasGeometry
    let isSelected: Bool
    let isEditing: Bool
    let isDraft: Bool
    @FocusState private var isTextEditorFocused: Bool

    var body: some View {
        let fontSize = max(geometry.viewDistance(forImageDistance: text.fontSize), AnnotationText.minimumFontSize)

        ZStack(alignment: .topLeading) {
            if isEditing {
                TextEditor(text: $textContent)
                    .font(.system(size: fontSize, weight: .semibold))
                    .foregroundStyle(Color(annotationColor: text.color))
                    .tint(Color(annotationColor: text.color))
                    .scrollContentBackground(.hidden)
                    .background(Color.clear)
                    .focused($isTextEditorFocused)
                    .frame(width: rect.width, height: rect.height, alignment: .topLeading)
                    .offset(x: rect.minX, y: rect.minY)
                    .onAppear {
                        DispatchQueue.main.async {
                            isTextEditorFocused = true
                        }
                    }
            } else {
                Text(text.content)
                    .font(.system(size: fontSize, weight: .semibold))
                    .foregroundStyle(Color(annotationColor: text.color))
                    .lineLimit(nil)
                    .multilineTextAlignment(.leading)
                    .frame(width: rect.width, height: rect.height, alignment: .topLeading)
                    .clipped()
                    .offset(x: rect.minX, y: rect.minY)
            }

            if isSelected || isDraft {
                Rectangle()
                    .strokeBorder(
                        Color.accentColor,
                        style: StrokeStyle(lineWidth: 2, dash: isDraft ? [6, 4] : [])
                    )
                    .frame(width: rect.width, height: rect.height)
                    .offset(x: rect.minX, y: rect.minY)
            }

            if isSelected && !isDraft && !isEditing {
                ForEach(AnnotationResizeHandle.allCases, id: \.self) { handle in
                    ResizeHandleView()
                        .position(handle.viewPosition(in: rect))
                }
            }
        }
        .allowsHitTesting(isEditing)
    }
}

private struct ArrowPreviewOverlay: View {
    let arrow: AnnotationArrow
    let geometry: ImageCanvasGeometry
    let selectionRect: CGRect
    let isSelected: Bool
    let isDraft: Bool

    var body: some View {
        let lineWidth = max(geometry.viewDistance(forImageDistance: Double(arrow.lineWidth)), 1)

        Path { path in
            path.move(to: geometry.viewPoint(forImagePoint: arrow.startPoint))
            path.addLine(to: geometry.viewPoint(forImagePoint: arrow.endPoint))
            for (headStart, headEnd) in arrow.arrowHeadSegments {
                path.move(to: geometry.viewPoint(forImagePoint: headStart))
                path.addLine(to: geometry.viewPoint(forImagePoint: headEnd))
            }
        }
        .stroke(
            Color(annotationColor: arrow.color),
            style: StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round)
        )
        .overlay(alignment: .topLeading) {
            if isSelected || isDraft {
                Rectangle()
                    .strokeBorder(
                        Color.accentColor,
                        style: StrokeStyle(lineWidth: 2, dash: isDraft ? [6, 4] : [])
                    )
                    .frame(width: selectionRect.width, height: selectionRect.height)
                    .offset(x: selectionRect.minX, y: selectionRect.minY)
            }
        }
        .overlay(alignment: .topLeading) {
            if isSelected && !isDraft {
                ForEach(AnnotationResizeHandle.allCases, id: \.self) { handle in
                    ResizeHandleView()
                        .position(handle.viewPosition(in: selectionRect))
                }
            }
        }
        .allowsHitTesting(false)
    }
}

private struct StrokePreviewOverlay: View {
    let stroke: AnnotationStroke
    let geometry: ImageCanvasGeometry
    let selectionRect: CGRect
    let isSelected: Bool
    let isDraft: Bool

    var body: some View {
        let lineWidth = max(geometry.viewDistance(forImageDistance: Double(stroke.lineWidth)), 1)

        Path { path in
            guard let firstPoint = stroke.points.first else {
                return
            }

            path.move(to: geometry.viewPoint(forImagePoint: firstPoint))
            for point in stroke.points.dropFirst() {
                path.addLine(to: geometry.viewPoint(forImagePoint: point))
            }
        }
        .stroke(
            Color(annotationColor: stroke.color).opacity(stroke.opacity),
            style: StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round)
        )
        .overlay(alignment: .topLeading) {
            if isSelected || isDraft {
                Rectangle()
                    .strokeBorder(
                        Color.accentColor,
                        style: StrokeStyle(lineWidth: 2, dash: isDraft ? [6, 4] : [])
                    )
                    .frame(width: selectionRect.width, height: selectionRect.height)
                    .offset(x: selectionRect.minX, y: selectionRect.minY)
            }
        }
        .overlay(alignment: .topLeading) {
            if isSelected && !isDraft {
                ForEach(AnnotationResizeHandle.allCases, id: \.self) { handle in
                    ResizeHandleView()
                        .position(handle.viewPosition(in: selectionRect))
                }
            }
        }
        .allowsHitTesting(false)
    }
}

private struct BlurPreviewOverlay: View {
    let image: NSImage
    let imageFrame: CGRect
    let containerSize: CGSize
    let rect: CGRect
    let blurRadius: CGFloat
    let isSelected: Bool
    let isDraft: Bool

    var body: some View {
        PixelatedBlurPreviewImageView(
            image: image,
            imageFrame: imageFrame,
            rect: rect,
            pixelBlockSize: pixelBlockSize
        )
        .frame(width: containerSize.width, height: containerSize.height, alignment: .topLeading)
        .overlay(alignment: .topLeading) {
            if isSelected || isDraft {
                Rectangle()
                    .strokeBorder(
                        Color.accentColor,
                        style: StrokeStyle(lineWidth: 2, dash: isDraft ? [6, 4] : [])
                    )
                    .frame(width: rect.width, height: rect.height)
                    .offset(x: rect.minX, y: rect.minY)
            }
        }
        .overlay(alignment: .topLeading) {
            if isSelected && !isDraft {
                ForEach(AnnotationResizeHandle.allCases, id: \.self) { handle in
                    ResizeHandleView()
                        .position(handle.viewPosition(in: rect))
                }
            }
        }
        .allowsHitTesting(false)
    }

    private var pixelBlockSize: CGFloat {
        guard blurRadius.isFinite else {
            return CGFloat(AnnotationBlur.defaultRadius)
        }

        return max(blurRadius.rounded(), 4)
    }
}

private struct PixelatedBlurPreviewImageView: NSViewRepresentable {
    let image: NSImage
    let imageFrame: CGRect
    let rect: CGRect
    let pixelBlockSize: CGFloat

    func makeNSView(context: Context) -> PixelatedBlurPreviewNSView {
        let view = PixelatedBlurPreviewNSView()
        view.image = image
        view.imageFrame = imageFrame
        view.rect = rect
        view.pixelBlockSize = pixelBlockSize
        return view
    }

    func updateNSView(_ nsView: PixelatedBlurPreviewNSView, context: Context) {
        nsView.image = image
        nsView.imageFrame = imageFrame
        nsView.rect = rect
        nsView.pixelBlockSize = pixelBlockSize
    }
}

private final class PixelatedBlurPreviewNSView: NSView {
    var image: NSImage? {
        didSet {
            needsDisplay = true
        }
    }
    var imageFrame: CGRect = .zero {
        didSet {
            needsDisplay = true
        }
    }
    var rect: CGRect = .zero {
        didSet {
            needsDisplay = true
        }
    }
    var pixelBlockSize: CGFloat = CGFloat(AnnotationBlur.defaultRadius) {
        didSet {
            needsDisplay = true
        }
    }

    override var isFlipped: Bool {
        true
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let image,
            imageFrame.width > 0,
            imageFrame.height > 0,
            rect.width > 0,
            rect.height > 0,
            let graphicsContext = NSGraphicsContext.current
        else {
            return
        }

        let clippedRect = rect.intersection(imageFrame)
        guard !clippedRect.isNull,
            clippedRect.width > 0,
            clippedRect.height > 0
        else {
            return
        }

        let blockSize = max(pixelBlockSize, 1)
        let sampleSize = CGSize(
            width: max((imageFrame.width / blockSize).rounded(.up), 1),
            height: max((imageFrame.height / blockSize).rounded(.up), 1)
        )
        let sampledImage = NSImage(size: sampleSize)

        sampledImage.lockFocus()
        if let sampleContext = NSGraphicsContext.current {
            sampleContext.imageInterpolation = .medium
        }
        image.draw(
            in: CGRect(origin: .zero, size: sampleSize),
            from: CGRect(origin: .zero, size: image.size),
            operation: .copy,
            fraction: 1,
            respectFlipped: true,
            hints: nil
        )
        sampledImage.unlockFocus()

        graphicsContext.saveGraphicsState()
        NSBezierPath(rect: clippedRect).setClip()
        graphicsContext.imageInterpolation = .none
        sampledImage.draw(
            in: imageFrame,
            from: CGRect(origin: .zero, size: sampleSize),
            operation: .sourceOver,
            fraction: 1,
            respectFlipped: true,
            hints: nil
        )
        graphicsContext.restoreGraphicsState()
    }
}

private struct ResizeHandleView: View {
    var body: some View {
        RoundedRectangle(cornerRadius: 2)
            .fill(Color(nsColor: .windowBackgroundColor))
            .overlay {
                RoundedRectangle(cornerRadius: 2)
                    .strokeBorder(Color.accentColor, lineWidth: 1.5)
            }
            .frame(
                width: EditorCanvasMetrics.resizeHandleVisualSize,
                height: EditorCanvasMetrics.resizeHandleVisualSize
            )
    }
}

private struct EditorToolbar: View {
    @Binding var selectedTool: EditorTool
    @Binding var selectedStrokeColor: AnnotationColor
    @Binding var selectedStrokeLineWidth: CGFloat
    @Binding var selectedBlurRadius: Double
    let showsStrokeControls: Bool
    let showsBlurControls: Bool
    let showsTextControls: Bool
    let showsRectangleControls: Bool
    let selectedAnnotationID: UUID?
    @Binding var selectedRectangleColor: AnnotationColor
    @Binding var selectedRectangleLineWidth: CGFloat
    @Binding var selectedTextColor: AnnotationColor
    @Binding var selectedTextFontSize: CGFloat
    let statusMessage: String?
    let deleteAction: () -> Void
    let copyAction: () -> Void
    let copyAndDeleteAction: () -> Void
    let saveAction: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            HStack(spacing: 4) {
                ForEach(EditorTool.implementedTools) { tool in
                    ToolButton(
                        tool: tool,
                        isSelected: selectedTool == tool
                    ) {
                        selectedTool = tool
                    }
                }

                ToolbarIconButton(
                    systemImageName: "trash",
                    helpText: selectedAnnotationID == nil
                        ? "Select an annotation to delete" : "Delete selected annotation",
                    action: deleteAction
                )
                .disabled(selectedAnnotationID == nil)
                .keyboardShortcut(.delete, modifiers: [])
            }

            if showsStrokeControls {
                Divider()
                    .frame(height: 22)

                StrokeControls(
                    selectedColor: $selectedStrokeColor,
                    selectedLineWidth: $selectedStrokeLineWidth
                )
            }

            if showsBlurControls {
                Divider()
                    .frame(height: 22)

                BlurControls(selectedBlurRadius: $selectedBlurRadius)
            }

            if showsRectangleControls {
                Divider()
                    .frame(height: 22)

                RectangleControls(
                    selectedColor: $selectedRectangleColor,
                    selectedLineWidth: $selectedRectangleLineWidth
                )
            }

            if showsTextControls {
                Divider()
                    .frame(height: 22)

                TextControls(
                    selectedColor: $selectedTextColor,
                    selectedFontSize: $selectedTextFontSize
                )
            }

            Spacer()

            if let statusMessage {
                Text(statusMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 6) {
                ToolbarIconButton(
                    descriptor: .copyEdited(.image),
                    action: copyAction
                )

                ToolbarIconButton(
                    descriptor: .saveEdited(.image),
                    action: saveAction
                )
            }

            Divider()
                .frame(height: 22)

            ToolbarIconButton(
                descriptor: .copyAndMoveToTrash(.image),
                action: copyAndDeleteAction
            )
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color(nsColor: .windowBackgroundColor))
    }
}

private struct ToolButton: View {
    let tool: EditorTool
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: tool.systemImageName)
                .frame(width: 18, height: 18)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .frame(width: 32, height: 32)
        .background {
            RoundedRectangle(cornerRadius: 8)
                .fill(isSelected ? Color.accentColor : Color(nsColor: .controlBackgroundColor))
        }
        .foregroundStyle(isSelected ? Color.white : Color.primary)
        .accessibilityLabel(tool.displayName)
        .help(tool.helpText)
    }
}

private struct RectangleControls: View {
    @Binding var selectedColor: AnnotationColor
    @Binding var selectedLineWidth: CGFloat

    var body: some View {
        HStack(spacing: 10) {
            ColorSwatches(selectedColor: $selectedColor, helpText: "Rectangle color")

            HStack(spacing: 6) {
                Image(systemName: "lineweight")
                    .foregroundStyle(.secondary)

                Slider(
                    value: Binding(
                        get: { Double(selectedLineWidth) },
                        set: { selectedLineWidth = CGFloat($0) }
                    ),
                    in: Double(AnnotationRectangle.minimumLineWidth)...Double(AnnotationRectangle.maximumLineWidth),
                    step: 1
                )
                .frame(width: 88)

                Text("\(Int(selectedLineWidth.rounded()))")
                    .monospacedDigit()
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(width: 22, alignment: .trailing)
            }
            .help("Rectangle border thickness")
        }
    }
}

private struct TextControls: View {
    @Binding var selectedColor: AnnotationColor
    @Binding var selectedFontSize: CGFloat

    var body: some View {
        HStack(spacing: 10) {
            ColorSwatches(selectedColor: $selectedColor, helpText: "Text color")

            HStack(spacing: 6) {
                Image(systemName: "textformat.size")
                    .foregroundStyle(.secondary)

                Slider(
                    value: Binding(
                        get: { Double(selectedFontSize) },
                        set: { selectedFontSize = CGFloat($0) }
                    ),
                    in: Double(AnnotationText.minimumFontSize)...Double(AnnotationText.maximumFontSize),
                    step: 1
                )
                .frame(width: 88)

                Text("\(Int(selectedFontSize.rounded()))")
                    .monospacedDigit()
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(width: 26, alignment: .trailing)
            }
            .help("Text size")
        }
    }
}

private struct BlurControls: View {
    @Binding var selectedBlurRadius: Double

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "circle.grid.cross")
                .foregroundStyle(.secondary)

            Slider(
                value: $selectedBlurRadius,
                in: ScreenshotEditorState.minimumBlurRadius...ScreenshotEditorState.maximumBlurRadius,
                step: 1
            )
            .frame(width: 112)

            Text("\(Int(selectedBlurRadius.rounded()))")
                .monospacedDigit()
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 24, alignment: .trailing)
        }
        .help("Pixelated blur strength. Larger values make bigger color blocks.")
    }
}

private struct StrokeControls: View {
    @Binding var selectedColor: AnnotationColor
    @Binding var selectedLineWidth: CGFloat

    var body: some View {
        HStack(spacing: 10) {
            ColorSwatches(selectedColor: $selectedColor, helpText: "Stroke color")

            HStack(spacing: 6) {
                Image(systemName: "lineweight")
                    .foregroundStyle(.secondary)

                Slider(
                    value: Binding(
                        get: { Double(selectedLineWidth) },
                        set: { selectedLineWidth = CGFloat($0) }
                    ),
                    in: Double(
                        ScreenshotEditorState.minimumStrokeLineWidth)...Double(
                            ScreenshotEditorState.maximumStrokeLineWidth),
                    step: 1
                )
                .frame(width: 104)

                Text("\(Int(selectedLineWidth.rounded()))")
                    .monospacedDigit()
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(width: 22, alignment: .trailing)
            }
            .help("Line thickness")
        }
    }
}

private struct ColorSwatches: View {
    @Binding var selectedColor: AnnotationColor
    let helpText: String

    var body: some View {
        HStack(spacing: 5) {
            ForEach(AnnotationColor.palette, id: \.self) { color in
                ColorSwatchButton(
                    color: color,
                    isSelected: selectedColor == color,
                    helpText: helpText
                ) {
                    selectedColor = color
                }
            }
        }
    }
}

private struct ColorSwatchButton: View {
    let color: AnnotationColor
    let isSelected: Bool
    let helpText: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Circle()
                .fill(Color(annotationColor: color))
                .overlay {
                    Circle()
                        .strokeBorder(Color.primary.opacity(0.18), lineWidth: 1)
                }
                .overlay {
                    if isSelected {
                        Circle()
                            .strokeBorder(Color.accentColor, lineWidth: 3)
                            .padding(-3)
                    }
                }
                .frame(width: 18, height: 18)
        }
        .buttonStyle(.plain)
        .frame(width: 24, height: 24)
        .accessibilityLabel(helpText)
        .help(helpText)
    }
}

private struct ToolbarIconButton: View {
    let descriptor: EditorToolbarActionDescriptor
    let action: () -> Void

    init(
        systemImageName: String,
        helpText: String,
        action: @escaping () -> Void
    ) {
        self.descriptor = EditorToolbarActionDescriptor(
            systemImageName: systemImageName,
            visibleTitle: nil,
            accessibilityLabel: helpText,
            helpText: helpText,
            visualRole: .standard
        )
        self.action = action
    }

    init(
        descriptor: EditorToolbarActionDescriptor,
        action: @escaping () -> Void
    ) {
        self.descriptor = descriptor
        self.action = action
    }

    var body: some View {
        Button(role: buttonRole, action: action) {
            if let visibleTitle = descriptor.visibleTitle {
                Label(visibleTitle, systemImage: descriptor.systemImageName)
                    .labelStyle(.titleAndIcon)
                    .font(.caption)
            } else {
                Image(systemName: descriptor.systemImageName)
                    .frame(width: 18, height: 18)
            }
        }
        .buttonStyle(.bordered)
        .foregroundStyle(foregroundStyle)
        .accessibilityLabel(descriptor.accessibilityLabel)
        .help(descriptor.helpText)
    }

    private var buttonRole: ButtonRole? {
        descriptor.visualRole == .destructive ? .destructive : nil
    }

    private var foregroundStyle: Color {
        descriptor.visualRole == .destructive ? .red : .primary
    }
}

private extension Color {
    init(annotationColor: AnnotationColor) {
        self.init(
            red: Double(annotationColor.red),
            green: Double(annotationColor.green),
            blue: Double(annotationColor.blue)
        )
    }
}

private extension NSImage {
    var pixelSize: CGSize {
        let bestRepresentation = representations.max { first, second in
            first.pixelsWide * first.pixelsHigh < second.pixelsWide * second.pixelsHigh
        }

        guard let bestRepresentation,
            bestRepresentation.pixelsWide > 0,
            bestRepresentation.pixelsHigh > 0
        else {
            return size
        }

        return CGSize(width: bestRepresentation.pixelsWide, height: bestRepresentation.pixelsHigh)
    }
}

#Preview {
    ScreenshotEditorView(imageURL: URL(fileURLWithPath: "/tmp/capture.png"))
}
