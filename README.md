<p align="center">
  <img src="assets/AppIcon.png" alt="Clippy app icon" width="128">
</p>

<h1 align="center">Clippy</h1>

<p align="center">
  <strong>Language:</strong> EN | <a href="README.ru.md">RU</a>
</p>

<p align="center">
  <strong>the legendary Office paperclip, reborn on macOS</strong>
</p>

<p align="center">
  <img alt="CI" src="https://github.com/boundlessend/clippy-mac/actions/workflows/ci.yml/badge.svg">
  <img alt="macOS" src="https://img.shields.io/badge/macOS-13%2B-111827">
  <img alt="Swift" src="https://img.shields.io/badge/Swift-5.9-f05138">
  <img alt="license" src="https://img.shields.io/badge/license-MIT-2563eb">
</p>

`Clippy` is a small macOS app that brings back the legendary assistant. Your character lives in the Dock as an animated icon; left-click it and a fact pops up in a speech bubble right next to it. Native Swift, zero dependencies.

## Features

- **animated Dock icon** - the app always lives in the Dock, and your chosen character animates there with a smooth idle loop that rests between bursts and occasionally throws in a spontaneous gesture.
- **a fact on click** - left-click the Dock icon and a fresh tip appears in a speech bubble right next to the icon.
- **Dock-aware bubble** - the bubble auto-sizes to the text, sits next to the icon (following the cursor on the icon), and its tail points at the Dock, wherever the Dock is (bottom / left / right).
- **Dock menu** - right-click the Dock icon: Show a fact / Show a gesture / Gestures (pick a specific one) / Character (pick one) / Random character / Settings… / About.
- **feed files** - drag a file onto the Dock icon and the character reacts; the first time it asks whether fed files should go to the Trash (changeable in Settings).
- **battery-friendly** - the idle animation rests between bursts and stops when the screen is locked or the display sleeps; an optional toggle also pauses it in Low Power Mode.
- **characters** - Clippy plus five more in the box (Merlin, Genie, Bonzi, Links, Rover), and any custom character dropped into the `Agents` folder (a subfolder with `agent.json` + `map.png`); switch in Settings, shuffle from the Dock menu, or randomize on every launch. Multi-layer sprites are composited, so full Microsoft Agent characters render correctly.
- **per-character facts** - each character shows its own facts. Clippy ships with ~500 lines in his own voice; a custom character shows facts only if you add its own `tips.json`, otherwise nothing pops up.
- **content sources** - besides local facts, Ollama / Claude / RSS / facts-API providers with an automatic fallback to local.
- **sound** - the original animation voices (off by default).
- **autostart** - at login (macOS Login Items via `SMAppService`).
- **about** - a panel with the app version.

## Installation

### from a built .dmg

Build the image and drag `ClippyMac.app` to `Applications`:

```bash
./scripts/build-dmg.sh
open build/ClippyMac.dmg
```

On the first launch of an unsigned app: right-click the `.app` and choose "Open".

### from source

```bash
swift run
```

Requires macOS 13+ and the Swift toolchain / Xcode.

## Content sources

Pick the source in Settings. Provider fields live there too (the Claude key is stored in the Keychain, not in plain text).

- **Local tips** - built in: ~500 Clippy lines, toggle categories in Settings.
- **Ollama** - a running `ollama serve` and a model; set the address and model in Settings (or via `CLIPPY_OLLAMA_URL` / `CLIPPY_OLLAMA_MODEL`).
- **Claude** - paste the API key in Settings (or `ANTHROPIC_API_KEY`).
- **RSS** - the feed URL in Settings (or `CLIPPY_RSS_URL`).
- **Facts from the internet** - built in.

## Development

Verify the logic without a GUI (sprite parsing, frame cropping, branching, sounds, bubble placement, content):

```bash
CLIPPY_SELFTEST=1 swift run
```

Import a [ClippyJS](https://github.com/smore-inc/clippy.js) character (its `map.png` + `agent.js` + optional `sounds-mp3.js`) into the `Agents` folder, then pick it in Settings:

```bash
python3 scripts/import-clippyjs.py <clippyjs-character-folder> [Name]
```

Plan and backlog live in [PLAN.md](PLAN.md).

## Credits & assets

- sprites, animation timings, and sounds come from [ClippyJS](https://github.com/smore-inc/clippy.js) (MIT), which in turn come from **Microsoft Agent** (the "Clippit" character)
- the desktop-agent idea and some features are inspired by [Cosmo/Clippy](https://github.com/Cosmo/Clippy)

Sprites and sounds remain the intellectual property of their owners and are included for personal, non-commercial use. The project's MIT license covers the source code only.

## License

[MIT](LICENSE) for the source code. For assets, see the section above.
