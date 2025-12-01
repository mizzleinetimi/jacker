//
//  ReviewSessionView.swift
//  Pic2PDF
//
//  Flashcard review session with AI grading
//

import SwiftUI

struct ReviewSessionView: View {
    let deck: FlashcardDeck
    @Environment(\.dismiss) private var dismiss
    @StateObject private var manager = FlashcardManager.shared
    
    @State private var dueCards: [Flashcard] = []
    @State private var currentIndex = 0
    @State private var userAnswer = ""
    @State private var isGrading = false
    @State private var showingFeedback = false
    @State private var currentResult: GradeResult?
    @State private var sessionStats = SessionStats()
    @State private var showingSummary = false
    
    private var currentCard: Flashcard? {
        guard currentIndex < dueCards.count else { return nil }
        return dueCards[currentIndex]
    }
    
    private var progress: Double {
        guard !dueCards.isEmpty else { return 0 }
        return Double(currentIndex) / Double(dueCards.count)
    }
    
    var body: some View {
        NavigationStack {
            ZStack {
                if showingSummary {
                    summaryView
                } else if let card = currentCard {
                    if showingFeedback {
                        feedbackView(card: card)
                    } else {
                        questionView(card: card)
                    }
                } else {
                    Text("No cards to review")
                }
            }
            .navigationTitle("Review")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("End") { dismiss() }
                }
                ToolbarItem(placement: .principal) {
                    ProgressView(value: progress)
                        .frame(width: 100)
                }
            }
        }
        .onAppear {
            dueCards = manager.getDueCards(for: deck)
        }
    }
    
    // MARK: - Question View
    
    private func questionView(card: Flashcard) -> some View {
        VStack(spacing: 0) {
            // Progress
            HStack {
                Text("Card \(currentIndex + 1) of \(dueCards.count)")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Spacer()
            }
            .padding()
            
            Spacer()
            
            // Question
            VStack(spacing: 16) {
                Text("Question")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                Text(card.front)
                    .font(.title2)
                    .fontWeight(.medium)
                    .multilineTextAlignment(.center)
                    .padding()
            }
            .padding()
            
            Spacer()
            
            // Answer input
            VStack(spacing: 16) {
                Text("Your Answer")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                TextEditor(text: $userAnswer)
                    .frame(height: 120)
                    .padding(8)
                    .background(Color(.systemGray6))
                    .cornerRadius(12)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color(.systemGray4), lineWidth: 1)
                    )
                
                Button(action: gradeAnswer) {
                    if isGrading {
                        HStack {
                            ProgressView()
                                .tint(.white)
                            Text("Grading...")
                        }
                    } else {
                        Text("Check Answer")
                    }
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(userAnswer.isEmpty ? Color.gray : Color.blue)
                .foregroundColor(.white)
                .cornerRadius(12)
                .disabled(isGrading)
            }
            .padding()
        }
    }
    
    // MARK: - Feedback View
    
    private func feedbackView(card: Flashcard) -> some View {
        ScrollView {
            VStack(spacing: 24) {
                // Verdict badge
                if let result = currentResult {
                    VerdictBadge(verdict: result.reviewVerdict)
                }
                
                // Question
                VStack(alignment: .leading, spacing: 8) {
                    Text("Question")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text(card.front)
                        .font(.headline)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
                .background(Color(.systemGray6))
                .cornerRadius(12)
                
                // Correct answer
                VStack(alignment: .leading, spacing: 8) {
                    Text("Correct Answer")
                        .font(.caption)
                        .foregroundColor(.green)
                    Text(card.back)
                        .font(.body)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
                .background(Color.green.opacity(0.1))
                .cornerRadius(12)
                
                // User's answer
                VStack(alignment: .leading, spacing: 8) {
                    Text("Your Answer")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text(userAnswer.isEmpty ? "(no answer)" : userAnswer)
                        .font(.body)
                        .foregroundColor(userAnswer.isEmpty ? .secondary : .primary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
                .background(Color(.systemGray6))
                .cornerRadius(12)
                
                // AI Feedback
                if let result = currentResult {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Image(systemName: "sparkles")
                            Text("AI Feedback")
                        }
                        .font(.caption)
                        .foregroundColor(.purple)
                        
                        Text(result.feedback)
                            .font(.body)
                        
                        Text("Score: \(result.score)/5")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
                    .background(Color.purple.opacity(0.1))
                    .cornerRadius(12)
                }
                
                Spacer(minLength: 20)
                
                // Next button
                Button(action: nextCard) {
                    Text(currentIndex < dueCards.count - 1 ? "Next Card" : "Finish")
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.blue)
                        .foregroundColor(.white)
                        .cornerRadius(12)
                }
                
                // Override buttons
                if currentResult != nil {
                    HStack(spacing: 12) {
                        Text("Override:")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        
                        ForEach([ReviewVerdict.again, .hard, .good, .easy], id: \.self) { verdict in
                            Button(verdict.emoji) {
                                overrideVerdict(verdict)
                            }
                            .padding(8)
                            .background(Color(.systemGray5))
                            .cornerRadius(8)
                        }
                    }
                }
            }
            .padding()
        }
    }
    
    // MARK: - Summary View
    
    private var summaryView: some View {
        VStack(spacing: 24) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 60))
                .foregroundColor(.green)
            
            Text("Session Complete! 🎉")
                .font(.title)
                .fontWeight(.bold)
            
            VStack(spacing: 16) {
                StatRow(label: "Cards Reviewed", value: "\(sessionStats.totalReviewed)")
                StatRow(label: "Average Score", value: String(format: "%.1f/5", sessionStats.averageScore))
                
                HStack(spacing: 20) {
                    MiniStat(emoji: "🔴", count: sessionStats.againCount)
                    MiniStat(emoji: "🟠", count: sessionStats.hardCount)
                    MiniStat(emoji: "🟢", count: sessionStats.goodCount)
                    MiniStat(emoji: "🔵", count: sessionStats.easyCount)
                }
            }
            .padding()
            .background(Color(.systemGray6))
            .cornerRadius(16)
            
            Spacer()
            
            Button(action: { dismiss() }) {
                Text("Back to Deck")
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.blue)
                    .foregroundColor(.white)
                    .cornerRadius(12)
            }
        }
        .padding()
    }
    
    // MARK: - Actions
    
    private func gradeAnswer() {
        guard let card = currentCard else { return }
        
        isGrading = true
        
        Task {
            do {
                let result = try await FlashcardGrader.shared.grade(
                    question: card.front,
                    correctAnswer: card.back,
                    userAnswer: userAnswer
                )
                
                currentResult = result
                applyResult(result.reviewVerdict, to: card)
                
            } catch {
                // Fallback to "hard" on error
                currentResult = GradeResult(score: 2, verdict: "hard", feedback: "Could not grade - marked as hard.")
                applyResult(.hard, to: card)
            }
            
            isGrading = false
            showingFeedback = true
        }
    }
    
    private func applyResult(_ verdict: ReviewVerdict, to card: Flashcard) {
        card.applyReview(verdict: verdict)
        manager.saveChanges()
        
        sessionStats.totalReviewed += 1
        sessionStats.totalScore += currentResult?.score ?? 2
        
        switch verdict {
        case .again: sessionStats.againCount += 1
        case .hard: sessionStats.hardCount += 1
        case .good: sessionStats.goodCount += 1
        case .easy: sessionStats.easyCount += 1
        }
    }
    
    private func overrideVerdict(_ verdict: ReviewVerdict) {
        guard let card = currentCard, let oldResult = currentResult else { return }
        
        // Undo old verdict stats
        switch oldResult.reviewVerdict {
        case .again: sessionStats.againCount -= 1
        case .hard: sessionStats.hardCount -= 1
        case .good: sessionStats.goodCount -= 1
        case .easy: sessionStats.easyCount -= 1
        }
        
        // Apply new verdict
        card.applyReview(verdict: verdict)
        manager.saveChanges()
        
        switch verdict {
        case .again: sessionStats.againCount += 1
        case .hard: sessionStats.hardCount += 1
        case .good: sessionStats.goodCount += 1
        case .easy: sessionStats.easyCount += 1
        }
        
        currentResult = GradeResult(score: verdict.score, verdict: verdict.rawValue, feedback: "Manually overridden.")
    }
    
    private func nextCard() {
        if currentIndex < dueCards.count - 1 {
            currentIndex += 1
            userAnswer = ""
            currentResult = nil
            showingFeedback = false
        } else {
            showingSummary = true
        }
    }
}

