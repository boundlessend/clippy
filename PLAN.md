# Скрепыш для macOS (clippy-mac)

возрождение легендарного Clippy/Clippit: раз в ~10 минут при активном экране
скрепыш выныривает в углу, проигрывает анимацию и показывает в речевом баллоне
случайный факт или совет.

## зафиксированные решения

| вопрос | выбор | следствие |
|--------|-------|-----------|
| стек | нативно Swift/SwiftUI | ноль зависимостей, menu bar agent + borderless NSPanel, .app ~1-2 МБ |
| распространение | только для себя | без подписи и нотаризации, сборка/запуск локально |
| анимация | оригинальные спрайты Clippy | переиспользуем спрайтшит и тайминги из ClippyJS, не рисуем с нуля |
| контент | локальный JSON на старте, провайдер pluggable | один протокол, за ним local / Ollama / Claude / RSS / facts-API |

## архитектура

функциональное ядро, OOP только для коннекторов к внешним системам (AppKit-окно,
провайдеры контента) - как того требует стиль проекта.

```
NSStatusItem (скрепыш в трее) + AppDelegate (чистый AppKit, точка входа в main.swift)
   ├─ NSMenu: Показать сейчас / Проиграть жест / Настройки… / О программе / Выход
   ├─ Настройки… -> NSWindow(NSHostingController(SettingsRootView: SwiftUI Form)
   ├─ О программе -> orderFrontStandardAboutPanel (версия из Info.plist)
   └─ активити-полиси: .regular (иконка в доке) / .accessory (только трей)
      │
   Scheduler (Timer 10 мин + джиттер)
      │  спрашивает ActivityMonitor: экран активен?
      ▼
   ActivityMonitor  ──> lock/unlock, sleep/wake, screensaver, idle
      │  да -> показать
      ▼
   ClippyPanel (NSPanel: borderless, прозрачный, поверх всех, не ворует фокус)
      └─ NSHostingView(ClippyView)
             ├─ SpriteAnimator  ──> проигрывает кадры из спрайтшита
             └─ SpeechBubbleView ──> текст от TipProvider
                                          │
                                    TipProvider (protocol)
                                    ├─ LocalJSONProvider   (старт)
                                    ├─ OllamaProvider       (localhost:11434)
                                    ├─ ClaudeProvider       (Anthropic API)
                                    ├─ RSSProvider
                                    └─ FactsAPIProvider
```

### ключевые технические узлы

**1. Тип приложения.** точка входа - чистый AppKit (`main.swift`:
`NSApplication` + `AppDelegate`), НЕ SwiftUI `App`. Причина: SwiftUI
`MenuBarExtra` на практике не реагировал на клики (в accessibility - 0 меню-баров)
и мешал reopen из дока. Трей - нативный `NSStatusItem` с `NSMenu` (раскрывается
всегда, виден в AX). Видимость в доке/трее - `setActivationPolicy(.regular /
.accessory)` + добавление/снятие `NSStatusItem`; `LSUIElement = YES` в Info.plist,
чтобы на старте не мигала иконка дока. SwiftUI остаётся только для контента окон
(`SettingsRootView`, баллон) через `NSHostingController`/`NSHostingView`.

**2. Окно скрепыша - `NSPanel`.**
- стиль `[.borderless, .nonactivatingPanel]`, `isFloatingPanel = true`
- `backgroundColor = .clear`, `isOpaque = false`, `hasShadow = false`
- `level = .floating` (поверх обычных окон)
- `collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]`
  - появляется на всех Spaces и поверх фуллскрин-приложений
- показ через `orderFrontRegardless()` (не `makeKey...`) - не крадёт фокус
- позиция: правый нижний угол `screen.visibleFrame`; перетаскивание мышью
  запоминается в настройках

**3. Спрайт-плеер (`SpriteAnimator` + `ClippyAgent`).**
- формат ClippyJS: `map.png` (спрайтшит) + `agent.js` с описанием `framesize`,
  сетки и `animations = { имя: { frames: [{ duration, images:[[x,y]], exitBranch,
  branching }] } }`
