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
            originalFilePath: result.fileURL.fileSystemPath
        )

        modelContainer.mainContext.insert(capture)
        try modelContainer.mainContext.save()

        return capture
    }

    @discardableResult
    func saveEditedCapture(editedFileURL: URL, sourceCapture: Capture?) throws -> Capture {
        let dimensions = try imageDimensions(for: editedFileURL)
        let capture = Capture(
            fileName: editedFileURL.lastPathComponent,
            captureMode: sourceCapture?.captureMode ?? "edited",
            width: dimensions.width,
            height: dimensions.height,
            originalFilePath: editedFileURL.fileSystemPath
        )

        modelContainer.mainContext.insert(capture)
        try modelContainer.mainContext.save()

        return capture
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
            "Could not read image dimensions for \(url.fileSystemPath)."
        }
    }
}