// MARK: - Supporting Views

struct VerdictBadge: View {
    let verdict: ReviewVerdict
    
    var body: some View {
        HStack {
            Text(verdict.emoji)
            Text(verdict.rawValue.capitalized)
                .fontWeight(.semibold)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
        .background(verdictColor.opacity(0.2))
        .foregroundColor(verdictColor)
        .cornerRadius(20)
    }
    
    private var verdictColor: Color {
        switch verdict {
        case .again: return .red
        case .hard: return .orange
        case .good: return .green
        case .easy: return .blue
        }
    }
}

struct StatRow: View {
    let label: String
    let value: String
    
    var body: some View {
        HStack {
            Text(label)
                .foregroundColor(.secondary)
            Spacer()
            Text(value)
                .fontWeight(.semibold)
        }
    }
}

struct MiniStat: View {
    let emoji: String
    let count: Int
    
    var body: some View {
        VStack {
            Text(emoji)
            Text("\(count)")
                .font(.caption)
                .fontWeight(.bold)
        }
    }
}

struct SessionStats {
    var totalReviewed = 0
    var totalScore = 0
    var againCount = 0
    var hardCount = 0
    var goodCount = 0
    var easyCount = 0
    
    var averageScore: Double {
        guard totalReviewed > 0 else { return 0 }
        return Double(totalScore) / Double(totalReviewed)
    }
}
