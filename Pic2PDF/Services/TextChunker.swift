//
//  TextChunker.swift
//  Pic2PDF
//
//  Splits text into digestible chunks for card-based reading
//

import Foundation

/// Splits text into readable chunks suitable for cards
class TextChunker {
    static let shared = TextChunker()
    
    /// Target size for each chunk (in characters)
    private let targetChunkSize = 500
    /// Maximum chunk size before forcing a split
    private let maxChunkSize = 800
    /// Minimum chunk size (avoid tiny cards)
    private let minChunkSize = 100
    
    private init() {}
    
    /// Split text into chunks, trying to break at natural boundaries
    func chunkText(_ text: String) -> [String] {
        let cleanedText = text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        
        guard !cleanedText.isEmpty else { return [] }
        
        // If text is short enough, return as single chunk
        if cleanedText.count <= maxChunkSize {
            return [cleanedText]
        }
        
        var chunks: [String] = []
        var currentChunk = ""
        
        // Split by paragraphs first
        let paragraphs = cleanedText.components(separatedBy: "\n\n")
        
        for paragraph in paragraphs {
            let trimmedParagraph = paragraph.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmedParagraph.isEmpty else { continue }
            
            // If paragraph itself is too long, split it further
            if trimmedParagraph.count > maxChunkSize {
                // Save current chunk if not empty
                if !currentChunk.isEmpty {
                    chunks.append(currentChunk.trimmingCharacters(in: .whitespacesAndNewlines))
                    currentChunk = ""
                }
                // Split long paragraph by sentences
                let sentenceChunks = splitBySentences(trimmedParagraph)
                chunks.append(contentsOf: sentenceChunks)
                continue
            }
            
            // Check if adding this paragraph exceeds target
            let potentialChunk = currentChunk.isEmpty ? trimmedParagraph : currentChunk + "\n\n" + trimmedParagraph
            
            if potentialChunk.count > targetChunkSize && !currentChunk.isEmpty {
                // Save current chunk and start new one
                chunks.append(currentChunk.trimmingCharacters(in: .whitespacesAndNewlines))
                currentChunk = trimmedParagraph
            } else {
                currentChunk = potentialChunk
            }
        }
        
        // Don't forget the last chunk
        if !currentChunk.isEmpty {
            let trimmed = currentChunk.trimmingCharacters(in: .whitespacesAndNewlines)
            // If last chunk is too small, merge with previous
            if trimmed.count < minChunkSize && !chunks.isEmpty {
                let lastChunk = chunks.removeLast()
                chunks.append(lastChunk + "\n\n" + trimmed)
            } else {
                chunks.append(trimmed)
            }
        }
        
        return chunks
    }
    
    /// Split a long paragraph by sentences
    private func splitBySentences(_ text: String) -> [String] {
        var chunks: [String] = []
        var currentChunk = ""
        
        // Simple sentence splitting (handles . ! ?)
        let sentencePattern = #"[^.!?]+[.!?]+"#
        let regex = try? NSRegularExpression(pattern: sentencePattern, options: [])
        let range = NSRange(text.startIndex..., in: text)
        
        var sentences: [String] = []
        regex?.enumerateMatches(in: text, options: [], range: range) { match, _, _ in
            if let matchRange = match?.range, let swiftRange = Range(matchRange, in: text) {
                sentences.append(String(text[swiftRange]).trimmingCharacters(in: .whitespaces))
            }
        }
        
        // If no sentences found, fall back to word-based splitting
        if sentences.isEmpty {
            return splitByWords(text)
        }
        
        for sentence in sentences {
            let potentialChunk = currentChunk.isEmpty ? sentence : currentChunk + " " + sentence
            
            if potentialChunk.count > targetChunkSize && !currentChunk.isEmpty {
                chunks.append(currentChunk)
                currentChunk = sentence
            } else {
                currentChunk = potentialChunk
            }
        }
        
        if !currentChunk.isEmpty {
            chunks.append(currentChunk)
        }
        
        return chunks
    }
    
    /// Last resort: split by words
    private func splitByWords(_ text: String) -> [String] {
        var chunks: [String] = []
        var currentChunk = ""
        
        let words = text.split(separator: " ")
        
        for word in words {
            let potentialChunk = currentChunk.isEmpty ? String(word) : currentChunk + " " + word
            
            if potentialChunk.count > targetChunkSize && !currentChunk.isEmpty {
                chunks.append(currentChunk)
                currentChunk = String(word)
            } else {
                currentChunk = potentialChunk
            }
        }
        
        if !currentChunk.isEmpty {
            chunks.append(currentChunk)
        }
        
        return chunks
    }
    
    /// Chunk multiple page texts, keeping track of page numbers
    func chunkPages(_ pageTexts: [String]) -> [(text: String, pageNumber: Int)] {
        var allChunks: [(text: String, pageNumber: Int)] = []
        
        for (pageIndex, pageText) in pageTexts.enumerated() {
            let chunks = chunkText(pageText)
            for chunk in chunks {
                allChunks.append((text: chunk, pageNumber: pageIndex + 1))
            }
        }
        
        return allChunks
    }
}
