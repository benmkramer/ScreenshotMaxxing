//
//  VideoExporter.swift
//  ScreenshotMaxxing
//
//  Created by Codex on 5/29/26.
//

import AVFoundation
import AudioToolbox
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

    func export(
        videoURL: URL,
        editState: VideoEditState,
        outputURL: URL,
        monoAudio: Bool = false
    ) async throws -> VideoExportResult {
        let plan = VideoExportPlanner.plan(for: editState)
        guard !plan.keptRanges.isEmpty else {
            throw VideoExportError.emptySelection
        }

        if fileManager.fileExists(atPath: outputURL.fileSystemPath) {
            try fileManager.removeItem(at: outputURL)
        }

        let asset = AVURLAsset(url: videoURL)
        let composition = try await makeComposition(asset: asset, plan: plan)

        // Only the mono path with audio present needs a second transcode pass;
        // everything else writes straight to the requested output.
        let needsMonoPass = monoAudio && !composition.tracks(withMediaType: .audio).isEmpty
        let exportSessionOutputURL = needsMonoPass ? temporaryOutputURL() : outputURL

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

        if fileManager.fileExists(atPath: exportSessionOutputURL.fileSystemPath) {
            try fileManager.removeItem(at: exportSessionOutputURL)
        }

        exportSession.outputURL = exportSessionOutputURL
        exportSession.outputFileType = .mp4
        exportSession.shouldOptimizeForNetworkUse = true

        try await export(exportSession)

        if needsMonoPass {
            do {
                try await downmixAudioToMono(from: exportSessionOutputURL, to: outputURL)
            } catch {
                try? fileManager.removeItem(at: exportSessionOutputURL)
                throw error
            }

            try? fileManager.removeItem(at: exportSessionOutputURL)
        }

        let metadata = try VideoMetadataReader.metadata(for: outputURL)
        return VideoExportResult(
            fileURL: outputURL,
            durationSeconds: metadata.durationSeconds,
            dimensions: metadata.dimensions
        )
    }

    private func makeComposition(asset: AVAsset, plan: VideoCompositionPlan) async throws -> AVMutableComposition {
        let composition = AVMutableComposition()
        let mediaTypes: [AVMediaType] = [.video, .audio]

        for mediaType in mediaTypes {
            for sourceTrack in try await asset.loadTracks(withMediaType: mediaType) {
                guard
                    let compositionTrack = composition.addMutableTrack(
                        withMediaType: mediaType,
                        preferredTrackID: kCMPersistentTrackID_Invalid
                    )
                else {
                    throw VideoExportError.compositionFailed
                }

                if mediaType == .video {
                    compositionTrack.preferredTransform = try await sourceTrack.load(.preferredTransform)
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

    private func temporaryOutputURL() -> URL {
        fileManager.temporaryDirectory
            .appendingPathComponent("ScreenshotMaxxing-mono-\(UUID().uuidString).mp4")
    }

    /// Re-encodes the audio of an already-edited file down to a single channel while
    /// passing the (already cleanly cut) video through untouched.
    private func downmixAudioToMono(from sourceURL: URL, to outputURL: URL) async throws {
        if fileManager.fileExists(atPath: outputURL.fileSystemPath) {
            try fileManager.removeItem(at: outputURL)
        }

        let asset = AVURLAsset(url: sourceURL)
        // Load tracks asynchronously; synchronous access can race the asset still loading.
        guard let audioTrack = try await asset.loadTracks(withMediaType: .audio).first else {
            throw VideoExportError.compositionFailed
        }
        let videoTrack = try await asset.loadTracks(withMediaType: .video).first

        let reader = try AVAssetReader(asset: asset)
        let writer = try AVAssetWriter(outputURL: outputURL, fileType: .mp4)

        var pairs: [(output: AVAssetReaderOutput, input: AVAssetWriterInput)] = []

        if let videoTrack {
            let preferredTransform = try await videoTrack.load(.preferredTransform)
            // Passthrough inputs need the source format up front, otherwise `canAdd`
            // can't validate the (still-compressed) samples and rejects the input.
            let videoFormatDescription = try await videoTrack.load(.formatDescriptions).first
            let videoOutput = AVAssetReaderTrackOutput(track: videoTrack, outputSettings: nil)
            videoOutput.alwaysCopiesSampleData = false
            guard reader.canAdd(videoOutput) else {
                throw VideoExportError.compositionFailed
            }
            reader.add(videoOutput)

            let videoInput = AVAssetWriterInput(
                mediaType: .video,
                outputSettings: nil,
                sourceFormatHint: videoFormatDescription
            )
            videoInput.expectsMediaDataInRealTime = false
            videoInput.transform = preferredTransform
            guard writer.canAdd(videoInput) else {
                throw VideoExportError.compositionFailed
            }
            writer.add(videoInput)
            pairs.append((videoOutput, videoInput))
        }

        let sampleRate = try await audioSampleRate(for: audioTrack)
        var monoLayout = AudioChannelLayout()
        monoLayout.mChannelLayoutTag = kAudioChannelLayoutTag_Mono
        let monoLayoutData = Data(bytes: &monoLayout, count: MemoryLayout<AudioChannelLayout>.size)

        let pcmSettings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsNonInterleaved: false,
            AVNumberOfChannelsKey: 1,
            AVSampleRateKey: sampleRate,
            AVChannelLayoutKey: monoLayoutData,
        ]
        let audioOutput = AVAssetReaderAudioMixOutput(audioTracks: [audioTrack], audioSettings: pcmSettings)
        audioOutput.alwaysCopiesSampleData = false
        guard reader.canAdd(audioOutput) else {
            throw VideoExportError.compositionFailed
        }
        reader.add(audioOutput)

        let aacSettings: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVNumberOfChannelsKey: 1,
            AVSampleRateKey: sampleRate,
            AVEncoderBitRateKey: 96_000,
            AVChannelLayoutKey: monoLayoutData,
        ]
        let audioInput = AVAssetWriterInput(mediaType: .audio, outputSettings: aacSettings)
        audioInput.expectsMediaDataInRealTime = false
        guard writer.canAdd(audioInput) else {
            throw VideoExportError.compositionFailed
        }
        writer.add(audioInput)
        pairs.append((audioOutput, audioInput))

        guard reader.startReading() else {
            throw reader.error ?? VideoExportError.exportFailed
        }
        guard writer.startWriting() else {
            throw writer.error ?? VideoExportError.exportFailed
        }
        writer.startSession(atSourceTime: .zero)

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let group = DispatchGroup()

            for (index, pair) in pairs.enumerated() {
                let queue = DispatchQueue(label: "VideoExporter.mono.\(index)")
                group.enter()
                pair.input.requestMediaDataWhenReady(on: queue) {
                    while pair.input.isReadyForMoreMediaData {
                        // End of stream, reader failure, or a rejected append all mean this
                        // input is done; anything else loops until the buffer fills, at which
                        // point we return and get called again.
                        guard reader.status == .reading,
                            let sample = pair.output.copyNextSampleBuffer()
                        else {
                            pair.input.markAsFinished()
                            group.leave()
                            return
                        }

                        if !pair.input.append(sample) {
                            pair.input.markAsFinished()
                            group.leave()
                            return
                        }
                    }
                }
            }

            group.notify(queue: .global()) {
                if reader.status == .failed {
                    continuation.resume(throwing: reader.error ?? VideoExportError.exportFailed)
                    return
                }

                writer.finishWriting {
                    switch writer.status {
                    case .completed:
                        continuation.resume()
                    case .cancelled:
                        continuation.resume(throwing: VideoExportError.exportCancelled)
                    default:
                        continuation.resume(throwing: writer.error ?? VideoExportError.exportFailed)
                    }
                }
            }
        }
    }

    private func audioSampleRate(for track: AVAssetTrack) async throws -> Double {
        let formatDescriptions = try await track.load(.formatDescriptions)
        guard let formatDescription = formatDescriptions.first,
            let basicDescription = CMAudioFormatDescriptionGetStreamBasicDescription(formatDescription)
        else {
            return 44_100
        }

        let sampleRate = basicDescription.pointee.mSampleRate
        return sampleRate > 0 ? sampleRate : 44_100
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
