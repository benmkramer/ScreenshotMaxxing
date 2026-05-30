//
//  VideoEditorView.swift
//  ScreenshotMaxxing
//
//  Created by Codex on 5/29/26.
//

import AVFoundation
import AVKit
import SwiftUI

struct VideoEditorView: View {
    let videoURL: URL
    private let capture: Capture?
    private let closeAction: () -> Void

    @State private var player: AVPlayer
    @State private var editState: VideoEditState
    @State private var currentTime: Double = 0
    @State private var isPlaying = false
    @State private var isExporting = false
    @State private var statusMessage: String?
    @State private var playbackObserver: Any?
    @State private var pendingPlaybackSkipTarget: Double?
    @State private var undoHistory = VideoEditUndoHistory()

    private static let playbackSkipOffset: Double = 0.04
    private static let successfulActionCloseDelay: TimeInterval = 0.6

    init(videoURL: URL, capture: Capture? = nil, closeAction: @escaping () -> Void = {}) {
        self.videoURL = videoURL
        self.capture = capture
        self.closeAction = closeAction
        let durationSeconds = (try? VideoMetadataReader.metadata(for: videoURL).durationSeconds)
            ?? capture?.durationSeconds
            ?? 0
        self._player = State(initialValue: AVPlayer(url: videoURL))
        self._editState = State(initialValue: VideoEditState(durationSeconds: durationSeconds))
    }

    var body: some View {
        VStack(spacing: 0) {
            VideoEditorToolbar(
                isPlaying: isPlaying,
                isExporting: isExporting,
                currentTime: currentTime,
                duration: editState.durationSeconds,
                hasSelectedCut: editState.selectedRemovedRangeID != nil,
                statusMessage: statusMessage,
                playPauseAction: togglePlayback,
                removeCutAction: removeSelectedCut,
                copyAction: copyEditedVideo,
                saveAction: saveEditedVideo,
                copyAndDeleteAction: copyEditedVideoAndDeleteCapture
            )

            Divider()

            VideoPlayerSurface(player: player)
                .background(Color.black)
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            Divider()

            VideoTimelineView(
                editState: $editState,
                currentTime: currentTime,
                seekAction: seekToTime,
                recordUndoAction: recordUndoSnapshot
            )
            .frame(height: 92)
            .padding(.horizontal, 18)
            .padding(.vertical, 14)
        }
        .frame(minWidth: 720, minHeight: 500)
        .background(Color(nsColor: .windowBackgroundColor))
        .overlay(alignment: .topLeading) {
            undoCommandButton
        }
        .onDeleteCommand {
            removeSelectedCut()
        }
        .onAppear {
            addPlaybackObserverIfNeeded()
            seek(to: editState.trimStart)
        }
        .onDisappear {
            removePlaybackObserver()
            player.pause()
        }
    }

    private var undoCommandButton: some View {
        Button("Undo Video Edit", action: undoLastVideoEdit)
            .keyboardShortcut("z", modifiers: .command)
            .disabled(!undoHistory.canUndo)
            .frame(width: 0, height: 0)
            .opacity(0)
            .accessibilityHidden(true)
    }

    private func togglePlayback() {
        if isPlaying {
            player.pause()
            isPlaying = false
        } else {
            if currentTime < editState.trimStart || currentTime >= editState.trimEnd {
                seek(to: editState.trimStart)
            } else if let skipTarget = editState.playbackSkipTarget(
                for: currentTime,
                offset: Self.playbackSkipOffset
            ) {
                seek(to: skipTarget)
            }
            player.play()
            isPlaying = true
        }
    }

    private func removeSelectedCut() {
        guard editState.selectedRemovedRangeID != nil else {
            return
        }

        recordUndoSnapshot()
        editState.removeSelectedRange()
    }

    private func recordUndoSnapshot() {
        undoHistory.record(editState)
    }

    private func undoLastVideoEdit() {
        guard let previousState = undoHistory.undo() else {
            return
        }

        editState = previousState
        seek(to: currentTime)
    }

    private func copyEditedVideo() {
        guard !isExporting else {
            return
        }

        isExporting = true
        statusMessage = "Exporting..."
        player.pause()
        isPlaying = false

        Task {
            do {
                let exportResult = try await saveEditedVideoToDisk()
                let mp4Data = try Data(contentsOf: exportResult.fileURL)

                if EditorClipboard.copyMP4Data(mp4Data) {
                    statusMessage = "Saved and copied video to clipboard"
                    closeAfterShowingSuccess()
                } else {
                    statusMessage = "Saved, but copy failed"
                }
            } catch {
                statusMessage = error.localizedDescription
            }

            isExporting = false
        }
    }

