# zmk-config

ZMK firmware configuration for a wireless [Corne](https://github.com/foostan/crkbd) split keyboard (Nice!Nano v2 + Nice!View display), built around a **Dvorak layout on macOS**.

## The problem

macOS Dvorak works by remapping QWERTY scancodes at the OS level. That means ZMK has to send QWERTY scancodes to get Dvorak output — but editing a keymap full of QWERTY codes when you *think* in Dvorak is miserable.

## The solution

This repo keeps **two representations** of the same keymap:

| File | Purpose |
|------|---------|
| `config/corne.keymap` | **ANSI** — the QWERTY scancodes ZMK actually compiles |
| `config/wysiwyg/corne.keymap` | **WYSIWYG** — the Dvorak characters you actually see on screen |

A custom translation script (`translate.rb`) converts between the two. It handles modifiers, shifted symbols, and is smart enough to leave Cmd-key combos alone (macOS uses QWERTY positions for shortcuts regardless of layout).

## Workflow

```
 Edit the WYSIWYG keymap
        │
        ▼
  make ansi          ← translate to machine-readable
        │
        ▼
   git push          ← GitHub Actions builds firmware automatically
        │
        ▼
 make get-firmware   ← download the .uf2 files
        │
        ▼
  Flash keyboard     ← drag .uf2 onto each half in bootloader mode
```

### Make targets

| Command | What it does |
|---------|-------------|
| `make ansi` | Translate WYSIWYG → ANSI (run before committing) |
| `make wysiwyg` | Translate ANSI → WYSIWYG (after editing the raw keymap) |
| `make get-firmware` | Download the latest firmware from GitHub Actions |

## Layout

Three layers on a 42-key Corne:

- **Base** — Dvorak with Ctrl/Esc/Tab on the left, Backspace/Enter on the right
- **Lower** — Numbers, brackets, and punctuation
- **Raise** — Arrow keys, Option+arrow word navigation, and delete variants

## Building

Firmware is compiled by [GitHub Actions](../../actions) using the official ZMK build workflow — no local toolchain needed. Just push and download the artifacts.

## Requirements

- [GitHub CLI](https://cli.github.com/) (`gh`) for `make get-firmware`
- Ruby for `translate.rb`

## License

[MIT](LICENSE)
