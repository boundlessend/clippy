import SwiftUI
import AppKit

// pure: случайный элемент, по возможности не равный current; nil при пустом списке
func pickRandomOther(from names: [String], current: String) -> String? {
    let others = names.filter { $0 != current }
    return (others.isEmpty ? names : others).randomElement()
}

// pure: порядок опроса провайдеров - выбранный, затем локальный фолбэк (без дублей)
func providerChain(selected: ProviderKind) -> [ProviderKind] {
    selected == .local ? [.local] : [selected, .local]
}

// статичный аватар персонажа: кадр RestPose (иначе первый непустой), обрезанный из спрайтшита
func agentAvatarImage(for ref: AgentRef) -> NSImage? {
    guard let agent = try? loadClippyAgent(from: ref.directory),
          let sheet = try? loadSpriteSheet(from: ref.directory) else { return nil }
    let anim = agent.animations["RestPose"] ?? agent.animations["Idle1_1"]
        ?? agent.animations.values.first
    guard let point = anim?.frames.lazy.compactMap({ $0.images?.first }).first,
          let cg = cropFrame(sheet: sheet, at: point, frameSize: agent.frameSize) else { return nil }
    return NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))
}

// окно настроек и его компоненты - в SettingsView.swift (struct SettingsRootView)

// размеры окна настроек - одно место (окно и контент совпадают)
let settingsWidth: CGFloat = 470
let settingsHeight: CGFloat = 640

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate, ObservableObject {
    @Published private(set) var availableAgents: [AgentRef] = []   // встроенный + из папки
    @Published private(set) var agentAvatars: [String: NSImage] = [:]   // имя -> аватар (кадр RestPose)
    @Published var isGeneratingPool = false                        // идёт генерация пачки фактов
    @Published private(set) var poolCount = 0                      // размер пула активного персонажа
    @Published private(set) var loginItemOn = false                // observable-зеркало статуса SMAppService
    private var dockView: NSImageView?                // куда рисует аниматор (иконка в доке)
    private var animator: SpriteAnimator?
    private var bubblePanel: NSPanel?                 // облачко с фактом у дока
    private var hideWork: DispatchWorkItem?
    private var settingsWindow: NSWindow?
    private var faqWindow: NSWindow?                  // окно «Частые вопросы»
    private var screenOff = false                    // экран заблокирован или дисплей спит

    var appVersion: String { currentAppVersion() }

    private var gestureInFlight = false               // играет одноразовый жест: idle его не прервёт
    private static let gestureMaxSteps = 60           // потолок кадров жеста (зацикленные не зависнут)

    func applicationDidFinishLaunching(_ notification: Notification) {
        reloadAgents()                            // список персонажей (встроенный + из папки)
        // случайный персонаж при старте, если включено в настройках (до setupDock)
        if AppSettings.shared.randomAgentOnLaunch, let name = randomAgentName() {
            AppSettings.shared.activeAgent = name
        }
        NSApp.mainMenu = makeMainMenu()           // меню приложения (Cmd+,, Cmd+Q)
        NSApp.setActivationPolicy(.regular)       // всегда в доке
        // «О программе» и Cmd-Tab берут applicationIconImage через кэш иконок macOS,
        // который держит старую иконку после замены .app - грузим свежую .icns из бандла явно
        if let iconURL = Bundle.main.url(forResource: "AppIcon", withExtension: "icns"),
           let icon = NSImage(contentsOf: iconURL) {
            NSApp.applicationIconImage = icon
        }
        setupDock()                               // анимированный персонаж в доке
        setupPowerNotifications()                 // пауза анимации при блокировке/сне экрана
        migrateLegacyLoginItemIfNeeded()          // перенос автозапуска со старого LaunchAgent на SMAppService
        UpdateCheck.startAutoChecks()             // тихая проверка новых релизов раз в сутки
    }

    func applicationWillTerminate(_ notification: Notification) {
        AppSettings.shared.flushPendingWrites()   // не потерять последний ввод ключа
    }

    // secure coding для восстановления состояния (macOS 14+): иначе рантайм-warning
    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool { true }

    // не крутить idle, когда иконка не видна (экран заблокирован или дисплей спит) -
    // экономия CPU/батареи; плюс опциональная пауза в режиме энергосбережения
    private func setupPowerNotifications() {
        let dc = DistributedNotificationCenter.default()
        dc.addObserver(forName: .init("com.apple.screenIsLocked"), object: nil, queue: .main) {
            [weak self] _ in MainActor.assumeIsolated { self?.setScreenOff(true) }
        }
        dc.addObserver(forName: .init("com.apple.screenIsUnlocked"), object: nil, queue: .main) {
            [weak self] _ in MainActor.assumeIsolated { self?.setScreenOff(false) }
        }
        let ws = NSWorkspace.shared.notificationCenter
        ws.addObserver(forName: NSWorkspace.screensDidSleepNotification, object: nil, queue: .main) {
            [weak self] _ in MainActor.assumeIsolated { self?.setScreenOff(true) }
        }
        ws.addObserver(forName: NSWorkspace.screensDidWakeNotification, object: nil, queue: .main) {
            [weak self] _ in MainActor.assumeIsolated { self?.setScreenOff(false) }
        }
        // режим энергосбережения включили/выключили - пересчитать (пауза, если стоит галочка)
        NotificationCenter.default.addObserver(
            forName: .NSProcessInfoPowerStateDidChange, object: nil, queue: .main) {
            [weak self] _ in MainActor.assumeIsolated { self?.refreshIdle() }
        }
    }

    // экран погас/зажёгся -> пересчитать, крутить ли idle
    private func setScreenOff(_ off: Bool) {
        screenOff = off
        refreshIdle()
    }

    // idle крутится только при активном экране и без паузы по энергосбережению.
    // единая точка решения: зовётся на блокировку/сон/энергосбережение/смену тумблера
    func refreshIdle() {
        let lowPowerPause = AppSettings.shared.pauseOnLowPower
            && ProcessInfo.processInfo.isLowPowerModeEnabled
        if screenOff || lowPowerPause {
            animator?.stop()
            gestureInFlight = false          // пауза отменяет и текущий жест
        } else if !gestureInFlight {
            animator?.loopIdle()             // играющий жест не рвём: его completion сам вернёт idle
        }
    }

    // левый клик по иконке в доке: всегда показываем факт у иконки, даже если открыто
    // окно настроек/FAQ/О программе. система при этом всё равно поднимет свои окна
    // (return true), а облачко - nonactivating-панель поверх всего
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool {
        showFact()
        return true
    }

    // файлы бросили на иконку в доке: персонаж их «съедает». выключенный Clippy не трогает
    func application(_ application: NSApplication, open urls: [URL]) {
        feed(urls)
    }

    private func feed(_ urls: [URL]) {
        guard AppSettings.shared.enabled, !urls.isEmpty else { return }
        if !AppSettings.shared.feedTrashAsked {               // при первом кормлении спрашиваем один раз
            AppSettings.shared.trashOnFeed = askFeedToTrash()
            AppSettings.shared.feedTrashAsked = true
        }
        playRandomGesture()                                   // реакция персонажа в доке
        let anchor = NSEvent.mouseLocation                    // курсор в момент броска - на иконке
        let label = urls.count == 1 ? urls[0].lastPathComponent : "\(urls.count) файлов"
        guard AppSettings.shared.trashOnFeed else {
            presentBubble("Ням! \(label)", anchor: anchor)    // файлы не трогаем
            return
        }
        // текст показываем по завершении recycle: при ошибке не врём «в Корзину»
        NSWorkspace.shared.recycle(urls) { [weak self] _, error in
            Task { @MainActor in
                guard let self else { return }
                if let error {
                    NSLog("clippy: не удалось отправить в корзину: \(error)")
                    self.presentBubble("Не смог отправить \(label) в Корзину", anchor: anchor)
                } else {
                    self.presentBubble("Ням! \(label) - в Корзину", anchor: anchor)
                }
            }
        }
    }

    // диалог первого кормления: спросить, отправлять ли кормлёные файлы в Корзину
    private func askFeedToTrash() -> Bool {
        let alert = NSAlert()
        alert.messageText = "Кормление файлами"
        alert.informativeText = "Когда вы бросаете файл на иконку Clippy, он его «съедает». "
            + "Отправлять такие файлы в Корзину? Это всегда можно изменить в настройках."
        alert.addButton(withTitle: "Не трогать файлы")       // первая = по умолчанию (безопасно)
        alert.addButton(withTitle: "Отправлять в Корзину")
        return alert.runModal() == .alertSecondButtonReturn
    }


    // правый клик по иконке в доке: меню (Quit док добавляет сам)
    func applicationDockMenu(_ sender: NSApplication) -> NSMenu? {
        let m = NSMenu()
        m.addItem(withTitle: "Показать факт", action: #selector(miFact), keyEquivalent: "")
        m.addItem(withTitle: "Показать жест", action: #selector(miGesture), keyEquivalent: "")
        // подменю конкретных жестов активного персонажа
        if let gestures = animator?.gestureNames, !gestures.isEmpty {
            let gItem = NSMenuItem(title: "Жесты", action: nil, keyEquivalent: "")
            let gSub = NSMenu()
            for g in gestures {
                let it = NSMenuItem(title: g, action: #selector(miPlayGesture(_:)), keyEquivalent: "")
                it.target = self
                it.representedObject = g
                gSub.addItem(it)
            }
            gItem.submenu = gSub
            m.addItem(gItem)
        }
        m.addItem(.separator())

        // подменю выбора персонажа (галочка на активном) + быстрый рандом
        let agentItem = NSMenuItem(title: "Персонаж", action: nil, keyEquivalent: "")
        let sub = NSMenu()
        let active = AppSettings.shared.activeAgent
        for ref in availableAgents {
            let it = NSMenuItem(title: ref.name, action: #selector(miPickAgent(_:)), keyEquivalent: "")
            it.target = self
            it.representedObject = ref.name
            it.state = ref.name == active ? .on : .off
            sub.addItem(it)
        }
        agentItem.submenu = sub
        m.addItem(agentItem)
        m.addItem(withTitle: "Случайный персонаж", action: #selector(miRandomAgent), keyEquivalent: "")
        m.addItem(.separator())

        m.addItem(withTitle: "Настройки…", action: #selector(miSettings), keyEquivalent: "")
        m.addItem(withTitle: "О программе Clippy Mac", action: #selector(miAbout), keyEquivalent: "")
        m.items.forEach { $0.target = self }      // топ-уровень; пункты подменю уже с target
        return m
    }

    // пересканировать папку персонажей; если активный пропал - вернуться к встроенному
    func reloadAgents() {
        availableAgents = discoverAgents()
        agentAvatars = Dictionary(
            availableAgents.compactMap { ref in agentAvatarImage(for: ref).map { (ref.name, $0) } },
            uniquingKeysWith: { first, _ in first })
        if !availableAgents.contains(where: { $0.name == AppSettings.shared.activeAgent }) {
            AppSettings.shared.activeAgent = builtInAgentName
            applyAgentChange()             // программный сброс: перестроить аниматор и обновить счётчик пула
        }
        // пулы пропавших персонажей не трогаем: папку могли вынести временно,
        // а генерация пула - платная; осиротевший JSON в Application Support безвреден
    }

    // открыть папку персонажей в Finder
    func showAgentsFolder() { NSWorkspace.shared.open(agentsFolder()) }

    // смена персонажа в настройках -> перестроить анимацию в доке и обновить счётчик пула
    func applyAgentChange() {
        rebuildDockAnimator()
        refreshPoolCount()
    }

    // актуализировать observable-состояние тумблера автозапуска: сам SMAppService не
    // observable, и без этого тумблер застревал в старом положении после ошибки или
    // изменения в Системных настройках
    func refreshLoginItem() { loginItemOn = isLoginItemEnabled() }

    // тумблер автозапуска с обратной связью: ошибка -> alert (в т.ч. dev-запуск без .app);
    // система ждёт подтверждения -> предлагаем открыть Системные настройки -> Объекты входа
    func applyLoginItem(_ enabled: Bool) {
        defer { refreshLoginItem() }              // тумблер отражает фактический статус, в т.ч. после ошибки
        do {
            try setLoginItem(enabled)
        } catch {
            let a = NSAlert()
            a.messageText = "Не удалось изменить автозапуск"
            a.informativeText = "\(error)\n\nАвтозапуск работает только у установленного приложения "
                + "(не при запуске из исходников)."
            a.runModal()
            return
        }
        if enabled, loginItemNeedsApproval() {
            let a = NSAlert()
            a.messageText = "Разрешите автозапуск"
            a.informativeText = "macOS ждёт подтверждения. Откройте Системные настройки -> Основные -> "
                + "Объекты входа и включите Clippy."
            a.addButton(withTitle: "Открыть настройки")
            a.addButton(withTitle: "Позже")
            if a.runModal() == .alertFirstButtonReturn { openLoginItemsSettings() }
        }
    }

    private func makeMainMenu() -> NSMenu {
        let main = NSMenu()
        let appItem = NSMenuItem()
        main.addItem(appItem)
        let appMenu = NSMenu()
        appItem.submenu = appMenu
        appMenu.addItem(withTitle: "О программе Clippy Mac", action: #selector(miAbout), keyEquivalent: "")
        appMenu.addItem(withTitle: "Проверить обновления…", action: #selector(miCheckUpdates), keyEquivalent: "")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Настройки…", action: #selector(miSettings), keyEquivalent: ",")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Выход", action: #selector(miQuit), keyEquivalent: "q")
        appMenu.items.forEach { $0.target = self }
        // меню Правка: AppKit диспетчеризует Cmd+V/C/X/A через главное меню - без этих
        // пунктов вставка/копирование не работают в полях настроек (target = responder chain)
        let editItem = NSMenuItem()
        main.addItem(editItem)
        let edit = NSMenu(title: "Правка")
        editItem.submenu = edit
        edit.addItem(withTitle: "Отменить", action: Selector(("undo:")), keyEquivalent: "z")
        edit.addItem(withTitle: "Повторить", action: Selector(("redo:")), keyEquivalent: "Z")
        edit.addItem(.separator())
        edit.addItem(withTitle: "Вырезать", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        edit.addItem(withTitle: "Копировать", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: "Вставить", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.addItem(withTitle: "Выделить всё", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        return main
    }

    @objc private func miFact() { showFact() }
    @objc private func miGesture() { playRandomGesture() }
    @objc private func miSettings() { showSettings() }
    @objc private func miQuit() { NSApp.terminate(nil) }
    @objc private func miCheckUpdates() { UpdateCheck.checkManually() }

    // случайный персонаж из меню дока (по возможности не текущий)
    @objc private func miRandomAgent() {
        guard let name = randomAgentName() else { return }
        AppSettings.shared.activeAgent = name
        applyAgentChange()
    }

    // выбор конкретного персонажа из подменю дока
    @objc private func miPickAgent(_ sender: NSMenuItem) {
        guard let name = sender.representedObject as? String,
              name != AppSettings.shared.activeAgent else { return }
        AppSettings.shared.activeAgent = name
        applyAgentChange()
    }

    // проиграть конкретный жест из подменю «Жесты»
    @objc private func miPlayGesture(_ sender: NSMenuItem) {
        guard let name = sender.representedObject as? String else { return }
        playGesture(name)
    }
    @objc private func miAbout() {
        NSApp.activate(ignoringOtherApps: true)
        NSApp.orderFrontStandardAboutPanel(options: [
            .applicationName: "Clippy Mac",
            .applicationVersion: appVersion,
            .credits: NSAttributedString(
                string: "ваш скрепыш в доке",
                attributes: [.font: NSFont.systemFont(ofSize: 11)]),
        ])
    }

    // общая фабрика окон настроек/FAQ: одинаковые стиль, размеры, delegate, автосейв позиции
    private func makePanelWindow<Content: View>(title: String, autosave: String,
                                                content: Content) -> NSWindow {
        let hosting = NSHostingController(rootView: content)
        hosting.sizingOptions = []                     // не навязывать окну размер контента
        let w = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: settingsWidth, height: settingsHeight),
            styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        w.contentViewController = hosting
        w.setContentSize(NSSize(width: settingsWidth, height: settingsHeight))
        w.minSize = NSSize(width: 440, height: 420)    // 6-колоночная сетка персонажей не влезала в 380
        w.title = title
        w.isReleasedWhenClosed = false
        w.delegate = self          // на закрытие отпускаем окно - разрыв retain-цикла
        w.center()
        w.setFrameAutosaveName(autosave)               // запоминаем размер и позицию между открытиями
        return w
    }

    // единое окно настроек: из дока и из меню приложения
    func showSettings() {
        refreshPoolCount()                         // счётчик пула актуален к открытию
        refreshLoginItem()                         // и тумблер автозапуска тоже
        if settingsWindow == nil {
            settingsWindow = makePanelWindow(title: "Настройки Clippy", autosave: "ClippySettingsWindow",
                                             content: SettingsRootView(delegate: self))
        }
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow?.makeKeyAndOrderFront(nil)
    }

    // окно «Частые вопросы»: гайды по настройке источников и добавлению персонажей
    func showFAQ() {
        if faqWindow == nil {
            faqWindow = makePanelWindow(title: "Частые вопросы", autosave: "ClippyFAQWindow",
                                        content: FAQView())
        }
        NSApp.activate(ignoringOtherApps: true)
        faqWindow?.makeKeyAndOrderFront(nil)
    }

    // окно закрыли: отпустить ссылку, иначе граф окна держит delegate (retain-цикл)
    func windowWillClose(_ notification: Notification) {
        let w = notification.object as? NSWindow
        if w === settingsWindow { settingsWindow = nil }
        if w === faqWindow { faqWindow = nil }
    }

    // MARK: - персонаж в доке

    // активный персонаж: из списка по имени, иначе первый (Clippy);
    // nil - библиотека пуста (повреждён бандл), рисовать некого
    private func activeAgentRef() -> AgentRef? {
        availableAgents.first { $0.name == AppSettings.shared.activeAgent }
            ?? availableAgents.first
    }

    // имя случайного персонажа, по возможности не текущего; nil - список пуст
    private func randomAgentName() -> String? {
        pickRandomOther(from: availableAgents.map(\.name), current: AppSettings.shared.activeAgent)
    }

    private func setupDock() {
        let iv = NSImageView(frame: NSRect(x: 0, y: 0, width: 128, height: 128))
        iv.imageScaling = .scaleProportionallyUpOrDown
        NSApp.dockTile.contentView = iv
        dockView = iv
        rebuildDockAnimator()
    }

    // построить аниматор активного персонажа и запустить бесконечный idle в доке
    private func rebuildDockAnimator() {
        guard let dockView, let ref = activeAgentRef() else { return }
        gestureInFlight = false                 // если сборка бросит на кривом agent.json, idle не должен остаться заглушённым
        do {
            let agent = try loadClippyAgent(from: ref.directory)
            let sheet = try loadSpriteSheet(from: ref.directory)
            let a = SpriteAnimator(imageView: dockView, sheet: sheet, agent: agent,
                                   soundsBase: ref.directory.appendingPathComponent("sounds"),
                                   onRender: { NSApp.dockTile.display() })
            animator?.stop()                       // погасить прежний, чтобы не дрались за иконку
            animator = a
            playGesture("Show")                    // приветственный жест, затем idle через гейт
        } catch {
            NSLog("clippy: failed to build dock animator: \(error)")
            // выбор уже переключён, а в доке остался прежний персонаж - не расходимся
            // молча: сообщаем и откатываемся на встроенного (он валиден, рекурсия одноразовая)
            presentErrorAlert("Не удалось загрузить персонажа «\(ref.name)»", error)
            if AppSettings.shared.activeAgent != builtInAgentName {
                AppSettings.shared.activeAgent = builtInAgentName
                applyAgentChange()
            }
        }
    }

    // MARK: - факт в облачке у дока

    // проиграть случайный жест активного персонажа
    func playRandomGesture() {
        guard let animator else { return }
        playGesture(animator.gestureNames.randomElement() ?? "Wave")
    }

    // проиграть один жест: пока он идёт, gestureInFlight не даёт refreshIdle его прервать;
    // по завершении снимаем флаг и через гейт возвращаемся в idle
    private func playGesture(_ name: String) {
        guard let animator else { return }
        gestureInFlight = true
        animator.play(name, maxSteps: Self.gestureMaxSteps) { [weak self] in
            guard let self else { return }
            self.gestureInFlight = false
            self.refreshIdle()
        }
    }

    // показать облачко у иконки и завести таймер автоскрытия (длиннее текст - дольше показ)
    private func presentBubble(_ text: String, anchor: NSPoint) {
        showBubble(text, anchor: anchor)
        scheduleHide(after: bubbleDuration(for: text))
    }

    // длительность показа облачка от длины текста, зажатая в разумные рамки
    private func bubbleDuration(for text: String) -> Double {
        min(18, max(6, 6 + Double(text.count) * 0.045))
    }

    // подсказка, если выбран LLM-источник в режиме пула, а пул активного персонажа пуст:
    // иначе молча показался бы локальный фолбэк, и непонятно, что пул не наполнен
    private func emptyPoolHint() -> String? {
        let s = AppSettings.shared
        guard s.usePool(for: s.providerKind), PoolStore.count(character: s.activeAgent) == 0 else { return nil }
        return "Пул фактов пуст - сгенерируйте их в настройках"
    }

    private var factInFlight = false      // защита от серии кликов: один запрос за раз (LLM - платный/медленный)

    // показать факт у иконки в доке; если у персонажа нет фактов - ничего не показываем
    func showFact() {
        guard AppSettings.shared.enabled, !factInFlight else { return }
        // якорь - курсор, зафиксированный в момент клика (по клику из дока он на иконке;
        // из меню/настроек облачко встаёт у места вызова). показываем после загрузки факта
        let anchor = NSEvent.mouseLocation
        playRandomGesture()                             // мгновенная реакция: клик услышан, факт грузится
        if let hint = emptyPoolHint() {                 // пул выбран, но пуст - подсказать, не молчать
            presentBubble(hint, anchor: anchor)
            return
        }
        factInFlight = true
        Task { @MainActor in
            defer { self.factInFlight = false }
            guard let tip = await self.fetchTip() else {
                let s = AppSettings.shared
                // единственный «тихий» случай, который стоит объяснить: локальный источник при
                // снятых всех категориях. остальное (у персонажа нет tips.json) - молча, как раньше
                if s.providerKind == .local, s.enabledCategories.isEmpty {
                    self.presentBubble("Все категории фактов выключены - включите в настройках", anchor: anchor)
                } else {
                    NSLog("clippy: фактов для персонажа нет - облачко не показываем")
                }
                return
            }
            self.presentBubble(tip, anchor: anchor)
        }
    }

    private func showBubble(_ text: String, anchor: NSPoint) {
        let orient = dockOrientation()
        let host = NSHostingView(rootView: SpeechBubbleView(text: text, dock: orient))
        let size = host.fittingSize
        host.frame = NSRect(origin: .zero, size: size)

        bubblePanel?.orderOut(nil)
        let bp = makeOverlayPanel(contentView: host, size: size)
        bubblePanel = bp

        // экран, на котором кликнули (мультимонитор), иначе главный
        let screen = NSScreen.screens.first { $0.frame.contains(anchor) } ?? NSScreen.main
        let visible = screen?.visibleFrame ?? .zero
        bp.setFrameOrigin(bubbleOrigin(anchor: anchor, orientation: orient,
                                       bubbleSize: size, screen: visible))
        bp.orderFrontRegardless()
    }

    private func scheduleHide(after seconds: Double) {
        hideWork?.cancel()
        let panel = bubblePanel          // прячем именно эту панель, а не ту, что окажется текущей на момент срабатывания
        let work = DispatchWorkItem { [weak panel] in panel?.orderOut(nil) }
        hideWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds, execute: work)
    }

    // MARK: - контент (сборка провайдеров - в ProviderFactory.swift)

    // фолбэк-цепочка: выбранный провайдер, при ошибке - локальные факты персонажа
    private func fetchTip() async -> String? {
        for kind in providerChain(selected: AppSettings.shared.providerKind) {
            do {
                let tip = try await makeTipProvider(kind: kind, settings: AppSettings.shared,
                                                    agentDirectory: activeAgentRef()?.directory).nextTip()
                if !tip.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return tip }
                // пустой результат (не throw) не показываем пустым облачком - идём к фолбэку
            } catch { NSLog("clippy: провайдер \(kind.rawValue) не сработал: \(error)") }
        }
        return nil
    }

    // MARK: - генерация пула

    private var poolTask: Task<Void, Never>?          // текущая генерация пула (для отмены)

    // сгенерировать пачку фактов текущим LLM-источником и дописать в пул активного персонажа
    func generatePool(count: Int) {
        let s = AppSettings.shared
        let kind = s.providerKind
        guard kind == .ollama || kind == .claude, !isGeneratingPool else { return }
        let character = s.activeAgent
        let cfg = kind == .ollama ? s.ollamaConfig : s.claudeConfig
        let maxTokens = min(8000, count * max(80, cfg.maxLen))
        isGeneratingPool = true
        poolTask = Task { @MainActor in
            defer { isGeneratingPool = false; poolTask = nil }
            do {
                let provider = try makeLLMProvider(kind: kind, settings: s, maxTokens: maxTokens)
                let facts = try await generateFactBatch(provider, style: cfg.prompt, count: count)
                try Task.checkCancellation()
                try PoolStore.append(character: character, facts: facts)
                refreshPoolCount()
            } catch is CancellationError {
                NSLog("clippy: генерация пула отменена")
            } catch let e as URLError where e.code == .cancelled {
                // отмена во время сетевого запроса приходит как URLError(.cancelled),
                // а не CancellationError - это тоже отмена, алерт не показываем
                NSLog("clippy: генерация пула отменена")
            } catch {
                NSLog("clippy: генерация пула не удалась: \(error)")
                presentErrorAlert("Не удалось сгенерировать факты", error)
            }
        }
    }

    // отменить текущую генерацию (отменяет и сетевой запрос внутри)
    func cancelGeneration() { poolTask?.cancel() }

    // ошибку показываем sheet'ом на окне настроек, если оно открыто, иначе модально
    private func presentErrorAlert(_ title: String, _ error: Error) {
        let a = NSAlert()
        a.messageText = title
        a.informativeText = "\(error)"
        if let w = settingsWindow, w.isVisible {
            a.beginSheetModal(for: w, completionHandler: nil)
        } else {
            a.runModal()
        }
    }

    // очистить пул активного персонажа (сгенерировать заново с нуля)
    func clearPool() {
        do { try PoolStore.clear(character: AppSettings.shared.activeAgent) }
        catch {
            NSLog("clippy: не удалось очистить пул: \(error)")
            presentErrorAlert("Не удалось очистить пул", error)
        }
        refreshPoolCount()
    }

    // пересчитать размер пула активного персонажа (для счётчика в настройках)
    func refreshPoolCount() {
        poolCount = PoolStore.count(character: AppSettings.shared.activeAgent)
    }
}
