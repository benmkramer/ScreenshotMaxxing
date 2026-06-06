//
//  CaptureHistoryView.swift
//  ScreenshotMaxxing
//
//  Created by Ben Kramer on 5/26/26.
//

import SwiftData
import SwiftUI

struct CaptureHistoryView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Capture.createdAt, order: .reverse) private var captures: [Capture]
    private let fileManager: FileManager
    private let openCapture: (Capture) -> Void
    @State private var searchText = ""
    @State private var selectedCaptureIDs = Set<UUID>()
    @State private var pendingDeletionIDs = Set<UUID>()
    @State private var showingDeleteConfirmation = false
    @State private var deleteErrorMessage: String?

    init(fileManager: FileManager = .default, openCapture: @escaping (Capture) -> Void = { _ in }) {
        self.fileManager = fileManager
        self.openCapture = openCapture
    }

    var body: some View {
        Group {
            if captures.isEmpty {
                emptyState
            } else {
                VStack(spacing: 0) {
                    historyControls

                    if filteredCaptures.isEmpty {
                        noResultsState
                    } else {
                        historyList
                    }
                }
            }
        }
        .frame(minWidth: 520, minHeight: 420)
        .navigationTitle("History")
        .confirmationDialog(
            "Delete selected captures?",
            isPresented: $showingDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button(deleteConfirmationButtonTitle, role: .destructive) {
                deletePendingCaptures()
            }

            Button("Cancel", role: .cancel) {
                pendingDeletionIDs.removeAll()
            }
        } message: {
            Text(CaptureHistoryData.deleteConfirmationMessage)
        }
        .alert(
            "Could not delete captures",
            isPresented: Binding(
                get: { deleteErrorMessage != nil },
                set: { isPresented in
                    if !isPresented {
                        deleteErrorMessage = nil
                    }
                }
            )
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(deleteErrorMessage ?? "")
        }
    }

    private var filteredCaptures: [Capture] {
        CaptureHistoryData.filteredCaptures(captures, searchText: searchText)
    }

    private var historyControls: some View {
        HStack(spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)

                TextField("Search by date, file, or type", text: $searchText)
                    .textFieldStyle(.plain)
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 7)
            .background {
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color(nsColor: .textBackgroundColor))
            }
            .overlay {
                RoundedRectangle(cornerRadius: 6)
                    .stroke(Color(nsColor: .separatorColor))
            }

            Button {
                toggleFilteredSelection()
            } label: {
                Label(selectAllButtonTitle, systemImage: selectAllSystemImage)
            }
            .disabled(filteredCaptures.isEmpty)

            Button(role: .destructive) {
                requestDelete(selectedCaptureIDs)
            } label: {
                Label(deleteButtonTitle, systemImage: "trash")
            }
            .disabled(selectedCaptureIDs.isEmpty)
        }
        .padding(16)
    }

    private var historyList: some View {
        List(filteredCaptures) { capture in
            let fileExists = CaptureHistoryData.fileExists(for: capture, fileManager: fileManager)

            HStack(spacing: 10) {
                Toggle(isOn: selectionBinding(for: capture)) {
                    EmptyView()
                }
                .labelsHidden()
                .toggleStyle(.checkbox)
                .accessibilityLabel("Select \(capture.fileName)")

                Button {
                    openCapture(capture)
                } label: {
                    CaptureHistoryRow(capture: capture, fileExists: fileExists)
                }
                .buttonStyle(.plain)
                .disabled(!fileExists)
            }
            .contextMenu {
                Button(role: .destructive) {
                    requestDelete([capture.id])
                } label: {
                    Label("Delete", systemImage: "trash")
                }
            }
            .listRowSeparator(.visible)
        }
        .listStyle(.inset)
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "clock.arrow.circlepath")
                .font(.system(size: 40, weight: .medium))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.secondary)

            Text("No captures yet")
                .font(.headline)

            Text("Capture an area, window, or full screen from the menu bar. Recent screenshots stay local on this Mac.")
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(32)
    }

    private var noResultsState: some View {
        VStack(spacing: 12) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 34, weight: .medium))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.secondary)

            Text("No matching captures")
                .font(.headline)

            Text("Try another file name, capture type, or date.")
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(32)
    }

    private var selectedFilteredCaptureIDs: Set<UUID> {
        Set(filteredCaptures.map(\.id))
    }

    private var allFilteredCapturesSelected: Bool {
        !selectedFilteredCaptureIDs.isEmpty && selectedFilteredCaptureIDs.isSubset(of: selectedCaptureIDs)
    }

    private var selectAllButtonTitle: String {
        allFilteredCapturesSelected ? "Deselect All" : "Select All"
    }

    private var selectAllSystemImage: String {
        allFilteredCapturesSelected ? "xmark.circle" : "checkmark.circle"
    }

    private var deleteButtonTitle: String {
        selectedCaptureIDs.isEmpty ? "Delete" : "Delete \(selectedCaptureIDs.count)"
    }

    private var deleteConfirmationButtonTitle: String {
        pendingDeletionIDs.count == 1 ? "Delete Capture" : "Delete \(pendingDeletionIDs.count) Captures"
    }

    private func selectionBinding(for capture: Capture) -> Binding<Bool> {
        Binding {
            selectedCaptureIDs.contains(capture.id)
        } set: { isSelected in
            if isSelected {
                selectedCaptureIDs.insert(capture.id)
            } else {
                selectedCaptureIDs.remove(capture.id)
            }
        }
    }

    private func toggleFilteredSelection() {
        if allFilteredCapturesSelected {
            selectedCaptureIDs.subtract(selectedFilteredCaptureIDs)
        } else {
            selectedCaptureIDs.formUnion(selectedFilteredCaptureIDs)
        }
    }

    private func requestDelete(_ captureIDs: Set<UUID>) {
        pendingDeletionIDs = captureIDs
        showingDeleteConfirmation = !captureIDs.isEmpty
    }

    private func deletePendingCaptures() {
        let capturesToDelete = CaptureHistoryData.capturesToDelete(
            from: captures,
            selectedIDs: pendingDeletionIDs
        )

        do {
            try CaptureHistoryData.deleteCaptures(
                capturesToDelete,
                from: modelContext,
                allCaptures: captures,
                fileManager: fileManager
            )
            selectedCaptureIDs.subtract(Set(capturesToDelete.map(\.id)))
            pendingDeletionIDs.removeAll()
        } catch {
            deleteErrorMessage = error.localizedDescription
        }
    }
}

