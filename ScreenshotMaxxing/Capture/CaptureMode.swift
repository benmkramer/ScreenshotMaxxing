//
//  CaptureMode.swift
//  ScreenshotMaxxing
//
//  Created by Ben Kramer on 5/26/26.
//

import Foundation

enum CaptureMode: String, CaseIterable {
    case area

    var displayName: String {
        switch self {
        case .area:
            "Area"
        }
    }

    var fileNamePrefix: String {
        rawValue
    }

    func screencaptureArguments(outputURL: URL) -> [String] {
        switch self {
        case .area:
            ["-i", "-s", "-x", outputURL.path()]
        }
    }
}
