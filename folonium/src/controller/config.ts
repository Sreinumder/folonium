import { KWin } from "kwin-api/qml";
import { TilingEngineType } from "../engine";
import { console } from "./index";

export enum LogLevel {
    Error = 0,
    Warn,
    Log,
    Debug,
}
export enum Borders {
    None = 0,
    Floating,
    Active,
    FloatingActive,
    All,
}
export enum DragPolicy {
    Always = 0,
    Tiled,
    Never,
}
export enum DragRetilePoint {
    Mouse = 0,
    Center,
    Top,
}
export enum UltrawidePosition {
    Center = 0,
    Left,
    Right,
}

export class Config {
    readonly rebuildDelay: number;
    readonly tileResizeAmount: number;
    readonly tileGap: number;
    readonly floatingWindowWidth: number;
    readonly floatingWindowHeight: number;
    readonly useDBusSaver: boolean;

    readonly logLevel: LogLevel;

    readonly defaultEngine: TilingEngineType;

    readonly customSettings: object;

    readonly borders: Borders;
    readonly tiledWindowsBelow: boolean;
    readonly mouseFollowsFocus: boolean;
    readonly mouseFollowsFocusDelay: number;
    readonly mouseFollowsFocusIgnoreEffects: string[];
    readonly windowDragPolicy: DragPolicy;
    readonly dragRetilePoint: DragRetilePoint;

    readonly ultrawideSingleWindow: boolean;
    readonly ultrawideOnly: boolean;
    readonly ultrawideSingleWindowWidth: number;
    readonly ultrawideSingleWindowPosition: UltrawidePosition;

    readonly rawRegex: boolean;
    readonly ignoreWindowClasses: RegExp;
    readonly ignoreWindowCaptions: RegExp;
    readonly untileWindowClasses: RegExp;
    readonly untileWindowCaptions: RegExp;
    readonly tilePopups: boolean;
    readonly minWindowSize: number;

    constructor(kwinApi: KWin) {
        const rc = kwinApi.readConfig;

        this.rebuildDelay = rc("RebuildDelay", 10);
        this.tileResizeAmount = rc("TileResizeAmount", 10);
        this.tileGap = rc("TileGap", 4);
        this.floatingWindowWidth = rc("FloatingWindowWidth", 1089);
        this.floatingWindowHeight = rc("FloatingWindowHeight", 467);
        this.useDBusSaver = rc("UseDBusSaver", false);

        this.logLevel = rc("LogLevel", LogLevel.Warn);

        this.defaultEngine = rc("DefaultEngine", TilingEngineType.Custom);
        const layoutsJson = rc("CustomLayouts", "");
        const ratiosJson = rc("CustomRatios", "");
        const layout1 = rc("CustomLayout1", "");
        const layout2 = rc("CustomLayout2", "");
        const layout3 = rc("CustomLayout3", "");
        const layout4 = rc("CustomLayout4", "");
        const layout5 = rc("CustomLayout5", "");
        const layout6 = rc("CustomLayout6", "");
        const layout7 = rc("CustomLayout7", "");
        const layout8 = rc("CustomLayout8", "");
        const layout9 = rc("CustomLayout9", "");
        const layout10 = rc("CustomLayout10", "");
        console().warn("CustomSettings layouts:", {layout1, layout2, layout3, layout4, layout5, layout6, layout7, layout8, layout9, layout10});
        this.customSettings = {
            layoutsJson,
            ratiosJson,
            layoutIndex: rc("CustomLayoutIndex", 0),
            horizontalRatioIndex: rc("CustomHorizontalRatioIndex", 0),
            verticalRatioIndex: rc("CustomVerticalRatioIndex", 0),
            windowOrderOffset: rc("CustomWindowOrderOffset", 0),
            // Per-window-count layouts
            layout1,
            layout2,
            layout3,
            layout4,
            layout5,
            layout6,
            layout7,
            layout8,
            layout9,
            layout10,
        };

        this.ultrawideSingleWindow = rc("UltrawideSingleWindow", false);
        this.ultrawideOnly = rc("UltrawideOnly", true);
        this.ultrawideSingleWindowWidth = rc("UltrawideSingleWindowWidth", 0.6);
        this.ultrawideSingleWindowPosition = rc(
            "UltrawideSingleWindowPosition",
            UltrawidePosition.Center,
        );

        this.rawRegex = rc("RawRegex", false);
        let ignoreWindowClasses = rc(
            "IgnoreWindowClasses",
            "krunner, yakuake, kded, polkit, plasmashell, xwaylandvideobridge",
        );
        let ignoreWindowCaptions = rc("IgnoreWindowCaptions", "");
        let untileWindowClasses = rc("UntileWindowClasses", "");
        let untileWindowCaptions = rc("UntileWindowCaptions", "");
        if (!this.rawRegex) {
            ignoreWindowClasses = "^" + commaRegex(ignoreWindowClasses) + "$";
            ignoreWindowCaptions = "^" + commaRegex(ignoreWindowCaptions) + "$";
            untileWindowClasses = "^" + commaRegex(untileWindowClasses) + "$";
            untileWindowCaptions = "^" + commaRegex(untileWindowCaptions) + "$";
        }
        this.ignoreWindowClasses = new RegExp(ignoreWindowClasses);
        this.ignoreWindowCaptions = new RegExp(ignoreWindowCaptions);
        this.untileWindowClasses = new RegExp(untileWindowClasses);
        this.untileWindowCaptions = new RegExp(untileWindowCaptions);

        this.borders = rc("Borders", Borders.All);
        this.tiledWindowsBelow = rc("TiledWindowsBelow", true);
        this.mouseFollowsFocus = rc("MouseFollowsFocus", false);
        this.mouseFollowsFocusDelay = rc("MouseFollowsFocusDelay", 50);
        this.mouseFollowsFocusIgnoreEffects = rc("MouseFollowsFocusIgnoreEffects", "foloniumoverview")
            .split(",")
            .map((x: string) => x.trim())
            .filter(Boolean);
        this.tilePopups = rc("TilePopups", false);
        this.minWindowSize = rc("MinWindowSize", 200);
        this.windowDragPolicy = rc("WindowDragPolicy", DragPolicy.Tiled);
        this.dragRetilePoint = rc("DragRetilePoint", DragRetilePoint.Mouse);
    }
}

function commaRegex(str: string): string {
    const pattern = str
        .split(",")
        .map((x) => x.trim())
        .filter(Boolean)
        .join("|");
    // An empty pattern would become /^$/, matching windows with empty initial metadata.
    return pattern || "(?!)";
}
