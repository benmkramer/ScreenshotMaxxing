//
//  FileLocations.swift
//  ScreenshotMaxxing
//
//  Created by Ben Kramer on 5/26/26.
//

import Foundation

extension URL {
    var fileSystemPath: String {
        path(percentEncoded: false)
    }
}

struct CaptureDirectories: Equatable {
    let root: URL
    let originals: URL
    let edited: URL
    let thumbnails: URL
}

enum FileLocations {
    static let applicationSupportFolderName = "ScreenshotMaxxing"

    static func applicationSupportDirectory(fileManager: FileManager = .default) throws -> URL {
        try fileManager
            .url(
                for: .applicationSupportDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: true
            )
            .appendingPathComponent(applicationSupportFolderName, isDirectory: true)
    }

    static func captureDirectories(baseDirectory: URL? = nil, fileManager: FileManager = .default) throws -> CaptureDirectories {
        let appSupport = try baseDirectory ?? applicationSupportDirectory(fileManager: fileManager)
        let root = appSupport.appendingPathComponent("Captures", isDirectory: true)

        return CaptureDirectories(
            root: root,
            originals: root.appendingPathComponent("originals", isDirectory: true),
            edited: root.appendingPathComponent("edited", isDirectory: true),
            thumbnails: root.appendingPathComponent("thumbnails", isDirectory: true)
        )
    }

    @discardableResult
    static func ensureCaptureDirectories(
        baseDirectory: URL? = nil,
        fileManager: FileManager = .default
    ) throws -> CaptureDirectories {
        let directories = try captureDirectories(baseDirectory: baseDirectory, fileManager: fileManager)

        try [directories.root, directories.originals, directories.edited, directories.thumbnails].forEach { directory in
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        }

        return directories
    }

    static func uniqueOriginalFileURL(
        captureMode: String,
        directories: CaptureDirectories,
        date: Date = Date(),
        uuid: UUID = UUID(),
        fileExtension: String = "png"
    ) -> URL {
        let fileName = uniqueFileName(prefix: captureMode, date: date, uuid: uuid, fileExtension: fileExtension)
        return directories.originals.appendingPathComponent(fileName, isDirectory: false)
    }

    static func uniqueEditedFileURL(
        originalFileName: String,
        directories: CaptureDirectories,
        uuid: UUID = UUID(),
        fileExtension: String = "png"
    ) -> URL {
        let baseName = URL(fileURLWithPath: originalFileName).deletingPathExtension().lastPathComponent
        return directories.edited.appendingPathComponent("\(baseName)-edited-\(uuid.uuidString.prefix(8)).\(fileExtension)")
    }

    static func uniqueThumbnailFileURL(
        originalFileName: String,
        directories: CaptureDirectories,
        uuid: UUID = UUID()
    ) -> URL {
        let baseName = URL(fileURLWithPath: originalFileName).deletingPathExtension().lastPathComponent
        return directories.thumbnails.appendingPathComponent("\(baseName)-thumbnail-\(uuid.uuidString.prefix(8)).png")
    }

    private static func uniqueFileName(prefix: String, date: Date, uuid: UUID, fileExtension: String) -> String {
        let safePrefix = prefix
            .lowercased()
            .replacingOccurrences(of: " ", with: "-")
        let timestamp = utcTimestamp(from: date)

        return "\(safePrefix)-\(timestamp)-\(uuid.uuidString.prefix(8)).\(fileExtension)"
    }

    private static func utcTimestamp(from date: Date) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let components = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)

        return String(
            format: "%04d%02d%02d-%02d%02d%02d",
            components.year ?? 0,
            components.month ?? 0,
            components.day ?? 0,
            components.hour ?? 0,
            components.minute ?? 0,
            components.second ?? 0
        )
    }
}
