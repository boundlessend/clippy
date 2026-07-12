import SwiftUI
import AppKit

// окно настроек в стиле утверждённого макета (design/settings-onboarding-mock.html):
// секции с цветными eyebrow, карточки-группы, ряды с иконками и тумблерами,
// сетка персонажей с реальными спрайтами, чипы категорий, шапка с аватаром.

// MARK: - палитра (значения токенов макета, светлая/тёмная тема)

private extension NSColor {
    convenience init(hex: UInt) {
        self.init(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
                  green: CGFloat((hex >> 8) & 0xFF) / 255,
                  blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
    }
}

private func dyn(_ light: UInt, _ dark: UInt) -> Color {
    Color(nsColor: NSColor(name: nil, dynamicProvider: { ap in
        let isDark = ap.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        return NSColor(hex: isDark ? dark : light)
    }))
}

private extension Color { init(hex: UInt) { self = Color(nsColor: NSColor(hex: hex)) } }

private enum P {
    static let ground = dyn(0xECECED, 0x0F0F11)
    static let card = dyn(0xFFFFFF, 0x232327)
    static let sunken = dyn(0xF6F6F9, 0x1B1B1F)
    static let ink = dyn(0x1C1C1E, 0xF3F3F6)
    static let ink2 = dyn(0x63636B, 0xA4A4AC)
    static let ink3 = dyn(0x98989F, 0x6D6D76)
    static let line = dyn(0xE8E8EC, 0x323238)
    static let lineStrong = dyn(0xD9D9DF, 0x40404A)
    static let accent = dyn(0xE0952A, 0xEDA941)
    static let accentStrong = dyn(0xC67D14, 0xE0952A)
    static let accentSoft = dyn(0xFBEEDA, 0x38301F)
}

// тона рядов/секций
private let toneAmber = Color(hex: 0xE0952A)
private let toneTeal = Color(hex: 0x3AA6C9)
private let toneGreen = Color(hex: 0x2FA36B)
private let toneRed = Color(hex: 0xD84F4F)
private let toneIndigo = Color(hex: 0x5B63C4)

// оттенок конкретного персонажа (для аватара/выделения), иначе акцент
private let characterTints: [String: Color] = [
    "Clippy": Color(hex: 0xE0952A), "Merlin": Color(hex: 0x5B63C4),
    "Genie": Color(hex: 0x3AA6C9), "Bonzi": Color(hex: 0x9152C9),
    "Links": Color(hex: 0xE0702A), "Rover": Color(hex: 0xD84F4F),
]
private func charTint(_ name: String) -> Color { characterTints[name] ?? Color(hex: 0xE0952A) }

// MARK: - панель настроек

struct SettingsRootView: View {
    @ObservedObject var delegate: AppDelegate
    @ObservedObject private var settings = AppSettings.shared

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                header
                VStack(alignment: .leading, spacing: 0) {
                    eyebrow("Основное", toneAmber)
                    settingsGroup {
                        SwitchRow(icon: "power", tone: toneAmber, title: "Включён",
                                  subtitle: "Показывать факты по клику", isOn: $settings.enabled)
                        rowSep()
                        SwitchRow(icon: "speaker.wave.2.fill", tone: toneTeal, title: "Звук", subtitle: nil,
                                  isOn: Binding(get: { !settings.muted }, set: { settings.muted = !$0 }))
                        rowSep()
                        SwitchRow(icon: "arrow.right.circle.fill", tone: toneGreen,
                                  title: "Запускать при входе", subtitle: nil,
                                  isOn: Binding(get: { isLoginItemEnabled() }, set: { setLoginItem($0) }))
                    }

                    eyebrow("Персонаж", toneIndigo)
                    settingsGroup { personaSection }

                    eyebrow("Факты", toneTeal)
                    settingsGroup { factsSection }

                    eyebrow("Поведение", toneRed)
                    settingsGroup {
                        SwitchRow(icon: "trash.fill", tone: toneRed, title: "Кормление файлом в Корзину",
                                  subtitle: "Файл, брошенный на иконку, уходит в Корзину",
                                  isOn: $settings.trashOnFeed)
                            .onChange(of: settings.trashOnFeed) { _ in settings.feedTrashAsked = true }
                        rowSep()
                        SwitchRow(icon: "bolt.fill", tone: toneIndigo, title: "Пауза в энергосбережении",
                                  subtitle: "Замирать в режиме энергосбережения",
                                  isOn: $settings.pauseOnLowPower)
                            .onChange(of: settings.pauseOnLowPower) { _ in delegate.refreshIdle() }
                    }

                    footer
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 18)
            }
            .frame(maxWidth: .infinity)    // контент тянется на всю ширину окна (шапка, группы - тоже)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)   // тянемся за окном
        .background(P.ground)
        .scrollContentBackground(.hidden)
        .scrollIndicators(.hidden)                          // без полосы прокрутки
    }

    // шапка: аватар активного персонажа, имя, роль, быстрые действия
    private var header: some View {
        let name = settings.activeAgent
        return HStack(spacing: 16) {
            avatarView(for: name, size: 58, corner: 15)
            VStack(alignment: .leading, spacing: 1) {
                Text(name).font(.system(size: 19, weight: .bold, design: .rounded)).foregroundStyle(P.ink)
                Text("Активный персонаж").font(.system(size: 12.5)).foregroundStyle(P.ink2)
            }
            Spacer(minLength: 8)
            HStack(spacing: 8) {
                ghostButton("Показать факт") { delegate.showFact() }
                ghostButton("Жест") { delegate.playRandomGesture() }
                Button { delegate.showFAQ() } label: {
                    Image(systemName: "questionmark.circle.fill")
                        .font(.system(size: 21)).foregroundStyle(P.accentStrong)
                }
                .buttonStyle(.plain).help("Частые вопросы: настройка источников и персонажей")
            }
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            LinearGradient(colors: [P.accent.opacity(0.20), P.accent.opacity(0.04)],
                           startPoint: .topLeading, endPoint: .bottomTrailing))
        .overlay(alignment: .bottom) { rowSep() }
    }

    // персонаж: сетка со спрайтами + случайный при запуске + библиотека
    private var personaSection: some View {
        VStack(spacing: 0) {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 6), spacing: 10) {
                ForEach(delegate.availableAgents) { ref in
                    CharacterCard(name: ref.name, image: delegate.agentAvatars[ref.name],
                                  selected: settings.activeAgent == ref.name)
                        .onTapGesture {
                            guard settings.activeAgent != ref.name else { return }
                            settings.activeAgent = ref.name
                            delegate.applyAgentChange()
                        }
                }
            }
            .padding(.vertical, 12)
            rowSep()
            InlineRow(title: "Случайный персонаж при запуске", subtitle: nil) {
                Toggle("", isOn: $settings.randomAgentOnLaunch)
                    .labelsHidden().toggleStyle(.switch).tint(P.accent)
            }
            rowSep()
            InlineRow(title: "Библиотека персонажей", subtitle: "Своя папка с персонажами") {
                HStack(spacing: 8) {
                    ghostButton("Папка") { delegate.showAgentsFolder() }
                    ghostButton("Обновить") { delegate.reloadAgents() }
                }
            }
        }
    }

    // факты: источник + поля провайдера + чипы категорий (для локального источника)
    private var factsSection: some View {
        VStack(spacing: 0) {
            InlineRow(title: "Источник", subtitle: nil) {
                Picker("", selection: $settings.providerKind) {
                    ForEach(ProviderKind.allCases) { Text($0.title).tag($0) }
                }
                .labelsHidden().pickerStyle(.menu).fixedSize().tint(P.ink2)
            }
            providerFields
            if settings.providerKind == .local {
                rowSep()
                categoryChips
            }
        }
    }

    @ViewBuilder private var providerFields: some View {
        switch settings.providerKind {
        case .ollama:
            rowSep()
            labeledField("Адрес Ollama", text: $settings.ollamaURL, secure: false)
            labeledField("Модель Ollama", text: $settings.ollamaModel, secure: false)
            rowSep()
            llmSection(config: $settings.ollamaConfig)
        case .claude:
            rowSep()
            labeledField("Ключ Claude API", text: $settings.claudeKey, secure: true)
            rowSep()
            llmSection(config: $settings.claudeConfig)
        case .rss:
            rowSep()
            labeledField("Адрес RSS-ленты", text: $settings.rssURL, secure: false)
            if settings.rssURL.hasPrefix("http://") {
                Text("http не поддерживается (ATS): нужен адрес на https")
                    .font(.system(size: 12)).foregroundStyle(toneRed)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.bottom, 10)
            }
        case .facts:
            rowSep()
            Text("Историческое событие, случившееся в этот день, из русской Википедии. Ключ не нужен, только интернет. Нет сети - покажется локальный факт.")
                .font(.system(size: 12)).foregroundStyle(P.ink2)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 12)
        case .local:
            EmptyView()
        }
    }

    private var categoryChips: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("КАТЕГОРИИ").font(.system(size: 11, weight: .heavy)).tracking(0.7).foregroundStyle(P.ink3)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 118), spacing: 8)],
                      alignment: .leading, spacing: 8) {
                ForEach(AppSettings.tipCategories) { cat in
                    let on = settings.enabledCategories.contains(cat.key)
                    Text(cat.title)
                        .font(.system(size: 12.5, weight: .medium))
                        .foregroundStyle(on ? P.accentStrong : P.ink2)
                        .padding(.horizontal, 13).padding(.vertical, 6)
                        .frame(maxWidth: .infinity)
                        .background(on ? P.accentSoft : P.card)
                        .clipShape(Capsule())
                        .overlay(Capsule().strokeBorder(on ? P.accent.opacity(0.45) : P.lineStrong, lineWidth: 1))
                        .contentShape(Capsule())
                        .onTapGesture {
                            if on { settings.enabledCategories.remove(cat.key) }
                            else { settings.enabledCategories.insert(cat.key) }
                        }
                }
            }
        }
        .padding(.vertical, 12)
    }

    private var footer: some View {
        HStack {
            Text("Версия \(delegate.appVersion)").font(.system(size: 11.5)).foregroundStyle(P.ink3)
            Spacer()
            Button("Выход") { NSApplication.shared.terminate(nil) }
                .buttonStyle(.plain)
                .font(.system(size: 12.5, weight: .medium)).foregroundStyle(P.ink2)
        }
        .padding(.horizontal, 6).padding(.top, 4).padding(.bottom, 2)
    }

    // аватар персонажа на тонированной подложке
    private func avatarView(for name: String, size: CGFloat, corner: CGFloat) -> some View {
        let t = charTint(name)
        return RoundedRectangle(cornerRadius: corner, style: .continuous)
            .fill(RadialGradient(colors: [t.opacity(0.30), t.opacity(0.08)],
                                 center: UnitPoint(x: 0.5, y: 0.36),
                                 startRadius: 2, endRadius: size * 0.72))
            .frame(width: size, height: size)
            .overlay {
                if let img = delegate.agentAvatars[name] {
                    Image(nsImage: img).resizable().scaledToFit().padding(size * 0.13)
                }
            }
            .overlay(RoundedRectangle(cornerRadius: corner, style: .continuous)
                .strokeBorder(t.opacity(0.25), lineWidth: 1))
    }

    private func ghostButton(_ title: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title).font(.system(size: 12.5, weight: .medium)).foregroundStyle(P.ink2)
                .padding(.horizontal, 13).padding(.vertical, 6)
                .background(P.card.opacity(0.55))
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(P.lineStrong, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    private func labeledField(_ label: String, text: Binding<String>, secure: Bool) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label.uppercased()).font(.system(size: 11, weight: .semibold)).tracking(0.5).foregroundStyle(P.ink3)
            Group {
                if secure { SecureField("", text: text) } else { TextField("", text: text) }
            }
            .textFieldStyle(.plain).font(.system(size: 13)).foregroundStyle(P.ink)
            .padding(.horizontal, 12).padding(.vertical, 9)
            .background(P.card)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(P.lineStrong, lineWidth: 1))
        }
        .padding(.vertical, 10)
    }

    // многострочное поле промпта (растёт по содержимому)
    private func promptField(_ text: Binding<String>) -> some View {
        TextField("", text: text, axis: .vertical)
            .textFieldStyle(.plain).font(.system(size: 12.5)).foregroundStyle(P.ink).lineLimit(3...8)
            .padding(.horizontal, 12).padding(.vertical, 9)
            .background(P.card)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(P.lineStrong, lineWidth: 1))
            .padding(.bottom, 10)
    }

    // блок LLM-провайдера: режим пула, поля стиля, итоговый промпт, генерация пачкой
    @ViewBuilder private func llmSection(config: Binding<LLMConfig>) -> some View {
        InlineRow(title: "Брать из готового пула",
                  subtitle: config.wrappedValue.usePool
                    ? "По клику - мгновенно из пула, без прогрева и оплаты"
                    : "Живой запрос к модели на каждый клик") {
            Toggle("", isOn: config.usePool).labelsHidden().toggleStyle(.switch).tint(P.accent)
        }
        rowSep()
        VStack(spacing: 0) {
            labeledField("Персона (характер)", text: config.persona, secure: false)
            labeledField("Ограничения / темы", text: config.constraints, secure: false)
            InlineRow(title: "Макс. длина факта", subtitle: "\(config.wrappedValue.maxLen) символов") {
                Stepper("", value: config.maxLen, in: 60...500, step: 20).labelsHidden()
            }
            InlineRow(title: "Промпт", subtitle: "что уходит модели - соберите из полей и поправьте") {
                ghostButton("Собрать") {
                    config.wrappedValue.prompt = assembleStylePrompt(
                        persona: config.wrappedValue.persona,
                        constraints: config.wrappedValue.constraints,
                        maxLen: config.wrappedValue.maxLen)
                }
            }
            promptField(config.prompt)
        }
        rowSep()
        InlineRow(title: "Пул для «\(settings.activeAgent)»",
                  subtitle: "\(delegate.poolCount) фактов готово") {
            HStack(spacing: 8) {
                if delegate.isGeneratingPool {
                    ProgressView().controlSize(.small)
                } else {
                    ghostButton("Сгенерировать 30") { delegate.generatePool(count: 30) }
                    if delegate.poolCount > 0 { ghostButton("Очистить") { delegate.clearPool() } }
                }
            }
        }
    }
}

