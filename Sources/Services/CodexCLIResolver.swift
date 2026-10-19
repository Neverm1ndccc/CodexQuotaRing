import Foundation

public enum CodexCLIResolver {
    public static func resolve(override: String = "") throws -> URL {
        let fm = FileManager.default
        if !override.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            guard override.hasPrefix("/"), fm.isExecutableFile(atPath: override), !isDirectory(override) else { throw QuotaError.cliUnavailable }
            return URL(fileURLWithPath: override)
        }
        let home = fm.homeDirectoryForCurrentUser.path
        var paths = (ProcessInfo.processInfo.environment["PATH"] ?? "").split(separator: ":").map { String($0) + "/codex" }
        paths += ["/opt/homebrew/bin/codex", "/usr/local/bin/codex", "\(home)/.local/bin/codex", "\(home)/.npm-global/bin/codex", "\(home)/.cargo/bin/codex", "\(home)/bin/codex", "/Applications/Codex.app/Contents/Resources/codex", "/Applications/ChatGPT.app/Contents/Resources/codex-cli/CodexCLI.app/Contents/MacOS/codex"]
        for root in [home + "/.nvm/versions/node", home + "/.fnm/node-versions"] {
            for version in (try? fm.contentsOfDirectory(atPath: root))?.sorted().reversed() ?? [] {
                paths.append(root + "/" + version + "/bin/codex")
                paths.append(root + "/" + version + "/installation/bin/codex")
            }
        }
        guard let path = paths.first(where: { $0.hasPrefix("/") && fm.isExecutableFile(atPath: $0) && !isDirectory($0) }) else { throw QuotaError.cliUnavailable }
        return URL(fileURLWithPath: path)
    }
    private static func isDirectory(_ path: String) -> Bool {
        var directory: ObjCBool = false; FileManager.default.fileExists(atPath: path, isDirectory: &directory); return directory.boolValue
    }
}
