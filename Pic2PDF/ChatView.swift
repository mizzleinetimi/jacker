//
//  ChatView.swift
//  Pic2PDF
//
//  Chat interface for text conversations with the on-device AI model
//

import SwiftUI

struct ChatMessage: Identifiable, Equatable {
    let id = UUID()
    let content: String
    let isUser: Bool
    let timestamp: Date
    
    static func == (lhs: ChatMessage, rhs: ChatMessage) -> Bool {
        lhs.id == rhs.id
    }
}

struct ChatView: View {
    @StateObject private var llmService = OnDeviceLLMService.shared
    @StateObject private var downloadManager = ModelDownloadManager.shared
    @State private var messages: [ChatMessage] = []
    @State private var inputText: String = ""
    @State private var isGenerating: Bool = false
    @State private var streamingResponse: String = ""
    @State private var pendingSendTask: Task<Void, Never>?
    @State private var showModelPicker: Bool = false
    @FocusState private var isInputFocused: Bool
    
    private var availableTextModels: [ModelIdentifier] {
        // Only show text-only models that are downloaded
        [.gemma270M, .gemma1B].filter { downloadManager.isModelDownloaded($0) }
    }
    
    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // Model indicator bar
                if !availableTextModels.isEmpty {
                    HStack {
                        Image(systemName: "cpu")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text("Model: \(llmService.selectedModel.displayName)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Spacer()
                        if availableTextModels.count > 1 {
                            Button("Switch") {
                                showModelPicker = true
                            }
                            .font(.caption)
                        }
                    }
                    .padding(.horizontal)
                    .padding(.vertical, 6)
                    .background(Color(.systemGray6))
                }
                
                // Chat messages
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 12) {
                            // Welcome message if empty
                            if messages.isEmpty && !isGenerating {
                                WelcomeCard()
                                    .padding(.top, 40)
                            }
                            
                            ForEach(messages) { message in
                                ChatBubble(message: message)
                                    .id(message.id)
                            }
                            
                            // Streaming response
                            if isGenerating && !streamingResponse.isEmpty {
                                ChatBubble(message: ChatMessage(
                                    content: streamingResponse,
                                    isUser: false,
                                    timestamp: Date()
                                ))
                                .id("streaming")
                            }
                            
                            // Typing indicator
                            if isGenerating && streamingResponse.isEmpty {
                                TypingIndicator()
                                    .id("typing")
                            }
                        }
                        .padding()
                    }
                    .onChange(of: messages.count) { _, _ in
                        scrollToBottom(proxy: proxy)
                    }
                    .onChange(of: streamingResponse) { _, _ in
                        scrollToBottom(proxy: proxy)
                    }
                }
                
                Divider()
                
                // Input area
                HStack(spacing: 12) {
                    TextField("Ask anything...", text: $inputText, axis: .vertical)
                        .textFieldStyle(.plain)
                        .lineLimit(1...5)
                        .focused($isInputFocused)
                        .disabled(isGenerating || !llmService.isInitialized)
                    
                    Button(action: sendMessage) {
                        Image(systemName: isGenerating ? "stop.circle.fill" : "arrow.up.circle.fill")
                            .font(.system(size: 32))
                            .foregroundColor(canSend ? .blue : .gray)
                    }
                    .disabled(!canSend && !isGenerating)
                }
                .padding()
                .background(Color(.systemBackground))
            }
            .navigationTitle("Chat")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Menu {
                        Button(action: clearChat) {
                            Label("Clear Chat", systemImage: "trash")
                        }
                        
                        if !llmService.isInitialized {
                            Button(action: {
                                Task { await llmService.initializeModel() }
                            }) {
                                Label("Initialize Model", systemImage: "arrow.clockwise")
                            }
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
            }
            .overlay {
                if !llmService.isInitialized {
                    ModelNotReadyOverlay()
                }
            }
            .sheet(isPresented: $showModelPicker) {
                ModelPickerSheet(
                    availableModels: availableTextModels,
                    currentModel: llmService.selectedModel,
                    onSelect: { model in
                        Task {
                            await llmService.switchModel(to: model)
                        }
                        showModelPicker = false
                    }
                )
                .presentationDetents([.medium])
            }
        }
    }
    
    private var canSend: Bool {
        !inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && 
        llmService.isInitialized && 
        !isGenerating
    }
    
    private func scrollToBottom(proxy: ScrollViewProxy) {
        withAnimation(.easeOut(duration: 0.2)) {
            if isGenerating {
                proxy.scrollTo("streaming", anchor: .bottom)
            } else if let lastMessage = messages.last {
                proxy.scrollTo(lastMessage.id, anchor: .bottom)
            }
        }
    }
    
    private func sendMessage() {
        if isGenerating {
            // Stop generation
            isGenerating = false
            if !streamingResponse.isEmpty {
                messages.append(ChatMessage(content: streamingResponse, isUser: false, timestamp: Date()))
                streamingResponse = ""
            }
            return
        }
        
        let userMessage = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !userMessage.isEmpty else { return }
        
        // Add user message
        messages.append(ChatMessage(content: userMessage, isUser: true, timestamp: Date()))
        inputText = ""
        isInputFocused = false
        
        // Generate response with light batching to allow rapid edits
        pendingSendTask?.cancel()
        pendingSendTask = Task {
            try? await Task.sleep(nanoseconds: 100_000_000)
            await generateResponse(to: userMessage)
            await MainActor.run {
                pendingSendTask = nil
            }
        }
    }
    
    private func generateResponse(to prompt: String) async {
        await MainActor.run {
            isGenerating = true
            streamingResponse = ""
        }
        
        do {
            // Build conversation history for context (last 6 messages max to fit in context window)
            let contextPrompt = buildConversationPrompt(newMessage: prompt)
            
            let response = try await llmService.generateChatResponse(prompt: contextPrompt) { partialResponse in
                Task { @MainActor in
                    streamingResponse = partialResponse
                }
            }
            
            await MainActor.run {
                messages.append(ChatMessage(content: response, isUser: false, timestamp: Date()))
                streamingResponse = ""
                isGenerating = false
            }
        } catch {
            await MainActor.run {
                let errorMessage = "Sorry, I encountered an error: \(error.localizedDescription)"
                messages.append(ChatMessage(content: errorMessage, isUser: false, timestamp: Date()))
                streamingResponse = ""
                isGenerating = false
            }
        }
    }
    
    /// Build a prompt that includes conversation history for context
    /// Uses Gemma's chat format: <start_of_turn>user\n...<end_of_turn>\n<start_of_turn>model\n
    private func buildConversationPrompt(newMessage: String) -> String {
        var prompt = ""
        
        // Include last 4 messages for context (2 exchanges) - keep it short for 1B model
        let recentMessages = messages.suffix(4)
        for msg in recentMessages {
            if msg.isUser {
                prompt += "<start_of_turn>user\n\(msg.content)<end_of_turn>\n"
            } else {
                prompt += "<start_of_turn>model\n\(msg.content)<end_of_turn>\n"
            }
        }
        
        // Add the new user message
        prompt += "<start_of_turn>user\n\(newMessage)<end_of_turn>\n<start_of_turn>model\n"
        return prompt
    }
    
    private func clearChat() {
        messages.removeAll()
        streamingResponse = ""
    }
}

