#!/usr/bin/env bash
# Install or uninstall the three pieces of this repo:
#   - the Folonium KWin tiling script
#   - the Folonium overview KWin effect
#   - the folonium-saver D-Bus service (settings, media, pointer warps)
#
# Usage: ./install.sh [install|uninstall]

set -euo pipefail

REPO=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
DATA=${XDG_DATA_HOME:-$HOME/.local/share}
CONFIG=${XDG_CONFIG_HOME:-$HOME/.config}

SCRIPT_DIR=$DATA/kwin/scripts/folonium
EFFECT_DIR=$DATA/kwin/effects/foloniumoverview
SAVER_DIR=$DATA/folonium-saver
SERVICE_FILE=$DATA/dbus-1/services/xyz.vaughanm.folonium.service
SETTINGS_APP=$DATA/applications/folonium-settings.desktop

say() { printf '%s\n' "$*"; }
die() { printf 'error: %s\n' "$*" >&2; exit 1; }

qdbus_cmd() {
    if command -v qdbus6 >/dev/null 2>&1; then
        qdbus6 "$@"
    elif command -v qdbus >/dev/null 2>&1; then
        qdbus "$@"
    else
        return 1
    fi
}

kwin_running() {
    qdbus_cmd org.kde.KWin /KWin >/dev/null 2>&1
}

set_plugin() {
    local key=$1 value=$2
    if command -v kwriteconfig6 >/dev/null 2>&1; then
        kwriteconfig6 --file kwinrc --group Plugins --key "$key" "$value"
    elif command -v kwriteconfig5 >/dev/null 2>&1; then
        kwriteconfig5 --file kwinrc --group Plugins --key "$key" "$value"
    else
        die "kwriteconfig6/kwriteconfig5 not found"
    fi
}

check_sources() {
    local f
    for f in \
        "$REPO/folonium/src/index.ts" \
        "$REPO/folonium/res/main.js" \
        "$REPO/folonium/res/main.xml" \
        "$REPO/folonium/res/config.ui" \
        "$REPO/folonium/res/metadata.json" \
        "$REPO/folonium-overview/metadata.json" \
        "$REPO/folonium-overview/contents/config/main.xml" \
        "$REPO/folonium-overview/contents/ui/main.qml" \
        "$REPO/folonium-overview/contents/ui/ScreenView.qml" \
        "$REPO/folonium-overview/contents/ui/config.ui" \
        "$REPO/folonium-saver/folonium_saver.py"; do
        [ -f "$f" ] || die "missing $f"
    done
}

install_script() {
    local version
    version=$(sed -n 's/^ *"version": *"\([^"]*\)".*/\1/p' "$REPO/folonium/package.json" | head -n1)
    version=${version:-0.0.0}

    say "Installing tiling script to $SCRIPT_DIR"
    rm -rf -- "$SCRIPT_DIR"
    install -d -- "$SCRIPT_DIR/contents/code" "$SCRIPT_DIR/contents/config" "$SCRIPT_DIR/contents/ui"
    install -m 644 -- "$REPO/folonium/src/index.ts" "$SCRIPT_DIR/contents/code/main.mjs"
    install -m 644 -- "$REPO/folonium/res/main.js" "$SCRIPT_DIR/contents/code/main.js"
    install -m 644 -- "$REPO/folonium/src/qml/"*.qml "$SCRIPT_DIR/contents/ui/"
    install -m 644 -- "$REPO/folonium/res/config.ui" "$SCRIPT_DIR/contents/ui/config.ui"
    install -m 644 -- "$REPO/folonium/res/main.xml" "$SCRIPT_DIR/contents/config/main.xml"
    sed -e "s/%VERSION%/$version/g" -e "s/%NAME%/folonium/g" \
        "$REPO/folonium/res/metadata.json" > "$SCRIPT_DIR/metadata.json"
}

