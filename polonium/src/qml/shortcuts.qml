// shortcuts.qml - Shortcuts

import QtQuick;
import org.kde.kwin;

Item {
    id: shortcuts;
    
    function toggleActiveTiling() {
        return toggleActiveTilingObj;
    }
    ShortcutHandler {
        id: toggleActiveTilingObj;
        
        name: "PoloniumToggleActiveTiling";
        text: "Polonium: Toggle Tiling on Active Window";
        sequence: "Meta+Shift+Space";
    }
    // no default shortcuts for specific engines
    function setEngineBTree() {
        return setEngineBTreeObj;
    }
    ShortcutHandler {
        id: setEngineBTreeObj;
        
        name: "PoloniumSetEngineBTree";
        text: "Polonium: Use Binary Tree Engine";
        sequence: "";
    }
    function setEngineHalf() {
        return setEngineHalfObj;
    }
    ShortcutHandler {
        id: setEngineHalfObj;
        
        name: "PoloniumSetEngineHalf";
        text: "Polonium: Use Half Engine";
        sequence: "";
    }
    function setEngineThreeColumn() {
        return setEngineThreeColumnObj;
    }
    ShortcutHandler {
        id: setEngineThreeColumnObj;
        
        name: "PoloniumSetEngineThreeColumn";
        text: "Polonium: Use Three Column Engine";
        sequence: "";
    }
    function setEnginePillars() {
        return setEnginePillarsObj;
    }
    ShortcutHandler {
        id: setEnginePillarsObj;
        
        name: "PoloniumSetEnginePillars";
        text: "Polonium: Use Pillars Engine";
        sequence: "";
    }
    function setEnginePager() {
        return setEnginePagerObj;
    }
    ShortcutHandler {
        id: setEnginePagerObj;
        
        name: "PoloniumSetEnginePager";
        text: "Polonium: Use Pager Engine";
        sequence: "";
    }
    function setEngineKWin() {
        return setEngineKWinObj;
    }
    ShortcutHandler {
        id: setEngineKWinObj;
        
        name: "PoloniumSetEngineKWin";
        text: "Polonium: Use KWin Engine";
        sequence: "";
    }

    function activateAbove() {
        return activateAboveObj;
    }
    ShortcutHandler {
        id: activateAboveObj;
        
        name: "PoloniumActivateAbove";
        text: "Polonium: Activate Above";
        sequence: "Meta+K";
    }

    function activateBelow() {
        return activateBelowObj;
    }
    ShortcutHandler {
        id: activateBelowObj;
        
        name: "PoloniumActivateBelow";
        text: "Polonium: Activate Below";
        sequence: "Meta+J";
    }

    function activateLeft() {
        return activateLeftObj;
    }
    ShortcutHandler {
        id: activateLeftObj;
        
        name: "PoloniumActivateLeft";
        text: "Polonium: Activate Left";
        sequence: "Meta+H";
    }

    function activateRight() {
        return activateRightObj;
    }
    ShortcutHandler {
        id: activateRightObj;
        
        name: "PoloniumActivateRight";
        text: "Polonium: Activate Right";
        sequence: "Meta+L";
    }

    function placeAbove() {
        return placeAboveObj;
    }
    ShortcutHandler {
        id: placeAboveObj;
        
        name: "PoloniumPlaceAbove";
        text: "Polonium: Place Window Above";
        sequence: "Meta+Shift+K";
    }

    function placeBelow() {
        return placeBelowObj;
    }
    ShortcutHandler {
        id: placeBelowObj;
        
        name: "PoloniumPlaceBelow";
        text: "Polonium: Place Window Below";
        sequence: "Meta+Shift+J";
    }

    function placeLeft() {
        return placeLeftObj;
    }
    ShortcutHandler {
        id: placeLeftObj;
        
        name: "PoloniumPlaceLeft";
        text: "Polonium: Place Window Left";
        sequence: "Meta+Shift+H";
    }

    function placeRight() {
        return placeRightObj;
    }
    ShortcutHandler {
        id: placeRightObj;
        
        name: "PoloniumPlaceRight";
        text: "Polonium: Place Window Right";
        sequence: "Meta+Shift+L";
    }

    function resizeUp() {
        return resizeUpObj;
    }
    ShortcutHandler {
        id: resizeUpObj;
        
        name: "PoloniumResizeUp";
        text: "Polonium: Resize Tile Up";
        sequence: "Meta+Ctrl+K";
    }

    function resizeDown() {
        return resizeDownObj;
    }
    ShortcutHandler {
        id: resizeDownObj;
        
        name: "PoloniumResizeDown";
        text: "Polonium: Resize Tile Down";
        sequence: "Meta+Ctrl+J";
    }

    function resizeLeft() {
        return resizeLeftObj;
    }
    ShortcutHandler {
        id: resizeLeftObj;
        
        name: "PoloniumResizeLeft";
        text: "Polonium: Resize Tile Left";
        sequence: "Meta+Ctrl+H";
    }

    function resizeRight() {
        return resizeRightObj;
    }
    ShortcutHandler {
        id: resizeRightObj;
        
        name: "PoloniumResizeRight";
        text: "Polonium: Resize Tile Right";
        sequence: "Meta+Ctrl+L";
    }
    
    function toggleSettingsMenu() {
        return toggleSettingsMenuObj;
    }
    ShortcutHandler {
        id: toggleSettingsMenuObj;
        
        name: "PoloniumToggleSettingsMenu";
        text: "Polonium: Toggle Settings Menu";
        sequence: "Meta+\\";
    }
 
    function cycleEngine() {
        return cycleEngineObj;
    }
    ShortcutHandler {
        id: cycleEngineObj;
        
        name: "PoloniumCycleEngine";
        text: "Polonium: Cycle Engine";
        sequence: "Meta+|";
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

    // Custom Engine Shortcuts
    function setEngineCustom() {
        return setEngineCustomObj;
    }
    ShortcutHandler {
        id: setEngineCustomObj;
        
        name: "PoloniumSetEngineCustom";
        text: "Polonium: Use Custom Engine";
        sequence: "";
    }

    function customRotateLayout() {
        return customRotateLayoutObj;
    }
    ShortcutHandler {
        id: customRotateLayoutObj;
        
        name: "PoloniumCustomRotateLayout";
        text: "Polonium: Custom Rotate Layout";
        sequence: "";
    }

    function customMirrorLayout() {
        return customMirrorLayoutObj;
    }
    ShortcutHandler {
        id: customMirrorLayoutObj;
        
        name: "PoloniumCustomMirrorLayout";
        text: "Polonium: Custom Mirror Layout";
        sequence: "";
    }

    function customCycleHorizontalRatio() {
        return customCycleHorizontalRatioObj;
    }
    ShortcutHandler {
        id: customCycleHorizontalRatioObj;
        
        name: "PoloniumCustomCycleHorizontalRatio";
        text: "Polonium: Custom Cycle Horizontal Ratio";
        sequence: "";
    }

    function customCycleVerticalRatio() {
        return customCycleVerticalRatioObj;
    }
    ShortcutHandler {
        id: customCycleVerticalRatioObj;
        
        name: "PoloniumCustomCycleVerticalRatio";
        text: "Polonium: Custom Cycle Vertical Ratio";
        sequence: "";
    }

    function customCycleLayout() {
        return customCycleLayoutObj;
    }
    ShortcutHandler {
        id: customCycleLayoutObj;
        
        name: "PoloniumCustomCycleLayout";
        text: "Polonium: Custom Cycle Layout";
        sequence: "";
    }

    function customCycleWindowOrder() {
        return customCycleWindowOrderObj;
    }
    ShortcutHandler {
        id: customCycleWindowOrderObj;
        
        name: "PoloniumCustomCycleWindowOrder";
        text: "Polonium: Custom Cycle Window Order";
        sequence: "";
    }
    /*
    function getSwitchThreeColumn() {
        return switchThreeColumn;
    }
    ShortcutHandler {
        id: switchThreeColumn;
        
        name: "PoloniumSwitchThreeColumn";
        text: "Polonium: Use Three Column Engine";
        sequence: "";
    }
    
    function getSwitchMonocle() {
        return switchMonocle;
    }
    ShortcutHandler {
        id: switchMonocle;
        
        name: "PoloniumSwitchMonocle";
        text: "Polonium: Use Monocle Engine";
        sequence: "";
    }
    
    function getSwitchKwin() {
        return switchKwin;
    }
    ShortcutHandler {
        id: switchKwin;
        
        name: "PoloniumSwitchKwin";
        text: "Polonium: Use KWin Engine";
        sequence: "";
      }
      */
}
