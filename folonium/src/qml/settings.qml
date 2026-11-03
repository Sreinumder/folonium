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
    // live facts about the layout the engine built right now; read-only
    property int windowCount: -1;
    property int variantCount: 1;
    property string shapeText: "";
    property int variantIndex: -1;
    property bool customSelected: false;
    property var customLayoutSets: [];
    property string horizontalRatio: "";
    property string verticalRatio: "";
    property int horizontalRatioCount: 0;
    property int verticalRatioCount: 0;
    property bool kwinActive: false;
    property bool monocleActive: false;
    x: (screenGeometry.x + screenGeometry.width / 2) - width / 2;
    y: (screenGeometry.y + screenGeometry.height / 2) - height / 2;

    type: PlasmaCore.Dialog.OnScreenDisplay;
    flags: Qt.Popup | Qt.WindowStaysOnTopHint;
    location: PlasmaCore.Types.Floating;
    hideOnWindowDeactivate: true;

    // Only the Custom engine reports a window list it can count and reshape.
    readonly property bool custom: engineType === 6 && windowCount >= 0;

    function show(desktop, activity, output, engineType, engineSettings, windowCount, variantCount, shapeText, variantIndex, customSelected, customLayoutSets, ratioInfo, monocleActive) {
        this.desktop = desktop;
        this.activity = activity;
        this.output = output;

        this.engineType = engineType;
        this.engineSettings = engineSettings;
        this.windowCount = windowCount !== undefined ? windowCount : -1;
        this.variantCount = variantCount !== undefined && variantCount > 0 ? variantCount : 1;
        this.shapeText = shapeText !== undefined ? shapeText : "";
        this.variantIndex = variantIndex !== undefined ? variantIndex : -1;
        this.customSelected = customSelected === true;
        this.customLayoutSets = customLayoutSets !== undefined ? customLayoutSets : [];
        const ratios = ratioInfo !== undefined ? ratioInfo : {};
        this.horizontalRatio = ratios.horizontal !== undefined ? ratios.horizontal : "";
        this.verticalRatio = ratios.vertical !== undefined ? ratios.vertical : "";
        this.horizontalRatioCount = ratios.horizontalCount !== undefined ? ratios.horizontalCount : 0;
        this.verticalRatioCount = ratios.verticalCount !== undefined ? ratios.verticalCount : 0;
        this.kwinActive = engineType === 5;
        this.monocleActive = monocleActive;

        // Update current screen information
        this.screenGeometry = Workspace.clientArea(KWin.MaximizeArea, output, desktop);

        // Show the popup
        this.visible = true;
    }

    function hide() {
        this.visible = false;
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

    function selectedSetName() {
        const tab = this.engineSettings.customLayoutTab ?? 0;
        for (let i = 0; i < this.customLayoutSets.length; i++) {
            if (this.customLayoutSets[i].index === tab) {
                return this.customLayoutSets[i].name;
            }
        }
        return "L1";
    }

    function selectedSetIndex() {
        const tab = this.engineSettings.customLayoutTab ?? 0;
        for (let i = 0; i < this.customLayoutSets.length; i++) {
            if (this.customLayoutSets[i].index === tab) {
                return i;
            }
        }
        return 0;
    }

    function layoutSummary() {
        const name = this.selectedSetName();
        const position = this.variantIndex >= 0 && this.variantCount > 1
            ? " " + (this.variantIndex + 1) + "/" + this.variantCount
            : "";
        if (this.customSelected) {
            return (this.shapeText || "-") + "   " + name + position;
        }
        return this.windowCount === 0
            ? "-   " + name
            : "-   " + name + " (no layout)";
    }

    signal saveSettings(desktop: var, activity: var, output: var, engineType: int, engineSettings: var);
    signal resetSettings(desktop: var, activity: var, output: var);
    // Read-only facts about the built layout, so the popup can show them.
    signal cycleVariant(backwards: bool);
    signal cycleHorizontalRatio(backwards: bool);
    signal cycleVerticalRatio(backwards: bool);
    signal rotateWindows(backwards: bool);
    signal toggleKwinEngine();
    signal toggleMonocle();
    signal selectCustomLayoutTab(desktop: var, activity: var, output: var, tabIndex: int);

    mainItem: GridLayout {
        columns: 2;
        // i feel like PlasmaCore.Dialog incorrectly implements this because theres no padding
        Layout.alignment: Qt.AlignHCenter;
        columnSpacing: 10;
        Layout.margins: 20;
        // change biggestLabel to be the id of whatever label is biggest
        Layout.preferredWidth: biggestLabel.implicitWidth * 2;

        PC3.Label {
            visible: root.custom;
            text: "Windows:";
        }
        PC3.Label {
            visible: root.custom;
            text: root.windowCount === 1 ? "1 window" : root.windowCount + " windows";
            Layout.alignment: Qt.AlignLeft;
        }

        // The shape on screen, written in the layout DSL: [ ] splits into
        // columns, / / into rows, and a number is that many stacked windows.
        PC3.Label {
            visible: root.custom;
            text: "Layout:";
        }
        PC3.Label {
            visible: root.custom;
            text: root.layoutSummary();
            Layout.alignment: Qt.AlignLeft;
        }

        PC3.Label {
            visible: root.custom && root.customLayoutSets.length > 0;
            text: "Layout Set:";
        }
        PC3.ComboBox {
            visible: root.custom && root.customLayoutSets.length > 0;
            Layout.fillWidth: true;
            model: root.customLayoutSets;
            textRole: "name";
            currentIndex: root.selectedSetIndex();
            onActivated: (index) => {
                root.selectCustomLayoutTab(
                    root.desktop,
                    root.activity,
                    root.output,
                    root.customLayoutSets[index].index
                );
            }
        }

        PC3.Label {
            visible: root.custom && root.variantCount > 1;
            text: "Change Layout:";
        }
        RowLayout {
            visible: root.custom && root.variantCount > 1;
            Layout.alignment: Qt.AlignLeft;
            spacing: 4;
            PC3.Button {
                text: "Previous";
                onClicked: root.cycleVariant(true);
            }
            PC3.Button {
                text: "Next";
                onClicked: root.cycleVariant(false);
            }
        }

        PC3.Label {
            id: biggestLabel;
            visible: root.custom && root.horizontalRatioCount > 0;
            text: "Horizontal Ratio:";
        }
        RowLayout {
            visible: root.custom && root.horizontalRatioCount > 0;
            Layout.alignment: Qt.AlignLeft;
            spacing: 4;
            PC3.Label {
                text: root.horizontalRatio || "-";
            }
            PC3.Button {
                visible: root.horizontalRatioCount > 1;
                text: "Previous";
                onClicked: root.cycleHorizontalRatio(true);
            }
            PC3.Button {
                visible: root.horizontalRatioCount > 1;
                text: "Next";
                onClicked: root.cycleHorizontalRatio(false);
            }
        }

        PC3.Label {
            visible: root.custom && root.verticalRatioCount > 0;
            text: "Vertical Ratio:";
        }
        RowLayout {
            visible: root.custom && root.verticalRatioCount > 0;
            Layout.alignment: Qt.AlignLeft;
            spacing: 4;
            PC3.Label {
                text: root.verticalRatio || "-";
            }
            PC3.Button {
                visible: root.verticalRatioCount > 1;
                text: "Previous";
                onClicked: root.cycleVerticalRatio(true);
            }
            PC3.Button {
                visible: root.verticalRatioCount > 1;
                text: "Next";
                onClicked: root.cycleVerticalRatio(false);
            }
        }

        PC3.Label {
            visible: root.custom && root.windowCount >= 2;
            text: "Rotate Windows:";
        }
        RowLayout {
            visible: root.custom && root.windowCount >= 2;
            Layout.alignment: Qt.AlignLeft;
            spacing: 4;
            PC3.Button {
                text: "Previous";
                onClicked: root.rotateWindows(true);
            }
            PC3.Button {
                text: "Next";
                onClicked: root.rotateWindows(false);
            }
        }

        // Always available: when KWin is in charge this is the way back.
        PC3.Label {
            text: "KWin Engine:";
        }
        PC3.Button {
            text: root.kwinActive ? "Back to Tiling" : "Switch to KWin";
            Layout.alignment: Qt.AlignLeft;
            onClicked: root.toggleKwinEngine();
        }

        RowLayout {
            visible: root.custom && root.windowCount >= 2;
            Layout.alignment: Qt.AlignLeft;
            Layout.columnSpan: 2;
            spacing: 4;
            PC3.Label {
                text: "Monocle layout:";
            }
            PC3.Button {
                text: root.monocleActive ? "Back to Tiling" : "Toggle Monocle";
                onClicked: root.toggleMonocle();
            }
        }
        

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
            visible: root.hasProp("mirrorLayout");
            // Mirrors the whole arrangement - windows and proportions together.
            text: "Mirror Layout:";
        }
        PC3.CheckBox {
            visible: root.hasProp("mirrorLayout");
            checked: root.engineSettings.mirrorLayout ?? false;
            onClicked: {
                root.engineSettings.mirrorLayout = !root.engineSettings.mirrorLayout;
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