- `ClippyAgent` парсит эти данные (конвертируем `agent.js` в `clippy_agent.json`
  один раз на этапе подготовки ассетов)
- `SpriteAnimator` по имени анимации крутит кадры: держит `duration` мс каждый,
  режет подкартинку из спрайтшита (`CGImage.cropping(to:)`) в слой `CALayer`
- сценарий показа: `Show/Appear` -> лёгкая idle-петля пока висит баллон -> `Hide`
- нужные анимации: Appear, Idle*, Wave, GetAttention, Congratulate, Hide
- **упрощение на старте:** линейное проигрывание кадров, `branching`
  (вероятностные переходы) игнорируем, поддерживаем только `exitBranch` для
  выхода из idle. `// ponytail: линейный плеер, branching добавить если idle
  выглядит мёртвым`

**4. Речевой баллон (`SpeechBubbleView`).** чистый SwiftUI: скруглённый
прямоугольник + хвостик через `Path`, авто-размер под текст, без ассетов.
Висит N секунд или до клика, затем скрепыш прячется.

**5. Детект "активного экрана" (`ActivityMonitor`).** не показывать, когда юзера
нет:
- lock/unlock: `DistributedNotificationCenter` -> `com.apple.screenIsLocked` /
  `com.apple.screenIsUnlocked`
- сон/пробуждение дисплея: `NSWorkspace.screensDidSleepNotification` /
  `screensDidWakeNotification`
- скринсейвер: distributed `com.apple.screensaver.didstart` / `.didstop`
- простой: `CGEventSource.secondsSinceLastEventType` (any input) - опционально
  не показывать, если юзер отошёл дольше порога
- правило показа: экран разблокирован И дисплей не спит И (опц.) idle < порога

**6. Планировщик (`Scheduler`).** `Timer` на 600 с + случайный джиттер
(±60 с), чтобы не ровно по часам. При заблокированном/спящем экране показ
пропускаем (следующий тик). Первый показ - с небольшой задержкой после старта.

**7. Настройки (`AppSettings`).** обёртка над `UserDefaults`: частотность показа,
вкл/выкл, провайдер, масштаб, звук, показ при простое, позиция окна, snooze,
`showInMenuBar` / `showInDock`. Управление - в окне настроек
(`SettingsRootView`: SwiftUI `Form` в `NSWindow`), открывается из меню трея
(«Настройки…»), из меню приложения / Cmd+, (режим дока) и при повторном запуске,
если скрыты обе поверхности.
- **частотность:** пресеты 5 / 10 / 15 / 30 / 60 мин, хранится как
  `intervalMinutes: Int`, применяется на лету (перезапуск `Scheduler`)
- **где показывать:** `showInMenuBar` / `showInDock` (по умолчанию обе). Скрыть
  можно каждую; если скрыты обе - окно настроек открывается при запуске уже
  запущенного приложения (reopen) и на старте
- **версия:** `CFBundleShortVersionString` из Info.plist (правится через `VERSION`
  в `build-dmg.sh`), показывается в панели «О программе»

**8. Автозапуск.** `SMAppService.mainApp.register()` (macOS 13+).
- **риск:** для незаверенного приложения регистрация капризна; если не заведётся -
  фолбэк на `LaunchAgent` plist в `~/Library/LaunchAgents`

**9. Провайдеры контента (`TipProvider`).**
```swift
protocol TipProvider { func nextTip() async throws -> String }
```
- `LocalJSONProvider`: `tips.json` из бандла, случайный выбор. Оффлайн, без ключей
- `OllamaProvider`: POST `http://localhost:11434/api/generate`, `stream=false`
- `ClaudeProvider`: Anthropic Messages API (при реализации свериться со скиллом
  claude-api за актуальной моделью и эндпоинтом; ключ - из Keychain, не в коде)
- `RSSProvider` / `FactsAPIProvider`: GET публичного фида, парсинг
- внешние вызовы: retries с warning-логами, затем raise последней ошибки (правило
  проекта). Провайдер выбирается в настройках; цепочку-фолбэк между провайдерами
  НЕ делаем по умолчанию (добавить, если попросишь)