install_effect() {
    say "Installing overview effect to $EFFECT_DIR"
    rm -rf -- "$EFFECT_DIR"
    install -d -- "$EFFECT_DIR/contents/config" "$EFFECT_DIR/contents/ui"
    install -m 644 -- "$REPO/folonium-overview/metadata.json" "$EFFECT_DIR/metadata.json"
    install -m 644 -- "$REPO/folonium-overview/contents/config/main.xml" "$EFFECT_DIR/contents/config/main.xml"
    install -m 644 -- "$REPO/folonium-overview/contents/ui/"*.qml "$EFFECT_DIR/contents/ui/"
    install -m 644 -- "$REPO/folonium-overview/contents/ui/config.ui" "$EFFECT_DIR/contents/ui/config.ui"
}

install_saver() {
    local python
    python=$(command -v python3) || die "python3 not found"
    say "Installing saver to $SAVER_DIR"
    rm -rf -- "$SAVER_DIR"
    install -d -- "$SAVER_DIR"
    install -m 644 -- "$REPO/folonium-saver/folonium_saver.py" "$SAVER_DIR/folonium_saver.py"

    say "Writing D-Bus service $SERVICE_FILE"
    install -d -- "$(dirname -- "$SERVICE_FILE")"
    cat > "$SERVICE_FILE" <<EOF
[D-BUS Service]
Name=xyz.vaughanm.folonium
Exec="$python" "$SAVER_DIR/folonium_saver.py"
EOF
}

restart_saver() {
    pkill -f -- "$SAVER_DIR/folonium_saver.py" >/dev/null 2>&1 || true
    sleep 0.2
    qdbus_cmd xyz.vaughanm.folonium /saver xyz.vaughanm.folonium.Ping >/dev/null 2>&1 || true
}

reload_kwin() {
    if ! kwin_running; then
        say "KWin is not running; the script and effect load at the next start."
        return
    fi
    say "Reloading KWin script and effect"
    qdbus_cmd org.kde.KWin /Scripting org.kde.kwin.Scripting.unloadScript folonium >/dev/null 2>&1 || true
    # KWin's QML engine keeps components and imported modules cached by URL, so
    # unloading and reloading the same path would keep running the old code.
    # Load a fresh copy from a new path instead; the canonical package path is
    # what KWin uses at the next login, when there is no cache to worry about.
    local load_root=${XDG_RUNTIME_DIR:-/tmp}
    rm -rf -- "$load_root"/folonium-load.* 2>/dev/null || true
    local load_dir
    load_dir=$(mktemp -d "$load_root/folonium-load.XXXXXX")
    cp -a -- "$SCRIPT_DIR/contents" "$load_dir/contents"
    qdbus_cmd org.kde.KWin /Scripting org.kde.kwin.Scripting.loadDeclarativeScript \
        "$load_dir/contents/ui/main.qml" folonium >/dev/null 2>&1 || true
    # A declarative script only runs after start(); without it the script is
    # loaded but never initializes (no states, no tiling).
    qdbus_cmd org.kde.KWin /Scripting org.kde.kwin.Scripting.start >/dev/null 2>&1 || true
    qdbus_cmd org.kde.KWin /Effects org.kde.kwin.Effects.unloadEffect foloniumoverview >/dev/null 2>&1 || true
    qdbus_cmd org.kde.KWin /Effects org.kde.kwin.Effects.loadEffect foloniumoverview >/dev/null 2>&1 || true
}

# The rename from Polonium keeps user data: move the old kwinrc groups over
# byte-for-byte and copy the settings store, so layouts and options survive.
# Renaming the group header in place is what keeps escaped layout text intact;
# reading values back and rewriting them would escape the escapes.
migrate_from_polonium() {
    local old_cfg=$HOME/.config/polonium
    local new_cfg=$HOME/.config/folonium

    if [ ! -e "$new_cfg/settings.json" ] && [ -e "$old_cfg/settings.json" ]; then
        say "Migrating Polonium settings to Folonium"
        install -d -- "$new_cfg"
        cp -p -- "$old_cfg/settings.json" "$new_cfg/settings.json"
    fi

    command -v python3 >/dev/null 2>&1 || return 0
    python3 - "$HOME/.config/kwinrc" <<'PYEOF' || true
import os, sys

path = sys.argv[1]
if not os.path.exists(path):
    raise SystemExit(0)

moves = {
    "[Script-polonium]": "[Script-folonium]",
    "[Effect-betteroverview]": "[Effect-foloniumoverview]",
}

with open(path, encoding="utf-8") as fh:
    lines = fh.read().splitlines(keepends=True)

present = {line.strip() for line in lines if line.startswith("[")}
changed = False
out = []
for line in lines:
    key = line.strip()
    if key in moves and moves[key] not in present:
        out.append(line.replace(key, moves[key], 1))
        changed = True
    else:
        out.append(line)

if changed:
    with open(path, "w", encoding="utf-8") as fh:
        fh.writelines(out)
    print("  moved old kwinrc groups to the folonium names")
PYEOF
}

