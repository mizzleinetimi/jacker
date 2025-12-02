//
//  FlashcardsView.swift
//  Pic2PDF
//
//  Main flashcard decks list view
//

import SwiftUI
import UniformTypeIdentifiers

struct FlashcardsView: View {
    @StateObject private var manager = FlashcardManager.shared
    @State private var showingImport = false
    @State private var showingCreateDeck = false
    @State private var newDeckName = ""
    @State private var importError: String?
    
    // Grid layout
    private let columns = [
        GridItem(.adaptive(minimum: 160), spacing: 20)
    ]
    
    var body: some View {
        NavigationStack {
            ZStack {
                Theme.background
                    .ignoresSafeArea()
                
                if manager.decks.isEmpty {
                    emptyState
                } else {
                    decksGrid
                }
            }
            .navigationTitle("Flashcards")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        Button(action: { showingCreateDeck = true }) {
                            Label("Create Deck", systemImage: "plus")
                        }
                        Button(action: { showingImport = true }) {
                            Label("Import CSV/JSON", systemImage: "square.and.arrow.down")
                        }
                    } label: {
                        Image(systemName: "plus.circle.fill")
                            .font(.system(size: 28))
                            .foregroundColor(Theme.accent)
                            .symbolRenderingMode(.hierarchical)
                    }
                }
            }
            .fileImporter(
                isPresented: $showingImport,
                allowedContentTypes: [.commaSeparatedText, .json, .plainText],
                allowsMultipleSelection: false
            ) { result in
                handleImport(result)
            }
            .alert("Create New Deck", isPresented: $showingCreateDeck) {
                TextField("Deck name", text: $newDeckName)
                Button("Cancel", role: .cancel) { newDeckName = "" }
                Button("Create") {
                    if !newDeckName.isEmpty {
                        _ = manager.createDeck(name: newDeckName)
                        newDeckName = ""
                    }
                }
            }
            .alert("Import Error", isPresented: .constant(importError != nil)) {
                Button("OK") { importError = nil }
            } message: {
                Text(importError ?? "")
            }
        }
    }
    
    private var emptyState: some View {
        VStack(spacing: 24) {
            Spacer()
            
            ZStack {
                Circle()
                    .fill(Theme.secondaryBackground)
                    .frame(width: 120, height: 120)
                
                Image(systemName: "rectangle.stack.fill")
                    .font(.system(size: 50))
                    .foregroundColor(Theme.accent.opacity(0.8))
            }
            .calmShadow()
            
            VStack(spacing: 8) {
                Text("No Flashcard Decks")
                    .font(Theme.uiFont(size: 22, weight: .bold))
                    .foregroundColor(Theme.text)
                
                Text("Create a deck or import from CSV/JSON to start studying")
                    .font(Theme.uiFont(size: 16))
                    .foregroundColor(Theme.secondaryText)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
            }
            
            HStack(spacing: 16) {
                Button(action: { showingCreateDeck = true }) {
                    Label("Create", systemImage: "plus")
                        .font(Theme.uiFont(size: 16, weight: .medium))
                        .padding(.horizontal, 24)
                        .padding(.vertical, 12)
                        .background(Theme.accent)
                        .foregroundColor(.white)
                        .cornerRadius(24)
                        .calmShadow()
                }
                
                Button(action: { showingImport = true }) {
                    Label("Import", systemImage: "square.and.arrow.down")
                        .font(Theme.uiFont(size: 16, weight: .medium))
                        .padding(.horizontal, 24)
                        .padding(.vertical, 12)
                        .background(Theme.secondaryBackground)
                        .foregroundColor(Theme.text)
                        .cornerRadius(24)
                        .calmShadow()
                }
            }
            .padding(.top, 16)
            
            Spacer()
        }
    }
    
    private var decksGrid: some View {
        ScrollView {
            VStack(spacing: 24) {
                // Summary Header
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Overview")
                            .font(Theme.uiFont(size: 14, weight: .bold))
                            .foregroundColor(Theme.secondaryText)
                            .textCase(.uppercase)
                        
                        HStack(spacing: 16) {
                            Label("\(manager.totalDueCards) Due", systemImage: "clock.fill")
                                .foregroundColor(.orange)
                                .font(Theme.uiFont(size: 16, weight: .medium))
                            
                            Label("\(manager.decks.count) Decks", systemImage: "rectangle.stack.fill")
                                .foregroundColor(Theme.text)
                                .font(Theme.uiFont(size: 16, weight: .medium))
                        }
                    }
                    Spacer()
                }
                .padding(.horizontal, 20)
                .padding(.top, 10)
                
                // Grid
                LazyVGrid(columns: columns, spacing: 20) {
                    ForEach(manager.decks) { deck in
                        NavigationLink(destination: DeckDetailView(deck: deck)) {
                            DeckCard(deck: deck)
                        }
                        .contextMenu {
                            Button(role: .destructive) {
                                manager.deleteDeck(deck)
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 20)
            }
        }
    }
    
    private func handleImport(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard let url = urls.first else { return }
            
            guard url.startAccessingSecurityScopedResource() else {
                importError = "Could not access the file."
                return
            }
            defer { url.stopAccessingSecurityScopedResource() }
            
            do {
                let data = try Data(contentsOf: url)
                let filename = url.deletingPathExtension().lastPathComponent
                let ext = url.pathExtension.lowercased()
                
                if ext == "json" {
                    _ = try manager.importJSON(data: data, deckName: filename)
                } else {
                    _ = try manager.importCSV(data: data, deckName: filename)
                }
            } catch {
                importError = error.localizedDescription
            }
            
        case .failure(let error):
            importError = error.localizedDescription
        }
    }
}

struct DeckCard: View {
    let deck: FlashcardDeck
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Icon & Badge
            HStack {
                ZStack {
                    Circle()
                        .fill(Color.blue.opacity(0.1))
                        .frame(width: 40, height: 40)
                    
                    Image(systemName: "rectangle.stack.fill")
                        .font(.system(size: 20))
                        .foregroundColor(.blue)
                }
                
                Spacer()
                
                if deck.dueCards > 0 {
                    Text("\(deck.dueCards)")
                        .font(Theme.uiFont(size: 12, weight: .bold))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.orange)
                        .foregroundColor(.white)
                        .clipShape(Capsule())
                }
            }
            
            // Info
            VStack(alignment: .leading, spacing: 4) {
                Text(deck.name)
                    .font(Theme.uiFont(size: 16, weight: .bold))
                    .foregroundColor(Theme.text)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                
                Text("\(deck.totalCards) cards")
                    .font(Theme.uiFont(size: 12))
                    .foregroundColor(Theme.secondaryText)
            }
            
            Spacer(minLength: 0)
            
            // Progress Bar (Visual flair)
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.gray.opacity(0.1))
                        .frame(height: 4)
                    
                    // Show some progress if there are cards, just for visuals
                    if deck.totalCards > 0 {
                        let progress = max(0.1, Double(deck.totalCards - deck.dueCards) / Double(deck.totalCards))
                        Capsule()
                            .fill(Color.blue.opacity(0.6))
                            .frame(width: geo.size.width * progress, height: 4)
                    }
                }
            }
            .frame(height: 4)
        }
        .padding(16)
        .frame(height: 160)
        .background(Theme.secondaryBackground)
        .cornerRadius(20)
        .calmShadow()
    }
}
