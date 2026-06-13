//
//  CaptureOptionsView.swift
//  ScreenshotMaxxing
//
//  Created by Ben Kramer on 5/27/26.
//

import AppKit
import SwiftUI

enum CaptureOptionsPane: String, CaseIterable {
    case screenshot
    case record

    static let defaultPane: CaptureOptionsPane = .screenshot

    var displayName: String {
        switch self {
        case .screenshot:
            "Screenshot"
        case .record:
            "Record"
        }
    }
}

struct CaptureOptionsView: View {
    static let availableModes = CaptureMode.allCases
    static let availableRecordingModes = RecordingMode.allCases

    @State private var selectedPane: CaptureOptionsPane
    @State private var microphoneEnabled: Bool
    @State private var systemAudioEnabled: Bool

    let onSelectCapture: (CaptureMode) -> Void
    let onSelectRecording: (RecordingOptions) -> Void
    let onPaneChange: (CaptureOptionsPane) -> Void
    let onMicrophoneChange: (Bool) -> Void
    let onSystemAudioChange: (Bool) -> Void
    let onDismiss: () -> Void

    init(
        selectedPane: CaptureOptionsPane = .defaultPane,
        microphoneEnabled: Bool = false,
        systemAudioEnabled: Bool = false,
        onSelectCapture: @escaping (CaptureMode) -> Void,
        onSelectRecording: @escaping (RecordingOptions) -> Void,
        onPaneChange: @escaping (CaptureOptionsPane) -> Void = { _ in },
        onMicrophoneChange: @escaping (Bool) -> Void = { _ in },
        onSystemAudioChange: @escaping (Bool) -> Void = { _ in },
        onDismiss: @escaping () -> Void
    ) {
        self._selectedPane = State(initialValue: selectedPane)
        self._microphoneEnabled = State(initialValue: microphoneEnabled)
        self._systemAudioEnabled = State(initialValue: systemAudioEnabled)
        self.onSelectCapture = onSelectCapture
        self.onSelectRecording = onSelectRecording
        self.onPaneChange = onPaneChange
        self.onMicrophoneChange = onMicrophoneChange
        self.onSystemAudioChange = onSystemAudioChange
        self.onDismiss = onDismiss
    }

