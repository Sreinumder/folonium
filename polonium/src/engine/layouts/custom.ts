// custom.ts - Custom tiling engine with user-definable layouts and ratios

import {
    Tile,
    Window,
    TilingEngineInterface,
    Direction,
    BaseEngineSettings,
    LayoutDirection,
} from "../engine";
import { console } from "../../controller";

interface CustomLayout {
    // column counts (e.g. [1, 2, 1] = 3 columns with 1, 2, 1 windows stacked)
    cols: number[];
    // whether this is a rotated layout (rows instead of columns)
    rotated: boolean;
    // total window count this layout handles
    windowCount: number;
}

interface CustomRatio {
    // ratio parts (e.g. [1, 2, 1] for 1:2:1)
    parts: number[];
    // arity = parts.length
    arity: number;
}

class CustomEngineSettings extends BaseEngineSettings {
    // Text fields from config (stored as JSON strings)
    layoutsJson: string = "";
    ratiosJson: string = "";

    // Parsed values (not persisted)
    layouts: CustomLayout[] = [];
    ratios: CustomRatio[] = [];

    // Current indices
    layoutIndex: number = 0;
    horizontalRatioIndex: number = 0;
    verticalRatioIndex: number = 0;
    windowOrderOffset: number = 0;

    // Per-window-count layout configs (from kwinrc CustomLayout1-10)
    layout1: string = "";
    layout2: string = "";
    layout3: string = "";
    layout4: string = "";
    layout5: string = "";
    layout6: string = "";
    layout7: string = "";
    layout8: string = "";
    layout9: string = "";
    layout10: string = "";

    getProps(): object {
        return {
            layoutsJson: this.layoutsJson,
            ratiosJson: this.ratiosJson,
            layoutIndex: this.layoutIndex,
            horizontalRatioIndex: this.horizontalRatioIndex,
            verticalRatioIndex: this.verticalRatioIndex,
            windowOrderOffset: this.windowOrderOffset,
            layout1: this.layout1,
            layout2: this.layout2,
            layout3: this.layout3,
            layout4: this.layout4,
            layout5: this.layout5,
            layout6: this.layout6,
            layout7: this.layout7,
            layout8: this.layout8,
            layout9: this.layout9,
            layout10: this.layout10,
        };
    }
    setProps(obj: any): void {
        console().error("CustomEngine.setProps CALLED");
        if (obj == null) return;
        console().warn("CustomEngine.setProps: obj keys:", Object.keys(obj));
        for (const key in this) {
            if (obj.hasOwnProperty(key)) {
                console().warn("CustomEngine.setProps: setting", key, "=", obj[key]);
                this[key] = obj[key];
            }
        }
        console().warn("CustomEngine.setProps: after copy, layout1:", this.layout1, "layout2:", this.layout2, "layout3:", this.layout3);
        this.parseLayouts();
        this.parseRatios();
    }

    parseLayouts(): void {
        this.layouts = [];
        console().warn("CustomEngine.parseLayouts: layout1:", this.layout1, "layout2:", this.layout2, "layout3:", this.layout3);
        
        // Parse global layoutsJson if present (legacy)
        if (this.layoutsJson && this.layoutsJson.trim()) {
            const tokens = this.layoutsJson.trim().split(/\s+/);
            for (const token of tokens) {
                const t = token.trim();
                if (!t) continue;
                let cols: number[];
                let rotated = false;
                if (t.startsWith("[") && t.endsWith("]")) {
                    cols = t.slice(1, -1).split(/\s+/).map(n => parseInt(n, 10)).filter(n => !isNaN(n));
                } else if (t.startsWith("/") && t.endsWith("/")) {
                    cols = t.slice(1, -1).split(/\s+/).map(n => parseInt(n, 10)).filter(n => !isNaN(n));
                    rotated = true;
                } else {
                    continue;
                }
                if (cols.length === 0) continue;
                const windowCount = cols.reduce((a, b) => a + b, 0);
                this.layouts.push({ cols, rotated, windowCount });
            }
        }

        // Parse per-window-count layouts from layout1-10
        for (let count = 1; count <= 10; count++) {
            const layoutStr = this["layout" + count];
            console().warn("CustomEngine.parseLayouts: layout" + count + " = " + layoutStr);
            if (!layoutStr || !layoutStr.trim()) continue;
            
            const tokens = layoutStr.trim().split(/\s+/);
            console().warn("CustomEngine.parseLayouts: layout" + count + " tokens:", tokens);
            for (const token of tokens) {
                const t = token.trim();
                if (!t) continue;
                let cols: number[];
                let rotated = false;
                if (t.startsWith("[") && t.endsWith("]")) {
                    cols = t.slice(1, -1).split(/\s+/).map(n => parseInt(n, 10)).filter(n => !isNaN(n));
                } else if (t.startsWith("/") && t.endsWith("/")) {
                    cols = t.slice(1, -1).split(/\s+/).map(n => parseInt(n, 10)).filter(n => !isNaN(n));
                    rotated = true;
                } else {
                    continue;
                }
                if (cols.length === 0) continue;
                const windowCount = cols.reduce((a, b) => a + b, 0);
                this.layouts.push({ cols, rotated, windowCount });
            }
        }
        
        // Sort by windowCount for cycling
        this.layouts.sort((a, b) => a.windowCount - b.windowCount);
    }

