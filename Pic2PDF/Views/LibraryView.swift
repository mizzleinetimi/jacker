//
//  LibraryView.swift
//  Pic2PDF
//
//  Shows all imported documents
//

import SwiftUI
import PhotosUI
import UniformTypeIdentifiers

struct LibraryView: View {
    @StateObject private var documentManager = DocumentManager.shared
    @State private var showImportOptions = false
    @State private var showPDFPicker = false
    @State private var showImagePicker = false
    @State private var selectedImages: [PhotosPickerItem] = []
    @State private var selectedDocument: Document?
    @State private var errorMessage: String?
    @State private var showError = false
    
    // Grid layout
    private let columns = [
        GridItem(.adaptive(minimum: 160), spacing: 20)
    ]
    
    var body: some View {
        NavigationStack {
            ZStack {
                Theme.background
                    .ignoresSafeArea()
                
                if documentManager.documents.isEmpty {
                    emptyState
                } else {
                    documentGrid
                }
                
                // Processing overlay
                if documentManager.isProcessing {
                    processingOverlay
                }
            }
            .navigationTitle("Library")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: { showImportOptions = true }) {
                        Image(systemName: "plus")
                            .font(Theme.uiFont(size: 20, weight: .medium))
                            .foregroundColor(Theme.accent)
                            .frame(width: 40, height: 40)
                            .background(Theme.secondaryBackground)
                            .clipShape(Circle())
                            .calmShadow()
                    }
                    .disabled(documentManager.isProcessing)
                }
            }
            .confirmationDialog("Import Content", isPresented: $showImportOptions) {
                Button("Import PDF") { showPDFPicker = true }
                Button("Import Images") { showImagePicker = true }
                Button("Cancel", role: .cancel) {}
            }
            .fileImporter(
                isPresented: $showPDFPicker,
                allowedContentTypes: [.pdf],
                allowsMultipleSelection: false
            ) { result in
                handlePDFImport(result)
            }
            .photosPicker(
                isPresented: $showImagePicker,
                selection: $selectedImages,
                maxSelectionCount: 20,
                matching: .images
            )
            .onChange(of: selectedImages) { _, newItems in
                if !newItems.isEmpty {
                    Task { await handleImageImport(newItems) }
                }
            }
            .alert("Error", isPresented: $showError) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(errorMessage ?? "An error occurred")
            }
            .navigationDestination(item: $selectedDocument) { document in
                ReaderView(document: document)
            }
        }
    }
    
    // MARK: - Empty State
    
    private var emptyState: some View {
        VStack(spacing: 24) {
            Spacer()
            
            Image(systemName: "books.vertical")
                .font(.system(size: 60))
                .foregroundColor(Theme.secondaryText.opacity(0.5))
            
            VStack(spacing: 8) {
                Text("Your Library is Empty")
                    .font(Theme.uiFont(size: 20, weight: .semibold))
                    .foregroundColor(Theme.text)
                
                Text("Import documents to start reading")
                    .font(Theme.uiFont(size: 16))
                    .foregroundColor(Theme.secondaryText)
            }
            
            Button(action: { showImportOptions = true }) {
                Text("Import Content")
                    .font(Theme.uiFont(size: 16, weight: .medium))
                    .padding(.horizontal, 24)
                    .padding(.vertical, 12)
                    .background(Theme.accent)
                    .foregroundColor(.white)
                    .cornerRadius(24)
                    .calmShadow()
            }
            .padding(.top, 16)
            
            Spacer()
        }
    }
    
    // MARK: - Document Grid
    
    private var documentGrid: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 20) {
                ForEach(documentManager.documents, id: \.id) { document in
                    DocumentCard(document: document)
                        .onTapGesture {
                            selectedDocument = document
                        }
                        .contextMenu {
                            Button(role: .destructive) {
                                documentManager.deleteDocument(document)
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                }
            }
            .padding(20)
        }
    }
    
    // MARK: - Processing Overlay
    
    private var processingOverlay: some View {
        ZStack {
            Color.black.opacity(0.3)
                .ignoresSafeArea()
            
            VStack(spacing: 20) {
                ProgressView()
                    .scaleEffect(1.2)
                    .tint(Theme.text)
                
                Text(documentManager.processingStatus)
                    .font(Theme.uiFont(size: 16, weight: .medium))
                    .foregroundColor(Theme.text)
                
                ProgressView(value: documentManager.processingProgress)
                    .progressViewStyle(.linear)
                    .tint(Theme.accent)
                    .frame(width: 180)
            }
            .padding(32)
            .background(Theme.secondaryBackground)
            .cornerRadius(20)
            .calmShadow()
        }
    }
    
    // MARK: - Import Handlers
    
    private func handlePDFImport(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard let url = urls.first else { return }
            
            Task {
                do {
                    guard url.startAccessingSecurityScopedResource() else {
                        throw NSError(domain: "Import", code: 1, userInfo: [NSLocalizedDescriptionKey: "Cannot access file"])
                    }
                    defer { url.stopAccessingSecurityScopedResource() }
                    
                    let data = try Data(contentsOf: url)
                    let title = url.deletingPathExtension().lastPathComponent
                    
                    let document = try await documentManager.importPDF(data: data, title: title)
                    
                    // Pre-simplify first few cards
                    await documentManager.presimplifyCards(document)
                    
                    selectedDocument = document
                } catch {
                    errorMessage = error.localizedDescription
                    showError = true
                }
            }
            
        case .failure(let error):
            errorMessage = error.localizedDescription
            showError = true
        }
    }
    
    private func handleImageImport(_ items: [PhotosPickerItem]) async {
        var images: [UIImage] = []
        
        for item in items {
            if let data = try? await item.loadTransferable(type: Data.self),
               let image = UIImage(data: data) {
                images.append(image)
            }
        }
        
        selectedImages = []
        
        guard !images.isEmpty else {
            errorMessage = "Could not load selected images"
            showError = true
            return
        }
        
        do {
            let title = "Photos \(Date().formatted(date: .abbreviated, time: .shortened))"
            let doc = try await documentManager.importImages(images, title: title)
            await documentManager.presimplifyCards(doc)
            selectedDocument = doc
        } catch {
            errorMessage = error.localizedDescription
            showError = true
        }
    }
}

