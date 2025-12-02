//
//  FlashcardGrader.swift
//  Pic2PDF
//
//  AI-powered semantic grading for flashcard answers
//

import Foundation

class FlashcardGrader {
    static let shared = FlashcardGrader()
    private let llmService = OnDeviceLLMService.shared

    private init() {}

    /// Grade a user's answer against the correct answer
    /// Uses LLM with simple YES/NO prompt, falls back to string similarity
    func grade(question: String, correctAnswer: String, userAnswer: String) async throws -> GradeResult {
        // Handle empty answer
        guard !userAnswer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            NSLog("[FlashcardGrader] Empty answer - returning 'again'")
            return GradeResult(score: 0, verdict: "again", feedback: "No answer provided.")
        }

        NSLog("[FlashcardGrader] ========== GRADING ==========")
        NSLog("[FlashcardGrader] Correct: \(correctAnswer.prefix(40))... | User: \(userAnswer.prefix(40))...")

        // Try LLM with simple prompt
        let prompt = buildSimplePrompt(correctAnswer: correctAnswer, userAnswer: userAnswer)

        do {
            let startTime = Date()
            let response = try await llmService.generateGradingResponse(prompt: prompt)
            let elapsed = Date().timeIntervalSince(startTime)

            NSLog("[FlashcardGrader] LLM (\(String(format: "%.1f", elapsed))s): '\(response.prefix(50))'")

            if let result = parseSimpleResponse(response) {
                NSLog("[FlashcardGrader] → \(result.verdict) (score \(result.score))")
                return result
            }
        } catch {
            NSLog("[FlashcardGrader] LLM error: \(error.localizedDescription)")
        }

        // Fallback to similarity
        let result = similarityGrade(userAnswer: userAnswer, correctAnswer: correctAnswer)
        NSLog("[FlashcardGrader] Fallback → \(result.verdict) (score \(result.score))")
        return result
    }

    /// Semantic prompt asking for JSON output
    private func buildSimplePrompt(correctAnswer: String, userAnswer: String) -> String {
        return """
        <start_of_turn>user
        Compare the meaning of the User Answer to the Correct Answer.
        
        Correct Answer: "\(correctAnswer)"
        User Answer: "\(userAnswer)"
        
        Evaluate the user's understanding. Ignore minor typos or phrasing differences if the core meaning is correct.
        
        Output a JSON object with:
        - "score": Integer 1 to 5 (1=Wrong, 3=Partially Correct, 5=Correct meaning)
        - "feedback": A short explanation (max 15 words)
        
        Example: {"score": 5, "feedback": "Correct meaning."}
        <end_of_turn>
        <start_of_turn>model
        """
    }

    /// Parse JSON response
    private func parseSimpleResponse(_ response: String) -> GradeResult? {
        // clean markdown code blocks
        var jsonString = response
        if let start = jsonString.range(of: "{"), 
           let end = jsonString.range(of: "}", options: .backwards),
           start.lowerBound < end.upperBound {
            jsonString = String(jsonString[start.lowerBound..<end.upperBound])
        } else {
            return nil
        }
        
        guard let data = jsonString.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let score = json["score"] as? Int else {
            return nil
        }
        
        let feedback = (json["feedback"] as? String) ?? "Graded by AI"
        
        // Map 1-5 score to verdict
        let verdict: String
        switch score {
        case 5: verdict = "easy"
        case 4: verdict = "good"
        case 3: verdict = "good"  // Partial credit is good
        case 2: verdict = "hard"
        default: verdict = "again"
        }
        
        return GradeResult(score: score, verdict: verdict, feedback: feedback)
    }

    /// Similarity-based grading fallback
    private func similarityGrade(userAnswer: String, correctAnswer: String) -> GradeResult {
        let similarity = stringSimilarity(userAnswer.lowercased(), correctAnswer.lowercased())
        let bonus = semanticBonus(userAnswer: userAnswer, correctAnswer: correctAnswer)
        let adjusted = min(1.0, similarity + bonus)

        NSLog("[FlashcardGrader] Similarity: \(String(format: "%.0f%%", adjusted * 100))")

        switch adjusted {
        case 0.80...1.0: return GradeResult(score: 5, verdict: "easy", feedback: "Perfect!")
        case 0.60..<0.80: return GradeResult(score: 4, verdict: "good", feedback: "Good!")
        case 0.40..<0.60: return GradeResult(score: 3, verdict: "good", feedback: "Close.")
        case 0.20..<0.40: return GradeResult(score: 2, verdict: "hard", feedback: "Partial.")
        default: return GradeResult(score: 1, verdict: "again", feedback: "Review.")
        }
    }

    /// Jaccard similarity on words
    private func stringSimilarity(_ s1: String, _ s2: String) -> Double {
        let words1 = Set(s1.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty })
        let words2 = Set(s2.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty })

        guard !words1.isEmpty || !words2.isEmpty else { return 0 }

        let intersection = words1.intersection(words2).count
        let union = words1.union(words2).count

        return Double(intersection) / Double(union)
    }

    /// Bonus for semantic equivalences
    private func semanticBonus(userAnswer: String, correctAnswer: String) -> Double {
        let user = userAnswer.lowercased()
        let correct = correctAnswer.lowercased()

        let pairs = [
            ("mom", "mother"), ("dad", "father"), ("yeah", "yes"), ("nope", "no"),
            ("gonna", "going to"), ("wanna", "want to"), ("ok", "okay"), ("cause", "because"),
            ("dont", "do not"), ("cant", "cannot"), ("wont", "will not"), ("im", "i am"),
            ("youre", "you are"), ("theyre", "they are"), ("hes", "he is"), ("shes", "she is")
        ]

        for (a, b) in pairs {
            if (user.contains(a) && correct.contains(b)) || (user.contains(b) && correct.contains(a)) {
                return 0.25
            }
        }
        return 0.0
    }
}

enum GradingError: LocalizedError {
    case modelNotReady
    case gradingFailed(String)

    var errorDescription: String? {
        switch self {
        case .modelNotReady:
            return "AI model is not ready. Please wait for it to load."
        case .gradingFailed(let reason):
            return "Failed to grade answer: \(reason)"
        }
    }
}
