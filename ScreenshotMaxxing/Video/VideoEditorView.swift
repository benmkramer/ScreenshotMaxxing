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
                addCutAction: addCutAtCurrentTime,
                removeCutAction: removeSelectedCut,
                saveAction: saveEditedVideo
            )

            Divider()

            VideoPlayer(player: player)
                .background(Color.black)
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            Divider()

            VideoTimelineView(
                editState: $editState,
                currentTime: currentTime,
                seekAction: seekToTime
            )
            .frame(height: 92)
            .padding(.horizontal, 18)
            .padding(.vertical, 14)
        }
        .frame(minWidth: 720, minHeight: 500)
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear {
            addPlaybackObserverIfNeeded()
            seek(to: editState.trimStart)
        }
        .onDisappear {
            removePlaybackObserver()
            player.pause()
        }
    }

    private func togglePlayback() {
        if isPlaying {
            player.pause()
            isPlaying = false
        } else {
            if currentTime < editState.trimStart || currentTime >= editState.trimEnd {
                seek(to: editState.trimStart)
            }
            player.play()
            isPlaying = true
        }
    }

    private func addCutAtCurrentTime() {
        let cutLength = min(1.0, max(editState.trimEnd - editState.trimStart, 0))
        guard cutLength > 0 else {
            return
        }

        let start = min(max(currentTime, editState.trimStart), max(editState.trimEnd - cutLength, editState.trimStart))
        let range = VideoTimeRange(start: start, end: min(start + cutLength, editState.trimEnd))
        editState.addRemovedRange(range)
        editState.selectedRemovedRangeID = editState.removedRanges.first(where: { $0 == range })?.id
    }

    private func removeSelectedCut() {
        editState.removeSelectedRange()
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

    private func addPlaybackObserverIfNeeded() {
        guard playbackObserver == nil else {
            return
        }

        playbackObserver = player.addPeriodicTimeObserver(
            forInterval: CMTime(seconds: 0.08, preferredTimescale: 600),
            queue: .main
        ) { time in
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
        if let removedRange = editState.removedRange(containing: time) {
            seek(to: removedRange.end)
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
        let clamped = min(max(seconds, editState.trimStart), editState.trimEnd)
        currentTime = clamped
        player.seek(
            to: CMTime(seconds: clamped, preferredTimescale: 600),
            toleranceBefore: .zero,
            toleranceAfter: .zero
        )
    }

    private func closeAfterShowingSuccess() {
        let closeAction = closeAction

        DispatchQueue.main.asyncAfter(deadline: .now() + Self.successfulActionCloseDelay) {
            closeAction()
        }
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
    let addCutAction: () -> Void
    let removeCutAction: () -> Void
    let saveAction: () -> Void

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

            ToolbarIconButton(systemImageName: "scissors", helpText: "Add cut", action: addCutAction)

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

            ToolbarIconButton(
                systemImageName: "square.and.arrow.down",
                helpText: "Save edited video",
                action: saveAction
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

                ForEach(editState.removedRanges) { range in
                    RoundedRectangle(cornerRadius: 3)
                        .fill(range.id == editState.selectedRemovedRangeID ? Color.red : Color.red.opacity(0.58))
                        .frame(width: max(metrics.width(for: range.duration), 4), height: metrics.trackHeight)
                        .offset(x: metrics.x(for: range.start), y: metrics.trackY)
                        .onTapGesture {
                            editState.selectedRemovedRangeID = range.id
                        }
                        .help("Cut")
                }

                Rectangle()
                    .fill(Color.white)
                    .frame(width: 2, height: metrics.trackHeight + 14)
                    .shadow(radius: 1)
                    .offset(x: metrics.x(for: currentTime), y: metrics.trackY - 7)

                TimelineHandle()
                    .offset(x: metrics.x(for: editState.trimStart) - 4, y: metrics.trackY - 7)
                    .gesture(handleDrag(metrics: metrics) { value in
                        editState.setTrimStart(value)
                        seekAction(editState.trimStart)
                    })

                TimelineHandle()
                    .offset(x: metrics.x(for: editState.trimEnd) - 4, y: metrics.trackY - 7)
                    .gesture(handleDrag(metrics: metrics) { value in
                        editState.setTrimEnd(value)
                        seekAction(editState.trimEnd)
                    })
            }
            .contentShape(Rectangle())
            .simultaneousGesture(
                SpatialTapGesture(coordinateSpace: .local)
                    .onEnded { value in
                        let time = metrics.time(for: value.location.x)
                        if editState.removedRange(containing: time) == nil {
                            seekAction(time)
                            editState.selectedRemovedRangeID = nil
                        }
                    }
            )
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

    private func handleDrag(metrics: VideoTimelineMetrics, update: @escaping (Double) -> Void) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                update(metrics.time(for: value.location.x))
            }
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
