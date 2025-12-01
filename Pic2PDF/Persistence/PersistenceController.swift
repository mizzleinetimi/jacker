//
//  PersistenceController.swift
//  Pic2PDF
//
//  Central SwiftData stack so every manager talks to the same store.
//

import Foundation
import SwiftData

@MainActor
final class PersistenceController {
    static let shared = PersistenceController()
    
    let container: ModelContainer
    
    private init() {
        let schema = Schema([
            Generation.self,
            RefinementEntry.self,
            Document.self,
            Card.self,
            FlashcardDeck.self,
            Flashcard.self
        ])
        
        do {
            let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
            container = try ModelContainer(for: schema, configurations: [configuration])
            NSLog("[Persistence] Shared container ready")
        } catch {
            fatalError("[Persistence] Failed to create ModelContainer: \(error)")
        }
    }
    
    func makeContext() -> ModelContext {
        ModelContext(container)
    }
}

