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
    @State private var editorState: ScreenshotEditorState
    @State private var draftBlurRect: CGRect?
    @State private var statusMessage: String?

    init(imageURL: URL, capture: Capture? = nil) {
        self.imageURL = imageURL
        self.capture = capture
        self.image = NSImage(contentsOf: imageURL)
        self._editorState = State(initialValue: ScreenshotEditorState(originalImageURL: imageURL))
    }

    var body: some View {
        Group {
            if let image {
                VStack(spacing: 0) {
                    EditorToolbar(
                        selectedTool: $editorState.selectedTool,
                        selectedAnnotationID: editorState.selectedAnnotationID,
                        statusMessage: statusMessage,
                        deleteAction: removeSelectedAnnotation,
                        copyAction: copyEditedImage,
                        saveAction: saveEditedImage
                    )
                    Divider()
                    ScreenshotImageCanvas(
                        image: image,
                        editorState: $editorState,
                        draftBlurRect: $draftBlurRect
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

            if EditorClipboard.copyPNGData(pngData) {
                statusMessage = "Copied"
            } else {
                statusMessage = "Copy failed"
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
            let editedFileURL = try EditorFileSaver().saveEditedPNG(
                pngData,
                originalFileName: capture?.fileName ?? imageURL.lastPathComponent,
                capture: capture
            )

            statusMessage = "Saved \(editedFileURL.lastPathComponent)"
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    private func removeSelectedAnnotation() {
        editorState.removeSelectedAnnotation()
    }
}

struct ScreenshotImageCanvas: View {
    let image: NSImage
    @Binding var editorState: ScreenshotEditorState
    @Binding var draftBlurRect: CGRect?
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
                    if annotation.type == .blur {
                        RedactionPreviewOverlay(
                            image: image,
                            imageFrame: geometry.imageRect,
                            containerSize: proxy.size,
                            rect: geometry.viewRect(forImageRect: annotation.rect),
                            blurRadius: previewBlurRadius,
                            isSelected: annotation.id == editorState.selectedAnnotationID,
                            isDraft: false
                        )
                    }
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
                    return
                }

                guard editorState.selectedTool == .blur else {
                    draftBlurRect = nil
                    return
                }

                draftBlurRect = geometry.imageRect(
                    fromViewStart: value.startLocation,
                    toViewEnd: value.location
                )
            }
            .onEnded { value in
                defer {
                    activeAnnotationDrag = nil
                    draftBlurRect = nil
                }

                guard activeAnnotationDrag == nil else {
                    return
                }

                guard editorState.selectedTool == .blur,
                      let imageRect = geometry.imageRect(
                        fromViewStart: value.startLocation,
                        toViewEnd: value.location
                      ) else {
                    return
                }

                editorState.addBlurRect(imageRect)
            }
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
                originalRect: annotation.rect,
                resizeHandle: resizeHandle
            )
        }

        guard let startImagePoint = geometry.imagePoint(forViewPoint: startLocation),
              let annotationID = editorState.annotationID(containing: startImagePoint),
              let annotation = editorState.annotation(id: annotationID) else {
            return nil
        }

        return AnnotationDrag(annotationID: annotationID, originalRect: annotation.rect)
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
                from: annotationDrag.originalRect,
                handle: resizeHandle,
                by: translation,
                within: image.pixelSize
            )
        } else {
            editorState.moveAnnotation(
                id: annotationDrag.annotationID,
                from: annotationDrag.originalRect,
                by: translation,
                within: image.pixelSize
            )
        }
    }
}

private struct AnnotationDrag: Equatable {
    let annotationID: UUID
    let originalRect: CGRect
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
                .blur(radius: blurRadius)
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
    let selectedAnnotationID: UUID?
    let statusMessage: String?
    let deleteAction: () -> Void
    let copyAction: () -> Void
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
            }

            Spacer()

            if let statusMessage {
                Text(statusMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            ToolbarIconButton(
                systemImageName: "trash",
                helpText: selectedAnnotationID == nil ? "Select a redaction to remove it" : "Remove selected redaction",
                action: deleteAction
            )
            .disabled(selectedAnnotationID == nil)
            .keyboardShortcut(.delete, modifiers: [])

            ToolbarIconButton(
                systemImageName: "doc.on.doc",
                helpText: "Copy edited image",
                action: copyAction
            )

            ToolbarIconButton(
                systemImageName: "square.and.arrow.down",
                helpText: "Save edited image",
                action: saveAction
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
