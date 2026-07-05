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
MenuBarExtra (иконка в трее, меню управления)
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

**1. Тип приложения.** agent-приложение: `LSUIElement = YES` в Info.plist (нет
иконки в доке). Трей через `MenuBarExtra` (SwiftUI, macOS 13+). Само окно
скрепыша создаётся вручную через `NSApplicationDelegate`, потому что SwiftUI
`WindowGroup` не даёт прозрачное borderless окно.

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

**7. Настройки (`Settings`).** обёртка над `UserDefaults`: частотность показа,
вкл/выкл, выбранный провайдер, показывать ли при простое, позиция окна, длина
показа баллона. Управление из меню трея.
- **частотность (обязательно с первого дня в UI):** пресеты в меню трея -
  каждые 5 / 10 / 15 / 30 / 60 мин + пункт "свой интервал" (произвольное число
  минут). Хранится как `intervalMinutes: Int` в `UserDefaults`, применяется на
  лету (перезапуск `Scheduler`)

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

```
clippy-mac/
  PLAN.md
  README.md
  ClippyMac.xcodeproj              # macOS App target, LSUIElement=YES
  Sources/
    ClippyMacApp.swift             # @main App + MenuBarExtra + AppDelegate
    ClippyPanel.swift              # конфиг NSPanel
    ClippyView.swift               # композиция скрепыш + баллон
    SpriteAnimator.swift           # плеер кадров
    ClippyAgent.swift              # модели + парсинг clippy_agent.json
    SpeechBubbleView.swift         # SwiftUI баллон
    ActivityMonitor.swift          # lock/sleep/screensaver/idle
    Scheduler.swift                # таймер + джиттер
    Settings.swift                 # UserDefaults
    TipProvider.swift              # protocol + LocalJSONProvider
    Providers/
      OllamaProvider.swift
      ClaudeProvider.swift
      RSSProvider.swift
      FactsAPIProvider.swift
  Resources/
    clippy_map.png                 # спрайтшит из ClippyJS
    clippy_agent.json              # тайминги кадров (конверт из agent.js)
    tips.json                      # стартовые факты/советы
```

каркас проще всего создать как macOS App в Xcode (File > New > Project). Как
альтернатива из кода - XcodeGen/Tuist по `project.yml`.

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
- отдельное окно настроек с UI (сейчас всё в меню трея; там же ввод «своего
  интервала» и ключа/эндпоинта провайдеров)
- цепочка фолбэков между провайдерами контента
- релизная подпись Developer ID + нотаризация (раздача без Gatekeeper-предупреждений)
- наполнение `tips.json`

## следующий шаг

MVP (P0-P5) и оживление (P6) готовы. проект подготовлен к публикации: CI-workflow,
сборка `.dmg` (`scripts/build-dmg.sh`), лицензия, бейджики. дальнейшее - в бэклоге.
