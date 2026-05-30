//
//  RecordingSettingsStore.swift
//  ScreenshotMaxxing
//
//  Created by Codex on 5/29/26.
//

import Foundation

struct RecordingSettingsStore {
    private enum Keys {
        static let microphoneEnabled = "recording.microphoneEnabled"
        static let systemAudioEnabled = "recording.systemAudioEnabled"
    }

    private let userDefaults: UserDefaults

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
    }

    func microphoneEnabled() -> Bool {
        userDefaults.bool(forKey: Keys.microphoneEnabled)
    }

    func saveMicrophoneEnabled(_ isEnabled: Bool) throws {
        userDefaults.set(isEnabled, forKey: Keys.microphoneEnabled)
    }

    func systemAudioEnabled() -> Bool {
        userDefaults.bool(forKey: Keys.systemAudioEnabled)
    }

    func saveSystemAudioEnabled(_ isEnabled: Bool) throws {
        userDefaults.set(isEnabled, forKey: Keys.systemAudioEnabled)
    }
}
