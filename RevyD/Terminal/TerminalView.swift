import AppKit

final class TerminalView: NSView {
    var scrollView: NSScrollView!
    var transcriptStack: NSStackView!
    var inputField: NSTextField!
    var inputContainer: NSVisualEffectView!
    var liveStatusLabel: NSTextField?
    var liveStatusContainer: NSView?
    var characterColor: NSColor = NSColor(red: 0.40, green: 0.60, blue: 1.0, alpha: 1.0)

    var onSendMessage: ((String) -> Void)?
    var onStopRequested: (() -> Void)?
    var onConnectGranola: (() -> Void)?
    private var hasStartedConversation = false

    private var isStreaming = false
    private var currentStreamingBubble: NSView?
    private var currentStreamingLabel: NSTextField?
    private var streamedText = ""

    override init(frame: NSRect) {
        super.init(frame: frame)
        setupViews()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupViews()
    }

    private func setupViews() {
        let inputAreaHeight: CGFloat = 52

        // --- Scroll view for transcript ---
        scrollView = NSScrollView(frame: NSRect(x: 0, y: inputAreaHeight, width: bounds.width, height: bounds.height - inputAreaHeight))
        scrollView.autoresizingMask = [.width, .height]
        scrollView.hasVerticalScroller = true
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        scrollView.scrollerStyle = .overlay
        scrollView.scrollerKnobStyle = .light

        // Transcript stack
        transcriptStack = NSStackView()
        transcriptStack.orientation = .vertical
        transcriptStack.alignment = .leading
        transcriptStack.spacing = 10
        transcriptStack.edgeInsets = NSEdgeInsets(top: 16, left: 16, bottom: 16, right: 16)

        let clipView = NSClipView()
        clipView.documentView = transcriptStack
        clipView.drawsBackground = false
        scrollView.contentView = clipView

        transcriptStack.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            transcriptStack.widthAnchor.constraint(equalTo: clipView.widthAnchor)
        ])

        addSubview(scrollView)

        // --- Input area: frosted glass bar ---
        inputContainer = NSVisualEffectView(frame: NSRect(x: 0, y: 0, width: bounds.width, height: inputAreaHeight))
        inputContainer.autoresizingMask = [.width]
        inputContainer.material = .menu
        inputContainer.blendingMode = .withinWindow
        inputContainer.state = .active

        // Top border on input area
        let inputBorder = NSView(frame: NSRect(x: 0, y: inputAreaHeight - 0.5, width: bounds.width, height: 0.5))
        inputBorder.autoresizingMask = [.width]
        inputBorder.wantsLayer = true
        inputBorder.layer?.backgroundColor = NSColor.separatorColor.withAlphaComponent(0.2).cgColor
        inputContainer.addSubview(inputBorder)

        // Text field with rounded glass look
        inputField = NSTextField(frame: NSRect(x: 14, y: 10, width: bounds.width - 28, height: 32))
        inputField.autoresizingMask = [.width]
        inputField.placeholderString = "Ask RevyD anything..."
        inputField.font = .systemFont(ofSize: 13, weight: .regular)
        inputField.textColor = .labelColor
        inputField.backgroundColor = NSColor.controlBackgroundColor.withAlphaComponent(0.3)
        inputField.isBordered = false
        inputField.isBezeled = true
        inputField.bezelStyle = .roundedBezel
        inputField.focusRingType = .none
        inputField.cell?.usesSingleLineMode = true
        inputField.cell?.wraps = false
        inputField.cell?.isScrollable = true
        inputField.wantsLayer = true
        inputField.layer?.cornerRadius = 8
        inputField.delegate = self
        inputContainer.addSubview(inputField)

        addSubview(inputContainer)
    }

    // MARK: - Welcome

    func showWelcomePanel() {
        let isFirstLaunch = !UserDefaults.standard.bool(forKey: "hasCompletedOnboarding")
        let meetingCount = MeetingStore().count()

        if isFirstLaunch && meetingCount == 0 {
            showOnboarding()
        } else if meetingCount > 0 {
            appendSystemBubble("Welcome back. Here's your dashboard.")
            showMeetingsSummary()
        } else {
            appendSystemBubble("Welcome to RevyD, your AI chief of staff.\n\nI help you debrief meetings, track commitments, and prepare for upcoming calls.")
            showConnectGranolaButton()
        }
    }

    private func showOnboarding() {
        // Step 1: Welcome
        appendSystemBubble("Hey! I'm RevyD, your AI chief of staff.\n\nI live on your dock and help you:\n  -  Debrief meetings with structured insights\n  -  Track commitments across conversations\n  -  Prepare you before upcoming calls\n  -  Connect your meeting notes with your documents")

        // Step 2: Check what's available
        var statusLines: [String] = []

        // Granola
        if GranolaClient.isAvailable {
            statusLines.append("  -  Granola detected — ready to sync meetings")
        } else {
            statusLines.append("  -  Granola not found — install from granola.ai")
        }

        // Claude Code
        if AppSettings.claudeCodePath() != nil {
            statusLines.append("  -  Claude Code detected — AI ready")
        } else {
            statusLines.append("  -  Claude Code not found — install from claude.ai/download")
        }

        // Calendar
        statusLines.append("  -  Calendar access — will be requested for meeting prep")

        appendSystemBubble("**Setup Status**\n\n" + statusLines.joined(separator: "\n"))

        // Step 3: Show connect button if Granola available
        if GranolaClient.isAvailable {
            showConnectGranolaButton()
        }
    }

    func showMeetingsSummary() {
        let store = MeetingStore()
        let commitmentStore = CommitmentStore()
        let meetings = store.getRecent(limit: 5)
        let openCommitments = commitmentStore.openCount()
        let overdueCommitments = commitmentStore.overdueCount()

        var summary = "**\(store.count()) meetings synced**"
        if openCommitments > 0 {
            summary += " | \(openCommitments) open commitments"
        }
        if overdueCommitments > 0 {
            summary += " | \(overdueCommitments) overdue"
        }
        summary += "\n\nRecent meetings:"
        for m in meetings {
            let date = String(m.createdAt.prefix(10))
            summary += "\n\u{2022} \(m.title) (\(date))"
        }

        appendSystemBubble(summary)

        // Show starter prompts
        showStarterPrompts(meetings: meetings)
    }

    // MARK: - Starter Prompts

    func showStarterPrompts(meetings: [Meeting] = []) {
        let store = MeetingStore()
        let personStore = PersonStore()
        let latestMeeting = meetings.first ?? store.getRecent(limit: 1).first
        let topPeople = personStore.getFrequent(limit: 3)

        // SF Symbols only — no emojis
        var prompts: [(sfSymbol: String, label: String, prompt: String)] = []

        if let latest = latestMeeting {
            let shortTitle = String(latest.title.prefix(28))
            prompts.append((
                sfSymbol: "doc.text.magnifyingglass",
                label: "Debrief: \(shortTitle)",
                prompt: "Debrief my meeting \"\(latest.title)\""
            ))
        }

        prompts.append((
            sfSymbol: "checkmark.circle",
            label: "Open commitments",
            prompt: "Show all my open commitments"
        ))

        if let topPerson = topPeople.first {
            let firstName = topPerson.name.components(separatedBy: " ").first ?? topPerson.name
            prompts.append((
                sfSymbol: "person.crop.circle",
                label: "History with \(firstName)",
                prompt: "What have I discussed with \(topPerson.name)?"
            ))
        }

        prompts.append((
            sfSymbol: "magnifyingglass",
            label: "Search all meetings",
            prompt: "What decisions were made this week?"
        ))

        prompts.append((
            sfSymbol: "calendar.badge.clock",
            label: "This week's summary",
            prompt: "Summarize all my meetings from this week"
        ))

        prompts.append((
            sfSymbol: "flag.checkered",
            label: "Prep for next meeting",
            prompt: "Prepare me for my next meeting"
        ))

        // Build horizontal carousel above the input field
        buildPromptCarousel(prompts: prompts)
    }

    private var promptCarousel: NSScrollView?

    private func buildPromptCarousel(prompts: [(sfSymbol: String, label: String, prompt: String)]) {
        // Remove existing carousel if any
        promptCarousel?.removeFromSuperview()

        let carouselHeight: CGFloat = 40
        let chipSpacing: CGFloat = 8
        let chipPadding: CGFloat = 14

        // Horizontal scroll view sitting just above the input container
        let scrollContainer = NSScrollView(frame: NSRect(
            x: 0, y: inputContainer.frame.maxY,
            width: bounds.width, height: carouselHeight
        ))
        scrollContainer.autoresizingMask = [.width]
        scrollContainer.hasHorizontalScroller = false
        scrollContainer.hasVerticalScroller = false
        scrollContainer.drawsBackground = false
        scrollContainer.borderType = .noBorder

        // Horizontal stack of chips
        let hStack = NSStackView()
        hStack.orientation = .horizontal
        hStack.spacing = chipSpacing
        hStack.alignment = .centerY
        hStack.edgeInsets = NSEdgeInsets(top: 0, left: chipPadding, bottom: 0, right: chipPadding)

        for prompt in prompts {
            let chip = createPromptChip(sfSymbol: prompt.sfSymbol, label: prompt.label, prompt: prompt.prompt)
            hStack.addArrangedSubview(chip)
        }

        hStack.translatesAutoresizingMaskIntoConstraints = false
        let clipView = NSClipView()
        clipView.documentView = hStack
        clipView.drawsBackground = false
        scrollContainer.contentView = clipView

        NSLayoutConstraint.activate([
            hStack.heightAnchor.constraint(equalToConstant: carouselHeight),
        ])

        addSubview(scrollContainer)
        promptCarousel = scrollContainer

        // Adjust scroll view frame so transcript doesn't overlap
        scrollView.frame = NSRect(
            x: 0,
            y: inputContainer.frame.maxY + carouselHeight,
            width: bounds.width,
            height: bounds.height - inputContainer.frame.height - carouselHeight
        )
    }

    private func createPromptChip(sfSymbol: String, label: String, prompt: String) -> NSView {
        let chip = NSView()
        chip.wantsLayer = true
        chip.layer?.cornerRadius = 8
        chip.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.06).cgColor
        chip.layer?.borderColor = NSColor.white.withAlphaComponent(0.10).cgColor
        chip.layer?.borderWidth = 0.5

        // SF Symbol icon
        let iconView = NSImageView(frame: .zero)
        let symbolConfig = NSImage.SymbolConfiguration(pointSize: 11, weight: .medium)
        iconView.image = NSImage(systemSymbolName: sfSymbol, accessibilityDescription: label)?
            .withSymbolConfiguration(symbolConfig)
        iconView.contentTintColor = .tertiaryLabelColor
        iconView.translatesAutoresizingMaskIntoConstraints = false
        chip.addSubview(iconView)

        let textButton = NSButton(frame: .zero)
        textButton.isBordered = false
        textButton.bezelStyle = .inline
        textButton.alignment = .left
        textButton.font = .systemFont(ofSize: 11.5, weight: .medium)
        textButton.contentTintColor = .secondaryLabelColor
        textButton.title = label
        textButton.target = self
        textButton.action = #selector(promptChipTapped(_:))
        textButton.toolTip = prompt
        textButton.translatesAutoresizingMaskIntoConstraints = false
        chip.addSubview(textButton)

        NSLayoutConstraint.activate([
            iconView.leadingAnchor.constraint(equalTo: chip.leadingAnchor, constant: 8),
            iconView.centerYAnchor.constraint(equalTo: chip.centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 14),
            iconView.heightAnchor.constraint(equalToConstant: 14),

            textButton.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 5),
            textButton.trailingAnchor.constraint(equalTo: chip.trailingAnchor, constant: -8),
            textButton.topAnchor.constraint(equalTo: chip.topAnchor, constant: 6),
            textButton.bottomAnchor.constraint(equalTo: chip.bottomAnchor, constant: -6),
        ])

        return chip
    }

    @objc private func promptChipTapped(_ sender: NSButton) {
        guard let prompt = sender.toolTip, !prompt.isEmpty else { return }
        onSendMessage?(prompt)
    }

    private func hidePromptCarousel() {
        guard let carousel = promptCarousel else { return }
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.2
            carousel.animator().alphaValue = 0
        } completionHandler: { [weak self] in
            carousel.removeFromSuperview()
            self?.promptCarousel = nil
            // Restore scroll view to full height
            guard let self else { return }
            let inputH = self.inputContainer.frame.height
            self.scrollView.frame = NSRect(
                x: 0, y: inputH,
                width: self.bounds.width,
                height: self.bounds.height - inputH
            )
        }
    }

    func showConnectGranolaButton() {
        // Create a card with a "Connect to Granola" button
        let card = NSVisualEffectView()
        card.wantsLayer = true
        card.material = .popover
        card.blendingMode = .withinWindow
        card.state = .active
        card.layer?.cornerRadius = 12
        card.layer?.borderColor = NSColor(red: 0.77, green: 0.82, blue: 0.31, alpha: 0.25).cgColor
        card.layer?.borderWidth = 0.5

        // Granola app icon
        let iconView = NSImageView(frame: .zero)
        if let resourceURL = Bundle.main.resourceURL {
            let iconPath = resourceURL.appendingPathComponent("CharacterSprites/granola-icon@2x.png").path
            iconView.image = NSImage(contentsOfFile: iconPath)
        }
        iconView.imageScaling = .scaleProportionallyUpOrDown
        iconView.wantsLayer = true
        iconView.layer?.cornerRadius = 6
        iconView.layer?.masksToBounds = true
        iconView.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(iconView)

        let titleLabel = NSTextField(labelWithString: "Granola")
        titleLabel.font = .systemFont(ofSize: 15, weight: .semibold)
        titleLabel.textColor = .labelColor
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(titleLabel)

        let descLabel = NSTextField(wrappingLabelWithString: "Sync your meetings to get debriefs, track commitments, and prepare for calls.")
        descLabel.font = .systemFont(ofSize: 12, weight: .regular)
        descLabel.textColor = .secondaryLabelColor
        descLabel.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(descLabel)

        // Granola brand color: #C5D14E (that yellow-green)
        let granolaBrand = NSColor(red: 0.77, green: 0.82, blue: 0.31, alpha: 1.0)

        let connectButton = NSButton(title: "Sync Meetings", target: self, action: #selector(connectGranolaTapped))
        connectButton.isBordered = false
        connectButton.wantsLayer = true
        connectButton.layer?.backgroundColor = granolaBrand.cgColor
        connectButton.layer?.cornerRadius = 8
        connectButton.font = .systemFont(ofSize: 13, weight: .semibold)
        connectButton.contentTintColor = NSColor(red: 0.12, green: 0.12, blue: 0.10, alpha: 1.0)
        connectButton.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(connectButton)

        NSLayoutConstraint.activate([
            iconView.topAnchor.constraint(equalTo: card.topAnchor, constant: 14),
            iconView.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 14),
            iconView.widthAnchor.constraint(equalToConstant: 30),
            iconView.heightAnchor.constraint(equalToConstant: 30),

            titleLabel.centerYAnchor.constraint(equalTo: iconView.centerYAnchor),
            titleLabel.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 8),

            descLabel.topAnchor.constraint(equalTo: iconView.bottomAnchor, constant: 10),
            descLabel.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 16),
            descLabel.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -16),

            connectButton.topAnchor.constraint(equalTo: descLabel.bottomAnchor, constant: 14),
            connectButton.centerXAnchor.constraint(equalTo: card.centerXAnchor),
            connectButton.widthAnchor.constraint(equalToConstant: 160),
            connectButton.heightAnchor.constraint(equalToConstant: 36),
            connectButton.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -16),
        ])

        transcriptStack.addArrangedSubview(card)
        card.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            card.leadingAnchor.constraint(equalTo: transcriptStack.leadingAnchor, constant: 16),
            card.trailingAnchor.constraint(equalTo: transcriptStack.trailingAnchor, constant: -16),
        ])

        scrollToBottom()
    }

    @objc private func connectGranolaTapped() {
        onConnectGranola?()
    }

    // MARK: - Bubbles

    func appendUserBubble(_ text: String) {
        // Hide starter prompts once conversation begins
        if !hasStartedConversation {
            hasStartedConversation = true
            hidePromptCarousel()
        }

        let bubble = createBubble(text: text, style: .user)
        transcriptStack.addArrangedSubview(bubble)

        bubble.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            bubble.trailingAnchor.constraint(equalTo: transcriptStack.trailingAnchor, constant: -16),
            bubble.widthAnchor.constraint(lessThanOrEqualTo: transcriptStack.widthAnchor, multiplier: 0.80)
        ])
        scrollToBottom()
    }

    func appendSystemBubble(_ text: String) {
        let bubble = createBubble(text: text, style: .system)
        transcriptStack.addArrangedSubview(bubble)

        bubble.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            bubble.leadingAnchor.constraint(equalTo: transcriptStack.leadingAnchor, constant: 16),
            bubble.widthAnchor.constraint(lessThanOrEqualTo: transcriptStack.widthAnchor, multiplier: 0.88)
        ])
        scrollToBottom()
    }

    func appendErrorBubble(_ text: String) {
        let bubble = createBubble(text: text, style: .error)
        transcriptStack.addArrangedSubview(bubble)

        bubble.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            bubble.leadingAnchor.constraint(equalTo: transcriptStack.leadingAnchor, constant: 16),
            bubble.widthAnchor.constraint(lessThanOrEqualTo: transcriptStack.widthAnchor, multiplier: 0.88)
        ])
        scrollToBottom()
    }

    // MARK: - Streaming

    private var shimmerView: NSView?
    private var shimmerAnimation: CABasicAnimation?

    func beginStreaming() {
        isStreaming = true
        streamedText = ""
        inputField.isEnabled = false

        // Show shimmer skeleton placeholder
        let skeleton = createShimmerSkeleton()
        transcriptStack.addArrangedSubview(skeleton)
        skeleton.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            skeleton.leadingAnchor.constraint(equalTo: transcriptStack.leadingAnchor, constant: 16),
            skeleton.trailingAnchor.constraint(equalTo: transcriptStack.trailingAnchor, constant: -60),
            skeleton.heightAnchor.constraint(equalToConstant: 72),
        ])
        shimmerView = skeleton
        scrollToBottom()
    }

    func appendStreamingText(_ delta: String) {
        // Remove shimmer on first text
        if streamedText.isEmpty {
            replaceShimmerWithBubble()
        }
        streamedText += delta
        currentStreamingLabel?.stringValue = streamedText
        currentStreamingLabel?.sizeToFit()
        scrollToBottom()
    }

    private func replaceShimmerWithBubble() {
        if let shimmer = shimmerView {
            transcriptStack.removeArrangedSubview(shimmer)
            shimmer.removeFromSuperview()
            shimmerView = nil
        }

        let bubble = createBubble(text: "", style: .assistant)
        transcriptStack.addArrangedSubview(bubble)
        bubble.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            bubble.leadingAnchor.constraint(equalTo: transcriptStack.leadingAnchor, constant: 16),
            bubble.widthAnchor.constraint(lessThanOrEqualTo: transcriptStack.widthAnchor, multiplier: 0.88)
        ])
        currentStreamingBubble = bubble
        if let label = bubble.subviews.compactMap({ $0 as? NSTextField }).first {
            currentStreamingLabel = label
        }
    }

    private func createShimmerSkeleton() -> NSView {
        let container = NSView()
        container.wantsLayer = true
        container.layer?.cornerRadius = 12
        container.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.03).cgColor

        let lineHeights: [CGFloat] = [10, 10, 7]
        let lineWidths: [CGFloat] = [0.80, 0.60, 0.40]

        for (i, (h, wFrac)) in zip(lineHeights, lineWidths).enumerated() {
            let line = NSView()
            line.wantsLayer = true
            line.layer?.cornerRadius = h / 2
            line.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.08).cgColor
            line.translatesAutoresizingMaskIntoConstraints = false
            container.addSubview(line)

            NSLayoutConstraint.activate([
                line.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 14),
                line.topAnchor.constraint(equalTo: container.topAnchor, constant: CGFloat(14 + i * 20)),
                line.heightAnchor.constraint(equalToConstant: h),
                line.widthAnchor.constraint(equalTo: container.widthAnchor, multiplier: wFrac),
            ])

            // Pulse shimmer — reliable with auto layout
            let pulse = CABasicAnimation(keyPath: "opacity")
            pulse.fromValue = 0.3
            pulse.toValue = 1.0
            pulse.duration = 0.8
            pulse.autoreverses = true
            pulse.repeatCount = .infinity
            pulse.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            // Stagger each line
            pulse.beginTime = CACurrentMediaTime() + Double(i) * 0.15
            line.layer?.add(pulse, forKey: "shimmer")
        }

        return container
    }

    func updateStreamingText(_ fullText: String) {
        streamedText = fullText
        currentStreamingLabel?.stringValue = fullText
        currentStreamingLabel?.sizeToFit()
        scrollToBottom()
    }

    func endStreaming() {
        isStreaming = false
        inputField.isEnabled = true

        // Remove shimmer if still showing (e.g. error before any text)
        if let shimmer = shimmerView {
            transcriptStack.removeArrangedSubview(shimmer)
            shimmer.removeFromSuperview()
            shimmerView = nil
        }

        // Re-render the final streamed text with markdown formatting
        if let label = currentStreamingLabel, !streamedText.isEmpty {
            label.attributedStringValue = MarkdownRenderer.render(streamedText, fontSize: 13, textColor: .labelColor)
            label.sizeToFit()
            scrollToBottom()
        }

        currentStreamingBubble = nil
        currentStreamingLabel = nil
        streamedText = ""

        DispatchQueue.main.async { [weak self] in
            self?.window?.makeFirstResponder(self?.inputField)
        }
    }

    // MARK: - Live Status

    func setLiveStatus(_ text: String, isBusy: Bool, isError: Bool = false) {
        if liveStatusContainer == nil {
            let container = NSView(frame: NSRect(x: 16, y: 0, width: bounds.width - 32, height: 22))
            container.wantsLayer = true

            let label = NSTextField(labelWithString: "")
            label.font = .systemFont(ofSize: 11, weight: .medium)
            label.textColor = .tertiaryLabelColor
            label.frame = NSRect(x: 0, y: 0, width: bounds.width - 32, height: 22)
            container.addSubview(label)

            liveStatusLabel = label
            liveStatusContainer = container
            transcriptStack.addArrangedSubview(container)
        }

        let prefix = isBusy ? "\u{25CF} " : ""  // bullet point
        liveStatusLabel?.stringValue = "\(prefix)\(text)"
        liveStatusLabel?.textColor = isError
            ? NSColor.systemRed.withAlphaComponent(0.8)
            : .tertiaryLabelColor
        scrollToBottom()
    }

    func clearLiveStatus() {
        if let container = liveStatusContainer {
            transcriptStack.removeArrangedSubview(container)
            container.removeFromSuperview()
        }
        liveStatusContainer = nil
        liveStatusLabel = nil
    }

    // MARK: - Bubble Factory

    private enum BubbleStyle {
        case user
        case assistant
        case system
        case error
    }

    private func createBubble(text: String, style: BubbleStyle) -> NSView {
        // Use NSVisualEffectView for glass-like bubbles
        let bubble = NSVisualEffectView()
        bubble.wantsLayer = true
        bubble.state = .active
        bubble.blendingMode = .withinWindow

        switch style {
        case .user:
            bubble.material = .selection
            bubble.layer?.backgroundColor = characterColor.withAlphaComponent(0.12).cgColor
            bubble.layer?.borderColor = characterColor.withAlphaComponent(0.25).cgColor
            bubble.layer?.borderWidth = 0.5

        case .assistant:
            bubble.material = .popover
            bubble.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.04).cgColor
            bubble.layer?.borderColor = NSColor.white.withAlphaComponent(0.08).cgColor
            bubble.layer?.borderWidth = 0.5

        case .system:
            bubble.material = .popover
            bubble.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.02).cgColor
            bubble.layer?.borderColor = NSColor.separatorColor.withAlphaComponent(0.15).cgColor
            bubble.layer?.borderWidth = 0.5

        case .error:
            bubble.material = .popover
            bubble.layer?.backgroundColor = NSColor.systemRed.withAlphaComponent(0.08).cgColor
            bubble.layer?.borderColor = NSColor.systemRed.withAlphaComponent(0.2).cgColor
            bubble.layer?.borderWidth = 0.5
        }

        bubble.layer?.cornerRadius = 12

        let textColor: NSColor
        switch style {
        case .user:     textColor = .labelColor
        case .assistant: textColor = .labelColor
        case .system:   textColor = .secondaryLabelColor
        case .error:    textColor = NSColor.systemRed
        }

        let label = NSTextField(wrappingLabelWithString: "")
        label.isSelectable = true
        label.drawsBackground = false
        label.isBordered = false
        label.maximumNumberOfLines = 0
        label.lineBreakMode = .byWordWrapping

        // Render markdown for assistant/system messages, plain for user
        if (style == .assistant || style == .system) && !text.isEmpty {
            label.attributedStringValue = MarkdownRenderer.render(text, fontSize: 13, textColor: textColor)
        } else {
            label.font = .systemFont(ofSize: 13, weight: .regular)
            label.textColor = textColor
            label.stringValue = text
        }

        label.translatesAutoresizingMaskIntoConstraints = false
        bubble.addSubview(label)

        NSLayoutConstraint.activate([
            label.topAnchor.constraint(equalTo: bubble.topAnchor, constant: 10),
            label.leadingAnchor.constraint(equalTo: bubble.leadingAnchor, constant: 12),
            label.trailingAnchor.constraint(equalTo: bubble.trailingAnchor, constant: -12),
            label.bottomAnchor.constraint(equalTo: bubble.bottomAnchor, constant: -10),
        ])

        return bubble
    }

    private func scrollToBottom() {
        DispatchQueue.main.async { [weak self] in
            guard let self, let documentView = self.scrollView.documentView else { return }
            let maxY = documentView.frame.height - self.scrollView.contentView.bounds.height
            if maxY > 0 {
                NSAnimationContext.runAnimationGroup { ctx in
                    ctx.duration = 0.15
                    ctx.allowsImplicitAnimation = true
                    self.scrollView.contentView.scroll(to: NSPoint(x: 0, y: maxY))
                }
                self.scrollView.reflectScrolledClipView(self.scrollView.contentView)
            }
        }
    }
}

// MARK: - NSTextFieldDelegate

extension TerminalView: NSTextFieldDelegate {
    func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        if commandSelector == #selector(NSResponder.insertNewline(_:)) {
            let text = inputField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { return true }
            inputField.stringValue = ""
            onSendMessage?(text)
            return true
        }
        return false
    }
}
