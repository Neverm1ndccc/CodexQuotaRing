import SwiftUI
import ServiceManagement
#if SWIFT_PACKAGE
import QuotaCore
#endif

struct SettingsView: View {
    @ObservedObject var settings: AppSettings
    @ObservedObject var service: QuotaService
    @State private var loginEnabled = SMAppService.mainApp.status == .enabled
    @State private var loginError: String?
    @State private var path = ""
    var body: some View {
        Form {
            Section("General") {
                Toggle("Launch at Login", isOn: Binding(get: { loginEnabled }, set: changeLogin))
                if let loginError { Text(loginError).font(.caption).foregroundStyle(.orange) }
                Picker("Refresh Interval", selection: $settings.interval) {
                    Text("60 seconds").tag(60.0); Text("120 seconds").tag(120.0); Text("300 seconds").tag(300.0)
                }
                Toggle("Launch Hidden", isOn: $settings.launchHidden)
            }
            Section("Appearance") {
                Picker("Theme", selection: $settings.theme) { ForEach(["System", "Light", "Dark"], id: \.self) { Text($0) } }
                Toggle("Monochrome Rings", isOn: $settings.monochrome)
                Toggle("Show Tooltips", isOn: $settings.tooltips)
            }
            Section("About") {
                LabeledContent("Version", value: "1.0.0")
                LabeledContent("Codex CLI") { Text(service.cliLocation).textSelection(.enabled).lineLimit(2).font(.caption) }
                LabeledContent("CLI Version", value: service.cliVersion)
                LabeledContent("Connection", value: service.refreshing ? "Synchronizing" : service.state.rawValue)
                LabeledContent("Last Sync", value: service.snapshot?.updatedAt.formatted(date: .abbreviated, time: .standard) ?? "Never")
            }
            Section("Advanced") {
                TextField("Codex absolute path (blank = auto)", text: $path).font(.caption).textFieldStyle(.roundedBorder)
                HStack {
                    Button("Choose…") {
                        let panel = NSOpenPanel(); panel.canChooseDirectories = false; panel.allowsMultipleSelection = false
                        if panel.runModal() == .OK, let url = panel.url { path = url.path }
                    }
                    Button("Save & Reconnect") { settings.cliPath = path.trimmingCharacters(in: .whitespacesAndNewlines); service.reconnect() }
                }
                Toggle("Diagnostic Logs", isOn: $settings.diagnostics)
                Text("Logs contain connection events only. Authentication data and server payloads are never logged.").font(.caption).foregroundStyle(.secondary)
            }
        }.formStyle(.grouped).frame(width: 480, height: 650)
            .onAppear { path = settings.cliPath; loginEnabled = SMAppService.mainApp.status == .enabled }
    }
    private func changeLogin(_ enabled: Bool) {
        do {
            if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            loginEnabled = SMAppService.mainApp.status == .enabled
            loginError = SMAppService.mainApp.status == .requiresApproval ? "Approve Codex Quota Ring in System Settings → General → Login Items." : nil
        } catch { loginEnabled = SMAppService.mainApp.status == .enabled; loginError = error.localizedDescription }
    }
}
