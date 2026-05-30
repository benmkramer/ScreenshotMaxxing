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
    @State private var statusMessage: String?
    private static let successfulActionCloseDelay: TimeInterval = 0.6

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
        self._editorState = State(initialValue: ScreenshotEditorState(
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
                        showsStrokeControls: editorState.selectedTool.showsStrokeControls || editorState.selectedAnnotationUsesStrokeStyle,
                        selectedAnnotationID: editorState.selectedAnnotationID,
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
                        draftStroke: $draftStroke
                    )
                }
            } else {
                unavailableImageView
            }
        }
        .frame(minWidth: 640, minHeight: 420)
        .background(Color(nsColor: .windowBackgroundColor))
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
                statusMessage = "Copied image to clipboard"
                closeAfterShowingSuccess()
                return
            }

            do {
                try CaptureMetadataStore().deleteCaptureFromHistoryAndDisk(capture)
                statusMessage = "Copied and deleted capture"
                closeAfterShowingSuccess()
            } catch {
                statusMessage = "Copied, but delete failed: \(error.localizedDescription)"
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
        editorState.removeSelectedAnnotation()
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
    @State private var activeAnnotationDrag: AnnotationDrag?

    var body: some View {
        GeometryReader { proxy in
            let geometry = ImageCanvasGeometry(
                imageSize: image.pixelSize,
                containerSize: proxy.size
            )
            let previewBlurRadius = geometry.viewDistance(forImageDistance: ImageRenderer.defaultBlurRadius)

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
                        containerSize: proxy.size,
                        geometry: geometry,
                        blurRadius: previewBlurRadius,
                        isSelected: annotation.id == editorState.selectedAnnotationID
                    )
                }

                if let draftBlurRect {
                    RedactionPreviewOverlay(
                        image: image,
                        imageFrame: geometry.imageRect,
                        containerSize: proxy.size,
                        rect: geometry.viewRect(forImageRect: draftBlurRect),
                        blurRadius: previewBlurRadius,
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
            }
            .contentShape(Rectangle())
            .gesture(canvasDragGesture(geometry: geometry))
            .simultaneousGesture(selectTapGesture(geometry: geometry))
        }
    }

    private func canvasDragGesture(geometry: ImageCanvasGeometry) -> some Gesture {
        DragGesture(minimumDistance: 1, coordinateSpace: .local)
            .onChanged { value in
                if activeAnnotationDrag == nil,
                   let activeDrag = annotationDrag(startingAt: value.startLocation, geometry: geometry) {
                    activeAnnotationDrag = activeDrag
                    editorState.selectAnnotation(id: activeDrag.annotationID)
                }

                if let activeAnnotationDrag {
                    let translation = geometry.imageTranslation(
                        fromViewStart: value.startLocation,
                        toViewEnd: value.location
                    )
                    updateActiveAnnotationDrag(activeAnnotationDrag, by: translation)
                    draftBlurRect = nil
                    draftStroke = nil
                    return
                }

                switch editorState.selectedTool {
                case .blur:
                    draftStroke = nil
                    draftBlurRect = geometry.imageRect(
                        fromViewStart: value.startLocation,
                        toViewEnd: value.location
                    )
                case .pen, .highlighter:
                    draftBlurRect = nil
                    updateDraftStroke(with: value, geometry: geometry)
                case .select, .rectangle, .arrow, .text:
                    draftBlurRect = nil
                    draftStroke = nil
                }
            }
            .onEnded { value in
                defer {
                    activeAnnotationDrag = nil
                    draftBlurRect = nil
                    draftStroke = nil
                }

                guard activeAnnotationDrag == nil else {
                    return
                }

                if editorState.selectedTool == .blur,
                   let imageRect = geometry.imageRect(
                        fromViewStart: value.startLocation,
                        toViewEnd: value.location
                   ) {
                    editorState.addBlurRect(imageRect)
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
              let imagePoint = geometry.imagePoint(forViewPoint: value.location) else {
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

    private func strokePoints(from value: DragGesture.Value, geometry: ImageCanvasGeometry) -> [CGPoint] {
        guard let startImagePoint = geometry.imagePoint(forViewPoint: value.startLocation),
              let endImagePoint = geometry.imagePoint(forViewPoint: value.location) else {
            return []
        }

        return [startImagePoint, endImagePoint]
    }

    private func selectTapGesture(geometry: ImageCanvasGeometry) -> some Gesture {
        SpatialTapGesture(coordinateSpace: .local)
            .onEnded { value in
                if resizeHandle(at: value.location, geometry: geometry) != nil {
                    return
                }

                guard let imagePoint = geometry.imagePoint(forViewPoint: value.location) else {
                    editorState.selectAnnotation(id: nil)
                    return
                }

                editorState.selectAnnotation(containing: imagePoint)
            }
    }

    private func annotationDrag(startingAt startLocation: CGPoint, geometry: ImageCanvasGeometry) -> AnnotationDrag? {
        if let selectedAnnotationID = editorState.selectedAnnotationID,
           let annotation = editorState.annotation(id: selectedAnnotationID),
           let resizeHandle = resizeHandle(at: startLocation, geometry: geometry) {
            return AnnotationDrag(
                annotationID: selectedAnnotationID,
                originalAnnotation: annotation,
                resizeHandle: resizeHandle
            )
        }

        guard let startImagePoint = geometry.imagePoint(forViewPoint: startLocation),
              let annotationID = editorState.annotationID(containing: startImagePoint),
              let annotation = editorState.annotation(id: annotationID) else {
            return nil
        }

        return AnnotationDrag(annotationID: annotationID, originalAnnotation: annotation)
    }

    private func resizeHandle(at viewPoint: CGPoint, geometry: ImageCanvasGeometry) -> AnnotationResizeHandle? {
        guard let selectedAnnotationID = editorState.selectedAnnotationID,
              let annotation = editorState.annotation(id: selectedAnnotationID) else {
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
    let blurRadius: CGFloat
    let isSelected: Bool

    var body: some View {
        switch annotation.type {
        case .blur:
            RedactionPreviewOverlay(
                image: image,
                imageFrame: imageFrame,
                containerSize: containerSize,
                rect: geometry.viewRect(forImageRect: annotation.rect),
                blurRadius: blurRadius,
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
        case .rectangle, .arrow, .text:
            EmptyView()
        }
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

private struct RedactionPreviewOverlay: View {
    let image: NSImage
    let imageFrame: CGRect
    let containerSize: CGSize
    let rect: CGRect
    let blurRadius: CGFloat
    let isSelected: Bool
    let isDraft: Bool

    var body: some View {
        ZStack(alignment: .topLeading) {
            Image(nsImage: image)
                .resizable()
                .interpolation(.high)
                .frame(width: imageFrame.width, height: imageFrame.height)
                .position(x: imageFrame.midX, y: imageFrame.midY)
                .blur(radius: blurRadius, opaque: true)
        }
        .frame(width: containerSize.width, height: containerSize.height, alignment: .topLeading)
        .mask(alignment: .topLeading) {
            Rectangle()
                .frame(width: rect.width, height: rect.height)
                .offset(x: rect.minX, y: rect.minY)
        }
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
    let showsStrokeControls: Bool
    let selectedAnnotationID: UUID?
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
                    helpText: selectedAnnotationID == nil ? "Select an annotation to delete" : "Delete selected annotation",
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

            Spacer()

            if let statusMessage {
                Text(statusMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 6) {
                ToolbarIconButton(
                    systemImageName: "doc.on.doc",
                    helpText: "Save edited image and copy it to the clipboard",
                    action: copyAction
                )

                ToolbarIconButton(
                    systemImageName: "square.and.arrow.down",
                    helpText: "Save edited image, reveal it in Finder, and copy the file path",
                    action: saveAction
                )
            }

            Divider()
                .frame(height: 22)

            ToolbarIconButton(
                systemImageName: "clipboard",
                helpText: "Copy image to clipboard and delete it from history and disk",
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

private struct StrokeControls: View {
    @Binding var selectedColor: AnnotationColor
    @Binding var selectedLineWidth: CGFloat

    var body: some View {
        HStack(spacing: 10) {
            HStack(spacing: 5) {
                ForEach(AnnotationColor.palette, id: \.self) { color in
                    ColorSwatchButton(
                        color: color,
                        isSelected: selectedColor == color
                    ) {
                        selectedColor = color
                    }
                }
            }

            HStack(spacing: 6) {
                Image(systemName: "lineweight")
                    .foregroundStyle(.secondary)

                Slider(
                    value: Binding(
                        get: { Double(selectedLineWidth) },
                        set: { selectedLineWidth = CGFloat($0) }
                    ),
                    in: Double(ScreenshotEditorState.minimumStrokeLineWidth)...Double(ScreenshotEditorState.maximumStrokeLineWidth),
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

private struct ColorSwatchButton: View {
    let color: AnnotationColor
    let isSelected: Bool
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
        .accessibilityLabel("Stroke color")
        .help("Stroke color")
    }
}

private struct ToolbarIconButton: View {
    let systemImageName: String
    let helpText: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImageName)
                .frame(width: 18, height: 18)
        }
        .buttonStyle(.bordered)
        .accessibilityLabel(helpText)
        .help(helpText)
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
              bestRepresentation.pixelsHigh > 0 else {
            return size
        }

        return CGSize(width: bestRepresentation.pixelsWide, height: bestRepresentation.pixelsHigh)
    }
}

#Preview {
    ScreenshotEditorView(imageURL: URL(fileURLWithPath: "/tmp/capture.png"))
}
