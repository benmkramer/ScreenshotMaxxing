//
//  CaptureHistoryView.swift
//  ScreenshotMaxxing
//
//  Created by Ben Kramer on 5/26/26.
//

import SwiftData
import SwiftUI

struct CaptureHistoryView: View {
    @Query(sort: \Capture.createdAt, order: .reverse) private var captures: [Capture]
    private let fileManager: FileManager

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    var body: some View {
        Group {
            if captures.isEmpty {
                emptyState
            } else {
                List(captures) { capture in
                    CaptureHistoryRow(
                        capture: capture,
                        fileExists: CaptureHistoryData.fileExists(for: capture, fileManager: fileManager)
                    )
                    .listRowSeparator(.visible)
                }
                .listStyle(.inset)
            }
        }
        .frame(minWidth: 520, minHeight: 420)
        .navigationTitle("History")
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "clock.arrow.circlepath")
                .font(.system(size: 40, weight: .medium))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.secondary)

            Text("No captures yet")
                .font(.headline)

            Text("Captured screenshots will appear here.")
                .foregroundStyle(.secondary)
        }
        .padding(32)
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
                Label("Missing", systemImage: "exclamationmark.triangle")
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
            } else {
                Image(systemName: fileExists ? "photo" : "questionmark.folder")
                    .font(.system(size: 22, weight: .medium))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: 72, height: 52)
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }
}

#Preview {
    CaptureHistoryView()
        .modelContainer(try! PersistenceController.makeModelContainer(inMemory: true))
}
