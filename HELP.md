# rise_tiles — Folonium

Personal KWin/Plasma 6 tiling setup, version controlled in one place.

Everything here is either source code or the installed service scripts. The
copies KWin loads are install artifacts and live outside this repo.

Fork of [Polonium](https://github.com/zeroxoneafour/polonium). Removed all the engine and replaced it with custom rules and added bunch of shortcuts, a reactive overview and a tiling saver script that persists your layout even after logoff/shutdown.

## Why "Folonium"

It is Polonium with one letter moved: **F**olonium is the *fork* of
[Polonium](https://github.com/zeroxoneafour/polonium)

Folonium = follow + **नियम** (niyam, Sanskrit for *rule*)

## Credits

This repo is a fork; both halves come from other people's work.

- **[Polonium](https://github.com/zeroxoneafour/polonium)** — the tiling script
  by Vaughan Milliman ([zeroxoneafour](https://github.com/zeroxoneafour)).
  MIT licensed. Everything in `folonium/` builds on it.
- **Polonium Overview** (the "better overview" effect) — the desktop overview
  effect by [mj0x0](https://github.com/mj0x0). GPL-2.0-or-later. Everything in
  `folonium-overview/` builds on it.

Local changes and the rule-based work are by
[Sreinumder](https://github.com/Sreinumder).

## What is in here

| Directory | What it is | Where it is used from |
| --- | --- | --- |
| `folonium/` | Folonium tiling script (Polonium v1.2.2) plus local changes) | installed copy in `~/.local/share/kwin/scripts/folonium` |
| `folonium-overview/` | Folonium Overview KWin effect (desktop overview, window drag) | installed copy in `~/.local/share/kwin/effects/foloniumoverview` |
| `folonium-saver/` | D-Bus saver service (`xyz.vaughanm.folonium`) that stores per-display state and relays overview commands to the tiling script | `~/.local/share/folonium-saver`, D-Bus activated |

`install.sh` copies all three into place, so the running setup always matches
the working tree. `kpackagetool6 --remove` only deletes the installed copy,
never this repo.

## Install everything

```sh
./install.sh            # or: ./install.sh install
```
```sh
./install.sh uninstall  # keeps ~/.config/folonium/settings.json and kwinrc
```

The installer enables both KWin plugins, turns on the D-Bus saver the overview
needs, restarts the saver service and live-reloads the script and effect.

## Build and install the tiling script by hand

```sh
cd folonium
npm ci                      # or: npm install --no-save kwin-api@6.7.1
make build                  # bundles src/index.ts into folonium.mjs, fills pkg/
make install                # kpackagetool6 --upgrade
```

Reload after installing (KWin caches QML documents per URL):

```sh
qdbus org.kde.KWin /Scripting org.kde.kwin.Scripting.unloadScript folonium
qdbus org.kde.KWin /Scripting org.kde.kwin.Scripting.loadDeclarativeScript \
    ~/.local/share/kwin/scripts/folonium/contents/ui/main.qml folonium
qdbus org.kde.KWin /Scripting org.kde.kwin.Scripting.start
```

`start()` is not optional: a declarative script is only loaded until it runs,
and without it the script looks enabled but never publishes state.

If a file was added or renamed inside the package, KWin can keep reporting the
old path until it restarts. A full KWin/Plasma restart is the reliable fix.

## Install the overview effect by hand

```sh
kpackagetool6 --type KWin/Effect --upgrade folonium-overview   # first time: --install
qdbus org.kde.KWin /Effects org.kde.kwin.Effects.unloadEffect foloniumoverview
qdbus org.kde.KWin /Effects org.kde.kwin.Effects.loadEffect foloniumoverview
```

Toggle it with the `Better Overview` shortcut (or the screen edge configured
in its settings).

## Saver service

`folonium-saver/folonium_saver.py` is started on demand by D-Bus
(`xyz.vaughanm.folonium`). It stores per-display engine state and carries the
single pending command (swap/move/focus) from the overview effect to the
tiling script, which polls it.

## Layouts

Folonium tiles with one engine, and the engine takes its layouts as text. A
layout is written in a small slicing grammar:

- `[ ]` puts windows side by side in columns.
- `/ /` stacks them in rows.
- A bare number is that many windows stacked along the other axis.

So `[1 2]` is one window beside a column of two, and `/1 2/` is the same shape
rotated. The window count of a layout is the sum of its numbers. Layouts are
shown in this compact spelling, so a rotated `[1 2]` appears as `/1 2/` rather
than `/1 [1 1]/`.

Each KCM tab is a **layout set**. Write one or more layouts in a tab, separated
by spaces or newlines, so a single tab can cover several window counts. L1 is
the default set; pick another set from the layout menu. The largest layout in
the set that fits the open windows is used, and extra windows float. If no
layout in the set fits, all windows float.

**Split ratios** are shared by every layout and live in their own field above
the tabs: whitespace-separated options such as `2:1 3:2 1:1 2:3 1:2` for
two-child splits and `1:1:1 2:1:1 1:2:1 1:1:2` for three-child splits.
Horizontal and vertical splits keep separate selections; cycle them from the
layout menu or their shortcuts.

Repeated spellings that normalize to the same layout are dropped, but rotations
and reflections are kept as separate variants because they fill the slots in a
different order. A layout tiles as many windows as it has slots; any extra
windows float. Per-display settings such as mirror and rotate are in the layout
menu, and the KWin row there switches that display to KWin's own tiling and
back.

Rotate and mirror are independent and give four states. For `[1 2]` they are
`[1 2]` (base), `/1 2/` (rotated), `[2 1]` (mirrored), and `/2 1/` (rotated and
mirrored). Mirroring always uses the layout's own horizontal axis before the
rotation is applied, so with rotation on the mirror appears vertical on screen.

Note that layouts and ratios are parsed by **separate** fields, not mixed
together — see the next section.

## Notes

- Plasma 6 Wayland only; X11 is not supported.
- Engine state per display lives in `~/.config/folonium/settings.json`.
- Script/effect enable flags and engine options live in `~/.config/kwinrc`.
- Renamed from Polonium: the plugin keywords are now `folonium` and
  `foloniumoverview`, so old `[Script-polonium]` / `[Effect-betteroverview]`
  config groups are left behind unused until you copy them across.
- Shortcut names changed to `Folonium: …`. Rebind them under System Settings →
  Shortcuts if the old `Polonium: …` entries kept your keys.
- To clean up all unused keyboard shortcuts (dead `Polonium: …` entries
  and any other stale bindings), run:
  ```
  qdbus org.kde.kglobalaccel /component/kwin org.kde.kglobalaccel.Component.cleanUp
  ```
- For showing the Playing media in the overview effect. For browsers it is best to install the plasma-integration plugin.
    - Firefox based browser might show two separate media. You should set `media.hardwaremediakeys.enabled` flag to false.
