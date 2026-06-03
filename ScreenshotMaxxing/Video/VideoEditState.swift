//
//  VideoEditState.swift
//  ScreenshotMaxxing
//
//  Created by Codex on 5/29/26.
//

import Foundation

enum VideoRemovedRangeSource: Equatable, Sendable {
    case manual
    case detectedSilence

    nonisolated var showsSilenceIndicator: Bool {
        self == .detectedSilence
    }

    nonisolated var helpText: String {
        switch self {
        case .manual:
            "Cut"
        case .detectedSilence:
            "Silence-detected cut"
        }
    }

    nonisolated func merging(_ other: VideoRemovedRangeSource) -> VideoRemovedRangeSource {
        self == .detectedSilence || other == .detectedSilence ? .detectedSilence : .manual
    }
}

struct VideoTimeRange: Identifiable, Equatable, Sendable {
    let id: UUID
    var start: Double
    var end: Double
    var source: VideoRemovedRangeSource

    nonisolated init(
        id: UUID = UUID(),
        start: Double,
        end: Double,
        source: VideoRemovedRangeSource = .manual
    ) {
        self.id = id
        self.start = start
        self.end = end
        self.source = source
    }

    nonisolated var duration: Double {
        max(end - start, 0)
    }

    nonisolated var normalized: VideoTimeRange {
        if start <= end {
            return self
        }

        return VideoTimeRange(id: id, start: end, end: start, source: source)
    }

    static func == (lhs: VideoTimeRange, rhs: VideoTimeRange) -> Bool {
        lhs.start == rhs.start && lhs.end == rhs.end && lhs.source == rhs.source
    }
}

struct VideoEditState: Equatable {
    let durationSeconds: Double
    var trimStart: Double
    var trimEnd: Double
    var removedRanges: [VideoTimeRange]
    var selectedRemovedRangeID: UUID?

    init(
        durationSeconds: Double,
        trimStart: Double = 0,
        trimEnd: Double? = nil,
        removedRanges: [VideoTimeRange] = [],
        selectedRemovedRangeID: UUID? = nil
    ) {
        let durationSeconds = max(durationSeconds, 0)
        self.durationSeconds = durationSeconds
        self.trimStart = min(max(trimStart, 0), durationSeconds)
        self.trimEnd = min(max(trimEnd ?? durationSeconds, 0), durationSeconds)
        self.removedRanges = removedRanges
        self.selectedRemovedRangeID = selectedRemovedRangeID
        normalize()
    }

    var keptRanges: [VideoTimeRange] {
        guard trimEnd > trimStart else {
            return []
        }

        let cuts = normalizedRemovedRanges()
        var cursor = trimStart
        var keptRanges: [VideoTimeRange] = []

        for cut in cuts {
            if cut.start > cursor {
                keptRanges.append(VideoTimeRange(start: cursor, end: cut.start))
            }

            cursor = max(cursor, cut.end)
        }

        if cursor < trimEnd {
            keptRanges.append(VideoTimeRange(start: cursor, end: trimEnd))
        }

        return keptRanges.filter { $0.duration > 0 }
    }

    var selectedRemovedRange: VideoTimeRange? {
        guard let selectedRemovedRangeID else {
            return nil
        }

        return removedRanges.first { $0.id == selectedRemovedRangeID }
    }

    mutating func setTrimStart(_ value: Double) {
        trimStart = min(max(value, 0), trimEnd)
        normalize()
    }

    mutating func setTrimEnd(_ value: Double) {
        trimEnd = max(min(value, durationSeconds), trimStart)
        normalize()
    }

    @discardableResult
    mutating func addRemovedRange(_ range: VideoTimeRange) -> UUID? {
        let normalizedRange = range.normalized
        let midpoint = (normalizedRange.start + normalizedRange.end) / 2
        removedRanges.append(normalizedRange)
        selectedRemovedRangeID = normalizedRange.id
        normalize()
        restoreSelection(containing: midpoint)
        return selectedRemovedRangeID
    }

    mutating func removeSelectedRange() {
        guard let selectedRemovedRangeID else {
            return
        }

        removedRanges.removeAll { $0.id == selectedRemovedRangeID }
        self.selectedRemovedRangeID = nil
    }

    mutating func selectRemovedRange(id: UUID?) {
        guard let id else {
            selectedRemovedRangeID = nil
            return
        }

        selectedRemovedRangeID = removedRanges.contains { $0.id == id } ? id : nil
    }

