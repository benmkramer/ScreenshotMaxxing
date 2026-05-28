//
//  ShortcutSettingsStore.swift
//  ScreenshotMaxxing
//
//  Created by Ben Kramer on 5/26/26.
//

import Foundation

struct ShortcutSettingsStore {
    private static let areaCaptureShortcutKey = "areaCaptureShortcut"
    private static let captureOptionsShortcutKey = "captureOptionsShortcut"

    private let userDefaults: UserDefaults
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
    }

    func areaCaptureShortcut() -> GlobalKeyboardShortcut {
        shortcut(forKey: Self.areaCaptureShortcutKey, defaultShortcut: .defaultAreaCapture)
    }

    func captureOptionsShortcut() -> GlobalKeyboardShortcut {
        shortcut(forKey: Self.captureOptionsShortcutKey, defaultShortcut: .defaultCaptureOptions)
    }

    func saveAreaCaptureShortcut(_ shortcut: GlobalKeyboardShortcut) throws {
        try save(shortcut, forKey: Self.areaCaptureShortcutKey)
    }

    func saveCaptureOptionsShortcut(_ shortcut: GlobalKeyboardShortcut) throws {
        try save(shortcut, forKey: Self.captureOptionsShortcutKey)
    }

    private func shortcut(
        forKey key: String,
        defaultShortcut: GlobalKeyboardShortcut
    ) -> GlobalKeyboardShortcut {
        guard let data = userDefaults.data(forKey: key),
              let shortcut = try? decoder.decode(GlobalKeyboardShortcut.self, from: data) else {
            return defaultShortcut
        }

        return shortcut
    }

    private func save(_ shortcut: GlobalKeyboardShortcut, forKey key: String) throws {
        let data = try encoder.encode(shortcut)
        userDefaults.set(data, forKey: key)
    }
}
