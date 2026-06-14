//
//  SavedFilePresenter.swift
//  ScreenshotMaxxing
//
//  Created by Codex on 5/30/26.
//

import AppKit
import Foundation

struct SavedFilePresenter {
    private let revealFile: @MainActor (URL) -> Void

    init(
        revealFile: @escaping @MainActor (URL) -> Void = { fileURL in
            NSWorkspace.shared.activateFileViewerSelecting([fileURL])
        }
    ) {
        self.revealFile = revealFile
    }

    @MainActor
    func revealInFinder(_ fileURL: URL) {
        revealFile(fileURL)
    }
}
