#!/usr/bin/env python3
"""импорт персонажа ClippyJS в папку персонажей ClippyMac.

вход: папка персонажа ClippyJS (или путь к agent.js) с map.png и, опционально,
sounds-mp3.js. выход: ~/Library/Application Support/ClippyMac/Agents/<Имя>/ с
agent.json + map.png + sounds/*.mp3 - подхватывается приложением (пункт «Персонаж»).

использование: import-clippyjs.py <папка_или_agent.js> [Имя]

спрайты и звуки персонажей - интеллектуальная собственность правообладателей
(Microsoft Agent и др.), только личное использование - см. README «Credits & assets»
"""
import sys
import os
import re
import json
import base64
import binascii
import shutil
from pathlib import Path

# поля кадра, которые понимает наш ClippyAgent (остальное из ClippyJS отбрасываем)
FRAME_KEYS = ("duration", "images", "exitBranch", "branching", "sound")


def safe_name(name: str) -> str:
    """имя персонажа без пути: только последний компонент, без .. и разделителей
    (иначе можно записать за пределы папки Agents)"""
    clean = Path(name).name.strip()
    if not clean or clean in {".", ".."} or "/" in name or "\\" in name:
        raise SystemExit(f"недопустимое имя персонажа: {name!r}")
    return clean


def parse_ready(text: str, verb: str) -> tuple[str, dict]:
    """разобрать вызов вида clippy.<verb>('Имя', {...}); -> (имя, объект).
    объект в agent.js - валидный JSON (двойные кавычки)"""
    m = re.search(r"\.%s\(\s*['\"]([^'\"]+)['\"]\s*,\s*(\{.*\})\s*\)\s*;?\s*$" % verb,
                  text.strip(), re.S)
    if not m:
        raise SystemExit(f"не найден вызов .{verb}(...) в файле")
    try:
        return m.group(1), json.loads(m.group(2))
    except json.JSONDecodeError as e:
        raise SystemExit(f".{verb}(...): объект не разобрался как JSON: {e}")


def convert_agent(data: dict) -> dict:
    """ClippyJS agent-объект -> наш agent.json (framesize + animations{frames})"""
    fs = data.get("framesize")
    if not (isinstance(fs, list) and len(fs) == 2):
        raise SystemExit("agent.js: framesize должен быть [w,h]")
    anims = data.get("animations")
    if not isinstance(anims, dict):
        raise SystemExit("agent.js: отсутствует секция animations")
    animations: dict[str, dict] = {}
    for anim, body in anims.items():
        frames = []
        for f in (body.get("frames", []) if isinstance(body, dict) else []):
            if not isinstance(f, dict):
                continue
            fr = {k: f[k] for k in FRAME_KEYS if k in f}
            if "sound" in fr:
                fr["sound"] = str(fr["sound"])          # у нас sound - строковый ключ
            frames.append(fr)
        animations[anim] = {"frames": frames}
    return {"framesize": fs, "animations": animations}


def write_sounds(snd_js: Path, dest: Path) -> int:
    """декодировать base64-звуки из sounds-mp3.js в sounds/<ключ>.mp3, вернуть число.
    формат JS (ключи/значения в одинарных или двойных кавычках), не строгий JSON.
    битые звуки пропускаем с сообщением, а не роняем весь импорт"""
    if not snd_js.exists():
        return 0
    pairs = re.findall(r"['\"](\w+)['\"]\s*:\s*['\"](data:[^'\"]+)['\"]",
                       snd_js.read_text(encoding="utf-8"))
    if not pairs:
        return 0
    sdir = dest / "sounds"
    sdir.mkdir(exist_ok=True)
    n = 0
    for key, uri in pairs:
        try:
            (sdir / f"{key}.mp3").write_bytes(base64.b64decode(uri.split(",", 1)[1], validate=True))
            n += 1
        except (binascii.Error, IndexError, ValueError) as e:
            print(f"  пропущен звук {key}: {e}")
    return n


def main() -> None:
    if len(sys.argv) < 2:
        raise SystemExit(__doc__)
    src = Path(sys.argv[1]).expanduser()
    src_dir = src if src.is_dir() else src.parent
    agent_js = src if src.is_file() and src.suffix == ".js" else src_dir / "agent.js"
    if not agent_js.exists():
        raise SystemExit(f"нет agent.js ({agent_js})")

    name_in_file, data = parse_ready(agent_js.read_text(encoding="utf-8"), "ready")
    name = safe_name(sys.argv[2] if len(sys.argv) > 2 else name_in_file)

    map_src = src_dir / "map.png"
    if not map_src.exists():
        raise SystemExit(f"нет map.png рядом с agent.js ({map_src})")

    # приёмник: CLIPPY_AGENTS_DIR (для сборки бандла) или пользовательская папка Agents
    base = (Path(os.environ["CLIPPY_AGENTS_DIR"]).expanduser()
            if os.environ.get("CLIPPY_AGENTS_DIR")
            else Path.home() / "Library/Application Support/ClippyMac/Agents")
    dest = base / name
    if not dest.resolve().is_relative_to(base.resolve()):    # страховка от выхода за папку
        raise SystemExit(f"путь назначения вне папки Agents: {dest}")
    dest.mkdir(parents=True, exist_ok=True)
    (dest / "agent.json").write_text(json.dumps(convert_agent(data), ensure_ascii=False),
                                     encoding="utf-8")
    shutil.copyfile(map_src, dest / "map.png")
    n_sounds = write_sounds(src_dir / "sounds-mp3.js", dest)

    print(f"импортирован '{name}': {len(data['animations'])} анимаций, {n_sounds} звуков, "
          f"overlayCount={data.get('overlayCount', 1)} -> {dest}")


if __name__ == "__main__":
    main()
