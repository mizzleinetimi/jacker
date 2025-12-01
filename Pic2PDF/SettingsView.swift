//
//  SettingsView.swift
//  Pic2PDF
//
//  Created by Younes Laaroussi on 2025-10-13.
//

import SwiftUI

struct SettingsView: View {
    @StateObject private var storageManager = StorageManager.shared
    @StateObject private var appState = AppState.shared
    @StateObject private var downloadManager = ModelDownloadManager.shared
    @StateObject private var llmService = OnDeviceLLMService.shared
    @AppStorage("performanceModeEnabled") private var performanceModeEnabled = false
    
    // LLM Parameters
    @AppStorage("llmTemperature") private var temperature: Double = 0.7
    @AppStorage("llmTopP") private var topP: Double = 0.9
    @AppStorage("llmTopK") private var topK: Int = 40
    @AppStorage("llmMaxTokens") private var maxTokens: Int = 2000
    @AppStorage("gradingModelIdentifier") private var gradingModelIdentifierRaw: String = ModelIdentifier.gemma1B.rawValue
    
    @State private var showClearDataAlert = false
    @State private var showResetParamsAlert = false
    @AppStorage("huggingFaceToken") private var huggingFaceToken: String = ""
    @State private var showTokenInfo = false
    @Environment(\.dismiss) var dismiss
    
    var body: some View {
        NavigationView {
            Form {
                // Performance Section
                Section {
                    Toggle("Performance Mode", isOn: $performanceModeEnabled)
                        .tint(.blue)
                    
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Optimizes for speed on ARM devices")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text("- Downscale images more aggressively\n- Lower max tokens\n- Slightly faster sampling")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                    .padding(.top, 2)
                } header: {
                    Text("Performance")
                }
                
                // LLM Parameters Section
                Section {
                    VStack(alignment: .leading, spacing: 12) {
                        // Temperature
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text("Temperature")
                                    .font(.subheadline)
                                Spacer()
                                Text(String(format: "%.2f", temperature))
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                            }
                            Slider(value: $temperature, in: 0.1...1.5, step: 0.05)
                                .tint(.blue)
                            Text("Controls randomness. Lower = more focused, Higher = more creative")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                        
                        Divider()
                        
                        // Top P
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text("Top P (Nucleus Sampling)")
                                    .font(.subheadline)
                                Spacer()
                                Text(String(format: "%.2f", topP))
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                            }
                            Slider(value: $topP, in: 0.1...1.0, step: 0.05)
                                .tint(.blue)
                            Text("Limits token choices by cumulative probability. Lower = more focused")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                        
                        Divider()
                        
                        // Top K
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text("Top K")
                                    .font(.subheadline)
                                Spacer()
                                Text("\(topK)")
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                            }
                            Slider(value: Binding(
                                get: { Double(topK) },
                                set: { topK = Int($0) }
                            ), in: 1...100, step: 1)
                                .tint(.blue)
                            Text("Limits token choices to top K options. Lower = more deterministic")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                        
                        Divider()
                        
                        // Max Tokens
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text("Max Tokens")
                                    .font(.subheadline)
                                Spacer()
                                Text("\(maxTokens)")
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                            }
                            Slider(value: Binding(
                                get: { Double(maxTokens) },
                                set: { maxTokens = Int($0) }
                            ), in: 500...4000, step: 100)
                                .tint(.blue)
                            Text("Maximum output length. Higher = longer documents, more memory")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    }
                    .padding(.vertical, 8)
                    
