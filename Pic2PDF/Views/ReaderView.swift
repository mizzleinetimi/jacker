//
//  ReaderView.swift
//  Pic2PDF
//
//  Swipeable card reader for documents
//

import SwiftUI

struct ReaderView: View {
    let document: Document
    
    @StateObject private var documentManager = DocumentManager.shared
    @State private var currentIndex: Int
    @State private var orderedCards: [Card]
    @State private var showOriginal = false
    @State private var showImage = false
    @State private var dragOffset: CGFloat = 0
    @Environment(\.dismiss) private var dismiss
    
    init(document: Document) {
        self.document = document
        let sorted = document.cards.sorted { $0.index < $1.index }
        _orderedCards = State(initialValue: sorted)
        let safeIndex = min(max(document.lastReadCardIndex, 0), max(sorted.count - 1, 0))
        _currentIndex = State(initialValue: safeIndex)
    }
    
    private var currentCard: Card? {
        guard currentIndex < orderedCards.count else { return nil }
        return orderedCards[currentIndex]
    }
    
    var body: some View {
        ZStack {
            // Background
            Color(.systemBackground)
                .ignoresSafeArea()
            
            VStack(spacing: 0) {
                // Progress header
                progressHeader
                
                // Card content with swipe animation
                if let card = currentCard {
                    cardContent(card)
                        .offset(x: dragOffset)
                        .gesture(swipeGesture)
                } else {
                    Text("No cards available")
                        .foregroundColor(.secondary)
                }
                
                // Navigation controls
                navigationControls
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text(document.title)
                    .font(.headline)
                    .lineLimit(1)
            }
        }
        .onAppear {
            orderedCards = document.cards.sorted { $0.index < $1.index }
            // Simplify current card if needed
            if let card = currentCard {
                Task { await documentManager.simplifyCard(card) }
            }
        }
        .onChange(of: currentIndex) { _, newIndex in
            // Save progress and simplify next card
            documentManager.updateReadingProgress(document, cardIndex: newIndex)
            if let card = currentCard {
                Task { await documentManager.simplifyCard(card) }
            }
            // Pre-simplify next card
            if newIndex + 1 < orderedCards.count {
                Task { await documentManager.simplifyCard(orderedCards[newIndex + 1]) }
            }
        }
    }
    
    // MARK: - Swipe Gesture
    
    private var swipeGesture: some Gesture {
        DragGesture(minimumDistance: 10)
            .onChanged { value in
                dragOffset = value.translation.width
            }
            .onEnded { value in
                let threshold: CGFloat = 50
                let velocity = value.predictedEndTranslation.width - value.translation.width
                
                // Quick swipe detection - lower thresholds for snappier feel
                if value.translation.width < -threshold || velocity < -50 {
                    swipeToNext()
                } else if value.translation.width > threshold || velocity > 50 {
                    swipeToPrevious()
                } else {
                    // Snap back instantly
                    withAnimation(.interactiveSpring(response: 0.15, dampingFraction: 0.8)) {
                        dragOffset = 0
                    }
                }
            }
    }
    
    private func swipeToNext() {
        guard currentIndex < orderedCards.count - 1 else {
            // Bounce at end
            withAnimation(.interactiveSpring(response: 0.15, dampingFraction: 0.5)) {
                dragOffset = 0
            }
            UIImpactFeedbackGenerator(style: .rigid).impactOccurred()
            return
        }
        
        // Instant card change with quick slide
        withAnimation(.easeOut(duration: 0.12)) {
            dragOffset = -UIScreen.main.bounds.width
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            dragOffset = 0
            currentIndex += 1
            showOriginal = false
            showImage = false
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        }
    }
    
    private func swipeToPrevious() {
        guard currentIndex > 0 else {
            // Bounce at start
            withAnimation(.interactiveSpring(response: 0.15, dampingFraction: 0.5)) {
                dragOffset = 0
            }
            UIImpactFeedbackGenerator(style: .rigid).impactOccurred()
            return
        }
        
        // Instant card change with quick slide
        withAnimation(.easeOut(duration: 0.12)) {
            dragOffset = UIScreen.main.bounds.width
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            dragOffset = 0
            currentIndex -= 1
            showOriginal = false
            showImage = false
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        }
    }
    
    // MARK: - Progress Header
    
