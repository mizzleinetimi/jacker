//
//  DeckDetailView.swift
//  Pic2PDF
//
//  Deck detail and card management
//

import SwiftUI

struct DeckDetailView: View {
    let deck: FlashcardDeck
    @StateObject private var manager = FlashcardManager.shared
    @State private var showingAddCard = false
    @State private var newFront = ""
    @State private var newBack = ""
    @State private var showingReview = false
    
    var body: some View {
        List {
            // Stats section
            Section {
                statsView
            }
            
            // Actions
            Section {
                if deck.dueCards > 0 {
                    Button(action: { showingReview = true }) {
                        Label("Start Review (\(deck.dueCards) due)", systemImage: "play.fill")
                            .foregroundColor(.blue)
                    }
                } else if !deck.cards.isEmpty {
                    Label("No cards due today", systemImage: "checkmark.circle")
                        .foregroundColor(.green)
                }
            }
            
            // Cards
            Section("Cards (\(deck.totalCards))") {
                ForEach(deck.cards) { card in
                    CardRow(card: card)
                }
                .onDelete(perform: deleteCards)
                
                Button(action: { showingAddCard = true }) {
                    Label("Add Card", systemImage: "plus")
                }
            }
        }
        .navigationTitle(deck.name)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button(action: { showingAddCard = true }) {
                    Image(systemName: "plus")
                }
            }
        }
        .sheet(isPresented: $showingAddCard) {
            addCardSheet
        }
        .fullScreenCover(isPresented: $showingReview) {
            ReviewSessionView(deck: deck)
        }
    }
    
    private var statsView: some View {
        HStack(spacing: 20) {
            StatBox(title: "Total", value: "\(deck.totalCards)", icon: "rectangle.stack")
            StatBox(title: "Due", value: "\(deck.dueCards)", icon: "clock", highlight: deck.dueCards > 0)
            StatBox(title: "Ease", value: String(format: "%.1f", deck.averageEase), icon: "speedometer")
        }
        .padding(.vertical, 8)
    }
    
    private var addCardSheet: some View {
        NavigationStack {
            Form {
                Section("Front (Question)") {
                    TextEditor(text: $newFront)
                        .frame(minHeight: 80)
                }
                
                Section("Back (Answer)") {
                    TextEditor(text: $newBack)
                        .frame(minHeight: 80)
                }
            }
            .navigationTitle("Add Card")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        newFront = ""
                        newBack = ""
                        showingAddCard = false
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        if !newFront.isEmpty && !newBack.isEmpty {
                            manager.addCard(to: deck, front: newFront, back: newBack)
                            newFront = ""
                            newBack = ""
                            showingAddCard = false
                        }
                    }
                    .disabled(newFront.isEmpty || newBack.isEmpty)
                }
            }
        }
    }
    
    private func deleteCards(at offsets: IndexSet) {
        for index in offsets {
            manager.deleteCard(deck.cards[index], from: deck)
        }
    }
}

struct StatBox: View {
    let title: String
    let value: String
    let icon: String
    var highlight: Bool = false
    
    var body: some View {
        VStack(spacing: 4) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundColor(highlight ? .orange : .blue)
            Text(value)
                .font(.title2)
                .fontWeight(.bold)
            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}

struct CardRow: View {
    let card: Flashcard
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(card.front)
                .font(.subheadline)
                .fontWeight(.medium)
                .lineLimit(2)
            
            Text(card.back)
                .font(.caption)
                .foregroundColor(.secondary)
                .lineLimit(1)
            
            HStack(spacing: 8) {
                if card.isDue {
                    Text("Due")
                        .font(.caption2)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.orange.opacity(0.2))
                        .foregroundColor(.orange)
                        .cornerRadius(4)
                }
                
                if card.totalReviews > 0 {
                    Text("\(Int(card.successRate * 100))% correct")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding(.vertical, 4)
    }
}
