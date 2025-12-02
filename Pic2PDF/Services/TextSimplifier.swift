//
//  TextSimplifier.swift
//  Pic2PDF
//
//  Uses on-device Gemma to simplify text chunks
//

import Foundation

/// Simplifies text using on-device LLM
class TextSimplifier {
    static let shared = TextSimplifier()
    
    private let llmService = OnDeviceLLMService.shared
    
    private init() {}
    
    /// Simplify a text chunk and extract key takeaways
    func simplify(_ text: String) async throws -> (simplified: String, takeaways: [String]) {
        guard llmService.isInitialized else {
            throw SimplificationError.modelNotReady
        }
        
        let prompt = buildSimplificationPrompt(text)
        
        var result = ""
        result = try await llmService.generateChatResponse(prompt: prompt) { _ in }
        
        // Parse the response
        return parseSimplificationResponse(result, originalText: text)
    }
    
    private func buildSimplificationPrompt(_ text: String) -> String {
        return """
        <start_of_turn>user
        Rewrite the following text using simpler words and shorter sentences.
        
        CRITICAL RULES:
        1. Output ONLY the simplified text.
        2. Do NOT say "Sure", "Here is", "The text", or any intro.
        3. Do NOT use quotes or markdown.
        4. Just start writing the simplified text immediately.

        Text to simplify:
        \(text)
        <end_of_turn>
        <start_of_turn>model
        """
    }
    
    private func parseSimplificationResponse(_ response: String, originalText: String) -> (simplified: String, takeaways: [String]) {
        var simplified = response.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Log raw response for debugging
        NSLog("[TextSimplifier] Raw response: \(simplified.prefix(100))...")
        
        // Trim wrapping quotes
        simplified = simplified.trimmingCharacters(in: CharacterSet(charactersIn: "\"“”' "))
        
        // Aggressive preamble removal
        // Matches: "Sure!", "Okay,", "Here is the text:", "Simplified version:", etc.
        let preamblePattern = #"^\s*(?:Sure|Okay|Certainly|Here(?:'s| is)|The (?:simplified|rewritten)|Simplified|Rewritten).{0,50}[:\n]\s*"#
        
        if let range = simplified.range(of: preamblePattern, options: [.regularExpression, .caseInsensitive]) {
            simplified.removeSubrange(range)
        }
        
        simplified = simplified.trimmingCharacters(in: CharacterSet(charactersIn: "\"“”' ").union(.whitespacesAndNewlines))
        
        // If empty, return original
        if simplified.isEmpty {
            simplified = originalText
        }
        
        return (simplified, [])
    }
}

enum SimplificationError: LocalizedError {
    case modelNotReady
    case simplificationFailed(String)
    
    var errorDescription: String? {
        switch self {
        case .modelNotReady:
            return "AI model is not ready. Please wait for it to load."
        case .simplificationFailed(let reason):
            return "Failed to simplify text: \(reason)"
        }
    }
}
