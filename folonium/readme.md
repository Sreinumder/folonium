# folonium

Rule-based autotiling for KWin 6 (Plasma 6, Wayland).

A fork of [Polonium](https://github.com/zeroxoneafour/polonium), which is the
spiritual successor to Bismuth. Folonium replaces the fixed tiling engines with
a small layout language: you write the shapes you want for each window count,
and the script tiles them.

See the repository root [`README.md`](../README.md) for the feature overview
and [`HELP.md`](../HELP.md) for usage and configuration.

## Layout

| Path | What it is |
| --- | --- |
| `src/index.ts` | The tiling script bundle. This is the code KWin runs; edit it directly. |
| `src/qml/` | QML loaded by KWin: entry point, settings popup, shortcuts, D-Bus calls. |
| `res/` | Package metadata, KConfig defaults, settings UI, launcher icon. |

There is no per-module build step: `src/index.ts` is copied verbatim into the
package as `contents/code/main.mjs`.

## Building

Requires `zip` and `kpackagetool6`.

```sh
make          # build, install, clean
make build    # build the .kwinscript package
make install  # install into KWin
```

The repository root has an `install.sh` that installs the script, the overview
effect, and the D-Bus saver together.
