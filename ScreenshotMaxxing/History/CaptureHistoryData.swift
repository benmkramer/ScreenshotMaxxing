//
//  CaptureHistoryData.swift
//  ScreenshotMaxxing
//
//  Created by Ben Kramer on 5/26/26.
//

import Foundation
import SwiftData

enum CaptureHistoryTypeFilter: String, CaseIterable, Identifiable {
    case all
    case screenshots
    case recordings
    case edited
    case missingFiles

    var id: Self { self }

    var title: String {
        switch self {
        case .all:
            "All"
        case .screenshots:
            "Screenshots"
        case .recordings:
            "Recordings"
        case .edited:
            "Edited"
        case .missingFiles:
            "Missing"
        }
    }

    var systemImage: String {
        switch self {
        case .all:
            "tray.full"
        case .screenshots:
            "photo"
        case .recordings:
            "video"
        case .edited:
            "pencil"
        case .missingFiles:
            "questionmark.folder"
        }
    }
}

enum CaptureHistoryDateFilter: String, CaseIterable, Identifiable {
    case all
    case today
    case yesterday
    case last7Days
    case last30Days

    var id: Self { self }

    var title: String {
        switch self {
        case .all:
            "Any Date"
        case .today:
            "Today"
        case .yesterday:
            "Yesterday"
        case .last7Days:
            "Last 7 Days"
        case .last30Days:
            "Last 30 Days"
        }
    }
}

enum CaptureHistoryError: LocalizedError, Equatable {
    case captureFileAvailableAgain(fileName: String)

    var errorDescription: String? {
        switch self {
        case .captureFileAvailableAgain(let fileName):
            "The file for \(fileName) is available again. Use Delete if you want to move it to the Trash."
        }
    }
}

enum CaptureHistoryData {
    static let deleteConfirmationMessage = "Deleting from the History view removes captures and any edited versions from History. Local files that still exist are moved to the Trash."
    static let removeMissingConfirmationMessage = "Removing a missing capture only deletes its History metadata. ScreenshotMaxxing will not move any files to the Trash."

    static var newestFirstSortDescriptors: [SortDescriptor<Capture>] {
        [SortDescriptor(\Capture.createdAt, order: .reverse)]
    }

    static func newestFirstFetchDescriptor() -> FetchDescriptor<Capture> {
        FetchDescriptor(sortBy: newestFirstSortDescriptors)
    }

    static func previewFilePath(for capture: Capture) -> String {
        if mediaType(for: capture) == .video, let thumbnailFilePath = capture.thumbnailFilePath {
            return thumbnailFilePath
        }

        return contentFilePath(for: capture)
    }

    static func contentFilePath(for capture: Capture) -> String {
        capture.editedFilePath ?? capture.originalFilePath
    }

    static func previewFileURL(for capture: Capture) -> URL {
        URL(fileURLWithPath: previewFilePath(for: capture))
    }

    static func contentFileURL(for capture: Capture) -> URL {
        URL(fileURLWithPath: contentFilePath(for: capture))
    }

    static func fileExists(for capture: Capture, fileManager: FileManager = .default) -> Bool {
        fileManager.fileExists(atPath: contentFilePath(for: capture))
    }

    static func lastKnownPath(for capture: Capture) -> String {
        contentFilePath(for: capture)
    }

    static func storageFolderURL(for capture: Capture, fileManager: FileManager = .default) -> URL? {
        for filePath in lastKnownFilePaths(for: capture) {
            let folderURL = URL(fileURLWithPath: filePath).deletingLastPathComponent()
            var isDirectory: ObjCBool = false

            if fileManager.fileExists(atPath: folderURL.fileSystemPath, isDirectory: &isDirectory),
               isDirectory.boolValue {
                return folderURL
            }
        }

        return nil
    }

