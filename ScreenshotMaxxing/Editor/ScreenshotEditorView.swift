//
//  ScreenshotEditorView.swift
//  ScreenshotMaxxing
//
//  Created by Ben Kramer on 5/26/26.
//

import SwiftUI

struct ScreenshotEditorView: View {
    let imageURL: URL

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "photo")
                .font(.system(size: 40, weight: .medium))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.secondary)

            Text(imageURL.lastPathComponent)
                .font(.headline)
                .lineLimit(1)

            Text("Editor tools are coming next.")
                .foregroundStyle(.secondary)
        }
        .padding(32)
        .frame(minWidth: 640, minHeight: 420)
    }
}

#Preview {
    ScreenshotEditorView(imageURL: URL(fileURLWithPath: "/tmp/capture.png"))
}
