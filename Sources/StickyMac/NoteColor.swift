import SwiftUI

enum NoteColor: String, Codable, CaseIterable, Identifiable {
    case lemon, peach, rose, mint, sky, lavender, graphite

    var id: String { rawValue }

    var name: String { rawValue.capitalized }

    /// Top and bottom of the note's soft vertical gradient.
    var top: Color {
        switch self {
        case .lemon:    return Color(hex: 0xFFF6A8)
        case .peach:    return Color(hex: 0xFFD8B0)
        case .rose:     return Color(hex: 0xFFC6D9)
        case .mint:     return Color(hex: 0xC8F5D2)
        case .sky:      return Color(hex: 0xC4E4FF)
        case .lavender: return Color(hex: 0xE0D2FF)
        case .graphite: return Color(hex: 0x3A3D45)
        }
    }

    var bottom: Color {
        switch self {
        case .lemon:    return Color(hex: 0xFFE76B)
        case .peach:    return Color(hex: 0xFFBC85)
        case .rose:     return Color(hex: 0xFFA3C2)
        case .mint:     return Color(hex: 0x9EE8B2)
        case .sky:      return Color(hex: 0x98CEFF)
        case .lavender: return Color(hex: 0xC8B2FF)
        case .graphite: return Color(hex: 0x24262C)
        }
    }

    var ink: Color { self == .graphite ? Color(hex: 0xF2F2F5) : Color(hex: 0x2B2A26) }
    var isDark: Bool { self == .graphite }
}

extension Color {
    init(hex: UInt32) {
        self.init(
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255
        )
    }
}
