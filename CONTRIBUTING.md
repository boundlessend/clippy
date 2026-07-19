# участие

проект «для себя», но если захочется собрать или доработать:

## сборка и запуск

```bash
swift run                      # запустить из дерева проекта
CLIPPY_SELFTEST=1 swift run    # проверить логику без GUI (парсинг спрайтов, контент, облачко)
./scripts/build-dmg.sh         # собрать .app + .dmg
```

Требуется macOS 14+ и Xcode 15+ (Swift 5.9+). Для нарядного dmg-установщика -
`brew install create-dmg` (без него скрипт соберёт простой dmg через hdiutil).

## стиль

- функциональное ядро; OOP только для коннекторов к внешним системам (окна, провайдеры, Keychain)
- строгая типизация, явные ошибки (retries с warning, затем raise), без тихих фолбэков
- коммиты по Conventional Commits (`type(scope): описание`, на английском)
- перед изменением: `swift build` и `CLIPPY_SELFTEST=1 swift run` должны быть зелёными

## релизы

см. [RELEASING.md](RELEASING.md).
