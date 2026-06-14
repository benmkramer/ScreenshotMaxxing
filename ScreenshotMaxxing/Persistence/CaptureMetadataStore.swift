//
//  CaptureMetadataStore.swift
//  ScreenshotMaxxing
//
//  Created by Ben Kramer on 5/26/26.
//

import Foundation
import AVFoundation
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
    func saveCapture(result: RecordingResult) throws -> Capture {
        let capture = Capture(
            fileName: result.fileURL.lastPathComponent,
            captureMode: result.mode.rawValue,
            mediaType: CaptureMediaType.video.rawValue,
            width: result.width,
            height: result.height,
            durationSeconds: result.durationSeconds,
            microphoneEnabled: result.microphoneEnabled,
            systemAudioEnabled: result.systemAudioEnabled,
            thumbnailFilePath: result.thumbnailURL.fileSystemPath,
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

    func deleteCaptureFromHistoryAndDisk(
        _ capture: Capture,
        fileManager: FileManager = .default,
        fileTrash: CaptureFileTrashing = FileManager.default
    ) throws {
        for filePath in uniqueFilePaths(for: capture) where fileManager.fileExists(atPath: filePath) {
            try fileTrash.moveItemToTrash(at: URL(fileURLWithPath: filePath))
        }

        modelContainer.mainContext.delete(capture)
        try modelContainer.mainContext.save()
    }

    @discardableResult
    func saveEditedVideoCapture(
        editedFileURL: URL,
        thumbnailURL: URL,
        sourceCapture: Capture?,
        durationSeconds: Double,
        dimensions: CGSize
    ) throws -> Capture {
        let capture = Capture(
            fileName: editedFileURL.lastPathComponent,
            captureMode: sourceCapture?.captureMode ?? "edited",
            mediaType: CaptureMediaType.video.rawValue,
            width: Int(dimensions.width.rounded()),
            height: Int(dimensions.height.rounded()),
            durationSeconds: durationSeconds,
            microphoneEnabled: sourceCapture?.microphoneEnabled ?? false,
            systemAudioEnabled: sourceCapture?.systemAudioEnabled ?? false,
            thumbnailFilePath: thumbnailURL.fileSystemPath,
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
            let height = properties[kCGImagePropertyPixelHeight] as? Int
        else {
            throw CaptureMetadataError.unreadableImage(url)
        }

        return (width, height)
    }

    private func uniqueFilePaths(for capture: Capture) -> [String] {
        var filePaths: [String] = []

        let possibleFilePaths = [
            capture.originalFilePath,
            capture.editedFilePath,
            capture.thumbnailFilePath,
        ]

        for filePath in possibleFilePaths.compactMap({ $0 }) where !filePaths.contains(filePath) {
            filePaths.append(filePath)
        }

        return filePaths
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
