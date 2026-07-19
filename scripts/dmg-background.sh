#!/bin/bash
# генерирует фон окна dmg-установщика (assets/dmg-background.png + @2x для retina).
# запускать вручную при смене дизайна; в CI не нужен - готовые png лежат в assets.
# требует ImageMagick (brew install imagemagick).
set -euo pipefail
cd "$(dirname "$0")/.."

W=540; H=400                 # размер окна = размер фона (в точках)
FONT="/System/Library/Fonts/Supplemental/Arial.ttf"   # с кириллицей
ACCENT="#b7afdd"             # приглушённый фиолетовый (акцент Clippy)
INK="#585274"               # текст

# рисуем в 2x (retina), затем ужимаем в 1x. координаты ниже - в пикселях 2x,
# то есть вдвое больше точек окна: иконки приложения (150,205) и Applications (390,205)
mkdir -p assets
magick -size $((W*2))x$((H*2)) gradient:'#f6f4fc-#e9e5f7' \
  -font "$FONT" -fill "$INK" -pointsize 40 -gravity North \
  -annotate +0+90 'Перетащите Clippy Mac в Applications' \
  -fill "$ACCENT" -stroke "$ACCENT" -strokewidth 12 \
  -draw "line 475,410 560,410" \
  -stroke none -draw "polygon 560,386 608,410 560,434" \
  assets/dmg-background@2x.png

magick assets/dmg-background@2x.png -resize ${W}x${H} assets/dmg-background.png
echo "готово: assets/dmg-background.png (@2x)"
