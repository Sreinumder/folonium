import { console, controller as ctrl } from "..";
import { Display } from "../event";
import { TilingEngineType } from "../../engine";
import { DBus as DBusQml } from "../../extern";

interface SettingsBundle {
    engineType?: TilingEngineType;
    engineSettings?: object;
}

function settingsBundle(
    engineType: TilingEngineType,
    engineSettings: object,
): string {
    const bundle = {
        engineType: engineType,
        engineSettings: engineSettings,
    };
    return JSON.stringify(bundle);
}

export class DBusHandler {
    private dbusQml: DBusQml;

    constructor(dbusQml: DBusQml) {
        this.dbusQml = dbusQml;
        dbusQml
            .getSettings()
            .finished.connect(this.getSettingsCallback.bind(this));
        dbusQml
            .takeRequest()
            .finished.connect(this.takeRequestCallback.bind(this));
    }

    // Ask the saver for the command the overview left behind, if any.
    takeRequest(): void {
        this.dbusQml.takeRequest().call();
    }

    private takeRequestCallback([requestStr]: any[]): void {
        if (requestStr === undefined || requestStr === "") return;
        let request;
        try {
            request = JSON.parse(requestStr as string);
        } catch (e) {
            console().error(e);
            return;
        }
        if (request === null || typeof request !== "object") return;
        ctrl().handleRequest(request);
    }

    getSettings(display: Display): void {
        console().debug("getSettings called");
        this.dbusQml.getSettings().arguments = [display.toString()];
        this.dbusQml.getSettings().call();
    }

    private getSettingsCallback([
        desktopIdStr,
        settingsBundleStr,
    ]: any[]): void {
        console().debug(
            "getSettings dbus callback activated -",
            desktopIdStr,
            settingsBundleStr,
        );
        try {
            const display = ctrl().parseDisplay(desktopIdStr as string);
            if (display === undefined) return;
            const settingsBundle = JSON.parse(
                settingsBundleStr as string,
            ) as SettingsBundle;
            ctrl().queueEvent(
                {
                    t: "changeEngine",
                    display: display,
                    engineType: settingsBundle.engineType,
                    engineSettings: settingsBundle.engineSettings,
                    noDBusUpdate: true,
                },
                true,
            );
        } catch (e) {
            console().error(e);
        }
    }

    setSettings(
        display: Display,
        engineType: TilingEngineType,
        engineSettings: object,
    ): void {
        console().debug("setSettings called");
        this.dbusQml.setSettings().arguments = [
            display.toString(),
            settingsBundle(engineType, engineSettings),
        ];
        this.dbusQml.setSettings().call();
    }

    resetSettings(display: Display): void {
        console().debug("resetSettings called");
        this.dbusQml.resetSettings().arguments = [display.toString()];
        this.dbusQml.resetSettings().call();
    }
}
