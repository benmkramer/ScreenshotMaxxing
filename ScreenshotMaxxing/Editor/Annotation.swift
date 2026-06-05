//
//  Annotation.swift
//  ScreenshotMaxxing
//
//  Created by Ben Kramer on 5/26/26.
//

import CoreGraphics
import Foundation

struct Annotation: Identifiable, Equatable {
    var id: UUID
    var type: AnnotationType
    var rect: CGRect

    init(id: UUID = UUID(), type: AnnotationType, rect: CGRect) {
        self.id = id
        self.type = type
        self.rect = rect.standardized
    }

    func withRect(_ rect: CGRect) -> Annotation {
        Annotation(id: id, type: type, rect: rect)
    }
}

enum AnnotationType: Equatable {
    case blur(AnnotationBlur)
    case stroke(AnnotationStroke)
    case rectangle
    case arrow(AnnotationArrow)
    case text(String)
}

struct AnnotationBlur: Equatable {
    static let minimumRadius: Double = 1
    static let maximumRadius: Double = 80
    static let defaultRadius: Double = 12

    var radius: Double

    init(radius: Double = Self.defaultRadius) {
        self.radius = Self.clampedRadius(radius)
    }

    var normalized: AnnotationBlur {
        AnnotationBlur(radius: radius)
    }

    static func clampedRadius(_ radius: Double) -> Double {
        guard radius.isFinite else {
            return defaultRadius
        }

        return min(max(radius, minimumRadius), maximumRadius)
    }
}

struct AnnotationArrow: Equatable {
    var startPoint: CGPoint
    var endPoint: CGPoint
    var color: AnnotationColor
    var lineWidth: CGFloat

    var style: AnnotationStrokeStyle {
        get {
            AnnotationStrokeStyle(color: color, lineWidth: lineWidth)
        }
        set {
            color = newValue.color
            lineWidth = newValue.lineWidth
        }
    }

    var visibleBounds: CGRect {
        let pointBounds = CGRect(
            x: min(startPoint.x, endPoint.x),
            y: min(startPoint.y, endPoint.y),
            width: abs(endPoint.x - startPoint.x),
            height: abs(endPoint.y - startPoint.y)
        )
        let padding = arrowHeadLength + max(lineWidth, 1) / 2

        return pointBounds.insetBy(dx: -padding, dy: -padding).standardized
    }

    var hasVisibleLength: Bool {
        hypot(endPoint.x - startPoint.x, endPoint.y - startPoint.y) > 0.5
    }

    var arrowHeadLength: CGFloat {
        max(lineWidth * 3, 12)
    }

    var arrowHeadAngle: CGFloat {
        .pi / 6
    }

    mutating func transformPoints(from sourceRect: CGRect, to targetRect: CGRect) {
        let sourceRect = sourceRect.standardized
        let targetRect = targetRect.standardized

        guard !sourceRect.isNull,
              !targetRect.isNull,
              sourceRect.width > 0,
              sourceRect.height > 0 else {
            let translation = CGSize(
                width: targetRect.minX - sourceRect.minX,
                height: targetRect.minY - sourceRect.minY
            )
            startPoint = CGPoint(x: startPoint.x + translation.width, y: startPoint.y + translation.height)
            endPoint = CGPoint(x: endPoint.x + translation.width, y: endPoint.y + translation.height)
            return
        }

        startPoint = startPoint.transformed(from: sourceRect, to: targetRect)
        endPoint = endPoint.transformed(from: sourceRect, to: targetRect)
    }

    func contains(_ point: CGPoint, hitPadding: CGFloat) -> Bool {
        guard visibleBounds.insetBy(dx: -hitPadding, dy: -hitPadding).contains(point) else {
            return false
        }

        let threshold = lineWidth / 2 + hitPadding
        if point.distance(toSegmentFrom: startPoint, to: endPoint) <= threshold {
            return true
        }

        return arrowHeadSegments.contains { headStart, headEnd in
            point.distance(toSegmentFrom: headStart, to: headEnd) <= threshold
        }
    }

