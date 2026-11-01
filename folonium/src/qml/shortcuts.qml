// shortcuts.qml - Shortcuts

import QtQuick;
import org.kde.kwin;

Item {
    id: shortcuts;
    
    function mirrorLayout() {
        return mirrorLayoutObj;
    }
    ShortcutHandler {
        id: mirrorLayoutObj;
        
        name: "FoloniumMirrorLayout";
        text: "Folonium: Mirror Layout";
        sequence: "";
    }
    function rotateLayout() {
        return rotateLayoutObj;
    }
    ShortcutHandler {
        id: rotateLayoutObj;
        
        name: "FoloniumRotateLayout";
        text: "Folonium: Rotate Layout";
        sequence: "";
    }
    function cycleLayout() {
        return cycleLayoutObj;
    }
    ShortcutHandler {
        id: cycleLayoutObj;
        
        name: "FoloniumCycleLayout";
        text: "Folonium: Cycle Layout For Window Count";
        sequence: "";
    }
    function rotateWindows() {
        return rotateWindowsObj;
    }
    ShortcutHandler {
        id: rotateWindowsObj;
        
        name: "FoloniumRotateWindows";
        text: "Folonium: Rotate Windows";
        sequence: "";
    }
    function cycleHorizontalRatio() {
        return cycleHorizontalRatioObj;
    }
    ShortcutHandler {
        id: cycleHorizontalRatioObj;

        name: "FoloniumCycleHorizontalRatio";
        text: "Folonium: Cycle Horizontal Ratio";
        sequence: "";
    }
    function cycleVerticalRatio() {
        return cycleVerticalRatioObj;
    }
    ShortcutHandler {
        id: cycleVerticalRatioObj;

        name: "FoloniumCycleVerticalRatio";
        text: "Folonium: Cycle Vertical Ratio";
        sequence: "";
    }
    function toggleKwinEngine() {
        return toggleKwinEngineObj;
    }
    ShortcutHandler {
        id: toggleKwinEngineObj;
        
        name: "FoloniumToggleKwinEngine";
        text: "Folonium: Toggle KWin Engine";
        sequence: "";
    }
    function toggleMonocle() {
        return toggleMonocleObj;
    }
    ShortcutHandler {
        id: toggleMonocleObj;

        name: "FoloniumToggleMonocle";
        text: "Folonium: Toggle Monocle Layout";
        sequence: "";
    }
    function toggleActiveTiling() {
        return toggleActiveTilingObj;
    }
    ShortcutHandler {
        id: toggleActiveTilingObj;
        
        name: "FoloniumToggleActiveTiling";
        text: "Folonium: Toggle Tiling/Floating for Active Window";
        sequence: "";
    }
    function activateLeft() {
        return activateLeftObj;
    }
    ShortcutHandler {
        id: activateLeftObj;
        
        name: "FoloniumActivateLeft";
        text: "Folonium: Activate Left";
        sequence: "";
    }
    function activateBelow() {
        return activateBelowObj;
    }
    ShortcutHandler {
        id: activateBelowObj;
        
        name: "FoloniumActivateBelow";
        text: "Folonium: Activate Below";
        sequence: "";
    }
    function activateAbove() {
        return activateAboveObj;
    }
    ShortcutHandler {
        id: activateAboveObj;
        
        name: "FoloniumActivateAbove";
        text: "Folonium: Activate Above";
        sequence: "";
    }
    function activateRight() {
        return activateRightObj;
    }
    ShortcutHandler {
        id: activateRightObj;
        
        name: "FoloniumActivateRight";
        text: "Folonium: Activate Right";
        sequence: "";
    }
    function placeLeft() {
        return placeLeftObj;
    }
    ShortcutHandler {
        id: placeLeftObj;
        
        name: "FoloniumPlaceLeft";
        text: "Folonium: Place Left";
        sequence: "";
    }
    function placeBelow() {
        return placeBelowObj;
    }
    ShortcutHandler {
        id: placeBelowObj;
        
        name: "FoloniumPlaceBelow";
        text: "Folonium: Place Below";
        sequence: "";
    }
    function placeAbove() {
        return placeAboveObj;
    }
    ShortcutHandler {
        id: placeAboveObj;
        
        name: "FoloniumPlaceAbove";
        text: "Folonium: Place Above";
        sequence: "";
    }
    function placeRight() {
        return placeRightObj;
    }
    ShortcutHandler {
        id: placeRightObj;
        
        name: "FoloniumPlaceRight";
        text: "Folonium: Place Right";
        sequence: "";
    }
    function resizeLeft() {
        return resizeLeftObj;
    }
    ShortcutHandler {
        id: resizeLeftObj;
        
        name: "FoloniumResizeLeft";
        text: "Folonium: Resize Left";
        sequence: "";
    }
    function resizeDown() {
        return resizeDownObj;
    }
    ShortcutHandler {
        id: resizeDownObj;
        
        name: "FoloniumResizeDown";
        text: "Folonium: Resize Below";
        sequence: "";
    }
    function resizeUp() {
        return resizeUpObj;
    }
    ShortcutHandler {
        id: resizeUpObj;
        
        name: "FoloniumResizeUp";
        text: "Folonium: Resize Above";
        sequence: "";
    }
    function resizeRight() {
        return resizeRightObj;
    }
    ShortcutHandler {
        id: resizeRightObj;
        
        name: "FoloniumResizeRight";
        text: "Folonium: Resize Right";
        sequence: "";
    }

    function toggleSettingsMenu() {
        return toggleSettingsMenuObj;
    }
    ShortcutHandler {
        id: toggleSettingsMenuObj;
        
        name: "FoloniumToggleSettingsMenu";
        text: "Folonium: Toggle Settings Menu";
        sequence: "";
    }
}
