//
//  ModelDownloadManager.swift
//  Pic2PDF
//
//  Created for Arm AI Developer Challenge 2025
//

import Foundation
import Combine

/// Configuration for downloadable models
struct DownloadableModelConfig {
    let identifier: ModelIdentifier
    let downloadURL: URL
    let expectedSizeMB: Double
    let checksum: String? // Optional SHA256 checksum for verification
    
    // Cloudflare R2 - Production URLs
    static let availableModels: [ModelIdentifier: DownloadableModelConfig] = [
        .gemma2B: DownloadableModelConfig(
            identifier: .gemma2B,
            downloadURL: URL(string: "https://pub-69c747d5957f4104a2f87b0aca35a2af.r2.dev/gemma-3n-E2B-it-int4.task")!,
            expectedSizeMB: 2992.0, // ~2.9 GB
            checksum: nil
        ),
        .gemma4B: DownloadableModelConfig(
            identifier: .gemma4B,
            downloadURL: URL(string: "https://pub-69c747d5957f4104a2f87b0aca35a2af.r2.dev/gemma-3n-E4B-it-int4.task")!,
            expectedSizeMB: 4608.0, // ~4.5 GB
            checksum: nil
        )
    ]
}

/// Model download status
enum ModelDownloadStatus: Equatable {
    case notStarted
    case downloading(progress: Double, bytesDownloaded: Int64, totalBytes: Int64)
    case verifying
    case extracting
    case completed
    case failed(error: String)
    case cancelled
    
    var isInProgress: Bool {
        switch self {
        case .downloading, .verifying, .extracting:
            return true
        default:
            return false
        }
    }
    
    var isCompleted: Bool {
        if case .completed = self {
            return true
        }
        return false
    }
}

/// Log entry for download events
struct DownloadLogEntry: Identifiable {
    let id = UUID()
    let timestamp: Date
    let message: String
    let type: LogType
    
    enum LogType {
        case info
        case success
        case error
        case progress
    }
    
    var icon: String {
        switch type {
        case .info: return "info.circle"
        case .success: return "checkmark.circle.fill"
        case .error: return "xmark.circle.fill"
        case .progress: return "arrow.down.circle"
        }
    }
}

/// Manages downloading and storing ML models at runtime
@MainActor
final class ModelDownloadManager: NSObject, ObservableObject {
    // MARK: - Published Properties
    @Published var downloadStatus: ModelDownloadStatus = .notStarted
    @Published var downloadSpeed: Double = 0.0 // MB/s
    @Published var estimatedTimeRemaining: TimeInterval = 0
    @Published var downloadLogs: [DownloadLogEntry] = []
    @Published var currentDownloadingModel: ModelIdentifier?
    
    // MARK: - Private Properties
    private var downloadTask: URLSessionDownloadTask?
    private var downloadStartTime: Date?
    private var lastProgressUpdate: Date?
    private var lastBytesDownloaded: Int64 = 0
    private var lastLoggedProgress: Int = -1 // Track last logged percentage to avoid spam
    private var resumeData: Data? // Store resume data for interrupted downloads
    private var currentModelIdentifier: ModelIdentifier? // Track which model we're downloading
    private var urlSession: URLSession?
    private var autoRetryCount: Int = 0
    private let maxAutoRetries: Int = 5 // Auto-retry up to 5 times on timeout
    
    // MARK: - Singleton
    static let shared = ModelDownloadManager()
    
    private override init() {
        super.init()
        setupBackgroundSession()
    }
    
    private func setupBackgroundSession() {
        let config = URLSessionConfiguration.background(withIdentifier: "com.pic2pdf.modeldownload")
        config.isDiscretionary = false // Don't let system delay the download
        config.sessionSendsLaunchEvents = true // Wake app when download completes
        config.timeoutIntervalForRequest = 300
        config.timeoutIntervalForResource = 14400 // 4 hours
        config.waitsForConnectivity = true
        config.allowsCellularAccess = true
        urlSession = URLSession(configuration: config, delegate: self, delegateQueue: nil)
    }
    
    // MARK: - Logging
    func addLog(_ message: String, type: DownloadLogEntry.LogType = .info) {
        let entry = DownloadLogEntry(timestamp: Date(), message: message, type: type)
        downloadLogs.append(entry)
        // Keep only last 100 logs
        if downloadLogs.count > 100 {
            downloadLogs.removeFirst()
        }
        NSLog("[ModelDownload] \(message)")
    }
    
    func clearLogs() {
        downloadLogs.removeAll()
    }
    
    // MARK: - Model Storage
    private var modelsDirectory: URL {
        let documentsDir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let modelsDir = documentsDir.appendingPathComponent("Models", isDirectory: true)
        try? FileManager.default.createDirectory(at: modelsDir, withIntermediateDirectories: true)
        return modelsDir
    }
    
