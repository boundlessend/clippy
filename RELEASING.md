# выпуск релиза

версия приложения берётся из git-тега - отдельно править её нигде не нужно.
тег `vX.Y.Z` -> workflow `.github/workflows/release.yml` собирает `.dmg` (версия = `X.Y.Z`)
и публикует GitHub Release с прикреплённым файлом.

## как выпустить

1. убедиться, что `main` зелёный (CI прошёл)
2. поставить тег и запушить:
   ```bash
   git tag -a v1.0.0 -m "Clippy 1.0.0"
   git push origin v1.0.0
   ```
3. на macOS-раннере соберётся `ClippyMac.dmg`, создастся Release с `.dmg` и инструкцией
   по Gatekeeper. проверить страницу Releases

## локально (запасной путь, без CI)

```bash
VERSION=1.0.0 ./scripts/build-dmg.sh
gh release create v1.0.0 build/ClippyMac.dmg --title "Clippy v1.0.0" --generate-notes
```

## подпись и обновления

- релизы ad-hoc-подписаны, без Developer ID / нотаризации (решение «только для себя»);
  Gatekeeper обходится правым кликом «Открыть» (см. README)
- автообновлений нет (ни Sparkle, ни аналогов) - обновление вручную: скачать новый релиз
