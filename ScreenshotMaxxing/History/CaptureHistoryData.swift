//
//  CaptureHistoryData.swift
//  ScreenshotMaxxing
//
//  Created by Ben Kramer on 5/26/26.
//

import Foundation
import SwiftData

enum CaptureHistoryData {
    static var newestFirstSortDescriptors: [SortDescriptor<Capture>] {
        [SortDescriptor(\Capture.createdAt, order: .reverse)]
    }

    static func newestFirstFetchDescriptor() -> FetchDescriptor<Capture> {
        FetchDescriptor(sortBy: newestFirstSortDescriptors)
    }

    static func previewFilePath(for capture: Capture) -> String {
        capture.editedFilePath ?? capture.originalFilePath
    }

    static func previewFileURL(for capture: Capture) -> URL {
        URL(fileURLWithPath: previewFilePath(for: capture))
    }

    static func fileExists(for capture: Capture, fileManager: FileManager = .default) -> Bool {
        fileManager.fileExists(atPath: previewFilePath(for: capture))
    }

    static func filteredCaptures(
        _ captures: [Capture],
        searchText: String,
        calendar: Calendar = .current
    ) -> [Capture] {
        captures.filter { capture in
            matchesSearch(capture, searchText: searchText, calendar: calendar)
        }
    }

    static func matchesSearch(
        _ capture: Capture,
        searchText: String,
        calendar: Calendar = .current
    ) -> Bool {
        let normalizedQuery = normalize(searchText)

        guard !normalizedQuery.isEmpty else {
            return true
        }

        return searchTokens(for: capture, calendar: calendar)
            .contains { normalize($0).contains(normalizedQuery) }
    }

    static func detailText(for capture: Capture) -> String {
        "\(displayMode(for: capture.captureMode)) - \(capture.width)x\(capture.height)"
    }

    static func displayMode(for captureMode: String) -> String {
        guard let mode = CaptureMode(rawValue: captureMode) else {
            return captureMode.capitalized
        }

        return mode.displayName
    }

    @MainActor
    static func capturesToDelete(from captures: [Capture], selectedIDs: Set<UUID>) -> [Capture] {
        var idsToDelete = selectedIDs
        var changed = true

        while changed {
            changed = false

            let selectedCaptures = captures.filter { idsToDelete.contains($0.id) }
            let editedPrefixes = selectedCaptures.flatMap(editedVersionPrefixes)

            for capture in captures where !idsToDelete.contains(capture.id) {
                if isEditedVersion(capture, matchingAnyOf: editedPrefixes) {
                    idsToDelete.insert(capture.id)
                    changed = true
                }
            }
        }

        return captures.filter { idsToDelete.contains($0.id) }
    }

    @MainActor
    static func deleteCaptures(
        _ capturesToDelete: [Capture],
        from modelContext: ModelContext,
        allCaptures: [Capture],
        fileManager: FileManager = .default
    ) throws {
        let fileURLs = try fileURLsToDelete(
            for: capturesToDelete,
            allCaptures: allCaptures,
            fileManager: fileManager
        )

        for fileURL in fileURLs where fileManager.fileExists(atPath: fileURL.fileSystemPath) {
            try fileManager.removeItem(at: fileURL)
        }

        let expandedCapturesToDelete = Self.capturesToDelete(
            from: allCaptures,
            selectedIDs: Set(capturesToDelete.map(\.id))
        )

        for capture in expandedCapturesToDelete {
            modelContext.delete(capture)
        }

        try modelContext.save()
    }

    @MainActor
    static func fileURLsToDelete(
        for capturesToDelete: [Capture],
        allCaptures: [Capture],
        fileManager: FileManager = .default
    ) throws -> [URL] {
        let expandedCapturesToDelete = Self.capturesToDelete(
            from: allCaptures,
            selectedIDs: Set(capturesToDelete.map(\.id))
        )
        var fileURLs = Set<URL>()

        for capture in expandedCapturesToDelete {
            fileURLs.insert(URL(fileURLWithPath: capture.originalFilePath))

            if let editedFilePath = capture.editedFilePath {
                fileURLs.insert(URL(fileURLWithPath: editedFilePath))
            }

            try editedVersionFileURLs(for: capture, fileManager: fileManager).forEach { editedFileURL in
                fileURLs.insert(editedFileURL)
            }
        }

        return fileURLs.sorted { $0.fileSystemPath < $1.fileSystemPath }
    }

