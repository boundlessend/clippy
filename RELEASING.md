# выпуск релиза

версия приложения берётся из git-тега - отдельно править её нигде не нужно.
тег `vX.Y.Z` -> workflow `.github/workflows/release.yml` собирает `.dmg` (версия = `X.Y.Z`)
и публикует GitHub Release с прикреплённым файлом.

## как выпустить

1. убедиться, что `main` зелёный (CI прошёл)
2. поставить тег и запушить:
   ```bash
   git tag -a v1.0.5 -m "Clippy Mac 1.0.5"
   git push origin v1.0.5
   ```
3. на macOS-раннере соберётся `ClippyMac.dmg`, создастся Release с `.dmg`, SHA256
   и инструкцией по Gatekeeper. проверить страницу Releases

## локально (запасной путь, без CI)

тот же блок установки/Gatekeeper, что кладёт CI (`--notes-file`), иначе релиз
выйдет без инструкции:

```bash
VERSION=1.0.5 ./scripts/build-dmg.sh
gh release create v1.0.5 build/ClippyMac.dmg --title "Clippy Mac v1.0.5" \
  --notes-file .github/release-notes.md
```

## подпись и обновления

- релизы ad-hoc-подписаны, без Developer ID / нотаризации (решение «только для себя»);
  Gatekeeper обходится через «Открыть всё равно» в настройках безопасности либо
  `xattr -dr com.apple.quarantine` (см. README)
- автообновлений нет (ни Sparkle, ни аналогов) - обновление вручную: скачать новый релиз
