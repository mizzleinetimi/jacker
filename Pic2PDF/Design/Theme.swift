//
//  Theme.swift
//  Pic2PDF
//
//  Created by AI Assistant on 2025-12-01.
//

import SwiftUI

/// Central design system for the application
struct Theme {
    // MARK: - Reading Themes
    
    enum ReadingTheme: String, CaseIterable, Identifiable {
        case paper
        case sage
        case sepia
        case ocean
        case midnight
        
        var id: String { rawValue }
        
        var background: Color {
            switch self {
            case .paper: return Color(hex: "F9F7F1")
            case .sage: return Color(hex: "E9F2E9")
            case .sepia: return Color(hex: "F4ECD8")
            case .ocean: return Color(hex: "E8F1F5")
            case .midnight: return Color(hex: "1C1C1E")
            }
        }
        
        var text: Color {
            switch self {
            case .paper: return Color(hex: "2C2C2E")
            case .sage: return Color(hex: "1A331A")
            case .sepia: return Color(hex: "4A3B2A")
            case .ocean: return Color(hex: "1A2A33")
            case .midnight: return Color(hex: "E5E5EA")
            }
        }
        
        var secondaryText: Color {
            switch self {
            case .midnight: return Color(hex: "98989D")
            default: return text.opacity(0.6)
            }
        }
        
        var displayName: String {
            switch self {
            case .paper: return "Paper"
            case .sage: return "Sage"
            case .sepia: return "Sepia"
            case .ocean: return "Ocean"
            case .midnight: return "Midnight"
            }
        }
    }
    
    // MARK: - Global Colors
    
    static let accent = Color.blue
    
    // MARK: - Typography
    
    /// Serif font for reading content (Book-like)
    static func readingFont(size: CGFloat = 18, weight: Font.Weight = .regular) -> Font {
        return .system(size: size, weight: weight, design: .serif)
    }
    
    /// Sans-serif font for UI elements (Clean)
    static func uiFont(size: CGFloat = 16, weight: Font.Weight = .regular) -> Font {
        return .system(size: size, weight: weight, design: .default)
    }
    
    // MARK: - Dynamic Colors (App UI)
    
    static var background: Color {
        Color(UIColor { traitCollection in
            return traitCollection.userInterfaceStyle == .dark ? UIColor(ReadingTheme.midnight.background) : UIColor(ReadingTheme.paper.background)
        })
    }
    
    static var secondaryBackground: Color {
        Color(UIColor { traitCollection in
            return traitCollection.userInterfaceStyle == .dark ? UIColor(hex: "2C2C2E") : UIColor(hex: "FFFFFF")
        })
    }
    
    static var text: Color {
        Color(UIColor { traitCollection in
            return traitCollection.userInterfaceStyle == .dark ? UIColor(ReadingTheme.midnight.text) : UIColor(ReadingTheme.paper.text)
        })
    }
    
    static var secondaryText: Color {
        Color(UIColor { traitCollection in
            return traitCollection.userInterfaceStyle == .dark ? UIColor(hex: "98989D") : UIColor(hex: "8E8E93")
        })
    }
}

// MARK: - Extensions

extension UIColor {
    convenience init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3: // RGB (12-bit)
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6: // RGB (24-bit)
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: // ARGB (32-bit)
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (1, 1, 1, 0)
        }
        
        self.init(
            red: CGFloat(r) / 255,
            green: CGFloat(g) / 255,
            blue: CGFloat(b) / 255,
            alpha: CGFloat(a) / 255
        )
    }
}

extension Color {
    init(hex: String) {
        self.init(uiColor: UIColor(hex: hex))
    }
}

struct CalmShadow: ViewModifier {
    @Environment(\.colorScheme) var colorScheme
    
    func body(content: Content) -> some View {
        content
            .shadow(
                color: colorScheme == .dark ? Color.black.opacity(0.3) : Color.black.opacity(0.05),
                radius: 10,
                x: 0,
                y: 4
            )
    }
}

struct CardStyle: ViewModifier {
    var backgroundColor: Color
    
    func body(content: Content) -> some View {
        content
            .background(backgroundColor)
            .cornerRadius(24) // More rounded for "Card" look
            .calmShadow()
    }
}

extension View {
    func calmShadow() -> some View {
        modifier(CalmShadow())
    }
    
    func cardStyle(backgroundColor: Color = Theme.secondaryBackground) -> some View {
        modifier(CardStyle(backgroundColor: backgroundColor))
    }
}
