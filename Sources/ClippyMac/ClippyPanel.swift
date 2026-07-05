import AppKit

// прозрачная панель поверх всех окон, не ворующая фокус
@MainActor
func makeClippyPanel(contentView: NSView, size: NSSize) -> NSPanel {
    let panel = NSPanel(
        contentRect: NSRect(origin: .zero, size: size),
        styleMask: [.borderless, .nonactivatingPanel],
        backing: .buffered,
        defer: false
    )
    panel.isFloatingPanel = true
    panel.level = .floating
    panel.backgroundColor = .clear
    panel.isOpaque = false
    panel.hasShadow = false
    panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]
    panel.isMovableByWindowBackground = true
    panel.contentView = contentView
    return panel
}

@MainActor
func positionBottomRight(_ panel: NSPanel) {
    guard let screen = NSScreen.main else { return }
    let vf = screen.visibleFrame
    let margin: CGFloat = 24
    let x = vf.maxX - panel.frame.width - margin
    let y = vf.minY + margin
    panel.setFrameOrigin(NSPoint(x: x, y: y))
}