    mutating func setRemovedRangeStart(id: UUID, _ value: Double, minimumDuration: Double = 0) {
        guard let index = removedRanges.firstIndex(where: { $0.id == id }) else {
            return
        }

        let end = removedRanges[index].end
        let minimumDuration = max(minimumDuration, 0)
        removedRanges[index].start = min(min(max(value, trimStart), trimEnd), end - minimumDuration)
        selectedRemovedRangeID = id
        normalize()
        restoreSelection(containing: removedRanges.first(where: { $0.id == id })?.start ?? value)
    }

    mutating func setRemovedRangeEnd(id: UUID, _ value: Double, minimumDuration: Double = 0) {
        guard let index = removedRanges.firstIndex(where: { $0.id == id }) else {
            return
        }

        let start = removedRanges[index].start
        let minimumDuration = max(minimumDuration, 0)
        removedRanges[index].end = max(min(max(value, trimStart), trimEnd), start + minimumDuration)
        selectedRemovedRangeID = id
        normalize()
        restoreSelection(containing: removedRanges.first(where: { $0.id == id })?.end ?? value)
    }

    mutating func moveRemovedRange(id: UUID, start: Double) {
        guard let index = removedRanges.firstIndex(where: { $0.id == id }) else {
            return
        }

        let duration = removedRanges[index].duration
        guard duration > 0 else {
            return
        }

        let lowerBound = trimStart
        let upperBound = max(trimStart, trimEnd - duration)
        let clampedStart = min(max(start, lowerBound), upperBound)
        removedRanges[index].start = clampedStart
        removedRanges[index].end = min(clampedStart + duration, trimEnd)
        selectedRemovedRangeID = id
        normalize()
        restoreSelection(containing: clampedStart + duration / 2)
    }

    func removedRange(containing time: Double) -> VideoTimeRange? {
        normalizedRemovedRanges().first { range in
            time >= range.start && time < range.end
        }
    }

    func playbackSkipTarget(for time: Double, offset: Double = 0) -> Double? {
        guard trimEnd > trimStart,
              removedRange(containing: time) != nil else {
            return nil
        }

        let offset = max(offset, 0)
        var target = min(max(time, trimStart), trimEnd)
        var didSkip = false

        while let removedRange = removedRange(containing: target), target < trimEnd {
            let nextTarget = min(removedRange.end + offset, trimEnd)
            guard nextTarget > target else {
                break
            }

            target = nextTarget
            didSkip = true
        }

        return didSkip ? target : nil
    }

    private mutating func normalize() {
        if trimEnd < trimStart {
            swap(&trimStart, &trimEnd)
        }

        trimStart = min(max(trimStart, 0), durationSeconds)
        trimEnd = min(max(trimEnd, 0), durationSeconds)
        removedRanges = normalizedRemovedRanges()

        if let selectedRemovedRangeID,
           !removedRanges.contains(where: { $0.id == selectedRemovedRangeID }) {
            self.selectedRemovedRangeID = nil
        }
    }

    private mutating func restoreSelection(containing time: Double) {
        guard selectedRemovedRangeID == nil else {
            return
        }

        selectedRemovedRangeID = removedRanges.first { range in
            time >= range.start && time <= range.end
        }?.id
    }

    private func normalizedRemovedRanges() -> [VideoTimeRange] {
        let clamped = removedRanges
            .map(\.normalized)
            .compactMap { range -> VideoTimeRange? in
                let start = min(max(range.start, trimStart), trimEnd)
                let end = min(max(range.end, trimStart), trimEnd)
                guard end > start else {
                    return nil
                }

                return VideoTimeRange(id: range.id, start: start, end: end, source: range.source)
            }
            .sorted { first, second in
                first.start == second.start ? first.end < second.end : first.start < second.start
            }

        guard var current = clamped.first else {
            return []
        }

        var merged: [VideoTimeRange] = []
        for range in clamped.dropFirst() {
            if range.start <= current.end {
                current.end = max(current.end, range.end)
                current.source = current.source.merging(range.source)
            } else {
                merged.append(current)
                current = range
            }
        }
        merged.append(current)

        return merged
    }
}

struct VideoEditUndoHistory: Equatable {
    private(set) var snapshots: [VideoEditState] = []

    var canUndo: Bool {
        !snapshots.isEmpty
    }

    mutating func record(_ state: VideoEditState) {
        guard snapshots.last != state else {
            return
        }

        snapshots.append(state)
    }

    mutating func undo() -> VideoEditState? {
        snapshots.popLast()
    }
}

struct VideoCompositionPlan: Equatable {
    let keptRanges: [VideoTimeRange]

    var outputDurationSeconds: Double {
        keptRanges.reduce(0) { $0 + $1.duration }
    }
}

enum VideoExportPlanner {
    static func plan(for state: VideoEditState) -> VideoCompositionPlan {
        VideoCompositionPlan(keptRanges: state.keptRanges)
    }
}
