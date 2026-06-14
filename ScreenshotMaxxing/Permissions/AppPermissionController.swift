//
//  AppPermissionController.swift
//  ScreenshotMaxxing
//
//  Created by Ben Kramer on 5/27/26.
//

import Foundation

enum AppPermission: CaseIterable, Equatable, Identifiable {
    case screenCapture
    case directScreenAccess

    var id: Self {
        self
    }

    var displayName: String {
        switch self {
        case .screenCapture:
            "Screen Recording"
        case .directScreenAccess:
            "First Capture Check"
        }
    }

    var explanation: String {
        switch self {
        case .screenCapture:
            "Allows ScreenshotMaxxing to capture and record your screen in System Settings."
        case .directScreenAccess:
            "Runs one test capture after Screen Recording is enabled so your first real capture can continue."
        }
    }

    var systemImageName: String {
        switch self {
        case .screenCapture:
            "display"
        case .directScreenAccess:
            "record.circle"
        }
    }

    var settingsURL: URL? {
        switch self {
        case .screenCapture:
            return URL(
                string: "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_ScreenCapture")
        case .directScreenAccess:
            return nil
        }
    }

    var requiresRelaunchAfterGrant: Bool {
        switch self {
        case .screenCapture:
            true
        case .directScreenAccess:
            false
        }
    }
}

struct AppPermissionState: Equatable, Identifiable {
    let permission: AppPermission
    let isGranted: Bool
    let isSetupEnabled: Bool

    var id: AppPermission {
        permission
    }
}

struct AppPermissionController {
    private let screenCapturePermissionController: ScreenCapturePermissionController
    private let directScreenAccessController: DirectScreenAccessController

    init(
        screenCapturePermissionController: ScreenCapturePermissionController = ScreenCapturePermissionController(),
        directScreenAccessController: DirectScreenAccessController = DirectScreenAccessController()
    ) {
        self.screenCapturePermissionController = screenCapturePermissionController
        self.directScreenAccessController = directScreenAccessController
    }

    func permissionStates() -> [AppPermissionState] {
        let screenCaptureGranted = screenCapturePermissionController.hasAccess()

        if !screenCaptureGranted {
            directScreenAccessController.clearApproval()
        }

        return [
            AppPermissionState(
                permission: .screenCapture,
                isGranted: screenCaptureGranted,
                isSetupEnabled: true
            ),
            AppPermissionState(
                permission: .directScreenAccess,
                isGranted: screenCaptureGranted && directScreenAccessController.hasAccess(),
                isSetupEnabled: screenCaptureGranted
            ),
        ]
    }

    func hasAllRequiredPermissions() -> Bool {
        permissionStates().allSatisfy(\.isGranted)
    }

    func hasAccess(for permission: AppPermission) -> Bool {
        switch permission {
        case .screenCapture:
            screenCapturePermissionController.hasAccess()
        case .directScreenAccess:
            screenCapturePermissionController.hasAccess() && directScreenAccessController.hasAccess()
        }
    }

    @discardableResult
    func requestAccessIfNeeded(for permission: AppPermission) async -> Bool {
        switch permission {
        case .screenCapture:
            return screenCapturePermissionController.requestAccessIfNeeded()
        case .directScreenAccess:
            guard screenCapturePermissionController.hasAccess() else {
                return false
            }

            return await directScreenAccessController.requestAccessIfNeeded()
        }
    }
}
