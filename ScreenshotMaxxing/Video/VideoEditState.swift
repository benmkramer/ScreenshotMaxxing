//
//  VideoEditState.swift
//  ScreenshotMaxxing
//
//  Created by Codex on 5/29/26.
//

import Foundation

struct VideoTimeRange: Identifiable, Equatable {
    let id: UUID
    var start: Double
    var end: Double

    init(id: UUID = UUID(), start: Double, end: Double) {
        self.id = id
        self.start = start
        self.end = end
    }

    var duration: Double {
        max(end - start, 0)
    }

    var normalized: VideoTimeRange {
        if start <= end {
            return self
        }

        return VideoTimeRange(id: id, start: end, end: start)
    }

    static func == (lhs: VideoTimeRange, rhs: VideoTimeRange) -> Bool {
        lhs.start == rhs.start && lhs.end == rhs.end
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

    mutating func addRemovedRange(_ range: VideoTimeRange) {
        removedRanges.append(range)
        normalize()
    }

    mutating func removeSelectedRange() {
        guard let selectedRemovedRangeID else {
            return
        }

        removedRanges.removeAll { $0.id == selectedRemovedRangeID }
        self.selectedRemovedRangeID = nil
    }

    func removedRange(containing time: Double) -> VideoTimeRange? {
        normalizedRemovedRanges().first { range in
            time >= range.start && time < range.end
        }
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

    private func normalizedRemovedRanges() -> [VideoTimeRange] {
        let clamped = removedRanges
            .map(\.normalized)
            .compactMap { range -> VideoTimeRange? in
                let start = min(max(range.start, trimStart), trimEnd)
                let end = min(max(range.end, trimStart), trimEnd)
                guard end > start else {
                    return nil
                }

                return VideoTimeRange(id: range.id, start: start, end: end)
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
            } else {
                merged.append(current)
                current = range
            }
        }
        merged.append(current)

        return merged
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
