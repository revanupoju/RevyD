import AppKit

class RevyDController {
    var characters: [RevyCharacter] = []
    private var displayLink: CVDisplayLink?
    private var fallbackDisplayTimer: Timer?
    private var lastTickTimestamp: CFTimeInterval = 0
    var pinnedScreenIndex: Int = -1
    private static let onboardingKey = "hasCompletedOnboarding"
    let syncEngine = GranolaSyncEngine()
    let proactiveScheduler = ProactiveScheduler()

    func start() {
        let revy = RevyCharacter()
        revy.accelStart = 2.5
        revy.fullSpeedStart = 3.2
        revy.decelStart = 7.8
        revy.walkStop = 8.4
        revy.walkAmountRange = 0.5...0.95
        revy.yOffset = 4
        revy.characterColor = NSColor(red: 0.40, green: 0.60, blue: 1.0, alpha: 1.0)
        revy.positionProgress = 0.5
        revy.pauseEndTime = CACurrentMediaTime() + Double.random(in: 0.5...2.0)
        revy.setup()

        characters = [revy]
        characters.forEach { $0.controller = self }

        startDisplayLink()

        // Start proactive checks (overdue commitments, upcoming meetings)
        // Request notification permission
        NotificationManager.shared.requestPermission()

        // Monitor network for offline mode
        _ = NetworkMonitor.shared
        NetworkMonitor.shared.onStatusChanged = { [weak self] connected in
            guard let char = self?.characters.first else { return }
            if !connected {
                char.showBubble(text: "offline", isCompletion: false)
                char.setExpression(.alert)
            } else {
                char.showBubble(text: "online", isCompletion: true)
                char.setExpression(.happy)
                DispatchQueue.main.asyncAfter(deadline: .now() + 3) { char.setExpression(.idle) }
            }
        }

        proactiveScheduler.onOverdueCommitments = { [weak self] overdue in
            guard let char = self?.characters.first else { return }
            char.showBubble(text: "\(overdue.count) overdue", isCompletion: false)
            char.setExpression(.alert)
            NotificationManager.shared.notifyOverdue(overdue)
            DispatchQueue.main.asyncAfter(deadline: .now() + 5) { char.setExpression(.idle) }
        }
        proactiveScheduler.onPrepReady = { [weak self] title, _ in
            guard let char = self?.characters.first else { return }
            let shortTitle = String(title.prefix(20))
            char.showBubble(text: "\(shortTitle) soon", isCompletion: false)
            NotificationManager.shared.notifyUpcomingMeeting(title: title, inMinutes: 10, attendees: [])
        }
        proactiveScheduler.start()

        // Auto-sync with Granola if available
        if GranolaClient.isAvailable {
            syncEngine.syncNow()
        }

        // Index local documents in background
        let indexer = DocumentIndexer()
        indexer.onComplete = { count in
            SessionDebugLogger.log("indexer", "Background indexing: \(count) documents indexed")
        }
        indexer.indexAll()

        if !UserDefaults.standard.bool(forKey: Self.onboardingKey) {
            triggerOnboarding()
        }
    }

