import SwiftUI

// Cove's look, the same as Conch's Claude themes: native structure (navigation,
// lists, sheets, Liquid Glass controls) in Claude's warm palette. Grouped pages
// (lists, settings) sit on a slightly deeper canvas with lighter cards; content
// pages (minutes, transcript, chat) sit on one even surface.

enum CoveColor {
    static let canvas = Color(light: 0xFAF9F5, dark: 0x262624)
    static let grouped = Color(light: 0xF5F4EE, dark: 0x1F1E1D)
    static let card = Color(light: 0xFFFFFF, dark: 0x2B2A27)
    static let text = Color(light: 0x3D3929, dark: 0xE8E6DC)
    static let accent = Color(light: 0xD97757, dark: 0xD97757)

    /// Speaker colors, from the Claude terminal themes' ANSI palette.
    private static let speakers: [Color] = [
        Color(light: 0xB8412E, dark: 0xEE8672),
        Color(light: 0x3D6E9E, dark: 0x8DB3DB),
        Color(light: 0x5E7A3C, dark: 0xB4C996),
        Color(light: 0x8F4F7E, dark: 0xD6A9C9),
        Color(light: 0xA0680E, dark: 0xF0C888),
        Color(light: 0x3F7F78, dark: 0x9CCBC4),
    ]

    static func speaker(_ index: Int) -> Color { speakers[abs(index) % speakers.count] }
}

/// Light / dark / follow the system, chosen in Settings.
enum Appearance: String, CaseIterable, Identifiable {
    case system, light, dark
    var id: String { rawValue }
    var label: String {
        switch self {
        case .system: "跟随系统"
        case .light: "Claude 昼"
        case .dark: "Claude 夜"
        }
    }
    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }
}

extension View {
    /// A List or Form on the grouped canvas. Give its Sections `.coveCard()`.
    func coveGroupedBackground() -> some View {
        scrollContentBackground(.hidden).background(CoveColor.grouped)
    }

    /// The rows of a Section on `coveGroupedBackground()`.
    func coveCard() -> some View {
        listRowBackground(CoveColor.card)
    }

    /// A content page on the canvas.
    func coveCanvas() -> some View {
        background(CoveColor.canvas)
    }
}

/// A small label next to a name ("本地", "说话人 1"): one quiet style everywhere.
struct CoveTag: View {
    let text: String

    var body: some View {
        Text(verbatim: text)
            .font(.system(size: 9, weight: .semibold))
            .kerning(0.4)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 5)
            .padding(.vertical, 1.5)
            .background(Color.primary.opacity(0.07), in: Capsule())
    }
}

extension Color {
    /// A color that follows light and dark mode (including the app's own override).
    init(light: UInt32, dark: UInt32) {
        func components(_ hex: UInt32) -> (CGFloat, CGFloat, CGFloat) {
            (CGFloat((hex >> 16) & 0xFF) / 255, CGFloat((hex >> 8) & 0xFF) / 255, CGFloat(hex & 0xFF) / 255)
        }
        let (lr, lg, lb) = components(light)
        let (dr, dg, db) = components(dark)
        self.init(uiColor: UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor(red: dr, green: dg, blue: db, alpha: 1)
                : UIColor(red: lr, green: lg, blue: lb, alpha: 1)
        })
    }
}

/// Liquid Glass where the system has it, a material capsule before that.
struct GlassCapsule: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 26, *) {
            content.glassEffect(.regular.interactive(), in: .capsule)
        } else {
            content
                .background(.regularMaterial, in: Capsule())
                .shadow(color: .black.opacity(0.08), radius: 12, y: 4)
        }
    }
}

/// Shrinks a touch while pressed, the way system cards respond.
struct PressableStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .opacity(configuration.isPressed ? 0.85 : 1)
            .animation(.snappy(duration: 0.18), value: configuration.isPressed)
    }
}

/// "1:02:03" or "02:03".
func clockString(_ seconds: TimeInterval) -> String {
    let total = max(0, Int(seconds))
    let h = total / 3600, m = total / 60 % 60, s = total % 60
    return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%02d:%02d", m, s)
}
