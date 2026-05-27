//
//  CaptureController.swift
//  ScreenshotMaxxing
//
//  Created by Ben Kramer on 5/26/26.
//

import Foundation

struct CaptureResult: Equatable {
    let mode: CaptureMode
    let fileURL: URL
}

enum CaptureError: LocalizedError, Equatable {
    case cancelled
    case missingOutput(URL)
    case commandFailed(status: Int32)

    var errorDescription: String? {
        switch self {
        case .cancelled:
            "Capture canceled."
        case .missingOutput(let url):
            "Capture finished but did not create an image at \(url.fileSystemPath)."
        case .commandFailed(let status):
            "Capture failed with status \(status)."
        }
    }
}

struct CaptureController {
    typealias ScreencaptureRunner = @MainActor ([String]) async throws -> Int32

    private let fileManager: FileManager
    private let runScreencapture: ScreencaptureRunner

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
        self.runScreencapture = CaptureController.runScreencapture
    }

    init(fileManager: FileManager = .default, runScreencapture: @escaping ScreencaptureRunner) {
        self.fileManager = fileManager
        self.runScreencapture = runScreencapture
    }

    func captureArea(baseDirectory: URL? = nil) async throws -> CaptureResult {
        try await capture(.area, baseDirectory: baseDirectory)
    }

    func captureWindow(baseDirectory: URL? = nil) async throws -> CaptureResult {
        try await capture(.window, baseDirectory: baseDirectory)
    }

    func captureFullscreen(baseDirectory: URL? = nil) async throws -> CaptureResult {
        try await capture(.fullscreen, baseDirectory: baseDirectory)
    }

    private func capture(_ mode: CaptureMode, baseDirectory: URL?) async throws -> CaptureResult {
        let directories = try FileLocations.ensureCaptureDirectories(
            baseDirectory: baseDirectory,
            fileManager: fileManager
        )
        let outputURL = FileLocations.uniqueOriginalFileURL(
            captureMode: mode.fileNamePrefix,
            directories: directories
        )
        let status = try await runScreencapture(mode.screencaptureArguments(outputURL: outputURL))
        let fileExists = fileManager.fileExists(atPath: outputURL.fileSystemPath)

        if mode.usesInteractiveSelection && !fileExists {
            throw CaptureError.cancelled
        }

        guard status == 0 else {
            throw CaptureError.commandFailed(status: status)
        }

        guard fileExists else {
            throw CaptureError.missingOutput(outputURL)
        }

        return CaptureResult(mode: mode, fileURL: outputURL)
    }

    private static func runScreencapture(arguments: [String]) async throws -> Int32 {
        try await Task.detached {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
            process.arguments = arguments
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus
        }.value
    }
}
