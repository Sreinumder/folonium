/*
    SPDX-FileCopyrightText: 2026 mj0x0
    SPDX-License-Identifier: GPL-2.0-or-later
*/

import QtQuick
import QtQuick.Effects
import org.kde.kirigami as Kirigami
import org.kde.kwin as KWinComponents

FocusScope {
    id: root
    focus: true

    readonly property QtObject targetScreen: KWinComponents.SceneView.screen
    readonly property QtObject currentDesktop: KWinComponents.SceneView.currentDesktop
    readonly property var desktops: KWinComponents.Workspace.desktops
    readonly property int desktopCount: Math.max(1, desktops.length)
    readonly property QtObject cfg: effect.configuration

    readonly property real screenW: targetScreen.geometry.width
    readonly property real screenH: targetScreen.geometry.height
    readonly property real screenX: targetScreen.geometry.x
    readonly property real screenY: targetScreen.geometry.y
    readonly property real dpr: targetScreen.devicePixelRatio
    readonly property int spacing: 3
    // full-screen overview: desktops are packed inside this margin
    readonly property int outerPad: 8
    readonly property int groupGap: 6
    readonly property int chipRowH: 46
    readonly property string activity: KWinComponents.Workspace.currentActivity

    // Dragging or reaching the top edge, or resting on the media strip, reveals
    // the top band; the grid slides down so nothing sits under it. The strip's
    // own mouse areas swallow hover, so it reports itself.
    property bool mediaHover: false
    readonly property bool topHover: mediaHover || mouseY < root.outerPad + root.mediaCardHeight
    readonly property bool chipsShown: dragActive || topHover
    // The band is reserved at once; the numbers fade in after the drop.
    property bool chipsReady: false
    Timer {
        id: chipsDelay
        interval: Kirigami.Units.longDuration
        onTriggered: root.chipsReady = root.chipsShown
    }
    onChipsShownChanged: {
        if (chipsShown) {
            chipsDelay.restart();
        } else {
            chipsDelay.stop();
            root.chipsReady = false;
        }
        rebuildGroups();
    }

    // Occupied desktops become groups packed to the largest common scale;
    // empty ones only get a numbered chip at the top.
    property var groups: []
    property var emptyDesktops: []
    property var desktopStates: ({})

    // A drag is drawn as a ghost above the panel; the source tile hides for a
    // move and dims for a clone. The ghost either lands on a desktop
    // (move/clone/swap) or animates back to where the window is tiled.
    property Item dragTile: null
    property QtObject dragWindow: null
    // Plain objects from root.groups / root.emptyDesktops, not Items.
    property var dragGroup: null
    property var dragChip: null
    property bool dragActive: false
    property bool dragReturning: false
    property int dragButton: Qt.NoButton
    property point dragPointer: Qt.point(0, 0)
    property point dragGrab: Qt.point(0, 0)
    property point dragReturnTo: Qt.point(0, 0)
    property real dragW: 1
    property real dragH: 1

    // Mouse position for hover desktop switching
    property real mouseX: 0
    property real mouseY: 0
    // Hover switching starts only after the pointer really moves, so opening
    // the overview does not switch away from the desktop it opened on.
    property bool pointerMoved: false
    // The real desktop and window under the pointer when the overview opened.
    property QtObject cursorDesktop: null
    property QtObject cursorWindow: null
    // Where the pointer really was, and whether it was moved into the preview.
    property point openPointer: Qt.point(0, 0)
    property bool openTransposed: false
    // The desktop that was active when the overview opened; quitting without
    // a direct choice returns there.
    property QtObject originDesktop: null
    property bool desktopPicked: false
    // Hover switches once per desktop entry, so it must not keep re-issuing
    // the switch while the pointer rests on the same desktop.
    property int hoveredDesktopNumber: 0
    // After a successful drag: retile the origin first, then land on the target.
    property QtObject dropTargetDesktop: null

    // Right click opens this window menu; it lives in the effect so the
    // overview can keep showing the change it makes.
    property QtObject menuWindow: null
    property point menuAt: Qt.point(0, 0)

    readonly property int tileRadius: 0

    // What sits behind the panel: the wallpaper, like KDE's own overview.
    readonly property int backdropMode: 2
    readonly property Item backdropSource: backdropMode === 1 ? backdrop : (backdropMode === 2 ? wallpaperBg : null)
    readonly property bool backdropBlur: backdropSource !== null

    // Now playing sits in the top-right corner. The revealed top band is at
    // least as tall as a media card, so the grid drops clear of both.
    readonly property int mediaCardHeight: 72
    readonly property int topBand: root.chipsShown ? Math.max(root.chipRowH, root.mediaCardHeight) : 0
    property int mediaTick: 0
    property real mediaAt: 0

    property bool ready: false
    property real openProgress: ready && effect.activated ? 1 : 0
    Component.onCompleted: Qt.callLater(() => {
        root.ready = true;
        root.rebuildGroups();
    })

    // MPRIS lives behind the polonium saver service: QML's DBusCall cannot
    // build the object-path/int64 arguments that seeking needs. One call gives
    // the whole list, so the strip costs one round trip per second.
    ListModel {
        id: mediaModel
    }
    KWinComponents.DBusCall {
        id: mediaCall
        service: "xyz.vaughanm.polonium"
        path: "/saver"
        dbusInterface: "xyz.vaughanm.polonium"
        method: "GetMedia"
        onFinished: (returnValue) => root.parseMedia(returnValue.length > 0 ? returnValue[0] : "")
        onFailed: () => mediaModel.clear()
    }
    KWinComponents.DBusCall {
        id: mediaAction
        service: "xyz.vaughanm.polonium"
        path: "/saver"
        dbusInterface: "xyz.vaughanm.polonium"
        method: "MediaAction"
    }
    // The effect cannot move real windows; ask polonium to exchange these two
    // in the tiling layout and it retiles them right away.
    KWinComponents.DBusCall {
        id: requestCall
        service: "xyz.vaughanm.polonium"
        path: "/saver"
        dbusInterface: "xyz.vaughanm.polonium"
        method: "SetRequest"
    }
    function requestSwap(a, b) {
        requestCall.arguments = [JSON.stringify({ t: "swap", a: String(a.internalId), b: String(b.internalId) })];
        requestCall.call();
    }

    // Only KWin's own D-Bus method moves the real desktop; writing
    // Workspace.currentDesktop from an effect is ignored.
    KWinComponents.DBusCall {
        id: setDesktopCall
        service: "org.kde.KWin"
        path: "/KWin"
        dbusInterface: "org.kde.KWin"
        method: "setCurrentDesktop"
        onFailed: () => {}
    }

    // Window menu. Above/below/hide apply immediately; the rule editors are
    // KWin's own KCM, told which window to edit on its command line, so the
    // effect has to close for it to take focus.
    function openMenu(window, p) {
        root.menuWindow = window;
        root.menuAt = p;
    }
    function closeMenu() {
        root.menuWindow = null;
    }
    function requestRules(window, wholeApp) {
        const id = String(window.internalId);
        root.closeMenu();
        effect.deactivate();
        requestCall.arguments = [JSON.stringify({ t: "rules", id: id, app: wholeApp })];
        requestCall.call();
    }

    // Polonium: a desktop group's layout buttons ask the script to change that
    // desktop, so the overview and the real desktop stay in step.
    function layoutCommand(number, action) {
        requestCall.arguments = [JSON.stringify({
            t: "layout",
            action: action,
            desktop: number,
            output: root.targetScreen.name
        })];
        requestCall.call();
    }

    // Request window focus from the polonium script (via saver D-Bus).

    // Every desktop's layout state in one call, keyed the same way polonium
    // publishes it in Display.toString().
    KWinComponents.DBusCall {
        id: statesCall
        service: "xyz.vaughanm.polonium"
        path: "/saver"
        dbusInterface: "xyz.vaughanm.polonium"
        method: "GetStates"
        onFinished: (returnValue) => root.parseStates(returnValue.length > 0 ? returnValue[0] : "")
        onFailed: () => {}
    }
    function parseStates(raw) {
        try {
            root.desktopStates = JSON.parse(raw) || {};
        } catch (e) {
            root.desktopStates = {};
        }
        root.rebuildGroups();
    }
    Timer {
        id: hoverDesktopTimer
        interval: 100
        repeat: true
        running: true
        onTriggered: {
            if (!effect.activated || !root.pointerMoved || root.dragActive || root.dropTargetDesktop !== null) return;
            const d = root.desktopAt(Qt.point(root.mouseX, root.mouseY));
            const n = d !== null ? d.x11DesktopNumber : 0;
            // One switch per hover; leaving all desktops re-arms it.
            if (n === root.hoveredDesktopNumber) return;
            root.hoveredDesktopNumber = n;
            if (d !== null) {
                root.switchTo(d);
            }
        }
    }
    Timer {
        interval: 500
        repeat: true
        running: effect.activated
        triggeredOnStart: true
        onTriggered: {
            statesCall.call();
            root.rebuildGroups();
        }
    }
    onDesktopCountChanged: rebuildGroups()
    onCurrentDesktopChanged: rebuildGroups()
    Connections {
        target: effect
        function onActivatedChanged() {
            if (effect.activated) {
                root.originDesktop = KWinComponents.Workspace.currentDesktop;
                root.desktopPicked = false;
                root.hoveredDesktopNumber = 0;
                // The pointer may already rest on a desktop; start from where
                // it really is instead of waiting for the first move.
                root.openPointer = Qt.point(KWinComponents.Workspace.cursorPos.x, KWinComponents.Workspace.cursorPos.y);
                root.mouseX = root.openPointer.x;
                root.mouseY = root.openPointer.y;
                root.pointerMoved = false;
                root.openTransposed = false;
                // The grid may be about to drop; let it land before the
                // numbers fade in.
                root.chipsReady = false;
                chipsDelay.restart();
                root.updateCursorTarget();
                root.dropTargetDesktop = null;
                statesCall.call();
                root.rebuildGroups();
                if (root.cfg.Transpose) {
                    root.transposeOpenPointer();
                }
            } else {
                afterDropTimer.stop();
                root.dropTargetDesktop = null;
                // Quitting without choosing returns to the desktop the
                // overview was opened on, so hovering does not move the user.
                if (!root.desktopPicked && root.originDesktop !== null) {
                    root.switchTo(root.originDesktop);
                }
                if (!root.desktopPicked && root.openTransposed && root.cfg.Transpose) {
                    root.warpPointer(root.openPointer, 150);
                }
                root.originDesktop = null;
                root.desktopPicked = false;
                root.openTransposed = false;
                root.cursorDesktop = null;
                root.cursorWindow = null;
            }
        }
    }

    // Real hit test against the windows as they sit on the screen now. KWin's
    // overview cannot warp the pointer, so this is what tells the grid which
    // window the user is already pointing at.
    function updateCursorTarget() {
        const p = KWinComponents.Workspace.cursorPos;
        const desktop = KWinComponents.Workspace.currentDesktop;
        let found = null;
        const order = KWinComponents.Workspace.stackingOrder;
        for (let i = order.length - 1; i >= 0; i--) {
            const w = order[i];
            if (w.skipPager || w.onScreenDisplay || w.notification || w.criticalNotification || w.minimized || w.hidden) {
                continue;
            }
            if (w.output === null || w.output.name !== root.targetScreen.name) {
                continue;
            }
            if (!w.onAllDesktops && w.desktops.indexOf(desktop) === -1) {
                continue;
            }
            if (w.activities.length > 0 && w.activities.indexOf(root.activity) === -1) {
                continue;
            }
            if (p.x >= w.x && p.x < w.x + w.width && p.y >= w.y && p.y < w.y + w.height) {
                found = w;
                break;
            }
        }
        root.cursorDesktop = desktop;
        root.cursorWindow = found;
    }

    // The DSL bracket layout ("[1 2]" side by side, "/1 1/" stacked) to leaf
    // rectangles in 0..1 tile space, in leaf order.
    function shapeRects(text, count) {
        const rects = [];
        if (count < 1) {
            return rects;
        }
        let i = 0;
        function skip() {
            while (i < text.length && /\s/.test(text[i])) {
                i++;
            }
        }
        function node(parentDir) {
            skip();
            const ch = text[i];
            if (ch === "[" || ch === "/") {
                i++;
                const dir = ch === "[" ? 1 : 2;
                const close = ch === "[" ? "]" : "/";
                const children = [];
                while (true) {
                    skip();
                    if (i >= text.length) {
                        throw new Error("unterminated shape");
                    }
                    if (text[i] === close) {
                        i++;
                        break;
                    }
                    children.push(node(dir));
                }
                return { dir: dir, children: children };
            }
            const m = /^\d+/.exec(text.slice(i));
            if (m === null) {
                throw new Error("bad shape");
            }
            i += m[0].length;
            const n = Math.max(1, parseInt(m[0], 10));
            const dir = parentDir === 1 ? 2 : 1;
            const children = [];
            for (let k = 0; k < n; k++) {
                children.push({ dir: 0, children: [] });
            }
            return children.length === 1 ? children[0] : { dir: dir, children: children };
        }
        function walk(n, x, y, w, h) {
            if (n.dir === 0) {
                rects.push({ x: x, y: y, w: w, h: h });
                return;
            }
            const k = n.children.length;
            if (n.dir === 1) {
                const cw = w / k;
                for (let c = 0; c < k; c++) {
                    walk(n.children[c], x + c * cw, y, cw, h);
                }
            } else {
                const ch = h / k;
                for (let c = 0; c < k; c++) {
                    walk(n.children[c], x, y + c * ch, w, ch);
                }
            }
        }
        try {
            walk(node(1), 0, 0, 1, 1);
        } catch (e) {
            rects.length = 0;
        }
        if (rects.length !== count) {
            // Unknown or mismatched shape: an even grid is still a fair preview.
            rects.length = 0;
            const cols = Math.ceil(Math.sqrt(count));
            const rows = Math.ceil(count / cols);
            for (let k = 0; k < count; k++) {
                rects.push({ x: (k % cols) / cols, y: Math.floor(k / cols) / rows, w: 1 / cols, h: 1 / rows });
            }
        }
        return rects;
    }

    // One group per occupied desktop. A monocle desktop with a few windows
    // becomes one cell per window; over the limit it previews the tiled layout
    // it would switch to.
    function collectGroups() {
        const wins = KWinComponents.Workspace.stackingOrder;
        const list = [];
        for (let i = 0; i < desktops.length; i++) {
            const d = desktops[i];
            const key = JSON.stringify({ d: d.id, a: root.activity, o: root.targetScreen.name });
            let state = {};
            try {
                state = JSON.parse(root.desktopStates[key] || "{}");
            } catch (e) {
                state = {};
            }
            const desktopWindows = [];
            // Topmost first: in monocle the active window leads the cells.
            for (let j = wins.length - 1; j >= 0; j--) {
                const w = wins[j];
                // OSDs, notifications and KWin's own overlays float on every
                // desktop; they are not desktop contents.
                if (w.onScreenDisplay || w.notification || w.criticalNotification) {
                    continue;
                }
                if (w.pid <= 0 && w.resourceClass === "") {
                    continue;
                }
                if (w.skipPager || w.output.name !== root.targetScreen.name) {
                    continue;
                }
                if (w.desktops.length > 0 && w.desktops.indexOf(d) === -1) {
                    continue;
                }
                if (w.activities.length > 0 && w.activities.indexOf(root.activity) === -1) {
                    continue;
                }
                desktopWindows.push(w);
            }
            const shown = desktopWindows.filter(w => !w.minimized);
            // A monocle desktop previews the shape it would tile into. It never
            // becomes one desktop-sized cell per window: that changed the
            // desktop's block and reshuffled the whole pack.
            const mono = state.mono === true && shown.length > 0;
            let previewRects = null;
            if (mono) {
                const rects = root.shapeRects(state.shape || "", shown.length);
                previewRects = rects.length === shown.length ? rects : null;
            }
            list.push({
                index: i,
                desktop: d,
                number: d.x11DesktopNumber,
                occupied: desktopWindows.length > 0,
                mono: mono,
                monoWindows: mono ? shown : [],
                previewRects: previewRects,
                count: desktopWindows.length
            });
        }
        return list;
    }

    // Place the desktops into a grid of equally sized, screen-shaped cells.
    // Every desktop gets one cell, so the pack order always follows desktop
    // order and no layout can reshuffle it.
    function packGroups(occupied) {
        const availW = root.screenW - 2 * root.outerPad;
        const availH = root.screenH - 2 * root.outerPad - root.topBand;
        const aspect = root.screenW / Math.max(1, root.screenH);
        const items = [];
        for (const g of occupied) {
            items.push({ g: g, rows: 1, cols: 1 });
        }
        const total = items.length;
        if (items.length === 0) {
            return null;
        }
        // Every block is one cell, so this keeps desktop order.
        items.sort((a, b) => a.g.index - b.g.index);
        let best = null;
        for (let C = 1; C <= total; C++) {
            if (!items.every(it => it.cols <= C)) {
                continue;
            }
            const grid = root.placeBlocks(items, C, Math.ceil(total / C));
            if (grid === null) {
                continue;
            }
            const cellW = Math.min(availW / C, (availH * aspect) / grid.rows);
            if (!(cellW > 0)) {
                continue;
            }
            const fill = total / (C * grid.rows);
            // Prefer square-ish grids: one that is much wider or taller than
            // the screen leaves the other axis empty. Landscape screens also
            // prefer columns over rows.
            const score = cellW * fill / (1 + 0.35 * Math.abs(C - grid.rows)) * (C < grid.rows ? 0.95 : 1);
            if (best === null || score > best.score + 0.0001) {
                best = { score: score, C: C, rows: grid.rows, cells: cellW, placements: grid.placements };
            }
        }
        return best;
    }

    // First fit into a C-column grid, growing the rows until everything fits.
    function placeBlocks(items, C, minRows) {
        let maxRows = 0;
        for (const it of items) {
            maxRows += it.rows;
        }
        for (let R = minRows; R <= Math.max(minRows, maxRows); R++) {
            const used = [];
            const placements = [];
            let ok = true;
            for (const it of items) {
                let at = null;
                for (let r = 0; r + it.rows <= R && at === null; r++) {
                    for (let c = 0; c + it.cols <= C; c++) {
                        let free = true;
                        for (let rr = r; rr < r + it.rows && free; rr++) {
                            for (let cc = c; cc < c + it.cols; cc++) {
                                if (used[rr * C + cc] === true) {
                                    free = false;
                                    break;
                                }
                            }
                        }
                        if (free) {
                            at = { r: r, c: c };
                            break;
                        }
                    }
                }
                if (at === null) {
                    ok = false;
                    break;
                }
                for (let rr = at.r; rr < at.r + it.rows; rr++) {
                    for (let cc = at.c; cc < at.c + it.cols; cc++) {
                        used[rr * C + cc] = true;
                    }
                }
                placements.push({ g: it.g, r: at.r, c: at.c, rows: it.rows, cols: it.cols });
            }
            if (ok) {
                return { rows: R, placements: placements };
            }
        }
        return null;
    }

    function rebuildGroups() {
        const list = root.collectGroups();
        const occupied = list.filter(g => g.occupied);
        const packed = root.packGroups(occupied);
        const rects = {};
        if (packed !== null && packed.cells > 0) {
            const cellH = packed.cells * root.screenH / Math.max(1, root.screenW);
            const gridW = packed.C * packed.cells;
            const gridH = packed.rows * cellH;
            const x0 = (root.screenW - gridW) / 2;
            const y0 = root.outerPad + root.topBand + Math.max(0, (root.screenH - 2 * root.outerPad - root.topBand - gridH) / 2);
            for (const p of packed.placements) {
                // A couple of pixels between blocks keep neighbouring desktops
                // from reading as one wide tile.
                rects[p.g.index] = {
                    x: Math.round(x0 + p.c * packed.cells) + 2,
                    y: Math.round(y0 + p.r * cellH) + 2,
                    w: Math.max(1, Math.round(p.cols * packed.cells) - 4),
                    h: Math.max(1, Math.round(p.rows * cellH) - 4),
                    s: packed.cells / Math.max(1, root.screenW)
                };
            }
        }
        for (const g of list) {
            const r = rects[g.index];
            if (r !== undefined) {
                g.x = r.x;
                g.y = r.y;
                g.w = r.w;
                g.h = r.h;
                g.s = r.s;
            } else {
                g.x = 0;
                g.y = 0;
                g.h = 0;
                g.s = 0;
                g.w = 0;
            }
        }
        root.emptyDesktops = list.filter(g => !g.occupied);
        root.groups = list;
    }

    function groupFor(index) {
        return root.groups[index] ?? null;
    }

    // Which desktop group / empty chip sits under a root-space point.
    function groupAt(p) {
        // Use the groups array which has all desktop positions calculated.
        // This is more reliable than tiles.itemAt(i) which may not have all items instantiated.
        for (let i = 0; i < root.groups.length; i++) {
            const g = root.groups[i];
            if (!g || !g.occupied || g.w === 0 || g.h === 0) {
                continue;
            }
            if (p.x >= g.x && p.x < g.x + g.w && p.y >= g.y && p.y < g.y + g.h) {
                return g;
            }
        }
        return null;
    }
    function chipAt(p) {
        // Empty desktops are only shown while dragging; use their real items
        // so the hit area matches what is drawn.
        for (let i = 0; i < chipRepeater.count; i++) {
            const item = chipRepeater.itemAt(i);
            if (item && root.pointInItem(item, p)) {
                return item.modelData;
            }
        }
        return null;
    }
    // The desktop under a point, occupied group or empty chip. Chips win:
    // they are drawn above the grid.
    function desktopAt(p) {
        const c = root.chipAt(p);
        if (c !== null) {
            return c.desktop;
        }
        const g = root.groupAt(p);
        return g !== null ? g.desktop : null;
    }
    function clearDropHover() {
        for (let i = 0; i < tiles.count; i++) {
            const item = tiles.itemAt(i);
            if (item) {
                item.dropHover = false;
            }
        }
        for (let i = 0; i < chipRepeater.count; i++) {
            const item = chipRepeater.itemAt(i);
            if (item) {
                item.dropHover = false;
            }
        }
        root.dragGroup = null;
        root.dragChip = null;
    }
    function pointInItem(item, p) {
        const o = item.mapToItem(root, 0, 0);
        return p.x >= o.x && p.x < o.x + item.width && p.y >= o.y && p.y < o.y + item.height;
    }
    function updateDropTarget() {
        if (root.dragTile === null) {
            return;
        }
        const c = root.chipAt(root.dragPointer);
        const g = c === null ? root.groupAt(root.dragPointer) : null;
        root.dragGroup = g;
        root.dragChip = c;
        for (let i = 0; i < tiles.count; i++) {
            const item = tiles.itemAt(i);
            if (item) {
                item.dropHover = item.group === g;
            }
        }
        for (let i = 0; i < chipRepeater.count; i++) {
            const item = chipRepeater.itemAt(i);
            if (item) {
                item.dropHover = item.modelData === c;
            }
        }
    }
    function beginDrag(tile, pointer, grab) {
        root.dragWindow = tile.window;
        root.dragPointer = pointer;
        root.dragGrab = grab;
        root.dragW = tile.width;
        root.dragH = tile.height;
        root.dragButton = tile.dragButton;
        root.dragReturning = false;
        root.dragActive = true;
        root.dragTile = tile;
        root.updateDropTarget();
    }
    function returnGhost(tile) {
        const o = tile.mapToItem(root, 0, 0);
        root.dragReturnTo = Qt.point(o.x, o.y);
        root.dragActive = false;
        root.dragReturning = true;
        root.clearDropHover();
        returnTimer.restart();
    }
    function clearDrag() {
        root.dragActive = false;
        root.dragReturning = false;
        root.dragTile = null;
        root.clearDropHover();
    }
    Timer {
        id: returnTimer
        interval: 170
        onTriggered: root.clearDrag()
    }

    // Floating windows are not tiled, so dragging one is a real move. The
    // overview works at a scale, hence the division.
    function moveFloating(tile, dx, dy) {
        const w = tile.window;
        const s = tile.tile && tile.tile.scale > 0 ? tile.tile.scale : 1;
        const nx = Math.round(w.x + dx / s);
        const ny = Math.round(w.y + dy / s);
        Qt.callLater(() => {
            w.frameGeometry = Qt.rect(nx, ny, w.frameGeometry.width, w.frameGeometry.height);
        });
    }
    function cloneToDesktop(w, desktop) {
        const list = [];
        for (let i = 0; i < w.desktops.length; i++) {
            list.push(w.desktops[i]);
        }
        if (list.indexOf(desktop) === -1) {
            list.push(desktop);
        }
        w.desktops = list;
    }

    function tileForGroup(g) {
        for (let i = 0; i < tiles.count; i++) {
            const item = tiles.itemAt(i);
            if (item && item.group === g) {
                return item;
            }
        }
        return null;
    }

    // Resolve a released ghost: move, clone, swap, or snap back on failure.
    function finishDrag(tile) {
        if (tile === null || root.dragTile !== tile) {
            return;
        }
        const w = tile.window;
        const g = root.dragGroup;
        const c = root.dragChip;
        const target = g !== null ? g.desktop : (c !== null ? c.desktop : null);
        const source = w.desktops.length > 0 ? w.desktops[0] : null;
        const dx = root.dragPointer.x - tile.pressPointer.x;
        const dy = root.dragPointer.y - tile.pressPointer.y;
        const floating = w.tile === null;

        // Outside every group and chip
        if (target === null) {
            if (floating) {
                // Floating window: real move, no snap-back animation
                root.moveFloating(tile, dx, dy);
                root.clearDrag(); // instant cleanup, no returnGhost
            } else {
                // Tiled window dropped on empty space: snap back to slot
                root.returnGhost(tile);
            }
            return;
        }
        // Same desktop drop - compare by x11DesktopNumber since QtObjects may differ
        function sameDesktop(d1, d2) {
            return d1 && d2 && d1.x11DesktopNumber === d2.x11DesktopNumber;
        }
        if (g !== null && sameDesktop(g.desktop, tile.tile.desktop)) {
            if (floating) {
                // Floating window on same desktop: just move it
                root.moveFloating(tile, dx, dy);
                root.clearDrag();
            } else if (tile.dragButton === Qt.LeftButton && !tile.tile.monoLayout) {
                // Tiled window: swap with window under cursor
                const groupTile = root.tileForGroup(g);
                const under = groupTile === null ? null
                    : groupTile.windowAt(root.dragPointer.x - g.x, root.dragPointer.y - g.y, tile);
                if (under !== null && under !== tile) {
                    root.requestSwap(w, under.window);
                }
                // Swap is instant; just clear drag (ghost vanishes)
                root.clearDrag();
            } else {
                // Monocle or right-click on same desktop: nothing happens, snap back
                root.returnGhost(tile);
            }
            return;
        }
        // Different desktop / empty chip
        if (tile.dragButton === Qt.RightButton) {
            // Right drag clones: window appears on extra desktop
            root.cloneToDesktop(w, target);
            root.clearDrag();
            root.switchAfterDrop(source, target);
        } else {
            // Left drag moves window to new desktop
            Qt.callLater(() => {
                w.desktops = [target];
                root.clearDrag();
                root.switchAfterDrop(source, target);
            });
        }
    }

    function refreshAfterDrag() {
        statesCall.call();
        root.rebuildGroups();
    }

    Timer {
        interval: 1000
        repeat: true
        running: effect.activated
        triggeredOnStart: true
        onTriggered: root.refreshMedia()
    }
    // Replays positions between polls without asking the player again.
    Timer {
        interval: 250
        repeat: true
        running: effect.activated
        onTriggered: root.mediaTick++
    }

    function refreshMedia() {
        mediaCall.call();
    }

    function parseMedia(raw) {
        let data;
        try {
            data = JSON.parse(raw);
        } catch (e) {
            return;
        }
        const players = data.players || [];
        root.mediaAt = data.at || 0;
        // Same player count: update roles in place so a card being dragged at
        // the moment the poll lands is not recreated under the pointer.
        if (players.length === mediaModel.count) {
            for (let i = 0; i < players.length; i++) {
                mediaModel.set(i, players[i]);
            }
            return;
        }
        mediaModel.clear();
        for (const player of players) {
            mediaModel.append(player);
        }
    }

    function mediaCommand(player, action, value) {
        mediaAction.arguments = [player, action, value === undefined ? "" : String(value)];
        mediaAction.call();
    }

    // Next playback speed in the usual ladder, wrapping back to 0.5.
    function nextRate(current) {
        const rates = [0.5, 0.75, 1, 1.25, 1.5, 2];
        for (let i = 0; i < rates.length; i++) {
            if (current < rates[i] - 0.01) {
                return rates[i];
            }
        }
        return rates[0];
    }

    // The player's own window may be open; browsers report the browser pid.
    // Nothing open: hand the track to the desktop instead. The class check is
    // the effect's version of the kdotool fallback in the mpris_dbus script.
    function raisePlayer(player, pid, desktopEntry, url) {
        root.mediaCommand(player, "raise");
        const entry = String(desktopEntry || "").toLowerCase();
        let target = null;
        for (const w of KWinComponents.Workspace.stackingOrder) {
            if (w.minimized || w.skipPager) {
                continue;
            }
            if (pid > 0 && w.pid === pid) {
                target = w;
                break;
            }
            if (entry.length === 0) {
                continue;
            }
            const cls = String(w.resourceClass || "").toLowerCase();
            const desk = String(w.desktopFileName || "").toLowerCase();
            if (cls === entry || desk === entry || desk === entry + ".desktop") {
                target = w;
                break;
            }
        }
        if (target !== null) {
            root.activateWindow(target);
        } else if (url.length > 0) {
            root.mediaCommand(player, "open", url);
            effect.deactivate();
        }
    }

    function formatTime(microseconds) {
        const total = Math.max(0, Math.floor(microseconds / 1000000));
        const hours = Math.floor(total / 3600);
        const minutes = Math.floor((total % 3600) / 60);
        const seconds = total % 60;
        const two = (n) => (n < 10 ? "0" : "") + n;
        return hours > 0 ? hours + ":" + two(minutes) + ":" + two(seconds) : minutes + ":" + two(seconds);
    }

    // KWin's own window menu is asked for after the overview closes; see
    // requestMenu() above. Nothing is drawn in the scene for it.

    Item {
        id: panelTheme
        Kirigami.Theme.inherit: false
        Kirigami.Theme.colorSet: root.colorSet("View")
    }
    Item {
        id: tileTheme
        Kirigami.Theme.inherit: false
        Kirigami.Theme.colorSet: root.colorSet("Window")
    }
    Item {
        id: windowTheme
        Kirigami.Theme.inherit: false
        Kirigami.Theme.colorSet: root.colorSet("Button")
    }
    readonly property color panelColor: panelTheme.Kirigami.Theme.backgroundColor
    readonly property color panelText: panelTheme.Kirigami.Theme.textColor
    readonly property color tileColor: tileTheme.Kirigami.Theme.backgroundColor
    readonly property color tileText: tileTheme.Kirigami.Theme.textColor
    readonly property color windowColor: windowTheme.Kirigami.Theme.backgroundColor
    readonly property color outlineColor: windowTheme.Kirigami.Theme.textColor
    readonly property color accentColor: Kirigami.Theme.highlightColor

    function colorSet(index) {
        switch (index) {
        case 1: return Kirigami.Theme.Window;
        case 2: return Kirigami.Theme.Button;
        case 3: return Kirigami.Theme.Tooltip;
        case 4: return Kirigami.Theme.Complementary;
        case 5: return Kirigami.Theme.Header;
        default: return Kirigami.Theme.View;
        }
    }

    function alpha(c, a) {
        return Qt.rgba(c.r, c.g, c.b, a);
    }

    // SceneView only changes the desktop the effect draws; the D-Bus call
    // moves the real desktop so polonium retiles it in the background.
    function previewTo(desktop) {
        KWinComponents.SceneView.currentDesktop = desktop;
    }

    function switchTo(desktop) {
        if (desktop === null || desktop === undefined) {
            return;
        }
        setDesktopCall.arguments = [desktop.x11DesktopNumber];
        setDesktopCall.call();
        root.previewTo(desktop);
    }

    // A move retiles both desktops; briefly return to the source so the old
    // layout drops the window, then land on the desktop it was dragged to.
    function switchAfterDrop(from, to) {
        root.desktopPicked = true;
        root.hoveredDesktopNumber = to !== null ? to.x11DesktopNumber : 0;
        root.switchTo(from);
        root.dropTargetDesktop = to;
        afterDropTimer.restart();
    }

    Timer {
        id: afterDropTimer
        interval: 200
        onTriggered: {
            const target = root.dropTargetDesktop;
            root.dropTargetDesktop = null;
            if (target !== null) {
                root.switchTo(target);
            }
            root.refreshAfterDrag();
        }
    }

    // The effect cannot move the real pointer; the saver runs ydotool for it.
    KWinComponents.DBusCall {
        id: warpCall
        service: "xyz.vaughanm.polonium"
        path: "/saver"
        dbusInterface: "xyz.vaughanm.polonium"
        method: "WarpPointer"
    }
    // p is in screen coordinates: the click transposed off the tile.
    function warpPointer(p, delay) {
        const x = Math.max(root.screenX, Math.min(root.screenX + root.screenW - 1, Math.round(p.x)));
        const y = Math.max(root.screenY, Math.min(root.screenY + root.screenH - 1, Math.round(p.y)));
        warpCall.arguments = [x, y, delay === undefined ? 0 : delay];
        warpCall.call();
    }

    // On open the pointer is still at its real screen position. Move it into
    // the preview of the desktop and window it is over, so the overview starts
    // where the user came from instead of at an arbitrary screen point.
    function transposeOpenPointer() {
        const d = root.cursorDesktop !== null ? root.cursorDesktop : root.originDesktop;
        if (d === null) {
            return;
        }
        let index = -1;
        for (let i = 0; i < desktops.length; i++) {
            if (desktops[i].x11DesktopNumber === d.x11DesktopNumber) {
                index = i;
                break;
            }
        }
        const g = index >= 0 ? root.groupFor(index) : null;
        if (g === null || g.w <= 0 || g.h <= 0 || !(g.s > 0)) {
            return;
        }
        const p = root.openPointer;
        let x = g.x + (p.x - root.screenX) * g.s;
        let y = g.y + (p.y - root.screenY) * g.s;
        const w = root.cursorWindow;
        if (w !== null) {
            const fx = w.width > 0 ? Math.max(0, Math.min(1, (p.x - w.x) / w.width)) : 0.5;
            const fy = w.height > 0 ? Math.max(0, Math.min(1, (p.y - w.y) / w.height)) : 0.5;
            const id = String(w.internalId);
            const at = g.monoWindows !== undefined ? g.monoWindows.findIndex(c => String(c.internalId) === id) : -1;
            if (at >= 0 && g.previewRects !== null) {
                const r = g.previewRects[at];
                if (r !== undefined) {
                    x = g.x + (r.x + fx * r.w) * g.w;
                    y = g.y + (r.y + fy * r.h) * g.h;
                }
            }
        }
        root.mouseX = x;
        root.mouseY = y;
        root.pointerMoved = false;
        root.openTransposed = true;
        root.warpPointer(Qt.point(root.screenX + x, root.screenY + y), 0);
    }

    function activateWindow(window, desktop, at) {
        if (desktop === undefined && window.desktops && window.desktops.length === 1) {
            desktop = window.desktops[0];
        }
        root.desktopPicked = true;
        if (desktop !== undefined) {
            root.switchTo(desktop);
        }
        if (window.minimized) {
            window.minimized = false;
        }
        KWinComponents.Workspace.activeWindow = window;
        if (root.cfg.TransposeDesktopClick && at !== undefined && at !== null) {
            root.warpPointer(at, 150);
        }
        effect.deactivate();
    }

    // A monocle desktop previews the layout it would tile into: switching to
    // that layout and focusing the window are one request to polonium.
    function activateTiled(window, desktop, at) {
        root.desktopPicked = true;
        if (desktop !== undefined) {
            root.switchTo(desktop);
        }
        requestCall.arguments = [JSON.stringify({ t: "tiled", id: String(window.internalId) })];
        requestCall.call();
        if (root.cfg.TransposeDesktopClick && at !== undefined && at !== null) {
            root.warpPointer(at, 150);
        }
        effect.deactivate();
    }

    // Move keyboard focus to the nearest DESKTOP (not window) in the given
    // direction, based on desktop positions in the overview. No wrap-around.
    function focusDesktopDirection(dx, dy) {
        // Build list of available desktops with their centres.
        const list = [];
        for (let i = 0; i < root.groups.length; i++) {
            const g = root.groups[i];
            const d = (g && g.desktop) ? g.desktop : (root.desktops[i] !== undefined ? root.desktops[i] : null);
            if (d === null) {
                continue;
            }
            if (!(g && g.occupied && g.w > 0 && g.h > 0)) {
                // ignore empty desktops completely
                continue;
            }
            const cx = g.x + g.w / 2;
            const cy = g.y + g.h / 2;
            list.push({ desktop: d, center: Qt.point(cx, cy) });
        }
        if (list.length === 0) {
            return;
        }
        // current
        let cur = null;
        for (const e of list) {
            if (e.desktop === root.currentDesktop || (e.desktop.x11DesktopNumber !== undefined && root.currentDesktop !== null && e.desktop.x11DesktopNumber === root.currentDesktop.x11DesktopNumber)) {
                cur = e;
                break;
            }
        }
        if (cur === null) {
            cur = list[0];
        }
        let best = null;
        let bestScore = Infinity;
        for (const e of list) {
            if (e === cur) {
                continue;
            }
            const px = e.center.x - cur.center.x;
            const py = e.center.y - cur.center.y;
            const primary = dx !== 0 ? px * dx : py * dy;
            if (primary <= 0) {
                continue;
            }
            const secondary = dx !== 0 ? py : px;
            const score = primary + 0.5 * Math.abs(secondary);
            if (score < bestScore) {
                bestScore = score;
                best = e;
            }
        }
        if (best === null) {
            return; // clamp at edge
        }
        root.desktopPicked = true;
        root.switchTo(best.desktop);
        const cx = best.center.x;
        const cy = best.center.y;
        root.mouseX = cx;
        root.mouseY = cy;
        root.warpPointer(Qt.point(root.screenX + cx, root.screenY + cy), 0);
    }

    function stepDesktop(delta) {
        const n = desktops.length;
        if (n < 2) {
            return;
        }
        root.desktopPicked = true;
        const i = desktops.indexOf(currentDesktop);
        switchTo(desktops[((i + delta) % n + n) % n]);
    }

    // Collect every visible window in the overview together with its center in
    // root (screen-local) coordinates, so keyboard navigation can pick the
    // nearest neighbour in a given direction.
    function windowCenters() {
        const wins = KWinComponents.Workspace.stackingOrder;
        const result = [];
        for (let j = 0; j < wins.length; j++) {
            const w = wins[j];
            if (w.skipPager || w.onScreenDisplay || w.notification || w.criticalNotification || w.minimized || w.hidden) {
                continue;
            }
            if (w.output === null || w.output.name !== root.targetScreen.name) {
                continue;
            }
            if (w.pid <= 0 && w.resourceClass === "") {
                continue;
            }
            if (w.activities.length > 0 && w.activities.indexOf(root.activity) === -1) {
                continue;
            }
            const desktop = (w.desktops && w.desktops.length > 0) ? w.desktops[0] : KWinComponents.Workspace.currentDesktop;
            let g = null;
            for (let i = 0; i < root.groups.length; i++) {
                const gg = root.groups[i];
                if (gg && gg.occupied && gg.w > 0 && desktop !== null && gg.desktop.x11DesktopNumber === desktop.x11DesktopNumber) {
                    g = gg;
                    break;
                }
            }
            if (g === null) {
                continue;
            }
            const cx = g.x + (w.x + w.width / 2 - root.screenX) * g.s;
            const cy = g.y + (w.y + w.height / 2 - root.screenY) * g.s;
            result.push({ window: w, center: Qt.point(cx, cy), group: g });
        }
        return result;
    }

    // Move keyboard focus to the nearest window in the given direction
    // (dx,dy in {-1,0,1}) from the currently focused/hovered window, warping
    // the pointer to that window's centre. No wrap; clamps at the edge.
    function focusWindowDirection(dx, dy) {
        const list = root.windowCenters();
        if (list.length === 0) {
            return;
        }
        let cur = null;
        if (root.cursorWindow !== null) {
            for (const e of list) {
                if (String(e.window.internalId) === String(root.cursorWindow.internalId)) {
                    cur = e;
                    break;
                }
            }
        }
        if (cur === null) {
            cur = list[0];
        }
        // Find the current entry's index to start from.
        let best = null;
        let bestScore = Infinity;
        for (const e of list) {
            if (e === cur) {
                continue;
            }
            const px = e.center.x - cur.center.x;
            const py = e.center.y - cur.center.y;
            const primary = dx !== 0 ? px * dx : py * dy;
            if (primary <= 0) {
                continue;
            }
            const secondary = dx !== 0 ? py : px;
            const score = primary + 0.5 * Math.abs(secondary);
            if (score < bestScore) {
                bestScore = score;
                best = e;
            }
        }
        if (best === null) {
            return; // clamp at edge
        }
        root.cursorWindow = best.window;
        root.pointerMoved = true;
        if (best.group.desktop !== null && best.group.desktop !== KWinComponents.Workspace.currentDesktop) {
            root.switchTo(best.group.desktop);
        }
        const cx = best.center.x;
        const cy = best.center.y;
        root.mouseX = cx;
        root.mouseY = cy;
        root.warpPointer(Qt.point(root.screenX + cx, root.screenY + cy), 0);
    }

    Keys.onPressed: (event) => {
        let target = -1;
        switch (event.key) {
        case Qt.Key_Escape:
        case Qt.Key_Return:
        case Qt.Key_Enter:
        case Qt.Key_Space:
            effect.deactivate();
            event.accepted = true;
            return;
        case Qt.Key_Left:
            root.focusDesktopDirection(-1, 0);
            event.accepted = true;
            return;
        case Qt.Key_Right:
            root.focusDesktopDirection(1, 0);
            event.accepted = true;
            return;
        case Qt.Key_Up:
            root.focusDesktopDirection(0, -1);
            event.accepted = true;
            return;
        case Qt.Key_Down:
            root.focusDesktopDirection(0, 1);
            event.accepted = true;
            return;
        case Qt.Key_H:
        case Qt.Key_K:
            root.stepDesktop(-1);
            event.accepted = true;
            return;
        case Qt.Key_L:
        case Qt.Key_J:
            root.stepDesktop(1);
            event.accepted = true;
            return;
        case Qt.Key_0:
            target = 9;
            break;
        default:
            if (event.key >= Qt.Key_1 && event.key <= Qt.Key_9) {
                target = event.key - Qt.Key_1;
            }
        }
        if (target >= 0 && target < desktops.length) {
            root.desktopPicked = true;
            switchTo(desktops[target]);
            event.accepted = true;
        }
    }

    component SharpThumbnail: Item {
        id: thumb

        required property QtObject window
        property real radius: 0

        // at least half the window's pixels so the first downsample stays <= 2x; mipmaps do the rest
        readonly property size textureSize: {
            const winW = window.width * root.dpr;
            const winH = window.height * root.dpr;
            const w = Math.min(winW, Math.max(width * root.dpr * 2, winW / 2));
            const h = Math.min(winH, Math.max(height * root.dpr * 2, winH / 2));
            return Qt.size(Math.max(1, Math.round(w)), Math.max(1, Math.round(h)));
        }

        KWinComponents.WindowThumbnail {
            anchors.fill: parent
            wId: thumb.window.internalId
            layer.enabled: true
            layer.mipmap: true
            layer.smooth: true
            layer.textureSize: thumb.textureSize
            layer.effect: MultiEffect {
                maskEnabled: true
                maskSource: mask
                maskThresholdMin: 0.5
                maskSpreadAtMin: 1.0
            }
        }

        Item {
            id: mask
            anchors.fill: parent
            visible: false
            layer.enabled: true
            layer.smooth: true
            Rectangle {
                anchors.fill: parent
                radius: thumb.radius
            }
        }
    }

    component MediaButton: Item {
        id: mb

        required property string icon
        property bool active: false
        property bool available: true
        signal clicked()

        width: 16
        height: 16
        visible: available

        Kirigami.Icon {
            anchors.centerIn: parent
            width: 11
            height: 11
            source: mb.icon
            color: mb.active ? root.accentColor : root.panelText
        }

        MouseArea {
            anchors.fill: parent
            onClicked: mb.clicked()
        }
    }

    // Small icon button used by a desktop group's layout controls.
    component LayoutButton: Item {
        id: lb

        required property string icon
        signal clicked()

        width: 17
        height: 14

        Kirigami.Icon {
            anchors.centerIn: parent
            width: 11
            height: 11
            source: lb.icon
            color: root.panelText
            opacity: lbHover.containsMouse ? 1 : 0.75
        }

        MouseArea {
            id: lbHover
            anchors.fill: parent
            hoverEnabled: true
            onClicked: lb.clicked()
        }
    }

    // One row of the right-click window menu.
    component MenuItem: Item {
        id: mi

        property string text: ""
        property bool checked: false
        property bool separator: false
        signal clicked()

        width: parent ? parent.width : 0
        height: separator ? 9 : 26

        Rectangle {
            visible: mi.separator
            anchors.verticalCenter: parent.verticalCenter
            x: 4
            width: mi.width - 8
            height: 1
            color: Qt.rgba(1, 1, 1, 0.18)
        }
        Rectangle {
            anchors.fill: parent
            visible: !mi.separator && menuHover.containsMouse
            color: root.alpha(root.accentColor, 0.25)
        }
        Text {
            visible: !mi.separator
            x: 20
            anchors.verticalCenter: parent.verticalCenter
            text: mi.text
            color: root.panelText
            font.pixelSize: 11
        }
        Text {
            visible: mi.checked && !mi.separator
            x: 7
            anchors.verticalCenter: parent.verticalCenter
            text: "✓"
            color: root.panelText
            font.pixelSize: 11
        }

        MouseArea {
            id: menuHover
            anchors.fill: parent
            enabled: !mi.separator
            hoverEnabled: true
            onClicked: mi.clicked()
        }
    }

    component WindowTile: Item {
        id: win

        required property QtObject window
        required property Item tile

        readonly property real s: tile.scale
        readonly property bool mini: window.minimized
        readonly property int slot: mini ? tile.minimizedItems.findIndex(t => String(t.window.internalId) === String(window.internalId)) : -1
        readonly property real chip: tile.chipSize

        // A monocle desktop previews the layout it would tile into; the window
        // is looked up by its index in that desktop's window list.
        readonly property int cellIndex: mini || tile.monoWindows === undefined ? -1 : tile.monoWindows.findIndex(w => String(w.internalId) === String(window.internalId))
        readonly property bool inPreview: !mini && cellIndex >= 0 && tile.previewRects !== null
        readonly property var previewRect: inPreview ? tile.previewRects[cellIndex] : null

        readonly property real wx: (window.x - tile.screen.geometry.x) * s
        readonly property real wy: (window.y - tile.screen.geometry.y) * s
        readonly property real ww: window.width * s
        readonly property real wh: window.height * s
        // the on-screen part of the window, in tile coordinates
        readonly property real initX: Math.round(Math.max(0, wx))
        readonly property real initY: Math.round(Math.max(0, wy))
        readonly property real initW: Math.round(Math.min(wx + ww, tile.width) - initX)
        readonly property real initH: Math.round(Math.min(wy + wh, tile.height) - initY)
        // Preview leaves share the tile with a small gap between them.
        x: mini ? 6 + slot * (chip + 4) : (inPreview ? Math.round(previewRect.x * tile.width) + 2 : initX)
        y: mini ? tile.height - chip - 6 : (inPreview ? Math.round(previewRect.y * tile.height) + 2 : initY)
        width: mini ? chip : (inPreview ? Math.max(1, Math.round(previewRect.w * tile.width) - 4) : Math.max(1, initW))
        height: mini ? chip : (inPreview ? Math.max(1, Math.round(previewRect.h * tile.height) - 4) : Math.max(1, initH))
        readonly property bool shown: !window.skipPager && (window.pid > 0 || window.resourceClass !== "") && (mini ? true : width > 0 && height > 0)
        readonly property bool compact: Math.min(width, height) < 56
        readonly property bool dragging: root.dragTile === win && root.dragActive
        readonly property bool hovered: dragArea.containsMouse
        // Where the real pointer already is when the overview opens.
        readonly property bool initial: !root.pointerMoved && root.cursorWindow !== null && String(root.cursorWindow.internalId) === String(win.window.internalId)
        readonly property real radius: 0

        property int dragButton: Qt.NoButton
        property bool dragged: false
        property point pressPointer: Qt.point(0, 0)
        property point pressGrab: Qt.point(0, 0)

        visible: shown
        clip: true
        // minimized chips sit above everything so they stay reachable
        z: dragging ? 100000 : (mini ? 20000 + slot : window.stackingOrder)
        // A move leaves no copy behind; a clone keeps the original visible.
        opacity: dragging ? (dragButton === Qt.RightButton ? 0.3 : 0) : 1

        Behavior on opacity {
            NumberAnimation { duration: Kirigami.Units.shortDuration }
        }
        Behavior on x {
            NumberAnimation { duration: Kirigami.Units.longDuration; easing.type: Easing.OutCubic }
        }
        Behavior on y {
            NumberAnimation { duration: Kirigami.Units.longDuration; easing.type: Easing.OutCubic }
        }

        Item {
            x: win.mini ? 0 : Math.round(Math.min(0, win.wx))
            y: win.mini ? 0 : Math.round(Math.min(0, win.wy))
            width: win.mini ? win.chip : Math.round(win.ww)
            height: win.mini ? win.chip : Math.round(win.wh)

            Rectangle {
                anchors.fill: parent
                radius: win.radius
                color: root.windowColor
                opacity: win.mini ? 0.7 : 1
            }

            SharpThumbnail {
                anchors.fill: parent
                window: win.window
                radius: win.radius
                visible: !win.window.minimized
            }
        }

        // Icon and title along the bottom of every window — larger and always visible.
        Rectangle {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            height: Math.min(36, win.height)
            visible: win.height > 28
            color: root.alpha(root.panelColor, 0.9)
            radius: win.radius

            Row {
                anchors.fill: parent
                anchors.leftMargin: 8
                anchors.rightMargin: 8
                spacing: 8

                Kirigami.Icon {
                    width: 20
                    height: 20
                    anchors.verticalCenter: parent.verticalCenter
                    source: win.window.icon
                }
                // Windows excluded from screen capture say so next to the icon.
                Kirigami.Icon {
                    width: 20
                    height: 20
                    anchors.verticalCenter: parent.verticalCenter
                    source: "view-hidden"
                    visible: win.window.excludeFromCapture
                }
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    width: Math.max(1, parent.width - 28 - (win.window.excludeFromCapture ? 28 : 0))
                    text: win.window.caption
                    color: root.panelText
                    font.pixelSize: 14
                    font.weight: Font.DemiBold
                    elide: Text.ElideRight
                }
            }
        }

        Kirigami.Icon {
            anchors.centerIn: parent
            // off by default: the live thumbnail already says what the window
            // is, and the glyph hides the content it sits on
            visible: win.window.minimized
            readonly property int iconSize: Math.round(Math.min(win.width, win.height) * (win.mini ? 0.6 : (win.compact ? 0.5 : 0.35)))
            width: iconSize
            height: iconSize
            source: win.window.icon
            opacity: win.window.minimized ? 0.7 : 1
        }

        // Window border: blue, always 2px, stronger on hover or under the real
        // pointer when the overview opens.
        Rectangle {
            anchors.fill: parent
            radius: win.radius
            color: "transparent"
            border.width: win.hovered || win.initial ? 3 : 2
            border.color: win.hovered || win.initial ? root.accentColor : root.alpha(root.accentColor, 0.5)
        }

        MouseArea {
            id: dragArea
            anchors.fill: parent
            hoverEnabled: true
            acceptedButtons: Qt.LeftButton | Qt.MiddleButton | Qt.RightButton
            propagateComposedEvents: false
            onPressed: (mouse) => {
                win.dragButton = mouse.button;
                win.dragged = false;
                const p = win.mapToItem(root, mouse.x, mouse.y);
                win.pressPointer = p;
                const o = win.mapToItem(root, 0, 0);
                win.pressGrab = Qt.point(p.x - o.x, p.y - o.y);
            }
            onPositionChanged: (mouse) => {
                const p = win.mapToItem(root, mouse.x, mouse.y);
                // Hover switching uses the pointer position even when the
                // cursor is over a window thumbnail rather than a tile gap.
                root.mouseX = p.x;
                root.mouseY = p.y;
                root.pointerMoved = true;
                // Middle click closes, so it never drags. A tiled preview is a
                // choice, not a draggable layout.
                if (!(mouse.buttons & (Qt.LeftButton | Qt.RightButton)) || win.inPreview) {
                    return;
                }
                if (!root.dragActive && !win.dragged) {
                    if (Math.abs(p.x - win.pressPointer.x) < 5 && Math.abs(p.y - win.pressPointer.y) < 5) {
                        return;
                    }
                    win.dragged = true;
                    root.beginDrag(win, p, win.pressGrab);
                    return;
                }
                if (root.dragTile === win) {
                    root.dragPointer = p;
                    root.updateDropTarget();
                }
            }
            onReleased: (mouse) => {
                if (root.dragTile === win) {
                    root.dragPointer = win.mapToItem(root, mouse.x, mouse.y);
                    root.finishDrag(win);
                }
            }
            onClicked: (mouse) => {
                if (win.dragged) {
                    mouse.accepted = true;
                    return;
                }
                if (mouse.button === Qt.LeftButton) {
                    // Transpose the click into screen coordinates: a tile is
                    // the whole screen scaled down, so the click's fraction is
                    // the same point on the desktop. Minimized chips sit
                    // outside the preview and get no warp.
                    let at = null;
                    if (!win.mini) {
                        const geo = win.tile.screen.geometry;
                        const p = win.mapToItem(win.tile, mouse.x, mouse.y);
                        at = Qt.point(geo.x + p.x / win.s, geo.y + p.y / win.s);
                    }
                    if (win.inPreview) {
                        root.activateTiled(win.window, win.tile.desktop, at);
                    } else {
                        root.activateWindow(win.window, win.tile.desktop, at);
                    }
                } else if (mouse.button === Qt.MiddleButton) {
                    win.window.closeWindow();
                } else if (mouse.button === Qt.RightButton) {
                    root.openMenu(win.window, win.pressPointer);
                }
            }
        }
    }

    component DesktopTile: Item {
        id: desktopTile

        required property QtObject desktop
        // VirtualDesktopModel exposes the desktop position as this role.
        required property int index
        readonly property QtObject screen: root.targetScreen

        // Where the packer put this desktop, and how polonium tiles it.
        readonly property var group: root.groupFor(index)
        readonly property real scale: group && group.s > 0 ? group.s : 0.001
        readonly property bool occupied: group !== null && group.occupied
        // Monocle has no slots to swap windows between.
        readonly property bool monoLayout: group ? group.mono : false

        readonly property var minimizedItems: {
            const items = [];
            for (let i = 0; i < windows.count; i++) {
                const item = windows.itemAt(i);
                if (item && item.shown && item.window.minimized) {
                    items.push(item);
                }
            }
            return items;
        }
        // Monocle cells and the tiled preview both come from the group, so a
        // delegate only has to look up its own window.
        readonly property var monoWindows: group ? group.monoWindows : []
        readonly property var previewRects: group ? group.previewRects : null
        readonly property bool initial: !root.pointerMoved && root.cursorDesktop !== null && root.cursorDesktop.x11DesktopNumber === desktopTile.desktop.x11DesktopNumber
        // The window under a point in this tile, ignoring one being dragged.
        function windowAt(x, y, ignore) {
            let found = null;
            for (let i = 0; i < windows.count; i++) {
                const item = windows.itemAt(i);
                if (!item || item === ignore || !item.shown || item.window.minimized) {
                    continue;
                }
                const p = item.mapFromItem(desktopTile, x, y);
                if (p.x >= 0 && p.y >= 0 && p.x < item.width && p.y < item.height && (found === null || item.z >= found.z)) {
                    found = item;
                }
            }
            return found;
        }
        readonly property real chipSize: Math.max(24, Math.min(Math.round(height * 0.2), (width - 12) / Math.max(1, minimizedItems.length) - 4))

        property bool dropHover: false
        property bool hovered: desktopHover.containsMouse

        x: group ? group.x : 0
        y: group ? group.y : 0
        width: group ? group.w : 0
        height: group ? group.h : 0
        visible: occupied && width > 0 && height > 0

        // Revealing the top band moves the pack down; slide rather than jump.
        Behavior on x {
            NumberAnimation { duration: Kirigami.Units.longDuration; easing.type: Easing.OutCubic }
        }
        Behavior on y {
            NumberAnimation { duration: Kirigami.Units.longDuration; easing.type: Easing.OutCubic }
        }

        Rectangle {
            anchors.fill: parent
            radius: root.tileRadius
            color: root.alpha(root.tileColor, desktopTile.dropHover ? 0.95 : 0.86)
            border.width: desktopTile.dropHover || desktopTile.hovered || desktopTile.initial ? 2 : 1
            border.color: desktopTile.dropHover || desktopTile.hovered || desktopTile.initial ? root.accentColor : Qt.rgba(1, 1, 1, 0.3)
        }

        Loader {
            anchors.fill: parent
            active: true
            sourceComponent: Item {
                KWinComponents.DesktopBackground {
                    id: wallpaper
                    anchors.fill: parent
                    activity: KWinComponents.Workspace.currentActivity
                    desktop: desktopTile.desktop
                    outputName: desktopTile.screen.name
                    visible: false
                }
                Kirigami.ShadowedTexture {
                    anchors.fill: parent
                    source: wallpaper
                    radius: root.tileRadius
                    color: "transparent"
                }
                Rectangle {
                    anchors.fill: parent
                    radius: root.tileRadius
                    color: root.alpha(root.tileColor, desktopTile.dropHover ? 0.35 : 0.15)
                }
            }
        }

        // Desktop number, top left.
        Rectangle {
            z: 40000
            anchors.left: parent.left
            anchors.top: parent.top
            anchors.margins: 6
            width: numberText.implicitWidth + 12
            height: numberText.implicitHeight + 6
            radius: 0
            color: "black"
            opacity: 0.75

            Text {
                id: numberText
                anchors.centerIn: parent
                text: desktopTile.desktop.x11DesktopNumber
                color: "white"
                font.pixelSize: 11
                font.weight: Font.DemiBold
            }
        }

        MouseArea {
            id: desktopHover
            anchors.fill: parent
            hoverEnabled: true
            acceptedButtons: Qt.LeftButton
            enabled: desktopTile.screen === root.targetScreen && !root.dragActive
            onClicked: (mouse) => {
                root.desktopPicked = true;
                // Transpose the click into the desktop it landed on: the tile
                // is the whole screen scaled down, so the click's fraction is
                // the same point on the real desktop.
                const g = desktopTile.group;
                if (root.cfg.TransposeDesktopClick && g && g.s > 0 && g.w > 0) {
                    root.warpPointer(Qt.point(root.screenX + mouse.x / g.s,
                                              root.screenY + mouse.y / g.s), 150);
                }
                root.switchTo(desktopTile.desktop);
                effect.deactivate();
            }
            // The hover timer reads this; gap moves inside a tile do not reach
            // the window tiles above it.
            onPositionChanged: (mouse) => {
                const p = desktopHover.mapToItem(root, mouse.x, mouse.y);
                root.mouseX = p.x;
                root.mouseY = p.y;
                root.pointerMoved = true;
            }
        }

        Repeater {
            id: windows
            model: KWinComponents.WindowFilterModel {
                activity: KWinComponents.Workspace.currentActivity
                desktop: desktopTile.desktop
                screenName: desktopTile.screen.name
                windowModel: KWinComponents.WindowModel {}
                minimizedWindows: true
                windowType: ~KWinComponents.WindowFilterModel.Dock &
                            ~KWinComponents.WindowFilterModel.Desktop &
                            ~KWinComponents.WindowFilterModel.Notification &
                            ~KWinComponents.WindowFilterModel.CriticalNotification &
                            ~KWinComponents.WindowFilterModel.OnScreenDisplay
            }
            delegate: WindowTile {
                tile: desktopTile
            }
        }
    }

    // KWin paints nothing beneath a SceneEffect, so the chosen backdrop is drawn here.
    Rectangle {
        anchors.fill: parent
        color: root.backdropMode === 3 ? root.panelColor : "black"
    }

    Text {
        anchors.centerIn: parent
        visible: root.groups.length > 0 && root.groups.every(function(g){ return !g.occupied; })
        text: "There is no window in any desktop."
        color: "white"
        font.pointSize: 20
        z: 1000
    }

    Item {
        id: backdrop
        // container keeps the thumbnails' z (stacking order) from competing with the panel
        anchors.fill: parent
        visible: root.backdropMode === 1
        Repeater {
            model: KWinComponents.WindowFilterModel {
                activity: KWinComponents.Workspace.currentActivity
                desktop: root.currentDesktop
                screenName: root.targetScreen.name
                windowModel: KWinComponents.WindowModel {}
                minimizedWindows: false
                // OSDs (volume, brightness) are on all desktops and would also
                // show up as normal windows here.
                windowType: ~KWinComponents.WindowFilterModel.Dock &
                            ~KWinComponents.WindowFilterModel.Desktop &
                            ~KWinComponents.WindowFilterModel.Notification &
                            ~KWinComponents.WindowFilterModel.CriticalNotification &
                            ~KWinComponents.WindowFilterModel.OnScreenDisplay
            }
            KWinComponents.WindowThumbnail {
                required property QtObject window
                wId: window.internalId
                x: window.x - root.screenX
                y: window.y - root.screenY
                width: window.width
                height: window.height
                z: window.stackingOrder
                visible: !window.hidden
            }
        }
    }

    // The current wallpaper as the background. The panel blurs just the part
    // under itself, so the rest of the screen stays sharp.
    Item {
        id: wallpaperBg
        anchors.fill: parent
        visible: root.backdropMode === 2
        KWinComponents.DesktopBackground {
            id: wallpaperSource
            anchors.fill: parent
            activity: KWinComponents.Workspace.currentActivity
            desktop: root.currentDesktop
            outputName: root.targetScreen.name
        }
        Kirigami.ShadowedTexture {
            anchors.fill: parent
            source: wallpaperSource
            color: "transparent"
        }
    }

    MouseArea {
        id: globalMouseArea
        anchors.fill: parent
        hoverEnabled: true
        acceptedButtons: Qt.AllButtons
        onClicked: effect.deactivate()
        // Wheel scrolling disabled in overview
        onWheel: (wheel) => { wheel.accepted = false; }
        onPositionChanged: (mouse) => {
            root.mouseX = mouse.x;
            root.mouseY = mouse.y;
            root.pointerMoved = true;
            if (root.dragActive && root.dragTile) {
                root.dragPointer = mouse;
                root.updateDropTarget();
            }
        }
        onReleased: (mouse) => {
            if (root.dragActive && root.dragTile) {
                root.dragPointer = mouse;
                root.finishDrag(root.dragTile);
            }
        }
    }

    // Full-screen drag tracker: only active during drag, high z to capture all events
    MouseArea {
    }

    // Tooltip removed: window title + icon shown on hover in the tile itself

    ShaderEffectSource {
        id: panelBackdrop
        visible: false
        live: root.backdropBlur
        sourceItem: root.backdropSource
        sourceRect: Qt.rect(0, 0, root.width, root.height)
    }

    MultiEffect {
        visible: root.backdropBlur
        anchors.fill: parent
        source: panelBackdrop
        autoPaddingEnabled: false
        blurEnabled: true
        blur: 1.0
        blurMax: 64
    }

    Item {
        id: panel
        anchors.fill: parent
        opacity: root.openProgress

        // One group per occupied desktop, placed by the packer.
        Repeater {
            id: tiles
            model: KWinComponents.VirtualDesktopModel {}
            delegate: DesktopTile {}
        }

        // Empty desktops only need a number to drop a window on. Each is shaped
        // like the screen so it reads as a desktop, and the font grows with it.
        Row {
            id: chipRow
            visible: root.emptyDesktops.length > 0 && root.chipsShown
            opacity: root.chipsReady ? 1 : 0
            scale: root.chipsReady ? 1 : 0.92
            Behavior on opacity {
                NumberAnimation { duration: 120 }
            }
            Behavior on scale {
                NumberAnimation { duration: 120; easing.type: Easing.OutCubic }
            }
            readonly property real avail: root.screenW - 2 * root.outerPad
            x: root.outerPad + (avail - width) / 2
            y: root.outerPad + (root.topBand - height) / 2
            spacing: root.groupGap

            Repeater {
                id: chipRepeater
                model: root.emptyDesktops
                Rectangle {
                    id: chip
                    required property var modelData
                    readonly property QtObject desktop: modelData.desktop
                    readonly property real aspect: root.screenW / Math.max(1, root.screenH)
                    readonly property real fitW: (chipRow.avail - (root.emptyDesktops.length - 1) * root.groupGap) / Math.max(1, root.emptyDesktops.length)
                    property bool dropHover: false

                    width: Math.min(root.chipRowH * aspect, fitW)
                    height: width / aspect
                    radius: 0
                    color: root.alpha(root.panelColor, chip.dropHover ? 0.9 : 0.55)
                    border.width: chip.dropHover ? 2 : 1
                    border.color: chip.dropHover ? "white" : Qt.rgba(1, 1, 1, 0.45)

                    Text {
                        id: chipLabel
                        anchors.centerIn: parent
                        text: chip.modelData.number
                        color: root.panelText
                        font.pixelSize: Math.max(12, Math.round(chip.height * 0.42))
                        font.weight: Font.DemiBold
                    }

                    MouseArea {
                        anchors.fill: parent
                        hoverEnabled: true
                        acceptedButtons: Qt.LeftButton
                        onClicked: (mouse) => {
                            root.desktopPicked = true;
                            // An empty chip is the screen shape too, so a click
                            // lands at the same relative point on that desktop.
                            if (root.cfg.TransposeDesktopClick && chip.width > 0 && chip.height > 0) {
                                root.warpPointer(Qt.point(
                                    root.screenX + mouse.x / chip.width * root.screenW,
                                    root.screenY + mouse.y / chip.height * root.screenH), 150);
                            }
                            root.switchTo(chip.desktop);
                            effect.deactivate();
                        }
                        // Lets the hover timer reach empty desktops too.
                        onPositionChanged: (mouse) => {
                            const p = mapToItem(root, mouse.x, mouse.y);
                            root.mouseX = p.x;
                            root.mouseY = p.y;
                            root.pointerMoved = true;
                        }
                    }
                }
            }
        }

        // Now playing, always shown in the top-right corner so it never moves
        // the grid. Fed by the saver once a second; the bar interpolates
        // between polls so it moves while the track plays.
        Row {
            id: mediaStrip
            anchors.right: parent.right
            anchors.rightMargin: root.outerPad
            y: root.outerPad
            spacing: 2 * root.spacing

            HoverHandler {
                onHoveredChanged: root.mediaHover = hovered
            }

            Repeater {
                model: mediaModel
                Rectangle {
                    id: mediaCard
                    required property int index
                    required property string player
                    required property string app
                    required property string title
                    required property string artist
                    required property string art
                    required property string url
                    required property string status
                    required property string loop
                    required property real rate
                    required property real position
                    required property real length
                    required property int pid
                    required property string desktopEntry
                    required property string icon
                    required property bool canSeek
                    required property bool canControl
                    required property bool canNext
                    required property bool canPrevious
                    required property bool canShuffle
                    required property bool canLoop
                    required property bool shuffle

                    readonly property real shownPosition: {
                        root.mediaTick;
                        const elapsed = status === "Playing" ? (Date.now() - root.mediaAt) * 1000 * Math.max(0, rate) : 0;
                        return Math.min(length, position + elapsed);
                    }

                    width: Math.min(260, (root.screenW * 0.4 - (mediaModel.count - 1) * mediaStrip.spacing) / Math.max(1, mediaModel.count))
                    height: root.mediaCardHeight
                    radius: 0
                    // Frosted: the panel already blurs the desktop behind it.
                    color: root.alpha(root.panelColor, 0.55)
                    border.width: 1
                    border.color: Qt.rgba(1, 1, 1, 0.12)
                    clip: true

                    // Clicking the card (title, art, anywhere but a control)
                    // raises the player, like mpris_dbus Raise.
                    MouseArea {
                        anchors.fill: parent
                        onClicked: root.raisePlayer(mediaCard.player, mediaCard.pid, mediaCard.desktopEntry, mediaCard.url)
                    }

                    Image {
                        id: cover
                        visible: mediaCard.art.length > 0
                        x: 6
                        y: 6
                        width: root.mediaCardHeight - 12
                        height: width
                        source: mediaCard.art
                        fillMode: Image.PreserveAspectCrop
                        asynchronous: true
                        sourceSize.width: 120
                        sourceSize.height: 120
                    }

                    // The app's own icon, resolved from its .desktop file.
                    Rectangle {
                        visible: mediaCard.icon.length > 0
                        x: cover.x + cover.width - 17
                        y: cover.y + cover.height - 17
                        width: 17
                        height: 17
                        radius: 0
                        color: root.alpha(root.panelColor, 0.8)

                        Kirigami.Icon {
                            anchors.fill: parent
                            anchors.margins: 2
                            source: mediaCard.icon
                        }
                    }

                    Column {
                        x: cover.visible ? cover.x + cover.width + 8 : 8
                        y: 5
                        width: mediaCard.width - x - 6
                        spacing: 1

                        Text {
                            width: parent.width
                            text: mediaCard.title || mediaCard.player
                            elide: Text.ElideRight
                            color: root.panelText
                            font.pixelSize: 12
                            font.weight: Font.DemiBold
                        }

                        Text {
                            width: parent.width
                            text: mediaCard.artist
                            elide: Text.ElideRight
                            color: root.alpha(root.panelText, 0.7)
                            font.pixelSize: 10
                        }

                        // Line 3: progress/total | seekbar | rate
                        Item {
                            width: parent.width
                            height: 16

                            Text {
                                id: timeText
                                anchors.left: parent.left
                                anchors.verticalCenter: parent.verticalCenter
                                text: root.formatTime(mediaCard.shownPosition) + " / " + (mediaCard.length > 0 ? root.formatTime(mediaCard.length) : "--:--")
                                color: root.alpha(root.panelText, 0.6)
                                font.pixelSize: 9
                            }

                            Text {
                                id: rateText
                                anchors.right: parent.right
                                anchors.verticalCenter: parent.verticalCenter
                                text: Math.round(mediaCard.rate * 100) / 100 + "×"
                                color: root.alpha(root.panelText, 0.8)
                                font.pixelSize: 9

                                MouseArea {
                                    anchors.fill: parent
                                    anchors.margins: -4
                                    onClicked: root.mediaCommand(mediaCard.player, "rate", root.nextRate(mediaCard.rate))
                                }
                            }

                            Item {
                                id: seekArea
                                anchors.left: timeText.right
                                anchors.leftMargin: 8
                                anchors.right: rateText.left
                                anchors.rightMargin: 8
                                anchors.verticalCenter: parent.verticalCenter
                                height: 16

                                // Where the pointer is along the bar, -1 when away.
                                readonly property real at: seekMouse.containsMouse && mediaCard.length > 0 ? Math.max(0, Math.min(1, seekMouse.mouseX / width)) : -1

                                Rectangle {
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: parent.width
                                    height: 5
                                    radius: 0
                                    color: root.alpha(root.panelText, 0.2)
                                }

                                Rectangle {
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: mediaCard.length > 0 ? parent.width * Math.min(1, mediaCard.shownPosition / mediaCard.length) : 0
                                    height: 5
                                    radius: 0
                                    color: root.accentColor
                                }

                                // Hover preview: a marker and the time it points at.
                                Rectangle {
                                    visible: seekArea.at >= 0
                                    x: Math.round(seekArea.at * (parent.width - width))
                                    width: 2
                                    height: 9
                                    anchors.verticalCenter: parent.verticalCenter
                                    color: root.panelText
                                }

                                Rectangle {
                                    id: seekTip
                                    visible: seekArea.at >= 0
                                    x: Math.max(0, Math.min(seekArea.width - width, seekArea.at * seekArea.width - width / 2))
                                    y: -height - 3
                                    width: tipText.implicitWidth + 8
                                    height: 14
                                    radius: 0
                                    color: root.alpha(root.panelColor, 0.95)
                                    border.width: 1
                                    border.color: Qt.rgba(1, 1, 1, 0.2)

                                    Text {
                                        id: tipText
                                        anchors.centerIn: parent
                                        text: root.formatTime(seekArea.at * mediaCard.length)
                                        color: root.panelText
                                        font.pixelSize: 9
                                    }
                                }

                                MouseArea {
                                    id: seekMouse
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    enabled: mediaCard.canSeek && mediaCard.length > 0
                                    onClicked: (mouse) => root.mediaCommand(mediaCard.player, "seek", Math.round(mouse.x / width * mediaCard.length))
                                }
                            }
                        }

                        // Line 4: transport buttons
                        Row {
                            spacing: 3

                            MediaButton {
                                icon: "media-skip-backward"
                                available: mediaCard.canPrevious
                                onClicked: root.mediaCommand(mediaCard.player, "previous")
                            }
                            MediaButton {
                                icon: "media-seek-backward"
                                available: mediaCard.canSeek
                                onClicked: root.mediaCommand(mediaCard.player, "seekby", -5000000)
                            }
                            MediaButton {
                                icon: mediaCard.status === "Playing" ? "media-playback-pause" : "media-playback-start"
                                available: mediaCard.canControl
                                onClicked: root.mediaCommand(mediaCard.player, "playpause")
                            }
                            MediaButton {
                                icon: "media-seek-forward"
                                available: mediaCard.canSeek
                                onClicked: root.mediaCommand(mediaCard.player, "seekby", 5000000)
                            }
                            MediaButton {
                                icon: "media-skip-forward"
                                available: mediaCard.canNext
                                onClicked: root.mediaCommand(mediaCard.player, "next")
                            }
                            MediaButton {
                                icon: mediaCard.shuffle ? "media-playlist-shuffle" : "media-playlist-no-shuffle"
                                available: mediaCard.canShuffle
                                active: mediaCard.shuffle
                                onClicked: root.mediaCommand(mediaCard.player, "shuffle")
                            }
                            MediaButton {
                                icon: mediaCard.loop === "Track" ? "media-playlist-repeat-song" : "media-playlist-repeat"
                                available: mediaCard.canLoop
                                active: mediaCard.loop !== "None"
                                onClicked: root.mediaCommand(mediaCard.player, "loop")
                            }
                        }
                    }
                }
            }
        }
    }

    // Right-click window menu, drawn over the overview.
    Item {
        id: menuShade
        anchors.fill: parent
        z: 190000
        visible: root.menuWindow !== null
        MouseArea {
            anchors.fill: parent
            onClicked: root.closeMenu()
        }
    }

    Rectangle {
        id: windowMenu
        z: 200000
        visible: root.menuWindow !== null
        width: 260
        height: menuColumn.implicitHeight + 8
        radius: 0
        color: root.alpha(root.panelColor, 0.97)
        border.width: 1
        border.color: Qt.rgba(1, 1, 1, 0.25)
        x: Math.max(8, Math.min(root.menuAt.x, root.width - width - 8))
        y: Math.max(8, Math.min(root.menuAt.y, root.height - height - 8))

        Column {
            id: menuColumn
            x: 4
            y: 4
            width: parent.width - 8

            MenuItem {
                text: "Above other windows"
                checked: root.menuWindow !== null && root.menuWindow.keepAbove
                onClicked: {
                    const w = root.menuWindow;
                    w.keepAbove = !w.keepAbove;
                    if (w.keepAbove) {
                        w.keepBelow = false;
                    }
                    root.closeMenu();
                }
            }
            MenuItem {
                text: "Below other windows"
                checked: root.menuWindow !== null && root.menuWindow.keepBelow
                onClicked: {
                    const w = root.menuWindow;
                    w.keepBelow = !w.keepBelow;
                    if (w.keepBelow) {
                        w.keepAbove = false;
                    }
                    root.closeMenu();
                }
            }
            MenuItem {
                text: "Hide from screenshare"
                checked: root.menuWindow !== null && root.menuWindow.excludeFromCapture
                onClicked: {
                    const w = root.menuWindow;
                    w.excludeFromCapture = !w.excludeFromCapture;
                    root.closeMenu();
                }
            }
            MenuItem { separator: true }
            MenuItem {
                text: "Configure special application settings…"
                onClicked: root.requestRules(root.menuWindow, true)
            }
            MenuItem {
                text: "Configure special window settings…"
                onClicked: root.requestRules(root.menuWindow, false)
            }
            MenuItem { separator: true }
            // A window on several desktops appears here as copies. Pinning it
            // back to this one replaces the all-desktops toggle then.
            MenuItem {
                visible: root.menuWindow !== null && (root.menuWindow.onAllDesktops || root.menuWindow.desktops.length > 1)
                text: "Show only in current desktop"
                onClicked: {
                    const w = root.menuWindow;
                    w.onAllDesktops = false;
                    w.desktops = [root.currentDesktop];
                    root.closeMenu();
                }
            }
            MenuItem {
                visible: root.menuWindow !== null && !root.menuWindow.onAllDesktops && root.menuWindow.desktops.length <= 1
                text: "Show on all desktops"
                onClicked: {
                    root.menuWindow.onAllDesktops = true;
                    root.closeMenu();
                }
            }
        }
    }

    // Drag ghost: follows the pointer, then flies back to the window's slot.
    Item {
        id: dragGhost
        visible: root.dragTile !== null
        width: root.dragW
        height: root.dragH
        x: root.dragReturning ? root.dragReturnTo.x : root.dragPointer.x - root.dragGrab.x
        y: root.dragReturning ? root.dragReturnTo.y : root.dragPointer.y - root.dragGrab.y
        opacity: 0.9

        Behavior on x {
            enabled: root.dragReturning
            NumberAnimation { duration: 170; easing.type: Easing.OutCubic }
        }
        Behavior on y {
            enabled: root.dragReturning
            NumberAnimation { duration: 170; easing.type: Easing.OutCubic }
        }

        Loader {
            anchors.fill: parent
            active: root.dragTile !== null
            sourceComponent: SharpThumbnail {
                window: root.dragWindow
                radius: root.tileRadius
            }
        }

        Rectangle {
            anchors.fill: parent
            radius: root.tileRadius
            color: root.alpha(root.windowColor, 0.25)
            border.width: 2
            border.color: root.accentColor
        }
    }
}
