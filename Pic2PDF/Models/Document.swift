//
//  Document.swift
//  Pic2PDF
//
//  Document and Card models for the reading assistant
//

import Foundation
import SwiftData
import UIKit

/// Represents an imported document (PDF or collection of images)
@Model
final class Document {
    var id: UUID
    var title: String
    var createdAt: Date
    var lastReadAt: Date?
    var lastReadCardIndex: Int
    var sourceType: String // "pdf" or "images"
    var totalCards: Int
    var processedCards: Int
    
    // Store PDF data or image references
    var pdfData: Data?
    var imageDataArray: [Data]
    
    @Relationship(deleteRule: .cascade)
    var cards: [Card]
    
    init(
        id: UUID = UUID(),
        title: String,
        sourceType: String,
        pdfData: Data? = nil,
        imageDataArray: [Data] = []
    ) {
        self.id = id
        self.title = title
        self.createdAt = Date()
        self.lastReadAt = nil
        self.lastReadCardIndex = 0
        self.sourceType = sourceType
        self.totalCards = 0
        self.processedCards = 0
        self.pdfData = pdfData
        self.imageDataArray = imageDataArray
        self.cards = []
    }
    
    var progress: Double {
        guard totalCards > 0 else { return 0 }
        return Double(lastReadCardIndex + 1) / Double(totalCards)
    }
    
    var isFullyProcessed: Bool {
        return processedCards >= totalCards && totalCards > 0
    }
}

/// Processing status for a card
enum CardStatus: String, Codable {
    case raw        // Text extracted, not simplified yet
    case processing // Currently being simplified
    case ready      // Simplified and ready to read
    case failed     // Simplification failed
}

/// Represents a single reading card (chunk of content)
@Model
final class Card {
    var id: UUID
    var index: Int  // Position in the document
    var originalText: String
    var simplifiedText: String?
    var keyTakeaways: [String]
    var statusRaw: String  // Store as string for SwiftData
    var sourceImageData: Data?  // Original image if from photo
    var pageNumber: Int?  // PDF page number if applicable
    
    var status: CardStatus {
        get { CardStatus(rawValue: statusRaw) ?? .raw }
        set { statusRaw = newValue.rawValue }
    }
    
    init(
        id: UUID = UUID(),
        index: Int,
        originalText: String,
        sourceImageData: Data? = nil,
        pageNumber: Int? = nil
    ) {
        self.id = id
        self.index = index
        self.originalText = originalText
        self.simplifiedText = nil
        self.keyTakeaways = []
        self.statusRaw = CardStatus.raw.rawValue
        self.sourceImageData = sourceImageData
        self.pageNumber = pageNumber
    }
    
    var isReady: Bool {
        return status == .ready && simplifiedText != nil
    }
}
