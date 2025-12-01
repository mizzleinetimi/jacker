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
    
    var body: some View {
        NavigationStack {
            Group {
                if manager.decks.isEmpty {
                    emptyState
                } else {
                    decksList
                }
            }
            .navigationTitle("Flashcards")
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
                            .font(.title2)
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
        VStack(spacing: 20) {
            Image(systemName: "rectangle.stack")
                .font(.system(size: 60))
                .foregroundColor(.secondary)
            
            Text("No Flashcard Decks")
                .font(.title2)
                .fontWeight(.semibold)
            
            Text("Create a deck or import from CSV/JSON")
                .foregroundColor(.secondary)
            
            HStack(spacing: 16) {
                Button(action: { showingCreateDeck = true }) {
                    Label("Create", systemImage: "plus")
                        .padding(.horizontal, 20)
                        .padding(.vertical, 12)
                        .background(Color.blue)
                        .foregroundColor(.white)
                        .cornerRadius(10)
                }
                
                Button(action: { showingImport = true }) {
                    Label("Import", systemImage: "square.and.arrow.down")
                        .padding(.horizontal, 20)
                        .padding(.vertical, 12)
                        .background(Color(.systemGray5))
                        .foregroundColor(.primary)
                        .cornerRadius(10)
                }
            }
        }
        .padding()
    }
    
    private var decksList: some View {
        List {
            // Summary header
            Section {
                HStack {
                    VStack(alignment: .leading) {
                        Text("\(manager.totalDueCards) cards due")
                            .font(.headline)
                        Text("\(manager.decks.count) decks")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                    if manager.totalDueCards > 0 {
                        Image(systemName: "flame.fill")
                            .foregroundColor(.orange)
                    }
                }
                .padding(.vertical, 4)
            }
            
            // Decks
            Section("Your Decks") {
                ForEach(manager.decks) { deck in
                    NavigationLink(destination: DeckDetailView(deck: deck)) {
                        DeckRow(deck: deck)
                    }
                }
                .onDelete(perform: deleteDecks)
            }
        }
    }
    
    private func deleteDecks(at offsets: IndexSet) {
        for index in offsets {
            manager.deleteDeck(manager.decks[index])
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

struct DeckRow: View {
    let deck: FlashcardDeck
    
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(deck.name)
                    .font(.headline)
                
                HStack(spacing: 12) {
                    Label("\(deck.totalCards)", systemImage: "rectangle.stack")
                    if deck.dueCards > 0 {
                        Label("\(deck.dueCards) due", systemImage: "clock")
                            .foregroundColor(.orange)
                    }
                }
                .font(.caption)
                .foregroundColor(.secondary)
            }
            
            Spacer()
            
            if deck.dueCards > 0 {
                Text("\(deck.dueCards)")
                    .font(.caption)
                    .fontWeight(.bold)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.orange)
                    .foregroundColor(.white)
                    .cornerRadius(10)
            }
        }
        .padding(.vertical, 4)
    }
}
