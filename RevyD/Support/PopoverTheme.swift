import AppKit

struct PopoverTheme {
    let name: String
    let popoverBg: NSColor
    let popoverBorder: NSColor
    let popoverBorderWidth: CGFloat
    let popoverCornerRadius: CGFloat
    let titleBarBg: NSColor
    let titleText: NSColor
    let titleFont: NSFont
    let titleString: String
    let separatorColor: NSColor
    let accentColor: NSColor
    let inputBg: NSColor
    let inputText: NSColor
    let userText: NSColor
    let assistantText: NSColor
    let assistantBubbleBg: NSColor
    let systemBubbleBg: NSColor
    let systemBubbleText: NSColor

    static var current: PopoverTheme = .revyDark

    static let revyDark = PopoverTheme(
        name: "RevyD",
        popoverBg: NSColor(red: 0.06, green: 0.06, blue: 0.10, alpha: 0.97),
        popoverBorder: NSColor(red: 0.35, green: 0.55, blue: 0.95, alpha: 0.5),
        popoverBorderWidth: 1.0,
        popoverCornerRadius: 14,
        titleBarBg: NSColor(red: 0.08, green: 0.08, blue: 0.13, alpha: 1.0),
        titleText: NSColor(red: 0.45, green: 0.65, blue: 1.0, alpha: 1.0),
        titleFont: .monospacedSystemFont(ofSize: 11, weight: .bold),
        titleString: "REVYD",
        separatorColor: NSColor(red: 0.35, green: 0.55, blue: 0.95, alpha: 0.22),
        accentColor: NSColor(red: 0.40, green: 0.60, blue: 1.0, alpha: 1.0),
        inputBg: NSColor(red: 0.10, green: 0.10, blue: 0.15, alpha: 1.0),
        inputText: NSColor(white: 0.90, alpha: 1.0),
        userText: NSColor(white: 0.95, alpha: 1.0),
        assistantText: NSColor(white: 0.88, alpha: 1.0),
        assistantBubbleBg: NSColor(red: 0.10, green: 0.12, blue: 0.18, alpha: 0.8),
        systemBubbleBg: NSColor(red: 0.08, green: 0.10, blue: 0.15, alpha: 0.6),
        systemBubbleText: NSColor(white: 0.70, alpha: 1.0)
    )
}
