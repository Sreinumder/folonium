# TODO

## In progress

- [ ] Fix window drag in the overview effect (left drag = swap/move, right drag = clone, snap back on invalid drop)
- [ ] Implement the custom tiling engine (see spec below)

## Overview drag — test checklist (manual)

After a KWin/Plasma restart (so the installed effect loads fresh):

1. **Open overview** — `Meta+Tab` or screen edge → grid of desktop tiles appears.
2. **Left-drag within same desktop** — grab a tiled window, drag to another tile's position → windows swap.
3. **Left-drag to different desktop** — drag window onto another desktop tile → window moves to that desktop, retiled.
4. **Right-drag to different desktop** — right-drag window onto another desktop tile → window is cloned (appears on both desktops).
5. **Drag to empty desktop chip** — drag onto the numbered chip at top → same as (3) or (4) depending on button.
6. **Drop on empty space** — release outside any tile/chip → ghost animates back to original slot (snap-back).
7. **Right-drag within same desktop** — should snap back (no-op per current logic).
8. **No double-activate** — clicking (not dragging) a window focuses it without closing the overview.

Current status: types fixed (`dragGroup`/`dragChip` now `var`), `finishDrag` compares desktops by `x11DesktopNumber`, `tileForGroup()` + local coords for `windowAt()`, `dragArea.drag.active` gates Qt drag. Logs show PRESS/BEGINDRAG but RELEASE/FINISHDRAG sometimes missing — likely event delivery to the drag tile vs. global area.

Next debugging step: check whether `dragTracker` global handler (z=100000) catches release, or if the per-tile `dragArea` with `drag.target` interferes.

## Custom tiling engine

Config (text fields, per display via the saver):

- `CustomLayouts` — one layout per whitespace-separated token; newlines are
  only formatting. `[a b c]` means `c` columns with `a`, `b`, `c` windows
  stacked vertically. `/a b c/` is the same layout rotated (rows, windows side
  by side). The window count of a layout is the sum of its numbers.
- `CustomRatios` — whitespace-separated ratios. `1:2` has arity 2, `1:2:1`
  arity 3. Ratios are matched to the number of columns (horizontal) or the
  number of windows in a stack (vertical). Separator lines are just formatting.

Behaviour:

- [ ] `[1 2 1]` builds 3 columns: one window, a 2-window stack, one window.
- [ ] `/1 2 1/` builds 3 rows: one window, 2 side by side, one window.
- [ ] Layouts are grouped by window count; a count with no exact layout uses
  the next larger one (empty slots are allowed).
- [ ] Horizontal ratio sets column widths, vertical ratio sets row heights.

Shortcuts:

- [ ] Rotate layout (toggle `[a b]` <-> `/a b/`, reuses the existing shortcut)
- [ ] Mirror layout (reverse column/row order)
- [ ] Cycle horizontal ratio
- [ ] Cycle vertical ratio
- [ ] Cycle layout for the current window count
- [ ] Cycle/rotate the order in which windows fill slots

## Known limitations

- KWin caches QML documents per URL for the whole session; renaming or adding
  files inside a loaded package needs a KWin/Plasma restart.
- The script instance currently running may be loaded from `~/dev/polonium-run3`
  because the installed entry point URL was poisoned by an earlier load.
