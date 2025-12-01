//
//  OnDeviceLLMService.swift
//  Pic2PDF
//
//  Created by AI Assistant on 2025-01-30.
//

import Foundation
import UIKit
import MediaPipeTasksGenAI
import ZIPFoundation
import Combine
import Accelerate
import os.signpost
import CryptoKit

/// Represents the available AI models optimized for image-to-LaTeX conversion
public enum ModelIdentifier: String, CaseIterable, Identifiable {
    case gemma1B = "gemma-3-1b-it-int4"  // Text-only, lightweight for chat
    case gemma270M = "gemma3-270m-it-q8" // Ultra-lightweight text-only grader
    case gemma2B = "gemma-3n-E2B-it-int4"
    case gemma4B = "gemma-3n-E4B-it-int4"

    public var id: String { self.rawValue }
    public var fileName: String { "\(self.rawValue).task" }

    public var displayName: String {
        switch self {
        case .gemma270M: return "Chat Model 270M (Text Only)"
        case .gemma1B: return "Chat Model 1B (Text Only)"
        case .gemma2B: return "Vision Model 2B"
        case .gemma4B: return "Vision Model 4B"
        }
    }
    
    /// Whether this model supports vision/image input
    public var supportsVision: Bool {
        switch self {
        case .gemma270M, .gemma1B: return false
        case .gemma2B, .gemma4B: return true
        }
    }
    
    /// Minimum RAM required in GB
    public var minimumRAMGB: Double {
        switch self {
        case .gemma270M: return 2.5
        case .gemma1B: return 3.0
        case .gemma2B: return 4.5
        case .gemma4B: return 6.0
        }
    }

    /// Checks which models are actually present in the app bundle
    public static func availableInBundle() -> [ModelIdentifier] {
        return ModelIdentifier.allCases.filter { modelId in
            Bundle.main.path(forResource: modelId.rawValue, ofType: "task") != nil
        }
    }
}

/// Manages the on-device AI model, including initialization and vision component extraction
struct OnDeviceModel {
    private(set) var inference: LlmInference
    let identifier: ModelIdentifier

    init(modelIdentifier: ModelIdentifier, maxTokens: Int = 1000) throws {
        self.identifier = modelIdentifier
        let fileManager = FileManager.default
        let cacheDir = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        try fileManager.createDirectory(at: cacheDir, withIntermediateDirectories: true, attributes: nil)

        // First check for downloaded model in documents directory
        let downloadManager = ModelDownloadManager.shared
        let downloadedModelPath = downloadManager.localModelPath(for: modelIdentifier)
        
        var sourceModelPath: String?
        
        if fileManager.fileExists(atPath: downloadedModelPath.path) {
            // Use downloaded model
            sourceModelPath = downloadedModelPath.path
            NSLog("Using downloaded model at: \(downloadedModelPath.path)")
        } else if let bundleModelPath = Bundle.main.path(forResource: modelIdentifier.rawValue, ofType: "task") {
            // Fallback to bundled model if available
            sourceModelPath = bundleModelPath
            NSLog("Using bundled model at: \(bundleModelPath)")
        }
        
        guard let modelPath = sourceModelPath else {
            let errorMessage = "Model file '\(modelIdentifier.fileName)' not found. Please download the model first."
            NSLog("[OnDeviceModel] ❌ \(errorMessage)")
            NSLog("[OnDeviceModel] Checked downloaded path: \(downloadedModelPath.path)")
            NSLog("[OnDeviceModel] Bundle path would be: \(modelIdentifier.rawValue).task")
            throw NSError(domain: "ModelSetupError", code: 1001, userInfo: [NSLocalizedDescriptionKey: errorMessage])
        }
        
        // Verify model file size before loading
        if let attributes = try? fileManager.attributesOfItem(atPath: modelPath),
           let fileSize = attributes[.size] as? Int64 {
            let fileSizeMB = Double(fileSize) / (1024 * 1024)
            NSLog("Model file size: \(String(format: "%.1f", fileSizeMB)) MB")
            
            // Minimum expected sizes for each model
            let minSizeMB: Double
            switch modelIdentifier {
            case .gemma270M:
                minSizeMB = 150.0
            case .gemma1B:
                minSizeMB = 250.0
            case .gemma2B:
                minSizeMB = 2000.0
            case .gemma4B:
                minSizeMB = 3500.0
            }
            
            if fileSizeMB < minSizeMB {
                let errorMessage = "Model file is corrupted or incomplete (\(String(format: "%.1f", fileSizeMB)) MB). Please delete and re-download the model."
                NSLog(errorMessage)
                // Delete the corrupted file
                try? fileManager.removeItem(atPath: modelPath)
                throw NSError(domain: "ModelSetupError", code: 1002, userInfo: [NSLocalizedDescriptionKey: errorMessage])
            }
        }

        let modelCopyPath = cacheDir.appendingPathComponent(modelIdentifier.fileName)

        // Copy to cache if not already there or if source has been updated
        if !fileManager.fileExists(atPath: modelCopyPath.path) {
            NSLog("Copying model to cache...")
            try fileManager.copyItem(atPath: modelPath, toPath: modelCopyPath.path)
            NSLog("Model copied to cache successfully")
        }

        // Define vision component filenames within the .task archive
        let visionEncoderFileName = "TF_LITE_VISION_ENCODER"
        let visionAdapterFileName = "TF_LITE_VISION_ADAPTER"

        let extractedVisionEncoderPath = cacheDir.appendingPathComponent(visionEncoderFileName)
        let extractedVisionAdapterPath = cacheDir.appendingPathComponent(visionAdapterFileName)

        // Only extract vision models for vision-capable models
        if modelIdentifier.supportsVision {
            // Extract vision models if they don't exist
            if !fileManager.fileExists(atPath: extractedVisionEncoderPath.path) ||
               !fileManager.fileExists(atPath: extractedVisionAdapterPath.path) {
                NSLog("Extracting vision models from .task file...")
                do {
                    try OnDeviceModel.extractVisionModels(
                        fromArchive: modelCopyPath,
                        toDirectory: cacheDir,
                        filesToExtract: [visionEncoderFileName, visionAdapterFileName]
                    )
                    NSLog("Successfully extracted vision models.")
                } catch {
                    let extractionErrorMessage = "Error extracting vision components: \(error.localizedDescription)"
                    NSLog(extractionErrorMessage)
                    // Continue without vision components for now
                }
            } else {
                NSLog("Vision models already exist in cache.")
            }
        } else {
            NSLog("Skipping vision extraction for text-only model: \(modelIdentifier.displayName)")
        }

        let options = LlmInference.Options(modelPath: modelCopyPath.path)
        options.maxTokens = maxTokens

        // Only configure vision modality for models that support it
        if modelIdentifier.supportsVision {
            options.visionEncoderPath = extractedVisionEncoderPath.path
            options.visionAdapterPath = extractedVisionAdapterPath.path
            options.maxImages = 5 // Support up to 5 images for document conversion
            NSLog("Vision modality enabled for \(modelIdentifier.displayName)")
        } else {
            NSLog("Text-only mode for \(modelIdentifier.displayName)")
        }

        inference = try LlmInference(options: options)
    }

