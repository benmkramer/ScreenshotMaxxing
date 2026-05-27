//
//  PreferencesView.swift
//  ScreenshotMaxxing
//
//  Created by Ben Kramer on 5/26/26.
//

import SwiftUI

struct PreferencesView: View {
    @State private var preferences: PreferencesData
    private let onShortcutChange: (GlobalKeyboardShortcut) -> Bool

    init(
        preferences: PreferencesData,
        onShortcutChange: @escaping (GlobalKeyboardShortcut) -> Bool = { _ in true }
    ) {
        _preferences = State(initialValue: preferences)
        self.onShortcutChange = onShortcutChange
    }

    var body: some View {
        Form {
            Section("Capture") {
                LabeledContent("Area capture shortcut") {
                    ShortcutRecorderView(shortcut: preferences.areaCaptureShortcut) { shortcut in
                        guard onShortcutChange(shortcut) else {
                            return false
                        }

                        preferences = preferences.updatingAreaCaptureShortcut(shortcut)
                        return true
                    }
                    .frame(width: 160)
                }
            }

            Section("Storage") {
                LabeledContent("Original screenshots") {
                    pathText(preferences.originalsFolderPath)
                }

                LabeledContent("Edited screenshots") {
                    pathText(preferences.editedFolderPath)
                }
            }
        }
        .formStyle(.grouped)
        .padding(20)
        .frame(minWidth: 540, minHeight: 300)
    }

    private func pathText(_ path: String) -> some View {
        Text(path)
            .font(.system(.body, design: .monospaced))
            .lineLimit(2)
            .textSelection(.enabled)
            .foregroundStyle(.secondary)
    }
}

#Preview {
    PreferencesView(
        preferences: PreferencesData(
            areaCaptureShortcut: .defaultAreaCapture,
            originalsFolderPath: "/Users/example/Library/Application Support/ScreenshotMaxxing/Captures/originals",
            editedFolderPath: "/Users/example/Library/Application Support/ScreenshotMaxxing/Captures/edited"
        )
    )
}