    private func copyEditedVideoAndDeleteCapture() {
        guard !isExporting else {
            return
        }

        isExporting = true
        statusMessage = "Exporting..."
        player.pause()
        isPlaying = false

        Task {
            var temporaryFileURL: URL?
            defer {
                if let temporaryFileURL {
                    try? FileManager.default.removeItem(at: temporaryFileURL)
                }

                isExporting = false
            }

            do {
                let exportResult = try await exportEditedVideoToTemporaryFile()
                temporaryFileURL = exportResult.fileURL
                let mp4Data = try Data(contentsOf: exportResult.fileURL)

                guard EditorClipboard.copyMP4Data(mp4Data) else {
                    statusMessage = "Copy failed"
                    return
                }

                guard let capture else {
                    statusMessage = "Copied video to clipboard"
                    closeAfterShowingSuccess()
                    return
                }

                do {
                    try CaptureMetadataStore().deleteCaptureFromHistoryAndDisk(capture)
                    statusMessage = "Copied and deleted capture"
                    closeAfterShowingSuccess()
                } catch {
                    statusMessage = "Copied, but delete failed: \(error.localizedDescription)"
                }
            } catch {
                statusMessage = error.localizedDescription
            }
        }
    }

    private func saveEditedVideo() {
        guard !isExporting else {
            return
        }

        isExporting = true
        statusMessage = "Exporting..."
        player.pause()
        isPlaying = false

        Task {
            do {
                let exportResult = try await saveEditedVideoToDisk()

                if EditorClipboard.copyString(exportResult.fileURL.fileSystemPath) {
                    statusMessage = "Saved; path copied to clipboard"
                    closeAfterShowingSuccess()
                } else {
                    statusMessage = "Saved, but path copy failed"
                }
            } catch {
                statusMessage = error.localizedDescription
            }

            isExporting = false
        }
    }

    private func saveEditedVideoToDisk() async throws -> VideoExportResult {
        let directories = try FileLocations.ensureCaptureDirectories()
        let editedFileURL = FileLocations.uniqueEditedFileURL(
            originalFileName: capture?.fileName ?? videoURL.lastPathComponent,
            directories: directories,
            fileExtension: "mp4"
        )
        let exportResult = try await VideoExporter().export(
            videoURL: videoURL,
            editState: editState,
            outputURL: editedFileURL
        )
        let thumbnailURL = try VideoThumbnailGenerator().writeThumbnail(
            for: exportResult.fileURL,
            originalFileName: exportResult.fileURL.lastPathComponent
        )
        try CaptureMetadataStore().saveEditedVideoCapture(
            editedFileURL: exportResult.fileURL,
            thumbnailURL: thumbnailURL,
            sourceCapture: capture,
            durationSeconds: exportResult.durationSeconds,
            dimensions: exportResult.dimensions
        )

        return exportResult
    }

    private func exportEditedVideoToTemporaryFile() async throws -> VideoExportResult {
        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("ScreenshotMaxxing-\(UUID().uuidString).mp4")

        return try await VideoExporter().export(
            videoURL: videoURL,
            editState: editState,
            outputURL: outputURL
        )
    }

    private func addPlaybackObserverIfNeeded() {
        guard playbackObserver == nil else {
            return
        }

        playbackObserver = player.addPeriodicTimeObserver(
            forInterval: CMTime(seconds: 0.08, preferredTimescale: 600),
            queue: .main
        ) { time in
            guard pendingPlaybackSkipTarget == nil else {
                return
            }

            currentTime = time.seconds.isFinite ? time.seconds : 0
            skipRemovedRangeIfNeeded(at: currentTime)
        }
    }

    private func removePlaybackObserver() {
        if let playbackObserver {
            player.removeTimeObserver(playbackObserver)
            self.playbackObserver = nil
        }
    }

    private func skipRemovedRangeIfNeeded(at time: Double) {
        if let skipTarget = editState.playbackSkipTarget(for: time, offset: Self.playbackSkipOffset) {
            skipPlayback(to: skipTarget)
            return
        }

        if time >= editState.trimEnd {
            player.pause()
            isPlaying = false
            seek(to: editState.trimStart)
        }
    }

