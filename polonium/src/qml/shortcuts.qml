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
        
        name: "PoloniumMirrorLayout";
        text: "Polonium: Mirror Layout";
        sequence: "";
    }
    function rotateLayout() {
        return rotateLayoutObj;
    }
    ShortcutHandler {
        id: rotateLayoutObj;
        
        name: "PoloniumRotateLayout";
        text: "Polonium: Rotate Layout";
        sequence: "";
    }
    function cycleLayout() {
        return cycleLayoutObj;
    }
    ShortcutHandler {
        id: cycleLayoutObj;
        
        name: "PoloniumCycleLayout";
        text: "Polonium: Cycle Layout For Window Count";
        sequence: "";
    }
    function rotateWindows() {
        return rotateWindowsObj;
    }
    ShortcutHandler {
        id: rotateWindowsObj;
        
        name: "PoloniumRotateWindows";
        text: "Polonium: Rotate Windows";
        sequence: "";
    }
    function cycleHorizontalRatio() {
        return cycleHorizontalRatioObj;
    }
    ShortcutHandler {
        id: cycleHorizontalRatioObj;

        name: "PoloniumCycleHorizontalRatio";
        text: "Polonium: Cycle Horizontal Ratio";
        sequence: "";
    }
    function cycleVerticalRatio() {
        return cycleVerticalRatioObj;
    }
    ShortcutHandler {
        id: cycleVerticalRatioObj;

        name: "PoloniumCycleVerticalRatio";
        text: "Polonium: Cycle Vertical Ratio";
        sequence: "";
    }
    function toggleKwinEngine() {
        return toggleKwinEngineObj;
    }
    ShortcutHandler {
        id: toggleKwinEngineObj;
        
        name: "PoloniumToggleKwinEngine";
        text: "Polonium: Toggle KWin Engine";
        sequence: "";
    }
    function toggleActiveTiling() {
        return toggleActiveTilingObj;
    }
    ShortcutHandler {
        id: toggleActiveTilingObj;
        
        name: "PoloniumToggleActiveTiling";
        text: "Polonium: Toggle Tiling on Active Window";
        sequence: "";
    }
    function activateLeft() {
        return activateLeftObj;
    }
    ShortcutHandler {
        id: activateLeftObj;
        
        name: "PoloniumActivateLeft";
        text: "Polonium: Activate Left";
        sequence: "";
    }
    function activateBelow() {
        return activateBelowObj;
    }
    ShortcutHandler {
        id: activateBelowObj;
        
        name: "PoloniumActivateBelow";
        text: "Polonium: Activate Below";
        sequence: "";
    }
    function activateAbove() {
        return activateAboveObj;
    }
    ShortcutHandler {
        id: activateAboveObj;
        
        name: "PoloniumActivateAbove";
        text: "Polonium: Activate Above";
        sequence: "";
    }
    function activateRight() {
        return activateRightObj;
    }
    ShortcutHandler {
        id: activateRightObj;
        
        name: "PoloniumActivateRight";
        text: "Polonium: Activate Right";
        sequence: "";
    }
    function placeLeft() {
        return placeLeftObj;
    }
    ShortcutHandler {
        id: placeLeftObj;
        
        name: "PoloniumPlaceLeft";
        text: "Polonium: Place Left";
        sequence: "";
    }
    function placeBelow() {
        return placeBelowObj;
    }
    ShortcutHandler {
        id: placeBelowObj;
        
        name: "PoloniumPlaceBelow";
        text: "Polonium: Place Below";
        sequence: "";
    }
    function placeAbove() {
        return placeAboveObj;
    }
    ShortcutHandler {
        id: placeAboveObj;
        
        name: "PoloniumPlaceAbove";
        text: "Polonium: Place Above";
        sequence: "";
    }
    function placeRight() {
        return placeRightObj;
    }
    ShortcutHandler {
        id: placeRightObj;
        
        name: "PoloniumPlaceRight";
        text: "Polonium: Place Right";
        sequence: "";
    }
    function resizeLeft() {
        return resizeLeftObj;
    }
    ShortcutHandler {
        id: resizeLeftObj;
        
        name: "PoloniumResizeLeft";
        text: "Polonium: Resize Left";
        sequence: "";
    }
    function resizeDown() {
        return resizeDownObj;
    }
    ShortcutHandler {
        id: resizeDownObj;
        
        name: "PoloniumResizeDown";
        text: "Polonium: Resize Below";
        sequence: "";
    }
    function resizeUp() {
        return resizeUpObj;
    }
    ShortcutHandler {
        id: resizeUpObj;
        
        name: "PoloniumResizeUp";
        text: "Polonium: Resize Above";
        sequence: "";
    }
    function resizeRight() {
        return resizeRightObj;
    }
    ShortcutHandler {
        id: resizeRightObj;
        
        name: "PoloniumResizeRight";
        text: "Polonium: Resize Right";
        sequence: "";
    }

    function toggleSettingsMenu() {
        return toggleSettingsMenuObj;
    }
    ShortcutHandler {
        id: toggleSettingsMenuObj;
        
        name: "PoloniumToggleSettingsMenu";
        text: "Polonium: Toggle Settings Menu";
        sequence: "";
    }
}
