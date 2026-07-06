import AppKit

// прозрачная панель поверх всех окон, не ворующая фокус (скрепыш и баллон)
@MainActor
func makeOverlayPanel(contentView: NSView, size: NSSize) -> NSPanel {
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

// pure: имя направленной анимации (Look*/Gesture*) по вектору from -> to.
// доминирующая ось задаёт направление; в AppKit y растёт вверх
func directionalAnimation(prefix: String, from: NSPoint, to: NSPoint) -> String {
    let dx = to.x - from.x
    let dy = to.y - from.y
    if abs(dx) >= abs(dy) { return dx >= 0 ? "\(prefix)Right" : "\(prefix)Left" }
    return dy >= 0 ? "\(prefix)Up" : "\(prefix)Down"
}

// pure: случайная позиция окна (левый нижний угол) в пределах видимой области с отступом
func randomWalkOrigin(in visibleFrame: NSRect, panelSize: NSSize, margin: CGFloat) -> NSPoint {
    let minX = visibleFrame.minX + margin
    let maxX = max(minX, visibleFrame.maxX - panelSize.width - margin)
    let minY = visibleFrame.minY + margin
    let maxY = max(minY, visibleFrame.maxY - panelSize.height - margin)
    return NSPoint(x: CGFloat.random(in: minX...maxX), y: CGFloat.random(in: minY...maxY))
}
