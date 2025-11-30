//
//  LLMEngine.swift
//  Pic2PDF
//
//  Lightweight actor that owns the OnDeviceModel and session cache so
//  heavy MediaPipe work never touches the main actor.
//

import Foundation
import MediaPipeTasksGenAI

actor LLMEngine {
    struct SessionKey: Hashable {
        let topK: Int
        let topP: Float
        let temperature: Float
        let enableVision: Bool
    }
    
    private var onDeviceModel: OnDeviceModel?
    private var cachedSessions: [SessionKey: LlmInference.Session] = [:]
    
    func initializeModel(identifier: ModelIdentifier, maxTokens: Int) throws -> OnDeviceModel {
        let model = try OnDeviceModel(modelIdentifier: identifier, maxTokens: maxTokens)
        onDeviceModel = model
        cachedSessions.removeAll()
        return model
    }
    
    func currentModelIdentifier() -> ModelIdentifier? {
        return onDeviceModel?.identifier
    }
    
    func session(for key: SessionKey) throws -> LlmInference.Session {
        guard let model = onDeviceModel else {
            throw OnDeviceLLMError.notInitialized
        }
        
        if let template = cachedSessions[key] {
            do {
                return try template.clone()
            } catch {
                cachedSessions.removeValue(forKey: key)
            }
        }
        
        let options = LlmInference.Session.Options()
        options.topk = key.topK
        options.topp = key.topP
        options.temperature = key.temperature
        options.enableVisionModality = key.enableVision
        
        let template = try LlmInference.Session(llmInference: model.inference, options: options)
        
        if let clone = try? template.clone() {
            cachedSessions[key] = template
            return clone
        } else {
            return template
        }
    }
    
    func resetSessions() {
        cachedSessions.removeAll()
    }
}