    private func seekToTime(_ seconds: Double) {
        seek(to: seconds)
    }

    private func seek(to seconds: Double) {
        pendingPlaybackSkipTarget = nil
        let clamped = min(max(seconds, editState.trimStart), editState.trimEnd)
        currentTime = clamped
        player.seek(
            to: CMTime(seconds: clamped, preferredTimescale: 600),
            toleranceBefore: .zero,
            toleranceAfter: .zero
        )
    }

    private func skipPlayback(to seconds: Double) {
        let clamped = min(max(seconds, editState.trimStart), editState.trimEnd)
        pendingPlaybackSkipTarget = clamped
        currentTime = clamped
        player.seek(
            to: CMTime(seconds: clamped, preferredTimescale: 600),
            toleranceBefore: .zero,
            toleranceAfter: .zero
        ) { _ in
            DispatchQueue.main.async {
                if pendingPlaybackSkipTarget == clamped {
                    pendingPlaybackSkipTarget = nil
                }

                if isPlaying {
                    player.play()
                }
            }
        }
    }

    private func closeAfterShowingSuccess() {
        let closeAction = closeAction

        DispatchQueue.main.asyncAfter(deadline: .now() + Self.successfulActionCloseDelay) {
            closeAction()
        }
    }
}

// Use AppKit playback directly to avoid SwiftUI VideoPlayer aborts while
// _AVKit_SwiftUI materializes the editor window on some macOS 26 builds.
private struct VideoPlayerSurface: NSViewRepresentable {
    let player: AVPlayer

    func makeNSView(context: Context) -> AVPlayerView {
        let playerView = AVPlayerView()
        playerView.player = player
        playerView.controlsStyle = .none
        playerView.videoGravity = .resizeAspect
        playerView.wantsLayer = true
        playerView.layer?.backgroundColor = NSColor.black.cgColor
        return playerView
    }

    func updateNSView(_ playerView: AVPlayerView, context: Context) {
        if playerView.player !== player {
            playerView.player = player
        }
    }

    static func dismantleNSView(_ playerView: AVPlayerView, coordinator: ()) {
        playerView.player = nil
    }
}

private struct VideoEditorToolbar: View {
    let isPlaying: Bool
    let isExporting: Bool
    let currentTime: Double
    let duration: Double
    let hasSelectedCut: Bool
    let statusMessage: String?
    let playPauseAction: () -> Void
    let removeCutAction: () -> Void
    let copyAction: () -> Void
    let saveAction: () -> Void
    let copyAndDeleteAction: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            ToolbarIconButton(
                systemImageName: isPlaying ? "pause.fill" : "play.fill",
                helpText: isPlaying ? "Pause" : "Play",
                action: playPauseAction
            )

            Text("\(timeText(currentTime)) / \(timeText(duration))")
                .font(.system(.body, design: .monospaced))
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .frame(width: 112, alignment: .leading)

            Divider()
                .frame(height: 22)

            ToolbarIconButton(
                systemImageName: "trash",
                helpText: hasSelectedCut ? "Remove selected cut" : "Select a cut to remove it",
                action: removeCutAction
            )
            .disabled(!hasSelectedCut)
            .keyboardShortcut(.delete, modifiers: [])

            Spacer()

            if let statusMessage {
                Text(statusMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 6) {
                ToolbarIconButton(
                    systemImageName: "doc.on.doc",
                    helpText: "Save edited video and copy it to the clipboard",
                    action: copyAction
                )
                .disabled(isExporting)

                ToolbarIconButton(
                    systemImageName: "square.and.arrow.down",
                    helpText: "Save edited video and copy the file path",
                    action: saveAction
                )
                .disabled(isExporting)
            }

            Divider()
                .frame(height: 22)

            ToolbarIconButton(
                systemImageName: "clipboard",
                helpText: "Copy video to clipboard and delete it from history and disk",
                action: copyAndDeleteAction
            )
            .disabled(isExporting)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color(nsColor: .windowBackgroundColor))
    }
}

private struct VideoTimelineView: View {
    @Binding var editState: VideoEditState
    let currentTime: Double
    let seekAction: (Double) -> Void
    let recordUndoAction: () -> Void

    @State private var draftCutStart: Double?
    @State private var draftCutEnd: Double?
    @State private var activeDrag: TimelineDrag?

