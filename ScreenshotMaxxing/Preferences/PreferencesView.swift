//
//  PreferencesView.swift
//  ScreenshotMaxxing
//
//  Created by Ben Kramer on 5/26/26.
//

import SwiftUI

struct PreferencesView: View {
    let preferences: PreferencesData

    var body: some View {
        Form {
            Section("Capture") {
                LabeledContent("Area capture shortcut") {
                    Text(preferences.areaCaptureShortcut.displayString)
                        .font(.system(.body, design: .monospaced))
                        .textSelection(.enabled)
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
