//
//  Capture.swift
//  ScreenshotMaxxing
//
//  Created by Ben Kramer on 5/26/26.
//

import Foundation
import SwiftData

enum CaptureMediaType: String, CaseIterable {
    case image
    case video
}

@Model
final class Capture {
    var id: UUID
    var createdAt: Date
    var fileName: String
    var captureMode: String
    var mediaType: String = CaptureMediaType.image.rawValue
    var width: Int
    var height: Int
    var durationSeconds: Double?
    var microphoneEnabled: Bool = false
    var systemAudioEnabled: Bool = false
    var thumbnailFilePath: String?
    var originalFilePath: String
    var editedFilePath: String?
    var favorite: Bool

    init(
        id: UUID = UUID(),
        createdAt: Date = Date(),
        fileName: String,
        captureMode: String,
        mediaType: String = CaptureMediaType.image.rawValue,
        width: Int,
        height: Int,
        durationSeconds: Double? = nil,
        microphoneEnabled: Bool = false,
        systemAudioEnabled: Bool = false,
        thumbnailFilePath: String? = nil,
        originalFilePath: String,
        editedFilePath: String? = nil,
        favorite: Bool = false
    ) {
        self.id = id
        self.createdAt = createdAt
        self.fileName = fileName
        self.captureMode = captureMode
        self.mediaType = mediaType
        self.width = width
        self.height = height
        self.durationSeconds = durationSeconds
        self.microphoneEnabled = microphoneEnabled
        self.systemAudioEnabled = systemAudioEnabled
        self.thumbnailFilePath = thumbnailFilePath
        self.originalFilePath = originalFilePath
        self.editedFilePath = editedFilePath
        self.favorite = favorite
    }
}
