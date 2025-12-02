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
    
    // View Mode State (Persistent)
    enum ViewMode {
        case simple
        case original
        case image
    }
    @State private var viewMode: ViewMode = .original // Default to Original
    
    @State private var dragOffset: CGFloat = 0
    @State private var showControls = false
    @AppStorage("selectedReadingTheme") private var selectedTheme: Theme.ReadingTheme = .paper
    @State private var showPageCount = false // Transient overlay
    
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    
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
    
    // Dynamic theme colors based on selection or system
    private var currentTheme: Theme.ReadingTheme {
        // If system is dark mode and we are in paper/default, switch to midnight
        if colorScheme == .dark && selectedTheme == .paper {
            return .midnight
        }
        return selectedTheme
    }
    
    var body: some View {
        ZStack {
            // 1. Fixed Background
            currentTheme.background
                .ignoresSafeArea()
                .onTapGesture {
                    withAnimation {
                        showControls.toggle()
                    }
                }
            
            // 2. Centered Card
            GeometryReader { geometry in
                VStack {
                    Spacer()
                    
                    if let card = currentCard {
                        cardContainer(card, size: geometry.size)
                            .offset(x: dragOffset)
                            .onTapGesture {
                                withAnimation {
                                    showControls.toggle()
                                }
                            }
                            .gesture(swipeGesture)
                    } else {
                        Text("No cards available")
                            .font(Theme.uiFont())
                            .foregroundColor(currentTheme.secondaryText)
                    }
                    
                    Spacer()
                }
                .frame(width: geometry.size.width, height: geometry.size.height)
            }
            .ignoresSafeArea()
            
            // 3. Transient Page Count Overlay
            if showPageCount {
                VStack {
                    Spacer()
                    Text("\(currentIndex + 1) / \(orderedCards.count)")
                        .font(Theme.uiFont(size: 14, weight: .medium))
                        .foregroundColor(Theme.secondaryText) // Use global secondary text for visibility
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(Theme.secondaryBackground.opacity(0.9))
                        .cornerRadius(20)
                        .calmShadow()
                        .padding(.bottom, 100)
                        .transition(.opacity)
                }
                .zIndex(100)
            }
            
            // 4. Overlays (Controls)
            VStack {
                if showControls {
                    topBar
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
                
                Spacer()
                
                // Bottom controls (if any, currently empty/minimal)
            }
        }
        .navigationBarHidden(true)
        .toolbar(.hidden, for: .navigationBar)
        .toolbar(showControls ? .visible : .hidden, for: .tabBar)
        .statusBar(hidden: !showControls)
        .onAppear {
            orderedCards = document.cards.sorted { $0.index < $1.index }
            if let card = currentCard {
                Task { await documentManager.simplifyCard(card) }
            }
        }
        .onChange(of: currentIndex) { _, newIndex in
            documentManager.updateReadingProgress(document, cardIndex: newIndex)
            if let card = currentCard {
                Task { await documentManager.simplifyCard(card) }
            }
            if newIndex + 1 < orderedCards.count {
                Task { await documentManager.simplifyCard(orderedCards[newIndex + 1]) }
            }
            
            // Show transient page count
            withAnimation { showPageCount = true }
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                withAnimation { showPageCount = false }
            }
        }
    }
    
    // MARK: - Card Container
    
    private func cardContainer(_ card: Card, size: CGSize) -> some View {
        let cardWidth = min(size.width - 32, 600) // Max width 600
        let cardHeight = size.height - 230 // Fixed stable height (accommodates bars)
        
        return ZStack {
            // Card Background
            currentTheme.background
                .brightness(colorScheme == .dark ? 0.05 : -0.02) // Slight contrast from bg
                .cornerRadius(24)
                .shadow(color: Color.black.opacity(0.1), radius: 15, x: 0, y: 5)
            
            // Static Content (No ScrollView)
            VStack(alignment: .leading, spacing: 24) {
                if viewMode == .image, let imageData = card.sourceImageData, let image = UIImage(data: imageData) {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .cornerRadius(12)
                } else if viewMode == .original {
                    Text(card.originalText)
                        .font(Theme.readingFont(size: 22))
                        .foregroundColor(currentTheme.text)
                        .lineSpacing(10)
                        .minimumScaleFactor(0.5) // Scale down to fit
                } else {
                    simplifiedContent(card)
                }
            }
            .padding(32)
            .frame(width: cardWidth, height: cardHeight, alignment: .topLeading)
        }
        .frame(width: cardWidth, height: cardHeight)
    }
    
    private func simplifiedContent(_ card: Card) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            switch card.status {
            case .raw, .processing:
                HStack {
                    Spacer()
                    ProgressView()
                        .tint(currentTheme.secondaryText)
                    Text("Simplifying...")
                        .font(Theme.uiFont(size: 14))
                        .foregroundColor(currentTheme.secondaryText)
                    Spacer()
                }
                .padding(.vertical, 40)
                
            case .ready:
                Text(card.simplifiedText ?? card.originalText)
                    .font(Theme.readingFont(size: 24))
                    .foregroundColor(currentTheme.text)
                    .lineSpacing(14)
                    .minimumScaleFactor(0.5) // Scale down to fit
                
            case .failed:
                Text(card.originalText)
                    .font(Theme.readingFont(size: 22))
                    .foregroundColor(currentTheme.text)
                    .lineSpacing(10)
                    .minimumScaleFactor(0.5)
                
                Text("(Could not simplify this section)")
                    .font(Theme.uiFont(size: 12))
                    .foregroundColor(Theme.accent)
                    .padding(.top, 8)
                
                Button(action: {
                    Task { await documentManager.simplifyCard(card, force: true) }
                }) {
                    Label("Retry", systemImage: "arrow.clockwise")
                        .font(Theme.uiFont(size: 14))
                        .foregroundColor(Theme.accent)
                        .padding(.vertical, 8)
                }
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
                
                if value.translation.width < -threshold || velocity < -50 {
                    swipeToNext()
                } else if value.translation.width > threshold || velocity > 50 {
                    swipeToPrevious()
                } else {
                    withAnimation(.interactiveSpring(response: 0.15, dampingFraction: 0.8)) {
                        dragOffset = 0
                    }
                }
            }
    }
    
    private func swipeToNext() {
        guard currentIndex < orderedCards.count - 1 else {
            withAnimation(.interactiveSpring(response: 0.15, dampingFraction: 0.5)) {
                dragOffset = 0
            }
            UIImpactFeedbackGenerator(style: .rigid).impactOccurred()
            return
        }
        
        withAnimation(.easeOut(duration: 0.15)) {
            dragOffset = -UIScreen.main.bounds.width
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            dragOffset = 0
            currentIndex += 1
            // View mode persists
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        }
    }
    
    private func swipeToPrevious() {
        guard currentIndex > 0 else {
            withAnimation(.interactiveSpring(response: 0.15, dampingFraction: 0.5)) {
                dragOffset = 0
            }
            UIImpactFeedbackGenerator(style: .rigid).impactOccurred()
            return
        }
        
        withAnimation(.easeOut(duration: 0.15)) {
            dragOffset = UIScreen.main.bounds.width
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            dragOffset = 0
            currentIndex -= 1
            // View mode persists
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        }
    }
    
    // MARK: - Top Bar
    
    private var topBar: some View {
        HStack {
            Button(action: { dismiss() }) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundColor(currentTheme.text)
                    .padding(12)
                    .background(currentTheme.background.opacity(0.9))
                    .clipShape(Circle())
                    .shadow(color: Color.black.opacity(0.1), radius: 4, x: 0, y: 2)
            }
            
            Spacer()
            
            // Theme Selector
            Menu {
                ForEach(Theme.ReadingTheme.allCases) { theme in
                    Button(action: { selectedTheme = theme }) {
                        Label(theme.displayName, systemImage: selectedTheme == theme ? "checkmark" : "")
                    }
                }
            } label: {
                Image(systemName: "textformat.size")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundColor(currentTheme.text)
                    .padding(12)
                    .background(currentTheme.background.opacity(0.9))
                    .clipShape(Circle())
                    .shadow(color: Color.black.opacity(0.1), radius: 4, x: 0, y: 2)
            }

            // View Toggles
            HStack(spacing: 0) {
                viewOption(title: "Simple", mode: .simple)
                viewOption(title: "Original", mode: .original)
                if currentCard?.sourceImageData != nil {
                    viewOption(title: "Image", mode: .image)
                }
            }
            .background(currentTheme.background.opacity(0.9))
            .cornerRadius(20)
            .shadow(color: Color.black.opacity(0.1), radius: 4, x: 0, y: 2)
        }
        .padding(.horizontal)
        .padding(.top, 50)
    }
    
    private func viewOption(title: String, mode: ViewMode) -> some View {
        Button(action: { 
            viewMode = mode 
            if mode == .simple, let card = currentCard, card.status == .failed {
                Task { await documentManager.simplifyCard(card, force: true) }
            }
        }) {
            Text(title)
                .font(Theme.uiFont(size: 14, weight: viewMode == mode ? .semibold : .regular))
                .foregroundColor(viewMode == mode ? currentTheme.text : currentTheme.secondaryText)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(viewMode == mode ? currentTheme.text.opacity(0.05) : Color.clear)
                .cornerRadius(16)
        }
    }
    
    // MARK: - Bottom Bar
    
    private var bottomBar: some View {
        VStack(spacing: 12) {
            // Progress Bar
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(currentTheme.secondaryText.opacity(0.2))
                        .frame(height: 4)
                    
                    Capsule()
                        .fill(Theme.accent)
                        .frame(width: geometry.size.width * CGFloat(currentIndex + 1) / CGFloat(max(orderedCards.count, 1)), height: 4)
                }
            }
            .frame(height: 4)
            .padding(.horizontal, 32)
            
            HStack {
                Text("\(currentIndex + 1) / \(orderedCards.count)")
                    .font(Theme.uiFont(size: 12, weight: .medium))
                    .foregroundColor(currentTheme.secondaryText)
                
                Spacer()
                
                if let card = currentCard, let pageNum = card.pageNumber {
                    Text("Page \(pageNum)")
                        .font(Theme.uiFont(size: 12))
                        .foregroundColor(currentTheme.secondaryText)
                }
            }
            .padding(.horizontal, 32)
            .padding(.bottom, 20)
        }
        .padding(.top, 20)
        .background(
            LinearGradient(
                colors: [currentTheme.background.opacity(0), currentTheme.background],
                startPoint: .top,
                endPoint: .bottom
            )
        )
    }
}
