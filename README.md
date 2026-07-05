<p align="center">
  <img src="assets/AppIcon.png" width="128" alt="clippy-mac">
</p>

# clippy-mac

[![CI](https://github.com/boundlessend/clippy-mac/actions/workflows/ci.yml/badge.svg)](https://github.com/boundlessend/clippy-mac/actions/workflows/ci.yml)
![Platform](https://img.shields.io/badge/platform-macOS%2013%2B-blue)
![Swift](https://img.shields.io/badge/Swift-6-orange)
![License](https://img.shields.io/badge/license-MIT-green)

возрождение легендарного скрепыша (Clippy/Clippit) на macOS. раз в настраиваемый
интервал при активном экране скрепыш выныривает в углу, проигрывает анимацию и
показывает в речевом баллоне факт или совет.

- нативно Swift/SwiftUI, menu bar agent, ноль зависимостей
- оригинальные спрайты и звуки Clippy (из ClippyJS)
- частотность показа настраивается (пресеты + свой интервал)
- живой idle (branching-анимации), жесты по клику, перетаскивание
- контент за протоколом: локальный JSON, Ollama, Claude, RSS, facts-API

## возможности

- **menu bar agent** - без иконки в доке, всё управление из трея (📎)
- **скрепыш** - прозрачное окно поверх всех окон и Spaces, не ворует фокус
- **живой idle** - вероятностные переходы кадров, случайные idle-жесты
- **взаимодействие** - левый клик = жест, правый клик = меню, перетаскивание
  мышью с запоминанием позиции
- **частота** - 5/10/15/30/60 мин, применяется на лету
- **детект активности** - не показывается на залоченном/спящем экране и при
  простое пользователя
- **размер** - масштаб скрепыша ×0.5…×2
- **звук** - оригинальная озвучка анимаций (по умолчанию выключена)
- **snooze** - «заткнуть на час» из контекстного меню
- **автозапуск** - при входе в систему (LaunchAgent)
- **источники контента** - переключаются в меню (см. ниже)

## установка

### из готового .dmg

собери образ и перетащи `ClippyMac.app` в «Программы»:

```
./scripts/build-dmg.sh
open build/ClippyMac.dmg
```

при первом запуске незаверенного приложения: правый клик по `.app` → «Открыть».

### из исходников

```
swift run
```

требуется macOS 13+ и Xcode / Swift toolchain.

## настройка источников контента

- **Локальные советы** - из коробки (`tips.json`)
- **Ollama** - нужен запущенный `ollama serve` и модель; модель через
  `CLIPPY_OLLAMA_MODEL` (дефолт `llama3.2`), адрес - `CLIPPY_OLLAMA_URL`
- **Claude** - ключ в `ANTHROPIC_API_KEY`
- **RSS** - адрес фида в `CLIPPY_RSS_URL`
- **Факты из интернета** - из коробки

## разработка

проверка логики без GUI (парсинг спрайтов, кроп кадров, branching, звуки,
границы джиттера, контент):

```
CLIPPY_SELFTEST=1 swift run
```

отладка частоты: `CLIPPY_INTERVAL_SEC`, `CLIPPY_FIRST_DELAY_SEC`.

план и бэклог - в [PLAN.md](PLAN.md).

## credits & assets

- спрайты, тайминги анимаций и звуки взяты из
  [ClippyJS](https://github.com/smore-inc/clippy.js) (MIT), которые в свою
  очередь происходят из **Microsoft Agent** (персонаж «Clippit»)
- идея desktop-агента и часть фич вдохновлены
  [Cosmo/Clippy](https://github.com/Cosmo/Clippy)

спрайты и звуки остаются интеллектуальной собственностью правообладателей и
включены для личного некоммерческого использования. MIT-лицензия проекта
покрывает только исходный код.

## лицензия

[MIT](LICENSE) - на исходный код. По ассетам см. раздел выше.