    private var progressHeader: some View {
        VStack(spacing: 8) {
            // Progress bar
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Rectangle()
                        .fill(Color.gray.opacity(0.2))
                        .frame(height: 4)
                    
                    Rectangle()
                        .fill(Color.blue)
                        .frame(width: geometry.size.width * CGFloat(currentIndex + 1) / CGFloat(max(orderedCards.count, 1)), height: 4)
                }
            }
            .frame(height: 4)
            
            // Card counter
            HStack {
                Text("Card \(currentIndex + 1) of \(orderedCards.count)")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                Spacer()
                
                if let card = currentCard, let pageNum = card.pageNumber {
                    Text("Page \(pageNum)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding(.horizontal)
        .padding(.top, 8)
    }
    
    // MARK: - Card Content
    
    private func cardContent(_ card: Card) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // View toggle
                viewToggle(card)
                
                // Main content
                if showImage, let imageData = card.sourceImageData, let image = UIImage(data: imageData) {
                    // Show original image
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .cornerRadius(12)
                } else if showOriginal {
                    // Show original text
                    Text(card.originalText)
                        .font(.body)
                        .foregroundColor(.primary)
                } else {
                    // Show simplified text
                    simplifiedContent(card)
                }
                
                Spacer(minLength: 100)
            }
            .padding()
        }
    }
    
    private func viewToggle(_ card: Card) -> some View {
        HStack(spacing: 12) {
            Button(action: { showOriginal = false; showImage = false }) {
                Text("Simple")
                    .font(.subheadline)
                    .fontWeight(showOriginal || showImage ? .regular : .semibold)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(showOriginal || showImage ? Color.clear : Color.blue)
                    .foregroundColor(showOriginal || showImage ? .secondary : .white)
                    .cornerRadius(20)
            }
            
            Button(action: { showOriginal = true; showImage = false }) {
                Text("Original")
                    .font(.subheadline)
                    .fontWeight(showOriginal && !showImage ? .semibold : .regular)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(showOriginal && !showImage ? Color.blue : Color.clear)
                    .foregroundColor(showOriginal && !showImage ? .white : .secondary)
                    .cornerRadius(20)
            }
            
            if card.sourceImageData != nil {
                Button(action: { showImage = true; showOriginal = false }) {
                    Text("Image")
                        .font(.subheadline)
                        .fontWeight(showImage ? .semibold : .regular)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(showImage ? Color.blue : Color.clear)
                        .foregroundColor(showImage ? .white : .secondary)
                        .cornerRadius(20)
                }
            }
            
            Spacer()
        }
        .padding(.vertical, 8)
        .background(Color(.systemGray6))
        .cornerRadius(25)
    }
    
    private func simplifiedContent(_ card: Card) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            switch card.status {
            case .raw, .processing:
                // Loading state
                VStack(spacing: 12) {
                    ProgressView()
                    Text("Simplifying...")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 40)
                
            case .ready:
                // Simplified text
                Text(card.simplifiedText ?? card.originalText)
                    .font(.system(size: 18))
                    .lineSpacing(8)
                
            case .failed:
                // Show original on failure
                Text(card.originalText)
                    .font(.body)
                
                Text("(Could not simplify this section)")
                    .font(.caption)
                    .foregroundColor(.orange)
            }
        }
    }
    
    // MARK: - Navigation Controls
    
    private var navigationControls: some View {
        HStack(spacing: 40) {
            Button(action: goToPrevious) {
                Image(systemName: "chevron.left.circle.fill")
                    .font(.system(size: 50))
                    .foregroundColor(currentIndex > 0 ? .blue : .gray.opacity(0.3))
            }
            .disabled(currentIndex == 0)
            
            Button(action: goToNext) {
                Image(systemName: "chevron.right.circle.fill")
                    .font(.system(size: 50))
                    .foregroundColor(currentIndex < orderedCards.count - 1 ? .blue : .gray.opacity(0.3))
            }
            .disabled(currentIndex >= orderedCards.count - 1)
        }
        .padding(.vertical, 20)
        .background(Color(.systemBackground))
    }
    
    // MARK: - Navigation (for button taps)
    
    private func goToNext() {
        guard currentIndex < orderedCards.count - 1 else { return }
        currentIndex += 1
        showOriginal = false
        showImage = false
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }
    
    private func goToPrevious() {
        guard currentIndex > 0 else { return }
        currentIndex -= 1
        showOriginal = false
        showImage = false
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }
}
