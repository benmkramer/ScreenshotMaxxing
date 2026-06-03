//
//  VideoSilenceDetector.swift
//  ScreenshotMaxxing
//
//  Created by Codex on 6/2/26.
//

import AVFoundation
import Foundation

struct VideoSilenceDetectionConfiguration: Equatable, Sendable {
    let minimumSilenceDuration: Double
    let silenceThresholdDecibels: Double
    let maximumNoiseGapDuration: Double
    let edgePaddingDuration: Double

    nonisolated init(
        minimumSilenceDuration: Double = 1,
        silenceThresholdDecibels: Double = -45,
        maximumNoiseGapDuration: Double = 0.12,
        edgePaddingDuration: Double = 0.08
    ) {
        self.minimumSilenceDuration = max(minimumSilenceDuration, 0)
        self.silenceThresholdDecibels = silenceThresholdDecibels
        self.maximumNoiseGapDuration = max(maximumNoiseGapDuration, 0)
        self.edgePaddingDuration = max(edgePaddingDuration, 0)
    }

    nonisolated var silenceThresholdAmplitude: Double {
        pow(10, silenceThresholdDecibels / 20)
    }
}

struct VideoSilenceDetector: Sendable {
    struct AudioLevelWindow: Equatable, Sendable {
        let start: Double
        let end: Double
        let rmsAmplitude: Double

        nonisolated init(start: Double, end: Double, rmsAmplitude: Double) {
            self.start = start
            self.end = end
            self.rmsAmplitude = rmsAmplitude
        }
    }

    nonisolated init() {}

    nonisolated func silentRanges(
        in videoURL: URL,
        configuration: VideoSilenceDetectionConfiguration = VideoSilenceDetectionConfiguration()
    ) throws -> [VideoTimeRange] {
        let asset = AVURLAsset(url: videoURL)
        let audioTracks = asset.tracks(withMediaType: .audio)

        guard !audioTracks.isEmpty else {
            throw VideoSilenceDetectionError.noAudioTrack
        }

        let reader = try AVAssetReader(asset: asset)
        let output = AVAssetReaderAudioMixOutput(
            audioTracks: audioTracks,
            audioSettings: Self.readerAudioSettings
        )
        output.alwaysCopiesSampleData = false

        guard reader.canAdd(output) else {
            throw VideoSilenceDetectionError.readerUnavailable
        }

        reader.add(output)

        guard reader.startReading() else {
            throw VideoSilenceDetectionError.readerFailed(reader.error?.localizedDescription)
        }

        var windows: [AudioLevelWindow] = []
        while reader.status == .reading, let sampleBuffer = output.copyNextSampleBuffer() {
            if let window = try Self.audioLevelWindow(for: sampleBuffer) {
                windows.append(window)
            }
        }

        switch reader.status {
        case .completed:
            let duration = asset.duration.seconds
            return Self.silentRanges(
                from: windows,
                assetDuration: duration.isFinite ? duration : nil,
                configuration: configuration
            )
        case .failed:
            throw VideoSilenceDetectionError.readerFailed(reader.error?.localizedDescription)
        case .cancelled:
            throw VideoSilenceDetectionError.cancelled
        default:
            throw VideoSilenceDetectionError.readerFailed(reader.error?.localizedDescription)
        }
    }

    nonisolated static func silentRanges(
        from windows: [AudioLevelWindow],
        assetDuration: Double? = nil,
        configuration: VideoSilenceDetectionConfiguration = VideoSilenceDetectionConfiguration()
    ) -> [VideoTimeRange] {
        let threshold = configuration.silenceThresholdAmplitude
        let rawRanges = rawSilentRanges(from: windows, silenceThresholdAmplitude: threshold)
        let mergedRanges = merge(rawRanges, maximumGapDuration: configuration.maximumNoiseGapDuration)
        let upperBound = assetDuration.flatMap { $0.isFinite ? max($0, 0) : nil }

        return mergedRanges.compactMap { range in
            guard range.duration >= configuration.minimumSilenceDuration else {
                return nil
            }

            let paddedStart = range.start + configuration.edgePaddingDuration
            let paddedEnd = range.end - configuration.edgePaddingDuration
            let clampedStart = min(max(paddedStart, 0), upperBound ?? paddedStart)
            let clampedEnd = min(max(paddedEnd, clampedStart), upperBound ?? paddedEnd)

            guard clampedEnd > clampedStart else {
                return nil
            }

            return VideoTimeRange(start: clampedStart, end: clampedEnd, source: .detectedSilence)
        }
    }

    private nonisolated static var readerAudioSettings: [String: Any] {
        [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVLinearPCMIsFloatKey: true,
            AVLinearPCMBitDepthKey: 32,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsNonInterleaved: false
        ]
    }

