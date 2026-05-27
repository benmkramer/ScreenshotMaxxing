//
//  CaptureMode.swift
//  ScreenshotMaxxing
//
//  Created by Ben Kramer on 5/26/26.
//

import Foundation

enum CaptureMode: String, CaseIterable {
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
        rawValue
    }

    func screencaptureArguments(outputURL: URL) -> [String] {
        switch self {
        case .area:
            ["-i", "-s", "-x", outputURL.fileSystemPath]
        case .window:
            ["-i", "-w", "-x", outputURL.fileSystemPath]
        case .fullscreen:
            ["-x", outputURL.fileSystemPath]
        }
    }
}
