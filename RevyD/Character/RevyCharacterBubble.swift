import AppKit

extension RevyCharacter {
    func showBubble(text: String, isCompletion: Bool = false) {
        currentPhrase = text
        showingCompletion = isCompletion

        if thinkingBubbleWindow == nil {
            createBubbleWindow()
        }

        guard let bubbleWindow = thinkingBubbleWindow else { return }
        if let label = bubbleWindow.contentView?.subviews.first as? NSTextField {
            label.stringValue = text
        }

        updateThinkingBubble()
        bubbleWindow.orderFrontRegardless()

        if isCompletion {
            completionBubbleExpiry = CACurrentMediaTime() + 3.0
            DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) { [weak self] in
                guard let self, self.showingCompletion else { return }
                self.hideBubble()
            }
        }
    }

    func hideBubble() {
        thinkingBubbleWindow?.orderOut(nil)
        showingCompletion = false
        currentPhrase = ""
    }

    private func createBubbleWindow() {
        let bubbleWidth: CGFloat = 80
        let bubbleHeight: CGFloat = 28

        let win = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: bubbleWidth, height: bubbleHeight),
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )
        win.isOpaque = false
        win.backgroundColor = .clear
        win.hasShadow = true
        win.level = NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue + 8)
        win.ignoresMouseEvents = true
        win.collectionBehavior = [.canJoinAllSpaces, .stationary]

        let container = NSView(frame: NSRect(x: 0, y: 0, width: bubbleWidth, height: bubbleHeight))
        container.wantsLayer = true
        container.layer?.backgroundColor = NSColor(white: 0.15, alpha: 0.92).cgColor
        container.layer?.cornerRadius = 10
        container.layer?.borderColor = characterColor.withAlphaComponent(0.4).cgColor
        container.layer?.borderWidth = 1

        let label = NSTextField(labelWithString: "")
        label.font = .monospacedSystemFont(ofSize: 11, weight: .medium)
        label.textColor = .white
        label.alignment = .center
        label.frame = NSRect(x: 4, y: 4, width: bubbleWidth - 8, height: bubbleHeight - 8)
        container.addSubview(label)

        win.contentView = container
        thinkingBubbleWindow = win
    }
}