    var arrowHeadSegments: [(CGPoint, CGPoint)] {
        let angle = atan2(endPoint.y - startPoint.y, endPoint.x - startPoint.x)

        return [
            arrowHeadPoint(at: angle + .pi - arrowHeadAngle),
            arrowHeadPoint(at: angle + .pi + arrowHeadAngle)
        ].map { (endPoint, $0) }
    }

    private func arrowHeadPoint(at angle: CGFloat) -> CGPoint {
        CGPoint(
            x: endPoint.x + cos(angle) * arrowHeadLength,
            y: endPoint.y + sin(angle) * arrowHeadLength
        )
    }
}

struct AnnotationStroke: Equatable {
    var kind: AnnotationStrokeKind
    var points: [CGPoint]
    var color: AnnotationColor
    var lineWidth: CGFloat

    var opacity: CGFloat {
        kind.opacity
    }

    var style: AnnotationStrokeStyle {
        get {
            AnnotationStrokeStyle(color: color, lineWidth: lineWidth)
        }
        set {
            color = newValue.color
            lineWidth = newValue.lineWidth
        }
    }

    var visibleBounds: CGRect {
        Self.visibleBounds(for: points, lineWidth: lineWidth)
    }

    var hasVisibleLength: Bool {
        guard let firstPoint = points.first else {
            return false
        }

        return points.contains { point in
            hypot(point.x - firstPoint.x, point.y - firstPoint.y) > 0.5
        }
    }

    mutating func transformPoints(from sourceRect: CGRect, to targetRect: CGRect) {
        let sourceRect = sourceRect.standardized
        let targetRect = targetRect.standardized

        guard !sourceRect.isNull,
              !targetRect.isNull,
              sourceRect.width > 0,
              sourceRect.height > 0 else {
            let translation = CGSize(
                width: targetRect.minX - sourceRect.minX,
                height: targetRect.minY - sourceRect.minY
            )
            points = points.map { point in
                CGPoint(x: point.x + translation.width, y: point.y + translation.height)
            }
            return
        }

        let scaleX = targetRect.width / sourceRect.width
        let scaleY = targetRect.height / sourceRect.height

        points = points.map { point in
            CGPoint(
                x: targetRect.minX + (point.x - sourceRect.minX) * scaleX,
                y: targetRect.minY + (point.y - sourceRect.minY) * scaleY
            )
        }
    }

    func contains(_ point: CGPoint, hitPadding: CGFloat) -> Bool {
        let threshold = lineWidth / 2 + hitPadding

        guard visibleBounds.insetBy(dx: -hitPadding, dy: -hitPadding).contains(point) else {
            return false
        }

        guard points.count > 1 else {
            return points.first.map { hypot(point.x - $0.x, point.y - $0.y) <= threshold } ?? false
        }

        return zip(points, points.dropFirst()).contains { startPoint, endPoint in
            point.distance(toSegmentFrom: startPoint, to: endPoint) <= threshold
        }
    }

    private static func visibleBounds(for points: [CGPoint], lineWidth: CGFloat) -> CGRect {
        guard let firstPoint = points.first else {
            return .null
        }

        var minX = firstPoint.x
        var minY = firstPoint.y
        var maxX = firstPoint.x
        var maxY = firstPoint.y

        for point in points.dropFirst() {
            minX = min(minX, point.x)
            minY = min(minY, point.y)
            maxX = max(maxX, point.x)
            maxY = max(maxY, point.y)
        }
        let strokePadding = max(lineWidth, 1) / 2
        let pointBounds = CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)

        return pointBounds.insetBy(dx: -strokePadding, dy: -strokePadding).standardized
    }
}

struct AnnotationStrokeStyle: Codable, Equatable {
    static let minimumLineWidth: CGFloat = 1
    static let maximumLineWidth: CGFloat = 48
    static let defaultPen = AnnotationStrokeStyle(color: .red, lineWidth: lineWidth(atScale: 0.25))
    static let defaultHighlighter = AnnotationStrokeStyle(color: .yellow, lineWidth: lineWidth(atScale: 0.75))