    private static func extractVisionModels(fromArchive archiveURL: URL, toDirectory destinationURL: URL, filesToExtract: [String]) throws {
        let fileManager = FileManager.default
        let archive = try Archive(url: archiveURL, accessMode: .read)

        for fileName in filesToExtract {
            guard let entry = archive[fileName] else {
                NSLog("Vision component '\(fileName)' not found in archive")
                continue
            }

            let destinationFilePath = destinationURL.appendingPathComponent(fileName)

            if fileManager.fileExists(atPath: destinationFilePath.path) {
                try fileManager.removeItem(at: destinationFilePath)
            }

            NSLog("Extracting '\(fileName)' to cache")
            _ = try archive.extract(entry, to: destinationFilePath)
        }
    }
}

/// Represents a chat session with the on-device AI model
final class AIChatSession {
    private let session: LlmInference.Session
    
    init(session: LlmInference.Session) {
        self.session = session
    }

    /// Adds an image to the current query context
    func addImageToQuery(image: CGImage) throws {
        try session.addImage(image: image)
    }

    /// Generates LaTeX from images and text prompt
    func generateLaTeX(prompt: String) async throws -> AsyncThrowingStream<String, any Error> {
        try session.addQueryChunk(inputText: prompt)
        let resultStream = session.generateResponseAsync()
        return resultStream
    }

    /// Gets the generation time for the last response
    func getLastResponseGenerationTime() -> TimeInterval? {
        return session.metrics.responseGenerationTimeInSeconds
    }

    /// Estimates token count for text
    func sizeInTokens(text: String) throws -> Int {
        return try session.sizeInTokens(text: text)
    }
}

/// Performance metrics for a single generation
struct GenerationMetrics: Identifiable {
    let id = UUID()
    let timestamp: Date
    let modelIdentifier: ModelIdentifier
    let inputImageCount: Int
    let outputTokenCount: Int
    let generationTime: TimeInterval
    let tokensPerSecond: Double
    let memoryUsageMB: Double
    let batteryLevelBefore: Int
    let batteryLevelAfter: Int
    let thermalState: ProcessInfo.ThermalState
}

/// Main service class for on-device LLM processing in Pic2PDF
final class OnDeviceLLMService: ObservableObject {
    // MARK: - Published Properties
    @Published var isInitialized = false
    @Published var initializationError: String?
    @Published var modelInitializationTime: Double = 0.0

    // MARK: - Performance Tracking
    @Published var generationHistory: [GenerationMetrics] = []
    @Published var totalGenerations: Int = 0
    @Published var averageGenerationTime: Double = 0.0
    @Published var averageTokensPerSecond: Double = 0.0
    @Published var peakMemoryUsage: Double = 0.0
    @Published var totalTokensGenerated: Int = 0

    // MARK: - Real-time Metrics
    @Published var currentMemoryUsage: Double = 0.0
    @Published var batteryLevel: Int = 100
    @Published var thermalState: ProcessInfo.ThermalState = .nominal
    @Published var deviceTemperature: Double = 0.0
    @Published var cpuUsage: Double = 0.0
    @Published var currentTokensPerSecond: Double = 0.0
    @Published var realtimeMemoryHistory: [Double] = [] // Real-time memory tracking during generation
    
    // MARK: - Live Generation Streaming
    @Published var streamingLaTeX: String = ""

    // MARK: - Public Model Access
    /// Public access to current model information for UI display
    var currentModelInfo: (identifier: ModelIdentifier, isInitialized: Bool) {
        if let modelId = cachedModelIdentifier {
            return (modelId, isInitialized)
        }
        return (preferredModel, false) // Return preferred model even if not initialized
    }
    
    /// Get the currently selected model identifier
    var selectedModel: ModelIdentifier {
        return preferredModel
    }

    // MARK: - Private Properties
    private let engine = LLMEngine()
    private let gradingEngine = LLMEngine()
    private var cachedModelIdentifier: ModelIdentifier?
    private var preferredModel: ModelIdentifier = OnDeviceLLMService.recommendedModel()
    private var gradingModelIdentifier: ModelIdentifier?
    private var metricsTimer: Timer?
    private let gradingPreferenceKey = "gradingModelIdentifier"
    
    /// Recommend model based on device RAM
    private static func recommendedModel() -> ModelIdentifier {
        let totalRAM = ProcessInfo.processInfo.physicalMemory
        let totalRAMGB = Double(totalRAM) / (1024 * 1024 * 1024)
        if totalRAMGB < 4.0 {
            return .gemma1B  // Low RAM devices (iPhone 12 mini, etc.)
        } else if totalRAMGB < 5.5 {
            return .gemma2B  // Medium RAM devices
        } else {
            return .gemma2B  // Default to 2B even for high RAM
        }
    }
    
    private func preferredGradingModel() -> ModelIdentifier {
        if let rawValue = UserDefaults.standard.string(forKey: gradingPreferenceKey),
           let identifier = ModelIdentifier(rawValue: rawValue) {
            return identifier
        }
        return .gemma270M
    }
    private let signpostLog = OSLog(subsystem: "com.pic2pdf.app", category: "LLM")
    private var firstTokenLogged = false
    private var downscaledImageCache: [String: CGImage] = [:]
    private var prewarmedSessions: [LLMEngine.SessionKey: LlmInference.Session] = [:]

    private var isPerformanceModeEnabled: Bool {
        return UserDefaults.standard.bool(forKey: "performanceModeEnabled")
    }
    
