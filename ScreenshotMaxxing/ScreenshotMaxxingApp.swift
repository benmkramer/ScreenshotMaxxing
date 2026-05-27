//
//  ScreenshotMaxxingApp.swift
//  ScreenshotMaxxing
//
//  Created by Ben Kramer on 5/26/26.
//

import SwiftUI
import SwiftData

@main
struct ScreenshotMaxxingApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(PersistenceController.sharedModelContainer)
    }
}
