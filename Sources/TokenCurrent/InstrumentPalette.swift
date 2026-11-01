#if os(macOS)
import SwiftUI
import TokenCurrentCore

enum InstrumentPalette {
    static func color(for provider: Provider, scheme: ColorScheme) -> Color {
        switch (provider, scheme) {
        case (.claude, .dark): Color(red: 0.35, green: 0.85, blue: 0.91)
        case (.claude, _): Color(red: 0.00, green: 0.40, blue: 0.46)
        case (.codex, .dark): Color(red: 0.98, green: 0.74, blue: 0.36)
        case (.codex, _): Color(red: 0.53, green: 0.32, blue: 0.03)
        }
    }
}
#endif