    private func triggerOnboarding() {
        guard let revy = characters.first else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            revy.showBubble(text: "hi!", isCompletion: true)
        }
    }

    func completeOnboarding() {
        UserDefaults.standard.set(true, forKey: Self.onboardingKey)
    }

    func currentDockMetrics() -> (screen: NSScreen, dockX: CGFloat, dockWidth: CGFloat, dockTopY: CGFloat)? {
        guard let screen = activeScreen else { return nil }

        let dockX: CGFloat
        let dockWidth: CGFloat
        let dockTopY: CGFloat

        if screenHasDock(screen) {
            (dockX, dockWidth) = getDockIconArea(screen: screen)
            dockTopY = screen.visibleFrame.origin.y
        } else {
            let margin: CGFloat = 40.0
            dockX = screen.frame.origin.x + margin
            dockWidth = screen.frame.width - margin * 2
            dockTopY = screen.frame.origin.y
        }

        return (screen, dockX, dockWidth, dockTopY)
    }

    // MARK: - Dock Geometry

    private func getDockIconArea(screen: NSScreen) -> (x: CGFloat, width: CGFloat) {
        let dockDefaults = UserDefaults(suiteName: "com.apple.dock")
        let tileSize = CGFloat(dockDefaults?.double(forKey: "tilesize") ?? 48)
        let slotWidth = tileSize * 1.25

        let persistentApps = dockDefaults?.array(forKey: "persistent-apps")?.count ?? 0
        let persistentOthers = dockDefaults?.array(forKey: "persistent-others")?.count ?? 0
        let showRecents = dockDefaults?.bool(forKey: "show-recents") ?? true
        let recentApps = showRecents ? (dockDefaults?.array(forKey: "recent-apps")?.count ?? 0) : 0
        let totalIcons = persistentApps + persistentOthers + recentApps

        var dividers = 0
        if persistentApps > 0 && (persistentOthers > 0 || recentApps > 0) { dividers += 1 }
        if persistentOthers > 0 && recentApps > 0 { dividers += 1 }
        if showRecents && recentApps > 0 { dividers += 1 }

        let dividerWidth: CGFloat = 12.0
        var dockWidth = slotWidth * CGFloat(totalIcons) + CGFloat(dividers) * dividerWidth
        let edgePadding = max(14.0, tileSize * 0.28)

        if totalIcons == 0 {
            dockWidth = max(220.0, tileSize * 4.0)
        } else {
            dockWidth += edgePadding * 2.0
        }

        let maximumDockWidth = screen.visibleFrame.width - 24.0
        let minimumUsableWidth = max(220.0, min(screen.visibleFrame.width - 48.0, screen.frame.width * 0.45))
        if dockWidth < minimumUsableWidth {
            dockWidth = minimumUsableWidth
        }

        dockWidth = min(dockWidth, maximumDockWidth)
        let dockX = screen.frame.midX - dockWidth / 2.0
        return (dockX, dockWidth)
    }

    // MARK: - Display Link

    private func startDisplayLink() {
        CVDisplayLinkCreateWithActiveCGDisplays(&displayLink)
        startFallbackDisplayTimer()
        guard let displayLink = displayLink else { return }

        let callback: CVDisplayLinkOutputCallback = { _, _, _, _, _, userInfo -> CVReturn in
            let controller = Unmanaged<RevyDController>.fromOpaque(userInfo!).takeUnretainedValue()
            DispatchQueue.main.async {
                controller.tick(source: .displayLink)
            }
            return kCVReturnSuccess
        }

        CVDisplayLinkSetOutputCallback(displayLink, callback,
                                       Unmanaged.passUnretained(self).toOpaque())
        _ = CVDisplayLinkStart(displayLink)
    }

    private func startFallbackDisplayTimer() {
        fallbackDisplayTimer?.invalidate()
        let timer = Timer(timeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
            self?.tick(source: .fallbackTimer)
        }
        fallbackDisplayTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    var activeScreen: NSScreen? {
        if pinnedScreenIndex >= 0, pinnedScreenIndex < NSScreen.screens.count {
            return NSScreen.screens[pinnedScreenIndex]
        }
        return NSScreen.main
    }

    private func screenHasDock(_ screen: NSScreen) -> Bool {
        return screen.visibleFrame.origin.y > screen.frame.origin.y
    }

    private enum TickSource {
        case displayLink
        case fallbackTimer
    }

    private func tick(source: TickSource) {
        let now = CACurrentMediaTime()
        if source == .fallbackTimer, now - lastTickTimestamp < (1.0 / 90.0) {
            return
        }
        lastTickTimestamp = now

        guard let metrics = currentDockMetrics() else { return }

        let activeChars = characters.filter { $0.window.isVisible }
        for char in activeChars {
            if char.isIdleForPopover { continue }
            if char.isPaused && now >= char.pauseEndTime {
                char.pauseEndTime = now + Double.random(in: 5.0...10.0)
            }
        }
        for char in activeChars {
            char.update(screen: metrics.screen, dockX: metrics.dockX, dockWidth: metrics.dockWidth, dockTopY: metrics.dockTopY)
        }
    }

    deinit {
        if let displayLink = displayLink {
            CVDisplayLinkStop(displayLink)
        }
        fallbackDisplayTimer?.invalidate()
    }
}