## структура проекта

SPM executable (`Package.swift`, swift-tools 5.9, macOS 13+), без xcodeproj.
Ресурсы через `.process("Resources")`. Сборка: `swift run` (dev),
`scripts/build-dmg.sh` (.app + .dmg).

```
clippy-mac/
  Package.swift                    # SPM executable, resources: .process("Resources")
  PLAN.md  README.md  LICENSE
  scripts/build-dmg.sh             # release -> .app (Info.plist, иконка) -> ad-hoc -> .dmg
  .github/workflows/ci.yml         # swift build + CLIPPY_SELFTEST=1 + release
  assets/AppIcon.png .icns         # иконка приложения
  Sources/ClippyMac/
    main.swift                     # точка входа: self-check, затем NSApplication+AppDelegate
    ClippyMacApp.swift             # AppDelegate + NSStatusItem/меню/About + ClippyControls/SettingsRootView
    ClippyPanel.swift              # конфиг NSPanel (overlay)
    ClippyImageView.swift          # NSImageView: клик/перетаскивание/контекстное меню
    SpriteAnimator.swift           # плеер кадров + branching + звук
    ClippyAgent.swift              # модели + парсинг clippy_agent.json + кроп кадра
    SpeechBubbleView.swift         # SwiftUI баллон
    ActivityMonitor.swift          # lock/sleep/screensaver/idle
    Scheduler.swift                # таймер + джиттер
    Settings.swift                 # AppSettings над UserDefaults
    TipProvider.swift              # protocol + LocalJSONProvider
    NetworkProviders.swift         # Ollama / Claude / RSS / FactsAPI
    LoginItem.swift                # автозапуск (SMAppService/LaunchAgent)
    SelfCheck.swift                # CLIPPY_SELFTEST=1: проверка ассетов без GUI
    Resources/
      clippy_map.png               # спрайтшит из ClippyJS
      clippy_agent.json            # тайминги кадров (конверт из agent.js)
      menubar.png                  # скрепыш для иконки в трее (фон убран)
      tips.json                    # локальные факты/советы
      sounds/1.mp3 … 15.mp3        # озвучка анимаций
```

## этапы и декомпозиция (MVP -> расширения)

**правило:** каждый этап декомпозируется ЗАРАНЕЕ, до начала работы над ним.
Подзадачи ниже - предварительные; перед стартом этапа они уточняются под текущее
состояние кода, но этап не начинается без готового списка подзадач. Каждый этап
оставляет одну проверяемую вещь и коммитится волной (см. git-стратегию).

### P0 каркас
- P0.1 создать macOS App target (Xcode или `project.yml`), `LSUIElement=YES`,
  bundle id, минимальная цель macOS 13
- P0.2 `MenuBarExtra` с иконкой в трее и меню-заглушкой ("Показать сейчас",
  "Выход")
- P0.3 `AppDelegate` + фабрика `ClippyPanel` (borderless, прозрачный, floating,
  `collectionBehavior`, не воюет за фокус)
- P0.4 "Показать сейчас" выводит пустую панель в правый нижний угол через
  `orderFrontRegardless`
- **verify:** иконка в трее есть; панель поверх всех окон; фокус активного
  приложения НЕ теряется

### P1 спрайт-плеер
- P1.1 ассеты: взять ClippyJS Clippy (`map.png` + `agent.js`), сконвертировать
  `agent.js` -> `clippy_agent.json`, положить в `Resources`
- P1.2 модели `ClippyAgent` (Animation, Frame, framesize, сетка) + JSON-декодер
- P1.3 `SpriteAnimator`: режет кадр из спрайтшита (`CGImage.cropping`), держит
  `duration`, крутит петлю
- P1.4 `ClippyView` показывает аниматор; сценарий Appear -> Idle
- **verify:** анимация играет по таймингам, кадры не съезжают

