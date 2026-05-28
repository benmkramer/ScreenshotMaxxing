//
//  AppPermissionController.swift
//  ScreenshotMaxxing
//
//  Created by Ben Kramer on 5/27/26.
//

import Foundation

enum AppPermission: CaseIterable, Equatable, Identifiable {
    case screenCapture

    var id: Self {
        self
    }

    var displayName: String {
        switch self {
        case .screenCapture:
            "Screen Recording"
        }
    }

    var explanation: String {
        switch self {
        case .screenCapture:
            "Allows ScreenshotMaxxing to capture your screen."
        }
    }

    var systemImageName: String {
        switch self {
        case .screenCapture:
            "display"
        }
    }

    var settingsURL: URL? {
        let path = switch self {
        case .screenCapture:
            "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture"
        }

        return URL(string: path)
    }

    var requiresRelaunchAfterGrant: Bool {
        switch self {
        case .screenCapture:
            true
        }
    }
}

struct AppPermissionState: Equatable, Identifiable {
    let permission: AppPermission
    let isGranted: Bool

    var id: AppPermission {
        permission
    }
}

struct AppPermissionController {
    private let screenCapturePermissionController: ScreenCapturePermissionController

    init(
        screenCapturePermissionController: ScreenCapturePermissionController = ScreenCapturePermissionController()
    ) {
        self.screenCapturePermissionController = screenCapturePermissionController
    }

    func permissionStates() -> [AppPermissionState] {
        AppPermission.allCases.map { permission in
            AppPermissionState(permission: permission, isGranted: hasAccess(for: permission))
        }
    }

    func hasAllRequiredPermissions() -> Bool {
        permissionStates().allSatisfy(\.isGranted)
    }

    func hasAccess(for permission: AppPermission) -> Bool {
        switch permission {
        case .screenCapture:
            screenCapturePermissionController.hasAccess()
        }
    }

    @discardableResult
    func requestAccessIfNeeded(for permission: AppPermission) -> Bool {
        switch permission {
        case .screenCapture:
            screenCapturePermissionController.requestAccessIfNeeded()
        }
    }
}
