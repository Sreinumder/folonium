import QtQuick;
import QtQuick.Layouts;
import org.kde.kwin;
import org.kde.plasma.components as PC3;
import org.kde.plasma.core as PlasmaCore;

PlasmaCore.Dialog {
    id: root;
    
    property var desktop: ({});
    property var activity: ({});
    property var output: ({});

    property int engineType: 0;
    property var engineSettings: ({});
    
    property rect screenGeometry;
    x: (screenGeometry.x + screenGeometry.width / 2) - width / 2;
    y: (screenGeometry.y + screenGeometry.height / 2) - height / 2;

    type: PlasmaCore.Dialog.OnScreenDisplay;
    flags: Qt.Popup | Qt.WindowStaysOnTopHint;
    location: PlasmaCore.Types.Floating;
    hideOnWindowDeactivate: true;
    
    function show(desktop, activity, output, engineType, engineSettings) {
        this.desktop = desktop;
        this.activity = activity;
        this.output = output;

        this.engineType = engineType;
        this.engineSettings = engineSettings;
                
        // Update current screen information
        this.screenGeometry = Workspace.clientArea(KWin.MaximizeArea, output, desktop);
        
        // Show the popup
        this.visible = true;
    }
    
    function hide() {
        this.visible = false;
    }

    function saveEngineTypeFn() {
        this.saveSettings(
            this.desktop,
            this.activity,
            this.output,
            this.engineType,
            undefined,
        );
    }

    function saveSettingsFn() {
        this.saveSettings(
            this.desktop,
            this.activity,
            this.output,
            this.engineType,
            this.engineSettings,
        );
    }

    function hasProp(prop) {
        return this.engineSettings.hasOwnProperty(prop);
    }
    
    signal saveSettings(desktop: var, activity: var, output: var, engineType: int, engineSettings: var);
    signal resetSettings(desktop: var, activity: var, output: var);

    // Helper: get layout text for a window count
    function getLayoutText(count) {
        return engineSettings["layout" + count] ?? "";
    }
    
    // Helper: set layout text for a window count
    function setLayoutText(count, text) {
        engineSettings["layout" + count] = text;
    }

                
    mainItem: GridLayout {
        columns: 2;
        Layout.alignment: Qt.AlignHCenter;
        columnSpacing: 10;
        Layout.margins: 20;
        Layout.preferredWidth: 600;

        // Engine Selection
        PC3.Label {
            text: "Engine:";
        }
        PC3.ComboBox {
            model: ["Binary Tree", "Half", "Three Column", "Pillars", "Pager", "Custom"];
            currentIndex: root.engineType;
            popup.y: height;
            onActivated: (idx) => {
                root.engineType = idx;
                root.saveEngineTypeFn();
            }
        }

        // ========== CUSTOM ENGINE SECTION ==========
        // Only visible when Custom engine is selected
        PC3.Label {
            visible: root.engineType === 6;
            Layout.columnSpan: 2;
            text: "<b>Custom Engine Configuration</b>";
            font.pixelSize: 14;
        }

        // Ratios field (global for all window counts)
        PC3.Label {
            visible: root.engineType === 6;
            text: "Ratios (global):";
        }
        PC3.TextArea {
            visible: root.engineType === 6;
            Layout.fillWidth: true;
            Layout.preferredHeight: 80;
            text: root.engineSettings.ratiosJson ?? "";
            placeholderText: "e.g. 2:1 3:2 1:1 2:3 1:2\n1:1:1 2:1:1 1:2:1 1:1:2\n1:1:1:1 2:1:1:1 1:2:1:1 1:1:2:1";
            onTextChanged: {
                root.engineSettings.ratiosJson = this.text;
                root.saveSettingsFn();
            }
        }

        // Window count selector
        PC3.Label {
            visible: root.engineType === 6;
            text: "Window Count:";
        }
        PC3.ComboBox {
            id: windowCountCombo;
            visible: root.engineType === 6;
            Layout.fillWidth: true;
            model: ["L1", "L2", "L3", "L4", "L5", "L6", "L7", "L8", "L9", "L10"];
            currentIndex: 0;
            onActivated: (idx) => {
                // Force UI update
                layoutTextArea.text = root.engineSettings["layout" + (idx + 1)] ?? "";
            }
        }

        // Layout text area for selected window count
        PC3.Label {
            visible: root.engineType === 6;
            Layout.columnSpan: 2;
            text: "Layouts for selected window count (one per line):";
        }
        PC3.TextArea {
            id: layoutTextArea;
            visible: root.engineType === 6;
            Layout.fillWidth: true;
            Layout.fillHeight: true;
            Layout.preferredHeight: 300;
            Layout.columnSpan: 2;
            text: root.engineSettings.layout1 ?? "";
            placeholderText: "Enter layouts for this window count, one per line:\n[1 1] /1 1/ [1 2] [2 1]";
            onTextChanged: {
                const count = windowCountCombo.currentIndex + 1;
                root.engineSettings["layout" + count] = this.text;
                root.saveSettingsFn();
            }
        }

        // ========== EXISTING ENGINE SETTINGS ==========
        PC3.Label {
            visible: root.hasProp("rotateLayout");
            text: "Rotate Layout:";
        }
        PC3.CheckBox {
            visible: root.hasProp("rotateLayout");
            checked: root.engineSettings.rotateLayout ?? false;
            onClicked: {
                root.engineSettings.rotateLayout = !root.engineSettings.rotateLayout;
                root.saveSettingsFn();
            }
        }

        PC3.Label {
            visible: root.hasProp("swapInsertSide");
            text: "Swap Insert Side:";
        }
        PC3.CheckBox {
            visible: root.hasProp("swapInsertSide");
            checked: root.engineSettings.swapInsertSide ?? false;
            onClicked: {
                root.engineSettings.swapInsertSide = !root.engineSettings.swapInsertSide;
                root.saveSettingsFn();
            }
        }

        PC3.Label {
            visible: root.hasProp("middleSplit");
            text: "Middle Split:";
        }
        PC3.SpinBox {
            visible: root.hasProp("middleSplit");
            from: 15;
            to: 85;
            value: root.engineSettings.middleSplit * 100 ?? 50;
            onValueModified: {
                root.engineSettings.middleSplit = this.value / 100;
                root.saveSettingsFn();
            }
        }
        PC3.Label {
            visible: root.hasProp("side1Size");
            text: "Side 1 Size:";
        }
        PC3.SpinBox {
            visible: root.hasProp("side1Size");
            from: 15;
            to: (0.85 - root.engineSettings.side2Size) * 100 ?? 70;
            value: root.engineSettings.side1Size * 100 ?? 25;
            onValueModified: {
                root.engineSettings.side1Size = this.value / 100;
                root.saveSettingsFn();
            }
        }
        PC3.Label {
            visible: root.hasProp("side2Size");
            text: "Side 2 Size:";
        }
        PC3.SpinBox {
            visible: root.hasProp("side2Size");
            from: 15;
            to: (0.85 - root.engineSettings.side1Size) * 100 ?? 70;
            value: root.engineSettings.side2Size * 100 ?? 25;
            onValueModified: {
                root.engineSettings.side2Size = this.value / 100;
                root.saveSettingsFn();
            }
        }

        PC3.Label {
            visible: root.hasProp("pillarCount");
            text: "Pillars:";
        }
        PC3.SpinBox {
            visible: root.hasProp("pillarCount");
            from: 1;
            to: 10;
            value: root.engineSettings.pillarCount ?? 3;
            onValueModified: {
                root.engineSettings.pillarCount = this.value;
                root.saveSettingsFn();
            }
        }

        PC3.Label {
            visible: root.hasProp("pageWidth");
            text: "Page Width:";
        }
        PC3.SpinBox {
            visible: root.hasProp("pageWidth");
            from: 15;
            to: 20;
            value: root.engineSettings.pageWidth * 100 ?? 15;
            onValueModified: {
                root.engineSettings.pageWidth = this.value / 100;
                root.saveSettingsFn();
            }
        }

        PC3.Label {
            visible: root.hasProp("insertionStyle");
            text: "Insertion Style:";
        }
        // btree insertion style
        PC3.ComboBox {
            visible: root.hasProp("insertionStyle") && root.engineType === 0;
            model: ["Shallow", "Dwindle", "Spiral"];
            currentIndex: root.engineSettings.insertionStyle ?? 0;
            popup.y: height;
            onActivated: (idx) => {
                root.engineSettings.insertionStyle = idx;
                root.saveSettingsFn();
            }
        }
        // pillars insertion style
        PC3.ComboBox {
            visible: root.hasProp("insertionStyle") && root.engineType === 3;
            model: ["Rows", "Snake", "Rows Up", "Snake Up"];
            currentIndex: root.engineSettings.insertionStyle ?? 0;
            popup.y: height;
            onActivated: (idx) => {
                root.engineSettings.insertionStyle = idx;
                root.saveSettingsFn();
            }
        }

        PC3.Label {
            visible: root.hasProp("keepMaster");
            text: "Keep Master:";
        }
        PC3.CheckBox {
            visible: root.hasProp("keepMaster");
            checked: root.engineSettings.keepMaster ?? false;
            onClicked: {
                root.engineSettings.keepMaster = !root.engineSettings.keepMaster;
                root.saveSettingsFn();
            }
        }

        PC3.Label {
            id: biggestLabel;
            visible: root.hasProp("insertInActive");
            text: "Insert in Active Tile:";
        }
        PC3.CheckBox {
            visible: root.hasProp("insertInActive");
            checked: root.engineSettings.insertInActive ?? false;
            onClicked: {
                root.engineSettings.insertInActive = !root.engineSettings.insertInActive;
                root.saveSettingsFn();
            }
        }

        PC3.Button {
            Layout.columnSpan: 2;
            Layout.fillWidth: true;
            text: "Reset to Default Settings";
            onClicked: {
                root.resetSettings(
                    root.desktop,
                    root.activity,
                    root.output,
                );
            }
        }
  
        PC3.Button {
            Layout.columnSpan: 2;
            Layout.fillWidth: true;
            text: "Close Menu";
            onClicked: {
                root.hide();
            }
        }
    }
}