#!/usr/bin/env bash
# Install or uninstall the three pieces of this repo:
#   - the Polonium KWin tiling script
#   - the Polonium overview KWin effect
#   - the polonium-saver D-Bus service (settings, media, pointer warps)
#
# Usage: ./install.sh [install|uninstall]

set -euo pipefail

REPO=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
DATA=${XDG_DATA_HOME:-$HOME/.local/share}
CONFIG=${XDG_CONFIG_HOME:-$HOME/.config}

SCRIPT_DIR=$DATA/kwin/scripts/polonium
EFFECT_DIR=$DATA/kwin/effects/betteroverview
SAVER_DIR=$DATA/polonium-saver
SERVICE_FILE=$DATA/dbus-1/services/xyz.vaughanm.polonium.service
SETTINGS_APP=$DATA/applications/polonium-settings.desktop

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
        "$REPO/polonium/src/index.ts" \
        "$REPO/polonium/res/main.js" \
        "$REPO/polonium/res/main.xml" \
        "$REPO/polonium/res/config.ui" \
        "$REPO/polonium/res/metadata.json" \
        "$REPO/polonium-overview/metadata.json" \
        "$REPO/polonium-overview/contents/config/main.xml" \
        "$REPO/polonium-overview/contents/ui/main.qml" \
        "$REPO/polonium-overview/contents/ui/ScreenView.qml" \
        "$REPO/polonium-overview/contents/ui/config.ui" \
        "$REPO/polonium-saver/polonium_saver.py"; do
        [ -f "$f" ] || die "missing $f"
    done
}

install_script() {
    local version
    version=$(sed -n 's/^ *"version": *"\([^"]*\)".*/\1/p' "$REPO/polonium/package.json" | head -n1)
    version=${version:-0.0.0}

    say "Installing tiling script to $SCRIPT_DIR"
    rm -rf -- "$SCRIPT_DIR"
    install -d -- "$SCRIPT_DIR/contents/code" "$SCRIPT_DIR/contents/config" "$SCRIPT_DIR/contents/ui"
    install -m 644 -- "$REPO/polonium/src/index.ts" "$SCRIPT_DIR/contents/code/main.mjs"
    install -m 644 -- "$REPO/polonium/res/main.js" "$SCRIPT_DIR/contents/code/main.js"
    install -m 644 -- "$REPO/polonium/src/qml/"*.qml "$SCRIPT_DIR/contents/ui/"
    install -m 644 -- "$REPO/polonium/res/config.ui" "$SCRIPT_DIR/contents/ui/config.ui"
    install -m 644 -- "$REPO/polonium/res/main.xml" "$SCRIPT_DIR/contents/config/main.xml"
    sed -e "s/%VERSION%/$version/g" -e "s/%NAME%/polonium/g" \
        "$REPO/polonium/res/metadata.json" > "$SCRIPT_DIR/metadata.json"
}

install_effect() {
    say "Installing overview effect to $EFFECT_DIR"
    rm -rf -- "$EFFECT_DIR"
    install -d -- "$EFFECT_DIR/contents/config" "$EFFECT_DIR/contents/ui"
    install -m 644 -- "$REPO/polonium-overview/metadata.json" "$EFFECT_DIR/metadata.json"
    install -m 644 -- "$REPO/polonium-overview/contents/config/main.xml" "$EFFECT_DIR/contents/config/main.xml"
    install -m 644 -- "$REPO/polonium-overview/contents/ui/"*.qml "$EFFECT_DIR/contents/ui/"
    install -m 644 -- "$REPO/polonium-overview/contents/ui/config.ui" "$EFFECT_DIR/contents/ui/config.ui"
}

