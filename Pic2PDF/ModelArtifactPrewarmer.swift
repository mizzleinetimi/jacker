//
//  ModelArtifactPrewarmer.swift
//  Pic2PDF
//
//  Created to pre-extract MediaPipe vision components off the main thread
//

import Foundation
import ZIPFoundation
import os.log

enum ModelArtifactPrewarmer {
    private static let visionEncoderFileName = "TF_LITE_VISION_ENCODER"
    private static let visionAdapterFileName = "TF_LITE_VISION_ADAPTER"
    private static let log = OSLog(subsystem: "com.pic2pdf.app", category: "ModelPrewarm")
    
    /// Copies the downloaded `.task` file into Application Support and extracts the vision encoder/adapter if needed.
    static func prewarmArtifactsIfNeeded(for identifier: ModelIdentifier, sourceURL: URL) {
        Task.detached(priority: .utility) {
            do {
                try performPrewarm(for: identifier, sourceURL: sourceURL)
                os_log("Prewarmed artifacts for %{public}@", log: log, type: .info, identifier.displayName)
            } catch {
                os_log("Prewarm failed for %{public}@ - %{public}@", log: log, type: .error, identifier.displayName, error.localizedDescription)
            }
        }
    }
    
    private static func performPrewarm(for identifier: ModelIdentifier, sourceURL: URL) throws {
        let fileManager = FileManager.default
        let cacheDir = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        try fileManager.createDirectory(at: cacheDir, withIntermediateDirectories: true)
        
        let cachedTaskURL = cacheDir.appendingPathComponent(identifier.fileName)
        if !fileManager.fileExists(atPath: cachedTaskURL.path) {
            try? fileManager.removeItem(at: cachedTaskURL)
            try fileManager.copyItem(at: sourceURL, to: cachedTaskURL)
        }
        
        let encoderURL = cacheDir.appendingPathComponent(visionEncoderFileName)
        let adapterURL = cacheDir.appendingPathComponent(visionAdapterFileName)
        
        if fileManager.fileExists(atPath: encoderURL.path),
           fileManager.fileExists(atPath: adapterURL.path) {
            return
        }
        
        let archive = try Archive(url: cachedTaskURL, accessMode: .read)
        try extract(entryNamed: visionEncoderFileName, from: archive, to: encoderURL)
        try extract(entryNamed: visionAdapterFileName, from: archive, to: adapterURL)
    }
    
    private static func extract(entryNamed name: String, from archive: Archive, to destination: URL) throws {
        let fileManager = FileManager.default
        if fileManager.fileExists(atPath: destination.path) {
            try fileManager.removeItem(at: destination)
        }
        guard let entry = archive[name] else {
            throw NSError(domain: "ModelArtifactPrewarmer", code: -1, userInfo: [NSLocalizedDescriptionKey: "Missing \(name) in archive"])
        }
        _ = try archive.extract(entry, to: destination)
    }
}

