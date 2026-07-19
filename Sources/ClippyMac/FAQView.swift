import SwiftUI

// окно «Частые вопросы»: гайды по настройке источников и своего персонажа.
// отдельное окно в стиле панели настроек (палитра P и атомы - в SettingsView.swift).
// текст ответов - markdown (`код`, **жирный**)

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
                        rowSep()
                        FAQItem(icon: "hand.point.up.left.fill", tone: toneTeal,
                                q: "Почему Clippy в меню «Открыть в программе»?",
                                a: "Чтобы персонажа можно было кормить, приложение объявляет системе, что принимает любые файлы. Побочный эффект: macOS показывает Clippy Mac в «Открыть в программе» у всех файлов. Выбор этого пункта равен перетаскиванию на иконку: файл будет «съеден» (и отправлен в Корзину, если включён такой режим).")
                    }

                    eyebrow("Источники фактов", toneTeal)
                    settingsGroup {
                        FAQItem(icon: "shippingbox.fill", tone: toneAmber,
                                q: "Локальные советы",
                                a: "Работают сразу, настраивать ничего не нужно: ~700 реплик Clippy. Чипами «Категории» можно оставить только интересные темы. Если снять все категории - Clippy честно скажет об этом в облачке.")
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
                                a: "1) включён ли тумблер «Включён»; 2) для Claude вставлен ли ключ, для RSS - адрес; 3) есть ли у своего персонажа `tips.json`; 4) не сняты ли все категории. Если выбранный источник недоступен, но у персонажа есть локальные факты - покажется факт из них.")
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
        .headerChrome(toneIndigo)
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