### P2 баллон + локальный контент
- P2.1 `SpeechBubbleView` (SwiftUI, хвостик через `Path`, авто-размер)
- P2.2 `tips.json` + `LocalJSONProvider` (protocol `TipProvider`, random)
- P2.3 связка: показать -> `nextTip()` -> баллон над скрепышем -> авто-скрытие
  через N сек -> Hide
- **verify:** текст читаем; баллон и скрепыш исчезают сами

### P3 планировщик + активность
- P3.1 `ActivityMonitor`: подписки на lock/unlock, sleep/wake, screensaver +
  функция `isScreenActive`
- P3.2 (опц.) idle через `CGEventSource.secondsSinceLastEventType` + порог
- P3.3 `Scheduler`: `Timer` по интервалу + джиттер; тик спрашивает
  `isScreenActive`, пропуск если экран неактивен
- P3.4 первый показ с задержкой после старта
- **verify:** на залоченном экране НЕ появляется; появляется после интервала

### P4 настройки + частотность + автозапуск
- P4.1 `Settings` над `UserDefaults` (частотность, вкл-выкл, длина баллона,
  позиция, провайдер)
- P4.2 меню трея: выбор частотности (пресеты 5/10/15/30/60 мин + свой), вкл-выкл,
  "Показать сейчас"
- P4.3 смена частотности применяется на лету (перезапуск `Scheduler`)
- P4.4 автозапуск через `SMAppService` (+ `LaunchAgent` фолбэк)
- **verify:** смена частотности меняет реальный интервал; автозапуск
  регистрируется

### P5 pluggable провайдеры
- P5.1 `OllamaProvider` (localhost:11434, `stream=false`, retries+raise)
- P5.2 `ClaudeProvider` (Messages API, ключ из Keychain; свериться со скиллом
  claude-api)
- P5.3 `RSSProvider` / `FactsAPIProvider`
- P5.4 выбор провайдера в меню трея; настройки эндпоинта/ключа
- **verify:** переключение источника; реальный вызов локального Ollama возвращает
  совет

## риски и подводные камни

- прозрачный borderless NSPanel в SwiftUI требует ручной настройки окна через
  AppDelegate (WindowGroup не подходит)
- поверх фуллскрин-приложений - только через `fullScreenAuxiliary` в
  collectionBehavior
- парсинг ClippyJS `agent.js`: `branching` сложнее линейного проигрывания;
  на старте упрощаем
- `SMAppService` для незаверенного .app может капризничать - держим LaunchAgent
  как запасной вариант
- App Nap может тормозить таймеры agent-приложения; при неточности - `ProcessInfo
  .beginActivity`
- idle-детект: важно взять правильный тип события (any input), иначе ложные
  срабатывания
- **лицензия ассетов:** спрайты Clippy - это Microsoft Agent (код ClippyJS под
  MIT, но сами картинки - IP Microsoft). Для личного использования ок; для
  раздачи другим - серая зона (но мы и выбрали "только для себя")

## git-стратегия

- проект подготовлен к публикации (CI, DMG, лицензия); публикация - по решению
  владельца, remote пока не задан
- коммитим **волнами**: одна логическая порция = один коммит (обычно = один этап
  или подзадача с проверяемым результатом)
- сообщения коммитов - **на английском, с маленькой буквы**, повелительное
  наклонение (`add scheduler with jitter`, `fix panel focus stealing`)
- ветка по умолчанию `main`

## P6: оживление скрепыша (идеи из Cosmo/Clippy)

декомпозиция заранее; каждая подфаза коммитится волной.

### P6.1 branching-анимации + живой idle (фича 1)
- `SpriteAnimator` учитывает `branching` (вероятностный прыжок по weight) вместо
  всегда +1; данные уже в `clippy_agent.json`
- idle: вместо фикс. `IdleSideToSide` - случайная из `Idle*`/`RestPose`, с лимитом
  шагов чтобы self-loop не залипал
- verify: self-check выбора ветки (индекс в границах, сумма weight)

### P6.2 масштаб + позиция (фичи 5, 4)
- `AppSettings.scale` (пресеты 0.5/0.75/1/1.5/2), панель/картинка масштабируются
- перетаскивание мышью + сохранение позиции в `UserDefaults`, восстановление
  при показе (иначе правый нижний угол)
