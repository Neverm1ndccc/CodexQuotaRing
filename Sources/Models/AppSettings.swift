import Foundation
import Combine

@MainActor public final class AppSettings: ObservableObject {
    public static let shared = AppSettings()
    public let defaults: UserDefaults
    @Published public var interval: Double { didSet { defaults.set(interval, forKey: "refreshInterval") } }
    @Published public var launchHidden: Bool { didSet { defaults.set(launchHidden, forKey: "launchHidden") } }
    @Published public var theme: String { didSet { defaults.set(theme, forKey: "theme") } }
    @Published public var monochrome: Bool { didSet { defaults.set(monochrome, forKey: "monochrome") } }
    @Published public var tooltips: Bool { didSet { defaults.set(tooltips, forKey: "tooltips") } }
    @Published public var cliPath: String { didSet { defaults.set(cliPath, forKey: "cliPath") } }
    @Published public var diagnostics: Bool { didSet { defaults.set(diagnostics, forKey: "diagnostics") } }
    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let seconds = defaults.double(forKey: "refreshInterval")
        interval = [60.0, 120, 300].contains(seconds) ? seconds : 60
        launchHidden = defaults.object(forKey: "launchHidden") as? Bool ?? true
        theme = defaults.string(forKey: "theme") ?? "System"
        monochrome = defaults.bool(forKey: "monochrome")
        tooltips = defaults.object(forKey: "tooltips") as? Bool ?? true
        cliPath = defaults.string(forKey: "cliPath") ?? ""
        diagnostics = defaults.bool(forKey: "diagnostics")
    }
}
