// engine/index.ts - Wrapper around the engines to interact with the driver
import { console } from "../controller";
import {
    TilingEngineInterface,
    Window,
    Tile,
    Direction,
    LayoutDirection,
} from "./engine";
import { KwinEngine } from "./layouts/kwin";
import { CustomEngine } from "./layouts/custom";

export { Window, Tile, Direction, LayoutDirection };

// Values 5 and 6 are kept stable: they are what saved settings and the saver
// store use. Older saves from the removed engines (0-4) resolve to Custom.
export enum TilingEngineType {
    KWin = 5,
    Custom = 6,
    _Loop = 7,
}

export class TilingEngine {
    private engine: TilingEngineInterface;
    private engineRootTile: Tile;

    readonly engineType: TilingEngineType;

    constructor(type: TilingEngineType, settings: object) {
        // The script has one tiling engine plus KWin's own tiling. Old saved
        // engine numbers (0-4) all resolve to Custom so their displays keep
        // tiling after an upgrade.
        if (type === TilingEngineType.KWin) {
            this.engineType = TilingEngineType.KWin;
            this.engine = new KwinEngine();
        } else {
            this.engineType = TilingEngineType.Custom;
            this.engine = new CustomEngine();
        }
        this.engine.setEngineSettings(settings);
        this.engineRootTile = this.engine.buildLayout();
    }

    getEngineSettings(): object {
        return this.engine.getEngineSettings();
    }
    setEngineSettings(settings: object): void {
        this.engine.setEngineSettings(settings);
    }

    buildLayout(): Tile {
        this.engineRootTile = this.engine.buildLayout();
        return this.engineRootTile;
    }
    addWindow(window: Window, tile?: Tile, direction?: Direction): void {
        return this.engine.addWindow(window, tile, direction);
    }
    placeWindow(window: Window, tile: Tile, direction?: Direction) {
        return this.engine.placeWindow(window, tile, direction);
    }
    windowActivated(window: Window): boolean {
        return this.engine.windowActivated(window);
    }
    removeWindow(window: Window): void {
        return this.engine.removeWindow(window);
    }
    updateTiles(rootTile: Tile): void {
        return this.engine.updateTiles(rootTile);
    }
}
