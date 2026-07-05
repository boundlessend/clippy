# clippy-mac

возрождение легендарного скрепыша (Clippy/Clippit) на macOS. раз в настраиваемый
интервал при активном экране скрепыш выныривает в углу, проигрывает анимацию и
показывает в речевом баллоне факт или совет.

- нативно Swift/SwiftUI, menu bar agent, ноль зависимостей
- оригинальные спрайты Clippy (из ClippyJS)
- частотность показа настраивается (пресеты + свой интервал)
- контент за протоколом: локальный JSON на старте, дальше Ollama / Claude / RSS /
  facts-API

статус: рабочий MVP (этапы P0-P5). сборка: `swift build`, запуск: `swift run`.
проверка логики без GUI: `CLIPPY_SELFTEST=1 swift run`. подробности и план -
в [PLAN.md](PLAN.md).

## настройка источников контента

- **Локальные советы** - из коробки (`tips.json`)
- **Ollama** - нужен запущенный `ollama serve` и модель; выбор модели через
  `CLIPPY_OLLAMA_MODEL` (дефолт `llama3.2`), адрес - `CLIPPY_OLLAMA_URL`
- **Claude** - ключ в `ANTHROPIC_API_KEY`
- **RSS** - адрес фида в `CLIPPY_RSS_URL`
- **Факты из интернета** - из коробки

отладка частоты: `CLIPPY_INTERVAL_SEC`, `CLIPPY_FIRST_DELAY_SEC`.
