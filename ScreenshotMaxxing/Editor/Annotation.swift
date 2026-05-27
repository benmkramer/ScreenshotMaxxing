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
}

enum AnnotationType: Equatable {
    case blur
    case rectangle
    case arrow
    case text(String)
}
