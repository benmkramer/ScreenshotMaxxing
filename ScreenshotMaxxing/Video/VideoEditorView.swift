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
    private let hasAudioTracks: Bool
    private let savedFilePresenter: SavedFilePresenter
    private let closeAction: () -> Void

    @State private var player: AVPlayer
    @State private var editState: VideoEditState
    @State private var currentTime: Double = 0
    @State private var isPlaying = false
    @State private var isExporting = false
    @State private var isDetectingSilence = false
    @State private var statusMessage: String?
    @State private var playbackObserver: Any?
    @State private var pendingPlaybackSkipTarget: Double?
    @State private var undoHistory = VideoEditUndoHistory()

    private static let playbackSkipOffset: Double = 0.04
    private static let successfulActionCloseDelay: TimeInterval = 0.6

    init(
        videoURL: URL,
        capture: Capture? = nil,
        savedFilePresenter: SavedFilePresenter = SavedFilePresenter(),
        closeAction: @escaping () -> Void = {}
    ) {
        self.videoURL = videoURL
        self.capture = capture
        self.savedFilePresenter = savedFilePresenter
        self.closeAction = closeAction
        let asset = AVURLAsset(url: videoURL)
        self.hasAudioTracks = !asset.tracks(withMediaType: .audio).isEmpty
        let durationSeconds =
            (try? VideoMetadataReader.metadata(for: videoURL).durationSeconds)
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
                isDetectingSilence: isDetectingSilence,
                currentTime: currentTime,
                duration: editState.durationSeconds,
                hasSelectedCut: editState.selectedRemovedRangeID != nil,
                canDetectSilence: hasAudioTracks,
                statusMessage: statusMessage,
                playPauseAction: togglePlayback,
                removeCutAction: removeSelectedCut,
                detectSilenceAction: detectSilentBlocks,
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

    private func detectSilentBlocks() {
        guard !isExporting, !isDetectingSilence else {
            return
        }

        guard hasAudioTracks else {
            statusMessage = "No audio track to scan"
            return
        }

        isDetectingSilence = true
        statusMessage = "Detecting silence..."
        player.pause()
        isPlaying = false

        let videoURL = videoURL
        Task {
            defer {
                isDetectingSilence = false
            }

            do {
                let detectedRanges = try await Task.detached(priority: .userInitiated) {
                    try VideoSilenceDetector().silentRanges(in: videoURL)
                }.value
                let ranges = detectedRanges.compactMap(clampedToCurrentTrim)

                guard !ranges.isEmpty else {
                    statusMessage = "No 1s+ silence found"
                    return
                }

                recordUndoSnapshot()
                for range in ranges {
                    editState.addRemovedRange(range)
                }

                if let skipTarget = editState.playbackSkipTarget(
                    for: currentTime,
                    offset: Self.playbackSkipOffset
                ) {
                    seek(to: skipTarget)
                }

                statusMessage = silenceDetectionSummary(for: ranges.count)
            } catch {
                statusMessage = error.localizedDescription
            }
        }
    }

    private func clampedToCurrentTrim(_ range: VideoTimeRange) -> VideoTimeRange? {
        let start = min(max(range.start, editState.trimStart), editState.trimEnd)
        let end = min(max(range.end, editState.trimStart), editState.trimEnd)

        guard end > start else {
            return nil
        }

        return VideoTimeRange(start: start, end: end, source: range.source)
    }

    private func silenceDetectionSummary(for count: Int) -> String {
        count == 1 ? "Added 1 silence cut" : "Added \(count) silence cuts"
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
                    statusMessage = EditorCopyAndTrashStatus.copiedWithoutCaptureMessage(for: .video)
                    closeAfterShowingSuccess()
                    return
                }

                do {
                    try CaptureMetadataStore().deleteCaptureFromHistoryAndDisk(capture)
                    statusMessage = EditorCopyAndTrashStatus.copiedAndMovedToTrashMessage(for: .video)
                    closeAfterShowingSuccess()
                } catch {
                    statusMessage = EditorCopyAndTrashStatus.copiedButMoveToTrashFailedMessage(
                        for: .video,
                        errorDescription: error.localizedDescription
                    )
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
                savedFilePresenter.revealInFinder(exportResult.fileURL)

                if EditorClipboard.copyString(exportResult.fileURL.fileSystemPath) {
                    statusMessage = "Saved; opened in Finder and path copied"
                    closeAfterShowingSuccess()
                } else {
                    statusMessage = "Saved and opened in Finder, but path copy failed"
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
    let isDetectingSilence: Bool
    let currentTime: Double
    let duration: Double
    let hasSelectedCut: Bool
    let canDetectSilence: Bool
    let statusMessage: String?
    let playPauseAction: () -> Void
    let removeCutAction: () -> Void
    let detectSilenceAction: () -> Void
    let copyAction: () -> Void
    let saveAction: () -> Void
    let copyAndDeleteAction: () -> Void

    var body: some View {
        let isBusy = isExporting || isDetectingSilence

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

            ToolbarIconButton(
                systemImageName: "waveform",
                helpText: silenceDetectionHelpText,
                action: detectSilenceAction
            )
            .disabled(!canDetectSilence || isBusy)

            Spacer()

            if let statusMessage {
                Text(statusMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 6) {
                ToolbarIconButton(
                    descriptor: .copyEdited(.video),
                    action: copyAction
                )
                .disabled(isBusy)

                ToolbarIconButton(
                    descriptor: .saveEdited(.video),
                    action: saveAction
                )
                .disabled(isBusy)
            }

            Divider()
                .frame(height: 22)

            ToolbarIconButton(
                descriptor: .copyAndMoveToTrash(.video),
                action: copyAndDeleteAction
            )
            .disabled(isBusy)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var silenceDetectionHelpText: String {
        if isDetectingSilence {
            return "Detecting silence"
        }

        return canDetectSilence ? "Detect 1s+ silent blocks" : "No audio track to scan"
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
                    range.duration >= minimumCutDuration(metrics: metrics)
                {
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

            if range.source.showsSilenceIndicator {
                TimelineSilenceCutIndicator(isSelected: isSelected)
                    .frame(width: rangeWidth, height: metrics.trackHeight)
                    .offset(y: 5)
            }

            TimelineCutResizeHandle(isSelected: isSelected)

            TimelineCutResizeHandle(isSelected: isSelected)
                .offset(x: rangeWidth - Self.handleWidth)
        }
        .frame(width: rangeWidth, height: metrics.trackHeight + 10, alignment: .topLeading)
        .offset(x: metrics.x(for: range.start), y: metrics.trackY - 5)
        .contentShape(Rectangle())
        .help(range.source.helpText)
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

private struct TimelineSilenceCutIndicator: View {
    let isSelected: Bool

    var body: some View {
        Image(systemName: "waveform")
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(Color.white.opacity(isSelected ? 0.95 : 0.82))
            .padding(.horizontal, 3)
            .padding(.vertical, 1)
            .background {
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color.black.opacity(isSelected ? 0.3 : 0.2))
            }
            .accessibilityLabel("Silence-detected cut")
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
    let descriptor: EditorToolbarActionDescriptor
    let action: () -> Void

    init(
        systemImageName: String,
        helpText: String,
        action: @escaping () -> Void
    ) {
        self.descriptor = EditorToolbarActionDescriptor(
            systemImageName: systemImageName,
            visibleTitle: nil,
            accessibilityLabel: helpText,
            helpText: helpText,
            visualRole: .standard
        )
        self.action = action
    }

    init(
        descriptor: EditorToolbarActionDescriptor,
        action: @escaping () -> Void
    ) {
        self.descriptor = descriptor
        self.action = action
    }

    var body: some View {
        Button(role: buttonRole, action: action) {
            if let visibleTitle = descriptor.visibleTitle {
                Label(visibleTitle, systemImage: descriptor.systemImageName)
                    .labelStyle(.titleAndIcon)
                    .font(.caption)
            } else {
                Image(systemName: descriptor.systemImageName)
                    .frame(width: 18, height: 18)
            }
        }
        .buttonStyle(.bordered)
        .foregroundStyle(foregroundStyle)
        .accessibilityLabel(descriptor.accessibilityLabel)
        .help(descriptor.helpText)
    }

    private var buttonRole: ButtonRole? {
        descriptor.visualRole == .destructive ? .destructive : nil
    }

    private var foregroundStyle: Color {
        descriptor.visualRole == .destructive ? .red : .primary
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