    parseRatios(): void {
        this.ratios = [];
        if (!this.ratiosJson || !this.ratiosJson.trim()) return;
        let json = this.ratiosJson.replace(/\n/g, ' ').replace(/\t/g, ' ').replace(/\r/g, ' ');
        const tokens = json.trim().split(/\s+/).filter(t => t.length > 0);
        for (const token of tokens) {
            const t = token.trim();
            if (!t) continue;
            const parts = t.split(":").map(n => parseFloat(n)).filter(n => !isNaN(n));
            if (parts.length === 0) continue;
            this.ratios.push({ parts, arity: parts.length });
        }
        // Group by arity
        this.ratios.sort((a, b) => a.arity - b.arity || a.parts[0] - b.parts[0]);
    }

    getLayoutsForCount(count: number): CustomLayout[] {
        return this.layouts.filter(l => l.windowCount === count);
    }

    getRatiosForArity(arity: number): CustomRatio[] {
        return this.ratios.filter(r => r.arity === arity);
    }

    getCurrentLayout(windowCount: number): CustomLayout | null {
        const candidates = this.getLayoutsForCount(windowCount);
        console().warn("CustomEngine.getCurrentLayout: windowCount:", windowCount, "candidates:", candidates.length, "layoutIndex:", this.layoutIndex);
        if (candidates.length === 0) {
            // Fallback: next larger layout
            const larger = this.layouts.find(l => l.windowCount > windowCount);
            return larger || null;
        }
        const idx = this.layoutIndex % candidates.length;
        return candidates[idx];
    }

    getCurrentHorizontalRatio(cols: number): CustomRatio | null {
        const candidates = this.getRatiosForArity(cols);
        if (candidates.length === 0) return null;
        const idx = this.horizontalRatioIndex % candidates.length;
        return candidates[idx];
    }

    getCurrentVerticalRatio(rows: number): CustomRatio | null {
        const candidates = this.getRatiosForArity(rows);
        if (candidates.length === 0) return null;
        const idx = this.verticalRatioIndex % candidates.length;
        return candidates[idx];
    }
}

export class CustomEngine implements TilingEngineInterface {
    settings = new CustomEngineSettings();
    // Internal window list - maintained by addWindow/removeWindow/placeWindow
    windows: Window[] = [];

    getEngineSettings(): object {
        return this.settings.getProps();
    }
    setEngineSettings(settings: object): void {
        console().warn("CustomEngine.setEngineSettings CALLED - THROWING");
        throw new Error("setEngineSettings called");
        this.settings.setProps(settings);
    }

    buildLayout(): Tile {
        // Build the tile tree based on current window list
        return this.buildLayoutForWindows(this.windows);
    }

    private buildLayoutForWindows(windows: Window[]): Tile {
        const count = windows.length;
        const root = new Tile();
        if (count === 0) {
            root.layoutDirection = LayoutDirection.Horizontal;
            root.size = 1;
            return root;
        }

        const layout = this.settings.getCurrentLayout(count);
        if (!layout) {
            // Fallback to single column
            return this.buildSingleColumn(windows);
        }

        const cols = layout.cols;
        const rotated = layout.rotated;

        // Get horizontal ratio (column widths for normal, row heights for rotated)
        const hRatio = this.settings.getCurrentHorizontalRatio(cols.length);

        if (!rotated) {
            return this.buildColumns(windows, cols, hRatio);
        } else {
            return this.buildRows(windows, cols, hRatio);
        }
    }

