//
//  TextExtractor.swift
//  Pic2PDF
//
//  Extracts text from PDFs and images using on-device OCR
//

import Foundation
import PDFKit
import Vision
import UIKit

/// Handles text extraction from PDFs and images
class TextExtractor {
    static let shared = TextExtractor()
    
    private init() {}
    
    // MARK: - PDF Text Extraction
    
    /// Extract text from PDF data, returning text per page
    func extractTextFromPDF(_ pdfData: Data) async throws -> [String] {
        guard let document = PDFDocument(data: pdfData) else {
            throw TextExtractionError.invalidPDF
        }
        
        var pageTexts: [String] = []
        
        for pageIndex in 0..<document.pageCount {
            guard let page = document.page(at: pageIndex) else { continue }
            let text = page.string ?? ""
            if !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                pageTexts.append(text)
            }
        }
        
        if pageTexts.isEmpty {
            throw TextExtractionError.noTextFound
        }
        
        return pageTexts
    }
    
    // MARK: - Image OCR
    
    /// Extract text from an image using Vision OCR
    func extractTextFromImage(_ image: UIImage) async throws -> String {
        guard let cgImage = image.cgImage else {
            throw TextExtractionError.invalidImage
        }
        
        return try await withCheckedThrowingContinuation { continuation in
            let request = VNRecognizeTextRequest { request, error in
                if let error = error {
                    continuation.resume(throwing: TextExtractionError.ocrFailed(error.localizedDescription))
                    return
                }
                
                guard let observations = request.results as? [VNRecognizedTextObservation] else {
                    continuation.resume(throwing: TextExtractionError.noTextFound)
                    return
                }
                
                let text = observations.compactMap { observation in
                    observation.topCandidates(1).first?.string
                }.joined(separator: "\n")
                
                if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    continuation.resume(throwing: TextExtractionError.noTextFound)
                } else {
                    continuation.resume(returning: text)
                }
            }
            
            // Configure for best accuracy
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true
            
            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
            
            do {
                try handler.perform([request])
            } catch {
                continuation.resume(throwing: TextExtractionError.ocrFailed(error.localizedDescription))
            }
        }
    }
    
    /// Extract text from multiple images
    func extractTextFromImages(_ images: [UIImage]) async throws -> [String] {
        var results: [String] = []
        
        for image in images {
            do {
                let text = try await extractTextFromImage(image)
                results.append(text)
            } catch TextExtractionError.noTextFound {
                // Skip images with no text
                continue
            }
        }
        
        if results.isEmpty {
            throw TextExtractionError.noTextFound
        }
        
        return results
    }
}

// MARK: - Errors

enum TextExtractionError: LocalizedError {
    case invalidPDF
    case invalidImage
    case noTextFound
    case ocrFailed(String)
    
    var errorDescription: String? {
        switch self {
        case .invalidPDF:
            return "Could not read the PDF file"
        case .invalidImage:
            return "Could not process the image"
        case .noTextFound:
            return "No readable text found in the document"
        case .ocrFailed(let reason):
            return "Text recognition failed: \(reason)"
        }
    }
}
