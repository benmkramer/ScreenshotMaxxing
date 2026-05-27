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

            Text("Use the menu bar to capture screenshots.")
                .foregroundStyle(.secondary)
        }
        .frame(minWidth: 420, minHeight: 280)
    }
}

#Preview {
    ContentView()
}
