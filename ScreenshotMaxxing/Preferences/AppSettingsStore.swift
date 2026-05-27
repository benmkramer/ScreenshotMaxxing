//
//  AppSettingsStore.swift
//  ScreenshotMaxxing
//
//  Created by Ben Kramer on 5/26/26.
//

import Foundation

struct AppSettingsStore {
    private static let menuBarIconVisibleKey = "menuBarIconVisible"

    private let userDefaults: UserDefaults

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
    }

    func menuBarIconVisible() -> Bool {
        guard userDefaults.object(forKey: Self.menuBarIconVisibleKey) != nil else {
            return true
        }

        return userDefaults.bool(forKey: Self.menuBarIconVisibleKey)
    }

    func saveMenuBarIconVisible(_ isVisible: Bool) {
        userDefaults.set(isVisible, forKey: Self.menuBarIconVisibleKey)
    }
}
