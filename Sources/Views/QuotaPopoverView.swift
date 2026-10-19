import SwiftUI
#if SWIFT_PACKAGE
import QuotaCore
#endif

struct QuotaPopoverView: View {
    @ObservedObject var service: QuotaService
    @ObservedObject var settings: AppSettings
    let openSettings: () -> Void
    let hide: () -> Void
    @State private var visible = false
    var body: some View {
        VStack(alignment: .leading, spacing: 15) {
            HStack {
                Text("Codex Quota Ring").font(.headline)
                Spacer()
                if service.refreshing { ProgressView().controlSize(.small) }
                Button { service.refresh() } label: { Image(systemName: "arrow.clockwise") }
                    .buttonStyle(.borderless).disabled(service.refreshing).help("Refresh quota")
                    .accessibilityLabel("Refresh quota")
            }
            if let snapshot = service.snapshot {
                if snapshot.ordinaryUsageAllowed == false || snapshot.restriction != nil {
                    Label("Included usage restricted by server", systemImage: "exclamationmark.triangle.fill").font(.caption).foregroundStyle(.orange)
                }
                ForEach(snapshot.windows) { window in
                    QuotaProgressView(window: window, stale: service.state == .stale, monochrome: settings.monochrome, visible: visible)
                }
                TimelineView(VisibleSchedule(active: visible)) { context in
                    Text("Updated \(snapshot.updatedAt.formatted(.relative(presentation: .named)))")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            if let message = service.message {
                Label(message, systemImage: service.state == .stale ? "clock.badge.exclamationmark" : "info.circle")
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
            } else if service.snapshot == nil {
                Text(service.refreshing ? "Connecting to Codex…" : "Codex quota unavailable").foregroundStyle(.secondary)
            }
            if service.state == .cliUnavailable {
                Link("Codex installation instructions", destination: URL(string: "https://developers.openai.com/codex/cli/")!).font(.caption)
            }
            if service.state == .unauthenticated { Text("In Terminal: codex login").font(.system(.caption, design: .monospaced)).textSelection(.enabled) }
            Divider()
            HStack {
                Button("Settings…", action: openSettings)
                Spacer()
                Button("Hide", action: hide)
                Button("Quit") { NSApp.terminate(nil) }
            }.buttonStyle(.borderless).font(.caption)
        }
        .padding(18).frame(width: 310)
        .onAppear { visible = true }.onDisappear { visible = false }
    }
}
struct QuotaProgressView: View {
    let window: QuotaWindow
    let stale: Bool
    let monochrome: Bool
    let visible: Bool
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(window.kind.label).font(.system(size: 10, weight: .semibold)).foregroundStyle(.secondary)
            Text("\(Int(window.remaining.rounded()))% remaining").font(.system(size: 21, weight: .medium, design: .rounded)).monospacedDigit()
            ProgressView(value: window.remaining, total: 100).tint(Color(nsColor: RingIconRenderer.color(window, stale: stale, monochrome: monochrome)))
            if let date = window.resetsAt {
                TimelineView(VisibleSchedule(active: visible)) { context in
                    Text(resetText(date, now: context.date)).font(.caption).foregroundStyle(.secondary)
                }
                Text(date.formatted(date: .abbreviated, time: .shortened)).font(.caption2).foregroundStyle(.secondary)
            } else { Text("Reset time unavailable").font(.caption).foregroundStyle(.secondary) }
        }
    }
    private func resetText(_ date: Date, now: Date) -> String {
        let seconds = max(0, Int(date.timeIntervalSince(now)))
        if seconds == 0 { return "Reset due · awaiting server update" }
        let minutes = max(1, seconds / 60)
        if minutes >= 1440 { return "Reset in \(minutes / 1440)d \(minutes % 1440 / 60)h" }
        return "Reset in \(minutes / 60)h \(minutes % 60)m"
    }
}

private struct VisibleSchedule: TimelineSchedule {
    let active: Bool
    func entries(from startDate: Date, mode: Mode) -> AnySequence<Date> {
        if !active { return AnySequence([startDate]) }
        return AnySequence(sequence(first: startDate) { $0.addingTimeInterval(30) })
    }
}