    static func filteredCaptures(
        _ captures: [Capture],
        searchText: String,
        typeFilter: CaptureHistoryTypeFilter = .all,
        dateFilter: CaptureHistoryDateFilter = .all,
        calendar: Calendar = .current,
        referenceDate: Date = Date(),
        fileManager: FileManager = .default
    ) -> [Capture] {
        captures.filter { capture in
            matchesTypeFilter(capture, typeFilter: typeFilter, fileManager: fileManager)
                && matchesDateFilter(capture, dateFilter: dateFilter, calendar: calendar, referenceDate: referenceDate)
                && matchesSearch(capture, searchText: searchText, calendar: calendar)
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

    static func captureIDs(in captures: [Capture]) -> Set<UUID> {
        Set(captures.map(\.id))
    }

    static func selectedVisibleCaptureIDs(
        selectedIDs: Set<UUID>,
        visibleCaptures: [Capture]
    ) -> Set<UUID> {
        selectedIDs.intersection(captureIDs(in: visibleCaptures))
    }

    static func allCaptureIDsSelected(
        _ captureIDs: Set<UUID>,
        selectedIDs: Set<UUID>
    ) -> Bool {
        !captureIDs.isEmpty && captureIDs.isSubset(of: selectedIDs)
    }

    static func toggledSelection(
        selectedIDs: Set<UUID>,
        filteredCaptureIDs: Set<UUID>
    ) -> Set<UUID> {
        if allCaptureIDsSelected(filteredCaptureIDs, selectedIDs: selectedIDs) {
            return selectedIDs.subtracting(filteredCaptureIDs)
        }

        return selectedIDs.union(filteredCaptureIDs)
    }

    static func detailText(for capture: Capture) -> String {
        let dimensions = "\(capture.width)x\(capture.height)"
        guard mediaType(for: capture) == .video, let durationSeconds = capture.durationSeconds else {
            return "\(displayMode(for: capture.captureMode)) - \(dimensions)"
        }

        return "\(displayMode(for: capture.captureMode)) - \(dimensions) - \(durationText(durationSeconds))"
    }

    static func mediaType(for capture: Capture) -> CaptureMediaType {
        CaptureMediaType(rawValue: capture.mediaType) ?? .image
    }

    static func displayMode(for captureMode: String) -> String {
        if let mode = CaptureMode(rawValue: captureMode) {
            return mode.displayName
        }

        guard let mode = RecordingMode(rawValue: captureMode) else {
            return captureMode.capitalized
        }

        return mode.displayName
    }

    static func durationText(_ durationSeconds: Double) -> String {
        let duration = max(Int(durationSeconds.rounded()), 0)
        let hours = duration / 3600
        let minutes = (duration % 3600) / 60
        let seconds = duration % 60

        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        }

        return String(format: "%d:%02d", minutes, seconds)
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
        fileManager: FileManager = .default,
        fileTrash: CaptureFileTrashing = FileManager.default
    ) throws {
        let capturesWithExistingContent = capturesToDelete.filter {
            Self.fileExists(for: $0, fileManager: fileManager)
        }
        let missingCapturesToRemove = capturesToDelete.filter {
            !Self.fileExists(for: $0, fileManager: fileManager)
        }
        let expandedCapturesToDelete = Self.capturesToDelete(
            from: allCaptures,
            selectedIDs: Set(capturesWithExistingContent.map(\.id))
        )
        let fileURLs = try fileURLsToDelete(
            for: expandedCapturesToDelete,
            allCaptures: allCaptures,
            fileManager: fileManager
        )

        for fileURL in fileURLs where fileManager.fileExists(atPath: fileURL.fileSystemPath) {
            try fileTrash.moveItemToTrash(at: fileURL)
        }

        let idsToDelete = Set(expandedCapturesToDelete.map(\.id))
            .union(missingCapturesToRemove.map(\.id))

        for capture in allCaptures where idsToDelete.contains(capture.id) {
            modelContext.delete(capture)
        }

        try modelContext.save()
    }

    @MainActor
    static func removeCapturesFromHistoryOnly(
        _ capturesToRemove: [Capture],
        from modelContext: ModelContext,
        fileManager: FileManager = .default
    ) throws {
        for capture in capturesToRemove where Self.fileExists(for: capture, fileManager: fileManager) {
            throw CaptureHistoryError.captureFileAvailableAgain(fileName: capture.fileName)
        }

        for capture in capturesToRemove {
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
            fileURLs.insert(canonicalFileURL(URL(fileURLWithPath: capture.originalFilePath)))

            if let editedFilePath = capture.editedFilePath {
                fileURLs.insert(canonicalFileURL(URL(fileURLWithPath: editedFilePath)))
            }

            if let thumbnailFilePath = capture.thumbnailFilePath {
                fileURLs.insert(canonicalFileURL(URL(fileURLWithPath: thumbnailFilePath)))
            }

            try editedVersionFileURLs(for: capture, fileManager: fileManager).forEach { editedFileURL in
                fileURLs.insert(canonicalFileURL(editedFileURL))
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

    private static func matchesTypeFilter(
        _ capture: Capture,
        typeFilter: CaptureHistoryTypeFilter,
        fileManager: FileManager
    ) -> Bool {
        switch typeFilter {
        case .all:
            true
        case .screenshots:
            mediaType(for: capture) == .image
        case .recordings:
            mediaType(for: capture) == .video
        case .edited:
            isEditedCapture(capture)
        case .missingFiles:
            !fileExists(for: capture, fileManager: fileManager)
        }
    }

    private static func matchesDateFilter(
        _ capture: Capture,
        dateFilter: CaptureHistoryDateFilter,
        calendar: Calendar,
        referenceDate: Date
    ) -> Bool {
        guard let dateRange = dateRange(for: dateFilter, calendar: calendar, referenceDate: referenceDate) else {
            return dateFilter == .all
        }

        return dateRange.contains(capture.createdAt)
    }

    private static func dateRange(
        for dateFilter: CaptureHistoryDateFilter,
        calendar: Calendar,
        referenceDate: Date
    ) -> Range<Date>? {
        let referenceDay = calendar.startOfDay(for: referenceDate)
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: referenceDay)

        switch dateFilter {
        case .all:
            return nil
        case .today:
            guard let tomorrow else {
                return nil
            }

            return referenceDay..<tomorrow
        case .yesterday:
            guard let yesterday = calendar.date(byAdding: .day, value: -1, to: referenceDay) else {
                return nil
            }

            return yesterday..<referenceDay
        case .last7Days:
            guard let startDate = calendar.date(byAdding: .day, value: -6, to: referenceDay),
                  let tomorrow else {
                return nil
            }

            return startDate..<tomorrow
        case .last30Days:
            guard let startDate = calendar.date(byAdding: .day, value: -29, to: referenceDay),
                  let tomorrow else {
                return nil
            }

            return startDate..<tomorrow
        }
    }

    private static func isEditedCapture(_ capture: Capture) -> Bool {
        if capture.editedFilePath != nil || capture.captureMode == "edited" {
            return true
        }

        return filePaths(for: capture).contains { filePath in
            URL(fileURLWithPath: filePath)
                .deletingPathExtension()
                .lastPathComponent
                .contains("-edited-")
        }
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

    private static func lastKnownFilePaths(for capture: Capture) -> [String] {
        var filePaths = [contentFilePath(for: capture)]

        for filePath in [capture.originalFilePath, capture.editedFilePath].compactMap({ $0 }) {
            if !filePaths.contains(filePath) {
                filePaths.append(filePath)
            }
        }

        return filePaths
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

    private static func canonicalFileURL(_ fileURL: URL) -> URL {
        fileURL.resolvingSymlinksInPath()
    }
}
