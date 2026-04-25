import AppKit

extension RevyCharacter {
    static let defaultPopoverWidth: CGFloat = 420
    static let defaultPopoverHeight: CGFloat = 560

    func openPopover() {
        isIdleForPopover = true
        isWalking = false
        isPaused = true
        pauseEndTime = .greatestFiniteMagnitude
        setFacing(.front)

        if popoverWindow == nil {
            createPopoverWindow()
        }

        if claudeSession == nil {
            let session = ClaudeSession()
            claudeSession = session
            wireSession(session)
            session.start()
        }

        updatePopoverPosition()
        popoverWindow?.orderFrontRegardless()
        popoverWindow?.makeKey()
        if let terminal = terminalView {
            popoverWindow?.makeFirstResponder(terminal.inputField)
        }

        installClickOutsideMonitor()
        installEscapeKeyMonitor()
    }

    func closePopover() {
        isIdleForPopover = false
        popoverWindow?.orderOut(nil)
        removeClickOutsideMonitor()
        removeEscapeKeyMonitor()
        pauseEndTime = CACurrentMediaTime() + Double.random(in: 1.5...3.5)
    }

    func createPopoverWindow() {
        let w = Self.defaultPopoverWidth
        let h = Self.defaultPopoverHeight

        let win = KeyableWindow(
            contentRect: NSRect(x: 0, y: 0, width: w, height: h),
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )
        win.isOpaque = false
        win.backgroundColor = .clear
        win.hasShadow = true
        win.level = NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue + 5)
        win.collectionBehavior = [.canJoinAllSpaces]

        // --- Liquid Glass: NSVisualEffectView as the root ---
        let glassView = NSVisualEffectView(frame: NSRect(x: 0, y: 0, width: w, height: h))
        glassView.material = .hudWindow           // Dark translucent glass
        glassView.blendingMode = .behindWindow     // Blurs what's behind the window
        glassView.state = .active
        glassView.wantsLayer = true
        glassView.layer?.cornerRadius = 16
        glassView.layer?.masksToBounds = true
        glassView.layer?.borderColor = NSColor.white.withAlphaComponent(0.12).cgColor
        glassView.layer?.borderWidth = 0.5

        // --- Title bar (vibrant) ---
        let titleBarHeight: CGFloat = 40
        let titleBar = NSVisualEffectView(frame: NSRect(x: 0, y: h - titleBarHeight, width: w, height: titleBarHeight))
        titleBar.material = .titlebar
        titleBar.blendingMode = .withinWindow
        titleBar.state = .active

        // App icon (small robot head)
        let iconSize: CGFloat = 22
        let iconView = NSImageView(frame: NSRect(x: 14, y: (titleBarHeight - iconSize) / 2, width: iconSize, height: iconSize))
        if let frontSprite = directionalImages[.front] {
            iconView.image = frontSprite
        }
        iconView.imageScaling = .scaleProportionallyUpOrDown
        titleBar.addSubview(iconView)

        let titleLabel = NSTextField(labelWithString: "RevyD")
        titleLabel.font = .systemFont(ofSize: 13, weight: .semibold)
        titleLabel.textColor = .labelColor
        titleLabel.frame = NSRect(x: 42, y: (titleBarHeight - 18) / 2, width: 100, height: 18)
        titleBar.addSubview(titleLabel)

        let subtitleLabel = NSTextField(labelWithString: "AI Chief of Staff")
        subtitleLabel.font = .systemFont(ofSize: 10, weight: .regular)
        subtitleLabel.textColor = .secondaryLabelColor
        subtitleLabel.frame = NSRect(x: 42 + 56, y: (titleBarHeight - 16) / 2, width: 120, height: 16)
        titleBar.addSubview(subtitleLabel)

        // Close button — native-feeling circle
        let closeBtn = NSButton(frame: NSRect(x: w - 36, y: (titleBarHeight - 20) / 2, width: 20, height: 20))
        closeBtn.bezelStyle = .circular
        closeBtn.isBordered = false
        closeBtn.image = NSImage(systemSymbolName: "xmark.circle.fill", accessibilityDescription: "Close")
        closeBtn.contentTintColor = .tertiaryLabelColor
        closeBtn.target = self
        closeBtn.action = #selector(closeButtonClicked)
        titleBar.addSubview(closeBtn)

        glassView.addSubview(titleBar)

        // --- Subtle separator ---
        let separator = NSView(frame: NSRect(x: 0, y: h - titleBarHeight - 0.5, width: w, height: 0.5))
        separator.wantsLayer = true
        separator.layer?.backgroundColor = NSColor.separatorColor.withAlphaComponent(0.3).cgColor
        glassView.addSubview(separator)

        // --- Chat terminal view ---
        let terminalFrame = NSRect(x: 0, y: 0, width: w, height: h - titleBarHeight - 0.5)
        let terminal = TerminalView(frame: terminalFrame)
        terminal.characterColor = characterColor
        terminal.onSendMessage = { [weak self] message in
            self?.handleUserMessage(message)
        }
        terminal.onStopRequested = { [weak self] in
            self?.claudeSession?.cancelActiveTurn()
            self?.terminalView?.endStreaming()
            self?.terminalView?.clearLiveStatus()
        }
        terminal.onConnectGranola = { [weak self] in
            self?.startGranolaSync()
        }
        glassView.addSubview(terminal)
        self.terminalView = terminal

