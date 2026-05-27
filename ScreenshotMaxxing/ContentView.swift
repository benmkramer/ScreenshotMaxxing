//
//  ContentView.swift
//  ScreenshotMaxxing
//
//  Created by Ben Kramer on 5/26/26.
//

import SwiftUI

struct ContentView: View {
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "camera.viewfinder")
                .font(.system(size: 44, weight: .medium))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.secondary)

            Text("ScreenshotMaxxing")
                .font(.title2.weight(.semibold))

            Text("Use the menu bar or Command-Shift-4 to drag-select an area.")
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(32)
        .frame(minWidth: 420, minHeight: 280)
    }
}

#Preview {
    ContentView()
}
