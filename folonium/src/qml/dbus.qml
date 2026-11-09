import QtQuick;
import org.kde.kwin;

Item {
    id: root;

    function getSettings() {
        return getSettingsObj;
    }
    DBusCall {
        id: getSettingsObj;
        
        service: "xyz.vaughanm.folonium";
        path: "/saver";
        dbusInterface: "xyz.vaughanm.folonium";
        method: "GetSettings";
    }

    function setSettings() {
        return setSettingsObj;
    }
    DBusCall {
        id: setSettingsObj;
        
        service: "xyz.vaughanm.folonium";
        path: "/saver";
        dbusInterface: "xyz.vaughanm.folonium";
        method: "SetSettings";
    }

    function resetSettings() {
        return resetSettingsObj;
    }
    DBusCall {
        id: resetSettingsObj;
        
        service: "xyz.vaughanm.folonium";
        path: "/saver";
        dbusInterface: "xyz.vaughanm.folonium";
        method: "ResetSettings";
    }

    function setGlobalSetting() {
        return setGlobalSettingObj;
    }
    DBusCall {
        id: setGlobalSettingObj;

        service: "xyz.vaughanm.folonium";
        path: "/saver";
        dbusInterface: "xyz.vaughanm.folonium";
        method: "SetGlobalSetting";
    }

    // Volatile per-display state (layout text and monocle flag) for the
    // overview effect.
    function setState() {
        return setStateObj;
    }
    DBusCall {
        id: setStateObj;

        service: "xyz.vaughanm.folonium";
        path: "/saver";
        dbusInterface: "xyz.vaughanm.folonium";
        method: "SetState";
    }

    // One pending command from the overview effect, polled by the script.
    function takeRequest() {
        return takeRequestObj;
    }
    DBusCall {
        id: takeRequestObj;

        service: "xyz.vaughanm.folonium";
        path: "/saver";
        dbusInterface: "xyz.vaughanm.folonium";
        method: "TakeRequest";
    }

    // Whether the overview effect is open, polled by the script. The one-slot
    // request queue can be overwritten by a click, so this flag is what tells
    // the script when to put monocle back.
    function getOverviewOpen() {
        return getOverviewOpenObj;
    }
    DBusCall {
        id: getOverviewOpenObj;

        service: "xyz.vaughanm.folonium";
        path: "/saver";
        dbusInterface: "xyz.vaughanm.folonium";
        method: "GetOverviewOpen";
    }

    // Every output's strip state, polled by the script. Kept separate from the
    // overview flag because the strip is per output and each screen view
    // refreshes its own entry.
    function getStripOpen() {
        return getStripOpenObj;
    }
    DBusCall {
        id: getStripOpenObj;

        service: "xyz.vaughanm.folonium";
        path: "/saver";
        dbusInterface: "xyz.vaughanm.folonium";
        method: "GetStripOpen";
    }

    function moveMouseToFocus() {
        return moveMouseToFocusObj;
    }
    DBusCall {
        id: moveMouseToFocusObj;

        service: "org.kde.kglobalaccel";
        path: "/component/kwin";
        dbusInterface: "org.kde.kglobalaccel.Component";
        method: "invokeShortcut";
        arguments: ["MoveMouseToFocus"];
    }

    // KWin only refreshes the values readConfig() returns after a reconfigure.
    // The saver asks for one when the layout tabs change; without the saver the
    // script asks when the settings popup opens.
    function reconfigureKWin() {
        return reconfigureKWinObj;
    }
    DBusCall {
        id: reconfigureKWinObj;

        service: "org.kde.KWin";
        path: "/KWin";
        dbusInterface: "org.kde.KWin";
        method: "reconfigure";
    }
}