        win.contentView = glassView
        popoverWindow = win
    }

    func updatePopoverPosition() {
        guard let popoverWindow, let window else { return }
        let charFrame = window.frame
        let popoverSize = popoverWindow.frame.size
        let x = charFrame.midX - popoverSize.width / 2
        let y = charFrame.maxY + 8
        popoverWindow.setFrameOrigin(NSPoint(x: x, y: y))
    }

    func updateThinkingBubble() {
        guard let thinkingBubbleWindow, let window else { return }
        let charFrame = window.frame
        let bubbleSize = thinkingBubbleWindow.frame.size
        let x = charFrame.midX - bubbleSize.width / 2
        let y = charFrame.maxY + 4
        thinkingBubbleWindow.setFrameOrigin(NSPoint(x: x, y: y))
    }

    @objc private func closeButtonClicked() {
        closePopover()
    }

    private func handleUserMessage(_ message: String) {
        guard let session = claudeSession else { return }
        let lower = message.lowercased()

        terminalView?.appendUserBubble(message)

        // Handle commitment queries locally first
        if lower.contains("commitment") || lower.contains("open items") || lower.contains("what did i promise") {
            let commitments = CommitmentStore().getAll()
            if commitments.isEmpty {
                // No commitments yet — need to run debriefs first
                let meetingCount = MeetingStore().count()
                if meetingCount > 0 {
                    terminalView?.appendSystemBubble(
                        "No commitments tracked yet. I need to debrief your meetings first to extract commitments.\n\n" +
                        "Try: \"Debrief my meeting [meeting name]\" to extract action items and commitments from a specific meeting."
                    )
                } else {
                    terminalView?.appendSystemBubble("No meetings synced yet. Connect to Granola first.")
                }
                return
            }

            // Show commitments from DB
            let open = commitments.filter { $0.status == "open" }
            let overdue = CommitmentStore().getOverdue()
            var response = "**\(open.count) open commitments**"
            if !overdue.isEmpty { response += " (\(overdue.count) overdue)" }
            response += "\n"

            if !overdue.isEmpty {
                response += "\n**Overdue:**\n"
                for c in overdue {
                    response += "  - \(c.ownerName): \(c.description)"
                    if let due = c.dueDate { response += " (due: \(String(due.prefix(10))))" }
                    response += "\n"
                }
            }

            if !open.isEmpty {
                response += "\n**Open:**\n"
                for c in open.prefix(15) {
                    response += "  - \(c.ownerName): \(c.description)\n"
                }
            }

            terminalView?.appendSystemBubble(response)
            return
        }

        // Handle weekly summary locally
        if lower.contains("weekly summary") || lower.contains("week's summary") {
            let summary = controller?.proactiveScheduler.generateWeeklySummary() ?? "No data available."
            terminalView?.appendSystemBubble(summary)
            return
        }

        // Send to Claude for everything else
        terminalView?.beginStreaming()
        session.send(message: message)
    }

    private func startGranolaSync() {
        // Check if Granola is installed first
        guard GranolaClient.isAvailable else {
            terminalView?.appendErrorBubble("Granola not found. Install Granola from granola.ai and open it at least once.")
            return
        }

        terminalView?.appendSystemBubble("Syncing with Granola...")
        terminalView?.setLiveStatus("Reading Granola meetings...", isBusy: true)

        guard let syncEngine = controller?.syncEngine else {
            terminalView?.clearLiveStatus()
            terminalView?.appendErrorBubble("Controller not available.")
            return
        }

        syncEngine.onSyncComplete = { [weak self] count in
            self?.terminalView?.clearLiveStatus()
            self?.setExpression(.happy)
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) { self?.setExpression(.idle) }
            UserDefaults.standard.set(true, forKey: "hasCompletedOnboarding")
            if count > 0 {
                self?.terminalView?.appendSystemBubble("Synced \(count) meetings from Granola!")
                self?.terminalView?.showMeetingsSummary()
            } else {
                // Check if we have existing meetings
                let total = MeetingStore().count()
                if total > 0 {
                    self?.terminalView?.appendSystemBubble("All \(total) meetings already up to date.")
                    self?.terminalView?.showMeetingsSummary()
                } else {
                    self?.terminalView?.appendSystemBubble("No meetings found in Granola. Have a meeting first, then sync again.")
                }
            }
        }

        syncEngine.onSyncError = { [weak self] error in
            self?.terminalView?.clearLiveStatus()
            self?.terminalView?.appendErrorBubble("Could not sync: \(error.localizedDescription)")
        }

        syncEngine.syncNow()
    }

    // MARK: - Event Monitors

    private func installClickOutsideMonitor() {
        removeClickOutsideMonitor()
        clickOutsideMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
            guard let self, let popoverWindow = self.popoverWindow else { return }
            let screenLocation = NSEvent.mouseLocation
            if !popoverWindow.frame.contains(screenLocation) && !self.window.frame.contains(screenLocation) {
                self.closePopover()
            }
        }
    }

    private func removeClickOutsideMonitor() {
        if let monitor = clickOutsideMonitor {
            NSEvent.removeMonitor(monitor)
            clickOutsideMonitor = nil
        }
    }

    private func installEscapeKeyMonitor() {
        removeEscapeKeyMonitor()
        escapeKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.keyCode == 53 {
                self?.closePopover()
                return nil
            }
            return event
        }
    }

    private func removeEscapeKeyMonitor() {
        if let monitor = escapeKeyMonitor {
            NSEvent.removeMonitor(monitor)
            escapeKeyMonitor = nil
        }
    }
}
