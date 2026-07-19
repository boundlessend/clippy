import AppKit

// проверка обновлений через GitHub Releases: тихая автопроверка раз в сутки
// (алерт - только при новой версии) и ручная из меню/настроек (отвечает всегда).
// состояние (время последней проверки, пропущенная версия) - в UserDefaults

let releasesPageURL = URL(string: "https://github.com/boundlessend/clippy/releases")!
private let latestReleaseURL =
    URL(string: "https://api.github.com/repos/boundlessend/clippy/releases/latest")!

// версия приложения из бандла; dev-сборка (swift run, без Info.plist) -> "dev"
func currentAppVersion() -> String {
    Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "dev"
}

// pure: числовые компоненты версии "1.2.3"; пустой массив - не версия (напр. "dev")
func versionComponents(_ s: String) -> [Int] {
    let parts = s.split(separator: ".").map { Int($0) }
    guard !parts.isEmpty, parts.allSatisfy({ $0 != nil }) else { return [] }
    return parts.compactMap { $0 }
}

// pure: true когда remote новее local; несравнимое (dev-сборка, кривой тег) - false
func isNewerVersion(_ remote: String, than local: String) -> Bool {
    let r = versionComponents(remote)
    let l = versionComponents(local)
    guard !r.isEmpty, !l.isEmpty else { return false }
    for i in 0..<max(r.count, l.count) {
        let rv = i < r.count ? r[i] : 0
        let lv = i < l.count ? l[i] : 0
        if rv != lv { return rv > lv }
    }
    return false
}

private struct LatestRelease: Decodable {
    let tagName: String
    let htmlURL: String
    enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case htmlURL = "html_url"
    }
}

@MainActor
enum UpdateCheck {
    static let interval: TimeInterval = 24 * 60 * 60
    private static let lastCheckKey = "lastUpdateCheck"
    private static let skippedKey = "skippedUpdateVersion"

    // на старте и затем ежечасно: проверяем, прошли ли сутки с последней удачной проверки
    // (часовой шаг переживает сон/пробуждение мака лучше, чем один 24-часовой таймер)
    static func startAutoChecks() {
        autoCheckIfDue()
        Timer.scheduledTimer(withTimeInterval: 60 * 60, repeats: true) { _ in
            Task { @MainActor in autoCheckIfDue() }
        }
    }

    private static func autoCheckIfDue() {
        let last = UserDefaults.standard.object(forKey: lastCheckKey) as? Date ?? .distantPast
        guard Date().timeIntervalSince(last) >= interval else { return }
        Task { @MainActor in
            let release: (version: String, url: URL)
            do { release = try await fetchLatest() }
            catch {
                NSLog("clippy: автопроверка обновлений не удалась: \(error)")
                return                                     // нет сети - попробуем через час
            }
            UserDefaults.standard.set(Date(), forKey: lastCheckKey)
            guard isNewerVersion(release.version, than: currentAppVersion()),
                  release.version != UserDefaults.standard.string(forKey: skippedKey) else { return }
            presentUpdateAlert(release)
        }
    }

    // ручная проверка: всегда отвечает алертом (новая версия / актуально / ошибка)
    static func checkManually() {
        let local = currentAppVersion()
        guard !versionComponents(local).isEmpty else {
            info("Dev-сборка", "Запуск из исходников: сравнивать версию не с чем.")
            return
        }
        Task { @MainActor in
            do {
                let release = try await fetchLatest()
                UserDefaults.standard.set(Date(), forKey: lastCheckKey)
                if isNewerVersion(release.version, than: local) {
                    presentUpdateAlert(release)
                } else {
                    info("Обновлений нет", "У вас последняя версия (\(local)).")
                }
            } catch {
                info("Не удалось проверить обновления", "\(error)")
            }
        }
    }

    private static func fetchLatest() async throws -> (version: String, url: URL) {
        var req = URLRequest(url: latestReleaseURL)
        req.timeoutInterval = networkTimeout
        req.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        let (data, resp) = try await tipSession.data(for: req)
        try ensureOK(resp)
        let release = try JSONDecoder().decode(LatestRelease.self, from: data)
        let version = release.tagName.hasPrefix("v")
            ? String(release.tagName.dropFirst()) : release.tagName
        return (version, URL(string: release.htmlURL) ?? releasesPageURL)
    }

    private static func presentUpdateAlert(_ release: (version: String, url: URL)) {
        let a = NSAlert()
        a.messageText = "Доступна версия \(release.version)"
        a.informativeText = "У вас \(currentAppVersion()). Скачайте новый DMG со страницы релиза."
        a.addButton(withTitle: "Открыть страницу")
        a.addButton(withTitle: "Позже")
        a.addButton(withTitle: "Пропустить эту версию")
        NSApp.activate(ignoringOtherApps: true)
        switch a.runModal() {
        case .alertFirstButtonReturn: NSWorkspace.shared.open(release.url)
        case .alertThirdButtonReturn:
            UserDefaults.standard.set(release.version, forKey: skippedKey)
        default: break
        }
    }

    private static func info(_ title: String, _ text: String) {
        let a = NSAlert()
        a.messageText = title
        a.informativeText = text
        NSApp.activate(ignoringOtherApps: true)
        a.runModal()
    }
}
