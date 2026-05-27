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
                .font(.system(size: 48))
                .symbolRenderingMode(.hierarchical)

            Text("ScreenshotMaxxing")
                .font(.title)
                .fontWeight(.semibold)

            Text("Screenshot capture tools are coming next.")
                .foregroundStyle(.secondary)
        }
        .frame(minWidth: 420, minHeight: 260)
    }
}

#Preview {
    ContentView()
}
