import SwiftUI
import AppKit

@main
struct RevyDApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        Settings {
            Text("RevyD Settings")
                .frame(width: 400, height: 300)
        }
    }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    var controller: RevyDController?
    var statusItem: NSStatusItem?
    var settingsWindow: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        // Initialize database (creates tables on first launch)
        _ = RevyDatabase.shared

        // Reset stuck debriefs from previous session
        RevyDatabase.shared.execute("UPDATE meetings SET debrief_status = 'pending' WHERE debrief_status = 'processing'")

        controller = RevyDController()
        controller?.start()
        setupMenuBar()
    }

    func applicationWillTerminate(_ notification: Notification) {
        controller?.characters.forEach { $0.claudeSession?.terminate() }
    }

    // MARK: - Menu Bar

    func setupMenuBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = statusItem?.button {
            if let resourceURL = Bundle.main.resourceURL {
                let iconPath = resourceURL.appendingPathComponent("CharacterSprites/granola-icon@2x.png").path
                let revyPath = resourceURL.appendingPathComponent("CharacterSprites/revy-front@2x.png").path
                if let img = NSImage(contentsOfFile: revyPath) {
                    img.size = NSSize(width: 18, height: 18)
                    button.image = img
                    button.image?.isTemplate = false
                }
            }
            button.toolTip = "RevyD — AI Chief of Staff"
        }

        let menu = NSMenu()

        let showItem = NSMenuItem(title: "Show RevyD", action: #selector(toggleCharacter), keyEquivalent: "1")
        showItem.state = .on
        menu.addItem(showItem)

        menu.addItem(NSMenuItem.separator())

        let resyncItem = NSMenuItem(title: "Sync Granola Now", action: #selector(resyncGranola), keyEquivalent: "r")
        menu.addItem(resyncItem)

        menu.addItem(NSMenuItem.separator())

        let settingsItem = NSMenuItem(title: "Settings...", action: #selector(openSettings), keyEquivalent: ",")
        menu.addItem(settingsItem)

        menu.addItem(NSMenuItem.separator())

        let logoutItem = NSMenuItem(title: "Logout & Reset Data", action: #selector(logoutAndReset), keyEquivalent: "")
        menu.addItem(logoutItem)

        menu.addItem(NSMenuItem.separator())

        let quitItem = NSMenuItem(title: "Quit", action: #selector(quitApp), keyEquivalent: "q")
        menu.addItem(quitItem)

        statusItem?.menu = menu
    }

    // MARK: - Menu Actions

    @objc func toggleCharacter(_ sender: NSMenuItem) {
        guard let chars = controller?.characters, !chars.isEmpty else { return }
        let char = chars[0]
        if char.window.isVisible {
            char.window.orderOut(nil)
            sender.state = .off
        } else {
            char.window.orderFrontRegardless()
            sender.state = .on
        }
    }

    @objc func openSettings() {
        NSApp.activate(ignoringOtherApps: true)
        if settingsWindow == nil {
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 500, height: 400),
                styleMask: [.titled, .closable, .miniaturizable],
                backing: .buffered,
                defer: false
            )
            window.title = "RevyD Settings"
            window.level = NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue + 11)
            window.collectionBehavior = [.canJoinAllSpaces]
            window.center()
            window.isReleasedWhenClosed = false
            settingsWindow = window
        }
        settingsWindow?.makeKeyAndOrderFront(nil)
        settingsWindow?.orderFrontRegardless()
    }

    @objc func resyncGranola() {
        controller?.syncEngine.syncNow()
        if let char = controller?.characters.first {
            char.showBubble(text: "syncing...", isCompletion: false)
        }
    }

    @objc func logoutAndReset() {
        NSApp.activate(ignoringOtherApps: true)

        let alert = NSAlert()
        alert.messageText = "Logout & Reset"
        alert.informativeText = "This will delete all synced meetings, commitments, and indexed documents. You can sync again after."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Reset")
        alert.addButton(withTitle: "Cancel")
        alert.window.level = NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue + 20)

        let response = alert.runModal()
        guard response == .alertFirstButtonReturn else { return }

        // Close popover and terminate sessions
        controller?.characters.first?.closePopover()
        controller?.characters.forEach { $0.claudeSession?.terminate(); $0.claudeSession = nil }
        controller?.syncEngine.stopSync()
        controller?.proactiveScheduler.stop()

        // Delete DB files
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let revydDir = appSupport.appendingPathComponent("RevyD")
        try? FileManager.default.removeItem(at: revydDir)

        // Reset all UserDefaults
        UserDefaults.standard.removeObject(forKey: "hasCompletedOnboarding")
        UserDefaults.standard.removeObject(forKey: "granolaLastSyncDate")
        UserDefaults.standard.removeObject(forKey: "granolaAutoSync")

        // Relaunch
        let bundlePath = Bundle.main.bundlePath
        DispatchQueue.global().async {
            let task = Process()
            task.executableURL = URL(fileURLWithPath: "/usr/bin/open")
            task.arguments = ["-n", bundlePath]
            try? task.run()
            task.waitUntilExit()
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            NSApp.terminate(nil)
        }
    }

    @objc func quitApp() {
        NSApp.terminate(nil)
    }
}
