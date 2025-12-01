//
//  Flashcard.swift
//  Pic2PDF
//
//  Flashcard and Deck models with SM-2 spaced repetition
//

import Foundation
import SwiftData

@Model
final class FlashcardDeck {
    var id: UUID = UUID()
    var name: String = ""
    var deckDescription: String = ""
    var createdAt: Date = Date()
    
    @Relationship(deleteRule: .cascade)
    var cards: [Flashcard] = []
    
    var totalCards: Int { cards.count }
    
    var dueCards: Int {
        cards.filter { $0.isDue }.count
    }
    
    var averageEase: Double {
        guard !cards.isEmpty else { return 2.5 }
        return cards.reduce(0) { $0 + $1.easeFactor } / Double(cards.count)
    }
    
    init(name: String, description: String = "") {
        self.name = name
        self.deckDescription = description
    }
}

@Model
final class Flashcard {
    var id: UUID = UUID()
    var front: String = ""
    var back: String = ""
    
    // SM-2 algorithm fields
    var intervalDays: Int = 0
    var easeFactor: Double = 2.5
    var repetitions: Int = 0
    var dueDate: Date = Date()
    
    // Stats
    var totalReviews: Int = 0
    var correctReviews: Int = 0
    var lastReviewedAt: Date?
    
    var isDue: Bool {
        dueDate <= Date()
    }
    
    var successRate: Double {
        guard totalReviews > 0 else { return 0 }
        return Double(correctReviews) / Double(totalReviews)
    }
    
    init(front: String, back: String) {
        self.front = front
        self.back = back
        self.dueDate = Date()
    }
}

// MARK: - SM-2 Algorithm

enum ReviewVerdict: String, Codable {
    case again = "again"
    case hard = "hard"
    case good = "good"
    case easy = "easy"
    
    var score: Int {
        switch self {
        case .again: return 0
        case .hard: return 2
        case .good: return 3
        case .easy: return 5
        }
    }
    
    var color: String {
        switch self {
        case .again: return "red"
        case .hard: return "orange"
        case .good: return "green"
        case .easy: return "blue"
        }
    }
    
    var emoji: String {
        switch self {
        case .again: return "🔴"
        case .hard: return "🟠"
        case .good: return "🟢"
        case .easy: return "🔵"
        }
    }
}

struct GradeResult: Codable {
    let score: Int
    let verdict: String
    let feedback: String
    
    var reviewVerdict: ReviewVerdict {
        ReviewVerdict(rawValue: verdict.lowercased()) ?? .hard
    }
}

extension Flashcard {
    /// Apply SM-2 algorithm based on review quality
    func applyReview(verdict: ReviewVerdict) {
        let quality = verdict.score
        totalReviews += 1
        lastReviewedAt = Date()
        
        if quality >= 3 {
            correctReviews += 1
        }
        
        // SM-2 Algorithm
        if quality < 3 {
            // Failed - reset
            repetitions = 0
            intervalDays = 1
        } else {
            // Passed
            if repetitions == 0 {
                intervalDays = 1
            } else if repetitions == 1 {
                intervalDays = 6
            } else {
                intervalDays = Int(Double(intervalDays) * easeFactor)
            }
            repetitions += 1
        }
        
        // Update ease factor
        let newEase = easeFactor + (0.1 - Double(5 - quality) * (0.08 + Double(5 - quality) * 0.02))
        easeFactor = max(1.3, newEase)
        
        // Set next due date
        dueDate = Calendar.current.date(byAdding: .day, value: intervalDays, to: Date()) ?? Date()
    }
}
