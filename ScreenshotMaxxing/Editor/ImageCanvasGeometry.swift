//
//  ImageCanvasGeometry.swift
//  ScreenshotMaxxing
//
//  Created by Ben Kramer on 5/26/26.
//

import CoreGraphics

struct ImageCanvasGeometry: Equatable {
    let imageSize: CGSize
    let containerSize: CGSize

    var imageRect: CGRect {
        guard imageSize.width > 0,
              imageSize.height > 0,
              containerSize.width > 0,
              containerSize.height > 0 else {
            return .zero
        }

        let scale = min(containerSize.width / imageSize.width, containerSize.height / imageSize.height)
        let fittedSize = CGSize(width: imageSize.width * scale, height: imageSize.height * scale)
        let origin = CGPoint(
            x: (containerSize.width - fittedSize.width) / 2,
            y: (containerSize.height - fittedSize.height) / 2
        )

        return CGRect(origin: origin, size: fittedSize)
    }

    func imagePoint(forViewPoint viewPoint: CGPoint) -> CGPoint? {
        let rect = imageRect

        guard rect.width > 0, rect.height > 0, rect.contains(viewPoint) else {
            return nil
        }

        return CGPoint(
            x: ((viewPoint.x - rect.minX) / rect.width) * imageSize.width,
            y: ((viewPoint.y - rect.minY) / rect.height) * imageSize.height
        )
    }

    func viewPoint(forImagePoint imagePoint: CGPoint) -> CGPoint {
        let rect = imageRect

        guard imageSize.width > 0,
              imageSize.height > 0,
              rect.width > 0,
              rect.height > 0 else {
            return .zero
        }

        return CGPoint(
            x: rect.minX + (imagePoint.x / imageSize.width) * rect.width,
            y: rect.minY + (imagePoint.y / imageSize.height) * rect.height
        )
    }

    func imageRect(forViewRect viewRect: CGRect) -> CGRect? {
        let rect = imageRect
        let clippedRect = viewRect.standardized.intersection(rect)

        guard rect.width > 0,
              rect.height > 0,
              !clippedRect.isNull,
              clippedRect.width > 0,
              clippedRect.height > 0 else {
            return nil
        }

        let origin = CGPoint(
            x: ((clippedRect.minX - rect.minX) / rect.width) * imageSize.width,
            y: ((clippedRect.minY - rect.minY) / rect.height) * imageSize.height
        )
        let size = CGSize(
            width: (clippedRect.width / rect.width) * imageSize.width,
            height: (clippedRect.height / rect.height) * imageSize.height
        )

        return CGRect(origin: origin, size: size)
    }

    func imageRect(fromViewStart startPoint: CGPoint, toViewEnd endPoint: CGPoint) -> CGRect? {
        let viewRect = CGRect(
            x: min(startPoint.x, endPoint.x),
            y: min(startPoint.y, endPoint.y),
            width: abs(endPoint.x - startPoint.x),
            height: abs(endPoint.y - startPoint.y)
        )

        return imageRect(forViewRect: viewRect)
    }

    func imageTranslation(fromViewStart startPoint: CGPoint, toViewEnd endPoint: CGPoint) -> CGSize {
        let rect = imageRect

        guard imageSize.width > 0,
              imageSize.height > 0,
              rect.width > 0,
              rect.height > 0 else {
            return .zero
        }

        return CGSize(
            width: ((endPoint.x - startPoint.x) / rect.width) * imageSize.width,
            height: ((endPoint.y - startPoint.y) / rect.height) * imageSize.height
        )
    }

    func viewRect(forImageRect imageRect: CGRect) -> CGRect {
        let rect = self.imageRect

        guard imageSize.width > 0,
              imageSize.height > 0,
              rect.width > 0,
              rect.height > 0 else {
            return .zero
        }

        let standardizedRect = imageRect.standardized
        let origin = CGPoint(
            x: rect.minX + (standardizedRect.minX / imageSize.width) * rect.width,
            y: rect.minY + (standardizedRect.minY / imageSize.height) * rect.height
        )
        let size = CGSize(
            width: (standardizedRect.width / imageSize.width) * rect.width,
            height: (standardizedRect.height / imageSize.height) * rect.height
        )

        return CGRect(origin: origin, size: size)
    }

    func viewDistance(forImageDistance imageDistance: Double) -> CGFloat {
        let rect = imageRect

        guard imageSize.width > 0, rect.width > 0 else {
            return 0
        }

        return CGFloat(imageDistance) * (rect.width / imageSize.width)
    }
}
