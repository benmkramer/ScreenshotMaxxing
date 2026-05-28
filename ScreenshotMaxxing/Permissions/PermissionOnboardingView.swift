//
//  PermissionOnboardingView.swift
//  ScreenshotMaxxing
//
//  Created by Ben Kramer on 5/27/26.
//

import AppKit
import Combine
import SwiftUI

@MainActor
final class PermissionOnboardingModel: ObservableObject {
    @Published private(set) var states: [AppPermissionState]
    @Published private(set) var setupStartedPermissions: Set<AppPermission> = []

    var onComplete: () -> Void = {}

    private let permissionController: AppPermissionController
    private let openURL: (URL) -> Void
    private let relaunchApp: @MainActor () -> Void

    init(
        permissionController: AppPermissionController,
        openURL: @escaping (URL) -> Void = { NSWorkspace.shared.open($0) },
        relaunchApp: @escaping @MainActor () -> Void = PermissionOnboardingModel.relaunchCurrentApp
    ) {
        self.permissionController = permissionController
        self.openURL = openURL
        self.relaunchApp = relaunchApp
        self.states = permissionController.permissionStates()
    }

    var allGranted: Bool {
        states.allSatisfy(\.isGranted)
    }

    var needsRelaunch: Bool {
        states.contains { state in
            !state.isGranted &&
            state.permission.requiresRelaunchAfterGrant &&
            setupStartedPermissions.contains(state.permission)
        }
    }

    var footerText: String {
        if allGranted {
            return "ScreenshotMaxxing is ready."
        }

        if needsRelaunch {
            return "After enabling Screen Recording, relaunch ScreenshotMaxxing to apply the change."
        }

        return "Enable Screen Recording in System Settings to finish setup."
    }

    var primaryActionTitle: String {
        needsRelaunch ? "Relaunch" : "Done"
    }

    func refresh() {
        states = permissionController.permissionStates()

        if allGranted {
            setupStartedPermissions = []
        }
    }

    func requestAccess(for permission: AppPermission) {
        setupStartedPermissions.insert(permission)
        _ = permissionController.requestAccessIfNeeded(for: permission)
        refresh()

        guard !permissionController.hasAccess(for: permission) else {
            return
        }

        openSettings(for: permission)
    }

    func openSettings(for permission: AppPermission) {
        guard let settingsURL = permission.settingsURL else {
            return
        }

        openURL(settingsURL)
    }

    func primaryAction() {
        refresh()

        if allGranted {
            onComplete()
        } else if needsRelaunch {
            relaunchApp()
        }
    }

    func actionTitle(for permission: AppPermission) -> String {
        setupStartedPermissions.contains(permission) ? "Open Settings" : "Set Up"
    }

    private static func relaunchCurrentApp() {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        process.arguments = ["-n", Bundle.main.bundlePath]

        do {
            try process.run()
            NSApp.terminate(nil)
        } catch {
            NSApp.terminate(nil)
        }
    }
}

struct PermissionOnboardingView: View {
    @ObservedObject var model: PermissionOnboardingModel

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            header

            VStack(spacing: 0) {
                ForEach(model.states) { state in
                    PermissionOnboardingRow(state: state, actionTitle: model.actionTitle(for: state.permission)) {
                        model.requestAccess(for: state.permission)
                    }

                    if state.id != model.states.last?.id {
                        Divider()
                    }
                }
            }
            .background(.background)
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(.quaternary, lineWidth: 1)
            }

            footer
        }
        .padding(28)
        .frame(width: 560)
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: "camera.viewfinder")
                .font(.system(size: 34, weight: .medium))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(Color.accentColor)
                .frame(width: 42, height: 42)

            VStack(alignment: .leading, spacing: 6) {
                Text("Set Up ScreenshotMaxxing")
                    .font(.title2.weight(.semibold))

                Text("Enable Screen Recording before taking your first screenshot.")
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var footer: some View {
        HStack(spacing: 12) {
            Text(model.footerText)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Spacer()

            Button("Refresh") {
                model.refresh()
            }

            Button(model.primaryActionTitle) {
                model.primaryAction()
            }
            .keyboardShortcut(.defaultAction)
            .disabled(!model.allGranted && !model.needsRelaunch)
        }
    }
}

private struct PermissionOnboardingRow: View {
    let state: AppPermissionState
    let actionTitle: String
    let requestAccess: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: state.isGranted ? "checkmark.circle.fill" : state.permission.systemImageName)
                .font(.system(size: 20, weight: .semibold))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(state.isGranted ? .green : .secondary)
                .frame(width: 28, height: 28)

            VStack(alignment: .leading, spacing: 4) {
                Text(state.permission.displayName)
                    .font(.headline)

                Text(state.permission.explanation)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 16)

            if state.isGranted {
                Text("Allowed")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.green)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
            } else {
                Button(actionTitle, action: requestAccess)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 13)
    }
}

#Preview {
    PermissionOnboardingView(
        model: PermissionOnboardingModel(
            permissionController: AppPermissionController(
                screenCapturePermissionController: ScreenCapturePermissionController {
                    false
                } requestAccess: {
                    false
                }
            )
        )
    )
}
