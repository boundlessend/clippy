import AppKit

// скрепыш: короткий левый клик -> onClick (жест), перетаскивание двигает окно,
// правый клик -> контекстное меню (назначается извне через .menu)
final class ClippyImageView: NSImageView {
    var onClick: (() -> Void)?
    private var didDrag = false

    override func mouseDown(with event: NSEvent) { didDrag = false }

    override func mouseDragged(with event: NSEvent) {
        didDrag = true
        guard let w = window else { return }
        w.setFrameOrigin(NSPoint(x: w.frame.origin.x + event.deltaX,
                                 y: w.frame.origin.y - event.deltaY))
    }

    override func mouseUp(with event: NSEvent) {
        if !didDrag { onClick?() }
    }

    override func rightMouseDown(with event: NSEvent) {
        guard let menu else { return }
        NSMenu.popUpContextMenu(menu, with: event, for: self)
    }
}
