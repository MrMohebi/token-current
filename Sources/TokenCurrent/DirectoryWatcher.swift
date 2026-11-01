#if os(macOS)
import Foundation
import Darwin

/// Notifications accelerate discovery; the engine's 30-second scan remains the fallback.
@MainActor
final class DirectoryWatcher {
    private var sources: [DispatchSourceFileSystemObject] = []
    private let action: @Sendable () -> Void

    init(action: @escaping @Sendable () -> Void) { self.action = action }

    func watch(_ directories: [URL]) {
        for source in sources { source.cancel() }
        sources.removeAll()
        // Bound descriptors on machines with thousands of historical session directories.
        for directory in directories.prefix(256) {
            let descriptor = open(directory.path, O_EVTONLY)
            guard descriptor >= 0 else { continue }
            let source = DispatchSource.makeFileSystemObjectSource(fileDescriptor: descriptor,
                eventMask: [.write, .rename, .delete], queue: .global(qos: .utility))
            source.setEventHandler(handler: action)
            source.setCancelHandler { close(descriptor) }
            source.resume()
            sources.append(source)
        }
    }
}
#endif
