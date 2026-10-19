import Foundation
import Combine
import AppKit
import Network
import OSLog

@MainActor public final class QuotaService: ObservableObject {
    @Published public private(set) var state: QuotaState = .loading
    @Published public private(set) var snapshot: QuotaSnapshot?
    @Published public private(set) var message: String?
    @Published public private(set) var refreshing = false
    @Published public private(set) var cliLocation = "Not detected"
    @Published public private(set) var cliVersion = "Unknown"
    private let client: CodexAppServerClient
    private let settings: AppSettings
    private var timer: Task<Void, Never>?
    private var refreshTask: Task<Void, Never>?
    private var subscriptions = Set<AnyCancellable>()
    private var retry = RetryPolicy()
    private let monitor = NWPathMonitor()
    private var wasOnline: Bool?
    private var active = false
    private var epoch = 0
    private var identityInvalidated = false
    private var knownIdentity: String?
    private var authRevision = 0
    private let cacheFile: URL?
    private let serverArguments: [String]
    private let logger = Logger(subsystem: "com.local.CodexQuotaRing", category: "connection")
    private var cacheURL: URL {
        cacheFile ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("CodexQuotaRing", isDirectory: true).appendingPathComponent("quota-cache.json")
    }
    public init(settings: AppSettings, client: CodexAppServerClient? = nil, cacheFile: URL? = nil, serverArguments: [String] = ["app-server"]) {
        self.settings = settings; self.client = client ?? CodexAppServerClient()
        self.cacheFile = cacheFile; self.serverArguments = serverArguments
        // A disk cache is never shown until account/read verifies its identity in this session.
        self.client.onNotification = { [weak self] method, _ in
            guard let self else { return }
            if method == "account/updated" {
                self.authRevision += 1
                if self.knownIdentity != nil || self.snapshot != nil {
                    self.identityInvalidated = true; self.clearCache()
                }
                // App Server emits this during initialization too. Never restart it here.
                // In-flight reads are discarded below if authentication changes during them.
                if !self.refreshing { self.refresh() }
            } else if method == "account/rateLimits/updated" { self.refresh() }
        }
        self.client.onDisconnect = { [weak self] in
            guard let self, self.active else { return }
            if !self.refreshing { self.fail(QuotaError.disconnected); self.schedule(self.retry.failed()) }
        }
        settings.$interval.dropFirst().sink { [weak self] value in self?.schedule(value) }.store(in: &subscriptions)
        NotificationCenter.default.publisher(for: NSWorkspace.didWakeNotification, object: nil)
            .sink { [weak self] _ in Task { @MainActor in self?.refresh() } }.store(in: &subscriptions)
        // Workspace notifications use NSWorkspace's own center.
        NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didWakeNotification)
            .sink { [weak self] _ in Task { @MainActor in self?.refresh() } }.store(in: &subscriptions)
        monitor.pathUpdateHandler = { [weak self] path in
            let online = path.status == .satisfied
            Task { @MainActor in
                guard let self else { return }
                let recovered = self.wasOnline == false && online
                self.wasOnline = online
                if recovered { self.refresh() }
            }
        }
    }
    public func start() {
        guard !active else { return }; active = true
        monitor.start(queue: DispatchQueue(label: "quota.network")); refresh()
    }
    public func stop() {
        active = false; epoch += 1; timer?.cancel(); refreshTask?.cancel(); client.stop(); monitor.cancel()
        subscriptions.removeAll()
    }
    public func reconnect() {
        epoch += 1; refreshTask?.cancel(); refreshTask = nil; refreshing = false
        timer?.cancel(); client.stop(); retry.succeeded()
        // A new executable may refer to a different account or CODEX_HOME.
        clearCache(); refresh()
    }
    public func refresh() {
        guard active, !refreshing else { return }
        refreshing = true; timer?.cancel()
        if snapshot == nil { state = .loading }; message = nil
        let token = epoch
        refreshTask = Task { [weak self] in
            guard let self else { return }
            do {
                let executable = try CodexCLIResolver.resolve(override: self.settings.cliPath)
                self.cliLocation = executable.path
                if !self.client.isRunning {
                    try await self.client.start(executable: executable, arguments: self.serverArguments)
                    self.readVersion(executable)
                }
                let revision = self.authRevision
                let before = try await self.client.request("account/read", params: ["refreshToken": false])
                let identity = try QuotaParser.identity(before)
                guard self.epoch == token, !Task.isCancelled else { return }
                if (self.snapshot != nil && self.snapshot?.identityHash != identity) || identity == nil { self.clearCache() }
                self.knownIdentity = identity
                self.restoreCache(identity: identity)
                let response = try await self.client.request("account/rateLimits/read")
                // Verify that login did not change while the quota request was in flight.
                let after = try await self.client.request("account/read", params: ["refreshToken": false])
                guard try QuotaParser.identity(after) == identity else {
                    self.clearCache(); throw QuotaError.unauthenticated
                }
                guard self.epoch == token, !Task.isCancelled else { return }
                guard revision == self.authRevision else {
                    self.refreshing = false; self.state = .loading; self.schedule(1); return
                }
                let fresh = QuotaParser.parse(response, identity: identity)
                if let old = self.snapshot?.accountHash, let new = fresh.accountHash, old != new { self.clearCache() }
                self.snapshot = fresh; self.identityInvalidated = false
                self.state = fresh.windows.isEmpty ? .noQuotaData : .ready
                self.message = fresh.windows.isEmpty ? "No supported 5-hour or weekly Codex quota windows were returned." : nil
                if identity == nil { self.message = "Account identity unavailable. This live response is not cached." }
                self.saveCache(fresh); self.retry.succeeded(); self.refreshing = false
                self.schedule(self.nextDelay(fresh))
                self.log("Quota synchronized")
            } catch {
                guard self.epoch == token, !Task.isCancelled else { return }
                self.refreshing = false
                if case QuotaError.timeout = error { self.client.stop() }
                self.fail(error); self.schedule(self.retry.failed())
            }
        }
    }
    private func nextDelay(_ fresh: QuotaSnapshot) -> Double {
        // A future reset triggers a read. A past reset never fabricates a refill or causes a tight loop.
        let future = fresh.windows.compactMap(\.resetsAt).map { $0.timeIntervalSinceNow }.filter { $0 > 0 }
        return min(settings.interval, future.min().map { max(1, $0 + 1) } ?? settings.interval)
    }
    private func schedule(_ seconds: Double) {
        timer?.cancel(); guard active else { return }
        timer = Task { [weak self] in
            do { try await Task.sleep(nanoseconds: UInt64(max(1, seconds) * 1_000_000_000)) } catch { return }
            self?.refresh()
        }
    }
    private func fail(_ error: Error) {
        if case QuotaError.unauthenticated = error { clearCache(); state = .unauthenticated }
        else if case QuotaError.unsupportedAccount = error { clearCache(); state = .noQuotaData }
        else if case QuotaError.cliUnavailable = error { clearCache(); state = .cliUnavailable }
        else { state = snapshot == nil ? .error : .stale }
        message = (error as? QuotaError)?.localizedDescription ?? "Unable to synchronize Codex quota. Retry or reconnect in Settings."
        if snapshot != nil { message! += " Cached data is stale; its current account source is unverified." }
        log("Quota synchronization failed")
    }
    private func clearCache() {
        snapshot = nil; knownIdentity = nil
        try? FileManager.default.removeItem(at: cacheURL)
    }
    private func restoreCache(identity: String?) {
        guard snapshot == nil, !identityInvalidated, let identity,
              let data = try? Data(contentsOf: cacheURL), let cached = try? JSONDecoder().decode(QuotaSnapshot.self, from: data),
              cached.identityHash == identity else { return }
        snapshot = cached; state = .stale
        message = "Cached data is stale; its current account source is unverified."
    }
    private func saveCache(_ value: QuotaSnapshot) {
        guard value.identityHash != nil, let data = try? JSONEncoder().encode(value) else { return }
        do {
            try FileManager.default.createDirectory(at: cacheURL.deletingLastPathComponent(), withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            try data.write(to: cacheURL, options: .atomic)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: cacheURL.path)
        } catch { log("Cache write failed") }
    }
    private func readVersion(_ url: URL) {
        Task { @MainActor [weak self] in
            let version = await Task.detached { () -> String in
                let child = Process(); let pipe = Pipe()
                child.executableURL = url; child.arguments = ["--version"]
                child.standardOutput = pipe; child.standardError = FileHandle.nullDevice
                do {
                    try child.run()
                    DispatchQueue.global().asyncAfter(deadline: .now() + 3) {
                        if child.isRunning { child.terminate() }
                    }
                    DispatchQueue.global().asyncAfter(deadline: .now() + 5) {
                        if child.isRunning { kill(child.processIdentifier, SIGKILL) }
                    }
                    let data = pipe.fileHandleForReading.readDataToEndOfFile(); child.waitUntilExit()
                    return String(data: data.prefix(256), encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "Unknown"
                } catch { return "Unknown" }
            }.value
            self?.cliVersion = version
        }
    }
    private func log(_ text: String) { if settings.diagnostics { logger.info("\(text, privacy: .public)") } }
}