    private static func searchTokens(for capture: Capture, calendar: Calendar) -> [String] {
        [
            capture.fileName,
            displayMode(for: capture.captureMode),
            capture.captureMode,
            detailText(for: capture),
            "\(capture.width)x\(capture.height)"
        ] + dateSearchTokens(for: capture.createdAt, calendar: calendar)
    }

    private static func dateSearchTokens(for date: Date, calendar: Calendar) -> [String] {
        let components = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        guard let year = components.year,
              let month = components.month,
              let day = components.day,
              let hour = components.hour,
              let minute = components.minute else {
            return []
        }

        return [
            String(format: "%04d-%02d-%02d", year, month, day),
            String(format: "%04d/%02d/%02d", year, month, day),
            String(format: "%02d/%02d/%04d", month, day, year),
            String(format: "%02d/%02d/%02d", month, day, year % 100),
            String(format: "%d/%d/%04d", month, day, year),
            String(format: "%d/%d/%02d", month, day, year % 100),
            String(format: "%02d:%02d", hour, minute)
        ] + monthNameDateSearchTokens(month: month, day: day, year: year)
    }

    private static func monthNameDateSearchTokens(month: Int, day: Int, year: Int) -> [String] {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")

        guard formatter.monthSymbols.indices.contains(month - 1),
              formatter.shortMonthSymbols.indices.contains(month - 1) else {
            return []
        }

        let fullMonth = formatter.monthSymbols[month - 1]
        let shortMonth = formatter.shortMonthSymbols[month - 1]

        return [
            "\(fullMonth) \(day)",
            "\(fullMonth) \(day) \(year)",
            "\(shortMonth) \(day)",
            "\(shortMonth) \(day) \(year)"
        ]
    }

    private static func normalize(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private static func editedVersionPrefixes(for capture: Capture) -> [String] {
        filePaths(for: capture).map { filePath in
            "\(URL(fileURLWithPath: filePath).deletingPathExtension().lastPathComponent)-edited-"
        }
    }

    private static func isEditedVersion(_ capture: Capture, matchingAnyOf prefixes: [String]) -> Bool {
        filePaths(for: capture).contains { filePath in
            let fileName = URL(fileURLWithPath: filePath).lastPathComponent

            return prefixes.contains { fileName.hasPrefix($0) }
        }
    }

    private static func filePaths(for capture: Capture) -> [String] {
        [capture.originalFilePath, capture.editedFilePath]
            .compactMap { $0 }
    }

    private static func editedVersionFileURLs(for capture: Capture, fileManager: FileManager) throws -> [URL] {
        var fileURLs = [URL]()

        for editedDirectory in editedDirectories(for: capture) {
            guard fileManager.fileExists(atPath: editedDirectory.fileSystemPath) else {
                continue
            }
            let editedFileURLs = try fileManager.contentsOfDirectory(
                at: editedDirectory,
                includingPropertiesForKeys: nil
            )
            let editedPrefixes = editedVersionPrefixes(for: capture)

            fileURLs.append(contentsOf: editedFileURLs.filter { editedFileURL in
                editedPrefixes.contains { editedFileURL.lastPathComponent.hasPrefix($0) }
            })
        }

        return fileURLs
    }

    private static func editedDirectories(for capture: Capture) -> [URL] {
        let directories = filePaths(for: capture).map { filePath in
            let fileURL = URL(fileURLWithPath: filePath)
            let containingDirectory = fileURL.deletingLastPathComponent()

            if containingDirectory.lastPathComponent == "originals" {
                return containingDirectory
                    .deletingLastPathComponent()
                    .appendingPathComponent("edited", isDirectory: true)
            }

            return containingDirectory
        }

        return Array(Set(directories))
    }
}