    // User-configurable LLM parameters
    private var userTemperature: Float {
        let value = UserDefaults.standard.double(forKey: "llmTemperature")
        return Float(value > 0 ? value : 0.7)
    }
    
    private var userTopP: Float {
        let value = UserDefaults.standard.double(forKey: "llmTopP")
        return Float(value > 0 ? value : 0.9)
    }
    
    private var userTopK: Int {
        let value = UserDefaults.standard.integer(forKey: "llmTopK")
        return value > 0 ? value : 40
    }
    
    private var userMaxTokens: Int {
        let value = UserDefaults.standard.integer(forKey: "llmMaxTokens")
        // Default to 1500 for faster generation (was 2000)
        return value > 0 ? value : 1500
    }

    // MARK: - Singleton
    static let shared = OnDeviceLLMService()

    private init() {
        Task { await self.setupMetricsMonitoring() }
        Task {
            await initializeModel()
        }
    }

    // MARK: - Metrics Monitoring
    @MainActor
    private func setupMetricsMonitoring() {
        // Update real-time metrics every second
        metricsTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.updateRealTimeMetrics()
            }
        }

        // Battery monitoring
        UIDevice.current.isBatteryMonitoringEnabled = true
        batteryLevel = Int((UIDevice.current.batteryLevel * 100).rounded())

        NotificationCenter.default.addObserver(forName: UIDevice.batteryLevelDidChangeNotification, object: nil, queue: .main) { [weak self] _ in
            self?.batteryLevel = Int((UIDevice.current.batteryLevel * 100).rounded())
        }

        // Thermal state monitoring
        thermalState = ProcessInfo.processInfo.thermalState
        NotificationCenter.default.addObserver(forName: ProcessInfo.thermalStateDidChangeNotification, object: nil, queue: .main) { [weak self] _ in
            self?.thermalState = ProcessInfo.processInfo.thermalState
        }
    }

    private func updateRealTimeMetrics() {
        currentMemoryUsage = ProcessMetrics.currentResidentMemoryMB()

        // Update peak memory usage
        if currentMemoryUsage > peakMemoryUsage {
            peakMemoryUsage = currentMemoryUsage
        }
        
        // Add to real-time history if we have streaming content (generation in progress)
        if !streamingLaTeX.isEmpty {
            realtimeMemoryHistory.append(currentMemoryUsage)
            // Keep only last 30 data points for performance
            if realtimeMemoryHistory.count > 30 {
                realtimeMemoryHistory.removeFirst()
            }
        }

        // CPU usage (simulated for demo)
        cpuUsage = ProcessMetrics.currentCPUUsage()

        // Temperature simulation (IOKit not available in iOS apps)
        // In production, would use private APIs or device sensors
        let baseTemp: Double = 38.0 // Base temperature for iOS device
        let thermalAdjustment: Double = thermalState == .nominal ? 0 :
                                       thermalState == .fair ? 3 :
                                       thermalState == .serious ? 8 : 12
        deviceTemperature = baseTemp + Double.random(in: -2...2) + thermalAdjustment
    }

    @MainActor
    private func recordGenerationMetrics(inputImages: Int,
                                         outputTokens: Int,
                                         generationTime: TimeInterval,
                                         batteryBefore: Int,
                                         modelOverride: ModelIdentifier? = nil) {
        let tokensPerSecond = Double(outputTokens) / generationTime
        let memoryUsage = currentMemoryUsage

        let metrics = GenerationMetrics(
            timestamp: Date(),
            modelIdentifier: modelOverride ?? preferredModel,
            inputImageCount: inputImages,
            outputTokenCount: outputTokens,
            generationTime: generationTime,
            tokensPerSecond: tokensPerSecond,
            memoryUsageMB: memoryUsage,
            batteryLevelBefore: batteryBefore,
            batteryLevelAfter: batteryLevel,
            thermalState: thermalState
        )

        generationHistory.append(metrics)

        // Keep only last 50 generations for performance
        if generationHistory.count > 50 {
            generationHistory.removeFirst()
        }

        // Update aggregates
        totalGenerations += 1
        totalTokensGenerated += outputTokens

        let allGenerationTimes = generationHistory.map { $0.generationTime }
        averageGenerationTime = allGenerationTimes.reduce(0, +) / Double(allGenerationTimes.count)

        let allTokensPerSecond = generationHistory.map { $0.tokensPerSecond }
        averageTokensPerSecond = allTokensPerSecond.reduce(0, +) / Double(allTokensPerSecond.count)
    }

    // MARK: - Model Management

    /// Initializes the preferred AI model - can be called after model download completes
    func initializeModel() async {
        // Check device RAM before attempting to load model
        let totalRAM = ProcessInfo.processInfo.physicalMemory
        let totalRAMGB = Double(totalRAM) / (1024 * 1024 * 1024)
        NSLog("Device total RAM: \(String(format: "%.1f", totalRAMGB)) GB")
        
        // Use model-specific RAM requirements
        let minimumRAMGB = preferredModel.minimumRAMGB
        if totalRAMGB < minimumRAMGB {
            await MainActor.run {
                initializationError = "Your device has \(String(format: "%.1f", totalRAMGB))GB RAM. The \(preferredModel.displayName) model requires at least \(String(format: "%.1f", minimumRAMGB))GB RAM. Try the Chat Model 1B for devices with less memory."
                isInitialized = false
            }
            NSLog("Insufficient RAM: \(totalRAMGB)GB < \(minimumRAMGB)GB required")
            return
        }
        
        do {
            let startTime = Date()
            os_signpost(.begin, log: signpostLog, name: "ModelInit", "Model=%{public}@", preferredModel.displayName)

            // Use user-configured max tokens, with performance mode override
            let maxTokens = isPerformanceModeEnabled ? min(1200, userMaxTokens) : userMaxTokens
            let model = try await engine.initializeModel(identifier: preferredModel, maxTokens: maxTokens)

            let endTime = Date()
            let elapsed = endTime.timeIntervalSince(startTime)

            await MainActor.run {
                cachedModelIdentifier = model.identifier
                modelInitializationTime = elapsed
                isInitialized = true
                initializationError = nil
            }

            os_signpost(.end, log: signpostLog, name: "ModelInit")
            NSLog("AI model \(preferredModel.displayName) initialized in \(modelInitializationTime)s (perfMode=\(isPerformanceModeEnabled))")
            
            prewarmChatSession()
        } catch {
            await MainActor.run {
                initializationError = "Failed to initialize on-device LLM: \(error.localizedDescription)"
                isInitialized = false
            }
            NSLog("Model initialization error: \(error)")
        }
    }

    /// Checks if the service is ready for inference
    func isReady() -> Bool {
        return isInitialized
    }
    
    /// Switch to a different model
    /// - Parameter modelIdentifier: The model to switch to
    func switchModel(to modelIdentifier: ModelIdentifier) async {
        guard modelIdentifier != preferredModel else {
            NSLog("Already using model: \(modelIdentifier.displayName)")
            return
        }
        
        NSLog("Switching model from \(preferredModel.displayName) to \(modelIdentifier.displayName)")
        
        // Update preferred model
        preferredModel = modelIdentifier
        
        // Reset initialization state
        await MainActor.run {
            isInitialized = false
            initializationError = nil
            cachedModelIdentifier = nil
        }
        await engine.resetSessions()
        
        // Initialize new model
        await initializeModel()
    }
    
    /// Clears cached grading sessions/models so the next grading request reloads with the new preference
    func gradingPreferenceDidChange() {
        gradingModelIdentifier = nil
        Task {
            await gradingEngine.resetSessions()
        }
    }

    // MARK: - LaTeX Generation

    /// Generates LaTeX from images using the on-device LLM
    /// - Parameters:
    ///   - images: Array of UIImages to convert
    ///   - additionalPrompt: Optional additional context or instructions
    ///   - status: Status object to update with progress
    /// - Returns: Generated LaTeX string
    func generateLaTeX(from images: [UIImage],
                       additionalPrompt: String? = nil,
                       status: GenerationStatus) async throws -> String {
        guard isReady() else {
            throw OnDeviceLLMError.notInitialized
        }

        let startTime = Date()
        let batteryBefore = batteryLevel
        let initialMemory = currentMemoryUsage

        await MainActor.run {
            status.statusMessage = "Processing images with on-device AI..."
            status.progress = 0.1
            streamingLaTeX = "" // Clear previous stream
            currentTokensPerSecond = 0.0 // Reset real-time metric
            realtimeMemoryHistory = [] // Clear real-time memory history
        }

        // Create a new session for this generation task using user settings
        // Performance mode can adjust parameters slightly for speed
        var temp = isPerformanceModeEnabled ? min(userTemperature, 0.6) : userTemperature
        var tP = isPerformanceModeEnabled ? min(userTopP, 0.95) : userTopP
        var tK = isPerformanceModeEnabled ? max(userTopK, 60) : userTopK
        (tK, tP, temp) = adaptParameters(topK: tK, topP: tP, temperature: temp)
        
        NSLog("[OnDeviceLLM] Creating vision-enabled session (perfMode=\(isPerformanceModeEnabled))")
        NSLog("[OnDeviceLLM] Parameters: temp=\(temp), topP=\(tP), topK=\(tK)")
        let session = try await acquireSession(for: makeSessionKey(topK: tK, topP: tP, temperature: temp, enableVision: true))
        NSLog("[OnDeviceLLM] Session created with vision modality enabled")

        // Downscale images in parallel (Accelerate) for lower memory and faster vision path
        // Smaller images = faster processing. 768px is usually sufficient for text/math recognition
        os_signpost(.begin, log: signpostLog, name: "PreprocessImages")
        let maxDimension = isPerformanceModeEnabled ? 768 : 1024
        var processedByIndex: [Int: CGImage] = [:]
        var pendingTasks: [(index: Int, image: UIImage, cacheKey: String?)] = []
        var keyByIndex: [Int: String] = [:]

        for (idx, image) in images.enumerated() {
            let cacheKey = imageCacheKey(for: image, maxDimension: maxDimension)
            if let cacheKey, let cached = downscaledImageCache[cacheKey] {
                processedByIndex[idx] = cached
            } else {
                pendingTasks.append((idx, image, cacheKey))
                if let cacheKey {
                    keyByIndex[idx] = cacheKey
                }
            }
        }

        var cacheUpdates: [(String, CGImage)] = []
        if !pendingTasks.isEmpty {
            await withTaskGroup(of: (Int, CGImage?).self) { group in
                for task in pendingTasks {
                    group.addTask(priority: .userInitiated) {
                        guard let cg = task.image.cgImage else { return (task.index, nil) }
                        let scaled = downscaleCGImageAccelerate(cg, maxDimension: maxDimension) ?? cg
                        return (task.index, scaled)
                    }
                }

                while let result = await group.next() {
                    if let image = result.1 {
                        processedByIndex[result.0] = image
                        if let key = keyByIndex[result.0] {
                            cacheUpdates.append((key, image))
                        }
                    }
                }
            }
        }

        for update in cacheUpdates {
            downscaledImageCache[update.0] = update.1
        }

        let processedCGImages = (0..<images.count).compactMap { processedByIndex[$0] }
        os_signpost(.end, log: signpostLog, name: "PreprocessImages")

        guard !processedCGImages.isEmpty else {
            throw OnDeviceLLMError.invalidImage
        }

        NSLog("[OnDeviceLLM] Adding \(processedCGImages.count) images to query")
        for (index, cgImage) in processedCGImages.enumerated() {
            NSLog("[OnDeviceLLM] Adding image \(index + 1): \(cgImage.width)x\(cgImage.height)")
            try session.addImageToQuery(image: cgImage)
            await MainActor.run {
                status.statusMessage = "Processing image \(index + 1) of \(processedCGImages.count)..."
                status.progress = 0.1 + (0.3 * Double(index + 1) / Double(processedCGImages.count))
            }
        }
        NSLog("[OnDeviceLLM] All images added successfully")

        await MainActor.run {
            status.statusMessage = "Generating LaTeX with on-device AI..."
            status.progress = 0.5
        }

        // Create the prompt for LaTeX generation
        let prompt = createLaTeXGenerationPrompt(additionalPrompt: additionalPrompt)
        NSLog("[OnDeviceLLM] Using prompt: \(prompt.prefix(200))...")

        // Generate LaTeX using streaming response (30fps throttled UI updates)
        let stream = try await session.generateLaTeX(prompt: prompt)
        var fullResponse = ""
        let generationStartTime = Date()
        var lastUIUpdate = Date.distantPast
        firstTokenLogged = false
        let promptTokenEstimate = (try? session.sizeInTokens(text: prompt)) ?? max(prompt.count / 4, 1)
        let outputTokenLimit = computeOutputLimit(promptEstimate: promptTokenEstimate)
        var producedTokens = 0

        streamingLoop: for try await chunk in stream {
            fullResponse += chunk

            // First token event
            if !firstTokenLogged && !chunk.isEmpty {
                os_signpost(.event, log: signpostLog, name: "FirstToken")
                firstTokenLogged = true
            }

            let now = Date()
            if now.timeIntervalSince(lastUIUpdate) >= (1.0 / 30.0) {
                let elapsedTime = now.timeIntervalSince(generationStartTime)
                let estimatedTokens = max(fullResponse.count / 4, 1) // ~4 chars per token
                let tokensPerSec = elapsedTime > 0 ? Double(estimatedTokens) / elapsedTime : 0

                await MainActor.run {
                    streamingLaTeX = fullResponse // Update streaming display
                    currentTokensPerSecond = tokensPerSec // Update real-time tokens/sec
                    status.statusMessage = "Generating LaTeX... (\(fullResponse.count) characters)"
                    status.progress = 0.5 + (0.4 * min(1.0, Double(fullResponse.count) / 2000.0))
                }
                lastUIUpdate = now
            }
            
            producedTokens += max(chunk.count / 4, 1)
            if producedTokens >= outputTokenLimit {
                break streamingLoop
            }
        }

        let endTime = Date()
        let generationTime = endTime.timeIntervalSince(startTime)

        await MainActor.run {
            status.statusMessage = "LaTeX generation complete"
            status.progress = 1.0
        }

        // Extract LaTeX content from response (remove any extra text)
        let latexResult = extractLaTeXFromResponse(fullResponse)

        // Estimate token count using model tokenizer; fallback to char/4 if unavailable
        let estimatedTokens = (try? session.sizeInTokens(text: fullResponse)) ?? (fullResponse.count / 4)

        // Record performance metrics
        await MainActor.run {
            recordGenerationMetrics(
                inputImages: images.count,
                outputTokens: estimatedTokens,
                generationTime: generationTime,
                batteryBefore: batteryBefore
            )
        }

        return latexResult
    }

    /// Refines existing LaTeX based on user feedback using on-device LLM
    /// - Parameters:
    ///   - currentLaTeX: The existing LaTeX to refine
    ///   - userFeedback: User's refinement instructions
    ///   - status: Status object to update with progress
    /// - Returns: Refined LaTeX string
    /// - Note: This method does NOT re-process images, only refines the existing LaTeX code
    func refineLaTeX(currentLaTeX: String,
                     userFeedback: String,
                     status: GenerationStatus) async throws -> String {
        guard isReady() else {
            throw OnDeviceLLMError.notInitialized
        }

        let startTime = Date()
        let batteryBefore = batteryLevel

        await MainActor.run {
            status.statusMessage = "Preparing refinement with on-device AI..."
            status.progress = 0.1
            streamingLaTeX = "" // Clear previous stream
            currentTokensPerSecond = 0.0 // Reset real-time metric
            realtimeMemoryHistory = [] // Clear real-time memory history
        }

        // Create a new session for refinement (text-only, no images) using user settings
        var temp = isPerformanceModeEnabled ? min(userTemperature, 0.6) : userTemperature
        var tP = isPerformanceModeEnabled ? min(userTopP, 0.95) : userTopP
        var tK = isPerformanceModeEnabled ? max(userTopK, 60) : userTopK
        (tK, tP, temp) = adaptParameters(topK: tK, topP: tP, temperature: temp)
        
        NSLog("[OnDeviceLLM] Creating text-only session for refinement")
        NSLog("[OnDeviceLLM] Parameters: temp=\(temp), topP=\(tP), topK=\(tK)")
        let session = try await acquireSession(for: makeSessionKey(topK: tK, topP: tP, temperature: temp, enableVision: false))

        await MainActor.run {
            status.statusMessage = "Refining LaTeX with on-device AI..."
            status.progress = 0.3
        }

        // Create refinement prompt
        let prompt = createLaTeXRefinementPrompt(currentLaTeX: currentLaTeX, userFeedback: userFeedback)

        // Generate refined LaTeX (30fps throttled updates)
        let stream = try await session.generateLaTeX(prompt: prompt)
        var fullResponse = ""
        let generationStartTime = Date()
        var lastUIUpdate = Date.distantPast
        firstTokenLogged = false
        let promptTokenEstimate = (try? session.sizeInTokens(text: prompt)) ?? max(prompt.count / 4, 1)
        let outputTokenLimit = computeOutputLimit(promptEstimate: promptTokenEstimate)
        var producedTokens = 0

        streamingLoop: for try await chunk in stream {
            fullResponse += chunk

            if !firstTokenLogged && !chunk.isEmpty {
                os_signpost(.event, log: signpostLog, name: "FirstToken(Refine)")
                firstTokenLogged = true
            }

            let now = Date()
            if now.timeIntervalSince(lastUIUpdate) >= (1.0 / 30.0) {
                let elapsedTime = now.timeIntervalSince(generationStartTime)
                let estimatedTokens = max(fullResponse.count / 4, 1)
                let tokensPerSec = elapsedTime > 0 ? Double(estimatedTokens) / elapsedTime : 0

                await MainActor.run {
                    streamingLaTeX = fullResponse // Update streaming display
                    currentTokensPerSecond = tokensPerSec // Update real-time tokens/sec
                    status.statusMessage = "Refining LaTeX... (\(fullResponse.count) characters)"
                    status.progress = 0.3 + (0.6 * min(1.0, Double(fullResponse.count) / 2000.0))
                }
                lastUIUpdate = now
            }
            
            producedTokens += max(chunk.count / 4, 1)
            if producedTokens >= outputTokenLimit {
                break streamingLoop
            }
        }

        let endTime = Date()
        let generationTime = endTime.timeIntervalSince(startTime)

        await MainActor.run {
            status.statusMessage = "LaTeX refinement complete"
            status.progress = 1.0
        }

        let latexResult = extractLaTeXFromResponse(fullResponse)

        // Estimate token count for refinement using tokenizer when possible
        let estimatedTokens = (try? session.sizeInTokens(text: fullResponse)) ?? (fullResponse.count / 4)

        // Record performance metrics for refinement (0 images since we're only refining LaTeX)
        await MainActor.run {
            recordGenerationMetrics(
                inputImages: 0,
                outputTokens: estimatedTokens,
                generationTime: generationTime,
                batteryBefore: batteryBefore
            )
        }

        return latexResult
    }

    // MARK: - Chat Generation
    
    /// Generates a chat response using the on-device LLM (text-only, no images)
    /// - Parameters:
    ///   - prompt: The user's message/question
    ///   - onPartialResponse: Callback for streaming partial responses
    /// - Returns: The complete response string
    func generateChatResponse(prompt: String, onPartialResponse: @escaping (String) -> Void) async throws -> String {
        guard isReady() else {
            throw OnDeviceLLMError.notInitialized
        }

        let startTime = Date()
        let batteryBefore = batteryLevel
        let normalizedPrompt = optimizedChatPrompt(prompt)

        await MainActor.run {
            streamingLaTeX = "" // Reuse for streaming display
            currentTokensPerSecond = 0.0
        }

        // Create a text-only session for chat
        let (tK, tP, temp) = fastChatParameters()
        
        NSLog("[OnDeviceLLM] Creating chat session")
        let session = try await acquireSession(for: makeSessionKey(topK: tK, topP: tP, temperature: temp, enableVision: false))

        // Generate response with streaming
        let stream = try await session.generateLaTeX(prompt: normalizedPrompt)
        var fullResponse = ""
        let generationStartTime = Date()
        var lastUIUpdate = Date.distantPast
        let promptTokenEstimate = (try? session.sizeInTokens(text: normalizedPrompt)) ?? max(normalizedPrompt.count / 4, 1)
        let outputTokenLimit = computeOutputLimit(promptEstimate: promptTokenEstimate)
        var producedTokens = 0
        let updateInterval = 1.0 / 15.0

        NSLog("[OnDeviceLLM] Starting chat generation, output limit: \(outputTokenLimit)")
        
        streamingLoop: for try await chunk in stream {
            fullResponse += chunk

            let now = Date()
            if now.timeIntervalSince(lastUIUpdate) >= updateInterval {
                let elapsedTime = now.timeIntervalSince(generationStartTime)
                let estimatedTokens = max(fullResponse.count / 4, 1)
                let tokensPerSec = elapsedTime > 0 ? Double(estimatedTokens) / elapsedTime : 0

                await MainActor.run {
                    currentTokensPerSecond = tokensPerSec
                }
                onPartialResponse(fullResponse)
                lastUIUpdate = now
            }
            
            producedTokens += max(chunk.count / 4, 1)
            if producedTokens >= outputTokenLimit {
                NSLog("[OnDeviceLLM] Hit output limit at \(producedTokens) tokens")
                break streamingLoop
            }
        }

        let endTime = Date()
        let generationTime = endTime.timeIntervalSince(startTime)
        NSLog("[OnDeviceLLM] Chat response: '\(fullResponse.prefix(100))...' (\(fullResponse.count) chars)")

        // Estimate token count
        let estimatedTokens = (try? session.sizeInTokens(text: fullResponse)) ?? (fullResponse.count / 4)

        // Record metrics
        await MainActor.run {
            recordGenerationMetrics(
                inputImages: 0,
                outputTokens: estimatedTokens,
                generationTime: generationTime,
                batteryBefore: batteryBefore
            )
        }

        return fullResponse.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    // MARK: - Flashcard Grading
    
    /// Generates a deterministic grading response using the dedicated grading model preference
    func generateGradingResponse(prompt: String) async throws -> String {
        NSLog("[OnDeviceLLM-Grading] Starting grading response generation...")
        
        let normalizedPrompt = optimizedChatPrompt(prompt)
        let batteryBefore = batteryLevel
        let startTime = Date()
        
        NSLog("[OnDeviceLLM-Grading] Initializing grading model...")
        let gradingModel = try await ensureGradingModelInitialized()
        NSLog("[OnDeviceLLM-Grading] Using model: \(gradingModel.displayName) (\(gradingModel.rawValue))")
        
        let (topK, topP, temp) = gradingChatParameters()
        NSLog("[OnDeviceLLM-Grading] Parameters - topK: \(topK), topP: \(topP), temp: \(temp)")
        
        let key = makeSessionKey(topK: topK, topP: topP, temperature: temp, enableVision: false)
        let session = try await acquireGradingSession(for: key)
        
        NSLog("[OnDeviceLLM-Grading] Session acquired, generating response...")
        let stream = try await session.generateLaTeX(prompt: normalizedPrompt)
        var fullResponse = ""
        let promptTokenEstimate = (try? session.sizeInTokens(text: normalizedPrompt)) ?? max(normalizedPrompt.count / 4, 1)
        // Grading only needs ~30-50 tokens for JSON response - keep it tight for speed
        let outputTokenLimit = 100
        var producedTokens = 0
        
        NSLog("[OnDeviceLLM-Grading] Prompt tokens ~\(promptTokenEstimate), output limit: \(outputTokenLimit)")
        
        for try await chunk in stream {
            fullResponse += chunk
            producedTokens += max(chunk.count / 4, 1)
            
            // Early termination: stop as soon as we have a complete JSON object
            if fullResponse.contains("}") {
                NSLog("[OnDeviceLLM-Grading] Complete JSON detected, stopping early")
                break
            }
            
            if producedTokens >= outputTokenLimit {
                NSLog("[OnDeviceLLM-Grading] Hit output token limit (\(outputTokenLimit))")
                break
            }
        }
        
        let generationTime = Date().timeIntervalSince(startTime)
        let estimatedTokens = (try? session.sizeInTokens(text: fullResponse)) ?? (fullResponse.count / 4)
        
        NSLog("[OnDeviceLLM-Grading] Generation complete in \(String(format: "%.2f", generationTime))s")
        NSLog("[OnDeviceLLM-Grading] Output tokens: ~\(estimatedTokens), chars: \(fullResponse.count)")
        NSLog("[OnDeviceLLM-Grading] Tokens/sec: \(String(format: "%.1f", Double(estimatedTokens) / generationTime))")
        
        await MainActor.run {
            recordGenerationMetrics(
                inputImages: 0,
                outputTokens: estimatedTokens,
                generationTime: generationTime,
                batteryBefore: batteryBefore,
                modelOverride: gradingModel
            )
        }
        
        return fullResponse.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Private Helper Methods

    private func createLaTeXGenerationPrompt(additionalPrompt: String?) -> String {
        // Concise prompt for faster generation
        let basePrompt = """
        Convert the image content to LaTeX. Output ONLY valid LaTeX code:

        \\documentclass{article}
        \\usepackage{amsmath}
        \\usepackage{amssymb}
        \\begin{document}
        [YOUR TRANSCRIPTION HERE]
        \\end{document}

        Rules: Use $ $ for inline math, \\[ \\] for display math. No explanations.
        """

        if let additional = additionalPrompt, !additional.isEmpty {
            return basePrompt + "\n" + additional
        }

        return basePrompt
    }

    private func createLaTeXRefinementPrompt(currentLaTeX: String, userFeedback: String) -> String {
        return """
        You are a LaTeX transcription tool. Refine the following LaTeX code based on user feedback.

        Current LaTeX:
        ```
        \(currentLaTeX)
        ```

        User feedback: \(userFeedback)

        Requirements:
        - Make the requested changes
        - Use ONLY \\documentclass{article} with \\usepackage{amsmath} and \\usepackage{amssymb}
        - Do NOT use: \\includegraphics, \\geometry, \\pagestyle, \\fancyhdr, \\fancyhead, \\fancyfoot, \\renewcommand, tabular, table, tikz, tikzpicture, or any other packages
        - Do NOT add \\section, \\subsection, or explanatory text about the LaTeX code itself
        - For math: Use ONLY \\[ \\] for display math and $ $ for inline math
        - NEVER use \\begin{equation}, \\begin{align}, \\begin{gather}, \\begin{multline}, or ANY \\begin{}...\\end{} environments
        - Keep it minimal and direct - just the content
        - Return ONLY the refined LaTeX code, no explanations

        Refined LaTeX:
        """
    }
    
    private func makeSessionKey(topK: Int, topP: Float, temperature: Float, enableVision: Bool) -> LLMEngine.SessionKey {
        return LLMEngine.SessionKey(topK: topK, topP: topP, temperature: temperature, enableVision: enableVision)
    }
    
    private func computeOutputLimit(promptEstimate: Int) -> Int {
        let remainingBudget = max(userMaxTokens - promptEstimate / 2, 128)
        return min(userMaxTokens, remainingBudget)
    }
    
    private func adaptParameters(topK: Int, topP: Float, temperature: Float) -> (Int, Float, Float) {
        var adjustedTopK = topK
        var adjustedTopP = topP
        var adjustedTemp = temperature
        
        switch thermalState {
        case .serious, .critical:
            adjustedTopK = min(adjustedTopK, 24)
            adjustedTopP = min(adjustedTopP, 0.8)
            adjustedTemp = min(adjustedTemp, 0.58)
        case .fair:
            adjustedTopK = min(adjustedTopK, 28)
            adjustedTopP = min(adjustedTopP, 0.84)
            adjustedTemp = min(adjustedTemp, 0.62)
        default:
            break
        }
        
        if cpuUsage >= 85 {
            adjustedTopK = min(adjustedTopK, 24)
            adjustedTopP = min(adjustedTopP, 0.8)
            adjustedTemp = min(adjustedTemp, 0.58)
        } else if cpuUsage >= 70 {
            adjustedTopK = min(adjustedTopK, 28)
            adjustedTopP = min(adjustedTopP, 0.84)
            adjustedTemp = min(adjustedTemp, 0.62)
        }
        
        return (max(8, adjustedTopK), max(0.1, adjustedTopP), max(0.3, adjustedTemp))
    }
    
    private func fastChatParameters() -> (Int, Float, Float) {
        let baseTopK = min(userTopK, 40)
        let baseTopP = min(userTopP, 0.9)
        let baseTemp = min(userTemperature, 0.8)
        
        // 270M model needs higher temperature to produce output
        // 1B model works better with lower temperature
        let maxTemp: Float
        let minTemp: Float
        switch preferredModel {
        case .gemma270M:
            maxTemp = 0.9
            minTemp = 0.6  // Don't go too low or it produces nothing
        case .gemma1B:
            maxTemp = 0.5
            minTemp = 0.3
        default:
            maxTemp = 0.65
            minTemp = 0.3
        }
        
        let adjustedTemp = max(minTemp, min(baseTemp, maxTemp))
        NSLog("[OnDeviceLLM] Chat params for \(preferredModel.displayName): temp=\(adjustedTemp)")
        
        return adaptParameters(
            topK: min(baseTopK, 32),
            topP: min(baseTopP, 0.85),
            temperature: adjustedTemp
        )
    }
    
    private func gradingChatParameters() -> (Int, Float, Float) {
        // Balance between speed and reliability
        // Too low temp (0.3) causes empty responses with 1B model
        let temp: Float = 0.5  // Higher temp to ensure output
        let topK = 20          // More candidates for better output
        let topP: Float = 0.85
        return (topK, topP, temp)
    }
    
    private func ensureGradingModelInitialized() async throws -> ModelIdentifier {
        let desired = preferredGradingModel()
        NSLog("[OnDeviceLLM-Grading] Preferred grading model: \(desired.displayName) (\(desired.rawValue))")
        
        // Check if model file exists
        let downloadManager = ModelDownloadManager.shared
        let modelPath = await MainActor.run { downloadManager.localModelPath(for: desired) }
        let fileExists = FileManager.default.fileExists(atPath: modelPath.path)
        NSLog("[OnDeviceLLM-Grading] Model file exists at \(modelPath.path): \(fileExists)")
        
        if !fileExists {
            NSLog("[OnDeviceLLM-Grading] Model file not found! Checking if downloaded...")
            let isDownloaded = await MainActor.run { downloadManager.isModelDownloaded(desired) }
            NSLog("[OnDeviceLLM-Grading] isModelDownloaded(\(desired.rawValue)): \(isDownloaded)")
        }
        
        if gradingModelIdentifier == desired,
           let current = await gradingEngine.currentModelIdentifier(),
           current == desired {
            NSLog("[OnDeviceLLM-Grading] Reusing already initialized grading model: \(desired.displayName)")
            return desired
        }
        
        // Need enough tokens for prompt (~100) + output (~50) with buffer
        let maxTokens = 512
        NSLog("[OnDeviceLLM-Grading] Attempting to initialize \(desired.displayName) with maxTokens=\(maxTokens)")
        
        do {
            let model = try await gradingEngine.initializeModel(identifier: desired, maxTokens: maxTokens)
            gradingModelIdentifier = model.identifier
            NSLog("[OnDeviceLLM-Grading] Successfully initialized \(model.identifier.displayName)")
            return model.identifier
        } catch {
            NSLog("[OnDeviceLLM-Grading] ❌ Failed to initialize \(desired.displayName): \(error.localizedDescription)")
            NSLog("[OnDeviceLLM-Grading] Full error: \(error)")
            
            if desired != .gemma1B {
                NSLog("[OnDeviceLLM-Grading] Falling back to Chat Model 1B...")
                // Don't persist the fallback - let user fix the issue
                let fallbackModel = try await gradingEngine.initializeModel(identifier: .gemma1B, maxTokens: maxTokens)
                gradingModelIdentifier = fallbackModel.identifier
                NSLog("[OnDeviceLLM-Grading] Fallback successful: \(fallbackModel.identifier.displayName)")
                return fallbackModel.identifier
            }
            throw error
        }
    }
    
    private func optimizedChatPrompt(_ prompt: String) -> String {
        let collapsed = prompt
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if collapsed.count > 2000 {
            let startIdx = collapsed.index(collapsed.endIndex, offsetBy: -2000)
            return String(collapsed[startIdx...])
        }
        return collapsed
    }
    
    private func prewarmChatSession() {
        let (topK, topP, temp) = fastChatParameters()
        let key = makeSessionKey(topK: topK, topP: topP, temperature: temp, enableVision: false)
        Task.detached(priority: .utility) { [weak self] in
            guard let self = self else { return }
            if let warmSession = try? await self.engine.session(for: key) {
                await MainActor.run {
                    self.prewarmedSessions[key] = warmSession
                }
            }
        }
    }
    
    @MainActor
    private func takePrewarmedSession(for key: LLMEngine.SessionKey) -> LlmInference.Session? {
        return prewarmedSessions.removeValue(forKey: key)
    }
    
    private func acquireSession(for key: LLMEngine.SessionKey) async throws -> AIChatSession {
        if let warm = await MainActor.run(body: { takePrewarmedSession(for: key) }) {
            return AIChatSession(session: warm)
        }
        let handle = try await engine.session(for: key)
        return AIChatSession(session: handle)
    }
    
    private func acquireGradingSession(for key: LLMEngine.SessionKey) async throws -> AIChatSession {
        // Always create fresh session - MediaPipe sessions accumulate context
        // and will overflow if reused across multiple grading requests
        let handle = try await gradingEngine.session(for: key)
        return AIChatSession(session: handle)
    }

    private func imageCacheKey(for image: UIImage, maxDimension: Int) -> String? {
        guard let data = image.pngData() ?? image.jpegData(compressionQuality: 0.95) else {
            return nil
        }
        let digest = SHA256.hash(data: data)
        let hex = digest.map { String(format: "%02x", $0) }.joined()
        return "\(maxDimension)-\(hex)"
    }

    private func extractLaTeXFromResponse(_ response: String) -> String {
        // Remove markdown code blocks if present
        var latex = response
            .replacingOccurrences(of: "```latex", with: "")
            .replacingOccurrences(of: "```", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        // Ensure it starts with \documentclass if it doesn't already
        if !latex.hasPrefix("\\documentclass") {
            // Try to find LaTeX content within the response
            if let latexStart = latex.firstIndex(of: "\\") {
                latex = String(latex[latexStart...])
            }
        }

        return latex
    }

}

// MARK: - Error Types
enum OnDeviceLLMError: LocalizedError {
    case notInitialized
    case modelNotAvailable
    case invalidImage
    case generationFailed(String)

    var errorDescription: String? {
        switch self {
        case .notInitialized:
            return "On-device AI is not initialized. Please wait for model loading to complete."
        case .modelNotAvailable:
            return "Required AI model is not available on this device."
        case .invalidImage:
            return "Invalid image provided for processing."
        case .generationFailed(let reason):
            return "AI generation failed: \(reason)"
        }
    }
}

// MARK: - Global Accelerate Helper (non-main-actor)
private func downscaleCGImageAccelerate(_ src: CGImage, maxDimension: Int) -> CGImage? {
    let width = src.width
    let height = src.height
    let maxSide = max(width, height)
    guard maxSide > maxDimension else { return src }

    let scale = Double(maxDimension) / Double(maxSide)
    let dstW = Int(Double(width) * scale)
    let dstH = Int(Double(height) * scale)

    let colorSpace = CGColorSpaceCreateDeviceRGB()
    var format = vImage_CGImageFormat(
        bitsPerComponent: 8,
        bitsPerPixel: 32,
        colorSpace: Unmanaged.passUnretained(colorSpace),
        bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue),
        version: 0,
        decode: nil,
        renderingIntent: .defaultIntent
    )

    var srcBuf = vImage_Buffer()
    var dstBuf = vImage_Buffer()

    guard vImageBuffer_InitWithCGImage(&srcBuf, &format, nil, src, vImage_Flags(kvImageNoFlags)) == kvImageNoError else { return nil }
    defer { free(srcBuf.data) }
    
    guard vImageBuffer_Init(&dstBuf, vImagePixelCount(dstH), vImagePixelCount(dstW), format.bitsPerPixel, vImage_Flags(kvImageNoFlags)) == kvImageNoError else { return nil }

    let scaleError = vImageScale_ARGB8888(&srcBuf, &dstBuf, nil, vImage_Flags(kvImageHighQualityResampling))
    guard scaleError == kvImageNoError else {
        free(dstBuf.data)
        return nil
    }
    
    // Use kvImageNoFlags to let vImage copy the data, so we can safely free dstBuf after
    let result = vImageCreateCGImageFromBuffer(&dstBuf, &format, { _, ptr in
        // This callback is called when the CGImage is deallocated
        free(ptr)
    }, nil, vImage_Flags(kvImageNoFlags), nil)?.takeRetainedValue()
    
    // Don't free dstBuf.data here - it's now owned by the CGImage via the callback
    return result
}
