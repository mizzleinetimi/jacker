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
        ZStack {
            Theme.background
                .ignoresSafeArea()
            
            ScrollView {
                VStack(spacing: 24) {
                    // Stats section
                    statsView
                    
                    // Actions
                    if deck.dueCards > 0 {
                        Button(action: { showingReview = true }) {
                            HStack {
                                Image(systemName: "play.fill")
                                Text("Start Review (\(deck.dueCards) due)")
                                    .fontWeight(.semibold)
                            }
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Theme.accent)
                            .foregroundColor(.white)
                            .cornerRadius(16)
                            .calmShadow()
                        }
                        .padding(.horizontal, 20)
                    } else if !deck.cards.isEmpty {
                        HStack {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.green)
                            Text("All caught up!")
                                .font(Theme.uiFont(size: 16, weight: .medium))
                                .foregroundColor(.green)
                        }
                        .padding()
                        .frame(maxWidth: .infinity)
                        .background(Color.green.opacity(0.1))
                        .cornerRadius(16)
                        .padding(.horizontal, 20)
                    }
                    
                    // Cards List
                    VStack(alignment: .leading, spacing: 16) {
                        HStack {
                            Text("Cards")
                                .font(Theme.uiFont(size: 18, weight: .bold))
                                .foregroundColor(Theme.text)
                            
                            Spacer()
                            
                            Text("\(deck.totalCards)")
                                .font(Theme.uiFont(size: 14, weight: .medium))
                                .foregroundColor(Theme.secondaryText)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Theme.secondaryBackground)
                                .cornerRadius(8)
                        }
                        .padding(.horizontal, 20)
                        
                        LazyVStack(spacing: 12) {
                            ForEach(deck.cards) { card in
                                CardRow(card: card)
                                    .contextMenu {
                                        Button(role: .destructive) {
                                            manager.deleteCard(card, from: deck)
                                        } label: {
                                            Label("Delete", systemImage: "trash")
                                        }
                                    }
                            }
                            
                            Button(action: { showingAddCard = true }) {
                                HStack {
                                    Image(systemName: "plus")
                                    Text("Add New Card")
                                }
                                .font(Theme.uiFont(size: 16, weight: .medium))
                                .foregroundColor(Theme.accent)
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(Theme.secondaryBackground)
                                .cornerRadius(16)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 16)
                                        .stroke(Theme.accent.opacity(0.3), style: StrokeStyle(lineWidth: 1, dash: [5]))
                                )
                            }
                        }
                        .padding(.horizontal, 20)
                    }
                }
                .padding(.vertical, 20)
            }
        }
        .navigationTitle(deck.name)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button(action: { showingAddCard = true }) {
                    Image(systemName: "plus")
                        .font(.system(size: 16, weight: .bold))
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
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 16) {
                StatBox(title: "Total Cards", value: "\(deck.totalCards)", icon: "rectangle.stack.fill", color: .blue)
                StatBox(title: "Due Now", value: "\(deck.dueCards)", icon: "clock.fill", color: .orange)
                StatBox(title: "Avg Ease", value: String(format: "%.1f", deck.averageEase), icon: "speedometer", color: .purple)
            }
            .padding(.horizontal, 20)
        }
    }
    
    private var addCardSheet: some View {
        NavigationStack {
            ZStack {
                Theme.background.ignoresSafeArea()
                
                ScrollView {
                    VStack(spacing: 24) {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Front (Question)")
                                .font(Theme.uiFont(size: 14, weight: .bold))
                                .foregroundColor(Theme.secondaryText)
                                .textCase(.uppercase)
                            
                            TextEditor(text: $newFront)
                                .frame(minHeight: 100)
                                .padding(12)
                                .background(Theme.secondaryBackground)
                                .cornerRadius(12)
                                .calmShadow()
                        }
                        
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Back (Answer)")
                                .font(Theme.uiFont(size: 14, weight: .bold))
                                .foregroundColor(Theme.secondaryText)
                                .textCase(.uppercase)
                            
                            TextEditor(text: $newBack)
                                .frame(minHeight: 100)
                                .padding(12)
                                .background(Theme.secondaryBackground)
                                .cornerRadius(12)
                                .calmShadow()
                        }
                    }
                    .padding(20)
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
                    .fontWeight(.bold)
                }
            }
        }
    }
}

struct StatBox: View {
    let title: String
    let value: String
    let icon: String
    let color: Color
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: icon)
                    .font(.system(size: 20))
                    .foregroundColor(color)
                Spacer()
                Text(value)
                    .font(Theme.uiFont(size: 24, weight: .bold))
                    .foregroundColor(Theme.text)
            }
            
            Text(title)
                .font(Theme.uiFont(size: 14, weight: .medium))
                .foregroundColor(Theme.secondaryText)
        }
        .padding(16)
        .frame(width: 140)
        .background(Theme.secondaryBackground)
        .cornerRadius(20)
        .calmShadow()
    }
}

struct CardRow: View {
    let card: Flashcard
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top) {
                Text(card.front)
                    .font(Theme.uiFont(size: 16, weight: .medium))
                    .foregroundColor(Theme.text)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                
                Spacer()
                
                if card.isDue {
                    Circle()
                        .fill(Color.orange)
                        .frame(width: 8, height: 8)
                }
            }
            
            Text(card.back)
                .font(Theme.uiFont(size: 14))
                .foregroundColor(Theme.secondaryText)
                .lineLimit(1)
        }
        .padding(16)
        .background(Theme.secondaryBackground)
        .cornerRadius(16)
        .calmShadow()
    }
}
