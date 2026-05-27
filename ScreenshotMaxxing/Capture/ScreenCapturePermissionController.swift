//
//  ScreenCapturePermissionController.swift
//  ScreenshotMaxxing
//
//  Created by Ben Kramer on 5/26/26.
//

import CoreGraphics

struct ScreenCapturePermissionController {
    typealias AccessPreflight = () -> Bool
    typealias AccessRequest = () -> Bool

    private let preflightAccess: AccessPreflight
    private let requestAccess: AccessRequest

    init(
        preflightAccess: @escaping AccessPreflight = CGPreflightScreenCaptureAccess,
        requestAccess: @escaping AccessRequest = CGRequestScreenCaptureAccess
    ) {
        self.preflightAccess = preflightAccess
        self.requestAccess = requestAccess
    }

    @discardableResult
    func requestAccessIfNeeded() -> Bool {
        if preflightAccess() {
            return true
        }

        return requestAccess()
    }
}