    var body: some View {
        VStack(spacing: 10) {
            Picker("Capture type", selection: paneSelection) {
                ForEach(CaptureOptionsPane.allCases, id: \.self) { pane in
                    Text(pane.displayName)
                        .tag(pane)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 240)
            .accessibilityIdentifier("capture-options-tabs")

            HStack(spacing: 8) {
                optionButtons

                Divider()
                    .frame(height: 52)
                    .padding(.horizontal, 4)

                Button(action: onDismiss) {
                    Image(systemName: "xmark")
                        .font(.system(size: 13, weight: .semibold))
                        .frame(width: 30, height: 30)
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.cancelAction)
                .help("Close")
                .accessibilityIdentifier("capture-options-close")
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(.quaternary, lineWidth: 1)
        }
        .fixedSize()
        .onExitCommand(perform: onDismiss)
    }

    private var paneSelection: Binding<CaptureOptionsPane> {
        Binding(
            get: { selectedPane },
            set: { pane in
                guard selectedPane != pane else {
                    return
                }

                selectedPane = pane
                onPaneChange(pane)
            }
        )
    }

    @ViewBuilder
    private var optionButtons: some View {
        switch selectedPane {
        case .screenshot:
            ForEach(Self.availableModes, id: \.self) { mode in
                CaptureOptionButton(
                    title: mode.captureOptionsDisplayName,
                    symbolName: mode.captureOptionsSymbolName,
                    showsRecordingBadge: false,
                    accessibilityIdentifier: mode.captureOptionsAccessibilityIdentifier
                ) {
                    onSelectCapture(mode)
                }
            }
        case .record:
            ForEach(Self.availableRecordingModes, id: \.self) { mode in
                CaptureOptionButton(
                    title: mode.captureOptionsDisplayName,
                    symbolName: mode.captureOptionsSymbolName,
                    showsRecordingBadge: true,
                    accessibilityIdentifier: mode.captureOptionsAccessibilityIdentifier
                ) {
                    onSelectRecording(RecordingOptions(
                        mode: mode,
                        microphoneEnabled: microphoneEnabled,
                        systemAudioEnabled: systemAudioEnabled
                    ))
                }
            }

            Divider()
                .frame(height: 52)
                .padding(.horizontal, 4)

            RecordingAudioToggle(
                isOn: Binding(
                    get: { microphoneEnabled },
                    set: { isEnabled in
                        microphoneEnabled = isEnabled
                        onMicrophoneChange(isEnabled)
                    }
                ),
                enabledSymbolName: "mic.fill",
                disabledSymbolName: "mic.slash",
                label: "Microphone",
                accessibilityIdentifier: "capture-options-record-microphone"
            )

            RecordingAudioToggle(
                isOn: Binding(
                    get: { systemAudioEnabled },
                    set: { isEnabled in
                        systemAudioEnabled = isEnabled
                        onSystemAudioChange(isEnabled)
                    }
                ),
                enabledSymbolName: "speaker.wave.2.fill",
                disabledSymbolName: "speaker.slash.fill",
                label: "System Audio",
                accessibilityIdentifier: "capture-options-record-system-audio"
            )
        }
    }
}

private struct RecordingAudioToggle: View {
    @Binding var isOn: Bool

    let enabledSymbolName: String
    let disabledSymbolName: String
    let label: String
    let accessibilityIdentifier: String

    var body: some View {
        Toggle(isOn: $isOn) {
            Image(systemName: isOn ? enabledSymbolName : disabledSymbolName)
                .font(.system(size: 18, weight: .medium))
                .frame(width: 24, height: 22)
        }
        .toggleStyle(.switch)
        .help(label)
        .accessibilityLabel(label)
        .accessibilityIdentifier(accessibilityIdentifier)
        .frame(width: 84)
    }
}

private struct CaptureOptionButton: View {
    let title: String
    let symbolName: String
    let showsRecordingBadge: Bool
    let accessibilityIdentifier: String
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button {
            action()
        } label: {
            VStack(spacing: 6) {
                CaptureOptionIcon(
                    symbolName: symbolName,
                    showsRecordingBadge: showsRecordingBadge
                )

                Text(title)
                    .font(.system(size: 12, weight: .medium))
                    .lineLimit(1)
            }
            .foregroundStyle(.primary)
            .frame(width: 92, height: 58)
            .background(
                (isHovered ? Color.primary.opacity(0.08) : Color.clear),
                in: RoundedRectangle(cornerRadius: 8, style: .continuous)
            )
            .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            isHovered = hovering
        }
        .help(title)
        .accessibilityIdentifier(accessibilityIdentifier)
    }
}

private struct CaptureOptionIcon: View {
    let symbolName: String
    let showsRecordingBadge: Bool

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            Image(systemName: symbolName)
                .font(.system(size: 20, weight: .medium))
                .frame(width: 26, height: 22)

            if showsRecordingBadge {
                Circle()
                    .fill(Color.red)
                    .frame(width: 8, height: 8)
                    .overlay {
                        Circle()
                            .stroke(Color(nsColor: .windowBackgroundColor), lineWidth: 1)
                    }
                    .offset(x: 1, y: 1)
            }
        }
        .frame(width: 30, height: 24)
    }
}

@MainActor
final class CaptureOptionsWindowController: NSWindowController, NSWindowDelegate {
    static let windowSize = NSSize(width: 598, height: 132)

    var onClose: ((CaptureOptionsWindowController) -> Void)?

    private let onSelectCapture: (CaptureMode) -> Void
    private let onSelectRecording: (RecordingOptions) -> Void
    private let onPaneChange: (CaptureOptionsPane) -> Void
    private let onMicrophoneChange: (Bool) -> Void
    private let onSystemAudioChange: (Bool) -> Void

