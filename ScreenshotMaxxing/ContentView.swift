//
//  ContentView.swift
//  ScreenshotMaxxing
//
//  Created by Ben Kramer on 5/26/26.
//

import SwiftUI

struct ContentView: View {
    let captureArea: () -> Void
    let openHistory: () -> Void
    let openPreferences: () -> Void

    init(
        captureArea: @escaping () -> Void = {},
        openHistory: @escaping () -> Void = {},
        openPreferences: @escaping () -> Void = {}
    ) {
        self.captureArea = captureArea
        self.openHistory = openHistory
        self.openPreferences = openPreferences
    }

    var body: some View {
        VStack(spacing: 18) {
            Image(systemName: "camera.viewfinder")
                .font(.system(size: 44, weight: .medium))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.secondary)

            Text("ScreenshotMaxxing")
                .font(.title2.weight(.semibold))

            Text("Use Control-Shift-4 for ScreenshotMaxxing captures.")
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            HStack(spacing: 10) {
                Button(action: captureArea) {
                    Label("Capture Area", systemImage: "viewfinder")
                }
                .keyboardShortcut("4", modifiers: [.control, .shift])

                Button(action: openHistory) {
                    Label("History", systemImage: "clock.arrow.circlepath")
                }

                Button(action: openPreferences) {
                    Label("Preferences", systemImage: "gearshape")
                }
            }
            .buttonStyle(.bordered)
        }
        .padding(32)
        .frame(minWidth: 460, minHeight: 300)
    }
}

#Preview {
    ContentView()
}
