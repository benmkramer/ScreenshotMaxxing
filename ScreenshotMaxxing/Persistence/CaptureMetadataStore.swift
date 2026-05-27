//
//  CaptureMetadataStore.swift
//  ScreenshotMaxxing
//
//  Created by Ben Kramer on 5/26/26.
//

import Foundation
import ImageIO
import SwiftData

@MainActor
final class CaptureMetadataStore {
    private let modelContainer: ModelContainer

    init() {
        self.modelContainer = PersistenceController.sharedModelContainer
    }

    init(modelContainer: ModelContainer) {
        self.modelContainer = modelContainer
    }

    @discardableResult
    func saveCapture(result: CaptureResult) throws -> Capture {
        let dimensions = try imageDimensions(for: result.fileURL)
        let capture = Capture(
            fileName: result.fileURL.lastPathComponent,
            captureMode: result.mode.rawValue,
            width: dimensions.width,
            height: dimensions.height,
            originalFilePath: result.fileURL.path()
        )

        modelContainer.mainContext.insert(capture)
        try modelContainer.mainContext.save()

        return capture
    }

    func updateEditedFilePath(for capture: Capture, editedFileURL: URL) throws {
        capture.editedFilePath = editedFileURL.path()
        try modelContainer.mainContext.save()
    }

    private func imageDimensions(for url: URL) throws -> (width: Int, height: Int) {
        guard let imageSource = CGImageSourceCreateWithURL(url as CFURL, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(imageSource, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int else {
            throw CaptureMetadataError.unreadableImage(url)
        }

        return (width, height)
    }
}

enum CaptureMetadataError: LocalizedError, Equatable {
    case unreadableImage(URL)

    var errorDescription: String? {
        switch self {
        case .unreadableImage(let url):
            "Could not read image dimensions for \(url.path())."
        }
    }
}
