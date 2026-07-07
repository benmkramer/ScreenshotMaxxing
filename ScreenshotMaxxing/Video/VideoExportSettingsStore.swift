//
//  VideoExportSettingsStore.swift
//  ScreenshotMaxxing
//

import Foundation

struct VideoExportSettingsStore {
    private enum Keys {
        static let monoAudioEnabled = "videoExport.monoAudioEnabled"
    }

    private let userDefaults: UserDefaults

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
    }

    func monoAudioEnabled() -> Bool {
        userDefaults.bool(forKey: Keys.monoAudioEnabled)
    }

    func saveMonoAudioEnabled(_ isEnabled: Bool) throws {
        userDefaults.set(isEnabled, forKey: Keys.monoAudioEnabled)
    }
}
