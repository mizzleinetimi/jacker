//
//  SettingsView.swift
//  Pic2PDF
//

import SwiftUI

struct SettingsView: View {
    @StateObject private var storageManager = StorageManager.shared
    @StateObject private var appState = AppState.shared
    @StateObject private var downloadManager = ModelDownloadManager.shared
    @StateObject private var llmService = OnDeviceLLMService.shared
    
    @AppStorage("huggingFaceToken") private var huggingFaceToken: String = ""
    @State private var showClearDataAlert = false
    @State private var showModelTest = false
    @Environment(\.dismiss) var dismiss

    var body: some View {
        NavigationView {
            List {
                // AI Models Section
                Section {
                    // Model status
                    HStack {
                        Image(systemName: llmService.isInitialized ? "checkmark.circle.fill" : "circle.dashed")
                            .foregroundColor(llmService.isInitialized ? .green : .orange)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(llmService.isInitialized ? "Model Ready" : "Loading...")
                                .font(.subheadline)
                                .fontWeight(.medium)
                            Text(llmService.selectedModel.displayName)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                        if llmService.isInitialized {
                            Button("Test") {
                                showModelTest = true
                            }
                            .font(.subheadline)
                            .buttonStyle(.bordered)
                        }
                    }
                    
                    // Downloaded models
                    ForEach([ModelIdentifier.gemma1B, .gemma2B], id: \.self) { model in
                        SettingsModelRow(model: model, downloadManager: downloadManager, llmService: llmService)
                    }
                } header: {
                    Label("AI Models", systemImage: "cpu")
                } footer: {
                    Text("Models run entirely on-device. Your data never leaves your phone.")
                }
                
                // HuggingFace Token (collapsed)
                Section {
                    DisclosureGroup {
                        VStack(alignment: .leading, spacing: 8) {
                            SecureField("Token", text: $huggingFaceToken)
                                .textFieldStyle(.roundedBorder)
                                .autocapitalization(.none)
                            Text("Get a free token from huggingface.co/settings/tokens")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    } label: {
                        HStack {
                            Image(systemName: huggingFaceToken.isEmpty ? "key" : "key.fill")
                                .foregroundColor(huggingFaceToken.isEmpty ? .secondary : .green)
                            Text("HuggingFace Token")
                            if !huggingFaceToken.isEmpty {
                                Spacer()
                                Text("Set")
                                    .font(.caption)
                                    .foregroundColor(.green)
                            }
                        }
                    }
                }
                
                // Storage
                Section {
                    let stats = storageManager.getStatistics()
                    LabeledContent("Documents", value: "\(stats.totalGenerations)")
                    LabeledContent("Storage", value: stats.formattedStorage)
                    
                    Button(role: .destructive) {
                        showClearDataAlert = true
                    } label: {
                        Label("Clear All Data", systemImage: "trash")
                    }
                } header: {
                    Label("Storage", systemImage: "internaldrive")
                }
                
                // About
                Section {
                    LabeledContent("Version", value: "1.0.0")
                    
                    Link(destination: URL(string: "https://github.com/youneslaaroussi/Pic2PDF")!) {
                        HStack {
                            Label("Source Code", systemImage: "chevron.left.forwardslash.chevron.right")
                            Spacer()
                            Image(systemName: "arrow.up.right")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    
                    Link(destination: URL(string: "https://github.com/youneslaaroussi/Pic2PDF/blob/main/PRIVACY.md")!) {
                        HStack {
                            Label("Privacy Policy", systemImage: "hand.raised")
                            Spacer()
                            Image(systemName: "arrow.up.right")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    
                    Button {
                        dismiss()
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                            appState.restartOnboarding()
                        }
                    } label: {
                        Label("View Tutorial", systemImage: "questionmark.circle")
                    }
                } header: {
                    Label("About", systemImage: "info.circle")
                } footer: {
                    Text("Built for Arm AI Developer Challenge 2025")
                        .frame(maxWidth: .infinity)
                        .padding(.top, 8)
                }
            }
            .navigationTitle("Settings")
            .sheet(isPresented: $showModelTest) {
                ModelTestView()
            }
            .alert("Clear All Data?", isPresented: $showClearDataAlert) {
                Button("Cancel", role: .cancel) {}
                Button("Delete", role: .destructive) {
                    try? storageManager.clearAllData()
                }
            } message: {
                Text("This will delete all saved documents and cannot be undone.")
            }
        }
    }
}

// MARK: - Settings Model Row
struct SettingsModelRow: View {
    let model: ModelIdentifier
    @ObservedObject var downloadManager: ModelDownloadManager
    @ObservedObject var llmService: OnDeviceLLMService

    private var isDownloaded: Bool { downloadManager.isModelDownloaded(model) }
    private var isDownloading: Bool {
        downloadManager.currentDownloadingModel == model && downloadManager.downloadStatus.isInProgress
    }
    private var isActive: Bool { llmService.selectedModel == model && llmService.isInitialized }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(model.displayName)
                            .font(.subheadline)
                        if isActive {
                            Text("Active")
                                .font(.caption2)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.blue.opacity(0.2))
                                .foregroundColor(.blue)
                                .cornerRadius(4)
                        }
                    }
                    Text(statusText)
                        .font(.caption)
                        .foregroundColor(statusColor)
                }

                Spacer()

                if isDownloading {
                    Button("Cancel") {
                        downloadManager.cancelDownload()
                    }
                    .font(.caption)
                    .buttonStyle(.bordered)
                    .tint(.red)
                } else if isDownloaded {
                    if !isActive {
                        Button("Use") {
                            Task { await llmService.switchModel(to: model) }
                        }
                        .font(.caption)
                        .buttonStyle(.bordered)
                    } else {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                    }
                } else {
                    Button("Download") {
                        Task { try? await downloadManager.downloadModel(model) }
                    }
                    .font(.caption)
                    .buttonStyle(.borderedProminent)
                }
            }

