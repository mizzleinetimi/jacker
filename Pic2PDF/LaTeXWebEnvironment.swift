//
//  LaTeXWebEnvironment.swift
//  Pic2PDF
//
//  Shared WKWebView configuration and local latex.js asset handling.
//

import Foundation
import WebKit

final class LaTeXWebEnvironment {
    static let shared = LaTeXWebEnvironment()
    
    let processPool = WKProcessPool()
    private let resourcesBaseURL: URL?
    
    private init() {
        if let scriptURL = Bundle.main.url(forResource: "latex.min", withExtension: "js", subdirectory: "WebResources/latexjs") {
            resourcesBaseURL = scriptURL.deletingLastPathComponent()
        } else {
            resourcesBaseURL = nil
        }
    }
    
    var baseURL: URL? {
        resourcesBaseURL
    }
    
    var scriptTag: String {
        if resourcesBaseURL != nil {
            return "<script src=\"latex.min.js\"></script>"
        }
        return "<script src=\"https://cdn.jsdelivr.net/npm/latex.js/dist/latex.min.js\"></script>"
    }
    
    var styleTag: String {
        if resourcesBaseURL != nil {
            return "<link rel=\"stylesheet\" href=\"latex.min.css\">"
        }
        return ""
    }
    
    func makeConfiguration(userContentController: WKUserContentController? = nil) -> WKWebViewConfiguration {
        let config = WKWebViewConfiguration()
        config.processPool = processPool
        config.userContentController = userContentController ?? WKUserContentController()
        return config
    }
}