private struct CaptureHistoryRow: View {
    let capture: Capture
    let fileExists: Bool

    var body: some View {
        HStack(spacing: 12) {
            CapturePreviewView(capture: capture, fileExists: fileExists)

            VStack(alignment: .leading, spacing: 4) {
                Text(capture.fileName)
                    .font(.headline)
                    .lineLimit(1)

                Text(CaptureHistoryData.detailText(for: capture))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                Text(capture.createdAt, format: .dateTime.month().day().hour().minute())
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }

            Spacer(minLength: 12)

            if !fileExists {
                Label("File missing", systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 6)
    }
}

private struct CapturePreviewView: View {
    let capture: Capture
    let fileExists: Bool

    private var image: NSImage? {
        guard fileExists else {
            return nil
        }

        return NSImage(contentsOfFile: CaptureHistoryData.previewFilePath(for: capture))
    }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 6)
                .fill(Color(nsColor: .underPageBackgroundColor))

            if let image {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 72, height: 52)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .overlay(alignment: .bottomTrailing) {
                        if CaptureHistoryData.mediaType(for: capture) == .video {
                            Image(systemName: "play.fill")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundStyle(.white)
                                .padding(5)
                                .background(.black.opacity(0.58), in: Circle())
                                .padding(4)
                        }
                    }
            } else {
                Image(systemName: placeholderSymbolName)
                    .font(.system(size: 22, weight: .medium))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: 72, height: 52)
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    private var placeholderSymbolName: String {
        if !fileExists {
            return "questionmark.folder"
        }

        return CaptureHistoryData.mediaType(for: capture) == .video ? "play.rectangle" : "photo"
    }
}

#Preview {
    CaptureHistoryView()
        .modelContainer(try! PersistenceController.makeModelContainer(inMemory: true))
}