- меню: подменю «Размер»

### P6.3 ручной триггер + контекстное меню + snooze (фичи 2, 6)
- левый клик по скрепышу -> случайный жест (Wave/Congratulate/...)
- правый клик -> меню: следующий совет / жест / спрятать / заткнуть на час
- `AppSettings.snoozeUntil`, `isAllowed` учитывает паузу
- пункт «Проиграть жест» в трее

### P6.4 звук + mute (фича 7)
- звуки из ClippyJS (`sounds-mp3.js`) декодированы в `Resources/sounds/*.mp3`
- `Frame.sound` -> проигрывание через `AVAudioPlayer`, если не muted
- `AppSettings.muted` + тумблер в меню (дефолт: звук выключен)
- verify: self-check загрузки звуковых файлов

## бэклог

идеи из Cosmo/Clippy:
- **9** кастомные агенты из папки `.agent` + «Show in Finder» + «Reload»
- **10** конвертер `.acs` (любой Microsoft Agent персонаж), по мотивам `agent-convert.sh`
- **11** MoveTo / GestureAt - скрепыш ходит по экрану и жестикулирует в точку
- другие персонажи (Merlin, Links) - частично закрывается пунктом 9

прочее отложенное:
- ~~наполнить `tips.json`~~ сделано: 598 реплик в стиле «Скрепыш с характером»
  (персона/самоирония, ретро-техника 90-х, история вычислений, интернет-факты,
  наука/природа, советы по macOS и микро-забота). Коротко (<=98 символов, чтобы
  баллон был маленьким), без упоминаний интервала показа и изменяемых настроек
  (иначе фраза устареет при смене частоты). Генерились 6 агентами по темам,
  затем склейка/дедуп/чистка длинного тире и HTML-сущностей
- релизная подпись Developer ID + нотаризация (раздача без Gatekeeper-предупреждений)
- **решение по ассетам Microsoft перед публичной публикацией**: оставить в репо
  с дисклеймером или скачивать скриптом при сборке (сейчас лежат в репо, для
  личного использования)

сделано после MVP: окно настроек (AppKit `NSWindow` + SwiftUI `Form`), нативное
меню трея на `NSStatusItem`, панель «О программе» с версией, видимость
дока/трея, версионирование `1.0.0`; свой интервал (степпер, минуты); поля
провайдеров в окне настроек (Ollama URL/модель, RSS, ключ Claude - в Keychain);
фолбэк-цепочка провайдеров (выбранный -> локальный); категории локальных фактов
(6 тем, тумблеры, фильтр в `LocalJSONProvider`, `tips.json` по категориям);
двуязычный README (`README.md` EN + `README.ru.md` RU) по образцу других репо.

## иконка

- поза скрепыша: кадр `GetAttention` из спрайтшита (крупные глаза, наклон)
- фон: линованный блокнот (кремовый лист), выбран из ретро-вариантов (были также
  XP Bliss, облака 98, XP Luna, окно Office, Win95 teal)
- сглаживание спрайта: AI super-resolution LapSRN ×8 (opencv-contrib `dnn_superres`)
  + inpaint фона + супер-сэмплинг вниз - убирает пикселизацию
- собрано в `assets/AppIcon.png` (1024) и `assets/AppIcon.icns` (все размеры);
  подключена в `build-dmg.sh` (`CFBundleIconFile`) и в шапку README
- генерация иконки была разовой (в scratchpad); при переделке - opencv-contrib
  + PIL, iconset -> `iconutil -c icns`

## следующий шаг

MVP (P0-P5), оживление (P6), публикация, иконка, UI (меню/окно настроек/About/
версия), 598 локальных фактов по категориям, свой интервал, поля провайдеров +
фолбэк, двуязычный README - готовы. Осталось из бэклога: P6 пункты 9/10/11
(кастомные `.agent`, конвертер `.acs`, ходьба по экрану), подпись Developer ID +
нотаризация, решение по ассетам Microsoft перед публичной публикацией.