// тонкая линия-разделитель между рядами
private func rowSep() -> some View { Rectangle().fill(P.line).frame(height: 1) }

// иконка-чип 32x32 в тонированном квадрате
private func iconChip(_ name: String, _ tone: Color) -> some View {
    RoundedRectangle(cornerRadius: 9, style: .continuous)
        .fill(tone.opacity(0.15))
        .frame(width: 32, height: 32)
        .overlay(Image(systemName: name).font(.system(size: 15, weight: .medium)).foregroundStyle(tone))
}

// карточка-группа: белая подложка, скругление, тонкая рамка
@ViewBuilder private func settingsGroup<C: View>(@ViewBuilder _ content: () -> C) -> some View {
    VStack(spacing: 0) { content() }
        .padding(.horizontal, 16)
        .background(P.card)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(P.line, lineWidth: 1))
        .padding(.bottom, 16)
}

// eyebrow-заголовок секции: цветная точка + капс-текст
private func eyebrow(_ text: String, _ tone: Color) -> some View {
    HStack(spacing: 7) {
        Circle().fill(tone).frame(width: 6, height: 6)
        Text(text.uppercased()).font(.system(size: 11, weight: .heavy)).tracking(0.7).foregroundStyle(P.ink3)
    }
    .padding(.horizontal, 4).padding(.top, 16).padding(.bottom, 8)
    .frame(maxWidth: .infinity, alignment: .leading)
}

