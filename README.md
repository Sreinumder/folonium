# rise_tiles

Personal KWin/Plasma 6 tiling setup, version controlled in one place.

Everything here is either source code or the installed service scripts. The
copies KWin loads are install artifacts and live outside this repo.

## What is in here

| Directory | What it is | Where it is used from |
| --- | --- | --- |
| `polonium/` | Polonium tiling script (upstream [mj0x0/polonium](https://github.com/mj0x0/polonium) v1.2.2 plus local changes) | `~/dev/polonium` (symlink); installed copy in `~/.local/share/kwin/scripts/polonium` |
| `polonium-overview/` | Polonium Overview KWin effect (desktop overview, window drag) | `~/dev/polonium-overview` (symlink); installed copy in `~/.local/share/kwin/effects/betteroverview` |
| `polonium-saver/` | D-Bus saver service (`xyz.vaughanm.polonium`) that stores per-display state and relays overview commands to the tiling script | `~/.local/share/polonium-saver` (symlink), D-Bus activated |

The three paths above are symlinks into this repo, so the running setup always
uses the working tree. `kpackagetool6 --remove` only deletes the installed
copy, never this repo.

## Build and install the tiling script

```sh
cd polonium
npm ci                      # or: npm install --no-save kwin-api@6.7.1
make build                  # bundles src/index.ts into polonium.mjs, fills pkg/
make install                # kpackagetool6 --upgrade
```

Reload after installing (KWin caches QML documents per URL):

```sh
qdbus org.kde.KWin /Scripting org.kde.kwin.Scripting.unloadScript polonium
qdbus org.kde.KWin /Scripting org.kde.kwin.Scripting.loadDeclarativeScript \
    ~/.local/share/kwin/scripts/polonium/contents/ui/main.qml polonium
qdbus org.kde.KWin /Scripting org.kde.kwin.Scripting.start
```

If a file was added or renamed inside the package, KWin can keep reporting the
old path until it restarts. A full KWin/Plasma restart is the reliable fix.

## Install the overview effect

```sh
kpackagetool6 --type KWin/Effect --upgrade polonium-overview   # first time: --install
qdbus org.kde.KWin /Effects org.kde.kwin.Effects.unloadEffect betteroverview
qdbus org.kde.KWin /Effects org.kde.kwin.Effects.loadEffect betteroverview
```

Toggle it with the `Better Overview` shortcut (or the screen edge configured
in its settings).

## Saver service

`polonium-saver/polonium_saver.py` is started on demand by D-Bus
(`xyz.vaughanm.polonium`). It stores per-display engine state and carries the
single pending command (swap/move/focus) from the overview effect to the
tiling script, which polls it.

## Notes

- Plasma 6 Wayland only; X11 is not supported.
- Engine state per display lives in `~/.config/polonium/settings.json`.
- Script/effect enable flags and engine options live in `~/.config/kwinrc`.
- For showing the Playing media in the overview effect. For browsers it is best to install the plasma-integration plugin.
    - Firefox based browser might show two separate media. You should set `media.hardwaremediakeys.enabled` flag to false.