            // Download progress bar
            if isDownloading, case .downloading(let progress, let downloaded, let total) = downloadManager.downloadStatus {
                VStack(spacing: 4) {
                    ProgressView(value: progress)
                        .tint(.blue)
                    HStack {
                        Text(formatBytes(downloaded))
                            .font(.caption2)
                            .foregroundColor(.secondary)
                        Spacer()
                        if downloadManager.downloadSpeed > 0 {
                            Text("\(String(format: "%.1f", downloadManager.downloadSpeed)) MB/s")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                        Text(formatBytes(total))
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
            }
        }
        .padding(.vertical, 4)
    }

    private var statusText: String {
        if isDownloading, case .downloading(let progress, _, _) = downloadManager.downloadStatus {
            return "Downloading... \(Int(progress * 100))%"
        }
        if isDownloaded {
            if let size = downloadManager.modelSize(model) {
                return "\(String(format: "%.0f", size)) MB • Ready"
            }
            return "Ready"
        }
        let expected = DownloadableModelConfig.availableModels[model]?.expectedSizeMB ?? 0
        return "~\(String(format: "%.0f", expected)) MB"
    }

    private var statusColor: Color {
        if isDownloading { return .blue }
        if isDownloaded { return .green }
        return .secondary
    }

    private func formatBytes(_ bytes: Int64) -> String {
        let mb = Double(bytes) / (1024 * 1024)
        if mb >= 1024 {
            return String(format: "%.1f GB", mb / 1024)
        }
        return String(format: "%.0f MB", mb)
    }
}

// MARK: - Model Test View (Chat)
struct ModelTestView: View {
    @StateObject private var llmService = OnDeviceLLMService.shared
    @State private var messages: [TestMessage] = []
    @State private var inputText = ""
    @State private var isGenerating = false
    @State private var streamingResponse = ""
    @State private var currentTask: Task<Void, Never>?
    @Environment(\.dismiss) var dismiss

    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // Model info bar
                HStack {
                    Image(systemName: "cpu")
                        .foregroundColor(.blue)
                    Text(llmService.selectedModel.displayName)
                        .font(.subheadline)
                        .fontWeight(.medium)
                    Spacer()
                    Circle()
                        .fill(llmService.isInitialized ? Color.green : Color.orange)
                        .frame(width: 8, height: 8)
                    Text(llmService.isInitialized ? "Ready" : "Loading")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal)
                .padding(.vertical, 10)
                .background(Color(.systemGray6))

