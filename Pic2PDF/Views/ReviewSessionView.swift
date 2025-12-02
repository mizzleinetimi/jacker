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
                Theme.background
                    .ignoresSafeArea()
                
                if showingSummary {
                    summaryView
                } else if let card = currentCard {
                    VStack(spacing: 0) {
                        // Progress Bar
                        ProgressView(value: progress)
                            .tint(Theme.accent)
                            .padding(.horizontal)
                            .padding(.top, 8)
                        
                        if showingFeedback {
                            feedbackView(card: card)
                                .transition(.move(edge: .trailing))
                        } else {
                            questionView(card: card)
                                .transition(.move(edge: .leading))
                        }
                    }
                    .animation(.spring(response: 0.5, dampingFraction: 0.8), value: showingFeedback)
                } else {
                    Text("No cards to review")
                        .font(Theme.uiFont(size: 18))
                        .foregroundColor(Theme.secondaryText)
                }
            }
            .navigationTitle("Review")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("End Session") { dismiss() }
                        .foregroundColor(Theme.secondaryText)
                }
            }
        }
        .onAppear {
            dueCards = manager.getDueCards(for: deck)
        }
    }
    
    // MARK: - Question View
    
    private func questionView(card: Flashcard) -> some View {
        VStack(spacing: 24) {
            Spacer()
            
            // Question Card
            VStack(spacing: 20) {
                Text("QUESTION")
                    .font(Theme.uiFont(size: 12, weight: .bold))
                    .foregroundColor(Theme.secondaryText)
                    .tracking(2)
                
                Text(card.front)
                    .font(Theme.uiFont(size: 24, weight: .semibold))
                    .foregroundColor(Theme.text)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 40)
            .background(Theme.secondaryBackground)
            .cornerRadius(24)
            .calmShadow()
            .padding(.horizontal, 24)
            
            Spacer()
            
            // Input Area
            VStack(spacing: 16) {
                TextEditor(text: $userAnswer)
                    .frame(height: 100)
                    .padding(16)
                    .background(Theme.secondaryBackground)
                    .cornerRadius(16)
                    .calmShadow()
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(Theme.accent.opacity(0.1), lineWidth: 1)
                    )
                    .overlay(alignment: .topLeading) {
                        if userAnswer.isEmpty {
                            Text("Type your answer...")
                                .font(Theme.uiFont(size: 16))
                                .foregroundColor(Theme.secondaryText.opacity(0.5))
                                .padding(20)
                                .allowsHitTesting(false)
                        }
                    }
                
                Button(action: gradeAnswer) {
                    HStack {
                        if isGrading {
                            ProgressView()
                                .tint(.white)
                                .padding(.trailing, 8)
                            Text("Checking...")
                        } else {
                            Text("Check Answer")
                        }
                    }
                    .font(Theme.uiFont(size: 18, weight: .bold))
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(userAnswer.isEmpty ? Color.gray.opacity(0.3) : Theme.accent)
                    .foregroundColor(.white)
                    .cornerRadius(16)
                    .calmShadow()
                }
                .disabled(isGrading || userAnswer.isEmpty)
            }
            .padding(24)
        }
    }
    
    // MARK: - Feedback View
    
    private func feedbackView(card: Flashcard) -> some View {
        ScrollView {
            VStack(spacing: 24) {
                // Verdict Header
                if let result = currentResult {
                    HStack {
                        Text(result.reviewVerdict.emoji)
                            .font(.system(size: 40))
                        
                        VStack(alignment: .leading) {
                            Text(result.reviewVerdict.rawValue.capitalized)
                                .font(Theme.uiFont(size: 24, weight: .bold))
                                .foregroundColor(verdictColor(for: result.reviewVerdict))
                            
                            Text("Score: \(result.score)/5")
                                .font(Theme.uiFont(size: 14))
                                .foregroundColor(Theme.secondaryText)
                        }
                        
                        Spacer()
                    }
                    .padding()
                    .background(verdictColor(for: result.reviewVerdict).opacity(0.1))
                    .cornerRadius(20)
                }
                
                // Comparison
                VStack(spacing: 0) {
                    // Correct Answer
                    VStack(alignment: .leading, spacing: 8) {
                        Text("CORRECT ANSWER")
                            .font(Theme.uiFont(size: 12, weight: .bold))
                            .foregroundColor(.green)
                            .tracking(1)
                        
                        Text(card.back)
                            .font(Theme.uiFont(size: 16))
                            .foregroundColor(Theme.text)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(20)
                    .background(Color.green.opacity(0.05))
                    
                    Divider()
                    
                    // User Answer
                    VStack(alignment: .leading, spacing: 8) {
                        Text("YOUR ANSWER")
                            .font(Theme.uiFont(size: 12, weight: .bold))
                            .foregroundColor(Theme.secondaryText)
                            .tracking(1)
                        
                        Text(userAnswer.isEmpty ? "(No answer provided)" : userAnswer)
                            .font(Theme.uiFont(size: 16))
                            .foregroundColor(Theme.text)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(20)
                    .background(Theme.secondaryBackground)
                }
                .cornerRadius(20)
                .calmShadow()
                
                // AI Feedback
                if let result = currentResult {
                    HStack(alignment: .top, spacing: 16) {
                        Image(systemName: "sparkles")
                            .font(.system(size: 24))
                            .foregroundColor(.purple)
                            .padding(12)
                            .background(Color.purple.opacity(0.1))
                            .clipShape(Circle())
                        
                        VStack(alignment: .leading, spacing: 8) {
                            Text("AI Feedback")
                                .font(Theme.uiFont(size: 14, weight: .bold))
                                .foregroundColor(.purple)
                            
                            Text(result.feedback)
                                .font(Theme.uiFont(size: 16))
                                .foregroundColor(Theme.text)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .padding(20)
                    .background(Theme.secondaryBackground)
                    .cornerRadius(20)
                    .calmShadow()
                }
                
                // Actions
                VStack(spacing: 16) {
                    Button(action: nextCard) {
                        Text(currentIndex < dueCards.count - 1 ? "Next Card" : "Finish Review")
                            .font(Theme.uiFont(size: 18, weight: .bold))
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Theme.accent)
                            .foregroundColor(.white)
                            .cornerRadius(16)
                            .calmShadow()
                    }
                    
                    if currentResult != nil {
                        Menu {
                            ForEach([ReviewVerdict.again, .hard, .good, .easy], id: \.self) { verdict in
                                Button {
                                    overrideVerdict(verdict)
                                } label: {
                                    Label(verdict.rawValue.capitalized, systemImage: verdict == .easy ? "star.fill" : "circle")
                                }
                            }
                        } label: {
                            Text("Override Grade")
                                .font(Theme.uiFont(size: 14, weight: .medium))
                                .foregroundColor(Theme.secondaryText)
                        }
                    }
                }
                .padding(.top, 10)
            }
            .padding(24)
        }
    }
    
    // MARK: - Summary View
    
    private var summaryView: some View {
        VStack(spacing: 32) {
            Spacer()
            
            VStack(spacing: 16) {
                ZStack {
                    Circle()
                        .fill(Color.green.opacity(0.1))
                        .frame(width: 100, height: 100)
                    
                    Image(systemName: "checkmark")
                        .font(.system(size: 40, weight: .bold))
                        .foregroundColor(.green)
                }
                
                Text("Session Complete!")
                    .font(Theme.uiFont(size: 28, weight: .bold))
                    .foregroundColor(Theme.text)
                
                Text("You reviewed \(sessionStats.totalReviewed) cards")
                    .font(Theme.uiFont(size: 16))
                    .foregroundColor(Theme.secondaryText)
            }
            
            VStack(spacing: 20) {
                HStack(spacing: 40) {
                    VStack {
                        Text("\(Int(sessionStats.averageScore * 20))%")
                            .font(Theme.uiFont(size: 32, weight: .bold))
                            .foregroundColor(Theme.accent)
                        Text("Accuracy")
                            .font(Theme.uiFont(size: 12))
                            .foregroundColor(Theme.secondaryText)
                    }
                    
                    VStack {
                        Text("\(sessionStats.goodCount + sessionStats.easyCount)")
                            .font(Theme.uiFont(size: 32, weight: .bold))
                            .foregroundColor(.green)
                        Text("Correct")
                            .font(Theme.uiFont(size: 12))
                            .foregroundColor(Theme.secondaryText)
                    }
                }
                
                Divider()
                
                HStack(spacing: 12) {
                    ResultPill(emoji: "🔴", count: sessionStats.againCount, label: "Again")
                    ResultPill(emoji: "🟠", count: sessionStats.hardCount, label: "Hard")
                    ResultPill(emoji: "🟢", count: sessionStats.goodCount, label: "Good")
                    ResultPill(emoji: "🔵", count: sessionStats.easyCount, label: "Easy")
                }
            }
            .padding(24)
            .background(Theme.secondaryBackground)
            .cornerRadius(24)
            .calmShadow()
            .padding(.horizontal, 24)
            
            Spacer()
            
            Button(action: { dismiss() }) {
                Text("Back to Deck")
                    .font(Theme.uiFont(size: 18, weight: .bold))
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Theme.accent)
                    .foregroundColor(.white)
                    .cornerRadius(16)
                    .calmShadow()
            }
            .padding(24)
        }
    }
    
    // MARK: - Logic
    
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
        
        switch oldResult.reviewVerdict {
        case .again: sessionStats.againCount -= 1
        case .hard: sessionStats.hardCount -= 1
        case .good: sessionStats.goodCount -= 1
        case .easy: sessionStats.easyCount -= 1
        }
        
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
    
    private func verdictColor(for verdict: ReviewVerdict) -> Color {
        switch verdict {
        case .again: return .red
        case .hard: return .orange
        case .good: return .green
        case .easy: return .blue
        }
    }
}

struct ResultPill: View {
    let emoji: String
    let count: Int
    let label: String
    
    var body: some View {
        VStack(spacing: 4) {
            Text(emoji)
            Text("\(count)")
                .font(Theme.uiFont(size: 16, weight: .bold))
            Text(label)
                .font(Theme.uiFont(size: 10))
                .foregroundColor(Theme.secondaryText)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(Theme.background)
        .cornerRadius(12)
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
