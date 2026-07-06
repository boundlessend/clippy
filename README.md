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

`Clippy` is a small macOS app that brings back the legendary assistant. Every so often, while your screen is active, Clippy pops up in a corner, plays an animation, and shows a fact or a tip in a speech bubble. Native Swift, menu bar agent, zero dependencies.

## Features

- **menu bar agent** - Clippy himself as the tray icon; a click opens a menu (Show now / Play gesture / Settings… / About / Quit), and Settings… opens a window.
- **where to show** - menu bar and/or a Dock icon (both by default). Hide either; if both are hidden, the settings window opens when you launch the already-running app.
- **the assistant** - a transparent panel above all windows and Spaces that never steals focus.
- **living idle** - probabilistic frame transitions (branching) and random idle gestures.
- **interaction** - left click = gesture, right click = menu, drag with the mouse; the position is remembered.
- **frequency** - any number of minutes, applied on the fly.
- **activity detection** - never shows on a locked or sleeping screen, or while you are away.
- **size** - Clippy scale from ×0.5 to ×2.
- **sound** - the original animation voices (off by default).
- **snooze** - "mute for an hour" from the context menu.
- **autostart** - at login (LaunchAgent).
- **content** - ~600 built-in lines in Clippy's own voice, filterable by category, plus Ollama / Claude / RSS / facts-API providers with an automatic fallback to local.
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

- **Local tips** - built in: ~600 Clippy lines, toggle categories in Settings.
- **Ollama** - a running `ollama serve` and a model; set the address and model in Settings (or via `CLIPPY_OLLAMA_URL` / `CLIPPY_OLLAMA_MODEL`).
- **Claude** - paste the API key in Settings (or `ANTHROPIC_API_KEY`).
- **RSS** - the feed URL in Settings (or `CLIPPY_RSS_URL`).
- **Facts from the internet** - built in.

## Development

Verify the logic without a GUI (sprite parsing, frame cropping, branching, sounds, jitter bounds, content):

```bash
CLIPPY_SELFTEST=1 swift run
```

Frequency debugging: `CLIPPY_INTERVAL_SEC`, `CLIPPY_FIRST_DELAY_SEC`.

Plan and backlog live in [PLAN.md](PLAN.md).

## Credits & assets

- sprites, animation timings, and sounds come from [ClippyJS](https://github.com/smore-inc/clippy.js) (MIT), which in turn come from **Microsoft Agent** (the "Clippit" character)
- the desktop-agent idea and some features are inspired by [Cosmo/Clippy](https://github.com/Cosmo/Clippy)

Sprites and sounds remain the intellectual property of their owners and are included for personal, non-commercial use. The project's MIT license covers the source code only.

## License

[MIT](LICENSE) for the source code. For assets, see the section above.
