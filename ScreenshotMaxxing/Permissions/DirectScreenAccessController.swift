//
//  DirectScreenAccessController.swift
//  ScreenshotMaxxing
//
//  Created by Ben Kramer on 5/28/26.
//

import Foundation

struct DirectScreenAccessController {
    typealias ApprovalPreflight = () -> Bool
    typealias ApprovalRequest = () async -> Bool

    private static let approvalCompletedKey = "permissions.directScreenAccessApprovalCompleted"

    private let preflightApproval: ApprovalPreflight
    private let requestApproval: ApprovalRequest
    private let markApprovalCompleted: () -> Void
    private let clearStoredApproval: () -> Void

    init(
        userDefaults: UserDefaults = .standard,
        requestApproval: ApprovalRequest? = nil
    ) {
        self.preflightApproval = {
            userDefaults.bool(forKey: Self.approvalCompletedKey)
        }
        self.requestApproval =
            requestApproval ?? {
                await DirectScreenAccessController.requestSystemApproval()
            }
        self.markApprovalCompleted = {
            userDefaults.set(true, forKey: Self.approvalCompletedKey)
        }
        self.clearStoredApproval = {
            userDefaults.removeObject(forKey: Self.approvalCompletedKey)
        }
    }

    init(
        _ preflightApproval: @escaping ApprovalPreflight,
        requestApproval: @escaping ApprovalRequest,
        markApprovalCompleted: @escaping () -> Void = {},
        clearStoredApproval: @escaping () -> Void = {}
    ) {
        self.preflightApproval = preflightApproval
        self.requestApproval = requestApproval
        self.markApprovalCompleted = markApprovalCompleted
        self.clearStoredApproval = clearStoredApproval
    }

    func hasAccess() -> Bool {
        preflightApproval()
    }

    @discardableResult
    func requestAccessIfNeeded() async -> Bool {
        if hasAccess() {
            return true
        }

        guard await requestApproval() else {
            return false
        }

        markApprovalCompleted()
        return true
    }

    func clearApproval() {
        clearStoredApproval()
    }

    nonisolated private static func requestSystemApproval() async -> Bool {
        let fileManager = FileManager.default
        let outputURL = fileManager.temporaryDirectory
            .appendingPathComponent("ScreenshotMaxxing-Permission-\(UUID().uuidString).png")
        let outputPath = outputURL.path
        defer {
            try? fileManager.removeItem(at: outputURL)
        }

        do {
            let status = try await Task.detached {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
                process.arguments = ["-x", outputPath]
                try process.run()
                process.waitUntilExit()
                return process.terminationStatus
            }.value

            return status == 0 && fileManager.fileExists(atPath: outputPath)
        } catch {
            return false
        }
    }
}
