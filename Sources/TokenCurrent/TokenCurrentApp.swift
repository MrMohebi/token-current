#if os(macOS)
import SwiftUI

@main
struct TokenCurrentApp: App {
    @State private var model = MonitorModel()

    var body: some Scene {
        MenuBarExtra {
            MeterPopover(model: model)
        } label: {
            MenuBarReadout(model: model)
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView(model: model)
        }
    }
}
#else
import Foundation

@main
enum UnsupportedPlatform {
    static func main() {
        FileHandle.standardError.write(Data("Token Current's interface requires macOS 14 or later. The accounting library and tests run on Linux.\n".utf8))
    }
}
#endif