    private buildColumns(windows: Window[], cols: number[], hRatio: CustomRatio | null): Tile {
        const root = new Tile();
        root.layoutDirection = LayoutDirection.Horizontal;
        root.size = 1;

        let winIdx = 0;
        const colWidths = hRatio ? this.normalizeRatio(hRatio.parts, cols.length) : this.equalParts(cols.length);

        for (let ci = 0; ci < cols.length; ci++) {
            const colWindows = cols[ci];
            const colTile = new Tile();
            colTile.layoutDirection = LayoutDirection.Vertical;
            colTile.size = colWidths[ci];

            if (colWindows === 1) {
                // Single window in this column
                if (winIdx < windows.length) {
                    colTile.windows = [windows[winIdx]];
                    winIdx++;
                }
            } else {
                // Stack of windows
                colTile.children = [];
                const vRatio = this.settings.getCurrentVerticalRatio(colWindows);
                const rowHeights = vRatio ? this.normalizeRatio(vRatio.parts, colWindows) : this.equalParts(colWindows);

                for (let ri = 0; ri < colWindows; ri++) {
                    if (winIdx >= windows.length) break;
                    const rowTile = new Tile();
                    rowTile.layoutDirection = LayoutDirection.Horizontal;
                    rowTile.size = rowHeights[ri];
                    rowTile.windows = [windows[winIdx]];
                    winIdx++;
                    colTile.children.push(rowTile);
                }
            }
            root.children.push(colTile);
        }
        return root;
    }

    private buildRows(windows: Window[], rows: number[], hRatio: CustomRatio | null): Tile {
        const root = new Tile();
        root.layoutDirection = LayoutDirection.Vertical;
        root.size = 1;

        let winIdx = 0;
        const rowHeights = hRatio ? this.normalizeRatio(hRatio.parts, rows.length) : this.equalParts(rows.length);

        for (let ri = 0; ri < rows.length; ri++) {
            const rowWindows = rows[ri];
            const rowTile = new Tile();
            rowTile.layoutDirection = LayoutDirection.Horizontal;
            rowTile.size = rowHeights[ri];

            if (rowWindows === 1) {
                if (winIdx < windows.length) {
                    rowTile.windows = [windows[winIdx]];
                    winIdx++;
                }
            } else {
                rowTile.children = [];
                const vRatio = this.settings.getCurrentVerticalRatio(rowWindows);
                const colWidths = vRatio ? this.normalizeRatio(vRatio.parts, rowWindows) : this.equalParts(rowWindows);

                for (let ci = 0; ci < rowWindows; ci++) {
                    if (winIdx >= windows.length) break;
                    const colTile = new Tile();
                    colTile.layoutDirection = LayoutDirection.Vertical;
                    colTile.size = colWidths[ci];
                    colTile.windows = [windows[winIdx]];
                    winIdx++;
                    rowTile.children.push(colTile);
                }
            }
            root.children.push(rowTile);
        }
        return root;
    }

    private buildSingleColumn(windows: Window[]): Tile {
        const root = new Tile();
        root.layoutDirection = LayoutDirection.Vertical;
        root.size = 1;
        for (let i = 0; i < windows.length; i++) {
            const t = new Tile();
            t.windows = [windows[i]];
            t.size = 1 / windows.length;
            root.children.push(t);
        }
        return root;
    }

    private normalizeRatio(parts: number[], expectedLength: number): number[] {
        if (parts.length !== expectedLength) {
            return this.equalParts(expectedLength);
        }
        const sum = parts.reduce((a, b) => a + b, 0);
        if (sum === 0) return this.equalParts(expectedLength);
        return parts.map(p => p / sum);
    }

    private equalParts(n: number): number[] {
        return Array(n).fill(1 / n);
    }

    addWindow(window: Window, tile?: Tile, direction?: Direction): void {
        if (!this.windows.includes(window)) {
            this.windows.push(window);
        }
    }

    removeWindow(window: Window): void {
        const idx = this.windows.indexOf(window);
        if (idx !== -1) {
            this.windows.splice(idx, 1);
        }
    }

    placeWindow(window: Window, tile: Tile, direction?: Direction): void {
        if (!this.windows.includes(window)) {
            this.windows.push(window);
        }
    }

    windowActivated(window: Window): boolean {
        return false;
    }

    updateTiles(rootTile: Tile): void {
        // Sync sizes from the KWin-synced rootTile back to settings
        this.readBackRatios(rootTile);
    }

