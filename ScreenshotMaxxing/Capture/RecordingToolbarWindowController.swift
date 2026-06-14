//
//  RecordingToolbarWindowController.swift
//  ScreenshotMaxxing
//
//  Created by Codex on 5/29/26.
//

import AppKit
import Combine
import SwiftUI

@MainActor
final class RecordingToolbarWindowController: NSWindowController {
    static let windowSize = NSSize(width: 214, height: 44)

    init(stopAction: @escaping () -> Void, restartAction: @escaping () -> Void) {
        let panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: Self.windowSize),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.isReleasedWhenClosed = false
        panel.sharingType = .none

        super.init(window: panel)

        panel.contentViewController = NSHostingController(
            rootView: RecordingToolbarView(
                startDate: Date(),
                stopAction: stopAction,
                restartAction: restartAction
            )
        )
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func show(on screen: NSScreen? = NSScreen.main) {
        guard let window else {
            return
        }

        if let screen {
            let visibleFrame = screen.visibleFrame
            window.setFrameOrigin(
                NSPoint(
                    x: visibleFrame.midX - Self.windowSize.width / 2,
                    y: visibleFrame.maxY - Self.windowSize.height - 20
                ))
        } else {
            window.center()
        }

        showWindow(nil)
        window.orderFrontRegardless()
    }
}

private struct RecordingToolbarView: View {
    let startDate: Date
    let stopAction: () -> Void
    let restartAction: () -> Void

    @State private var now = Date()

    var body: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(Color.red)
                .frame(width: 10, height: 10)

            Text(elapsedText)
                .font(.system(.body, design: .monospaced))
                .monospacedDigit()
                .frame(width: 46, alignment: .leading)

            Button(action: restartAction) {
                Image(systemName: "arrow.counterclockwise")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.primary)
                    .frame(width: 28, height: 28)
                    .background(
                        Color.primary.opacity(0.08),
                        in: RoundedRectangle(cornerRadius: 7, style: .continuous)
                    )
            }
            .buttonStyle(.plain)
            .help("Restart recording")
            .accessibilityLabel("Restart recording")
            .accessibilityIdentifier("recording-toolbar-restart")

            Button(action: stopAction) {
                ZStack {
                    Circle()
                        .fill(Color.red)
                        .frame(width: 28, height: 28)

                    Image(systemName: "stop.fill")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.white)
                }
                .frame(width: 28, height: 28)
            }
            .buttonStyle(.plain)
            .help("Stop recording")
            .accessibilityLabel("Stop recording")
            .accessibilityIdentifier("recording-toolbar-stop")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(.quaternary, lineWidth: 1)
        }
        .onReceive(Timer.publish(every: 1, on: .main, in: .common).autoconnect()) { date in
            now = date
        }
    }

    private var elapsedText: String {
        let elapsed = max(Int(now.timeIntervalSince(startDate)), 0)
        return String(format: "%02d:%02d", elapsed / 60, elapsed % 60)
    }
}