    private static let coordinateSpaceName = "video-timeline"
    private static let cutEdgeHitWidth: CGFloat = 14
    private static let minimumCutDragDistance: CGFloat = 4
    private static let trimHandleHitWidth: CGFloat = 14

    var body: some View {
        GeometryReader { proxy in
            let metrics = VideoTimelineMetrics(size: proxy.size, duration: editState.durationSeconds)

            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color(nsColor: .controlBackgroundColor))
                    .frame(height: metrics.trackHeight)
                    .position(x: proxy.size.width / 2, y: metrics.trackMidY)

                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.accentColor.opacity(0.28))
                    .frame(
                        width: metrics.width(for: editState.trimEnd - editState.trimStart),
                        height: metrics.trackHeight
                    )
                    .offset(x: metrics.x(for: editState.trimStart), y: metrics.trackY)
                    .contentShape(Rectangle())

                if let draftCutRange = draftCutRange(metrics: metrics) {
                    TimelineCutRangeShape(
                        range: draftCutRange,
                        metrics: metrics,
                        isSelected: true,
                        isDraft: true
                    )
                    .offset(x: metrics.x(for: draftCutRange.start), y: metrics.trackY)
                }

                ForEach(editState.removedRanges) { range in
                    TimelineCutRangeView(
                        range: range,
                        isSelected: range.id == editState.selectedRemovedRangeID,
                        metrics: metrics
                    )
                }

                Rectangle()
                    .fill(Color.white)
                    .frame(width: 2, height: metrics.trackHeight + 14)
                    .shadow(radius: 1)
                    .offset(x: metrics.x(for: currentTime), y: metrics.trackY - 7)

                TimelineHandle()
                    .offset(x: metrics.x(for: editState.trimStart) - 4, y: metrics.trackY - 7)

