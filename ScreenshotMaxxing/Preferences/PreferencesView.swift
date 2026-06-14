//
//  PreferencesView.swift
//  ScreenshotMaxxing
//
//  Created by Ben Kramer on 5/26/26.
//

import AppKit
import SwiftUI

struct PreferencesView: View {
    @State private var preferences: PreferencesData
    private let onAreaCaptureShortcutChange: (GlobalKeyboardShortcut) -> Bool
    private let onCaptureOptionsShortcutChange: (GlobalKeyboardShortcut) -> Bool
    private let onOpenHistoryShortcutChange: (GlobalKeyboardShortcut) -> Bool
    private let onAreaCaptureShortcutReset: () -> GlobalKeyboardShortcut
    private let onCaptureOptionsShortcutReset: () -> GlobalKeyboardShortcut
    private let onOpenHistoryShortcutReset: () -> GlobalKeyboardShortcut
    private let onLaunchAtLoginChange: (Bool) -> Bool
    private let onOpenStorageFolder: (String) -> Void

    init(
        preferences: PreferencesData,
        onAreaCaptureShortcutChange: @escaping (GlobalKeyboardShortcut) -> Bool = { _ in true },
        onCaptureOptionsShortcutChange: @escaping (GlobalKeyboardShortcut) -> Bool = { _ in true },
        onOpenHistoryShortcutChange: @escaping (GlobalKeyboardShortcut) -> Bool = { _ in true },
        onAreaCaptureShortcutReset: @escaping () -> GlobalKeyboardShortcut = { .defaultAreaCapture },
        onCaptureOptionsShortcutReset: @escaping () -> GlobalKeyboardShortcut = { .defaultCaptureOptions },
        onOpenHistoryShortcutReset: @escaping () -> GlobalKeyboardShortcut = { .defaultOpenHistory },
        onLaunchAtLoginChange: @escaping (Bool) -> Bool = { _ in true },
        onOpenStorageFolder: @escaping (String) -> Void = { path in
            NSWorkspace.shared.open(URL(fileURLWithPath: path, isDirectory: true))
        }
    ) {
        _preferences = State(initialValue: preferences)
        self.onAreaCaptureShortcutChange = onAreaCaptureShortcutChange
        self.onCaptureOptionsShortcutChange = onCaptureOptionsShortcutChange
        self.onOpenHistoryShortcutChange = onOpenHistoryShortcutChange
        self.onAreaCaptureShortcutReset = onAreaCaptureShortcutReset
        self.onCaptureOptionsShortcutReset = onCaptureOptionsShortcutReset
        self.onOpenHistoryShortcutReset = onOpenHistoryShortcutReset
        self.onLaunchAtLoginChange = onLaunchAtLoginChange
        self.onOpenStorageFolder = onOpenStorageFolder
    }

    var body: some View {
        Form {
            Section {
                Toggle(
                    "Open at Login",
                    isOn: Binding(
                        get: { preferences.launchAtLoginEnabled },
                        set: { isEnabled in
                            guard onLaunchAtLoginChange(isEnabled) else {
                                return
                            }

                            preferences = preferences.updatingLaunchAtLoginEnabled(isEnabled)
                        }
                    ))
            } header: {
                Text("Startup")
                    .accessibilityIdentifier("preferences-startup-section")
            }

            Section {
                LabeledContent("Area capture shortcut") {
                    ShortcutRecorderView(shortcut: preferences.areaCaptureShortcut) { shortcut in
                        guard onAreaCaptureShortcutChange(shortcut) else {
                            return false
                        }

                        preferences = preferences.updatingAreaCaptureShortcut(shortcut)
                        return true
                    } onShortcutReset: {
                        let shortcut = onAreaCaptureShortcutReset()
                        preferences = preferences.resettingAreaCaptureShortcut()
                        return shortcut
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
                    } onShortcutReset: {
                        let shortcut = onCaptureOptionsShortcutReset()
                        preferences = preferences.resettingCaptureOptionsShortcut()
                        return shortcut
                    }
                    .frame(width: 160)
                }

                LabeledContent("Open history shortcut") {
                    ShortcutRecorderView(shortcut: preferences.openHistoryShortcut) { shortcut in
                        guard onOpenHistoryShortcutChange(shortcut) else {
                            return false
                        }

                        preferences = preferences.updatingOpenHistoryShortcut(shortcut)
                        return true
                    } onShortcutReset: {
                        let shortcut = onOpenHistoryShortcutReset()
                        preferences = preferences.resettingOpenHistoryShortcut()
                        return shortcut
                    }
                    .frame(width: 160)
                }

                Text(
                    "Command-Shift-3, Command-Shift-4, and Command-Shift-5 stay reserved for macOS screenshots unless changed in System Settings."
                )
                .font(.footnote)
                .foregroundStyle(.secondary)
            } header: {
                Text("Capture")
                    .accessibilityIdentifier("preferences-shortcuts-section")
            }

            Section {
                LabeledContent("Original captures") {
                    storageFolderRow(path: preferences.originalsFolderPath)
                }

                LabeledContent("Edited captures") {
                    storageFolderRow(path: preferences.editedFolderPath)
                }
            } header: {
                Text("Storage")
                    .accessibilityIdentifier("preferences-storage-section")
            }
        }
        .formStyle(.grouped)
        .padding(20)
        .frame(minWidth: 540, minHeight: 360)
        .accessibilityIdentifier("preferences-root")
    }

    private func storageFolderRow(path: String) -> some View {
        StorageFolderRow(path: path, onOpen: onOpenStorageFolder)
    }
}

private struct StorageFolderRow: View {
    let path: String
    let onOpen: (String) -> Void

    var body: some View {
        HStack(spacing: 8) {
            Text(folderName)
                .lineLimit(1)
                .truncationMode(.middle)
                .textSelection(.enabled)
                .help(path)
                .foregroundStyle(.secondary)

            Button {
                onOpen(path)
            } label: {
                Label("Open", systemImage: "folder")
            }
            .help("Open folder in Finder")
            .accessibilityLabel("Open \(folderName) folder in Finder")
        }
    }

    private var folderName: String {
        let folderName = URL(fileURLWithPath: path, isDirectory: true).lastPathComponent

        return folderName.isEmpty ? path : folderName
    }
}

#Preview("Storage folder row") {
    Form {
        LabeledContent("Original screenshots") {
            StorageFolderRow(
                path: "/Users/example/Library/Application Support/ScreenshotMaxxing/Captures/originals",
                onOpen: { _ in }
            )
        }
    }
    .formStyle(.grouped)
    .padding()
    .frame(width: 360)
}

#Preview {
    PreferencesView(
        preferences: PreferencesData(
            areaCaptureShortcut: .defaultAreaCapture,
            captureOptionsShortcut: .defaultCaptureOptions,
            openHistoryShortcut: .defaultOpenHistory,
            launchAtLoginEnabled: false,
            originalsFolderPath: "/Users/example/Library/Application Support/ScreenshotMaxxing/Captures/originals",
            editedFolderPath: "/Users/example/Library/Application Support/ScreenshotMaxxing/Captures/edited"
        )
    )
}
