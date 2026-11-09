/*
    SPDX-FileCopyrightText: 2026 mj0x0
    SPDX-FileCopyrightText: 2026 Sreinumder
    SPDX-License-Identifier: GPL-2.0-or-later
*/

import QtQuick
import QtQuick.Effects
import org.kde.kirigami as Kirigami
import org.kde.kwin as KWinComponents

// The window strip: one horizontal row of window cards with no stacking, so
// every window on the output reads as side by side no matter how its desktop
// is tiled. Live thumbnails need real window geometry, so the strip clones the
// windows onto a temporary sandbox desktop, makes that desktop current on this
// output and lets the script contract it into a flat row. Closing restores
// every window's desktop list and removes the sandbox.
FocusScope {
    id: root
    focus: true

    readonly property QtObject targetScreen: KWinComponents.SceneView.screen
    readonly property var desktops: KWinComponents.Workspace.desktops
    readonly property string activity: KWinComponents.Workspace.currentActivity
    readonly property QtObject cfg: effect.configuration

    readonly property real screenW: targetScreen.geometry.width
    readonly property real screenH: targetScreen.geometry.height
    readonly property real dpr: targetScreen.devicePixelRatio

    // The card takes a percentage of the usable page width. A single card can
    // reach the full width at 100%.
    readonly property real widthPercent: {
        const v = Number(root.cfg.StripWindowWidth);
        return isFinite(v) && v > 0 ? v : 33;
    }
    readonly property real cardWidth: Math.max(120, Math.min(root.pageW, root.pageW * root.widthPercent / 100))

    // Breathing room between the strip content and every screen edge. The
    // focused card snaps flush to the padded edge, which also keeps its ring
    // clear of the screen border.
    readonly property int outerPad: 12
    readonly property int cardInset: 3
    readonly property int pageGap: 14
    readonly property int columnGap: 10
    readonly property real pageW: root.screenW - root.outerPad * 2
    readonly property real pageH: root.screenH - root.outerPad * 2
    readonly property int titleFont: 14
    readonly property int titleIcon: 20
    readonly property int titlePad: 8
    readonly property int titleRow: Math.max(titleIcon, Math.round(titleFont * 1.4))
    readonly property int titleBand: titleRow + titlePad

    // Cards in visual order. Each entry is a plain object:
    // { id, win, kind, desktopId, x, y, w, h, snapX }
    property var cards: []
    property string cardSignature: ""
    property real contentWidth: root.screenW
    property var desktopStates: ({})
    property string focusId: ""
    property string hoverId: ""
    // Which screen edge the focused card is pinned to: right while moving
    // forward (Right), left while moving back (Left). Pinning to an edge
    // instead of centering keeps the ring fully visible and leaves the rest of
    // the strip as a continuous run of neighbouring windows.
    property bool alignRight: false
    property bool ready: false
    // Set once the user picks a card or pans, so a late state update does not
    // pull the view back to the opening window behind their back.
    property bool userMoved: false
    property bool committed: false
    property QtObject openWindow: null
    // The effect may be started with a view per output. Only the one on KWin's
    // active output owns the strip; the others stay transparent, so opening
    // the strip on one screen never contracts every screen.
    property bool stripOwned: false
    // KWin only applies tile geometry to a desktop that is current on an
    // output. The strip therefore clones every window onto a temporary desktop,
    // switches this output to it, and lets the script tile that one desktop as
    // a flat row. Cloning keeps each window's real desktop list, so restoring is
    // exact and a crash leaves the user's desktops intact.
    readonly property string sandboxPrefix: "Folonium Strip Sandbox"
    property string sandboxDesktopId: ""
    property string openDesktopId: ""
    property var sandboxWindows: []
    property int sandboxAttempts: 0
    property bool closing: false
    property QtObject targetWindow: null
    property string targetDesktopId: ""
    // Workspace.activeScreen has no change notification, so this is a function
    // rather than a binding: a binding would warn at load and never update.
    // Older builds may not expose activeScreen to effect QML; in that case the
    // effect's single view is already the active screen.
    function isActiveScreen() {
        const active = KWinComponents.Workspace.activeScreen;
        if (active === null || active === undefined) {
            return true;
        }
        return root.targetScreen !== null && active.name === root.targetScreen.name;
    }

    function desktopById(id) {
        if (id === null || id === undefined || id === "") {
            return null;
        }
        const list = KWinComponents.Workspace.desktops;
        for (let i = 0; i < list.length; i++) {
            if (String(list[i].id) === String(id)) {
                return list[i];
            }
        }
        return null;
    }

    function screenDesktop() {
        if (root.targetScreen !== null && root.targetScreen !== undefined && typeof KWinComponents.Workspace.currentDesktopForScreen === "function") {
            const d = KWinComponents.Workspace.currentDesktopForScreen(root.targetScreen);
            if (d !== null && d !== undefined) {
                return d;
            }
        }
        return KWinComponents.Workspace.currentDesktop;
    }

    function setScreenDesktop(desktop) {
        if (desktop === null || desktop === undefined) {
            return;
        }
        if (root.targetScreen !== null && root.targetScreen !== undefined && typeof KWinComponents.Workspace.setCurrentDesktopForScreen === "function") {
            KWinComponents.Workspace.setCurrentDesktopForScreen(desktop, root.targetScreen);
        } else {
            KWinComponents.Workspace.currentDesktop = desktop;
        }
    }

    function firstRealDesktop(exclude) {
        const list = KWinComponents.Workspace.desktops;
        for (let i = 0; i < list.length; i++) {
            if (exclude === null || exclude === undefined || String(list[i].id) !== String(exclude.id)) {
                return list[i];
            }
        }
        return null;
    }

    function isSandbox(d) {
        return d !== null && d !== undefined && String(d.name || "").indexOf(root.sandboxPrefix) === 0;
    }

    readonly property bool shown: root.ready && effect.activated && root.stripOwned

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

    Component.onCompleted: Qt.callLater(() => {
        // Recover a sandbox left behind if the effect was killed while open.
        if (root.isActiveScreen()) {
            root.cleanupStaleSandboxes();
        }
        root.ready = true;
        // If the delegate is created after the effect has already started,
        // the activatedChanged signal is already behind us.
        if (effect.activated) {
            root.enterStrip();
        }
    })

    // The effect lives in KWin's effect engine and cannot tile real windows,
    // so the script is told which output and which sandbox desktop the strip is
    // using. The sandbox id is what keeps the script from ever touching the
    // user's real desktops.
    KWinComponents.DBusCall {
        id: stripOpenCall
        service: "xyz.vaughanm.folonium"
        path: "/saver"
        dbusInterface: "xyz.vaughanm.folonium"
        method: "SetStripOpen"
        onFailed: () => {}
    }
    function setStripOpen(open, desktopId) {
        stripOpenCall.arguments = [
            open,
            root.targetScreen.name,
            Math.round(root.widthPercent),
            open ? root.sandboxDesktopId : (desktopId || "")
        ];
        stripOpenCall.call();
    }

    // After the clones are removed, ask the script to put the windows back into
    // their real desktops' tiles. KWin defers the geometry of a hidden desktop,
    // but restoring the tile membership makes switching to it instant.
    KWinComponents.DBusCall {
        id: rebuildCall
        service: "xyz.vaughanm.folonium"
        path: "/saver"
        dbusInterface: "xyz.vaughanm.folonium"
        method: "SetRequest"
        onFailed: () => {}
    }
    function requestRebuild() {
        rebuildCall.arguments = [JSON.stringify({ t: "rebuild", output: root.targetScreen.name })];
        rebuildCall.call();
    }

    // The script removes the sandbox a poll later, after KWin has applied the
    // clones' desktop changes. Removing it from the effect while the views are
    // being destroyed makes KWin rebuild with a desktop that no longer exists.
    KWinComponents.DBusCall {
        id: sandboxCall
        service: "xyz.vaughanm.folonium"
        path: "/saver"
        dbusInterface: "xyz.vaughanm.folonium"
        method: "SetRequest"
        onFailed: () => {}
    }
    function requestSandboxRemove(sandbox) {
        sandboxCall.arguments = [JSON.stringify({
            t: "stripSandbox",
            ids: sandbox !== null ? [String(sandbox.id)] : [],
            output: root.targetScreen.name
        })];
        sandboxCall.call();
    }

    // The effect's own removeDesktop call is dropped while KWin is tearing the
    // effect down, so sandbox removal goes through KWin's D-Bus interface,
    // which the compositor handles outside the effect call stack.
    KWinComponents.DBusCall {
        id: sandboxRemoveCall
        service: "org.kde.KWin"
        path: "/VirtualDesktopManager"
        dbusInterface: "org.kde.KWin.VirtualDesktopManager"
        method: "removeDesktop"
        onFailed: () => {}
    }
    function removeSandboxDesktop(sandbox) {
        if (sandbox === null || sandbox === undefined) {
            return;
        }
        sandboxRemoveCall.arguments = [String(sandbox.id)];
        sandboxRemoveCall.call();
    }

    KWinComponents.DBusCall {
        id: statesCall
        service: "xyz.vaughanm.folonium"
        path: "/saver"
        dbusInterface: "xyz.vaughanm.folonium"
        method: "GetStates"
        onFinished: (returnValue) => root.parseStates(returnValue.length > 0 ? returnValue[0] : "")
        onFailed: () => {}
    }

    Timer {
        id: stripPoll
        interval: 400
        repeat: true
        running: effect.activated && root.stripOwned && !root.closing
        triggeredOnStart: true
        onTriggered: {
            statesCall.call();
            // Keep refreshing: a stale entry is treated as closed, so this is
            // also what recovers the real layout if the poll loop ever stalls.
            root.setStripOpen(true);
            root.rebuild();
        }
    }

    Timer {
        id: sandboxTimer
        interval: 60
        repeat: false
        onTriggered: root.attachSandbox()
    }

    // KWin drops a virtual desktop created from inside the effect activation
    // call stack. Let the effect finish starting before asking for the sandbox.
    Timer {
        id: sandboxStartTimer
        interval: 50
        repeat: false
        onTriggered: root.startSandbox()
    }

    // KWin applies the new tile geometry after the desktop switch, so refresh
    // the card sizes once more after it has settled.
    Timer {
        id: geometryTimer
        interval: 180
        repeat: false
        onTriggered: root.rebuild()
    }

    function enterStrip() {
        if (root.stripOwned || root.closing || !root.isActiveScreen()) {
            return;
        }
        // A killed effect can leave a sandbox behind. Remove it before saving
        // the desktop the user is really on.
        root.cleanupStaleSandboxes();
        root.stripOwned = true;
        root.closing = false;
        root.openWindow = KWinComponents.Workspace.activeWindow;
        const openDesktop = root.screenDesktop();
        root.openDesktopId = openDesktop !== null && openDesktop !== undefined ? String(openDesktop.id) : "";
        root.committed = false;
        root.userMoved = false;
        root.alignRight = false;
        root.hoverId = "";
        root.focusId = root.openWindow !== null ? String(root.openWindow.internalId) : "";
        root.sandboxDesktopId = "";
        root.sandboxWindows = [];
        root.sandboxAttempts = 0;
        sandboxStartTimer.restart();
        root.setStripOpen(true);
        root.statesCallNow();
        root.rebuild();
        root.focusActive();
        root.forceActiveFocus();
    }

    function findSandbox() {
        const list = KWinComponents.Workspace.desktops;
        for (let i = list.length - 1; i >= 0; i--) {
            if (root.isSandbox(list[i])) {
                return list[i];
            }
        }
        return null;
    }

    function startSandbox() {
        if (!root.stripOwned || root.closing) {
            return;
        }
        let sandbox = root.findSandbox();
        if (sandbox === null) {
            // KWin silently ignores desktop creation from inside the effect
            // activation call stack, so this runs from a timer and retries.
            if (root.sandboxAttempts >= 12) {
                // No sandbox means no contraction. The strip still works, it
                // just shows the real desktops exactly as they are.
                root.setStripOpen(true);
                return;
            }
            root.sandboxAttempts += 1;
            const list = KWinComponents.Workspace.desktops;
            KWinComponents.Workspace.createDesktop(list.length, root.sandboxPrefix);
            sandbox = root.findSandbox();
            if (sandbox === null) {
                sandboxTimer.restart();
                return;
            }
        }
        root.sandboxDesktopId = String(sandbox.id);
        const wins = KWinComponents.Workspace.stackingOrder;
        const entries = [];
        for (let i = 0; i < wins.length; i++) {
            const w = wins[i];
            if (!root.isCandidate(w)) {
                continue;
            }
            const saved = [];
            let hasSandbox = false;
            for (let j = 0; j < w.desktops.length; j++) {
                saved.push(String(w.desktops[j].id));
                if (String(w.desktops[j].id) === String(sandbox.id)) {
                    hasSandbox = true;
                }
            }
            if (!w.onAllDesktops && !hasSandbox) {
                const next = [];
                for (let j = 0; j < w.desktops.length; j++) {
                    next.push(w.desktops[j]);
                }
                next.push(sandbox);
                w.desktops = next;
            }
            entries.push({ win: w, saved: saved, allDesktops: w.onAllDesktops });
        }
        root.sandboxWindows = entries;
        root.setScreenDesktop(sandbox);
        root.setStripOpen(true);
        root.rebuild();
        geometryTimer.restart();
    }

    function attachSandbox() {
        if (!root.stripOwned || root.closing) {
            return;
        }
        root.startSandbox();
    }

    function leaveStrip() {
        if (!root.stripOwned) {
            return;
        }
        root.closing = true;
        root.stripOwned = false;
        const target = root.committed ? root.targetWindow : root.openWindow;
        const desktopId = root.committed ? root.targetDesktopId : root.openDesktopId;
        root.closeSandbox(target, desktopId);
        root.committed = false;
        root.targetWindow = null;
        root.targetDesktopId = "";
        root.userMoved = false;
    }

    function closeSandbox(target, desktopId) {
        const sandbox = root.desktopById(root.sandboxDesktopId);
        root.setStripOpen(false, sandbox !== null ? String(sandbox.id) : "");
        const entries = root.sandboxWindows;
        root.sandboxWindows = [];
        if (sandbox === null || entries.length === 0) {
            root.finishSandboxClose(null, target, desktopId);
            return;
        }
        for (let i = 0; i < entries.length; i++) {
            const entry = entries[i];
            const w = entry.win;
            if (w === null || w === undefined || !controllerWindowExists(w) || entry.allDesktops) {
                continue;
            }
            const next = [];
            let removed = false;
            for (let j = 0; j < w.desktops.length; j++) {
                if (String(w.desktops[j].id) === String(sandbox.id)) {
                    removed = true;
                } else {
                    next.push(w.desktops[j]);
                }
            }
            if (!removed) {
                continue;
            }
            if (next.length === 0) {
                for (let j = 0; j < entry.saved.length; j++) {
                    const d = root.desktopById(entry.saved[j]);
                    if (d !== null) {
                        next.push(d);
                    }
                }
            }
            if (next.length > 0) {
                w.desktops = next;
            }
        }
        // Put the real desktops back into their tiles before switching, so the
        // first frame the user sees already has the real layout.
        root.finishSandboxClose(sandbox, target, desktopId);
    }

    function finishSandboxClose(sandbox, target, desktopId) {
        let desktop = root.desktopById(desktopId);
        if (desktop === null || (sandbox !== null && String(desktop.id) === String(sandbox.id))) {
            desktop = root.firstRealDesktop(sandbox);
        }
        if (desktop !== null) {
            root.setScreenDesktop(desktop);
        }
        if (target !== null && target !== undefined && controllerWindowExists(target)) {
            if (target.minimized) {
                target.minimized = false;
            }
            KWinComponents.Workspace.activeWindow = target;
        }
        root.sandboxDesktopId = "";
        root.closing = false;
        root.openWindow = null;
        root.openDesktopId = "";
        if (sandbox !== null) {
            // Removing the desktop through the script lets KWin settle the
            // window desktop changes first; the effect's views are already
            // being torn down and cannot wait for that.
            root.requestSandboxRemove(sandbox);
        } else {
            root.requestRebuild();
        }
        root.rebuild();
    }

    function cleanupStaleSandboxes() {
        const list = KWinComponents.Workspace.desktops;
        const stale = [];
        for (let i = 0; i < list.length; i++) {
            if (root.isSandbox(list[i])) {
                stale.push(list[i]);
            }
        }
        for (let i = 0; i < stale.length; i++) {
            const sandbox = stale[i];
            const wins = KWinComponents.Workspace.stackingOrder;
            for (let j = 0; j < wins.length; j++) {
                const w = wins[j];
                if (w.onAllDesktops) {
                    continue;
                }
                let has = false;
                const next = [];
                for (let k = 0; k < w.desktops.length; k++) {
                    if (String(w.desktops[k].id) === String(sandbox.id)) {
                        has = true;
                    } else {
                        next.push(w.desktops[k]);
                    }
                }
                if (has && next.length > 0) {
                    w.desktops = next;
                }
            }
            const current = root.screenDesktop();
            if (current !== null && current !== undefined && String(current.id) === String(sandbox.id)) {
                const fallback = root.firstRealDesktop(sandbox);
                if (fallback !== null) {
                    root.setScreenDesktop(fallback);
                }
            }
            root.removeSandboxDesktop(sandbox);
            // Let the saver forget this crash-leftover sandbox's state too.
            root.setStripOpen(false, String(sandbox.id));
        }
    }

    Connections {
        target: effect
        function onActivatedChanged() {
            if (effect.activated) {
                root.enterStrip();
            } else {
                root.leaveStrip();
            }
        }
    }

    function controllerWindowExists(window) {
        if (window === null) {
            return false;
        }
        const wins = KWinComponents.Workspace.stackingOrder;
        for (let i = 0; i < wins.length; i++) {
            if (String(wins[i].internalId) === String(window.internalId)) {
                return true;
            }
        }
        return false;
    }

    function statesCallNow() {
        statesCall.call();
    }

    function parseStates(raw) {
        try {
            root.desktopStates = JSON.parse(raw) || {};
        } catch (e) {
            root.desktopStates = {};
        }
        root.rebuild();
    }

    // Windows that are not desktop contents: panels, popups, notifications,
    // OSDs, splash screens and anything on another output or activity.
    function isCandidate(w) {
        if (w.output === null || w.output.name !== root.targetScreen.name) {
            return false;
        }
        if (w.skipPager || w.skipTaskbar || w.hidden) {
            return false;
        }
        if (w.onScreenDisplay || w.notification || w.criticalNotification) {
            return false;
        }
        if (w.dock || w.desktopWindow || w.splash || w.popupMenu || w.tooltip || w.popupWindow) {
            return false;
        }
        if (w.pid <= 0 && w.resourceClass === "") {
            return false;
        }
        if (w.activities.length > 0 && w.activities.indexOf(root.activity) === -1) {
            return false;
        }
        return w.width > 0 && w.height > 0;
    }

    // A floating or minimized window smaller than roughly 200 px is noise: a
    // picker, a hint, a progress popup. Tiled windows are never dropped here;
    // the strip lays their cards out itself.
    function importantEnough(w) {
        return Math.min(w.width, w.height) >= 200;
    }

    // A window belongs to exactly one desktop group, even when KWin lists it
    // on several desktops. All-desktop windows belong to the current desktop.
    function desktopIndexFor(w, current) {
        const currentId = current !== null && current !== undefined ? current.id : "";
        if (w.onAllDesktops || w.desktops.length === 0) {
            for (let i = 0; i < root.desktops.length; i++) {
                if (root.desktops[i].id === currentId) {
                    return i;
                }
            }
            return root.desktops.length > 0 ? 0 : -1;
        }
        const id = w.desktops[0].id;
        for (let i = 0; i < root.desktops.length; i++) {
            if (root.desktops[i].id === id) {
                return i;
            }
        }
        return -1;
    }

    function byPosition(a, b) {
        if (Math.abs(a.x - b.x) > 4) {
            return a.x - b.x;
        }
        return a.y - b.y;
    }

    // A card is the window's own aspect ratio plus the title band underneath.
    // WindowThumbnail always letterboxes a window inside its item, so a tall
    // card around a landscape window wasted most of the card on empty space and
    // left the picture small. Matching the card to the window fills it instead.
    function cardHeightFor(w, cardW, maxH) {
        const ratio = w.width > 0 && w.height > 0 ? w.height / w.width : 9 / 16;
        const thumb = Math.max(60, Math.min(maxH - root.titleBand, Math.round(cardW * ratio)));
        return Math.max(root.titleBand + 60, thumb + root.titleBand);
    }

    function rebuild() {
        const wins = KWinComponents.Workspace.stackingOrder;
        // While the sandbox is current, all-desktop windows still belong to
        // the desktop the strip was opened from, not to the sandbox.
        const current = root.desktopById(root.openDesktopId) || KWinComponents.Workspace.currentDesktop;
        const buckets = [];
        for (let i = 0; i < root.desktops.length; i++) {
            buckets.push([]);
        }
        for (let i = 0; i < wins.length; i++) {
            const w = wins[i];
            if (!root.isCandidate(w)) {
                continue;
            }
            const di = root.desktopIndexFor(w, current);
            if (di >= 0) {
                buckets[di].push(w);
            }
        }

        const list = [];
        let cursorX = root.outerPad;
        for (let i = 0; i < root.desktops.length; i++) {
            const all = buckets[i];
            if (all.length === 0) {
                continue;
            }
            const d = root.desktops[i];
            const key = JSON.stringify({ d: d.id, a: root.activity, o: root.targetScreen.name });
            let state = {};
            try {
                state = JSON.parse(root.desktopStates[key] || "{}");
            } catch (e) {
                state = {};
            }
            const order = Array.isArray(state.order) ? state.order.map(String) : [];
            const engine = state.engine === "kwin" ? "kwin" : "custom";

            const byId = {};
            for (let j = 0; j < all.length; j++) {
                byId[String(all[j].internalId)] = all[j];
            }

            // Tiled windows in engine order. Minimized windows keep their tile
            // but move to the end of the row with the other minimized cards.
            let tiledOrder = [];
            if (engine === "custom" && order.length > 0) {
                for (let j = 0; j < order.length; j++) {
                    tiledOrder.push(byId[order[j]] || null);
                }
            } else {
                const tiled = [];
                for (let j = 0; j < all.length; j++) {
                    const w = all[j];
                    if (w.minimized) {
                        continue;
                    }
                    // With the script's state not in yet, a KWin tile is still
                    // the reliable sign of a tiled window in both engines.
                    if (w.tile === null || w.tile === undefined) {
                        continue;
                    }
                    tiled.push(w);
                }
                tiled.sort(root.byPosition);
                tiledOrder = tiled;
            }

            const tiledIds = {};
            for (let j = 0; j < tiledOrder.length; j++) {
                if (tiledOrder[j] !== null) {
                    tiledIds[String(tiledOrder[j].internalId)] = true;
                }
            }

            // Every window is one card in a single horizontal row. The
            // desktop's own layout only decides which windows are tiled and in
            // what order; cards are never stacked, so all windows read as side
            // by side however the desktop looks.
            const cardW = Math.max(1, Math.round(root.cardWidth) - root.cardInset * 2);
            const cardH = Math.max(1, Math.round(root.pageH) - root.cardInset * 2);
            const step = root.cardWidth + root.columnGap;
            const pageCards = [];

            for (let j = 0; j < tiledOrder.length; j++) {
                const w = tiledOrder[j];
                if (w === null || w.minimized) {
                    continue;
                }
                const h = root.cardHeightFor(w, cardW, cardH);
                const x = pageCards.length * step;
                pageCards.push({
                    id: String(w.internalId),
                    win: w,
                    kind: "tiled",
                    desktopId: d.id,
                    x: x + root.cardInset,
                    y: Math.round(root.outerPad + (root.pageH - h) / 2),
                    w: cardW,
                    h,
                    snapX: x + root.cardWidth / 2
                });
            }

            const floating = [];
            for (let j = 0; j < all.length; j++) {
                const w = all[j];
                if (w.minimized || tiledIds[String(w.internalId)]) {
                    continue;
                }
                if (root.importantEnough(w)) {
                    floating.push(w);
                }
            }
            for (let j = 0; j < floating.length; j++) {
                const w = floating[j];
                const h = root.cardHeightFor(w, cardW, cardH);
                const x = pageCards.length * step;
                pageCards.push({
                    id: String(w.internalId),
                    win: w,
                    kind: "floating",
                    desktopId: d.id,
                    x: x + root.cardInset,
                    y: Math.round(root.outerPad + (root.pageH - h) / 2),
                    w: cardW,
                    h,
                    snapX: x + root.cardWidth / 2
                });
            }

            const minimized = [];
            for (let j = 0; j < all.length; j++) {
                const w = all[j];
                if (w.minimized && root.importantEnough(w)) {
                    minimized.push(w);
                }
            }
            for (let j = 0; j < minimized.length; j++) {
                const w = minimized[j];
                const h = Math.min(cardH, Math.max(96, root.titleBand * 2.4));
                const x = pageCards.length * step;
                pageCards.push({
                    id: String(w.internalId),
                    win: w,
                    kind: "minimized",
                    desktopId: d.id,
                    x: x + root.cardInset,
                    y: Math.round(root.outerPad + (root.pageH - h) / 2),
                    w: cardW,
                    h: Math.round(h),
                    snapX: x + root.cardWidth / 2
                });
            }

            if (pageCards.length > 0) {
                if (list.length > 0) {
                    cursorX += root.pageGap;
                }
                for (let j = 0; j < pageCards.length; j++) {
                    const card = pageCards[j];
                    card.x += cursorX;
                    card.snapX += cursorX;
                    list.push(card);
                }
                cursorX += pageCards.length * root.cardWidth + (pageCards.length - 1) * root.columnGap;
            }
        }

        // Leave the same padded edge after the last card that the first card
        // has before it, so right-pinning the final card is not clamped short.
        root.contentWidth = Math.max(root.screenW, cursorX + root.cardInset + root.outerPad);

        const signature = list.map((c) => c.id + "@" + Math.round(c.x) + "," + Math.round(c.y) + "," + Math.round(c.w) + "," + Math.round(c.h) + "#" + c.kind).join("|");
        if (signature !== root.cardSignature) {
            root.cardSignature = signature;
            root.cards = list;
            if (!root.userMoved) {
                Qt.callLater(() => root.scrollToFocus(false));
            }
        }

        // Keep the highlight on a window that still exists. If the opening
        // window vanished, fall back to whatever is active now, then the first
        // card.
        if (root.indexById(root.focusId) < 0) {
            const active = KWinComponents.Workspace.activeWindow;
            const activeId = active !== null ? String(active.internalId) : "";
            if (root.indexById(activeId) >= 0) {
                root.focusId = activeId;
            } else if (list.length > 0) {
                root.focusId = list[0].id;
            } else {
                root.focusId = "";
            }
        }
    }

    function indexById(id) {
        for (let i = 0; i < root.cards.length; i++) {
            if (root.cards[i].id === id) {
                return i;
            }
        }
        return -1;
    }

    function cardById(id) {
        const i = root.indexById(id);
        return i >= 0 ? root.cards[i] : null;
    }

    function focusActive() {
        let id = root.focusId;
        if (root.indexById(id) < 0) {
            const active = KWinComponents.Workspace.activeWindow;
            if (active !== null && root.indexById(String(active.internalId)) >= 0) {
                id = String(active.internalId);
            } else if (root.cards.length > 0) {
                id = root.cards[0].id;
            }
        }
        if (id !== root.focusId) {
            root.focusId = id;
        }
        root.scrollToFocus(false);
    }

    function moveFocus(delta) {
        if (root.cards.length === 0) {
            return;
        }
        let i = root.indexById(root.focusId);
        if (i < 0) {
            i = delta > 0 ? 0 : root.cards.length - 1;
        } else {
            i = Math.max(0, Math.min(root.cards.length - 1, i + delta));
        }
        root.userMoved = true;
        root.focusId = root.cards[i].id;
        // Moving forward pins the arriving card to the right edge; moving back
        // pins it to the left edge, so the focused window always touches a
        // screen edge instead of floating in the middle.
        root.alignRight = delta > 0;
        root.scrollToCard(root.cards[i], true);
    }

    function scrollToFocus(animate) {
        const card = root.cardById(root.focusId);
        if (card !== null) {
            root.scrollToCard(card, animate);
        }
    }

    readonly property real maxContentX: Math.max(0, root.contentWidth - root.width)

    function scrollToCard(card, animate) {
        if (card === null || card === undefined) {
            return;
        }
        // Pin the focused card to the padded left or right edge. x/width are in
        // content coordinates, so subtract the viewport edge the card should
        // land on.
        const target = root.alignRight
            ? card.x + card.w - (root.width - root.outerPad)
            : card.x - root.outerPad;
        const clamped = Math.max(0, Math.min(root.maxContentX, target));
        if (animate) {
            snapAnim.stop();
            snapAnim.to = clamped;
            snapAnim.start();
        } else {
            view.contentX = clamped;
        }
    }

    function snapNearest() {
        if (root.cards.length === 0) {
            return;
        }
        const center = view.contentX + view.width / 2;
        let best = null;
        let bestDistance = Infinity;
        for (let i = 0; i < root.cards.length; i++) {
            const card = root.cards[i];
            const distance = Math.abs(card.snapX - center);
            if (distance < bestDistance - 0.5) {
                bestDistance = distance;
                best = card;
            }
        }
        if (best !== null) {
            // Panning also moves the highlight, and the card keeps the edge it
            // is already nearest to so the snap is the shortest one.
            root.focusId = best.id;
            root.alignRight = best.snapX > center;
            root.scrollToCard(best, true);
        }
    }

    // Click or Enter: switch to the desktop if needed, restore the window if
    // it was minimized, focus it for real and close. Nothing warps the pointer;
    // a strip card is not a real screen position.
    function activateCard(card) {
        if (card === null || card === undefined) {
            return;
        }
        const win = card.win;
        root.focusId = card.id;
        root.committed = true;
        root.targetWindow = win;
        root.targetDesktopId = card.desktopId;
        // Restoration removes the sandbox, switches to the window's real
        // desktop, and focuses it there. Doing that here would focus it while
        // the sandbox is still current.
        effect.deactivate();
    }

    function activateFocused() {
        const card = root.cardById(root.focusId);
        if (card !== null) {
            root.activateCard(card);
        }
    }

    Keys.onPressed: (event) => {
        switch (event.key) {
        case Qt.Key_Escape:
            effect.deactivate();
            event.accepted = true;
            return;
        case Qt.Key_Return:
        case Qt.Key_Enter:
        case Qt.Key_Space:
            root.activateFocused();
            event.accepted = true;
            return;
        case Qt.Key_Left:
            root.moveFocus(-1);
            event.accepted = true;
            return;
        case Qt.Key_Right:
            root.moveFocus(1);
            event.accepted = true;
            return;
        case Qt.Key_Home:
            if (root.cards.length > 0) {
                root.userMoved = true;
                root.focusId = root.cards[0].id;
                root.alignRight = false;
                root.scrollToCard(root.cards[0], true);
            }
            event.accepted = true;
            return;
        case Qt.Key_End:
            if (root.cards.length > 0) {
                const last = root.cards[root.cards.length - 1];
                root.userMoved = true;
                root.focusId = last.id;
                root.alignRight = true;
                root.scrollToCard(last, true);
            }
            event.accepted = true;
            return;
        default:
            break;
        }
    }

    // A live KWin thumbnail, masked to the card's rounded corners. Shared by
    // every strip card, exactly as the grid overview's window tiles use it.
    component SharpThumbnail: Item {
        id: thumb

        required property QtObject window
        property real radius: 0

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

    // Wallpaper, then a dim wash, then the strip. Cards are opaque; the wash
    // just keeps the real desktops from competing with them.
    Item {
        anchors.fill: parent
        visible: root.shown
        KWinComponents.DesktopBackground {
            anchors.fill: parent
            activity: root.activity
            desktop: KWinComponents.SceneView.currentDesktop
            outputName: root.targetScreen.name
        }
        Rectangle {
            anchors.fill: parent
            color: root.alpha(root.panelColor, 0.72)
        }
    }

    NumberAnimation {
        id: snapAnim
        target: view
        property: "contentX"
        duration: 180
        easing.type: Easing.OutCubic
    }

    Timer {
        id: wheelSnap
        interval: 150
        onTriggered: root.snapNearest()
    }

    // Only holds the scrolled content. Input is handled by the overlay below:
    // a Flickable consumes the press before its card children can turn it into
    // a click, which made cards keyboard-focusable but not clickable.
    Flickable {
        id: view
        anchors.fill: parent
        visible: root.shown
        contentWidth: root.contentWidth
        contentHeight: height
        boundsBehavior: Flickable.StopAtBounds
        flickableDirection: Flickable.HorizontalFlick
        interactive: false
        clip: true

        Item {
            id: stripContent
            width: view.contentWidth
            height: view.height

            Repeater {
                model: root.cards
                delegate: Rectangle {
                    id: card

                    required property var modelData

                    readonly property bool focused: modelData.id === root.focusId
                    readonly property bool hovered: modelData.id === root.hoverId
                    readonly property bool onScreen: card.x + card.width > view.contentX - root.screenW && card.x < view.contentX + view.width + root.screenW
                    readonly property bool minimized: modelData.kind === "minimized"

                    x: modelData.x
                    y: modelData.y
                    width: modelData.w
                    height: modelData.h
                    radius: 6
                    clip: true
                    color: root.windowColor
                    z: focused ? 100 : 1

                    // The picture fills the card above the title band. The card
                    // already has the window's aspect ratio, so the live
                    // thumbnail uses the whole area instead of letterboxing.
                    SharpThumbnail {
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.top: parent.top
                        height: Math.max(1, card.height - (card.height >= root.titleBand ? root.titleBand : 0))
                        window: card.modelData.win
                        radius: card.radius
                        visible: card.onScreen && !card.minimized && !card.modelData.win.minimized
                    }

                    Kirigami.Icon {
                        anchors.centerIn: parent
                        visible: card.minimized
                        width: Math.max(24, Math.min(card.width, card.height) * 0.3)
                        height: width
                        source: card.modelData.win.icon
                        opacity: 0.8
                    }

                    // Icon and title along the bottom of every card, exactly
                    // like the desktop overview's window tiles.
                    Rectangle {
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.bottom: parent.bottom
                        height: Math.min(root.titleBand, card.height)
                        visible: card.height >= root.titleBand
                        color: root.alpha(root.panelColor, 0.9)
                        radius: card.radius

                        Row {
                            anchors.fill: parent
                            anchors.leftMargin: root.titlePad
                            anchors.rightMargin: root.titlePad
                            spacing: root.titlePad

                            Kirigami.Icon {
                                width: root.titleIcon
                                height: root.titleIcon
                                anchors.verticalCenter: parent.verticalCenter
                                source: card.modelData.win.icon
                            }
                            Kirigami.Icon {
                                width: root.titleIcon
                                height: root.titleIcon
                                anchors.verticalCenter: parent.verticalCenter
                                source: "view-hidden"
                                visible: card.modelData.win.excludeFromCapture
                            }
                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                width: Math.max(1, parent.width - root.titleIcon - root.titlePad - (card.modelData.win.excludeFromCapture ? root.titleIcon + root.titlePad : 0))
                                text: card.modelData.win.caption
                                color: root.panelText
                                font.pixelSize: root.titleFont
                                font.weight: Font.DemiBold
                                elide: Text.ElideRight
                            }
                        }
                    }

                    // The ring is a sibling on top of the thumbnail and title
                    // band. A Rectangle border would be painted underneath its
                    // children, which made the focus ring invisible whenever
                    // the live picture filled the card.
                    Rectangle {
                        anchors.fill: parent
                        radius: card.radius
                        color: "transparent"
                        border.width: card.focused ? 3 : (card.hovered ? 2 : 1)
                        border.color: card.focused ? root.accentColor : (card.hovered ? root.alpha(root.accentColor, 0.85) : root.alpha(root.outlineColor, 0.35))

                        Behavior on border.width {
                            NumberAnimation { duration: Kirigami.Units.shortDuration }
                        }
                    }
                }
            }
        }
    }

    // One input surface above the row: drag pans, a tap activates the card
    // under the pointer, and the wheel scrolls. Keeping it outside the
    // Flickable is what lets taps reach the cards at all.
    MouseArea {
        id: stripInput
        anchors.fill: parent
        visible: root.shown
        hoverEnabled: true
        acceptedButtons: Qt.LeftButton
        cursorShape: pressed ? Qt.ClosedHandCursor : (root.hoverId !== "" ? Qt.PointingHandCursor : Qt.ArrowCursor)

        property real pressX: 0
        property real pressContentX: 0
        property bool dragged: false

        function cardAt(px, py) {
            const cx = view.contentX + px;
            for (let i = 0; i < root.cards.length; i++) {
                const card = root.cards[i];
                if (cx >= card.x && cx <= card.x + card.w && py >= card.y && py <= card.y + card.h) {
                    return card;
                }
            }
            return null;
        }

        onPressed: (mouse) => {
            snapAnim.stop();
            pressX = mouse.x;
            pressContentX = view.contentX;
            dragged = false;
        }
        onPositionChanged: (mouse) => {
            const card = cardAt(mouse.x, mouse.y);
            root.hoverId = card !== null ? card.id : "";
            if (!pressed) {
                return;
            }
            const dx = mouse.x - pressX;
            if (!dragged && Math.abs(dx) > 6) {
                dragged = true;
                root.userMoved = true;
            }
            if (dragged) {
                view.contentX = Math.max(0, Math.min(root.maxContentX, pressContentX - dx));
            }
        }
        onReleased: (mouse) => {
            if (dragged) {
                root.snapNearest();
            } else {
                const card = cardAt(mouse.x, mouse.y);
                if (card !== null) {
                    root.activateCard(card);
                } else {
                    effect.deactivate();
                }
            }
            dragged = false;
        }
        onExited: root.hoverId = ""
        onWheel: (wheel) => {
            const pixel = wheel.pixelDelta;
            const angle = wheel.angleDelta;
            let delta = 0;
            if (pixel.x !== 0 || pixel.y !== 0) {
                delta = pixel.x + pixel.y;
            } else {
                delta = (angle.x + angle.y) * 0.7;
            }
            view.contentX = Math.max(0, Math.min(root.maxContentX, view.contentX - delta));
            root.userMoved = true;
            root.hoverId = "";
            wheelSnap.restart();
            wheel.accepted = true;
        }
    }

    // A small "no windows" hint, so an empty output does not look broken.
    Text {
        anchors.centerIn: parent
        visible: root.shown && root.cards.length === 0
        text: i18nd("kwin_effect_foloniumoverview", "No windows on this output")
        color: root.panelText
        font.pixelSize: 18
        opacity: 0.7
    }
}
