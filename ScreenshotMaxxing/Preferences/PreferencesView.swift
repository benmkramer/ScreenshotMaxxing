//
//  PreferencesView.swift
//  ScreenshotMaxxing
//
//  Created by Ben Kramer on 5/26/26.
//

import SwiftUI

struct PreferencesView: View {
    @State private var preferences: PreferencesData
    private let onAreaCaptureShortcutChange: (GlobalKeyboardShortcut) -> Bool
    private let onCaptureOptionsShortcutChange: (GlobalKeyboardShortcut) -> Bool
    private let onLaunchAtLoginChange: (Bool) -> Bool
    private let onMenuBarIconVisibleChange: (Bool) -> Bool

    init(
        preferences: PreferencesData,
        onAreaCaptureShortcutChange: @escaping (GlobalKeyboardShortcut) -> Bool = { _ in true },
        onCaptureOptionsShortcutChange: @escaping (GlobalKeyboardShortcut) -> Bool = { _ in true },
        onLaunchAtLoginChange: @escaping (Bool) -> Bool = { _ in true },
        onMenuBarIconVisibleChange: @escaping (Bool) -> Bool = { _ in true }
    ) {
        _preferences = State(initialValue: preferences)
        self.onAreaCaptureShortcutChange = onAreaCaptureShortcutChange
        self.onCaptureOptionsShortcutChange = onCaptureOptionsShortcutChange
        self.onLaunchAtLoginChange = onLaunchAtLoginChange
        self.onMenuBarIconVisibleChange = onMenuBarIconVisibleChange
    }

    var body: some View {
        Form {
            Section("Startup") {
                Toggle("Open at Login", isOn: Binding(
                    get: { preferences.launchAtLoginEnabled },
                    set: { isEnabled in
                        guard onLaunchAtLoginChange(isEnabled) else {
                            return
                        }

                        preferences = preferences.updatingLaunchAtLoginEnabled(isEnabled)
                    }
                ))

                Toggle("Show in Menu Bar", isOn: Binding(
                    get: { preferences.menuBarIconVisible },
                    set: { isVisible in
                        guard onMenuBarIconVisibleChange(isVisible) else {
                            return
                        }

                        preferences = preferences.updatingMenuBarIconVisible(isVisible)
                    }
                ))
            }

            Section("Capture") {
                LabeledContent("Area capture shortcut") {
                    ShortcutRecorderView(shortcut: preferences.areaCaptureShortcut) { shortcut in
                        guard onAreaCaptureShortcutChange(shortcut) else {
                            return false
                        }

                        preferences = preferences.updatingAreaCaptureShortcut(shortcut)
                        return true
                    }
                    .frame(width: 160)
                }

                LabeledContent("Capture options shortcut") {
                    ShortcutRecorderView(shortcut: preferences.captureOptionsShortcut) { shortcut in
                        guard onCaptureOptionsShortcutChange(shortcut) else {
                            return false
                        }

                        preferences = preferences.updatingCaptureOptionsShortcut(shortcut)
                        return true
                    }
                    .frame(width: 160)
                }

                Text("Command-Shift-3, Command-Shift-4, and Command-Shift-5 stay reserved for macOS screenshots unless changed in System Settings.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
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
        .frame(minWidth: 540, minHeight: 360)
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
            captureOptionsShortcut: .defaultCaptureOptions,
            launchAtLoginEnabled: false,
            menuBarIconVisible: true,
            originalsFolderPath: "/Users/example/Library/Application Support/ScreenshotMaxxing/Captures/originals",
            editedFolderPath: "/Users/example/Library/Application Support/ScreenshotMaxxing/Captures/edited"
        )
    )
}