clear_folonium_cache() {
    # Clear folonium saver cache/state only; keep settings.json and kwinrc.
    rm -rf -- "$HOME/.cache/folonium" "$HOME/.cache/folonium-saver" "$HOME/.cache/folonium-saver-state" 2>/dev/null || true
    rm -rf -- "$HOME/.local/share/folonium-saver/cache" "$HOME/.local/share/folonium/cache" 2>/dev/null || true
    # Remove any stray cache files under ~/.config/folonium but keep settings.json
    if [ -d "$HOME/.config/folonium" ]; then
        find "$HOME/.config/folonium" -mindepth 1 -maxdepth 1 ! -name settings.json -exec rm -rf -- {} + 2>/dev/null || true
    fi
    if [ -d "$HOME/.config/folonium-saver" ]; then
        find "$HOME/.config/folonium-saver" -mindepth 1 -maxdepth 1 ! -name settings.json -exec rm -rf -- {} + 2>/dev/null || true
    fi
}

install_all() {
    check_sources
    migrate_from_polonium
    install_script
    install_effect
    clear_folonium_cache
    install_saver
    set_plugin foloniumEnabled true
    set_plugin foloniumoverviewEnabled true
    if command -v kwriteconfig6 >/dev/null 2>&1; then
        kwriteconfig6 --file kwinrc --group Script-folonium --key UseDBusSaver true --type bool
    elif command -v kwriteconfig5 >/dev/null 2>&1; then
        kwriteconfig5 --file kwinrc --group Script-folonium --key UseDBusSaver true --type bool
    fi
    restart_saver
    reload_kwin
    say "Done. Toggle the overview with Meta+G (KWin shortcut \"Better Overview\")."
}

uninstall_all() {
    say "Disabling Folonium and the overview in kwinrc"
    set_plugin foloniumEnabled false
    set_plugin foloniumoverviewEnabled false

    if kwin_running; then
        say "Unloading KWin script and effect"
        qdbus_cmd org.kde.KWin /Scripting org.kde.kwin.Scripting.unloadScript folonium >/dev/null 2>&1 || true
        qdbus_cmd org.kde.KWin /Effects org.kde.kwin.Effects.unloadEffect foloniumoverview >/dev/null 2>&1 || true
    fi

    say "Stopping saver"
    pkill -f -- "$SAVER_DIR/folonium_saver.py" >/dev/null 2>&1 || true

    say "Removing installed files"
    rm -rf -- "$SCRIPT_DIR" "$EFFECT_DIR" "$SAVER_DIR"
    rm -rf -- "${XDG_RUNTIME_DIR:-/tmp}"/folonium-load.* 2>/dev/null || true
    rm -f -- "$SERVICE_FILE" "$SETTINGS_APP"

    clear_folonium_cache
    say "Done. Your settings in ~/.config/folonium/settings.json and kwinrc were kept."
}

case ${1:-install} in
    install) install_all ;;
    uninstall|remove) uninstall_all ;;
    -h|--help|help)
        say "Usage: $0 [install|uninstall]"
        say "  install    copy and enable the tiling script, overview effect and saver"
        say "  uninstall  disable and remove them, keeping your settings"
        ;;
    *) die "unknown action '$1' (use install or uninstall)" ;;
esac
