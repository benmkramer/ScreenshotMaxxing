//
//  LoginItemController.swift
//  ScreenshotMaxxing
//
//  Created by Ben Kramer on 5/26/26.
//

import Foundation
import ServiceManagement

enum LoginItemControllerError: LocalizedError, Equatable {
    case requiresApproval

    var errorDescription: String? {
        switch self {
        case .requiresApproval:
            "ScreenshotMaxxing needs approval in System Settings before it can open at login."
        }
    }
}

struct LoginItemController {
    var launchAtLoginEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    func setLaunchAtLoginEnabled(_ isEnabled: Bool) throws {
        if isEnabled {
            try SMAppService.mainApp.register()
        } else if SMAppService.mainApp.status != .notRegistered {
            try SMAppService.mainApp.unregister()
        }

        guard SMAppService.mainApp.status != .requiresApproval else {
            throw LoginItemControllerError.requiresApproval
        }
    }
}
