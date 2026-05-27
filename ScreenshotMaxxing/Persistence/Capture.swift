//
//  Capture.swift
//  ScreenshotMaxxing
//
//  Created by Ben Kramer on 5/26/26.
//

import Foundation
import SwiftData

@Model
final class Capture {
    var id: UUID
    var createdAt: Date
    var fileName: String
    var captureMode: String
    var width: Int
    var height: Int
    var originalFilePath: String
    var editedFilePath: String?
    var favorite: Bool

    init(
        id: UUID = UUID(),
        createdAt: Date = Date(),
        fileName: String,
        captureMode: String,
        width: Int,
        height: Int,
        originalFilePath: String,
        editedFilePath: String? = nil,
        favorite: Bool = false
    ) {
        self.id = id
        self.createdAt = createdAt
        self.fileName = fileName
        self.captureMode = captureMode
        self.width = width
        self.height = height
        self.originalFilePath = originalFilePath
        self.editedFilePath = editedFilePath
        self.favorite = favorite
    }
}
