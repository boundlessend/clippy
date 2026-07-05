import AppKit

// P0: пустая прозрачная панель поверх всех окон, не ворующая фокус.
// содержимое (скрепыш + баллон) заменит заглушку в P1/P2.
@MainActor
func makeClippyPanel() -> NSPanel {
    let size = NSSize(width: 200, height: 160)
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

    // ponytail: жёлтая плашка-заглушка вместо скрепыша, чтобы видеть панель в P0
    let placeholder = NSView(frame: NSRect(origin: .zero, size: size))
    placeholder.wantsLayer = true
    placeholder.layer?.backgroundColor = NSColor.systemYellow.withAlphaComponent(0.85).cgColor
    placeholder.layer?.cornerRadius = 16
    panel.contentView = placeholder

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
