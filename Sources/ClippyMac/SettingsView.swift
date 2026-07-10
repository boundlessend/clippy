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
            .frame(width: settingsWidth)
        }
        .frame(width: settingsWidth, height: settingsHeight)
        .background(P.ground)
        .scrollContentBackground(.hidden)
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
        case .claude:
            rowSep()
            labeledField("Ключ Claude API", text: $settings.claudeKey, secure: true)
        case .rss:
            rowSep()
            labeledField("Адрес RSS-ленты", text: $settings.rssURL, secure: false)
            if settings.rssURL.hasPrefix("http://") {
                Text("http не поддерживается (ATS): нужен адрес на https")
                    .font(.system(size: 12)).foregroundStyle(toneRed)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.bottom, 10)
            }
        case .local, .facts:
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

    // карточка-группа: белая подложка, скругление, тонкая рамка
    @ViewBuilder private func settingsGroup<C: View>(@ViewBuilder _ content: () -> C) -> some View {
        VStack(spacing: 0) { content() }
            .padding(.horizontal, 16)
            .background(P.card)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(P.line, lineWidth: 1))
            .padding(.bottom, 16)
    }

    private func eyebrow(_ text: String, _ tone: Color) -> some View {
        HStack(spacing: 7) {
            Circle().fill(tone).frame(width: 6, height: 6)
            Text(text.uppercased()).font(.system(size: 11, weight: .heavy)).tracking(0.7).foregroundStyle(P.ink3)
        }
        .padding(.horizontal, 4).padding(.top, 16).padding(.bottom, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
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
                if let subtitle {
                    Text(subtitle).font(.system(size: 12)).foregroundStyle(P.ink2)
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
                if let subtitle {
                    Text(subtitle).font(.system(size: 12)).foregroundStyle(P.ink2)
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
