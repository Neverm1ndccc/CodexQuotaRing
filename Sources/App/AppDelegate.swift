import AppKit
import SwiftUI
import Combine
#if SWIFT_PACKAGE
import QuotaCore
#endif

@MainActor final class AppDelegate: NSObject, NSApplicationDelegate, NSPopoverDelegate {
    private let settings = AppSettings.shared
    private lazy var service = QuotaService(settings: settings)
    private var item: NSStatusItem!
    private let popover = NSPopover()
    private var settingsWindow: NSWindow?
    private var subscriptions = Set<AnyCancellable>()
    private var lastRenderKey = ""
    func applicationDidFinishLaunching(_ notification: Notification) {
        if NSClassFromString("XCTestCase") != nil { return }
        item = NSStatusBar.system.statusItem(withLength: 26)
        item.button?.target = self; item.button?.action = #selector(toggle)
        item.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])
        item.button?.setAccessibilityLabel("Codex Quota Ring")
        popover.delegate = self; popover.behavior = .transient; popover.animates = false

        Publishers.Merge(service.objectWillChange, settings.objectWillChange)
            .receive(on: DispatchQueue.main).sink { [weak self] _ in self?.update() }.store(in: &subscriptions)
        NotificationCenter.default.publisher(for: NSApplication.didChangeScreenParametersNotification)
            .sink { [weak self] _ in self?.lastRenderKey = ""; self?.update() }.store(in: &subscriptions)
        DistributedNotificationCenter.default().publisher(for: Notification.Name("AppleInterfaceThemeChangedNotification"))
            .receive(on: DispatchQueue.main).sink { [weak self] _ in self?.lastRenderKey = ""; self?.update() }.store(in: &subscriptions)
        update(); service.start()
        if !settings.launchHidden { DispatchQueue.main.async { self.toggle() } }
    }
    private func update() {
        let windows = service.snapshot?.windows ?? []
        let restricted = service.snapshot?.ordinaryUsageAllowed == false || service.snapshot?.restriction != nil
        let key = "\(windows)-\(service.state)-\(settings.monochrome)-\(restricted)-\(NSApp.effectiveAppearance.name)"
        if key != lastRenderKey {
            item.button?.image = RingIconRenderer.render(windows: windows, state: service.state, monochrome: settings.monochrome, restricted: restricted)
            lastRenderKey = key
        }
        var tip = service.snapshot?.tooltip ?? "Codex quota unavailable"
        if service.state == .stale { tip += " (stale, account source unverified)" }
        if restricted { tip += " | Included usage restricted by server" }
        item.button?.toolTip = settings.tooltips ? tip : nil
        item.button?.setAccessibilityValue(tip)
        let appearance = settings.theme == "System" ? nil : NSAppearance(named: settings.theme == "Dark" ? .darkAqua : .aqua)
        popover.appearance = appearance; settingsWindow?.appearance = appearance
    }
    @objc private func toggle() {
        if NSApp.currentEvent?.type == .rightMouseUp {
            let menu = NSMenu()
            menu.addItem(withTitle: "Show Quota", action: #selector(showQuota), keyEquivalent: "").target = self
            menu.addItem(withTitle: "Settings…", action: #selector(showSettings), keyEquivalent: ",").target = self
            menu.addItem(.separator())
            menu.addItem(withTitle: "Quit Codex Quota Ring", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
            item.menu = menu; item.button?.performClick(nil); item.menu = nil
            return
        }
        if popover.isShown { popover.performClose(nil) } else { showQuota() }
    }
    @objc private func showQuota() {
        guard let button = item.button else { return }
        popover.contentViewController = NSHostingController(rootView: QuotaPopoverView(service: service, settings: settings,
            openSettings: { [weak self] in self?.showSettings() }, hide: { [weak self] in self?.popover.performClose(nil) }))
        NSApp.activate(ignoringOtherApps: true)
        // Leave one menu-bar row below the camera/notch safe area.
        let rowHeight = NSStatusBar.system.thickness
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        if let window = popover.contentViewController?.view.window,
           let screen = button.window?.screen ?? window.screen {
            let safeTop = min(screen.visibleFrame.maxY, screen.frame.maxY - screen.safeAreaInsets.top)
            let targetTop = safeTop - rowHeight
            if window.frame.maxY > targetTop {
                window.setFrameOrigin(NSPoint(x: window.frame.minX,
                    y: max(screen.visibleFrame.minY, targetTop - window.frame.height)))
            }
            window.makeKey()
        }
    }
    @objc private func showSettings() {
        popover.performClose(nil)
        if settingsWindow == nil {
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 480, height: 590), styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
            window.title = "Codex Quota Ring Settings"; window.isReleasedWhenClosed = false
            window.contentViewController = NSHostingController(rootView: SettingsView(settings: settings, service: service))
            window.center(); settingsWindow = window
        }
        update(); NSApp.activate(ignoringOtherApps: true); settingsWindow?.makeKeyAndOrderFront(nil)
    }
    func popoverDidClose(_ notification: Notification) { popover.contentViewController = nil }
    func applicationWillTerminate(_ notification: Notification) { service.stop(); subscriptions.removeAll(); if let item { NSStatusBar.system.removeStatusItem(item) } }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool { showQuota(); return true }
}