// MARK: - Document Card

struct DocumentCard: View {
    let document: Document
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Thumbnail / Icon Area
            ZStack {
                Rectangle()
                    .fill(document.sourceType == "pdf" ? Color.red.opacity(0.05) : Color.blue.opacity(0.05))
                
                Image(systemName: document.sourceType == "pdf" ? "doc.text.fill" : "photo.stack.fill")
                    .font(.system(size: 32))
                    .foregroundColor(document.sourceType == "pdf" ? .red.opacity(0.5) : .blue.opacity(0.5))
            }
            .frame(height: 110)
            .clipped()
            
            // Info Area
            VStack(alignment: .leading, spacing: 8) {
                Text(document.title)
                    .font(Theme.uiFont(size: 16, weight: .semibold))
                    .foregroundColor(Theme.text)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .frame(height: 44, alignment: .topLeading) // Fixed height for alignment
                
                HStack {
                    Text("\(document.totalCards) cards")
                        .font(Theme.uiFont(size: 12))
                        .foregroundColor(Theme.secondaryText)
                    
                    Spacer()
                    
                    if document.lastReadCardIndex > 0 {
                        Text("\(Int(document.progress * 100))%")
                            .font(Theme.uiFont(size: 12, weight: .medium))
                            .foregroundColor(Theme.accent)
                    }
                }
                
                // Progress Bar
                if document.lastReadCardIndex > 0 {
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule()
                                .fill(Color.gray.opacity(0.1))
                                .frame(height: 4)
                            
                            Capsule()
                                .fill(Theme.accent)
                                .frame(width: geo.size.width * document.progress, height: 4)
                        }
                    }
                    .frame(height: 4)
                } else {
                    // Placeholder to keep height consistent
                    Color.clear.frame(height: 4)
                }
            }
            .padding(16)
            .background(Theme.secondaryBackground)
        }
        .cornerRadius(20) // Match ReaderView card radius style
        .calmShadow()
    }
}
