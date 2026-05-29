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
}

struct RecordingResult: Equatable {
    let mode: RecordingMode
    let fileURL: URL
    let durationSeconds: Double
    let width: Int
    let height: Int
    let thumbnailURL: URL
}