                    Button(action: { showResetParamsAlert = true }) {
                        HStack {
                            Image(systemName: "arrow.counterclockwise")
                            Text("Reset to Defaults")
                        }
                        .foregroundColor(.blue)
                    }
                } header: {
                    Text("LLM Parameters")
                } footer: {
                    Text("Advanced settings for AI model behavior. Changes take effect on next generation.")
                }
                
                // Storage Section
                Section {
                    let stats = storageManager.getStatistics()
                    
                    HStack {
                        Text("Total Generations")
                        Spacer()
                        Text("\(stats.totalGenerations)")
                            .foregroundColor(.secondary)
                    }
                    
                    HStack {
                        Text("Total Images")
                        Spacer()
                        Text("\(stats.totalImages)")
                            .foregroundColor(.secondary)
                    }
                    
                    HStack {
                        Text("Favorites")
                        Spacer()
                        Text("\(stats.totalFavorites)")
                            .foregroundColor(.secondary)
                    }
                    
                    HStack {
                        Text("Storage Used")
                        Spacer()
                        Text(stats.formattedStorage)
                            .foregroundColor(.secondary)
                    }
                } header: {
                    Text("Storage")
                }
                
                // HuggingFace Token Section (for gated models)
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        SecureField("HuggingFace Token", text: $huggingFaceToken)
                            .textFieldStyle(.roundedBorder)
                            .autocapitalization(.none)
                            .disableAutocorrection(true)
                        
                        Button(action: { showTokenInfo = true }) {
                            HStack {
                                Image(systemName: "info.circle")
                                Text("How to get a token")
                            }
                            .font(.caption)
                        }
                    }
                } header: {
                    Text("HuggingFace Authentication")
                } footer: {
                    Text("Required to download Gemma models. Get a free token from huggingface.co/settings/tokens")
                }
                
                // AI Model Management Section
                Section {
                    // Model Selector Dropdown
                    if ModelIdentifier.allCases.contains(where: { downloadManager.isModelDownloaded($0) }) {
                        Picker("Current Model", selection: Binding(
                            get: { llmService.selectedModel },
                            set: { newModel in
                                Task {
                                    await llmService.switchModel(to: newModel)
                                }
                            }
                        )) {
                            ForEach(ModelIdentifier.allCases.filter { downloadManager.isModelDownloaded($0) }) { model in
                                Text(model.displayName).tag(model)
                            }
                        }
                    }
                    
                    // Downloaded Models List
                    ForEach([ModelIdentifier.gemma270M, ModelIdentifier.gemma1B, ModelIdentifier.gemma2B, ModelIdentifier.gemma4B], id: \.self) { model in
                        ModelDownloadRow(model: model, downloadManager: downloadManager)
                    }
                } header: {
                    Text("AI Models")
                } footer: {
                    Text("Download AI models for on-device processing. Models are stored locally and never uploaded.")
                }
                
                // Flashcard grading preference
                Section {
                    Picker("Preferred Model", selection: gradingModelSelection) {
                        ForEach([ModelIdentifier.gemma270M, .gemma1B, .gemma2B, .gemma4B], id: \.self) { model in
                            Text(model.displayName).tag(model)
                        }
                    }
                    Text("Gemma 3-270M is optimized for structured grading with minimal latency. Larger models remain available if you prioritize accuracy over speed.")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                } header: {
                    Text("Flashcard Grading")
                } footer: {
                    Text("Downloaded models appear automatically. Pic2PDF will load this model on demand for flashcard review without interrupting your primary vision model.")
                }
                
                // Download Progress Section (shown when downloading)
                if downloadManager.downloadStatus.isInProgress {
                    Section {
                        DownloadProgressView(downloadManager: downloadManager)
                    } header: {
                        Text("Download Progress")
                    }
                }
                
                // Download Logs Section
                if !downloadManager.downloadLogs.isEmpty {
                    Section {
                        DownloadLogsView(downloadManager: downloadManager)
                    } header: {
                        HStack {
                            Text("Download Logs")
                            Spacer()
                            Button("Clear") {
                                downloadManager.clearLogs()
                            }
                            .font(.caption)
                        }
                    }
                }
                
                // Data Management Section
                Section {
                    Button(role: .destructive, action: { showClearDataAlert = true }) {
                        HStack {
                            Image(systemName: "trash")
                            Text("Clear All Data")
                        }
                    }
                } header: {
                    Text("Data Management")
                } footer: {
                    Text("This will permanently delete all saved generations and cannot be undone.")
                }
                
                // Help Section
                Section {
                    Button(action: {
                        dismiss()
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                            withAnimation {
                                appState.restartOnboarding()
                            }
                        }
                    }) {
                        HStack {
                            Image(systemName: "book.circle")
                                .foregroundColor(.blue)
                            Text("View Onboarding Tutorial")
                                .foregroundColor(.primary)
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                } header: {
                    Text("Help")
                } footer: {
                    Text("Learn about the app's features and how to use it effectively.")
                }
                
                // About Section
                Section {
                    HStack {
                        Text("Version")
                        Spacer()
                        Text("1.0.0")
                            .foregroundColor(.secondary)
                    }
                    
                    Link(destination: URL(string: "https://github.com/youneslaaroussi/Pic2PDF")!) {
                        HStack {
                            Image(systemName: "link")
                            Text("GitHub Repository")
                            Spacer()
                            Image(systemName: "arrow.up.right")
                                .font(.caption)
                        }
                    }
                    
                    Link(destination: URL(string: "https://github.com/youneslaaroussi/Pic2PDF/blob/main/PRIVACY.md")!) {
                        HStack {
                            Image(systemName: "hand.raised.fill")
                            Text("Privacy Policy")
                            Spacer()
                            Image(systemName: "arrow.up.right")
                                .font(.caption)
                        }
                    }
                } header: {
                    Text("About")
                } footer: {
                    Text("Built for Arm AI Developer Challenge 2025 - Showcasing efficient on-device AI processing with fully local PDF generation.")
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.large)
            // Removed Done button since Settings is now a tab
            .alert("Clear All Data", isPresented: $showClearDataAlert) {
                Button("Cancel", role: .cancel) {}
                Button("Delete All", role: .destructive) {
                    clearAllData()
                }
            } message: {
                Text("Are you sure you want to delete all saved generations? This action cannot be undone.")
            }
            .alert("Reset LLM Parameters", isPresented: $showResetParamsAlert) {
                Button("Cancel", role: .cancel) {}
                Button("Reset") {
                    resetLLMParameters()
                }
            } message: {
                Text("Reset all LLM parameters to their default values?")
            }
            .alert("HuggingFace Token", isPresented: $showTokenInfo) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("1. Go to huggingface.co and create a free account\n2. Go to Settings → Access Tokens\n3. Create a new token with 'read' permission\n4. Copy and paste the token here\n5. Accept the Gemma model license at huggingface.co/google/gemma-3n-E2B-it-litert-preview")
            }
        }
    }
    
    private var gradingModelSelection: Binding<ModelIdentifier> {
        Binding(
            get: { ModelIdentifier(rawValue: gradingModelIdentifierRaw) ?? .gemma270M },
            set: { newValue in
                gradingModelIdentifierRaw = newValue.rawValue
                llmService.gradingPreferenceDidChange()
            }
        )
    }
    
    private func clearAllData() {
        do {
            try storageManager.clearAllData()
        } catch {
            print("[Settings] ERROR: Failed to clear data: \(error)")
        }
    }
    
    private func resetLLMParameters() {
        temperature = 0.7
        topP = 0.9
        topK = 40
        maxTokens = 2000
    }
}