                // Messages
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 12) {
                            if messages.isEmpty && !isGenerating {
                                // Welcome
                                VStack(spacing: 16) {
                                    Image(systemName: "bubble.left.and.bubble.right.fill")
                                        .font(.system(size: 50))
                                        .foregroundColor(.blue.opacity(0.6))
                                    Text("Test Your Model")
                                        .font(.title2)
                                        .fontWeight(.bold)
                                    Text("Send a message to verify the AI model is working correctly.")
                                        .font(.subheadline)
                                        .foregroundColor(.secondary)
                                        .multilineTextAlignment(.center)
                                        .padding(.horizontal, 40)
                                }
                                .padding(.top, 60)
                            }

                            ForEach(messages) { msg in
                                TestBubble(message: msg)
                                    .id(msg.id)
                            }

                            // Streaming response
                            if isGenerating && !streamingResponse.isEmpty {
                                TestBubble(message: TestMessage(content: streamingResponse, isUser: false))
                                    .id("streaming")
                            }

                            // Typing indicator
                            if isGenerating && streamingResponse.isEmpty {
                                HStack {
                                    HStack(spacing: 4) {
                                        ForEach(0..<3, id: \.self) { _ in
                                            Circle()
                                                .fill(Color.gray)
                                                .frame(width: 8, height: 8)
                                        }
                                    }
                                    .padding(.horizontal, 14)
                                    .padding(.vertical, 12)
                                    .background(Color(.systemGray5))
                                    .cornerRadius(18)
                                    Spacer()
                                }
                                .id("typing")
                            }
                        }
                        .padding()
                    }
                    .onChange(of: messages.count) { _, _ in
                        if let lastId = messages.last?.id {
                            withAnimation { proxy.scrollTo(lastId, anchor: .bottom) }
                        }
                    }
                    .onChange(of: streamingResponse) { _, _ in
                        withAnimation { proxy.scrollTo("streaming", anchor: .bottom) }
                    }
                }

                Divider()

                // Input
                HStack(spacing: 12) {
                    TextField("Type a message...", text: $inputText, axis: .vertical)
                        .textFieldStyle(.plain)
                        .lineLimit(1...4)
                        .disabled(isGenerating || !llmService.isInitialized)

                    Button(action: isGenerating ? stopGeneration : sendMessage) {
                        Image(systemName: isGenerating ? "stop.circle.fill" : "arrow.up.circle.fill")
                            .font(.system(size: 32))
                            .foregroundColor(canSend || isGenerating ? .blue : .gray)
                    }
                    .disabled(!canSend && !isGenerating)
                }
                .padding()
                .background(Color(.systemBackground))
            }
            .navigationTitle("Test Model")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Done") { dismiss() }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        messages.removeAll()
                        streamingResponse = ""
                    } label: {
                        Image(systemName: "trash")
                    }
                    .disabled(messages.isEmpty)
                }
            }
        }
    }

    private var canSend: Bool {
        !inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && llmService.isInitialized && !isGenerating
    }

    private func sendMessage() {
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }

        // Add user message
        messages.append(TestMessage(content: text, isUser: true))
        inputText = ""
        isGenerating = true
        streamingResponse = ""

        currentTask = Task {
            do {
                let prompt = "<start_of_turn>user\n\(text)<end_of_turn>\n<start_of_turn>model\n"
                let result = try await llmService.generateChatResponse(prompt: prompt) { partial in
                    Task { @MainActor in
                        streamingResponse = partial
                    }
                }
                await MainActor.run {
                    messages.append(TestMessage(content: result, isUser: false))
                    streamingResponse = ""
                    isGenerating = false
                }
            } catch {
                await MainActor.run {
                    messages.append(TestMessage(content: "Error: \(error.localizedDescription)", isUser: false))
                    streamingResponse = ""
                    isGenerating = false
                }
            }
        }
    }

    private func stopGeneration() {
        currentTask?.cancel()
        if !streamingResponse.isEmpty {
            messages.append(TestMessage(content: streamingResponse, isUser: false))
        }
        streamingResponse = ""
        isGenerating = false
    }
}

// Simple message model for test chat
struct TestMessage: Identifiable {
    let id = UUID()
    let content: String
    let isUser: Bool
}

// Chat bubble for test view
struct TestBubble: View {
    let message: TestMessage

    var body: some View {
        HStack {
            if message.isUser { Spacer(minLength: 60) }
            Text(message.content)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(message.isUser ? Color.blue : Color(.systemGray5))
                .foregroundColor(message.isUser ? .white : .primary)
                .cornerRadius(18)
            if !message.isUser { Spacer(minLength: 60) }
        }
    }
}

#Preview {
    SettingsView()
}
