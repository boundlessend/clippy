import AppKit

// прозрачная панель поверх всех окон, не ворующая фокус (облачко с фактом)
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
    panel.ignoresMouseEvents = true          // облачко не интерактивно, клики проходят насквозь
    panel.contentView = contentView
    return panel
}

// сторона экрана, где стоит док (читается из настроек Dock)
enum DockOrientation { case bottom, left, right }

// ориентация дока из com.apple.dock (bottom/left/right), по умолчанию bottom
func dockOrientation() -> DockOrientation {
    let v = CFPreferencesCopyAppValue("orientation" as CFString,
                                      "com.apple.dock" as CFString) as? String
    switch v {
    case "left": return .left
    case "right": return .right
    default: return .bottom
    }
}

// pure: точка на краю иконки дока, обращённом к экрану (для якоря облачка).
// док внизу -> верх иконки; слева -> правый край; справа -> левый край
func dockEdgeAnchor(iconRect: NSRect, orientation: DockOrientation) -> NSPoint {
    switch orientation {
    case .bottom: return NSPoint(x: iconRect.midX, y: iconRect.maxY)
    case .left:   return NSPoint(x: iconRect.maxX, y: iconRect.midY)
    case .right:  return NSPoint(x: iconRect.minX, y: iconRect.midY)
    }
}

// pure: левый нижний угол облачка так, чтобы оно стояло у иконки со стороны дока
// и не вылезало за видимую область экрана
func bubbleOrigin(anchor: NSPoint, orientation: DockOrientation,
                  bubbleSize: NSSize, screen: NSRect) -> NSPoint {
    let gap: CGFloat = 8
    var x: CGFloat
    var y: CGFloat
    switch orientation {
    case .bottom:
        x = anchor.x - bubbleSize.width / 2
        y = anchor.y + gap
    case .left:
        x = anchor.x + gap
        y = anchor.y - bubbleSize.height / 2
    case .right:
        x = anchor.x - bubbleSize.width - gap
        y = anchor.y - bubbleSize.height / 2
    }
    x = min(max(x, screen.minX + 4), screen.maxX - bubbleSize.width - 4)
    y = min(max(y, screen.minY + 4), screen.maxY - bubbleSize.height - 4)
    return NSPoint(x: x, y: y)
}