// MARK: - Model Download Row
struct ModelDownloadRow: View {
    let model: ModelIdentifier
    @ObservedObject var downloadManager: ModelDownloadManager
    
    var isCurrentlyDownloading: Bool {
        downloadManager.currentDownloadingModel == model && downloadManager.downloadStatus.isInProgress
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(model.displayName)
                            .font(.subheadline)
                            .fontWeight(.medium)
                        
                        if isCurrentlyDownloading {
                            ProgressView()
                                .scaleEffect(0.7)
                        }
                    }
                    
                    if downloadManager.isModelDownloaded(model) {
                        if let size = downloadManager.modelSize(model) {
                            Text("\(String(format: "%.1f", size)) MB • Downloaded")
                                .font(.caption)
                                .foregroundColor(.green)
                        }
                    } else if isCurrentlyDownloading {
                        if case .downloading(let progress, let downloaded, let total) = downloadManager.downloadStatus {
                            Text("\(formatBytes(downloaded)) / \(formatBytes(total))")
                                .font(.caption)
                                .foregroundColor(.blue)
                        }
                    } else {
                        let expectedSize = DownloadableModelConfig.availableModels[model]?.expectedSizeMB ?? 0
                        Text("~\(String(format: "%.1f", expectedSize)) MB • Not downloaded")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                
                Spacer()
                
                if downloadManager.isModelDownloaded(model) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                        .font(.title2)
                } else if isCurrentlyDownloading {
                    Button("Cancel") {
                        downloadManager.cancelDownload()
                    }
                    .buttonStyle(.bordered)
                    .tint(.red)
                } else if !downloadManager.downloadStatus.isInProgress {
                    // Show Retry if we have resume data for this model, otherwise Download
                    if downloadManager.canResumeDownload() {
                        Button("Retry") {
                            Task {
                                do {
                                    try await downloadManager.retryDownload()
                                } catch {
                                    print("Failed to retry download: \(error)")
                                }
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.orange)
                    } else {
                        Button("Download") {
                            Task {
                                do {
                                    try await downloadManager.downloadModel(model)
                                } catch {
                                    print("Failed to download model: \(error)")
                                }
                            }
                        }
                        .buttonStyle(.borderedProminent)
                    }
                }
            }
            
            // Progress bar for this model
            if isCurrentlyDownloading {
                if case .downloading(let progress, _, _) = downloadManager.downloadStatus {
                    ProgressView(value: progress)
                        .progressViewStyle(LinearProgressViewStyle())
                        .tint(.blue)
                }
            }
            