    /// Get the local path for a model file
    func localModelPath(for identifier: ModelIdentifier) -> URL {
        return modelsDirectory.appendingPathComponent(identifier.fileName)
    }
    
    /// Check if a model is already downloaded
    func isModelDownloaded(_ identifier: ModelIdentifier) -> Bool {
        let path = localModelPath(for: identifier)
        return FileManager.default.fileExists(atPath: path.path)
    }
    
    /// Get the size of a downloaded model in MB
    func modelSize(_ identifier: ModelIdentifier) -> Double? {
        let path = localModelPath(for: identifier)
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: path.path),
              let fileSize = attributes[.size] as? Int64 else {
            return nil
        }
        return Double(fileSize) / (1024 * 1024)
    }
    
    // MARK: - Download Methods
    
    /// Download a model from the configured URL
    func downloadModel(_ identifier: ModelIdentifier) async throws {
        guard let config = DownloadableModelConfig.availableModels[identifier] else {
            throw ModelDownloadError.configurationNotFound
        }
        
        // Check if already downloaded
        if isModelDownloaded(identifier) {
            addLog("Model \(identifier.displayName) already downloaded", type: .success)
            downloadStatus = .completed
            return
        }
        
        // Check available disk space
        let requiredSpace = Int64(config.expectedSizeMB * 1024 * 1024)
        if !hasEnoughDiskSpace(requiredBytes: requiredSpace) {
            addLog("Insufficient disk space. Need \(Int(config.expectedSizeMB)) MB", type: .error)
            throw ModelDownloadError.insufficientDiskSpace(requiredMB: config.expectedSizeMB)
        }
        
        // Cancel any existing continuation to prevent leaks
        if let existingContinuation = downloadContinuation {
            addLog("Cancelling previous download", type: .info)
            existingContinuation.resume(throwing: ModelDownloadError.downloadFailed("Download cancelled - new download started"))
            downloadContinuation = nil
        }
        
        currentDownloadingModel = identifier
        downloadStatus = .downloading(progress: 0, bytesDownloaded: 0, totalBytes: Int64(config.expectedSizeMB * 1024 * 1024))
        downloadStartTime = Date()
        lastProgressUpdate = Date()
        lastBytesDownloaded = 0
        lastLoggedProgress = -1
        
        currentModelIdentifier = identifier
        
        addLog("Starting download: \(identifier.displayName)", type: .info)
        addLog("URL: \(config.downloadURL.absoluteString)", type: .info)
        addLog("Expected size: \(String(format: "%.1f", config.expectedSizeMB)) MB", type: .info)
        
        // Reset auto-retry count for new downloads (not resumes)
        if resumeData == nil {
            autoRetryCount = 0
        }
        
        // Ensure background session is set up
        if urlSession == nil {
            setupBackgroundSession()
        }
        
        addLog("Using background session for reliable download...", type: .info)
        
        return try await withCheckedThrowingContinuation { continuation in
            // Store continuation for completion callback
            self.downloadContinuation = continuation
            
            let task: URLSessionDownloadTask
            
            // Check if we have resume data from a previous interrupted download
            if let resumeData = self.resumeData {
                addLog("Resuming previous download...", type: .info)
                task = urlSession!.downloadTask(withResumeData: resumeData)
                self.resumeData = nil
            } else {
                task = urlSession!.downloadTask(with: config.downloadURL)
            }
            
            downloadTask = task
            
            self.addLog("Download task created, starting...", type: .progress)
            task.resume()
        }
    }
    
    /// Resume a failed download if resume data is available
    func canResumeDownload() -> Bool {
        return resumeData != nil && currentModelIdentifier != nil
    }
    
    /// Retry/resume the last failed download
    func retryDownload() async throws {
        guard let identifier = currentModelIdentifier else {
            throw ModelDownloadError.downloadFailed("No previous download to retry")
        }
        try await downloadModel(identifier)
    }
    
    /// Cancel ongoing download
    func cancelDownload() {
        downloadTask?.cancel()
        downloadTask = nil
        downloadStatus = .cancelled
    }
    
    /// Delete a downloaded model
    func deleteModel(_ identifier: ModelIdentifier) throws {
        let path = localModelPath(for: identifier)
        if FileManager.default.fileExists(atPath: path.path) {
            try FileManager.default.removeItem(at: path)
        }
    }
    
    // MARK: - Private Helper Methods
    
    private var downloadContinuation: CheckedContinuation<Void, Error>?
    
    private func hasEnoughDiskSpace(requiredBytes: Int64) -> Bool {
        guard let attributes = try? FileManager.default.attributesOfFileSystem(forPath: NSHomeDirectory()),
              let freeSpace = attributes[.systemFreeSize] as? Int64 else {
            return false
        }
        // Keep 500MB buffer
        return freeSpace > (requiredBytes + 500 * 1024 * 1024)
    }
    
    private func calculateDownloadSpeed(bytesDownloaded: Int64) {
        guard let lastUpdate = lastProgressUpdate else { return }
        
        let now = Date()
        let timeDiff = now.timeIntervalSince(lastUpdate)
        
        if timeDiff >= 1.0 { // Update speed every second
            let bytesDiff = bytesDownloaded - lastBytesDownloaded
            downloadSpeed = Double(bytesDiff) / (1024 * 1024) / timeDiff // MB/s
            
            lastProgressUpdate = now
            lastBytesDownloaded = bytesDownloaded
        }
    }
    
    private func calculateEstimatedTime(bytesDownloaded: Int64, totalBytes: Int64) {
        if downloadSpeed > 0 {
            let remainingBytes = totalBytes - bytesDownloaded
            let remainingMB = Double(remainingBytes) / (1024 * 1024)
            estimatedTimeRemaining = remainingMB / downloadSpeed
        }
    }
}

