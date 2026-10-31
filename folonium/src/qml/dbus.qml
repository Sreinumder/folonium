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
}
