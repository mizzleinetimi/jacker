//
//  DocumentManager.swift
//  Pic2PDF
//
//  Manages document import, processing, and storage
//

import Foundation
import SwiftData
import UIKit
import PDFKit
import Combine

/// Manages the document lifecycle
@MainActor
class DocumentManager: ObservableObject {
    static let shared = DocumentManager()
    
    @Published var documents: [Document] = []
    @Published var isProcessing = false
    @Published var processingProgress: Double = 0
    @Published var processingStatus: String = ""
    
    private let textExtractor = TextExtractor.shared
    private let chunker = TextChunker.shared
    private let simplifier = TextSimplifier.shared
    
    private let persistence = PersistenceController.shared
    let modelContext: ModelContext
    
    private init() {
        self.modelContext = persistence.makeContext()
        loadDocuments()
    }
    
    // MARK: - Document Loading
    
    func loadDocuments() {
        let descriptor = FetchDescriptor<Document>(
            sortBy: [SortDescriptor(\.lastReadAt, order: .reverse), SortDescriptor(\.createdAt, order: .reverse)]
        )
        
        do {
            documents = try modelContext.fetch(descriptor)
        } catch {
            print("[DocumentManager] Failed to load documents: \(error)")
        }
    }
    
    // MARK: - Import PDF
    
    func importPDF(data: Data, title: String) async throws -> Document {
        isProcessing = true
        processingStatus = "Extracting text from PDF..."
        processingProgress = 0.1
        
        defer {
            isProcessing = false
            processingProgress = 0
            processingStatus = ""
        }
        
        // Extract text from PDF
        let pageTexts = try await textExtractor.extractTextFromPDF(data)
        
        processingStatus = "Creating reading cards..."
        processingProgress = 0.4
        
        // Chunk the text
        let chunks = chunker.chunkPages(pageTexts)
        
        // Create document
        let document = Document(
            title: title,
            sourceType: "pdf",
            pdfData: data
        )
        document.totalCards = chunks.count
        
        // Create cards
        for (index, chunk) in chunks.enumerated() {
            let card = Card(
                index: index,
                originalText: chunk.text,
                pageNumber: chunk.pageNumber
            )
            document.cards.append(card)
        }
        
        processingProgress = 0.8
        
        // Save to storage
        modelContext.insert(document)
        try modelContext.save()
        
        processingProgress = 1.0
        loadDocuments()
        
        return document
    }
    
    // MARK: - Import Images
    
    func importImages(_ images: [UIImage], title: String) async throws -> Document {
        isProcessing = true
        processingStatus = "Reading text from images..."
        processingProgress = 0.1
        
        defer {
            isProcessing = false
            processingProgress = 0
            processingStatus = ""
        }
        
        var allChunks: [(text: String, imageData: Data?)] = []
        
        // Process each image
        for (index, image) in images.enumerated() {
            processingProgress = 0.1 + (0.5 * Double(index) / Double(images.count))
            processingStatus = "Reading image \(index + 1) of \(images.count)..."
            
            do {
                let text = try await textExtractor.extractTextFromImage(image)
                let chunks = chunker.chunkText(text)
                let imageData = image.jpegData(compressionQuality: 0.7)
                
                for chunk in chunks {
                    allChunks.append((text: chunk, imageData: imageData))
                }
            } catch TextExtractionError.noTextFound {
                // Skip images with no text
                continue
            }
        }
        
        guard !allChunks.isEmpty else {
            throw TextExtractionError.noTextFound
        }
        
        processingStatus = "Creating reading cards..."
        processingProgress = 0.7
        
        // Create document
        let imageDataArray = images.compactMap { $0.jpegData(compressionQuality: 0.7) }
        let document = Document(
            title: title,
            sourceType: "images",
            imageDataArray: imageDataArray
        )
        document.totalCards = allChunks.count
        
        // Create cards
        for (index, chunk) in allChunks.enumerated() {
            let card = Card(
                index: index,
                originalText: chunk.text,
                sourceImageData: chunk.imageData
            )
            document.cards.append(card)
        }
        
        processingProgress = 0.9
        
        // Save to storage
        modelContext.insert(document)
        try modelContext.save()
        
        processingProgress = 1.0
        loadDocuments()
        
        return document
    }
    
    // MARK: - Card Simplification
    
    /// Simplify a card's text (called lazily when user views the card)
    func simplifyCard(_ card: Card) async {
        guard card.status == .raw else { return }
        
        card.status = .processing
        let originalText = card.originalText
        
        do {
            let result = try await Task.detached(priority: .userInitiated) {
                try await TextSimplifier.shared.simplify(originalText)
            }.value
            card.simplifiedText = result.simplified
            card.keyTakeaways = result.takeaways
            card.status = .ready
            try modelContext.save()
        } catch {
            print("[DocumentManager] Failed to simplify card: \(error)")
            card.status = .failed
        }
    }
    
    /// Pre-simplify the first few cards of a document
    func presimplifyCards(_ document: Document, count: Int = 3) async {
        let cardsToProcess = document.cards
            .sorted { $0.index < $1.index }
            .prefix(count)
            .filter { $0.status == .raw }
        
        for card in cardsToProcess {
            await simplifyCard(card)
            document.processedCards += 1
        }
    }
    
    // MARK: - Reading Progress
    
    func updateReadingProgress(_ document: Document, cardIndex: Int) {
        document.lastReadCardIndex = cardIndex
        document.lastReadAt = Date()
        try? modelContext.save()
    }
    
    // MARK: - Delete Document
    
    func deleteDocument(_ document: Document) {
        modelContext.delete(document)
        try? modelContext.save()
        loadDocuments()
    }
}
