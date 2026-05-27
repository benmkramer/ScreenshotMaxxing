//
//  ImageRenderer.swift
//  ScreenshotMaxxing
//
//  Created by Ben Kramer on 5/26/26.
//

import CoreImage
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

struct ImageRenderer {
    static let defaultBlurRadius: Double = 12

    private let context: CIContext
    private let blurRadius: Double

    init(blurRadius: Double = Self.defaultBlurRadius) {
        self.context = CIContext()
        self.blurRadius = blurRadius
    }

    func renderPNG(imageURL: URL, annotations: [Annotation]) throws -> Data {
        let sourceImage = try loadImage(from: imageURL)
        let renderedImage = try render(sourceImage: sourceImage, annotations: annotations)

        guard let cgImage = context.createCGImage(renderedImage, from: sourceImage.extent) else {
            throw ImageRendererError.renderFailed
        }

        return try pngData(from: cgImage)
    }

    func render(sourceImage: CIImage, annotations: [Annotation]) throws -> CIImage {
        try annotations.reduce(sourceImage.cropped(to: sourceImage.extent)) { currentImage, annotation in
            switch annotation.type {
            case .blur:
                renderBlur(on: currentImage, imageRect: annotation.rect)
            case .stroke(let stroke):
                try renderStroke(stroke, over: currentImage)
            case .rectangle, .arrow, .text:
                currentImage
            }
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

    private func renderBlur(on image: CIImage, imageRect: CGRect) -> CIImage {
        let blurRect = coreImageRect(forImageRect: imageRect, imageHeight: image.extent.height)
            .intersection(image.extent)

        guard !blurRect.isNull, blurRect.width > 0, blurRect.height > 0 else {
            return image.cropped(to: image.extent)
        }

        let blurredImage = image
            .clampedToExtent()
            .applyingFilter("CIGaussianBlur", parameters: [kCIInputRadiusKey: blurRadius])
            .cropped(to: image.extent)

        return blurredImage
            .cropped(to: blurRect)
            .composited(over: image)
            .cropped(to: image.extent)
    }

    private func renderStroke(_ stroke: AnnotationStroke, over image: CIImage) throws -> CIImage {
        guard stroke.points.count > 1, stroke.hasVisibleLength else {
            return image.cropped(to: image.extent)
        }

        let width = Int(image.extent.width.rounded(.up))
        let height = Int(image.extent.height.rounded(.up))

        guard width > 0, height > 0,
              let cgImage = context.createCGImage(image, from: image.extent),
              let bitmapContext = CGContext(
                data: nil,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: 0,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
              ) else {
            throw ImageRendererError.renderFailed
        }

        bitmapContext.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
        draw(stroke, in: bitmapContext, imageHeight: CGFloat(height))

        guard let renderedCGImage = bitmapContext.makeImage() else {
            throw ImageRendererError.renderFailed
        }

        return CIImage(cgImage: renderedCGImage).cropped(to: image.extent)
    }

    private func draw(_ stroke: AnnotationStroke, in context: CGContext, imageHeight: CGFloat) {
        guard let firstPoint = stroke.points.first else {
            return
        }

        context.saveGState()
        context.translateBy(x: 0, y: imageHeight)
        context.scaleBy(x: 1, y: -1)
        context.setBlendMode(.normal)
        context.setStrokeColor(stroke.color.cgColor(opacity: stroke.opacity))
        context.setLineWidth(stroke.lineWidth)
        context.setLineCap(.round)
        context.setLineJoin(.round)

        context.beginPath()
        context.move(to: firstPoint)
        for point in stroke.points.dropFirst() {
            context.addLine(to: point)
        }
        context.strokePath()
        context.restoreGState()
    }
}

enum ImageRendererError: LocalizedError, Equatable {
    case unreadableImage(URL)
    case renderFailed

    var errorDescription: String? {
        switch self {
        case .unreadableImage(let url):
            "Could not read image at \(url.fileSystemPath)."
        case .renderFailed:
            "Could not render edited image."
        }
    }
}

private extension AnnotationColor {
    func cgColor(opacity: CGFloat) -> CGColor {
        CGColor(red: red, green: green, blue: blue, alpha: opacity)
    }
}
