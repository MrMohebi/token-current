#if os(macOS)
import Foundation
import TokenCurrentCore

enum SourceFilter: String, CaseIterable, Codable, Identifiable {
    case all, claude, codex
    var id: String { rawValue }
    var title: String {
        switch self { case .all: "All"; case .claude: "Claude"; case .codex: "Codex" }
    }
    var provider: Provider? { Provider(rawValue: rawValue) }
}

enum DisplayDensity: String, CaseIterable, Codable, Identifiable {
    case standard, compact, icon
    var id: String { rawValue }
    var title: String {
        switch self { case .standard: "Rate and unit"; case .compact: "Compact rate"; case .icon: "Icon only" }
    }
}

struct AppPreferences: Codable {
    var sources = SourceConfiguration.autodetected()
    var filter = SourceFilter.all
    var density = DisplayDensity.standard

    static func load() -> Self {
        guard let data = UserDefaults.standard.data(forKey: "preferences"),
              let value = try? JSONDecoder().decode(Self.self, from: data) else { return Self() }
        return value
    }

    func save() {
        if let data = try? JSONEncoder().encode(self) { UserDefaults.standard.set(data, forKey: "preferences") }
    }
}
#endif
