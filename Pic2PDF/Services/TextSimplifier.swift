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
        Rewrite the passage using simpler words. Keep it the same length or shorter.
        RULES:
        - Output ONLY the rewritten text (no explanations, no introductions, no bullet labels).
        - Do NOT start with phrases like "Here's an alternative" or "Simplified version".
        - Do NOT wrap the answer in quotes or markdown code fences.

        \(text)
        <end_of_turn>
        <start_of_turn>model
        """
    }
    
    private func parseSimplificationResponse(_ response: String, originalText: String) -> (simplified: String, takeaways: [String]) {
        var simplified = response.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Trim wrapping quotes or leading bullet characters
        simplified = simplified.trimmingCharacters(in: CharacterSet(charactersIn: "\"“”' "))
        
        // Strip common LLM preambles using regex (handles bullets + punctuation)
        let preamblePattern = #"^\s*(?:[-–—•*]\s*)?(?:here(?:'s| is)\s+(?:an|a|the)\s+(?:alternative|simpler version|rewritten(?: text)?|summary)|simplified version|rewritten|alternative)\s*:?\s*"#
        if let range = simplified.range(of: preamblePattern, options: [.regularExpression, .caseInsensitive]) {
            simplified.removeSubrange(range)
            simplified = simplified.trimmingCharacters(in: CharacterSet(charactersIn: "\"“”' ").union(.whitespacesAndNewlines))
        }
        
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