// MARK: - ряды

// ряд с иконкой, заголовком, необязательным описанием и тумблером
private struct SwitchRow: View {
    let icon: String
    let tone: Color
    let title: String
    let subtitle: String?
    @Binding var isOn: Bool

    var body: some View {
        HStack(spacing: 15) {
            iconChip(icon, tone)
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.system(size: 14)).foregroundStyle(P.ink)
                    .fixedSize(horizontal: false, vertical: true)
                if let subtitle {
                    Text(subtitle).font(.system(size: 12)).foregroundStyle(P.ink2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 8)
            Toggle("", isOn: $isOn).labelsHidden().toggleStyle(.switch).tint(P.accent)
        }
        .padding(.vertical, 12)
    }
}

// ряд без иконки: заголовок/описание + произвольный контрол справа
private struct InlineRow<Trailing: View>: View {
    let title: String
    let subtitle: String?
    @ViewBuilder let trailing: () -> Trailing

    var body: some View {
        HStack(spacing: 15) {
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.system(size: 14)).foregroundStyle(P.ink)
                    .fixedSize(horizontal: false, vertical: true)
                if let subtitle {
                    Text(subtitle).font(.system(size: 12)).foregroundStyle(P.ink2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 8)
            trailing()
        }
        .padding(.vertical, 12)
    }
}

