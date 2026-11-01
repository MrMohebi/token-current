#if os(macOS)
import SwiftUI
import ServiceManagement
import TokenCurrentCore

@Observable @MainActor
final class MonitorModel {
    private var preferences: AppPreferences
    private var engine: MonitoringEngine?
    private var monitorTask: Task<Void, Never>?
    private var watcher: DirectoryWatcher?
    private var watchedPaths: [URL] = []
    private var monitoringError: String?

    let mesh = MeshController()
    var snapshot = MonitorSnapshot()
    var errorMessage: String?
    var filter: SourceFilter { didSet { preferences.filter = filter; preferences.save() } }
    var density: DisplayDensity { didSet { preferences.density = density; preferences.save() } }
    var claudeHome: String
    var codexHome: String
    var launchAtLogin = SMAppService.mainApp.status == .enabled
    var needsLoginApproval = SMAppService.mainApp.status == .requiresApproval
    var wantsLaunchAtLogin: Bool {
        get { launchAtLogin || needsLoginApproval }
        set { setLaunchAtLogin(newValue) }
    }
    var isApplyingSources = false
    var isPaused = false

    init(startMonitoring: Bool = true) {
        let settings = AppPreferences.load()
        preferences = settings
        filter = settings.filter
        density = settings.density
        claudeHome = settings.sources.claudeHome
        codexHome = settings.sources.codexHome
        if startMonitoring { monitorTask = Task { [weak self] in await self?.run() } }
    }

    var rate: Double? { monitoringError == nil || mesh.isEnabled ? snapshot.rate(for: filter.provider) : nil }
    var totals: TokenCounts { snapshot.total(for: filter.provider) }
    var selectedProviders: [Provider] { filter.provider.map { [$0] } ?? Provider.allCases }
    var hasMeasurement: Bool { selectedProviders.contains { snapshot.health[$0]?.isMeasurable == true } }
    var displayedError: String? { errorMessage ?? monitoringError ?? (mesh.isEnabled ? mesh.error : nil) }
    var status: String {
        if displayedError != nil { return "Needs attention" }
        if isPaused { return mesh.isEnabled ? "Local paused" : "Paused" }
        if snapshot.importing { return "Reading history" }
        if let rate { return rate > 0 ? "Reporting" : "Idle" }
        if selectedProviders.contains(where: { snapshot.health[$0] == .unsupported }) { return "Update needed" }
        return "Waiting for usage"
    }

    func applySources() async {
        guard !isApplyingSources else { return }
        let claude = claudeHome.trimmingCharacters(in: .whitespacesAndNewlines)
        let codex = codexHome.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !claude.isEmpty, !codex.isEmpty,
              (claude.hasPrefix("/") || claude.hasPrefix("~/")),
              (codex.hasPrefix("/") || codex.hasPrefix("~/")) else {
            errorMessage = "Use an absolute folder path or a path starting with ~/."
            return
        }
        isApplyingSources = true
        defer { isApplyingSources = false }
        preferences.sources = SourceConfiguration(claudeHome: claude, codexHome: codex)
        preferences.save()
        await engine?.configure(preferences.sources)
        snapshot = MonitorSnapshot(paused: isPaused)
        errorMessage = nil
    }

    func togglePause() async {
        isPaused.toggle()
        await engine?.setPaused(isPaused)
        snapshot.paused = isPaused
    }

    func clearHistory() async {
        do {
            try await engine?.clearHistory()
            if let engine {
                var calendar = Calendar.current
                if mesh.isEnabled { calendar.timeZone = TimeZone(secondsFromGMT: 0)! }
                let local = try await engine.tick(calendar: calendar)
                snapshot = mesh.isEnabled ? mesh.update(local: local, available: true) : local
            }
            errorMessage = nil
        } catch { errorMessage = "Could not clear local history: \(error.localizedDescription)" }
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled { try SMAppService.mainApp.register() }
            else { try SMAppService.mainApp.unregister() }
            refreshLoginStatus()
        } catch {
            refreshLoginStatus()
            errorMessage = "Could not change login launch: \(error.localizedDescription)"
        }
    }

    func refreshLoginStatus() {
        launchAtLogin = SMAppService.mainApp.status == .enabled
        needsLoginApproval = SMAppService.mainApp.status == .requiresApproval
    }

    private func run() async {
        do {
            let directory = URL.applicationSupportDirectory.appending(path: "Token Current", directoryHint: .isDirectory)
            var useUTC = mesh.isEnabled
            var engine = try MonitoringEngine(databasePath: directory.appending(path: useUTC ? "network-usage.sqlite" : "usage.sqlite").path,
                                              configuration: preferences.sources)
            self.engine = engine
            watcher = DirectoryWatcher { [weak self] in
                Task { @MainActor [weak self] in await self?.engine?.requestDiscovery() }
            }
            while !Task.isCancelled {
                do {
                    if useUTC != mesh.isEnabled {
                        useUTC = mesh.isEnabled
                        engine = try MonitoringEngine(databasePath: directory.appending(path: useUTC ? "network-usage.sqlite" : "usage.sqlite").path,
                                                      configuration: preferences.sources)
                        self.engine = engine
                        await engine.setPaused(isPaused)
                    }
                    var calendar = Calendar.current
                    if useUTC { calendar.timeZone = TimeZone(secondsFromGMT: 0)! }
                    let local = try await engine.tick(calendar: calendar)
                    snapshot = useUTC ? mesh.update(local: local, available: true) : local
                    monitoringError = nil
                    let paths = await engine.watchedDirectories()
                    if paths != watchedPaths { watcher?.watch(paths); watchedPaths = paths }
                } catch { monitoringError = "Monitoring stopped: \(error.localizedDescription)" }
                try await Task.sleep(for: .seconds(1))
            }
        } catch is CancellationError {
            return
        } catch {
            snapshot.importing = false
            monitoringError = "Could not open local storage: \(error.localizedDescription). Quit and reopen to retry."
        }
    }
}
#endif
