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
    
    var body: some View {
        NavigationStack {
            ZStack {
                if documentManager.documents.isEmpty {
                    emptyState
                } else {
                    documentList
                }
                
                // Processing overlay
                if documentManager.isProcessing {
                    processingOverlay
                }
            }
            .navigationTitle("My Library")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: { showImportOptions = true }) {
                        Image(systemName: "plus.circle.fill")
                            .font(.title2)
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
            Image(systemName: "books.vertical")
                .font(.system(size: 80))
                .foregroundColor(.gray)
            
            Text("No Documents Yet")
                .font(.title2)
                .fontWeight(.semibold)
            
            Text("Import a PDF or photos of your notes to get started")
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
            
            Button(action: { showImportOptions = true }) {
                Label("Import Content", systemImage: "plus.circle.fill")
                    .font(.headline)
                    .padding()
                    .background(Color.blue)
                    .foregroundColor(.white)
                    .cornerRadius(12)
            }
        }
    }
    
    // MARK: - Document List
    
    private var documentList: some View {
        List {
            ForEach(documentManager.documents, id: \.id) { document in
                DocumentRow(document: document)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        selectedDocument = document
                    }
            }
            .onDelete(perform: deleteDocuments)
        }
        .listStyle(.plain)
    }
    
    // MARK: - Processing Overlay
    
    private var processingOverlay: some View {
        ZStack {
            Color.black.opacity(0.5)
                .ignoresSafeArea()
            
            VStack(spacing: 20) {
                ProgressView()
                    .scaleEffect(1.5)
                    .tint(.white)
                
                Text(documentManager.processingStatus)
                    .font(.headline)
                    .foregroundColor(.white)
                
                ProgressView(value: documentManager.processingProgress)
                    .progressViewStyle(.linear)
                    .tint(.white)
                    .frame(width: 200)
            }
            .padding(40)
            .background(Color(.systemGray6).opacity(0.9))
            .cornerRadius(20)
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
    
    private func deleteDocuments(at offsets: IndexSet) {
        for index in offsets {
            documentManager.deleteDocument(documentManager.documents[index])
        }
    }
}

// MARK: - Document Row

struct DocumentRow: View {
    let document: Document
    
    var body: some View {
        HStack(spacing: 16) {
            // Icon
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(document.sourceType == "pdf" ? Color.red.opacity(0.2) : Color.blue.opacity(0.2))
                    .frame(width: 50, height: 50)
                
                Image(systemName: document.sourceType == "pdf" ? "doc.fill" : "photo.stack.fill")
                    .font(.title2)
                    .foregroundColor(document.sourceType == "pdf" ? .red : .blue)
            }
            
            // Info
            VStack(alignment: .leading, spacing: 4) {
                Text(document.title)
                    .font(.headline)
                    .lineLimit(1)
                
                Text("\(document.totalCards) cards")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                // Progress bar
                if document.lastReadCardIndex > 0 {
                    ProgressView(value: document.progress)
                        .tint(.green)
                }
            }
            
            Spacer()
            
            // Continue indicator
            if document.lastReadAt != nil {
                VStack(alignment: .trailing, spacing: 2) {
                    Text("Card \(document.lastReadCardIndex + 1)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding(.vertical, 8)
    }
}
