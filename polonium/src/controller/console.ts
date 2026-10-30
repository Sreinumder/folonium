import { Console as QmlConsole } from "kwin-api/qt";
import { config } from ".";
import { LogLevel } from "./config";

export class Console {
    private console: QmlConsole;

    constructor(console: QmlConsole) {
        this.console = console;
    }

    debug(...args: any[]) {
        const cfg = config();
        if (!cfg || cfg.logLevel < LogLevel.Debug) return;
        this.console.info("Polonium DBG:", ...args);
    }

    log(...args: any[]) {
        const cfg = config();
        if (!cfg || cfg.logLevel < LogLevel.Log) return;
        // use console.info for all log levels (except warning and error)
        this.console.info("Polonium LOG:", ...args);
    }
    warn(...args: any[]) {
        const cfg = config();
        if (!cfg || cfg.logLevel < LogLevel.Warn) return;
        this.console.warn("Polonium WRN:", ...args);
    }
    error(...args: any[]) {
        this.console.error("Polonium ERR:", ...args);
    }
}