                TimelineHandle()
                    .offset(x: metrics.x(for: editState.trimEnd) - 4, y: metrics.trackY - 7)
            }
            .coordinateSpace(name: Self.coordinateSpaceName)
            .contentShape(Rectangle())
            .gesture(timelineDrag(metrics: metrics))
            .overlay(alignment: .bottomLeading) {
                HStack {
                    Text(timeText(editState.trimStart))
                    Spacer()
                    Text(timeText(editState.trimEnd))
                }
                .font(.caption)
                .monospacedDigit()
                .foregroundStyle(.secondary)
            }
        }
    }

    private func timelineDrag(metrics: VideoTimelineMetrics) -> some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .named(Self.coordinateSpaceName))
            .onChanged { value in
                let drag: TimelineDrag
                if let activeDrag {
                    drag = activeDrag
                } else {
                    drag = dragTarget(for: value.startLocation, metrics: metrics)
                    if drag.recordsUndoSnapshot {
                        recordUndoAction()
                    }
                }

                activeDrag = drag
                update(drag, with: value, metrics: metrics)
            }
            .onEnded { value in
                let drag = activeDrag ?? dragTarget(for: value.startLocation, metrics: metrics)
                defer {
                    activeDrag = nil
                    draftCutStart = nil
                    draftCutEnd = nil
                }

                guard hasMeaningfulDrag(value) else {
                    handleClick(for: drag, at: value.startLocation, metrics: metrics)
                    return
                }

                if case .createCut(let startTime) = drag,
                   let range = normalizedCutRange(
                       start: startTime,
                       end: metrics.time(
                           for: value.location.x,
                           lowerBound: editState.trimStart,
                           upperBound: editState.trimEnd
                       )
                   ),
                   range.duration >= minimumCutDuration(metrics: metrics) {
                    recordUndoAction()
                    editState.addRemovedRange(range)
                    if currentTime >= range.start && currentTime < range.end {
                        seekAction(range.end)
                    }
                }
            }
    }

    private func dragTarget(for location: CGPoint, metrics: VideoTimelineMetrics) -> TimelineDrag {
        let time = metrics.time(for: location.x)

        if abs(location.x - metrics.x(for: editState.trimStart)) <= Self.trimHandleHitWidth {
            return .trimStart
        }

        if abs(location.x - metrics.x(for: editState.trimEnd)) <= Self.trimHandleHitWidth {
            return .trimEnd
        }

        for range in editState.removedRanges.reversed() {
            if abs(location.x - metrics.x(for: range.start)) <= Self.cutEdgeHitWidth {
                return .resizeCutStart(range.id)
            }

            if abs(location.x - metrics.x(for: range.end)) <= Self.cutEdgeHitWidth {
                return .resizeCutEnd(range.id)
            }
        }

        if let range = editState.removedRange(containing: time) {
            return .moveCut(
                id: range.id,
                originalStart: range.start,
                originalEnd: range.end,
                startTime: time
            )
        }

        if time >= editState.trimStart && time <= editState.trimEnd {
            return .createCut(startTime: time)
        }

        return .seek
    }

    private func update(_ drag: TimelineDrag, with value: DragGesture.Value, metrics: VideoTimelineMetrics) {
        let time = metrics.time(
            for: value.location.x,
            lowerBound: editState.trimStart,
            upperBound: editState.trimEnd
        )

        switch drag {
        case .trimStart:
            editState.setTrimStart(metrics.time(for: value.location.x))
            seekAction(editState.trimStart)
        case .trimEnd:
            editState.setTrimEnd(metrics.time(for: value.location.x))
            seekAction(editState.trimEnd)
        case .resizeCutStart(let id):
            editState.setRemovedRangeStart(id: id, time, minimumDuration: minimumCutDuration(metrics: metrics))
            if let selectedRange = editState.selectedRemovedRange {
                seekAction(selectedRange.start)
            }
        case .resizeCutEnd(let id):
            editState.setRemovedRangeEnd(id: id, time, minimumDuration: minimumCutDuration(metrics: metrics))
            if let selectedRange = editState.selectedRemovedRange {
                seekAction(selectedRange.end)
            }
        case .moveCut(let id, let originalStart, _, let startTime):
            editState.moveRemovedRange(id: id, start: originalStart + time - startTime)
            if let selectedRange = editState.selectedRemovedRange {
                seekAction(selectedRange.start)
            }
        case .createCut(let startTime):
            guard hasMeaningfulDrag(value) else {
                return
            }

            draftCutStart = startTime
            draftCutEnd = time
            editState.selectRemovedRange(id: nil)
        case .seek:
            break
        }
    }

    private func handleClick(for drag: TimelineDrag, at location: CGPoint, metrics: VideoTimelineMetrics) {
        switch drag {
        case .resizeCutStart(let id), .resizeCutEnd(let id), .moveCut(let id, _, _, _):
            editState.selectRemovedRange(id: id)
        default:
            let time = metrics.time(for: location.x)
            if let range = editState.removedRange(containing: time) {
                editState.selectRemovedRange(id: range.id)
            } else {
                seekAction(time)
                editState.selectRemovedRange(id: nil)
            }
        }
    }

    private func hasMeaningfulDrag(_ value: DragGesture.Value) -> Bool {
        abs(value.translation.width) >= Self.minimumCutDragDistance
    }

    private func draftCutRange(metrics: VideoTimelineMetrics) -> VideoTimeRange? {
        guard let draftCutStart, let draftCutEnd else {
            return nil
        }

        return normalizedCutRange(start: draftCutStart, end: draftCutEnd)
    }

    private func normalizedCutRange(start: Double, end: Double) -> VideoTimeRange? {
        let clampedStart = min(max(start, editState.trimStart), editState.trimEnd)
        let clampedEnd = min(max(end, editState.trimStart), editState.trimEnd)
        let range = VideoTimeRange(start: min(clampedStart, clampedEnd), end: max(clampedStart, clampedEnd))

        return range.duration > 0 ? range : nil
    }

    private func minimumCutDuration(metrics: VideoTimelineMetrics) -> Double {
        let trimDuration = max(editState.trimEnd - editState.trimStart, 0)
        guard trimDuration > 0 else {
            return 0
        }

        return min(max(0.05, metrics.duration(forWidth: 4)), trimDuration)
    }

    private enum TimelineDrag {
        case trimStart
        case trimEnd
        case resizeCutStart(UUID)
        case resizeCutEnd(UUID)
        case moveCut(id: UUID, originalStart: Double, originalEnd: Double, startTime: Double)
        case createCut(startTime: Double)
        case seek

        var recordsUndoSnapshot: Bool {
            switch self {
            case .trimStart, .trimEnd, .resizeCutStart, .resizeCutEnd, .moveCut:
                true
            case .createCut, .seek:
                false
            }
        }
    }
}

private struct TimelineCutRangeView: View {
    let range: VideoTimeRange
    let isSelected: Bool
    let metrics: VideoTimelineMetrics

    private static let handleWidth: CGFloat = 16

