// index.ts - Entry point from QML to TypeScript

import { QmlApi, QmlObjects } from "./extern";
import { initializeController, controller } from "./controller";
import { Display } from "./controller/event";

export function main(api: QmlApi, qmlObjects: QmlObjects) {
    Display.setWorkspace(api.workspace);
    initializeController(api, qmlObjects);
    // Adopt windows that were already open when this instance started.
    controller().adoptExistingWindows();
}
