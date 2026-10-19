import Foundation

public enum WindowKind: String, Codable, CaseIterable, Sendable {
    case fiveHour, weekly
    public var label: String { self == .fiveHour ? "5-HOUR LIMIT" : "WEEKLY LIMIT" }
    public var short: String { self == .fiveHour ? "5h" : "7d" }
}
public struct QuotaWindow: Codable, Equatable, Sendable, Identifiable {
    public let kind: WindowKind
    public let remaining: Double
    public let resetsAt: Date?
    public var id: WindowKind { kind }
    public init(kind: WindowKind, remaining: Double, resetsAt: Date? = nil) {
        self.kind = kind; self.remaining = max(0, min(100, remaining)); self.resetsAt = resetsAt
    }
}
public struct QuotaSnapshot: Codable, Equatable, Sendable {
    public let windows: [QuotaWindow]
    public let updatedAt: Date
    public let identityHash: String?
    public let accountHash: String?
    public let ordinaryUsageAllowed: Bool?
    public let restriction: String?
    public var tooltip: String { windows.isEmpty ? "Codex quota unavailable" : windows.map { "\($0.kind.short): \(Int($0.remaining.rounded()))% remaining" }.joined(separator: " | ") }
    public init(windows: [QuotaWindow], updatedAt: Date = Date(), identityHash: String? = nil, accountHash: String? = nil, ordinaryUsageAllowed: Bool? = nil, restriction: String? = nil) {
        self.windows = windows; self.updatedAt = updatedAt; self.identityHash = identityHash; self.accountHash = accountHash; self.ordinaryUsageAllowed = ordinaryUsageAllowed; self.restriction = restriction
    }
}
public enum QuotaState: String, Sendable { case loading, ready, stale, error, unauthenticated, cliUnavailable, noQuotaData }
public enum QuotaError: LocalizedError {
    case cliUnavailable, timeout, disconnected, malformed, unauthenticated, unsupportedAccount, rpc(Int)
    public var errorDescription: String? {
        switch self {
        case .cliUnavailable: return "Codex CLI not found. Install Codex or select its absolute path in Settings."
        case .timeout: return "Codex App Server request timed out. Check your connection and retry."
        case .disconnected: return "Codex App Server disconnected. Reconnecting automatically."
        case .malformed: return "Codex returned an invalid protocol response."
        case .unauthenticated: return "Codex login required. Run codex login in Terminal."
        case .unsupportedAccount: return "ChatGPT subscription quota is unavailable for this authentication mode (including API keys)."
        case .rpc(let code): return "Codex request failed (code \(code)). Check login and network, then retry."
        }
    }
}
public struct JSONLineFramer {
    private var buffer = Data()
    public init() {}
    public mutating func append(_ chunk: Data) throws -> [Data] {
        buffer.append(chunk)
        guard buffer.count <= 8 * 1024 * 1024 else { buffer.removeAll(); throw QuotaError.malformed }
        var lines: [Data] = []
        while let end = buffer.firstIndex(of: 10) {
            let line = buffer[..<end]; buffer.removeSubrange(...end)
            if !line.isEmpty { lines.append(Data(line)) }
        }
        return lines
    }
}
public struct RetryPolicy {
    public private(set) var failures = 0
    public init() {}
    public mutating func failed() -> TimeInterval {
        let delays: [TimeInterval] = [5, 15, 30, 60, 120]
        let delay = delays[min(failures, delays.count - 1)]; failures += 1; return delay
    }
    public mutating func succeeded() { failures = 0 }
}