    var body: some View {
        let rangeWidth = max(metrics.width(for: range.duration), Self.handleWidth * 2)

        ZStack(alignment: .topLeading) {
            TimelineCutRangeShape(
                range: range,
                metrics: metrics,
                isSelected: isSelected,
                isDraft: false
            )
            .offset(y: 5)

            TimelineCutResizeHandle(isSelected: isSelected)

            TimelineCutResizeHandle(isSelected: isSelected)
                .offset(x: rangeWidth - Self.handleWidth)
        }
        .frame(width: rangeWidth, height: metrics.trackHeight + 10, alignment: .topLeading)
        .offset(x: metrics.x(for: range.start), y: metrics.trackY - 5)
        .contentShape(Rectangle())
        .help("Cut")
    }
}

private struct TimelineCutRangeShape: View {
    let range: VideoTimeRange
    let metrics: VideoTimelineMetrics
    let isSelected: Bool
    let isDraft: Bool

    var body: some View {
        RoundedRectangle(cornerRadius: 3)
            .fill(fillColor)
            .overlay {
                if isSelected {
                    RoundedRectangle(cornerRadius: 3)
                        .strokeBorder(Color.accentColor, lineWidth: isDraft ? 1.5 : 2)
                }
            }
            .frame(width: max(metrics.width(for: range.duration), 4), height: metrics.trackHeight)
    }

    private var fillColor: Color {
        if isDraft {
            return Color.gray.opacity(0.45)
        }

        return isSelected ? Color.gray.opacity(0.68) : Color.gray.opacity(0.5)
    }
}

private struct TimelineCutResizeHandle: View {
    let isSelected: Bool

    var body: some View {
        Rectangle()
            .fill(Color.clear)
            .frame(width: 16, height: 38)
            .overlay {
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(isSelected ? Color.accentColor : Color(nsColor: .secondaryLabelColor))
                    .frame(width: 3, height: 32)
            }
            .contentShape(Rectangle())
    }
}

private struct VideoTimelineMetrics {
    let size: CGSize
    let duration: Double
    let trackHeight: CGFloat = 28

    var trackY: CGFloat {
        max((size.height - trackHeight) / 2 - 8, 0)
    }

    var trackMidY: CGFloat {
        trackY + trackHeight / 2
    }

    func x(for time: Double) -> CGFloat {
        guard duration > 0 else {
            return 0
        }

        return min(max(time / duration, 0), 1) * size.width
    }

    func width(for duration: Double) -> CGFloat {
        guard self.duration > 0 else {
            return 0
        }

        return max(duration / self.duration, 0) * size.width
    }

    func time(for x: CGFloat) -> Double {
        guard duration > 0 else {
            return 0
        }

        return min(max(x / size.width, 0), 1) * duration
    }

    func time(for x: CGFloat, lowerBound: Double, upperBound: Double) -> Double {
        let time = time(for: x)
        let lowerBound = min(max(lowerBound, 0), duration)
        let upperBound = min(max(upperBound, lowerBound), duration)

        return min(max(time, lowerBound), upperBound)
    }

    func duration(forWidth width: CGFloat) -> Double {
        guard duration > 0, size.width > 0 else {
            return 0
        }

        return Double(max(width, 0) / size.width) * duration
    }
}

private struct TimelineHandle: View {
    var body: some View {
        RoundedRectangle(cornerRadius: 2)
            .fill(Color(nsColor: .windowBackgroundColor))
            .overlay {
                RoundedRectangle(cornerRadius: 2)
                    .strokeBorder(Color.accentColor, lineWidth: 1.5)
            }
            .frame(width: 8, height: 42)
    }
}

private struct ToolbarIconButton: View {
    let systemImageName: String
    let helpText: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImageName)
                .frame(width: 18, height: 18)
        }
        .buttonStyle(.bordered)
        .accessibilityLabel(helpText)
        .help(helpText)
    }
}

private func timeText(_ seconds: Double) -> String {
    let totalSeconds = max(Int(seconds.rounded()), 0)
    let hours = totalSeconds / 3600
    let minutes = (totalSeconds % 3600) / 60
    let remainingSeconds = totalSeconds % 60

    if hours > 0 {
        return String(format: "%d:%02d:%02d", hours, minutes, remainingSeconds)
    }

    return String(format: "%d:%02d", minutes, remainingSeconds)
}

#Preview {
    VideoEditorView(videoURL: URL(fileURLWithPath: "/tmp/capture.mp4"))
}
