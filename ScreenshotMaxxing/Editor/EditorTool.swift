//
//  EditorTool.swift
//  ScreenshotMaxxing
//
//  Created by Ben Kramer on 5/26/26.
//

import Foundation

enum EditorTool: String, CaseIterable, Identifiable {
    case select
    case blur
    case pen
    case highlighter
    case rectangle
    case arrow
    case text

    static let implementedTools: [EditorTool] = [.select, .blur, .pen, .highlighter]

    var id: String {
        rawValue
    }

    var displayName: String {
        switch self {
        case .select:
            "Select"
        case .blur:
            "Blur"
        case .pen:
            "Pen"
        case .highlighter:
            "Highlighter"
        case .rectangle:
            "Rectangle"
        case .arrow:
            "Arrow"
        case .text:
            "Text"
        }
    }

    var systemImageName: String {
        switch self {
        case .select:
            "cursorarrow"
        case .blur:
            "eye.slash"
        case .pen:
            "pencil.tip"
        case .highlighter:
            "highlighter"
        case .rectangle:
            "rectangle"
        case .arrow:
            "arrow.up.right"
        case .text:
            "textformat"
        }
    }

    var helpText: String {
        switch self {
        case .select:
            "Select an annotation"
        case .blur:
            "Draw a blur effect"
        case .pen:
            "Draw a solid line"
        case .highlighter:
            "Draw a translucent highlight"
        case .rectangle:
            "Draw a rectangle"
        case .arrow:
            "Draw an arrow"
        case .text:
            "Add text"
        }
    }

    var strokeKind: AnnotationStrokeKind? {
        switch self {
        case .pen:
            .pen
        case .highlighter:
            .highlighter
        case .select, .blur, .rectangle, .arrow, .text:
            nil
        }
    }

    var showsStrokeControls: Bool {
        strokeKind != nil
    }
}
