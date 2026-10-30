// main.qml - Entry point into script

import QtQuick;
import org.kde.kwin;

import "../code/main.mjs" as Polonium;

Item {
    id: root;

    Timer {
        id: eventTimer;
    }

    Timer {
        id: mffTimer;
    }

    // The overview effect cannot call into the script, so it leaves one
    // command in the saver; this polls that slot.
    Timer {
        id: requestTimer;
        interval: 500;
        repeat: true;
        running: true;
    }

    Component.onCompleted: {
        const api = {
            "workspace": Workspace,
            "options": Options,
            "kwin": KWin,
            "console": console,
            "qt": Qt,
        };
        const qmlObjects = {
            "root": root,
            "eventTimer": eventTimer,
            "mffTimer": mffTimer,
            "requestTimer": requestTimer,
            "shortcuts": shortcutsLoader.item,
            "settings": settingsLoader.item,
            "dbus": dbusLoader.item,
        };
        Polonium.main(api, qmlObjects);
    }

    Loader {
        id: shortcutsLoader;
                
        source: "shortcuts.qml";
        asynchronous: false;
        onStatusChanged: {
            if (status === Loader.Ready) {
                console.error("Shortcuts QML loaded successfully");
            } else if (status === Loader.Error) {
                console.error("Shortcuts QML failed to load:", errorString);
            }
        }
        Component.onCompleted: {
            console.error("Shortcuts Loader completed, status:", status);
        }
    }

    Loader {
        id: settingsLoader;
                
        source: "settings.qml";
    }
    
    Loader {
        id: dbusLoader;
        
        source: "dbus.qml";
    }
}
