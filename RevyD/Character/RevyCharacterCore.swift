import AppKit

extension RevyCharacter {
    func setup() {
        loadDirectionalImages()

        let screen = NSScreen.main!
        let dockTopY = screen.visibleFrame.origin.y
        let bottomPadding = displayHeight * 0.15
        let y = dockTopY - bottomPadding + yOffset

        let contentRect = CGRect(x: 0, y: y, width: displayWidth, height: displayHeight)
        window = NSWindow(
            contentRect: contentRect,
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.level = .statusBar
        window.ignoresMouseEvents = false
        window.collectionBehavior = [.canJoinAllSpaces, .stationary]

        let hostView = CharacterContentView(frame: CGRect(x: 0, y: 0, width: displayWidth, height: displayHeight))
        hostView.character = self
        hostView.wantsLayer = true
        hostView.layer?.backgroundColor = NSColor.clear.cgColor

        let imageView = NSImageView(frame: hostView.bounds)
        imageView.imageScaling = .scaleProportionallyUpOrDown
        imageView.animates = true
        imageView.autoresizingMask = [.width, .height]
        hostView.addSubview(imageView)
        self.imageView = imageView
        setFacing(.front)

        window.contentView = hostView
        window.contentView?.toolTip = "RevyD — Click to chat"
        window.orderFrontRegardless()
    }

    func handleClick() {
        if isIdleForPopover {
            closePopover()
        } else {
            openPopover()
        }
    }

    func setFacing(_ facing: RevyFacing) {
        imageView?.image = directionalImages[facing] ?? directionalImages[.front]
    }

    /// Load the actual pixel art robot sprites from CharacterSprites/
    private func loadDirectionalImages() {
        directionalImages[.front] = loadSprite(named: "revy-front.png")
        directionalImages[.left] = loadSprite(named: "revy-walk-left.gif", fallback: "revy-left.png")
        directionalImages[.right] = loadSprite(named: "revy-walk-right.gif", fallback: "revy-right.png")

        // Expression variants
        expressionImages[.idle] = directionalImages[.front]
        expressionImages[.thinking] = loadSprite(named: "revy-thinking.png", fallback: "revy-front.png")
        expressionImages[.happy] = loadSprite(named: "revy-happy.png", fallback: "revy-front.png")
        expressionImages[.alert] = loadSprite(named: "revy-alert.png", fallback: "revy-front.png")
    }

    func setExpression(_ expression: RevyExpression) {
        currentExpression = expression
        if !isWalking {
            imageView?.image = expressionImages[expression] ?? directionalImages[.front]
        }
    }

    private func loadSprite(named name: String, fallback: String? = nil) -> NSImage {
        guard let resourceURL = Bundle.main.resourceURL else {
            return placeholderImage()
        }
        let spritesDir = resourceURL.appendingPathComponent("CharacterSprites")
        let primaryPath = spritesDir.appendingPathComponent(name).path

        if let image = NSImage(contentsOfFile: primaryPath) {
            return image
        }

        if let fallback {
            let fallbackPath = spritesDir.appendingPathComponent(fallback).path
            if let image = NSImage(contentsOfFile: fallbackPath) {
                return image
            }
        }

        return placeholderImage()
    }

    private func placeholderImage() -> NSImage {
        let size = NSSize(width: displayWidth, height: displayHeight)
        let image = NSImage(size: size)
        image.lockFocus()

        // Simple fallback circle if sprites are missing
        characterColor.withAlphaComponent(0.8).setFill()
        NSBezierPath(ovalIn: NSRect(x: 16, y: 16, width: 64, height: 64)).fill()

        NSColor.white.setFill()
        let letter = NSAttributedString(string: "R", attributes: [
            .font: NSFont.boldSystemFont(ofSize: 28),
            .foregroundColor: NSColor.white
        ])
        letter.draw(at: NSPoint(x: 36, y: 32))

        image.unlockFocus()
        return image
    }
}
