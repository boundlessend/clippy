import AppKit
import ApplicationServices

// точное положение иконки этого приложения в доке через Accessibility (внешняя
// система - Dock, обращаемся напрямую). нужен доступ Accessibility; без него
// функции возвращают nil, и вызывающий откатывается на позицию курсора.

// якорь облачка на краю иконки, обращённом к экрану (координаты Cocoa).
// nil -> доступа нет или иконка не найдена -> фолбэк на курсор
@MainActor
func dockAnchor(orientation: DockOrientation) -> NSPoint? {
    guard let rect = dockIconRect() else { return nil }
    return dockEdgeAnchor(iconRect: rect, orientation: orientation)
}

// rect иконки этого приложения в доке (координаты Cocoa), либо nil
@MainActor
func dockIconRect() -> NSRect? {
    guard axTrusted() else { return nil }
    guard let dock = NSRunningApplication
        .runningApplications(withBundleIdentifier: "com.apple.dock").first else { return nil }
    // Dock кладёт в title отображаемое имя; сверяем со всеми вариантами имени приложения,
    // т.к. CFBundleName и CFBundleDisplayName могут различаться (иначе якорь тихо ломается)
    let info = Bundle.main.infoDictionary
    let names = Set([
        NSRunningApplication.current.localizedName,
        info?["CFBundleDisplayName"] as? String,
        info?["CFBundleName"] as? String,
    ].compactMap { $0 }.filter { !$0.isEmpty })
    guard !names.isEmpty else { return nil }

    let dockApp = AXUIElementCreateApplication(dock.processIdentifier)
    guard let list = firstChild(of: dockApp, role: kAXListRole as String),
          let items = axChildren(list) else { return nil }
    for item in items {
        if let title = axString(item, kAXTitleAttribute as String), names.contains(title) {
            return axRect(item)
        }
    }
    return nil
}

// системный запрос доступа показываем раз за запуск, а не навсегда: при переустановке
// ad-hoc-подписи грант сбрасывается, и на следующем старте нужно попросить снова
@MainActor private enum AXPromptState { static var shownThisLaunch = false }

@MainActor
private func axTrusted() -> Bool {
    if AXIsProcessTrusted() { return true }
    if !AXPromptState.shownThisLaunch {
        AXPromptState.shownThisLaunch = true
        let promptKey = kAXTrustedCheckOptionPrompt.takeUnretainedValue()
        _ = AXIsProcessTrustedWithOptions([promptKey: true] as CFDictionary)
    }
    return false
}

private func firstChild(of element: AXUIElement, role: String) -> AXUIElement? {
    for child in axChildren(element) ?? [] where axString(child, kAXRoleAttribute as String) == role {
        return child
    }
    return nil
}

private func axChildren(_ element: AXUIElement) -> [AXUIElement]? {
    var ref: CFTypeRef?
    guard AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &ref) == .success
    else { return nil }
    return ref as? [AXUIElement]
}

private func axString(_ element: AXUIElement, _ attr: String) -> String? {
    var ref: CFTypeRef?
    guard AXUIElementCopyAttributeValue(element, attr as CFString, &ref) == .success else { return nil }
    return ref as? String
}

// AX-позиция/размер -> NSRect в координатах Cocoa (переворот Y по высоте главного экрана,
// т.к. Accessibility отдаёт координаты от верхнего-левого угла главного дисплея вниз)
private func axRect(_ element: AXUIElement) -> NSRect? {
    var posRef: CFTypeRef?
    var sizeRef: CFTypeRef?
    guard AXUIElementCopyAttributeValue(element, kAXPositionAttribute as CFString, &posRef) == .success,
          AXUIElementCopyAttributeValue(element, kAXSizeAttribute as CFString, &sizeRef) == .success,
          let posVal = posRef, CFGetTypeID(posVal) == AXValueGetTypeID(),
          let sizeVal = sizeRef, CFGetTypeID(sizeVal) == AXValueGetTypeID() else { return nil }
    var pos = CGPoint.zero
    var size = CGSize.zero
    // AXValue может быть другого подтипа: тогда pos/size остались бы нулевыми и якорь
    // уехал бы в угол - лучше вернуть nil и откатиться на позицию курсора
    guard AXValueGetValue(posVal as! AXValue, .cgPoint, &pos),
          AXValueGetValue(sizeVal as! AXValue, .cgSize, &size) else { return nil }
    let primaryH = (NSScreen.screens.first { $0.frame.origin == .zero } ?? NSScreen.main)?
        .frame.height ?? 0
    return NSRect(x: pos.x, y: primaryH - pos.y - size.height, width: size.width, height: size.height)
}
