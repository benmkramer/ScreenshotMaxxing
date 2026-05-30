//
//  EditorClipboard.swift
//  ScreenshotMaxxing
//
//  Created by Ben Kramer on 5/26/26.
//

import AppKit
import Foundation
import UniformTypeIdentifiers

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

    static func copyString(_ string: String, to pasteboard: NSPasteboard = .general) -> Bool {
        pasteboard.clearContents()

        return pasteboard.setString(string, forType: .string)
    }

    static func copyMP4Data(_ mp4Data: Data, to pasteboard: NSPasteboard = .general) -> Bool {
        pasteboard.clearContents()

        let wroteMP4 = pasteboard.setData(mp4Data, forType: NSPasteboard.PasteboardType(UTType.mpeg4Movie.identifier))
        let wroteMovie = pasteboard.setData(mp4Data, forType: NSPasteboard.PasteboardType(UTType.movie.identifier))

        return wroteMP4 || wroteMovie
    }
}
