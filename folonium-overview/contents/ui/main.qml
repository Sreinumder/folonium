/*
    SPDX-FileCopyrightText: 2026 mj0x0
    SPDX-FileCopyrightText: 2026 Sreinumder
    SPDX-License-Identifier: GPL-2.0-or-later
*/

import QtQuick
import org.kde.kirigami as Kirigami
import org.kde.kwin as KWinComponents

KWinComponents.SceneEffect {
    id: effect

    property bool activated: false
    // what KWin actually did: it refuses to start while another full-screen effect runs (e.g. Slide)
    property bool kwinRunning: false
    onActivated: kwinRunning = true
    onDeactivated: kwinRunning = false
    readonly property int animationDuration: Kirigami.Units.longDuration

    // The effect has two views: the desktop grid and the horizontal window
    // strip. mode is set before activating, so the delegate below is always
    // the one KWin instantiates.
    property string mode: "grid"

    // KWin's shared QML engine caches files by URL for the whole session; the stamp makes re-enabling the effect load edited files
    property var gridDelegate: Qt.createComponent("ScreenView.qml?" + Date.now())
    property var stripDelegate: Qt.createComponent("StripView.qml?" + Date.now())
    delegate: effect.mode === "strip" ? effect.stripDelegate : effect.gridDelegate

    Instantiator {
        model: effect.configuration.BorderActivate
        KWinComponents.ScreenEdgeHandler {
            mode: KWinComponents.ScreenEdgeHandler.Pointer
            edge: modelData
            onActivated: effect.toggleMode("grid")
        }
    }

    Instantiator {
        model: effect.configuration.TouchBorderActivate
        KWinComponents.ScreenEdgeHandler {
            mode: KWinComponents.ScreenEdgeHandler.Touch
            edge: modelData
            onActivated: effect.toggleMode("grid")
        }
    }

    KWinComponents.ShortcutHandler {
        // The name keys the stored shortcut, so it stays "Better Overview"
        // even though the effect is now Folonium's.
        name: "Better Overview"
        text: i18nd("kwin_effect_foloniumoverview", "Toggle Folonium Overview")
        // Default binding, so a fresh install and any shortcut cleanup keep
        // the usual Meta+G instead of dropping the association.
        sequence: "Meta+G"
        onActivated: effect.toggleMode("grid")
    }

    KWinComponents.ShortcutHandler {
        // Deliberately unbound by default: the strip is a second, optional
        // overview mode and must not steal a key from anyone.
        name: "FoloniumWindowStrip"
        text: i18nd("kwin_effect_foloniumoverview", "Toggle Folonium Window Strip")
        onActivated: effect.toggleMode("strip")
    }

    Timer {
        id: deactivateTimer
        interval: effect.animationDuration
        onTriggered: effect.visible = false
    }

    Timer {
        id: retryTimer
        interval: 50
        repeat: true
        property int attempts: 0
        onTriggered: {
            if (++attempts > 20 || effect.activated) {
                stop();
                return;
            }
            effect.activate();
        }
    }

    // Switching between the grid and the strip needs a fresh delegate, and
    // KWin only reads it when the effect starts. Close the old mode first,
    // then reopen the requested one after the fade.
    property string pendingMode: ""
    Timer {
        id: modeTimer
        // Slightly longer than the fade so the old delegate's views are hidden
        // before KWin instantiates the new mode's delegate.
        interval: effect.animationDuration + 50
        onTriggered: {
            if (effect.pendingMode === "") {
                return;
            }
            effect.mode = effect.pendingMode;
            effect.pendingMode = "";
            effect.activate();
        }
    }

    function toggleMode(next) {
        if (activated) {
            if (mode === next) {
                deactivate();
                return;
            }
            pendingMode = next;
            deactivate();
            modeTimer.restart();
            return;
        }
        mode = next;
        activate();
    }

    function toggle() {
        toggleMode(mode);
    }

    function activate() {
        if (activated) {
            return;
        }
        // re-opening during the fade-out reuses the live views instead of dropping the press
        deactivateTimer.stop();
        visible = true;
        if (!kwinRunning) {
            visible = false;
            if (!retryTimer.running) {
                retryTimer.attempts = 0;
                retryTimer.start();
            }
            return;
        }
        retryTimer.stop();
        activated = true;
    }

    function deactivate() {
        if (!activated) {
            return;
        }
        activated = false;
        deactivateTimer.start();
    }
}