// карточка персонажа: аватар-спрайт + имя, выделяется оттенком при выборе
private struct CharacterCard: View {
    let name: String
    let image: NSImage?
    let selected: Bool

    var body: some View {
        let t = charTint(name)
        return VStack(spacing: 7) {
            RoundedRectangle(cornerRadius: 13, style: .continuous)
                .fill(RadialGradient(colors: [t.opacity(0.30), t.opacity(0.09)],
                                     center: UnitPoint(x: 0.5, y: 0.36), startRadius: 2, endRadius: 34))
                .aspectRatio(1, contentMode: .fit)
                .overlay {
                    if let image {
                        Image(nsImage: image).resizable().scaledToFit().padding(6)
                    }
                }
            Text(name).font(.system(size: 12, weight: selected ? .semibold : .medium))
                .foregroundStyle(selected ? t : P.ink).lineLimit(1)
        }
        .padding(.horizontal, 6).padding(.top, 10).padding(.bottom, 8)
        .background(selected ? t.opacity(0.12) : P.sunken)
        .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 11, style: .continuous)
            .strokeBorder(selected ? t : P.line, lineWidth: 1.5))
        .contentShape(Rectangle())
    }
}

// MARK: - FAQ (частые вопросы: настройка источников и своего персонажа)
// отдельное окно в стиле панели настроек. текст ответов - markdown (`код`, **жирный**)