install_saver() {
    local python
    python=$(command -v python3) || die "python3 not found"
    say "Installing saver to $SAVER_DIR"
    rm -rf -- "$SAVER_DIR"
    install -d -- "$SAVER_DIR"
    install -m 644 -- "$REPO/polonium-saver/polonium_saver.py" "$SAVER_DIR/polonium_saver.py"

    say "Writing D-Bus service $SERVICE_FILE"
    install -d -- "$(dirname -- "$SERVICE_FILE")"
    cat > "$SERVICE_FILE" <<EOF
[D-BUS Service]
Name=xyz.vaughanm.polonium
Exec="$python" "$SAVER_DIR/polonium_saver.py"
EOF
}

restart_saver() {
    pkill -f -- "$SAVER_DIR/polonium_saver.py" >/dev/null 2>&1 || true
    sleep 0.2
    qdbus_cmd xyz.vaughanm.polonium /saver xyz.vaughanm.polonium.Ping >/dev/null 2>&1 || true
}

reload_kwin() {
    if ! kwin_running; then
        say "KWin is not running; the script and effect load at the next start."
        return
    fi
    say "Reloading KWin script and effect"
    qdbus_cmd org.kde.KWin /Scripting org.kde.kwin.Scripting.unloadScript polonium >/dev/null 2>&1 || true
    qdbus_cmd org.kde.KWin /Scripting org.kde.kwin.Scripting.loadDeclarativeScript \
        "$SCRIPT_DIR/contents/ui/main.qml" polonium >/dev/null 2>&1 || true
    qdbus_cmd org.kde.KWin /Effects org.kde.kwin.Effects.unloadEffect betteroverview >/dev/null 2>&1 || true
    qdbus_cmd org.kde.KWin /Effects org.kde.kwin.Effects.loadEffect betteroverview >/dev/null 2>&1 || true
}

clear_polonium_cache() {
    # Clear polonium saver cache/state only; keep settings.json and kwinrc.
    rm -rf -- "$HOME/.cache/polonium" "$HOME/.cache/polonium-saver" "$HOME/.cache/polonium-saver-state" 2>/dev/null || true
    rm -rf -- "$HOME/.local/share/polonium-saver/cache" "$HOME/.local/share/polonium/cache" 2>/dev/null || true
    # Remove any stray cache files under ~/.config/polonium but keep settings.json
    if [ -d "$HOME/.config/polonium" ]; then
        find "$HOME/.config/polonium" -mindepth 1 -maxdepth 1 ! -name settings.json -exec rm -rf -- {} + 2>/dev/null || true
    fi
    if [ -d "$HOME/.config/polonium-saver" ]; then
        find "$HOME/.config/polonium-saver" -mindepth 1 -maxdepth 1 ! -name settings.json -exec rm -rf -- {} + 2>/dev/null || true
    fi
}

install_all() {
    check_sources
    install_script
    install_effect
    clear_polonium_cache
    install_saver
    set_plugin poloniumEnabled true
    set_plugin betteroverviewEnabled true
    restart_saver
    reload_kwin
    say "Done. Toggle the overview with Meta+G (KWin shortcut \"Better Overview\")."
}

uninstall_all() {
    say "Disabling Polonium and the overview in kwinrc"
    set_plugin poloniumEnabled false
    set_plugin betteroverviewEnabled false

    if kwin_running; then
        say "Unloading KWin script and effect"
        qdbus_cmd org.kde.KWin /Scripting org.kde.kwin.Scripting.unloadScript polonium >/dev/null 2>&1 || true
        qdbus_cmd org.kde.KWin /Effects org.kde.kwin.Effects.unloadEffect betteroverview >/dev/null 2>&1 || true
    fi

    say "Stopping saver"
    pkill -f -- "$SAVER_DIR/polonium_saver.py" >/dev/null 2>&1 || true

    say "Removing installed files"
    rm -rf -- "$SCRIPT_DIR" "$EFFECT_DIR" "$SAVER_DIR"
    rm -f -- "$SERVICE_FILE" "$SETTINGS_APP"

    clear_polonium_cache
    say "Done. Your settings in ~/.config/polonium/settings.json and kwinrc were kept."
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
