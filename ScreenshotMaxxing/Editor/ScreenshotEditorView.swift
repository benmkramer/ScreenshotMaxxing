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

    init(imageURL: URL) {
        self.imageURL = imageURL
        self.image = NSImage(contentsOf: imageURL)
    }

    var body: some View {
        Group {
            if let image {
                ScreenshotImageCanvas(image: image)
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
