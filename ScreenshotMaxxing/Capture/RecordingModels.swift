//
//  RecordingModels.swift
//  ScreenshotMaxxing
//
//  Created by Codex on 5/29/26.
//

import Foundation

enum RecordingMode: String, CaseIterable {
    case area
    case window
    case fullscreen

    var displayName: String {
        switch self {
        case .area:
            "Area"
        case .window:
            "Window"
        case .fullscreen:
            "Fullscreen"
        }
    }

    var fileNamePrefix: String {
        "recording-\(rawValue)"
    }
}

struct RecordingOptions: Equatable {
    let mode: RecordingMode
    let microphoneEnabled: Bool
    let systemAudioEnabled: Bool

    init(mode: RecordingMode, microphoneEnabled: Bool, systemAudioEnabled: Bool = false) {
        self.mode = mode
        self.microphoneEnabled = microphoneEnabled
        self.systemAudioEnabled = systemAudioEnabled
    }

    var outputContainer: RecordingOutputContainer {
        microphoneEnabled ? .mov : .mp4
    }
}

enum RecordingOutputContainer: Equatable {
    case mp4
    case mov

    var fileExtension: String {
        switch self {
        case .mp4:
            "mp4"
        case .mov:
            "mov"
        }
    }

    var displayName: String {
        switch self {
        case .mp4:
            "MP4"
        case .mov:
            "MOV"
        }
    }
}

struct RecordingResult: Equatable {
    let mode: RecordingMode
    let fileURL: URL
    let durationSeconds: Double
    let width: Int
    let height: Int
    let thumbnailURL: URL
    let microphoneEnabled: Bool
    let systemAudioEnabled: Bool

    init(
        mode: RecordingMode,
        fileURL: URL,
        durationSeconds: Double,
        width: Int,
        height: Int,
        thumbnailURL: URL,
        microphoneEnabled: Bool = false,
        systemAudioEnabled: Bool = false
    ) {
        self.mode = mode
        self.fileURL = fileURL
        self.durationSeconds = durationSeconds
        self.width = width
        self.height = height
        self.thumbnailURL = thumbnailURL
        self.microphoneEnabled = microphoneEnabled
        self.systemAudioEnabled = systemAudioEnabled
    }
}