    var color: AnnotationColor
    var lineWidth: CGFloat

    init(color: AnnotationColor, lineWidth: CGFloat) {
        self.color = color
        self.lineWidth = Self.clampedLineWidth(lineWidth)
    }

    var normalized: AnnotationStrokeStyle {
        AnnotationStrokeStyle(color: color, lineWidth: lineWidth)
    }

    static func lineWidth(atScale scale: CGFloat) -> CGFloat {
        let clampedScale = min(max(scale, 0), 1)
        let lineWidth = minimumLineWidth + (maximumLineWidth - minimumLineWidth) * clampedScale

        return lineWidth.rounded()
    }

    static func clampedLineWidth(_ lineWidth: CGFloat) -> CGFloat {
        guard lineWidth.isFinite else {
            return minimumLineWidth
        }

        return min(max(lineWidth, minimumLineWidth), maximumLineWidth)
    }
}

struct StrokeToolSettings: Codable, Equatable {
    static let defaultSettings = StrokeToolSettings(
        pen: .defaultPen,
        highlighter: .defaultHighlighter
    )

    var pen: AnnotationStrokeStyle
    var highlighter: AnnotationStrokeStyle

    func style(for kind: AnnotationStrokeKind) -> AnnotationStrokeStyle {
        switch kind {
        case .pen:
            pen
        case .highlighter:
            highlighter
        }
    }

    mutating func update(_ style: AnnotationStrokeStyle, for kind: AnnotationStrokeKind) {
        switch kind {
        case .pen:
            pen = style.normalized
        case .highlighter:
            highlighter = style.normalized
        }
    }

    var normalized: StrokeToolSettings {
        StrokeToolSettings(
            pen: pen.normalized,
            highlighter: highlighter.normalized
        )
    }
}

enum AnnotationStrokeKind: Equatable {
    case pen
    case highlighter

    var opacity: CGFloat {
        switch self {
        case .pen:
            1
        case .highlighter:
            0.35
        }
    }
}

struct AnnotationColor: Codable, Equatable, Hashable {
    static let red = AnnotationColor(red: 0.94, green: 0.16, blue: 0.12)
    static let yellow = AnnotationColor(red: 1, green: 0.78, blue: 0.12)
    static let green = AnnotationColor(red: 0.18, green: 0.68, blue: 0.35)
    static let blue = AnnotationColor(red: 0.12, green: 0.44, blue: 0.92)
    static let black = AnnotationColor(red: 0.08, green: 0.08, blue: 0.09)
    static let white = AnnotationColor(red: 1, green: 1, blue: 1)

    static let palette: [AnnotationColor] = [.red, .yellow, .green, .blue, .black, .white]

    var red: CGFloat
    var green: CGFloat
    var blue: CGFloat
}

private extension CGPoint {
    func transformed(from sourceRect: CGRect, to targetRect: CGRect) -> CGPoint {
        CGPoint(
            x: targetRect.minX + (x - sourceRect.minX) * targetRect.width / sourceRect.width,
            y: targetRect.minY + (y - sourceRect.minY) * targetRect.height / sourceRect.height
        )
    }

    func distance(toSegmentFrom startPoint: CGPoint, to endPoint: CGPoint) -> CGFloat {
        let segment = CGSize(width: endPoint.x - startPoint.x, height: endPoint.y - startPoint.y)
        let segmentLengthSquared = segment.width * segment.width + segment.height * segment.height

        guard segmentLengthSquared > 0 else {
            return hypot(x - startPoint.x, y - startPoint.y)
        }

        let projection = ((x - startPoint.x) * segment.width + (y - startPoint.y) * segment.height) / segmentLengthSquared
        let clampedProjection = min(max(projection, 0), 1)
        let closestPoint = CGPoint(
            x: startPoint.x + clampedProjection * segment.width,
            y: startPoint.y + clampedProjection * segment.height
        )

        return hypot(x - closestPoint.x, y - closestPoint.y)
    }
}
