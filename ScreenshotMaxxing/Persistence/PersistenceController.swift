//
//  PersistenceController.swift
//  ScreenshotMaxxing
//
//  Created by Ben Kramer on 5/26/26.
//

import SwiftData

@MainActor
enum PersistenceController {
    static let sharedModelContainer: ModelContainer = {
        do {
            return try makeModelContainer()
        } catch {
            fatalError("Unable to create SwiftData model container: \(error)")
        }
    }()

    static func makeModelContainer(inMemory: Bool = false) throws -> ModelContainer {
        let schema = Schema([Capture.self])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: inMemory)
        return try ModelContainer(for: schema, configurations: [configuration])
    }
}
