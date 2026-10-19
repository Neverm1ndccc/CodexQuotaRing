import Foundation
import QuotaCore

@main struct QuotaProbe {
    @MainActor static func main() async {
        let client = CodexAppServerClient()
        defer { client.stop() }
        do {
            let url = try CodexCLIResolver.resolve(override: CommandLine.arguments.dropFirst().first ?? "")
            try await client.start(executable: url)
            let account = try await client.request("account/read", params:["refreshToken":false])
            let identity = try QuotaParser.identity(account)
            let limits = try await client.request("account/rateLimits/read")
            let snapshot = QuotaParser.parse(limits, identity:identity)
            // Never print identity, auth responses, or raw server payloads.
            print("Live Codex App Server connection: OK")
            print("Account identity available: \(identity != nil)")
            print(snapshot.tooltip)
            print("ordinaryUsageAllowed: \(snapshot.ordinaryUsageAllowed.map(String.init) ?? "unavailable")")
            for window in snapshot.windows { print("\(window.kind.short) reset: \(window.resetsAt?.formatted() ?? "unknown")") }
        } catch { print("Live probe failed: \((error as? QuotaError)?.localizedDescription ?? "Connection error")"); exit(1) }
    }
}