    private nonisolated static func audioLevelWindow(for sampleBuffer: CMSampleBuffer) throws -> AudioLevelWindow? {
        guard let formatDescription = CMSampleBufferGetFormatDescription(sampleBuffer),
              let streamDescription = CMAudioFormatDescriptionGetStreamBasicDescription(formatDescription)?.pointee else {
            throw VideoSilenceDetectionError.unreadableAudioSamples
        }

        let sampleCount = CMSampleBufferGetNumSamples(sampleBuffer)
        guard sampleCount > 0 else {
            return nil
        }

        var bufferListSize = 0
        var blockBuffer: CMBlockBuffer?
        var status = CMSampleBufferGetAudioBufferListWithRetainedBlockBuffer(
            sampleBuffer,
            bufferListSizeNeededOut: &bufferListSize,
            bufferListOut: nil,
            bufferListSize: 0,
            blockBufferAllocator: kCFAllocatorDefault,
            blockBufferMemoryAllocator: kCFAllocatorDefault,
            flags: kCMSampleBufferFlag_AudioBufferList_Assure16ByteAlignment,
            blockBufferOut: &blockBuffer
        )

        guard status == noErr, bufferListSize > 0 else {
            throw VideoSilenceDetectionError.unreadableAudioSamples
        }

        let rawBufferList = UnsafeMutableRawPointer.allocate(
            byteCount: bufferListSize,
            alignment: MemoryLayout<AudioBufferList>.alignment
        )
        defer {
            rawBufferList.deallocate()
        }

        let bufferList = rawBufferList.bindMemory(to: AudioBufferList.self, capacity: 1)
        status = CMSampleBufferGetAudioBufferListWithRetainedBlockBuffer(
            sampleBuffer,
            bufferListSizeNeededOut: nil,
            bufferListOut: bufferList,
            bufferListSize: bufferListSize,
            blockBufferAllocator: kCFAllocatorDefault,
            blockBufferMemoryAllocator: kCFAllocatorDefault,
            flags: kCMSampleBufferFlag_AudioBufferList_Assure16ByteAlignment,
            blockBufferOut: &blockBuffer
        )

        guard status == noErr else {
            throw VideoSilenceDetectionError.unreadableAudioSamples
        }

        var sumSquares: Double = 0
        var valueCount = 0
        for audioBuffer in UnsafeMutableAudioBufferListPointer(bufferList) {
            guard let data = audioBuffer.mData else {
                continue
            }

            let sampleValueCount = Int(audioBuffer.mDataByteSize) / MemoryLayout<Float>.size
            let samples = data.bindMemory(to: Float.self, capacity: sampleValueCount)

            for index in 0..<sampleValueCount {
                let sample = min(max(Double(samples[index]), -1), 1)
                sumSquares += sample * sample
                valueCount += 1
            }
        }

        guard valueCount > 0 else {
            return nil
        }

        let start = CMSampleBufferGetPresentationTimeStamp(sampleBuffer).seconds
        guard start.isFinite else {
            return nil
        }

        let sampleDuration = CMSampleBufferGetDuration(sampleBuffer).seconds
        let fallbackDuration = streamDescription.mSampleRate > 0
            ? Double(sampleCount) / streamDescription.mSampleRate
            : 0
        let duration = sampleDuration.isFinite && sampleDuration > 0 ? sampleDuration : fallbackDuration

        guard duration > 0 else {
            return nil
        }

        return AudioLevelWindow(
            start: start,
            end: start + duration,
            rmsAmplitude: sqrt(sumSquares / Double(valueCount))
        )
    }

    private nonisolated static func rawSilentRanges(
        from windows: [AudioLevelWindow],
        silenceThresholdAmplitude: Double
    ) -> [VideoTimeRange] {
        var ranges: [VideoTimeRange] = []
        var activeStart: Double?
        var activeEnd: Double?

        for window in windows.sorted(by: { $0.start < $1.start }) where window.end > window.start {
            if window.rmsAmplitude <= silenceThresholdAmplitude {
                activeStart = activeStart ?? window.start
                activeEnd = window.end
            } else if let start = activeStart, let end = activeEnd {
                ranges.append(VideoTimeRange(start: start, end: end))
                activeStart = nil
                activeEnd = nil
            }
        }

        if let start = activeStart, let end = activeEnd {
            ranges.append(VideoTimeRange(start: start, end: end))
        }

        return ranges
    }

    private nonisolated static func merge(
        _ ranges: [VideoTimeRange],
        maximumGapDuration: Double
    ) -> [VideoTimeRange] {
        guard var current = ranges.first?.normalized else {
            return []
        }

        var merged: [VideoTimeRange] = []
        for range in ranges.dropFirst().map(\.normalized) {
            if range.start - current.end <= maximumGapDuration {
                current.end = max(current.end, range.end)
            } else {
                merged.append(current)
                current = range
            }
        }
        merged.append(current)

        return merged
    }
}

enum VideoSilenceDetectionError: LocalizedError, Equatable {
    case noAudioTrack
    case readerUnavailable
    case unreadableAudioSamples
    case cancelled
    case readerFailed(String?)

    var errorDescription: String? {
        switch self {
        case .noAudioTrack:
            return "This video does not have an audio track to scan."
        case .readerUnavailable:
            return "Could not prepare the audio track for silence detection."
        case .unreadableAudioSamples:
            return "Could not read audio samples from this video."
        case .cancelled:
            return "Silence detection was canceled."
        case .readerFailed(let details):
            if let details, !details.isEmpty {
                return "Silence detection failed. \(details)"
            }

            return "Silence detection failed."
        }
    }
}
