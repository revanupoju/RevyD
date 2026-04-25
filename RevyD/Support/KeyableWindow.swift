import AppKit

/// A borderless window that can become key and accept keyboard input.
/// Standard borderless NSWindows refuse to become key, which breaks text fields.
final class KeyableWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}
