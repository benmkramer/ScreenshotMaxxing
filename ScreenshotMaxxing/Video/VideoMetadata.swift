//
//  VideoMetadata.swift
//  ScreenshotMaxxing
//
//  Created by Codex on 5/29/26.
//

import AppKit
import AVFoundation
import Foundation

struct VideoMetadata: Equatable {
    let durationSeconds: Double
    let dimensions: CGSize
}

enum VideoMetadataReader {
    static func metadata(for url: URL) throws -> VideoMetadata {
        let asset = AVURLAsset(url: url)
        let durationSeconds = asset.duration.seconds

        guard durationSeconds.isFinite, durationSeconds > 0 else {
            throw VideoMetadataError.unreadableVideo(url)
        }

        guard let videoTrack = asset.tracks(withMediaType: .video).first else {
            throw VideoMetadataError.unreadableVideo(url)
        }

        let transformedSize = videoTrack.naturalSize.applying(videoTrack.preferredTransform)
        let dimensions = CGSize(
            width: abs(transformedSize.width),
            height: abs(transformedSize.height)
        )

        guard dimensions.width > 0, dimensions.height > 0 else {
            throw VideoMetadataError.unreadableVideo(url)
        }

        return VideoMetadata(durationSeconds: durationSeconds, dimensions: dimensions)
    }
}

struct VideoThumbnailGenerator {
    private let fileManager: FileManager

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    func writeThumbnail(
        for videoURL: URL,
        originalFileName: String,
        baseDirectory: URL? = nil
    ) throws -> URL {
        let directories = try FileLocations.ensureCaptureDirectories(
            baseDirectory: baseDirectory,
            fileManager: fileManager
        )
        let thumbnailURL = FileLocations.uniqueThumbnailFileURL(
            originalFileName: originalFileName,
            directories: directories
        )
        let asset = AVURLAsset(url: videoURL)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        let duration = asset.duration.seconds
        let midpoint = duration.isFinite && duration > 1 ? CMTime(seconds: min(duration / 2, 1), preferredTimescale: 600) : .zero
        let image = try generator.copyCGImage(at: midpoint, actualTime: nil)
        let imageRep = NSBitmapImageRep(cgImage: image)

        guard let pngData = imageRep.representation(using: .png, properties: [:]) else {
            throw VideoMetadataError.thumbnailFailed(videoURL)
        }

        try pngData.write(to: thumbnailURL, options: .atomic)
        return thumbnailURL
    }
}

enum VideoMetadataError: LocalizedError, Equatable {
    case unreadableVideo(URL)
    case thumbnailFailed(URL)

    var errorDescription: String? {
        switch self {
        case .unreadableVideo(let url):
            "Could not read video metadata for \(url.fileSystemPath)."
        case .thumbnailFailed(let url):
            "Could not create a thumbnail for \(url.fileSystemPath)."
        }
    }
}
