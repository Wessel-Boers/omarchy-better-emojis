# Better Emojis for Omarchy

A drop-in replacement for the built-in Omarchy emoji picker (`Super + Ctrl + E`)
with category tabs, recents, skin tones, a live preview, and adjustable sizing —
the emoji-picker experience you know from WhatsApp, iOS, and Android, native to
your Omarchy shell.

![preview](https://raw.githubusercontent.com/wessel/omarchy-better-emojis/main/.assets/preview.png)

## Install

```bash
omarchy plugin add https://github.com/wessel/omarchy-better-emojis.git --enable
```

That's it. The plugin registers itself as the implementation behind
`omarchy.emojis`, so your existing `Super + Ctrl + E` binding opens it and the
stock picker is disabled automatically. Removing the plugin restores the stock
picker:

```bash
omarchy plugin remove wessel.better-emojis
```

## Features

- **Category tabs** — All, Recent, Smileys & Emotion, People & Body,
  Animals & Nature, Food & Drink, Activities, Travel & Places, Objects,
  Symbols, Flags. Searching always searches every category.
- **Recents** — everything you insert is remembered (last 30) and one click away.
- **Skin tones** — five tones plus default, applied live across the grid and
  preview; toned picks are stored in recents as-is.
- **Live preview** — hover or cursor over any emoji to see it large with its name.
- **Adjustable layout** — emoji size (Normal / Large / Extra Large), window
  width (Normal / Wide / Extra Wide), and window height (Normal / Tall /
  Extra Tall) are preset pickers in the plugin's settings popover
  (gear icon or `Ctrl + ,`).
- **Copy mode** — `Ctrl + Enter` copies instead of typing into the focused app.
- **Theme aware** — uses the same menu surface tokens as the stock picker, so
  every Omarchy theme styles it automatically.
- **2,239 emojis** — generated from Unicode emoji-test.txt with CLDR names and
  keywords (Emoji 17-era data), ordered exactly like every other platform.

## Keyboard shortcuts

| Key | Action |
| --- | --- |
| type | Search all categories |
| `Esc` | Clear search → close settings → close picker |
| arrows / PgUp / PgDn | Move the cursor |
| `Tab` / `Shift + Tab` | Next / previous category tab |
| `Ctrl + 1` … `Ctrl + 9` | Jump to tab N |
| `Ctrl + T` | Cycle skin tone |
| `Enter` | Insert selected emoji |
| `Ctrl + Enter` | Copy selected emoji |
| `Ctrl + ,` | Toggle the settings popover |

## Settings

Settings persist in
`~/.local/state/omarchy/plugins/wessel.better-emojis/settings.json`
(deliberately outside the plugin folder so `omarchy plugin update` stays a clean
fast-forward): emoji size, window width/height, chosen skin tone, last open
category, and recent emojis.

## How it works

The manifest carries `"omarchy": { "clonedFrom": "omarchy.emojis" }`. The shell
routes every call made to the built-in `omarchy.emojis` id — including the
`Super + Ctrl + E` binding — to the enabled plugin that claims it, and disables
the stock picker while this one is enabled. It's the same mechanism
`omarchy plugin clone` uses, shipped as a standalone plugin.

## Development

Regenerate the emoji dataset (requires network):

```bash
python3 tools/generate_emoji_data.py
```

Validate the manifest the same way the shell does:

```bash
omarchy plugin validate .
```

For local testing, symlink or copy the repo into
`~/.config/omarchy/plugins/wessel.better-emojis/`, run
`omarchy plugin enable wessel.better-emojis`, then hit `Super + Ctrl + E`.
Edits under `~/.config/omarchy/plugins/` hot-reload.

## License

MIT
