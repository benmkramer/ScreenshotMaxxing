//
//  ScreenshotEditorView.swift
//  ScreenshotMaxxing
//
//  Created by Ben Kramer on 5/26/26.
//

import SwiftUI

struct ScreenshotEditorView: View {
    let imageURL: URL
    private let image: NSImage?
    @State private var editorState: ScreenshotEditorState

    init(imageURL: URL) {
        self.imageURL = imageURL
        self.image = NSImage(contentsOf: imageURL)
        self._editorState = State(initialValue: ScreenshotEditorState(originalImageURL: imageURL))
    }

    var body: some View {
        Group {
            if let image {
                VStack(spacing: 0) {
                    EditorToolbar(selectedTool: $editorState.selectedTool)
                    Divider()
                    ScreenshotImageCanvas(image: image, annotations: editorState.annotations)
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
        }
        .padding(32)
    }
}

struct ScreenshotImageCanvas: View {
    let image: NSImage
    let annotations: [Annotation]

    var body: some View {
        GeometryReader { proxy in
            let geometry = ImageCanvasGeometry(
                imageSize: image.pixelSize,
                containerSize: proxy.size
            )

            ZStack(alignment: .topLeading) {
                Color(nsColor: .underPageBackgroundColor)

                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .frame(width: geometry.imageRect.width, height: geometry.imageRect.height)
                    .position(x: geometry.imageRect.midX, y: geometry.imageRect.midY)
                    .accessibilityLabel("Screenshot")
            }
        }
    }
}

private struct EditorToolbar: View {
    @Binding var selectedTool: EditorTool

    var body: some View {
        HStack(spacing: 8) {
            Picker("Tool", selection: $selectedTool) {
                ForEach(EditorTool.allCases) { tool in
                    Image(systemName: tool.systemImageName)
                        .help(tool.displayName)
                        .tag(tool)
                }
            }
            .pickerStyle(.segmented)
            .frame(width: 180)

            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color(nsColor: .windowBackgroundColor))
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
