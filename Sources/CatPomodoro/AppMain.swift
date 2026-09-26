import AppKit
import SwiftUI
import UserNotifications

@main
struct CatPomodoroApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        Settings {
            EmptyView()
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate, UNUserNotificationCenterDelegate {
    private let model = TimerModel()
    private var panel: FloatingPanel?
    private var statusItem: NSStatusItem?
    private var pauseMenuItem: NSMenuItem?
    private var isResizingPanel = false

    // The pet itself is rendered at 60% of the original approved size.
    private let compactSize = NSSize(width: 190, height: 264)
    // A shadow with an 18pt blur needs roughly three times that distance to
    // fade fully before it reaches the transparent panel boundary.
    private let expandedSize = NSSize(width: 586, height: 462)
    private let encouragementSize = NSSize(width: 586, height: 376)

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        configureNotifications()
        configurePanel()
        configureStatusItem()

        model.onPresentationChanged = { [weak self] in
            self?.resizePanelForPresentation()
        }
        model.onTimerStateChanged = { [weak self] in
            self?.updateStatusMenu()
        }

        let arguments = ProcessInfo.processInfo.arguments

        if arguments.contains("--preview-completion") {
            model.previewCompletion()
        }

        if arguments.contains("--preview-encouragement") {
            model.previewEncouragement()
        }

        if !arguments.contains("--start-hidden") {
            panel?.orderFrontRegardless()
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationShouldHandleReopen(
        _ sender: NSApplication,
        hasVisibleWindows flag: Bool
    ) -> Bool {
        panel?.orderFrontRegardless()
        return true
    }

    private func configureNotifications() {
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        center.requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    private func configurePanel() {
        let rootView = RootView(
            model: model,
            onHide: { [weak self] in self?.panel?.orderOut(nil) }
        )
        let hostingView = NSHostingView(rootView: rootView)
        hostingView.layer?.backgroundColor = NSColor.clear.cgColor

        let frame = restoredFrame() ?? defaultFrame()
        let panel = FloatingPanel(contentRect: frame)
        panel.contentView = hostingView
        panel.delegate = self
        panel.setContentSize(compactSize)
        self.panel = panel
    }

    private func configureStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = item.button {
            button.image = NSImage(
                systemSymbolName: "timer",
                accessibilityDescription: "냥모도로"
            )
            button.toolTip = "냥모도로"
        }

        let menu = NSMenu()
        menu.addItem(menuItem("타이머 보기", action: #selector(showTimer), key: "t"))

        let pauseItem = menuItem("집중 시작", action: #selector(toggleTimer), key: " ")
        menu.addItem(pauseItem)
        self.pauseMenuItem = pauseItem

        menu.addItem(menuItem("타이머 설정…", action: #selector(showSettings), key: ","))
        menu.addItem(menuItem("초기화", action: #selector(resetTimer), key: "r"))
        menu.addItem(.separator())
        menu.addItem(menuItem("냥모도로 종료", action: #selector(quitApp), key: "q"))
        item.menu = menu
        statusItem = item
        updateStatusMenu()
    }

    private func menuItem(_ title: String, action: Selector, key: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = self
        return item
    }

    @objc private func showTimer() {
        panel?.orderFrontRegardless()
    }

    @objc private func toggleTimer() {
        panel?.orderFrontRegardless()
        model.toggleRunning()
    }

    @objc private func showSettings() {
        panel?.orderFrontRegardless()
        model.openSettings()
    }

    @objc private func resetTimer() {
        panel?.orderFrontRegardless()
        model.resetCurrentSession()
    }

    @objc private func quitApp() {
        NSApp.terminate(nil)
    }

    private func updateStatusMenu() {
        pauseMenuItem?.title = model.isRunning ? "일시정지" : "\(model.phase.title) 시작"
    }

    private func resizePanelForPresentation() {
        guard let panel else { return }

        let expanding = model.isPresentingBubble
        let oldFrame = panel.frame
        let targetSize: NSSize
        if model.isShowingEncouragement {
            targetSize = encouragementSize
        } else if expanding {
            targetSize = expandedSize
        } else {
            targetSize = compactSize
        }

        if abs(oldFrame.width - targetSize.width) < 0.5,
           abs(oldFrame.height - targetSize.height) < 0.5 {
            return
        }

        let visibleFrame = (panel.screen ?? NSScreen.main)?.visibleFrame
            ?? NSRect(origin: .zero, size: NSScreen.main?.frame.size ?? targetSize)

        var targetOrigin = oldFrame.origin

        let wasCompact = abs(oldFrame.width - compactSize.width) < 0.5

        if expanding, wasCompact {
            let extraWidth = targetSize.width - compactSize.width
            let hasRoomOnRight = oldFrame.maxX + extraWidth <= visibleFrame.maxX - 12
            model.bubbleOnLeft = !hasRoomOnRight

            if model.bubbleOnLeft {
                targetOrigin.x = oldFrame.maxX - targetSize.width
            }
        } else if model.bubbleOnLeft {
            targetOrigin.x = oldFrame.maxX - compactSize.width
        }

        // Preserve the pet's vertical center while a bubble opens or closes.
        targetOrigin.y = oldFrame.midY - (targetSize.height / 2)
        targetOrigin.x = min(max(targetOrigin.x, visibleFrame.minX + 8), visibleFrame.maxX - targetSize.width - 8)
        targetOrigin.y = min(max(targetOrigin.y, visibleFrame.minY + 8), visibleFrame.maxY - targetSize.height - 8)

        let targetFrame = NSRect(origin: targetOrigin, size: targetSize)
        isResizingPanel = true
        panel.setFrame(targetFrame, display: true)
        isResizingPanel = false

        if !expanding {
            saveCompactFrame()
        }
    }

    private func defaultFrame() -> NSRect {
        guard let visible = NSScreen.main?.visibleFrame else {
            return NSRect(origin: NSPoint(x: 60, y: 60), size: compactSize)
        }
        return NSRect(
            x: visible.maxX - compactSize.width - 34,
            y: visible.maxY - compactSize.height - 34,
            width: compactSize.width,
            height: compactSize.height
        )
    }

    private func restoredFrame() -> NSRect? {
        let defaults = UserDefaults.standard
        guard defaults.object(forKey: "panelOriginX") != nil,
              defaults.object(forKey: "panelOriginY") != nil else {
            return nil
        }

        let proposed = NSRect(
            x: defaults.double(forKey: "panelOriginX"),
            y: defaults.double(forKey: "panelOriginY"),
            width: compactSize.width,
            height: compactSize.height
        )

        let isVisible = NSScreen.screens.contains { $0.visibleFrame.intersects(proposed) }
        return isVisible ? proposed : nil
    }

    private func saveCompactFrame() {
        guard let panel, !model.isPresentingBubble else { return }
        UserDefaults.standard.set(panel.frame.origin.x, forKey: "panelOriginX")
        UserDefaults.standard.set(panel.frame.origin.y, forKey: "panelOriginY")
    }

    func windowDidMove(_ notification: Notification) {
        guard !isResizingPanel else { return }
        saveCompactFrame()
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }
}
