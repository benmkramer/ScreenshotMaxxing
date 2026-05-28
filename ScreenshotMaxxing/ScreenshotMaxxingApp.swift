//
//  ScreenshotMaxxingApp.swift
//  ScreenshotMaxxing
//
//  Created by Ben Kramer on 5/26/26.
//

import SwiftUI

@main
struct ScreenshotMaxxingApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        Settings {
            PreferencesSettingsScene {
                try appDelegate.makePreferencesView()
            }
        }
    }
}

private struct PreferencesSettingsScene: View {
    let makePreferencesView: () throws -> PreferencesView

    var body: some View {
        makeBody()
    }

    private func makeBody() -> AnyView {
        do {
            return AnyView(try makePreferencesView())
        } catch {
            return AnyView(
                Text(error.localizedDescription)
                    .padding(24)
                    .frame(minWidth: 360, minHeight: 160)
            )
        }
    }
}