// MARK: - Chat Bubble
struct ChatBubble: View {
    let message: ChatMessage
    
    var body: some View {
        HStack {
            if message.isUser { Spacer(minLength: 60) }
            
            VStack(alignment: message.isUser ? .trailing : .leading, spacing: 4) {
                Text(message.content)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(message.isUser ? Color.blue : Color(.systemGray5))
                    .foregroundColor(message.isUser ? .white : .primary)
                    .cornerRadius(18)
                
                Text(message.timestamp, style: .time)
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            
            if !message.isUser { Spacer(minLength: 60) }
        }
    }
}

// MARK: - Welcome Card
struct WelcomeCard: View {
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "bubble.left.and.bubble.right.fill")
                .font(.system(size: 50))
                .foregroundColor(.blue.opacity(0.7))
            
            Text("Chat with AI")
                .font(.title2)
                .fontWeight(.bold)
            
            Text("Ask questions, get help with math, or have a conversation. All processing happens on-device.")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
            
            // Suggestion chips
            VStack(spacing: 8) {
                Text("Try asking:")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                FlowLayout(spacing: 8) {
                    SuggestionChip(text: "Explain quadratic equations")
                    SuggestionChip(text: "What is calculus?")
                    SuggestionChip(text: "Help me with fractions")
                    SuggestionChip(text: "What is pi?")
                }
            }
            .padding(.top, 8)
        }
        .padding()
    }
}

