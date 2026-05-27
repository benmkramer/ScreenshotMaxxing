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
    case rectangle
    case arrow
    case text

    static let implementedTools: [EditorTool] = [.select, .blur]

    var id: String {
        rawValue
    }

    var displayName: String {
        switch self {
        case .select:
            "Select"
        case .blur:
            "Blur"
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
            "drop"
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
            "Select a redaction"
        case .blur:
            "Draw a blur redaction"
        case .rectangle:
            "Draw a rectangle"
        case .arrow:
            "Draw an arrow"
        case .text:
            "Add text"
        }
    }
}
