#!/usr/bin/env python3
"""импорт персонажа ClippyJS в папку персонажей ClippyMac.

вход: папка персонажа ClippyJS (или путь к agent.js) с map.png и, опционально,
sounds-mp3.js. выход: ~/Library/Application Support/ClippyMac/Agents/<Имя>/ с
agent.json + map.png + sounds/*.mp3 - подхватывается приложением (пункт «Персонаж»).

использование: import-clippyjs.py <папка_или_agent.js> [Имя]
"""
import sys
import os
import re
import json
import base64
import shutil
from pathlib import Path

# поля кадра, которые понимает наш ClippyAgent (остальное из ClippyJS отбрасываем)
FRAME_KEYS = ("duration", "images", "exitBranch", "branching", "sound")


def parse_ready(text: str, verb: str) -> tuple[str, dict]:
    """разобрать вызов вида clippy.<verb>('Имя', {...}); -> (имя, объект)"""
    m = re.search(r"\.%s\(\s*['\"]([^'\"]+)['\"]\s*,\s*(\{.*\})\s*\)\s*;?\s*$" % verb,
                  text.strip(), re.S)
    if not m:
        raise SystemExit(f"не найден вызов .{verb}(...) в файле")
    return m.group(1), json.loads(m.group(2))


def convert_agent(data: dict) -> dict:
    """ClippyJS agent-объект -> наш agent.json (framesize + animations{frames})"""
    animations: dict[str, dict] = {}
    for anim, body in data["animations"].items():
        frames = []
        for f in body.get("frames", []):
            fr = {k: f[k] for k in FRAME_KEYS if k in f}
            if "sound" in fr:
                fr["sound"] = str(fr["sound"])          # у нас sound - строковый ключ
            frames.append(fr)
        animations[anim] = {"frames": frames}
    return {"framesize": data["framesize"], "animations": animations}


def write_sounds(snd_js: Path, dest: Path) -> int:
    """декодировать base64-звуки из sounds-mp3.js в sounds/<ключ>.mp3, вернуть число.
    формат JS (ключи/значения в одинарных или двойных кавычках), не строгий JSON"""
    if not snd_js.exists():
        return 0
    text = snd_js.read_text(encoding="utf-8")
    pairs = re.findall(r"['\"](\w+)['\"]\s*:\s*['\"](data:[^'\"]+)['\"]", text)
    if not pairs:
        return 0
    sdir = dest / "sounds"
    sdir.mkdir(exist_ok=True)
    for key, uri in pairs:
        (sdir / f"{key}.mp3").write_bytes(base64.b64decode(uri.split(",", 1)[1]))
    return len(pairs)


def main() -> None:
    if len(sys.argv) < 2:
        raise SystemExit(__doc__)
    src = Path(sys.argv[1]).expanduser()
    src_dir = src if src.is_dir() else src.parent
    agent_js = src if src.is_file() and src.suffix == ".js" else src_dir / "agent.js"
    if not agent_js.exists():
        raise SystemExit(f"нет agent.js ({agent_js})")

    name_in_file, data = parse_ready(agent_js.read_text(encoding="utf-8"), "ready")
    name = sys.argv[2] if len(sys.argv) > 2 else name_in_file

    map_src = src_dir / "map.png"
    if not map_src.exists():
        raise SystemExit(f"нет map.png рядом с agent.js ({map_src})")

    # приёмник: CLIPPY_AGENTS_DIR (для сборки бандла) или пользовательская папка Agents
    base = (Path(os.environ["CLIPPY_AGENTS_DIR"]).expanduser()
            if os.environ.get("CLIPPY_AGENTS_DIR")
            else Path.home() / "Library/Application Support/ClippyMac/Agents")
    dest = base / name
    dest.mkdir(parents=True, exist_ok=True)
    (dest / "agent.json").write_text(json.dumps(convert_agent(data), ensure_ascii=False),
                                     encoding="utf-8")
    shutil.copyfile(map_src, dest / "map.png")
    n_sounds = write_sounds(src_dir / "sounds-mp3.js", dest)

    print(f"импортирован '{name}': {len(data['animations'])} анимаций, {n_sounds} звуков, "
          f"overlayCount={data.get('overlayCount', 1)} -> {dest}")


if __name__ == "__main__":
    main()
