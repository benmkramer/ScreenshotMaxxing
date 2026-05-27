//
//  CaptureHistoryData.swift
//  ScreenshotMaxxing
//
//  Created by Ben Kramer on 5/26/26.
//

import Foundation
import SwiftData

enum CaptureHistoryData {
    static var newestFirstSortDescriptors: [SortDescriptor<Capture>] {
        [SortDescriptor(\Capture.createdAt, order: .reverse)]
    }

    static func newestFirstFetchDescriptor() -> FetchDescriptor<Capture> {
        FetchDescriptor(sortBy: newestFirstSortDescriptors)
    }

    static func previewFilePath(for capture: Capture) -> String {
        capture.editedFilePath ?? capture.originalFilePath
    }

    static func fileExists(for capture: Capture, fileManager: FileManager = .default) -> Bool {
        fileManager.fileExists(atPath: previewFilePath(for: capture))
    }

    static func detailText(for capture: Capture) -> String {
        "\(displayMode(for: capture.captureMode)) - \(capture.width)x\(capture.height)"
    }

    static func displayMode(for captureMode: String) -> String {
        guard let mode = CaptureMode(rawValue: captureMode) else {
            return captureMode.capitalized
        }

        return mode.displayName
    }
}
