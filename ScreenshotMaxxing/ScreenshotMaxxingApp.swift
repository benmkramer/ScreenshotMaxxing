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
            if Self.isRunningHostedUnitTests {
                EmptyView()
            } else {
                PreferencesSettingsScene {
                    try appDelegate.makePreferencesView()
                }
            }
        }
    }

    private static var isRunningHostedUnitTests: Bool {
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
            && !ProcessInfo.processInfo.arguments.contains("--screenshotmaxxing-ui-testing")
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
