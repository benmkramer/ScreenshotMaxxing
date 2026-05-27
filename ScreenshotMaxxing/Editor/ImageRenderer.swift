//
//  ImageRenderer.swift
//  ScreenshotMaxxing
//
//  Created by Ben Kramer on 5/26/26.
//

import CoreImage
import Foundation
import ImageIO
import UniformTypeIdentifiers

struct ImageRenderer {
    private let context: CIContext
    private let blurRadius: Double

    init(blurRadius: Double = 12) {
        self.context = CIContext()
        self.blurRadius = blurRadius
    }

    func renderPNG(imageURL: URL, annotations: [Annotation]) throws -> Data {
        let sourceImage = try loadImage(from: imageURL)
        let renderedImage = render(sourceImage: sourceImage, annotations: annotations)

        guard let cgImage = context.createCGImage(renderedImage, from: sourceImage.extent) else {
            throw ImageRendererError.renderFailed
        }

        return try pngData(from: cgImage)
    }

    func render(sourceImage: CIImage, annotations: [Annotation]) -> CIImage {
        let blurRects = annotations.compactMap { annotation -> CGRect? in
            guard annotation.type == .blur else {
                return nil
            }

            return coreImageRect(forImageRect: annotation.rect, imageHeight: sourceImage.extent.height)
                .intersection(sourceImage.extent)
        }
        let usableBlurRects = blurRects.filter { !$0.isNull && $0.width > 0 && $0.height > 0 }

        guard !usableBlurRects.isEmpty else {
            return sourceImage.cropped(to: sourceImage.extent)
        }

        let blurredImage = sourceImage
            .clampedToExtent()
            .applyingFilter("CIGaussianBlur", parameters: [kCIInputRadiusKey: blurRadius])
            .cropped(to: sourceImage.extent)

        return usableBlurRects.reduce(sourceImage) { currentImage, blurRect in
            blurredImage
                .cropped(to: blurRect)
                .composited(over: currentImage)
                .cropped(to: sourceImage.extent)
        }
    }

    func coreImageRect(forImageRect imageRect: CGRect, imageHeight: CGFloat) -> CGRect {
        let rect = imageRect.standardized

        return CGRect(
            x: rect.minX,
            y: imageHeight - rect.maxY,
            width: rect.width,
            height: rect.height
        )
    }

    private func loadImage(from url: URL) throws -> CIImage {
        guard let imageSource = CGImageSourceCreateWithURL(url as CFURL, nil),
              let cgImage = CGImageSourceCreateImageAtIndex(imageSource, 0, nil) else {
            throw ImageRendererError.unreadableImage(url)
        }

        return CIImage(cgImage: cgImage)
    }

    private func pngData(from cgImage: CGImage) throws -> Data {
        let data = NSMutableData()

        guard let destination = CGImageDestinationCreateWithData(
            data,
            UTType.png.identifier as CFString,
            1,
            nil
        ) else {
            throw ImageRendererError.renderFailed
        }

        CGImageDestinationAddImage(destination, cgImage, nil)

        guard CGImageDestinationFinalize(destination) else {
            throw ImageRendererError.renderFailed
        }

        return data as Data
    }
}

enum ImageRendererError: LocalizedError, Equatable {
    case unreadableImage(URL)
    case renderFailed

    var errorDescription: String? {
        switch self {
        case .unreadableImage(let url):
            "Could not read image at \(url.path())."
        case .renderFailed:
            "Could not render edited image."
        }
    }
}
