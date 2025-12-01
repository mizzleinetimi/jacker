//
//  FlashcardManager.swift
//  Pic2PDF
//
//  Manages flashcard decks and review sessions
//

import Foundation
import SwiftData
import Combine
import UniformTypeIdentifiers

@MainActor
class FlashcardManager: ObservableObject {
    static let shared = FlashcardManager()
    
    @Published var decks: [FlashcardDeck] = []
    @Published var isImporting = false
    
    private let persistence = PersistenceController.shared
    let modelContext: ModelContext
    
    var totalDueCards: Int {
        decks.reduce(0) { $0 + $1.dueCards }
    }
    
    private init() {
        self.modelContext = persistence.makeContext()
        loadDecks()
    }
    
    func loadDecks() {
        let descriptor = FetchDescriptor<FlashcardDeck>(
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        )
        
        do {
            decks = try modelContext.fetch(descriptor)
        } catch {
            print("[FlashcardManager] Failed to load decks: \(error)")
        }
    }
    
    // MARK: - Deck Management
    
    func createDeck(name: String, description: String = "") -> FlashcardDeck {
        let deck = FlashcardDeck(name: name, description: description)
        modelContext.insert(deck)
        try? modelContext.save()
        loadDecks()
        return deck
    }
    
    func deleteDeck(_ deck: FlashcardDeck) {
        modelContext.delete(deck)
        try? modelContext.save()
        loadDecks()
    }
    
    // MARK: - Card Management
    
    func addCard(to deck: FlashcardDeck, front: String, back: String) {
        let card = Flashcard(front: front, back: back)
        deck.cards.append(card)
        try? modelContext.save()
    }
    
    func deleteCard(_ card: Flashcard, from deck: FlashcardDeck) {
        if let index = deck.cards.firstIndex(where: { $0.id == card.id }) {
            deck.cards.remove(at: index)
            modelContext.delete(card)
            try? modelContext.save()
        }
    }
    
    func saveChanges() {
        try? modelContext.save()
    }
    
    // MARK: - Import
    
    func importCSV(data: Data, deckName: String) throws -> FlashcardDeck {
        guard let content = String(data: data, encoding: .utf8) else {
            throw ImportError.invalidFormat
        }
        
        let lines = content.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        
        guard !lines.isEmpty else {
            throw ImportError.emptyFile
        }
        
        let deck = FlashcardDeck(name: deckName)
        
        for line in lines {
            // Support both comma and tab separated
            let parts: [String]
            if line.contains("\t") {
                parts = line.components(separatedBy: "\t")
            } else {
                parts = parseCSVLine(line)
            }
            
            guard parts.count >= 2 else { continue }
            
            let front = parts[0].trimmingCharacters(in: .whitespaces)
            let back = parts[1].trimmingCharacters(in: .whitespaces)
            
            guard !front.isEmpty && !back.isEmpty else { continue }
            
            let card = Flashcard(front: front, back: back)
            deck.cards.append(card)
        }
        
        guard !deck.cards.isEmpty else {
            throw ImportError.noValidCards
        }
        
        modelContext.insert(deck)
        try? modelContext.save()
        loadDecks()
        
        return deck
    }
    
    private func parseCSVLine(_ line: String) -> [String] {
        var result: [String] = []
        var current = ""
        var inQuotes = false
        
        for char in line {
            if char == "\"" {
                inQuotes.toggle()
            } else if char == "," && !inQuotes {
                result.append(current)
                current = ""
            } else {
                current.append(char)
            }
        }
        result.append(current)
        
        return result.map { $0.trimmingCharacters(in: CharacterSet(charactersIn: "\"")) }
    }
    
    func importJSON(data: Data, deckName: String) throws -> FlashcardDeck {
        struct JSONCard: Codable {
            let front: String
            let back: String
        }
        
        struct JSONDeck: Codable {
            let name: String?
            let cards: [JSONCard]
        }
        
        // Try array of cards first
        if let cards = try? JSONDecoder().decode([JSONCard].self, from: data) {
            let deck = FlashcardDeck(name: deckName)
            for jsonCard in cards {
                let card = Flashcard(front: jsonCard.front, back: jsonCard.back)
                deck.cards.append(card)
            }
            modelContext.insert(deck)
            try? modelContext.save()
            loadDecks()
            return deck
        }
        
        // Try deck object
        if let jsonDeck = try? JSONDecoder().decode(JSONDeck.self, from: data) {
            let deck = FlashcardDeck(name: jsonDeck.name ?? deckName)
            for jsonCard in jsonDeck.cards {
                let card = Flashcard(front: jsonCard.front, back: jsonCard.back)
                deck.cards.append(card)
            }
            modelContext.insert(deck)
            try? modelContext.save()
            loadDecks()
            return deck
        }
        
        throw ImportError.invalidFormat
    }
    
    // MARK: - Review Session
    
    func getDueCards(for deck: FlashcardDeck) -> [Flashcard] {
        deck.cards.filter { $0.isDue }.sorted { $0.dueDate < $1.dueDate }
    }
}

enum ImportError: LocalizedError {
    case invalidFormat
    case emptyFile
    case noValidCards
    
    var errorDescription: String? {
        switch self {
        case .invalidFormat:
            return "Could not read the file format. Please use CSV or JSON."
        case .emptyFile:
            return "The file appears to be empty."
        case .noValidCards:
            return "No valid flashcards found. Each card needs a front and back."
        }
    }
}
