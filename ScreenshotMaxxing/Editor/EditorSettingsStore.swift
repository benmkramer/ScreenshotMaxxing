//
//  EditorSettingsStore.swift
//  ScreenshotMaxxing
//
//  Created by Ben Kramer on 5/26/26.
//

import Foundation

struct EditorSettingsStore {
    private static let strokeToolSettingsKey = "editor.strokeToolSettings"

    private let userDefaults: UserDefaults
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
    }

    func strokeToolSettings() -> StrokeToolSettings {
        guard let data = userDefaults.data(forKey: Self.strokeToolSettingsKey),
              let settings = try? decoder.decode(StrokeToolSettings.self, from: data) else {
            return .defaultSettings
        }

        return settings.normalized
    }

    func saveStrokeToolSettings(_ settings: StrokeToolSettings) throws {
        let data = try encoder.encode(settings.normalized)
        userDefaults.set(data, forKey: Self.strokeToolSettingsKey)
    }
}