    private readBackRatios(rootTile: Tile): void {
        if (!rootTile.children || rootTile.children.length === 0) return;

        // Read horizontal ratios (top-level children sizes)
        const hParts = rootTile.children.map(c => c.size);
        if (hParts.length > 0) {
            const candidates = this.settings.getRatiosForArity(hParts.length);
            if (candidates.length > 0) {
                let bestIdx = 0;
                let bestDiff = Infinity;
                for (let i = 0; i < candidates.length; i++) {
                    const norm = this.normalizeRatio(candidates[i].parts, hParts.length);
                    const diff = norm.reduce((sum, n, idx) => sum + Math.abs(n - hParts[idx]), 0);
                    if (diff < bestDiff) {
                        bestDiff = diff;
                        bestIdx = i;
                    }
                }
                this.settings.horizontalRatioIndex = bestIdx;
            }
        }

        // Read vertical ratios (second level)
        for (const child of rootTile.children) {
            if (child.children && child.children.length > 0) {
                const vParts = child.children.map(c => c.size);
                const candidates = this.settings.getRatiosForArity(vParts.length);
                if (candidates.length > 0) {
                    let bestIdx = 0;
                    let bestDiff = Infinity;
                    for (let i = 0; i < candidates.length; i++) {
                        const norm = this.normalizeRatio(candidates[i].parts, vParts.length);
                        const diff = norm.reduce((sum, n, idx) => sum + Math.abs(n - vParts[idx]), 0);
                        if (diff < bestDiff) {
                            bestDiff = diff;
                            bestIdx = i;
                        }
                    }
                    this.settings.verticalRatioIndex = bestIdx;
                }
            }
        }
    }

    // Shortcut actions
    rotateLayout(): void {
        const count = this.windows.length;
        const candidates = this.settings.getLayoutsForCount(count);
        if (candidates.length === 0) return;
        const current = this.settings.getCurrentLayout(count);
        if (!current) return;

        const opposite = candidates.find(l => 
            l.cols.length === current.cols.length && 
            l.cols.every((v, i) => v === current.cols[i]) && 
            l.rotated !== current.rotated
        );
        if (opposite) {
            const allIndex = this.settings.layouts.indexOf(opposite);
            if (allIndex !== -1) {
                this.settings.layoutIndex = allIndex;
            }
        }
    }

    mirrorLayout(): void {
        const count = this.windows.length;
        const current = this.settings.getCurrentLayout(count);
        if (!current) return;

        const mirroredCols = [...current.cols].reverse();
        const mirrored: CustomLayout = {
            cols: mirroredCols,
            rotated: current.rotated,
            windowCount: current.windowCount,
        };
        
        let foundIdx = this.settings.layouts.findIndex(l => 
            l.cols.length === mirrored.cols.length &&
            l.cols.every((v, i) => v === mirrored.cols[i]) &&
            l.rotated === mirrored.rotated
        );
        if (foundIdx === -1) {
            this.settings.layouts.push(mirrored);
            this.settings.layouts.sort((a, b) => a.windowCount - b.windowCount);
            foundIdx = this.settings.layouts.indexOf(mirrored);
        }
        this.settings.layoutIndex = foundIdx;
    }

    cycleHorizontalRatio(): void {
        const count = this.windows.length;
        const current = this.settings.getCurrentLayout(count);
        if (!current) return;
        const arity = current.cols.length;
        const candidates = this.settings.getRatiosForArity(arity);
        if (candidates.length <= 1) return;
        this.settings.horizontalRatioIndex = (this.settings.horizontalRatioIndex + 1) % candidates.length;
    }

    cycleVerticalRatio(): void {
        const count = this.windows.length;
        const current = this.settings.getCurrentLayout(count);
        if (!current) return;
        const subCount = current.cols[0];
        const candidates = this.settings.getRatiosForArity(subCount);
        if (candidates.length <= 1) return;
        this.settings.verticalRatioIndex = (this.settings.verticalRatioIndex + 1) % candidates.length;
    }

    cycleLayout(): void {
        const count = this.windows.length;
        const candidates = this.settings.getLayoutsForCount(count);
        if (candidates.length <= 1) return;
        this.settings.layoutIndex = (this.settings.layoutIndex + 1) % candidates.length;
    }

    cycleWindowOrder(): void {
        if (this.windows.length === 0) return;
        this.settings.windowOrderOffset = (this.settings.windowOrderOffset + 1) % this.windows.length;
    }
}