            // Show failed status with resume info
            if case .failed(let error) = downloadManager.downloadStatus {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Failed: \(error)")
                        .font(.caption)
                        .foregroundColor(.red)
                    if downloadManager.canResumeDownload() {
                        Text("Tap Retry to resume from where it stopped")
                            .font(.caption2)
                            .foregroundColor(.orange)
                    }
                }
            }
        }
        .padding(.vertical, 4)
    }
    
    private func formatBytes(_ bytes: Int64) -> String {
        let mb = Double(bytes) / (1024 * 1024)
        if mb >= 1024 {
            return String(format: "%.2f GB", mb / 1024)
        }
        return String(format: "%.0f MB", mb)
    }
}

// MARK: - Download Progress View
struct DownloadProgressView: View {
    @ObservedObject var downloadManager: ModelDownloadManager
    
    var body: some View {
        VStack(spacing: 16) {
            if case .downloading(let progress, let downloaded, let total) = downloadManager.downloadStatus {
                // Circular progress
                ZStack {
                    Circle()
                        .stroke(Color.gray.opacity(0.2), lineWidth: 10)
                        .frame(width: 100, height: 100)
                    
                    Circle()
                        .trim(from: 0, to: progress)
                        .stroke(Color.blue, style: StrokeStyle(lineWidth: 10, lineCap: .round))
                        .frame(width: 100, height: 100)
                        .rotationEffect(.degrees(-90))
                        .animation(.linear(duration: 0.3), value: progress)
                    
                    VStack(spacing: 2) {
                        Text("\(Int(progress * 100))%")
                            .font(.title2)
                            .fontWeight(.bold)
                        if let model = downloadManager.currentDownloadingModel {
                            Text(model == .gemma2B ? "2B" : "4B")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }
                
                // Stats
                VStack(spacing: 8) {
                    HStack {
                        Label("\(formatBytes(downloaded)) / \(formatBytes(total))", systemImage: "arrow.down.circle")
                        Spacer()
                        if downloadManager.downloadSpeed > 0 {
                            Label(String(format: "%.1f MB/s", downloadManager.downloadSpeed), systemImage: "speedometer")
                        }
                    }
                    .font(.caption)
                    .foregroundColor(.secondary)
                    
                    if downloadManager.estimatedTimeRemaining > 0 {
                        HStack {
                            Label("ETA: \(formatTime(downloadManager.estimatedTimeRemaining))", systemImage: "clock")
                            Spacer()
                        }
                        .font(.caption)
                        .foregroundColor(.secondary)
                    }
                }
                
                // Cancel button
                Button(role: .destructive) {
                    downloadManager.cancelDownload()
                } label: {
                    Label("Cancel Download", systemImage: "xmark.circle")
                }
                .buttonStyle(.bordered)
            }
        }
        .padding(.vertical, 8)
    }
    
    private func formatBytes(_ bytes: Int64) -> String {
        let mb = Double(bytes) / (1024 * 1024)
        if mb >= 1024 {
            return String(format: "%.2f GB", mb / 1024)
        }
        return String(format: "%.0f MB", mb)
    }
    
    private func formatTime(_ seconds: TimeInterval) -> String {
        if seconds < 60 {
            return "\(Int(seconds))s"
        } else if seconds < 3600 {
            let mins = Int(seconds) / 60
            let secs = Int(seconds) % 60
            return "\(mins)m \(secs)s"
        } else {
            let hours = Int(seconds) / 3600
            let mins = (Int(seconds) % 3600) / 60
            return "\(hours)h \(mins)m"
        }
    }
}

// MARK: - Download Logs View
struct DownloadLogsView: View {
    @ObservedObject var downloadManager: ModelDownloadManager
    @State private var isExpanded = true
    
    var body: some View {
        DisclosureGroup("Recent Activity (\(downloadManager.downloadLogs.count))", isExpanded: $isExpanded) {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 6) {
                    ForEach(downloadManager.downloadLogs.reversed()) { log in
                        HStack(alignment: .top, spacing: 8) {
                            Image(systemName: log.icon)
                                .font(.caption)
                                .foregroundColor(logColor(for: log.type))
                                .frame(width: 16)
                            
                            VStack(alignment: .leading, spacing: 2) {
                                Text(log.message)
                                    .font(.caption)
                                    .foregroundColor(.primary)
                                
                                Text(log.timestamp, style: .time)
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                            
                            Spacer()
                        }
                        .padding(.vertical, 2)
                    }
                }
            }
            .frame(maxHeight: 200)
        }
    }
    
    private func logColor(for type: DownloadLogEntry.LogType) -> Color {
        switch type {
        case .info: return .blue
        case .success: return .green
        case .error: return .red
        case .progress: return .orange
        }
    }
}

#Preview {
    SettingsView()
}

