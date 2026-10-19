import Foundation
import Darwin

@MainActor public final class CodexAppServerClient {
    private var process: Process?
    private var input: FileHandle?
    private var output: FileHandle?
    private var errors: FileHandle?
    private var consumer: Task<Void, Never>?
    private var pending: [Int: CheckedContinuation<[String: Any], Error>] = [:]
    private var deadlines: [Int: Task<Void, Never>] = [:]
    private var nextID = 0
    private var generation = UUID()
    private var initialized = false
    public var onNotification: ((String, [String: Any]) -> Void)?
    public var onDisconnect: (() -> Void)?
    public var isRunning: Bool { process?.isRunning == true && initialized }
    public init() {}

    public func start(executable: URL, arguments: [String] = ["app-server"]) async throws {
        if isRunning { return }
        stop()
        let token = UUID(); generation = token
        let child = Process(); let stdin = Pipe(); let stdout = Pipe(); let stderr = Pipe()
        child.executableURL = executable; child.arguments = arguments
        var env = ProcessInfo.processInfo.environment
        env["PATH"] = executable.deletingLastPathComponent().path + ":/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:" + (env["PATH"] ?? "")
        child.environment = env
        child.standardInput = stdin; child.standardOutput = stdout; child.standardError = stderr
        input = stdin.fileHandleForWriting; output = stdout.fileHandleForReading; errors = stderr.fileHandleForReading
        let stream = AsyncStream<Data> { continuation in
            stdout.fileHandleForReading.readabilityHandler = { handle in
                let data = handle.availableData
                if data.isEmpty { continuation.finish() } else { continuation.yield(data) }
            }
        }
        // Drain stderr without retaining, logging, or exposing sensitive server output.
        stderr.fileHandleForReading.readabilityHandler = { handle in _ = handle.availableData }
        child.terminationHandler = { [weak self] _ in
            Task { @MainActor in
                guard let self, self.generation == token else { return }
                self.stop(); self.onDisconnect?()
            }
        }
        process = child
        do { try child.run() } catch { stop(); throw QuotaError.disconnected }
        consumer = Task { [weak self] in
            var framer = JSONLineFramer()
            do {
                for await chunk in stream {
                    guard let self, self.generation == token, !Task.isCancelled else { return }
                    for line in try framer.append(chunk) { try self.receive(line) }
                }
                guard let self, self.generation == token, !Task.isCancelled else { return }
                self.stop(); self.onDisconnect?()
            } catch {
                guard let self, self.generation == token else { return }
                self.stop(); self.onDisconnect?()
            }
        }
        do {
            _ = try await request("initialize", params: ["clientInfo": ["name": "codex_quota_ring", "title": "Codex Quota Ring", "version": "1.0.0"]])
            try send(["method": "initialized"]); initialized = true
        } catch { if generation == token { stop() }; throw error }
    }
    public func request(_ method: String, params: [String: Any]? = nil, timeout: TimeInterval = 15) async throws -> [String: Any] {
        guard process?.isRunning == true else { throw QuotaError.disconnected }
        nextID += 1; let id = nextID
        return try await withTaskCancellationHandler(operation: {
            try await withCheckedThrowingContinuation { continuation in
                pending[id] = continuation
                deadlines[id] = Task { [weak self] in
                    do { try await Task.sleep(nanoseconds: UInt64(max(0.01, timeout) * 1_000_000_000)) } catch { return }
                    self?.finish(id, result: .failure(QuotaError.timeout))
                }
                do {
                    var message: [String: Any] = ["id": id, "method": method]
                    if let params { message["params"] = params }
                    try send(message)
                } catch { finish(id, result: .failure(error)) }
            }
        }, onCancel: { [weak self] in Task { @MainActor in self?.finish(id, result: .failure(CancellationError())) } })
    }
    private func send(_ message: [String: Any]) throws {
        guard let input else { throw QuotaError.disconnected }
        var data = try JSONSerialization.data(withJSONObject: message); data.append(10)
        do { try input.write(contentsOf: data) } catch { throw QuotaError.disconnected }
    }
    private func receive(_ data: Data) throws {
        guard let message = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw QuotaError.malformed }
        if let id = message["id"] as? Int, message["method"] == nil {
            if let error = message["error"] as? [String: Any] { finish(id, result: .failure(QuotaError.rpc(error["code"] as? Int ?? -1))) }
            else if let result = message["result"] as? [String: Any] { finish(id, result: .success(result)) }
            else { finish(id, result: .failure(QuotaError.malformed)) }
        } else if let method = message["method"] as? String {
            // This read-only client cannot service token refresh or interactive requests.
            if let id = message["id"] {
                try send(["id": id, "error": ["code": -32601, "message": "Read-only quota client does not support this request"]])
            } else { onNotification?(method, message["params"] as? [String: Any] ?? [:]) }
        }
    }
    private func finish(_ id: Int, result: Result<[String: Any], Error>) {
        deadlines.removeValue(forKey: id)?.cancel(); pending.removeValue(forKey: id)?.resume(with: result)
    }
    public func stop() {
        generation = UUID(); initialized = false
        consumer?.cancel(); consumer = nil
        output?.readabilityHandler = nil; errors?.readabilityHandler = nil
        try? input?.close(); input = nil
        let old = process; process = nil; old?.terminationHandler = nil
        if let old, old.isRunning {
            old.terminate()
            DispatchQueue.global().asyncAfter(deadline: .now() + 2) {
                if old.isRunning { kill(old.processIdentifier, SIGKILL) }
            }
        }
        try? output?.close(); try? errors?.close(); output = nil; errors = nil
        for id in Array(pending.keys) { finish(id, result: .failure(QuotaError.disconnected)) }
    }
}