struct FAQView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                header
                VStack(alignment: .leading, spacing: 0) {
                    eyebrow("С чего начать", toneAmber)
                    settingsGroup {
                        FAQItem(icon: "cursorarrow.click", tone: toneAmber,
                                q: "Как это вообще работает?",
                                a: "Клик по иконке в доке показывает один факт в облачке. Откуда берётся факт - задаёт «Факты → Источник» в настройках. Если персонаж выключен тумблером «Включён», облачко не появляется.")
                        rowSep()
                        FAQItem(icon: "arrow.triangle.2.circlepath", tone: toneGreen,
                                q: "Сменил источник, а факты как будто прежние?",
                                a: "Если выбранный источник не ответил (нет интернета, не задан ключ или адрес), Clippy молча берёт локальный факт - чтобы облачко не было пустым. Ниже расписаны условия каждого источника.")
                    }

                    eyebrow("Источники фактов", toneTeal)
                    settingsGroup {
                        FAQItem(icon: "shippingbox.fill", tone: toneAmber,
                                q: "Локальные советы",
                                a: "Работают сразу, настраивать ничего не нужно: ~500 реплик Clippy. Чипами «Категории» можно оставить только интересные темы. Если снять все категории - Clippy честно скажет об этом в облачке.")
                        rowSep()
                        FAQItem(icon: "calendar", tone: toneTeal,
                                q: "«В этот день» (Википедия)",
                                a: "Историческое событие, случившееся в этот день, из русской Википедии - на русском, ключ не нужен, только интернет. Нет сети - покажется локальный факт.")
                        rowSep()
                        FAQItem(icon: "desktopcomputer", tone: toneGreen,
                                q: "Ollama (локально)",
                                a: "Своя нейросеть прямо на вашем компьютере - приватно и бесплатно. Нужно: 1) установить Ollama с ollama.com; 2) один раз скачать модель командой `ollama pull llama3.2`; 3) чтобы в фоне работал `ollama serve`. Адрес `http://localhost:11434/api/generate` и модель `llama3.2` уже подставлены в настройках - при желании поменяйте. Каждый клик генерирует новый факт (пара секунд).")
                        rowSep()
                        FAQItem(icon: "sparkles", tone: toneIndigo,
                                q: "Claude API",
                                a: "Факты сочиняет Claude - это платный сервис Anthropic. Нужен ключ с console.anthropic.com: вставьте его в поле «Ключ Claude API» (хранится в Связке ключей, не открытым текстом). Каждый клик - один запрос (доли цента). Если ключ неверный, Clippy тихо покажет локальный факт - проверьте ключ.")
                        rowSep()
                        FAQItem(icon: "dot.radiowaves.up.forward", tone: toneRed,
                                q: "RSS-лента",
                                a: "Показывает заголовок свежей новости из любой ленты. Вставьте адрес ленты в поле - он должен начинаться с **https** (http заблокирован ради безопасности). Подойдёт любой обычный RSS.")
                    }

                    eyebrow("Свой персонаж", toneIndigo)
                    settingsGroup {
                        FAQItem(icon: "folder.fill", tone: toneIndigo,
                                q: "Как добавить своего персонажа?",
                                a: "«Персонаж → Библиотека → Папка» откроет папку `Agents`. Положите туда подпапку персонажа с файлами `agent.json` и `map.png` (формат ClippyJS / Microsoft Agent) и нажмите «Обновить» - персонаж появится в сетке.")
                        rowSep()
                        FAQItem(icon: "arrow.down.doc.fill", tone: toneTeal,
                                q: "Взять готового из ClippyJS",
                                a: "В комплекте есть импортёр: `python3 scripts/import-clippyjs.py <папка-персонажа> [Имя]`. Он соберёт `map.png` и `agent.json` в нужном виде.")
                        rowSep()
                        FAQItem(icon: "text.bubble.fill", tone: toneAmber,
                                q: "Почему свой персонаж молчит?",
                                a: "У каждого персонажа свои факты. Чтобы он их показывал, положите ему в папку файл `tips.json` - это либо простой список строк, либо словарь по категориям. Без этого файла персонаж ничего не говорит.")
                    }

                    eyebrow("Если ничего не появляется", toneRed)
                    settingsGroup {
                        FAQItem(icon: "checklist", tone: toneRed,
                                q: "Проверьте по порядку",
                                a: "1) включён ли тумблер «Включён»; 2) для Claude вставлен ли ключ, для RSS - адрес; 3) есть ли у своего персонажа `tips.json`; 4) не сняты ли у Clippy все категории. Если выбранный источник недоступен, но у персонажа есть локальные факты - покажется факт из них.")
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 18)
            }
            .frame(maxWidth: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(P.ground)
        .scrollContentBackground(.hidden)
        .scrollIndicators(.hidden)                          // без полосы прокрутки
    }

    private var header: some View {
        HStack(spacing: 14) {
            iconChip("questionmark", toneIndigo)
            VStack(alignment: .leading, spacing: 1) {
                Text("Частые вопросы").font(.system(size: 19, weight: .bold, design: .rounded)).foregroundStyle(P.ink)
                Text("Настройка источников и персонажей").font(.system(size: 12.5)).foregroundStyle(P.ink2)
            }
            Spacer(minLength: 8)
        }
        .padding(.horizontal, 22).padding(.vertical, 18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            LinearGradient(colors: [toneIndigo.opacity(0.18), toneIndigo.opacity(0.03)],
                           startPoint: .topLeading, endPoint: .bottomTrailing))
        .overlay(alignment: .bottom) { rowSep() }
    }
}

// один вопрос-ответ: иконка-чип + жирный вопрос + markdown-ответ
private struct FAQItem: View {
    let icon: String
    let tone: Color
    let q: String
    let a: String

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            iconChip(icon, tone)
            VStack(alignment: .leading, spacing: 4) {
                Text(q).font(.system(size: 14, weight: .semibold)).foregroundStyle(P.ink)
                    .fixedSize(horizontal: false, vertical: true)
                Text(.init(a)).font(.system(size: 12.5)).foregroundStyle(P.ink2)
                    .fixedSize(horizontal: false, vertical: true).lineSpacing(2)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 13)
    }
}
