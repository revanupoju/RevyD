import AppKit

final class RevyCharacter {
    var window: NSWindow!
    var imageView: NSImageView!

    let displayHeight: CGFloat = 96
    let displayWidth: CGFloat = 96

    // Movement timing (matches Lenny's walk cycle curve)
    var accelStart: CFTimeInterval = 3.0
    var fullSpeedStart: CFTimeInterval = 3.75
    var decelStart: CFTimeInterval = 7.5
    var walkStop: CFTimeInterval = 8.25
    var walkAmountRange: ClosedRange<CGFloat> = 0.25...0.5
    var yOffset: CGFloat = 0
    var characterColor: NSColor = NSColor(red: 0.40, green: 0.60, blue: 1.0, alpha: 1.0)

    // Movement state
    var walkStartTime: CFTimeInterval = 0
    var positionProgress: CGFloat = 0.0
    var isWalking = false
    var isPaused = true
    var pauseEndTime: CFTimeInterval = 0
    var goingRight = true
    var walkStartPos: CGFloat = 0.0
    var walkEndPos: CGFloat = 0.0
    var currentTravelDistance: CGFloat = 500.0
    var walkStartPixel: CGFloat = 0.0
    var walkEndPixel: CGFloat = 0.0

    // UI state
    var isIdleForPopover = false
    var popoverWindow: NSWindow?
    var terminalView: TerminalView?
    var claudeSession: ClaudeSession?
    var clickOutsideMonitor: Any?
    var escapeKeyMonitor: Any?
    weak var controller: RevyDController?

    // Bubble state
    var thinkingBubbleWindow: NSWindow?
    var currentPhrase = ""
    var showingCompletion = false
    var completionBubbleExpiry: CFTimeInterval = 0
    var currentActivityStatus = ""

    // Drag state
    var isDraggingHorizontally = false
    var usesExpandedHorizontalRange = false

    var isClaudeBusy: Bool { claudeSession?.isBusy ?? false }

    var directionalImages: [RevyFacing: NSImage] = [:]
    var expressionImages: [RevyExpression: NSImage] = [:]
    var currentExpression: RevyExpression = .idle

    init() {}
}
