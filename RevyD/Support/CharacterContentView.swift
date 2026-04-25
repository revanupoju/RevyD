import AppKit

class CharacterContentView: NSView {
    weak var character: RevyCharacter?

    override func mouseDown(with event: NSEvent) {
        character?.handleClick()
    }

    override func mouseDragged(with event: NSEvent) {
        guard let character else { return }
        if !character.isDraggingHorizontally {
            character.beginHorizontalDrag(at: event)
        } else {
            character.continueHorizontalDrag(with: event)
        }
    }

    override func mouseUp(with event: NSEvent) {
        guard let character, character.isDraggingHorizontally else { return }
        character.endHorizontalDrag()
    }
}
