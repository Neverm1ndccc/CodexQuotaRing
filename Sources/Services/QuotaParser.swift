import Foundation
import CryptoKit

public enum QuotaParser {
    public static func hash(_ text: String) -> String { SHA256.hash(data: Data(text.utf8)).map { String(format: "%02x", $0) }.joined() }
    public static func identity(_ result: [String: Any]) throws -> String? {
        guard let account = result["account"] as? [String: Any] else { throw QuotaError.unauthenticated }
        guard let type = account["type"] as? String, ["chatgpt", "chatgptAuthTokens"].contains(type) else { throw QuotaError.unsupportedAccount }
        // No credential access. Email is hashed in memory and never logged or stored verbatim.
        guard let email = account["email"] as? String, !email.isEmpty else { return nil }
        return hash(type + ":" + email + ":" + (account["planType"] as? String ?? ""))
    }
    public static func parse(_ result: [String: Any], identity: String? = nil, now: Date = Date()) -> QuotaSnapshot {
        let buckets = result["rateLimitsByLimitId"] as? [String: Any]
        var bucket = buckets?["codex"] as? [String: Any]
        if let selected = bucket, let id = selected["limitId"] as? String, id != "codex" { bucket = nil }
        if bucket == nil, let legacy = result["rateLimits"] as? [String: Any] {
            let id = legacy["limitId"] as? String
            // A nameless historical single bucket is supported only when no multi-bucket map exists.
            if id == "codex" || (id == nil && (buckets == nil || buckets?.isEmpty == true) && legacy["limitName"] as? String == nil) { bucket = legacy }
        }
        var found: [WindowKind: QuotaWindow] = [:]
        for key in ["primary", "secondary"] {
            guard let raw = bucket?[key] as? [String: Any], let minutes = number(raw["windowDurationMins"]), let used = number(raw["usedPercent"]) else { continue }
            let kind: WindowKind
            switch minutes { case 300: kind = .fiveHour; case 10080: kind = .weekly; default: continue }
            let reset = number(raw["resetsAt"]).map { Date(timeIntervalSince1970: $0) }
            let window = QuotaWindow(kind: kind, remaining: 100 - used, resetsAt: reset)
            // Duplicate windows: conservatively retain the lower remaining value.
            if found[kind] == nil || window.remaining < found[kind]!.remaining { found[kind] = window }
        }
        let allowed = result["ordinaryUsageAllowed"] as? Bool ?? bucket?["ordinaryUsageAllowed"] as? Bool
        let restriction = bucket?["rateLimitReachedType"] as? String
            ?? ((bucket?["spendControlReached"] as? Bool == true) ? "spend_control_reached" : nil)
        return QuotaSnapshot(windows: WindowKind.allCases.compactMap { found[$0] }, updatedAt: now, identityHash: identity,
                             accountHash: (result["accountId"] as? String).map(hash), ordinaryUsageAllowed: allowed, restriction: restriction)
    }
    private static func number(_ value: Any?) -> Double? {
        guard let n = value as? NSNumber, CFGetTypeID(n) != CFBooleanGetTypeID(), n.doubleValue.isFinite else { return nil }
        return n.doubleValue
    }
}
import CoreFoundation
