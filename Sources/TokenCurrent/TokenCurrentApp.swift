#if os(macOS)
import SwiftUI
import TokenCurrentCore
import Darwin

@main
struct TokenCurrentApp: App {
    @State private var model: MonitorModel

    init() {
        let arguments = CommandLine.arguments
        let check = arguments.firstIndex(of: "--check-tailnet")
        _model = State(initialValue: MonitorModel(startMonitoring: check == nil))
        if let check {
            let address = arguments.indices.contains(check + 1) ? arguments[check + 1] : ""
            Task { @MainActor in
                do {
                    guard let origin = MeshAPI.tailscaleOrigin(address) else { throw MeshAPIError.endpoint }
                    let result = try await MeshAPI(origin: origin, trustTailscale: true).mesh()
                    guard result.machines.count == 1 else { throw MeshAPIError.invalid }
                    FileHandle.standardOutput.write(Data("Connected to Tailscale agent (1 machine).\n".utf8))
                    exit(0)
                } catch {
                    FileHandle.standardError.write(Data("Tailscale connection failed: \(error.localizedDescription)\n".utf8))
                    exit(1)
                }
            }
        }
    }

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