struct SuggestionChip: View {
    let text: String
    
    var body: some View {
        Text(text)
            .font(.caption)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Color.blue.opacity(0.1))
            .foregroundColor(.blue)
            .cornerRadius(16)
    }
}

// Simple flow layout for suggestion chips
struct FlowLayout: Layout {
    var spacing: CGFloat = 8
    
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = FlowResult(in: proposal.width ?? 0, subviews: subviews, spacing: spacing)
        return result.size
    }
    
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = FlowResult(in: bounds.width, subviews: subviews, spacing: spacing)
        for (index, subview) in subviews.enumerated() {
            subview.place(at: CGPoint(x: bounds.minX + result.positions[index].x,
                                      y: bounds.minY + result.positions[index].y),
                         proposal: .unspecified)
        }
    }
    
    struct FlowResult {
        var size: CGSize = .zero
        var positions: [CGPoint] = []
        
        init(in maxWidth: CGFloat, subviews: Subviews, spacing: CGFloat) {
            var x: CGFloat = 0
            var y: CGFloat = 0
            var rowHeight: CGFloat = 0
            
            for subview in subviews {
                let size = subview.sizeThatFits(.unspecified)
                if x + size.width > maxWidth && x > 0 {
                    x = 0
                    y += rowHeight + spacing
                    rowHeight = 0
                }
                positions.append(CGPoint(x: x, y: y))
                rowHeight = max(rowHeight, size.height)
                x += size.width + spacing
            }
            
            self.size = CGSize(width: maxWidth, height: y + rowHeight)
        }
    }
}

// MARK: - Typing Indicator
struct TypingIndicator: View {
    @State private var animationOffset: CGFloat = 0
    
    var body: some View {
        HStack {
            HStack(spacing: 4) {
                ForEach(0..<3) { index in
                    Circle()
                        .fill(Color.gray)
                        .frame(width: 8, height: 8)
                        .offset(y: animationOffset(for: index))
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(Color(.systemGray5))
            .cornerRadius(18)
            
            Spacer()
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 0.6).repeatForever()) {
                animationOffset = 1
            }
        }
    }
    
    private func animationOffset(for index: Int) -> CGFloat {
        let delay = Double(index) * 0.2
        return sin((animationOffset + CGFloat(delay)) * .pi) * 4
    }
}

// MARK: - Model Not Ready Overlay
struct ModelNotReadyOverlay: View {
    var body: some View {
        VStack(spacing: 16) {
            ProgressView()
                .scaleEffect(1.5)
            
            Text("Loading AI Model...")
                .font(.headline)
            
            Text("Please wait for the model to initialize")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemBackground).opacity(0.9))
    }
}

// MARK: - Model Picker Sheet
struct ModelPickerSheet: View {
    let availableModels: [ModelIdentifier]
    let currentModel: ModelIdentifier
    let onSelect: (ModelIdentifier) -> Void
    @Environment(\.dismiss) var dismiss
    
    var body: some View {
        NavigationView {
            List {
                Section {
                    ForEach(availableModels, id: \.self) { model in
                        Button(action: { onSelect(model) }) {
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(model.displayName)
                                        .font(.headline)
                                        .foregroundColor(.primary)
                                    Text(modelDescription(for: model))
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                                Spacer()
                                if model == currentModel {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundColor(.blue)
                                }
                            }
                            .padding(.vertical, 4)
                        }
                    }
                } header: {
                    Text("Select Chat Model")
                } footer: {
                    Text("Smaller models are faster but may be less accurate. The 270M model is optimized for quick responses.")
                }
            }
            .navigationTitle("Chat Model")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
    
    private func modelDescription(for model: ModelIdentifier) -> String {
        switch model {
        case .gemma270M:
            return "Ultra-fast, ~290MB • Best for quick chats & grading"
        case .gemma1B:
            return "Balanced, ~529MB • Better reasoning"
        case .gemma2B:
            return "Vision-capable, ~3GB • Image understanding"
        case .gemma4B:
            return "Most capable, ~4.5GB • Best quality"
        }
    }
}

#Preview {
    ChatView()
}