    init(
        selectedPane: CaptureOptionsPane = .defaultPane,
        microphoneEnabled: Bool = false,
        systemAudioEnabled: Bool = false,
        onSelectCapture: @escaping (CaptureMode) -> Void,
        onSelectRecording: @escaping (RecordingOptions) -> Void,
        onPaneChange: @escaping (CaptureOptionsPane) -> Void = { _ in },
        onMicrophoneChange: @escaping (Bool) -> Void = { _ in },
        onSystemAudioChange: @escaping (Bool) -> Void = { _ in }
    ) {
        self.onSelectCapture = onSelectCapture
        self.onSelectRecording = onSelectRecording
        self.onPaneChange = onPaneChange
        self.onMicrophoneChange = onMicrophoneChange
        self.onSystemAudioChange = onSystemAudioChange

        let panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: Self.windowSize),
            styleMask: [.titled, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        panel.title = "Capture Options"
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.isMovableByWindowBackground = true
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.isReleasedWhenClosed = false
        panel.standardWindowButton(.closeButton)?.isHidden = true
        panel.standardWindowButton(.miniaturizeButton)?.isHidden = true
        panel.standardWindowButton(.zoomButton)?.isHidden = true

        super.init(window: panel)

        panel.delegate = self
        panel.contentViewController = NSHostingController(
            rootView: CaptureOptionsView(
                selectedPane: selectedPane,
                microphoneEnabled: microphoneEnabled,
                systemAudioEnabled: systemAudioEnabled,
                onSelectCapture: { [weak self] mode in
                    self?.selectCapture(mode)
                },
                onSelectRecording: { [weak self] options in
                    self?.selectRecording(options)
                },
                onPaneChange: { [weak self] pane in
                    self?.onPaneChange(pane)
                },
                onMicrophoneChange: { [weak self] isEnabled in
                    self?.onMicrophoneChange(isEnabled)
                },
                onSystemAudioChange: { [weak self] isEnabled in
                    self?.onSystemAudioChange(isEnabled)
                },
                onDismiss: { [weak self] in
                    self?.close()
                }
            )
        )
    }

    convenience init(onSelect: @escaping (CaptureMode) -> Void) {
        self.init(
            onSelectCapture: onSelect,
            onSelectRecording: { _ in },
            onMicrophoneChange: { _ in }
        )
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func show() {
        guard let window else {
            return
        }

        position(window)
        showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ notification: Notification) {
        onClose?(self)
    }

    private func selectCapture(_ mode: CaptureMode) {
        close()
        onSelectCapture(mode)
    }

    private func selectRecording(_ options: RecordingOptions) {
        close()
        onSelectRecording(options)
    }

    private func position(_ window: NSWindow) {
        guard let screen = NSScreen.main else {
            window.center()
            return
        }

        let visibleFrame = screen.visibleFrame
        let origin = NSPoint(
            x: visibleFrame.midX - Self.windowSize.width / 2,
            y: visibleFrame.minY + 72
        )
        window.setFrameOrigin(origin)
    }
}

private extension CaptureMode {
    var captureOptionsDisplayName: String {
        switch self {
        case .area:
            "Area"
        case .window:
            "Window"
        case .fullscreen:
            "Full Screen"
        }
    }

    var captureOptionsSymbolName: String {
        switch self {
        case .area:
            "rectangle.dashed"
        case .window:
            "macwindow"
        case .fullscreen:
            "display"
        }
    }

    var captureOptionsAccessibilityIdentifier: String {
        "capture-options-\(rawValue)"
    }
}

private extension RecordingMode {
    var captureOptionsDisplayName: String {
        switch self {
        case .area:
            "Area"
        case .window:
            "Window"
        case .fullscreen:
            "Full Screen"
        }
    }

    var captureOptionsSymbolName: String {
        switch self {
        case .area:
            "rectangle.dashed"
        case .window:
            "macwindow"
        case .fullscreen:
            "display"
        }
    }

    var captureOptionsAccessibilityIdentifier: String {
        "capture-options-record-\(rawValue)"
    }
}