// MARK: - URLSessionDownloadDelegate
extension ModelDownloadManager: URLSessionDownloadDelegate {
    nonisolated func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        // CRITICAL: Must copy file SYNCHRONOUSLY before this delegate method returns
        // iOS deletes the temp file after this method completes!
        
        NSLog("[ModelDownload] Download finished, temp file at: \(location.path)")
        
        // Get identifier synchronously
        guard let originalURL = downloadTask.originalRequest?.url,
              let identifier = DownloadableModelConfig.availableModels.first(where: { $0.value.downloadURL == originalURL })?.key else {
            NSLog("[ModelDownload] ERROR: Unknown model")
            Task { @MainActor in
                self.addLog("Error: Unknown model URL", type: .error)
                self.downloadStatus = .failed(error: "Unknown model")
                self.downloadContinuation?.resume(throwing: ModelDownloadError.unknownModel)
                self.downloadContinuation = nil
            }
            return
        }
        
        let destination = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
            .appendingPathComponent("Models", isDirectory: true)
            .appendingPathComponent(identifier.fileName)
        
        // Copy file SYNCHRONOUSLY
        do {
            // Create Models directory if needed
            let modelsDir = destination.deletingLastPathComponent()
            try? FileManager.default.createDirectory(at: modelsDir, withIntermediateDirectories: true)
            
            Task { @MainActor in
                self.addLog("Download complete, copying to storage...", type: .progress)
            }
            
            // Remove existing file if present
            if FileManager.default.fileExists(atPath: destination.path) {
                try FileManager.default.removeItem(at: destination)
            }
            
            // Get file size
            let attributes = try FileManager.default.attributesOfItem(atPath: location.path)
            var fileSizeMB: Double = 0
            if let fileSize = attributes[.size] as? Int64 {
                fileSizeMB = Double(fileSize) / (1024 * 1024)
                NSLog("[ModelDownload] File size: \(fileSize) bytes (\(fileSizeMB) MB)")
            }
            
            // Copy file IMMEDIATELY
            try FileManager.default.copyItem(at: location, to: destination)
            
            ModelArtifactPrewarmer.prewarmArtifactsIfNeeded(for: identifier, sourceURL: destination)
            
            // Update UI on main actor and initialize the model
            Task { @MainActor in
                self.addLog("Model saved: \(String(format: "%.1f", fileSizeMB)) MB", type: .success)
                self.addLog("✅ \(identifier.displayName) ready to use!", type: .success)
                self.downloadStatus = .completed
                self.currentDownloadingModel = nil
                self.downloadContinuation?.resume()
                self.downloadContinuation = nil
                
                // Auto-initialize the LLM service with the newly downloaded model
                self.addLog("Initializing AI model...", type: .info)
                await OnDeviceLLMService.shared.initializeModel()
                self.addLog("AI model initialized and ready!", type: .success)
            }
            
        } catch {
            NSLog("[ModelDownload] ERROR: \(error)")
            
            Task { @MainActor in
                self.addLog("Error saving model: \(error.localizedDescription)", type: .error)
                self.downloadStatus = .failed(error: error.localizedDescription)
                self.currentDownloadingModel = nil
                self.downloadContinuation?.resume(throwing: error)
                self.downloadContinuation = nil
            }
        }
    }
    
    nonisolated func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        Task { @MainActor in
            let progress = Double(totalBytesWritten) / Double(totalBytesExpectedToWrite)
            let progressPercent = Int(progress * 100)
            
            downloadStatus = .downloading(progress: progress, bytesDownloaded: totalBytesWritten, totalBytes: totalBytesExpectedToWrite)
            
            calculateDownloadSpeed(bytesDownloaded: totalBytesWritten)
            calculateEstimatedTime(bytesDownloaded: totalBytesWritten, totalBytes: totalBytesExpectedToWrite)
            
            // Log progress at 10% intervals
            let logInterval = progressPercent / 10 * 10
            if logInterval > lastLoggedProgress && logInterval > 0 {
                lastLoggedProgress = logInterval
                let downloadedMB = Double(totalBytesWritten) / (1024 * 1024)
                let totalMB = Double(totalBytesExpectedToWrite) / (1024 * 1024)
                addLog("\(logInterval)% - \(String(format: "%.0f", downloadedMB))/\(String(format: "%.0f", totalMB)) MB", type: .progress)
            }
        }
    }
    
    nonisolated func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        Task { @MainActor in
            if let error = error {
                let nsError = error as NSError
                
                // Try to extract resume data for later retry
                if let resumeData = nsError.userInfo[NSURLSessionDownloadTaskResumeData] as? Data {
                    self.resumeData = resumeData
                    addLog("Download interrupted - resume data saved (\(resumeData.count / 1024) KB)", type: .info)
                }
                
                if nsError.code == NSURLErrorCancelled {
                    addLog("Download cancelled by user", type: .info)
                    downloadStatus = .cancelled
                    downloadContinuation?.resume(throwing: error)
                    currentDownloadingModel = nil
                    downloadContinuation = nil
                } else if nsError.code == -1001 && self.resumeData != nil && self.autoRetryCount < self.maxAutoRetries {
                    // Timeout with resume data available - auto retry!
                    self.autoRetryCount += 1
                    addLog("⏱️ Timeout detected, auto-resuming... (attempt \(self.autoRetryCount)/\(self.maxAutoRetries))", type: .info)
                    
                    // Small delay before retry
                    try? await Task.sleep(nanoseconds: 2_000_000_000) // 2 seconds
                    
                    // Auto-resume the download
                    if let identifier = self.currentModelIdentifier {
                        do {
                            // Don't clear the continuation - we're continuing the same download
                            let task = self.urlSession!.downloadTask(withResumeData: self.resumeData!)
                            self.resumeData = nil
                            self.downloadTask = task
                            self.addLog("Resuming download...", type: .progress)
                            task.resume()
                            // Don't resume continuation yet - wait for completion
                            return
                        } catch {
                            addLog("Auto-resume failed: \(error.localizedDescription)", type: .error)
                        }
                    }
                    
                    // If auto-resume setup failed, fall through to normal error handling
                    downloadStatus = .failed(error: "Auto-resume failed")
                    downloadContinuation?.resume(throwing: error)
                    currentDownloadingModel = nil
                    downloadContinuation = nil
                } else {
                    addLog("Download failed: \(error.localizedDescription)", type: .error)
                    addLog("Error code: \(nsError.code)", type: .error)
                    
                    // Provide more helpful error messages
                    if nsError.code == -1001 {
                        if self.autoRetryCount >= self.maxAutoRetries {
                            addLog("Max auto-retries reached. Tap 'Retry' to continue manually.", type: .info)
                        } else {
                            addLog("Tip: Tap 'Retry' to resume from where it stopped", type: .info)
                        }
                    }
                    
                    downloadStatus = .failed(error: error.localizedDescription)
                    downloadContinuation?.resume(throwing: error)
                    currentDownloadingModel = nil
                    downloadContinuation = nil
                }
            }
        }
    }
    
    nonisolated func urlSession(_ session: URLSession, didBecomeInvalidWithError error: Error?) {
        Task { @MainActor in
            if let error = error {
                addLog("Session error: \(error.localizedDescription)", type: .error)
                downloadStatus = .failed(error: error.localizedDescription)
                currentDownloadingModel = nil
                downloadContinuation?.resume(throwing: error)
                downloadContinuation = nil
            }
            // Recreate the session
            setupBackgroundSession()
        }
    }
    
    // Handle background session events (called when app wakes up)
    nonisolated func urlSessionDidFinishEvents(forBackgroundURLSession session: URLSession) {
        Task { @MainActor in
            addLog("Background session events completed", type: .info)
        }
    }
}

// MARK: - Error Types
enum ModelDownloadError: LocalizedError {
    case configurationNotFound
    case insufficientDiskSpace(requiredMB: Double)
    case checksumMismatch
    case unknownModel
    case downloadFailed(String)
    
    var errorDescription: String? {
        switch self {
        case .configurationNotFound:
            return "Model configuration not found"
        case .insufficientDiskSpace(let requiredMB):
            return "Insufficient disk space. Need at least \(Int(requiredMB))MB free"
        case .checksumMismatch:
            return "Downloaded file checksum verification failed"
        case .unknownModel:
            return "Unknown model identifier"
        case .downloadFailed(let reason):
            return "Download failed: \(reason)"
        }
    }
}

