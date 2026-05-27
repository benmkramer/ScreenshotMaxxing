//
//  ShortcutSettingsStore.swift
//  ScreenshotMaxxing
//
//  Created by Ben Kramer on 5/26/26.
//

import Foundation

struct ShortcutSettingsStore {
    private static let areaCaptureShortcutKey = "areaCaptureShortcut"

    private let userDefaults: UserDefaults
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
    }

    func areaCaptureShortcut() -> GlobalKeyboardShortcut {
        guard let data = userDefaults.data(forKey: Self.areaCaptureShortcutKey),
              let shortcut = try? decoder.decode(GlobalKeyboardShortcut.self, from: data) else {
            return .defaultAreaCapture
        }

        return shortcut
    }

    func saveAreaCaptureShortcut(_ shortcut: GlobalKeyboardShortcut) throws {
        let data = try encoder.encode(shortcut)
        userDefaults.set(data, forKey: Self.areaCaptureShortcutKey)
    }
}
