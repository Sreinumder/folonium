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
    readonly property int chipRowH: 28
    readonly property string activity: KWinComponents.Workspace.currentActivity

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
    property Item dragGroup: null
    property Item dragChip: null
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

    // Right click opens this window menu; it lives in the effect so the
    // overview can keep showing the change it makes.
    property QtObject menuWindow: null
    property point menuAt: Qt.point(0, 0)

    readonly property int tileRadius: 8

    // What sits behind the panel: live desktop, wallpaper or a flat colour.
    readonly property int backdropMode: cfg.Backdrop
    readonly property Item backdropSource: backdropMode === 1 ? backdrop : (backdropMode === 2 ? wallpaperBg : null)
    readonly property bool backdropBlur: backdropSource !== null

    // The media strip is collapsed by default; click the toggle button to expand.
    readonly property int mediaCardHeight: 90
    readonly property int mediaSpace: root.mediaExpanded && mediaModel.count > 0 ? mediaCardHeight + spacing : 0
    property bool mediaExpanded: false
    property int mediaTick: 0
    property real mediaAt: 0

    property bool ready: false
    property real openProgress: ready && effect.activated ? 1 : 0
    Component.onCompleted: Qt.callLater(() => {
        root.ready = true;
        root.rebuildGroups();
        // Rapidly cycle through all desktops to ensure they're tiled, then return.
        root.primeAllDesktops();
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
            if (!effect.activated || root.dragActive) return;
            const mousePos = Qt.point(root.mouseX, root.mouseY);
            const g = root.groupAt(mousePos);
            if (g && g.desktop !== root.currentDesktop) {
                root.switchTo(g.desktop);
            }
        }
    }
    Timer {
        id: desktopSwitchTimer
        interval: 30
        repeat: false
        onTriggered: {
            root.primeAllDesktops();
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
                statesCall.call();
                root.rebuildGroups();
            }
        }
    }

    // One group per occupied desktop: the output-shaped desktop, or for a
    // monocle desktop the windows side by side at their real proportions.
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
            let count = 0;
            let sumW = 0;
            let maxH = 0;
            for (const w of wins) {
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
                count++;
                if (!w.minimized) {
                    sumW += w.width;
                    maxH = Math.max(maxH, w.height);
                }
            }
            const mono = state.mono === true && sumW > 0;
            list.push({
                index: i,
                desktop: d,
                number: d.x11DesktopNumber,
                occupied: count > 0,
                mono: mono,
                layout: state.layout || "",
                count: count,
                w: mono ? sumW : root.screenW,
                h: mono ? Math.max(1, maxH) : root.screenH
            });
        }
        return list;
    }

    // Shelf-pack every group at one common scale. The layout is "max scale
    // possible", so search for the biggest scale whose rows still fit.
    function packGroups(occupied) {
        const availW = root.screenW - 2 * root.outerPad;
        const availH = root.screenH - 2 * root.outerPad - root.chipRowH - root.mediaSpace;
        // Desktop order, so desktop 1 is the first group at the top.
        const ordered = occupied.slice();
        let lo = 0.001;
        let hi = 1;
        let best = null;
        for (let iter = 0; iter < 22; iter++) {
            const s = (lo + hi) / 2;
            const rows = [];
            let row = null;
            let ok = true;
            for (const g of ordered) {
                const gw = g.w * s;
                const gh = g.h * s;
                if (gw > availW) {
                    ok = false;
                    break;
                }
                if (row !== null && row.w + root.groupGap + gw > availW) {
                    rows.push(row);
                    row = null;
                }
                if (row === null) {
                    row = { items: [], w: 0, h: 0 };
                }
                row.items.push({ g: g, w: gw, h: gh });
                row.w += (row.items.length > 1 ? root.groupGap : 0) + gw;
                row.h = Math.max(row.h, gh);
            }
            if (ok && row !== null) {
                rows.push(row);
            }
            let totalH = 0;
            for (const r of rows) {
                totalH += r.h;
            }
            totalH += root.groupGap * Math.max(0, rows.length - 1);
            if (ok && rows.length > 0 && totalH <= availH) {
                lo = s;
                best = { s: s, rows: rows, h: totalH };
            } else {
                hi = s;
            }
        }
        return best;
    }

    function rebuildGroups() {
        const list = root.collectGroups();
        const occupied = list.filter(g => g.occupied);
        const packed = root.packGroups(occupied);
        const rects = {};
        if (packed !== null && packed.s > 0) {
            let y = root.outerPad + root.chipRowH + Math.max(0, (root.screenH - 2 * root.outerPad - root.chipRowH - root.mediaSpace - packed.h) / 2);
            for (const row of packed.rows) {
                let x = (root.screenW - row.w) / 2;
                for (const item of row.items) {
                    rects[item.g.index] = {
                        x: Math.round(x),
                        y: Math.round(y + (row.h - item.h) / 2),
                        w: Math.round(item.w),
                        h: Math.round(item.h),
                        s: packed.s
                    };
                    x += item.w + root.groupGap;
                }
                y += row.h + root.groupGap;
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
        // Empty desktops are chips at the top; use emptyDesktops array
        for (let i = 0; i < root.emptyDesktops.length; i++) {
            const c = root.emptyDesktops[i];
            // Chips are centered horizontally at the top
            const chipX = (root.screenW - root.emptyDesktops.length * 28 - (root.emptyDesktops.length - 1) * root.groupGap) / 2 + i * (28 + root.groupGap);
            const chipY = root.outerPad;
            const chipW = 28;
            const chipH = root.chipRowH;
            if (p.x >= chipX && p.x < chipX + chipW && p.y >= chipY && p.y < chipY + chipH) {
                return c;
            }
        }
        return null;
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
        const g = root.groupAt(root.dragPointer);
        const c = g === null ? root.chipAt(root.dragPointer) : null;
        root.dragGroup = g;
        root.dragChip = c;
        for (let i = 0; i < tiles.count; i++) {
            const item = tiles.itemAt(i);
            if (item) {
                item.dropHover = item === g;
            }
        }
        for (let i = 0; i < chipRepeater.count; i++) {
            const item = chipRepeater.itemAt(i);
            if (item) {
                item.dropHover = item === c;
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

    // Resolve a released ghost: move, clone, swap, or snap back on failure.
    function finishDrag(tile) {
        const w = tile.window;
        const g = root.dragGroup;
        const c = root.dragChip;
        const target = g !== null ? g.desktop : (c !== null ? c.desktop : null);
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
        // Same desktop drop
        if (g !== null && g.desktop === tile.tile.desktop) {
            if (floating) {
                // Floating window on same desktop: just move it
                root.moveFloating(tile, dx, dy);
                root.clearDrag();
            } else if (tile.dragButton === Qt.LeftButton && !tile.tile.monoLayout) {
                // Tiled window: swap with window under cursor
                const p = g.mapFromItem(root, root.dragPointer.x, root.dragPointer.y);
                const under = g.windowAt(p.x, p.y, tile);
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
            root.refreshAfterDrag();
        } else {
            // Left drag moves window to new desktop
            Qt.callLater(() => {
                w.desktops = [target];
                root.clearDrag();
                root.refreshAfterDrag();
            });
        }
    }

    function refreshAfterDrag() {
        statesCall.call();
        root.rebuildGroups();
        root.primeAllDesktops();
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
    // Nothing open: hand the track to the desktop instead.
    function raisePlayer(player, pid, url) {
        let target = null;
        for (const w of KWinComponents.Workspace.stackingOrder) {
            if (pid > 0 && w.pid === pid && !w.minimized && !w.skipPager) {
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
        Kirigami.Theme.colorSet: root.colorSet(root.cfg.PanelColorSet)
    }
    Item {
        id: tileTheme
        Kirigami.Theme.inherit: false
        Kirigami.Theme.colorSet: root.colorSet(root.cfg.TileColorSet)
    }
    Item {
        id: windowTheme
        Kirigami.Theme.inherit: false
        Kirigami.Theme.colorSet: root.colorSet(root.cfg.WindowColorSet)
    }
    readonly property color panelColor: panelTheme.Kirigami.Theme.backgroundColor
    readonly property color panelText: panelTheme.Kirigami.Theme.textColor
    readonly property color tileColor: tileTheme.Kirigami.Theme.backgroundColor
    readonly property color tileText: tileTheme.Kirigami.Theme.textColor
    readonly property color windowColor: windowTheme.Kirigami.Theme.backgroundColor
    readonly property color outlineColor: windowTheme.Kirigami.Theme.textColor
    readonly property color accentColor: {
        switch (cfg.ActiveBorderColor) {
        case 1: return Kirigami.Theme.focusColor;
        case 2: return Kirigami.Theme.linkColor;
        case 3: return Kirigami.Theme.textColor;
        default: return Kirigami.Theme.highlightColor;
        }
    }

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

    function switchTo(desktop) {
        root.KWinComponents.SceneView.currentDesktop = desktop;
    }

    function primeAllDesktops() {
        const original = root.currentDesktop;
        const list = root.desktops;
        if (list.length < 2) return;
        let i = 0;
        function next() {
            if (i >= list.length) {
                root.switchTo(original);
                return;
            }
            root.switchTo(list[i]);
            i++;
            // Use a short timer to let KWin process the desktop change and emit signals
            desktopSwitchTimer.interval = 30;
            desktopSwitchTimer.running = true;
        }
        Qt.callLater(next);
    }

    function activateWindow(window) {
        if (window.minimized) {
            window.minimized = false;
        }
        KWinComponents.Workspace.activeWindow = window;
        effect.deactivate();
    }

    function stepDesktop(delta) {
        const n = desktops.length;
        if (n < 2) {
            return;
        }
        const i = desktops.indexOf(currentDesktop);
        switchTo(desktops[((i + delta) % n + n) % n]);
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
        case Qt.Key_Up:
        case Qt.Key_H:
        case Qt.Key_K:
            root.stepDesktop(-1);
            event.accepted = true;
            return;
        case Qt.Key_Right:
        case Qt.Key_Down:
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
            switchTo(desktops[target]);
            event.accepted = true;
        }
        // Debug: press 'D' to test groupAt at current mouse position
        if (event.key === Qt.Key_D) {
            const pos = Qt.point(root.mouseX, root.mouseY);
            const g = root.groupAt(pos);
            const tileCount = root.tiles.count;
            // Switch to desktop based on tile count to verify tiles exist
            if (tileCount > 0) {
                root.switchTo(root.desktops[1]); // Desktop 2 if tiles exist
            } else {
                root.switchTo(root.desktops[0]); // Desktop 1 if no tiles
            }
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

        width: 20
        height: 20
        visible: available

        Kirigami.Icon {
            anchors.centerIn: parent
            width: 14
            height: 14
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

        // Monocle puts every window of a desktop in one full-size tile, so the
        // overview splits that tile into a column per window.
        readonly property var twins: mini ? [] : tile.monoItems
        readonly property int twinCount: twins.length
        readonly property bool stacked: twinCount > 1
        readonly property int twinIndex: {
            if (!stacked) {
                return 0;
            }
            for (let i = 0; i < twins.length; i++) {
                const other = twins[i];
                if (other && other.window && String(other.window.internalId) === String(window.internalId)) {
                    return i;
                }
            }
            return 0;
        }
        // Monocle stacks every window of the desktop on the same screen area, so
        // the overview lays the group out as columns at the windows' own widths.
        readonly property real stackOffset: {
            if (!stacked) {
                return 0;
            }
            let x = 0;
            for (let i = 0; i < twinIndex; i++) {
                const other = twins[i];
                x += other && other.window ? other.window.width * s : 0;
            }
            return x;
        }

        readonly property real wx: (window.x - tile.screen.geometry.x) * s
        readonly property real wy: (window.y - tile.screen.geometry.y) * s
        readonly property real ww: window.width * s
        readonly property real wh: window.height * s
        // the on-screen part of the window, in tile coordinates
        readonly property real initX: Math.round(stacked ? stackOffset : Math.max(0, wx))
        readonly property real initY: Math.round(stacked ? Math.max(0, (tile.height - wh) / 2) : Math.max(0, wy))
        readonly property real initW: Math.round(stacked ? ww : Math.min(wx + ww, tile.width) - initX)
        readonly property real initH: Math.round(stacked ? wh : Math.min(wy + wh, tile.height) - initY)
        readonly property bool shown: !window.skipPager && (window.pid > 0 || window.resourceClass !== "") && (mini ? root.cfg.ShowMinimized : initW > 0 && initH > 0)
        readonly property bool compact: Math.min(width, height) < 56
        readonly property bool dragging: root.dragTile === win && root.dragActive
        readonly property bool hovered: dragArea.containsMouse
        readonly property real radius: Math.max(2, 18 * s)

        property int dragButton: Qt.NoButton
        property bool dragged: false
        property point pressPointer: Qt.point(0, 0)
        property point pressGrab: Qt.point(0, 0)

        x: mini ? 6 + slot * (chip + 4) : initX
        y: mini ? tile.height - chip - 6 : initY
        width: mini ? chip : Math.max(1, initW)
        height: mini ? chip : Math.max(1, initH)
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
            x: win.mini || win.stacked ? 0 : Math.round(Math.min(0, win.wx))
            y: win.mini || win.stacked ? 0 : Math.round(Math.min(0, win.wy))
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
            visible: root.cfg.ShowAppIcon || win.window.minimized
            readonly property int iconSize: Math.round(Math.min(win.width, win.height) * (win.mini ? 0.6 : (win.compact ? 0.5 : 0.35)))
            width: iconSize
            height: iconSize
            source: win.window.icon
            opacity: win.window.minimized ? 0.7 : 1
        }

        // Window border: blue, always 2px, stronger on hover.
        Rectangle {
            anchors.fill: parent
            radius: win.radius
            color: "transparent"
            border.width: 2
            border.color: win.hovered ? root.accentColor : root.alpha(root.accentColor, 0.5)
        }

        MouseArea {
            id: dragArea
            anchors.fill: parent
            hoverEnabled: true
            acceptedButtons: Qt.LeftButton | Qt.MiddleButton | Qt.RightButton
            onPressed: (mouse) => {
                win.dragButton = mouse.button;
                win.dragged = false;
                const p = win.mapToItem(root, mouse.x, mouse.y);
                win.pressPointer = p;
                const o = win.mapToItem(root, 0, 0);
                win.pressGrab = Qt.point(p.x - o.x, p.y - o.y);
            }
            onPositionChanged: (mouse) => {
                // Middle click closes, so it never drags.
                if (!(mouse.buttons & (Qt.LeftButton | Qt.RightButton))) {
                    return;
                }
                const p = win.mapToItem(root, mouse.x, mouse.y);
                if (!root.dragActive) {
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
                if (root.dragTile !== win) {
                    return;
                }
                root.dragPointer = win.mapToItem(root, mouse.x, mouse.y);
                root.finishDrag(win);
            }
            onClicked: (mouse) => {
                if (win.dragged) {
                    return;
                }
                if (mouse.button === Qt.LeftButton) {
                    root.activateWindow(win.window);
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
        readonly property string layoutText: group ? group.layout : ""
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
        // In monocle every window shares one tile; list them so each delegate
        // can take its own column. Window properties keep this loop free of a
        // binding cycle through item.shown.
        readonly property var monoItems: {
            if (!monoLayout) {
                return [];
            }
            const items = [];
            for (let i = 0; i < windows.count; i++) {
                const item = windows.itemAt(i);
                if (item && !item.window.minimized && !item.window.skipPager) {
                    items.push(item);
                }
            }
            return items;
        }
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

        Rectangle {
            anchors.fill: parent
            radius: root.tileRadius
            color: root.alpha(root.tileColor, desktopTile.dropHover ? 0.95 : 0.86)
            border.width: desktopTile.dropHover || desktopTile.hovered ? 2 : 1
            border.color: desktopTile.dropHover || desktopTile.hovered ? root.accentColor : Qt.rgba(1, 1, 1, 0.3)
        }

        Loader {
            anchors.fill: parent
            active: root.cfg.WallpaperTiles
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

        // Desktop number then the tiling polonium runs there, top left — larger.
        Rectangle {
            z: 40000
            anchors.left: parent.left
            anchors.top: parent.top
            anchors.margins: 6
            width: labelRow.implicitWidth + 12
            height: labelRow.implicitHeight + 6
            radius: 4
            color: "black"
            opacity: 0.75

            Row {
                id: labelRow
                anchors.centerIn: parent
                spacing: 6

                Text {
                    text: desktopTile.desktop.x11DesktopNumber
                    color: "white"
                    font.pixelSize: 11
                    font.weight: Font.DemiBold
                }
                // Layout text at the end
                Text {
                    visible: desktopTile.layoutText.length > 0
                    text: desktopTile.layoutText + (desktopTile.monoLayout ? "  ·  mono" : "")
                    color: "white"
                    font.pixelSize: 10
                }
            }
        }

        MouseArea {
            id: desktopHover
            anchors.fill: parent
            hoverEnabled: true
            acceptedButtons: Qt.LeftButton
            enabled: desktopTile.screen === root.targetScreen && !root.dragActive
            onClicked: {
                root.switchTo(desktopTile.desktop);
                effect.deactivate();
            }
            // onEntered doesn't fire when item appears under mouse, so use containsMouse binding
            onContainsMouseChanged: {
                if (containsMouse && !root.dragActive) {
                    root.switchTo(desktopTile.desktop);
                }
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

    Rectangle {
        anchors.fill: parent
        color: "black"
        opacity: root.openProgress * root.cfg.BackdropDim / 100
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
        }
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
        blurMax: root.cfg.BlurRadius
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

        // Empty desktops only need a number to drop a window on.
        Row {
            id: chipRow
            visible: root.emptyDesktops.length > 0 && root.dragActive
            anchors.horizontalCenter: parent.horizontalCenter
            y: root.outerPad + (root.chipRowH - height) / 2
            spacing: root.groupGap

            Repeater {
                id: chipRepeater
                model: root.emptyDesktops
                Rectangle {
                    id: chip
                    required property var modelData
                    readonly property QtObject desktop: modelData.desktop
                    property bool dropHover: false

                    width: Math.max(28, chipLabel.implicitWidth + 18)
                    height: 26
                    radius: 6
                    color: root.alpha(root.panelColor, chip.dropHover ? 0.9 : 0.55)
                    border.width: chip.dropHover ? 2 : 1
                    border.color: chip.dropHover ? "white" : Qt.rgba(1, 1, 1, 0.45)

                    Text {
                        id: chipLabel
                        anchors.centerIn: parent
                        text: chip.modelData.number
                        color: root.panelText
                        font.pixelSize: 11
                    }

                    MouseArea {
                        anchors.fill: parent
                        acceptedButtons: Qt.LeftButton
                        onClicked: {
                            root.switchTo(chip.desktop);
                            effect.deactivate();
                        }
                    }
                }
            }
        }

        // Now playing. Fed by the saver once a second; the bar interpolates
        // between polls so it moves while the track plays.
        Row {
            id: mediaStrip
            visible: root.mediaSpace > 0
            anchors.horizontalCenter: parent.horizontalCenter
            y: root.screenH - root.outerPad - root.mediaCardHeight
            spacing: 2 * root.spacing

            // Media toggle button (show/hide media panel)
            Rectangle {
                id: mediaToggleBtn
                width: 32
                height: 32
                radius: 16
                color: root.alpha(root.panelColor, 0.8)
                border.width: 1
                border.color: Qt.rgba(1, 1, 1, 0.2)
                MouseArea {
                    anchors.fill: parent
                    onClicked: root.mediaExpanded = !root.mediaExpanded
                }
                Kirigami.Icon {
                    anchors.centerIn: parent
                    width: 16
                    height: 16
                    source: root.mediaExpanded ? "view-list-tree" : "view-list-details"
                    color: root.panelText
                }
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

                    width: Math.min(420, (root.screenW - 2 * root.outerPad - (mediaModel.count - 1) * mediaStrip.spacing) / Math.max(1, mediaModel.count))
                    height: root.mediaCardHeight
                    radius: 6
                    color: root.alpha(root.panelText, 0.08)
                    clip: true

                    // Clicking anywhere brings the player's window forward via MPRIS Raise.
                    MouseArea {
                        anchors.fill: parent
                        onClicked: root.mediaCommand(mediaCard.player, "raise", "")
                    }

                    Image {
                        id: cover
                        visible: mediaCard.art.length > 0
                        x: 12
                        y: 12
                        width: 100
                        height: 100
                        source: mediaCard.art
                        fillMode: Image.PreserveAspectCrop
                        asynchronous: true
                        sourceSize.width: 200
                        sourceSize.height: 200
                    }

                    Column {
                        x: cover.visible ? 124 : 12
                        y: 12
                        width: mediaCard.width - x - 12
                        spacing: 4

                        Text {
                            width: parent.width
                            text: mediaCard.title || mediaCard.player
                            elide: Text.ElideRight
                            color: root.panelText
                            font.pixelSize: 14
                            font.weight: Font.DemiBold
                        }

                        Text {
                            width: parent.width
                            text: mediaCard.artist
                            elide: Text.ElideRight
                            color: root.alpha(root.panelText, 0.7)
                            font.pixelSize: 11
                        }

                        // Line 3: progress/total | seekbar | rate
                        Item {
                            width: parent.width
                            height: 20

                            Text {
                                id: timeText
                                anchors.left: parent.left
                                anchors.verticalCenter: parent.verticalCenter
                                text: root.formatTime(mediaCard.shownPosition) + " / " + (mediaCard.length > 0 ? root.formatTime(mediaCard.length) : "--:--")
                                color: root.alpha(root.panelText, 0.6)
                                font.pixelSize: 10
                            }

                            Text {
                                id: rateText
                                anchors.right: parent.right
                                anchors.verticalCenter: parent.verticalCenter
                                text: Math.round(mediaCard.rate * 100) / 100 + "×"
                                color: root.alpha(root.panelText, 0.8)
                                font.pixelSize: 10

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

                                Rectangle {
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: parent.width
                                    height: 6
                                    radius: 3
                                    color: root.alpha(root.panelText, 0.2)
                                }

                                Rectangle {
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: mediaCard.length > 0 ? parent.width * Math.min(1, mediaCard.shownPosition / mediaCard.length) : 0
                                    height: 6
                                    radius: 3
                                    color: root.accentColor
                                }

                                MouseArea {
                                    anchors.fill: parent
                                    enabled: mediaCard.canSeek && mediaCard.length > 0
                                    onClicked: (mouse) => root.mediaCommand(mediaCard.player, "seek", Math.round(mouse.x / width * mediaCard.length))
                                }
                            }
                        }

                        // Line 4: transport buttons
                        Row {
                            spacing: 4

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
        radius: 6
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
            MenuItem {
                text: "Show on all desktops"
                checked: root.menuWindow !== null && root.menuWindow.onAllDesktops
                onClicked: {
                    const w = root.menuWindow;
                    w.onAllDesktops = !w.onAllDesktops;
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
