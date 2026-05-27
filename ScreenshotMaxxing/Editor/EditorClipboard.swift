//
//  EditorClipboard.swift
//  ScreenshotMaxxing
//
//  Created by Ben Kramer on 5/26/26.
//

import AppKit
import Foundation

@MainActor
enum EditorClipboard {
    static func copyPNGData(_ pngData: Data, to pasteboard: NSPasteboard = .general) -> Bool {
        pasteboard.clearContents()

        let wrotePNG = pasteboard.setData(pngData, forType: .png)
        let wroteTIFF: Bool

        if let image = NSImage(data: pngData), let tiffData = image.tiffRepresentation {
            wroteTIFF = pasteboard.setData(tiffData, forType: .tiff)
        } else {
            wroteTIFF = false
        }

        return wrotePNG || wroteTIFF
    }
}
