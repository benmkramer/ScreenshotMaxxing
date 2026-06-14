//
//  VideoExporter.swift
//  ScreenshotMaxxing
//
//  Created by Codex on 5/29/26.
//

import AVFoundation
import Foundation

struct VideoExportResult: Equatable {
    let fileURL: URL
    let durationSeconds: Double
    let dimensions: CGSize
}

struct VideoExporter {
    private let fileManager: FileManager

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    func export(videoURL: URL, editState: VideoEditState, outputURL: URL) async throws -> VideoExportResult {
        let plan = VideoExportPlanner.plan(for: editState)
        guard !plan.keptRanges.isEmpty else {
            throw VideoExportError.emptySelection
        }

        if fileManager.fileExists(atPath: outputURL.fileSystemPath) {
            try fileManager.removeItem(at: outputURL)
        }

        let asset = AVURLAsset(url: videoURL)
        let composition = try makeComposition(asset: asset, plan: plan)

        guard
            let exportSession = AVAssetExportSession(
                asset: composition,
                presetName: AVAssetExportPresetHighestQuality
            )
        else {
            throw VideoExportError.exportUnavailable
        }

        guard exportSession.supportedFileTypes.contains(.mp4) else {
            throw VideoExportError.mp4ExportUnavailable
        }

        exportSession.outputURL = outputURL
        exportSession.outputFileType = .mp4
        exportSession.shouldOptimizeForNetworkUse = true

        try await export(exportSession)

        let metadata = try VideoMetadataReader.metadata(for: outputURL)
        return VideoExportResult(
            fileURL: outputURL,
            durationSeconds: metadata.durationSeconds,
            dimensions: metadata.dimensions
        )
    }

    private func makeComposition(asset: AVAsset, plan: VideoCompositionPlan) throws -> AVMutableComposition {
        let composition = AVMutableComposition()
        let mediaTypes: [AVMediaType] = [.video, .audio]

        for mediaType in mediaTypes {
            for sourceTrack in asset.tracks(withMediaType: mediaType) {
                guard
                    let compositionTrack = composition.addMutableTrack(
                        withMediaType: mediaType,
                        preferredTrackID: kCMPersistentTrackID_Invalid
                    )
                else {
                    throw VideoExportError.compositionFailed
                }

                if mediaType == .video {
                    compositionTrack.preferredTransform = sourceTrack.preferredTransform
                }

                var insertionTime = CMTime.zero
                for range in plan.keptRanges {
                    let start = CMTime(seconds: range.start, preferredTimescale: 600)
                    let duration = CMTime(seconds: range.duration, preferredTimescale: 600)
                    try compositionTrack.insertTimeRange(
                        CMTimeRange(start: start, duration: duration),
                        of: sourceTrack,
                        at: insertionTime
                    )
                    insertionTime = CMTimeAdd(insertionTime, duration)
                }
            }
        }

        guard !composition.tracks(withMediaType: .video).isEmpty else {
            throw VideoExportError.compositionFailed
        }

        return composition
    }

    private func export(_ exportSession: AVAssetExportSession) async throws {
        try await withCheckedThrowingContinuation { continuation in
            exportSession.exportAsynchronously {
                switch exportSession.status {
                case .completed:
                    continuation.resume()
                case .failed:
                    continuation.resume(throwing: exportSession.error ?? VideoExportError.exportFailed)
                case .cancelled:
                    continuation.resume(throwing: VideoExportError.exportCancelled)
                default:
                    continuation.resume(throwing: VideoExportError.exportFailed)
                }
            }
        }
    }
}

enum VideoExportError: LocalizedError, Equatable {
    case emptySelection
    case compositionFailed
    case exportUnavailable
    case mp4ExportUnavailable
    case exportCancelled
    case exportFailed

    var errorDescription: String? {
        switch self {
        case .emptySelection:
            "Choose at least one kept range before exporting."
        case .compositionFailed:
            "Could not build the edited video composition."
        case .exportUnavailable:
            "Video export is unavailable for this edit."
        case .mp4ExportUnavailable:
            "AVFoundation cannot export this edit as MP4."
        case .exportCancelled:
            "Video export was canceled."
        case .exportFailed:
            "Video export failed."
        }
    }
}
