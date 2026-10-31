#!/usr/bin/env python3
"""Per-display settings saver for the Folonium KWin script.

SPDX-FileCopyrightText: 2026 Sreinumder
SPDX-License-Identifier: MIT

Exposes the xyz.vaughanm.folonium /saver interface that folonium's
contents/ui/dbus.qml expects (all args and returns are plain strings):

    GetSettings(s displayKey) -> (s displayKey, s bundleJson)
    SetSettings(s displayKey, s bundleJson)
    ResetSettings(s displayKey)
    SetGlobalSetting(s key, s value)
    SetState(s displayKey, s stateJson)
    GetState(s displayKey) -> (s stateJson)
    GetStates() -> (s statesJson)
    GetMedia() -> (s playersJson)
    MediaAction(s player, s action, s value)

A displayKey is folonium's Display.toString(), e.g.
    {"d":"3","a":"6b3d...","o":"DP-1"}

The stored bundle is the script's JSON blob: engineType, engineSettings,
and optionally lastEngine / lastEngineSettings so a display that was left on
KWin's engine comes back with the same Custom layout when toggled back.

GetSettings returns ("", "") when nothing is stored for a key; the script
side treats that as "keep whatever you already have".

The state methods are volatile: folonium pushes the layout text and monocle
flag for each display on every rebuild so the overview effect can label its
desktops, and GetState returns "" for a display it never heard from. Nothing
here is persisted, so a restart starts with an empty map.

GetMedia and MediaAction exist because QML's DBusCall cannot produce the
object-path and int64 arguments MPRIS seeking needs. The overview effect asks
for one JSON snapshot and sends plain string commands back.

Storage is one JSON file, written atomically (temp file + rename), with
writes debounced so dragging a divider does not hammer the disk.

Implemented with jeepney so there is no python-dbus/C-extension dependency.
"""

import json
import os
import subprocess
import tempfile
import threading
import time
from collections import deque

from jeepney import DBusAddress, MatchRule, MessageType, new_method_call
from jeepney.io.blocking import open_dbus_connection
from jeepney.low_level import Header, HeaderFields, Message, MessageFlag

ERROR_UNKNOWN_METHOD = "org.freedesktop.DBus.Error.UnknownMethod"
ERROR_UNKNOWN_INTERFACE = "org.freedesktop.DBus.Error.UnknownInterface"
ERROR_UNKNOWN_OBJECT = "org.freedesktop.DBus.Error.UnknownObject"

SERVICE = "xyz.vaughanm.folonium"
PATH = "/saver"
IFACE = "xyz.vaughanm.folonium"
DBUS_IFACE = "org.freedesktop.DBus"
DBUS_PATH = "/org/freedesktop/DBus"
FLUSH_DELAY = 0.4
POLL_TIMEOUT = 0.25

CONFIG_HOME = os.environ.get("XDG_CONFIG_HOME") or os.path.expanduser("~/.config")
STORE_PATH = os.path.join(CONFIG_HOME, "folonium", "settings.json")

# Script-wide options the popup can change. They live in kwinrc under the
# script's group, which is where the script's readConfig() looks; the script
# itself has no way to write a config file, so it asks us. Keep this a
# whitelist: the value arrives over D-Bus and ends up in a config file.
KWIN_CONFIG = "kwinrc"
KWIN_GROUP = "Script-folonium"
GLOBAL_KEYS = {
    "AutoFitStubbornWindows": "bool",
}

MPRIS_PREFIX = "org.mpris.MediaPlayer2"
MPRIS_PATH = "/org/mpris/MediaPlayer2"
MPRIS_IFACE = "org.mpris.MediaPlayer2"
PLAYER_IFACE = "org.mpris.MediaPlayer2.Player"
PROPS_IFACE = "org.freedesktop.DBus.Properties"
STATE_LIMIT = 4096


def variant_value(props, key, default=None):
    """jeepney decodes a variant as a (signature, value) tuple."""
    entry = props.get(key)
    return default if entry is None else entry[1]


def log(msg):
    print(f"folonium-saver: {msg}", flush=True)


def pointer_pos():
    """The real pointer in screen coordinates, or None if kdotool is missing."""
    try:
        out = subprocess.run(
            ["kdotool", "getmouselocation"],
            capture_output=True,
            text=True,
            timeout=1,
        ).stdout
    except (OSError, subprocess.SubprocessError):
        return None
    x = y = None
    for part in out.split():
        if part.startswith("x:"):
            x = int(part[2:] or 0)
        elif part.startswith("y:"):
            y = int(part[2:] or 0)
    return None if x is None or y is None else (x, y)


class Store:
    def __init__(self, path):
        self.path = path
        self.data = {"version": 1, "displays": {}}
        self._dirty_at = None
        self.load()

    def load(self):
        try:
            with open(self.path, "r", encoding="utf-8") as fh:
                raw = json.load(fh)
            if isinstance(raw, dict) and isinstance(raw.get("displays"), dict):
                self.data = raw
                self.data.setdefault("version", 1)
                log(f"loaded {len(self.data['displays'])} stored display(s)")
            else:
                log("store file had an unexpected shape, starting empty")
        except FileNotFoundError:
            log("no store yet, starting empty")
        except (OSError, ValueError) as exc:
            # Never let a corrupt file stop the service; keep a copy to inspect.
            try:
                os.replace(self.path, self.path + ".corrupt")
                log(f"store unreadable ({exc}); moved aside to {self.path}.corrupt")
            except OSError:
                log(f"store unreadable ({exc}) and could not be moved aside")

    def get(self, key):
        return self.data["displays"].get(key)

    def set(self, key, engine_type, engine_settings, last_engine=None,
            last_engine_settings=None):
        entry = {
            "engineType": engine_type,
            "engineSettings": engine_settings,
        }
        # The tiling engine to come back to when KWin's untiled mode is toggled
        # off again. Optional so older bundles still load.
        if isinstance(last_engine, int) and not isinstance(last_engine, bool):
            entry["lastEngine"] = last_engine
        # Settings belonging to lastEngine. Kept separately because
        # engineSettings describes KWin's empty settings while KWin is active.
        if isinstance(last_engine_settings, dict):
            entry["lastEngineSettings"] = last_engine_settings
        self.data["displays"][key] = entry
        self._dirty_at = time.monotonic()

    def delete(self, key):
        if key in self.data["displays"]:
            del self.data["displays"][key]
            self._dirty_at = time.monotonic()
            return True
        return False

    def tick(self):
        """Flush if a debounced write is due. Call from the main loop."""
        if self._dirty_at is None:
            return
        if time.monotonic() - self._dirty_at < FLUSH_DELAY:
            return
        self.flush()

    def flush(self):
        if self._dirty_at is None:
            return
        self._dirty_at = None
        tmp = None
        try:
            os.makedirs(os.path.dirname(self.path), exist_ok=True)
            fd, tmp = tempfile.mkstemp(
                dir=os.path.dirname(self.path), prefix=".settings-", suffix=".json"
            )
            with os.fdopen(fd, "w", encoding="utf-8") as fh:
                json.dump(self.data, fh, indent=2, sort_keys=True)
                fh.flush()
                os.fsync(fh.fileno())
            os.replace(tmp, self.path)
            tmp = None
            log(f"wrote {len(self.data['displays'])} display(s)")
        except OSError as exc:
            log(f"failed to write store: {exc}")
        finally:
            if tmp is not None:
                try:
                    os.unlink(tmp)
                except OSError:
                    pass


def valid_display_key(key):
    try:
        parsed = json.loads(key)
    except (ValueError, TypeError):
        return None
    if not isinstance(parsed, dict):
        return None
    if not all(field in parsed for field in ("d", "a", "o")):
        return None
    return parsed


def coerce_display_key(value):
    """Accept either the string folonium sends or a dict from lenient clients.

    KWin's DBusCall passes a plain QString, but callers such as `gdbus call`
    can infer a{ss} from the JSON-looking argument, so normalise both.
    """
    if isinstance(value, dict):
        if not all(field in value for field in ("d", "a", "o")):
            return None
        return json.dumps({field: str(value[field]) for field in ("d", "a", "o")},
                          separators=(",", ":"))
    if isinstance(value, str):
        return value if valid_display_key(value) is not None else None
    return None


class Media:
    """A flat MPRIS snapshot plus the few typed calls QML cannot make."""

    def __init__(self, conn):
        self.conn = conn
        # Last artwork seen per player. plasma-browser-integration rewrites the
        # artwork file mid-track and reports artUrl:"" until the new one lands;
        # holding the previous URL keeps the cover steady instead of blinking.
        self.art_cache = {}

    def call(self, bus_name, path, interface, member, signature="", body=()):
        address = DBusAddress(path, bus_name=bus_name, interface=interface)
        return self.conn.send_and_get_reply(
            new_method_call(address, member, signature, body)
        ).body

    def properties(self, player):
        return self.call(
            player, MPRIS_PATH, PROPS_IFACE, "GetAll", "s", (PLAYER_IFACE,)
        )[0]

    def desktop_entry(self, player):
        """The .desktop name some players publish, used to find their window."""
        try:
            reply = self.call(
                player,
                MPRIS_PATH,
                PROPS_IFACE,
                "Get",
                "ss",
                (MPRIS_IFACE, "DesktopEntry"),
            )
        except Exception:
            return ""
        value = reply[0]
        if isinstance(value, tuple):
            value = value[1]
        return str(value or "")

    @staticmethod
    def icon_name(entry):
        """MPRIS gives the .desktop name; the icon usually lives inside it."""
        if not entry:
            return ""
        for base in (
            "~/.local/share/applications",
            "/usr/local/share/applications",
            "/usr/share/applications",
        ):
            path = os.path.join(os.path.expanduser(base), entry + ".desktop")
            try:
                with open(path, "r", encoding="utf-8") as fh:
                    for line in fh:
                        if line.startswith("Icon="):
                            return line[len("Icon=") :].strip()
            except OSError:
                continue
        return entry

    def snapshot(self):
        players = []
        names = self.call(DBUS_IFACE, DBUS_PATH, DBUS_IFACE, "ListNames")[0]
        for name in names:
            if not name.startswith(MPRIS_PREFIX):
                continue
            # Chromium-style names can be on the bus while exporting nothing.
            try:
                props = self.properties(name)
            except Exception as exc:
                log(f"media: {name} is not reachable: {exc!r}")
                continue
            status = variant_value(props, "PlaybackStatus", "Stopped")
            if status == "Stopped":
                continue
            metadata = variant_value(props, "Metadata", {}) or {}
            artists = variant_value(metadata, "xesam:artist", [])
            if isinstance(artists, str):
                artist = artists
            else:
                artist = ", ".join(a for a in artists if a)
            entry = self.desktop_entry(name)
            art = variant_value(metadata, "mpris:artUrl", "") or ""
            track_id = variant_value(metadata, "mpris:trackid", "") or ""
            if art:
                self.art_cache[name] = (track_id, art)
            else:
                # Fall back to the last good art for this player, but only
                # while it is the same track: a new track with no art is a
                # genuine "no artwork" case.
                track = variant_value(metadata, "mpris:trackid", "") or ""
                cached = self.art_cache.get(name)
                if cached:
                    cached_track, cached_art = cached
                    if cached_track == track:
                        art = cached_art
            players.append(
                {
                    "player": name,
                    "app": name[len(MPRIS_PREFIX) + 1 :].split(".")[0],
                    "status": status,
                    "title": variant_value(metadata, "xesam:title", "") or "",
                    "artist": artist,
                    "url": variant_value(metadata, "xesam:url", "") or "",
                    "art": art,
                    "length": int(variant_value(metadata, "mpris:length", 0) or 0),
                    "position": int(variant_value(props, "Position", 0) or 0),
                    "rate": float(variant_value(props, "Rate", 1.0) or 1.0),
                    "canSeek": bool(variant_value(props, "CanSeek", False)),
                    "canControl": bool(variant_value(props, "CanControl", False)),
                    "canNext": bool(variant_value(props, "CanGoNext", False)),
                    "canPrevious": bool(variant_value(props, "CanGoPrevious", False)),
                    "canShuffle": "Shuffle" in props,
                    "canLoop": "LoopStatus" in props,
                    "shuffle": bool(variant_value(props, "Shuffle", False)),
                    "loop": variant_value(props, "LoopStatus", "") or "",
                    # plasma-browser-integration reports the browser's pid, and
                    # that is what the overview matches against open windows.
                    "pid": int(variant_value(metadata, "kde:pid", 0) or 0),
                    # Used when the pid does not lead to the player's window.
                    "desktopEntry": entry,
                    "icon": self.icon_name(entry),
                }
            )
        # Firefox and plasma-browser-integration both publish the same track;
        # keep the copy that carries the artwork and the length.
        players.sort(
            key=lambda p: (bool(p["art"]), bool(p["length"]), bool(p["title"])),
            reverse=True,
        )
        out = []
        seen = set()
        for player in players:
            # Two players exposing one playback (Firefox and the browser
            # integration) answer the same Seek; key on the track, not the url,
            # so only one card owns it.
            if player["title"]:
                key = (player["title"], player["artist"])
            elif player["url"]:
                key = player["url"]
            else:
                key = player["player"]
            if key in seen:
                continue
            seen.add(key)
            out.append(player)
        return json.dumps({"players": out, "at": int(time.time() * 1000)})

    def action(self, player, action, value):
        if player != MPRIS_PREFIX and not player.startswith(MPRIS_PREFIX + "."):
            raise LookupError(f"not an MPRIS player: {player}")
        if action == "playpause":
            self.call(player, MPRIS_PATH, PLAYER_IFACE, "PlayPause")
        elif action == "next":
            self.call(player, MPRIS_PATH, PLAYER_IFACE, "Next")
        elif action == "previous":
            self.call(player, MPRIS_PATH, PLAYER_IFACE, "Previous")
        elif action == "seek":
            target = int(value)
            props = self.properties(player)
            metadata = variant_value(props, "Metadata", {}) or {}
            track = variant_value(metadata, "mpris:trackid", "") or ""
            if track:
                try:
                    self.call(
                        player,
                        MPRIS_PATH,
                        PLAYER_IFACE,
                        "SetPosition",
                        "ox",
                        (track, target),
                    )
                    return
                except Exception as exc:
                    log(f"media: SetPosition failed on {player}: {exc!r}")
            current = int(variant_value(props, "Position", 0) or 0)
            self.call(
                player, MPRIS_PATH, PLAYER_IFACE, "Seek", "x", (target - current,)
            )
        elif action == "shuffle":
            props = self.properties(player)
            current = bool(variant_value(props, "Shuffle", False))
            self.call(
                player,
                MPRIS_PATH,
                PROPS_IFACE,
                "Set",
                "ssv",
                (PLAYER_IFACE, "Shuffle", ("b", not current)),
            )
        elif action == "loop":
            # None -> Track -> Playlist -> None, like most players' own button.
            order = ["None", "Track", "Playlist"]
            current = variant_value(self.properties(player), "LoopStatus", "None")
            nxt = order[(order.index(current) + 1) % len(order)] if current in order else "Track"
            self.call(
                player,
                MPRIS_PATH,
                PROPS_IFACE,
                "Set",
                "ssv",
                (PLAYER_IFACE, "LoopStatus", ("s", nxt)),
            )
        elif action == "seekby":
            self.call(player, MPRIS_PATH, PLAYER_IFACE, "Seek", "x", (int(value),))
        elif action == "open":
            # Nothing of that player is on screen: hand the track to the desktop.
            if value:
                subprocess.Popen(
                    ["xdg-open", value],
                    start_new_session=True,
                    stdout=subprocess.DEVNULL,
                    stderr=subprocess.DEVNULL,
                )
        elif action == "rate":
            self.call(
                player,
                MPRIS_PATH,
                PROPS_IFACE,
                "Set",
                "ssv",
                (PLAYER_IFACE, "Rate", ("d", float(value))),
            )
        elif action == "raise":
            # MPRIS Raise is on the root interface, not the Player one. Some
            # players do not implement it, so the failure is not fatal: the
            # overview also activates the player's window by its app id.
            try:
                self.call(player, MPRIS_PATH, MPRIS_IFACE, "Raise")
            except Exception as exc:
                log(f"media: Raise failed on {player}: {exc!r}")
        else:
            raise LookupError(f"no such media action: {action}")


class Saver:
    def __init__(self, store, media_conn=None):
        self.store = store
        # Volatile per-display state for the overview effect; never persisted.
        self.state = {}
        # One pending command from the overview effect to the script.
        self.request = ""
        # Cursor position for hover desktop switching.
        self.cursor_x = 0
        self.cursor_y = 0
        self.media = Media(media_conn) if media_conn is not None else None

    def dispatch(self, member, args):
        """Returns (signature, body) for a method call."""
        if member == "GetSettings":
            return ("ss", self.get_settings(args[0]))
        if member == "SetSettings":
            self.set_settings(args[0], args[1])
            return ("", ())
        if member == "ResetSettings":
            self.reset_settings(args[0])
            return ("", ())
        if member == "SetGlobalSetting":
            self.set_global_setting(args[0], args[1])
            return ("", ())
        if member == "SetState":
            self.set_state(args[0], args[1])
            return ("", ())
        if member == "GetState":
            return ("s", (self.get_state(args[0]),))
        if member == "GetStates":
            return ("s", (json.dumps(self.state),))
        if member == "SetRequest":
            self.set_request(args[0])
            return ("", ())
        if member == "TakeRequest":
            return ("s", (self.take_request(),))
        if member == "GetMedia":
            if self.media is None:
                return ("s", ("",))
            return ("s", (self.media.snapshot(),))
        if member == "MediaAction":
            if self.media is None:
                return ("", ())
            self.media.action(args[0], args[1], args[2])
            return ("", ())
        if member == "SetCursorPos":
            self.set_cursor_pos(args[0], args[1])
            return ("", ())
        if member == "GetCursorPos":
            return ("ii", (self.cursor_x, self.cursor_y))
        if member == "WarpPointer":
            self.warp_pointer(args[0], args[1], args[2])
            return ("", ())
        if member == "Introspect":
            return ("s", (INTROSPECTION_XML,))
        if member == "Ping":
            return ("", ())
        raise NotImplementedError(f"no such method: {member}")

    def get_settings(self, display_key):
        display_key = coerce_display_key(display_key)
        if display_key is None:
            log(f"GetSettings got a malformed display key: {display_key!r}")
            return ("", "")
        entry = self.store.get(display_key)
        if entry is None:
            return ("", "")
        return (display_key, json.dumps(entry))

    def set_settings(self, display_key, bundle_json):
        display_key = coerce_display_key(display_key)
        if display_key is None:
            log(f"SetSettings got a malformed display key, ignoring")
            return
        try:
            bundle = json.loads(bundle_json)
        except (ValueError, TypeError) as exc:
            log(f"SetSettings got an unparseable bundle ({exc}), ignoring")
            return
        if (
            not isinstance(bundle, dict)
            or not isinstance(bundle.get("engineType"), int)
            or not isinstance(bundle.get("engineSettings"), dict)
        ):
            log(f"SetSettings got a malformed bundle, ignoring: {bundle!r}")
            return
        self.store.set(
            display_key,
            bundle["engineType"],
            bundle["engineSettings"],
            bundle.get("lastEngine"),
            bundle.get("lastEngineSettings"),
        )

    def reset_settings(self, display_key):
        display_key = coerce_display_key(display_key)
        if display_key is None:
            log("ResetSettings got a malformed display key, ignoring")
            return
        if self.store.delete(display_key):
            log(f"reset {display_key}")
        else:
            log(f"nothing stored to reset for {display_key}")

    def set_state(self, display_key, state_json):
        display_key = coerce_display_key(display_key)
        if display_key is None:
            log("SetState got a malformed display key, ignoring")
            return
        if not isinstance(state_json, str) or len(state_json) > STATE_LIMIT:
            log("SetState got an oversized or non-string state, ignoring")
            return
        try:
            json.loads(state_json)
        except (ValueError, TypeError):
            log(f"SetState got unparseable JSON, ignoring: {state_json!r}")
            return
        self.state[display_key] = state_json

    def set_request(self, request_json):
        if not isinstance(request_json, str) or len(request_json) > STATE_LIMIT:
            log("SetRequest got an oversized or non-string request, ignoring")
            return
        try:
            request = json.loads(request_json)
            if not isinstance(request, dict):
                raise ValueError("not an object")
        except (ValueError, TypeError):
            log(f"SetRequest got unparseable JSON, ignoring: {request_json!r}")
            return
        # KWin's rule editors are a separate process, so the overview asks us
        # to start them instead of forwarding the request to the script.
        if request.get("t") == "rules":
            self.open_rules(str(request.get("id", "")), request.get("app") is True)
            return
        self.request = request_json

    def open_rules(self, window_id, whole_app):
        window_id = window_id.strip("{}")
        if len(window_id) != 36:
            log(f"open_rules got a malformed window id: {window_id!r}")
            return
        args = f"uuid {window_id}"
        if whole_app:
            args += " whole-app"
        try:
            subprocess.Popen(["kcmshell6", "kcm_kwinrules", "--args", args])
        except OSError as exc:
            log(f"could not open the window rules editor: {exc}")

    def take_request(self):
        request, self.request = self.request, ""
        return request

    def get_state(self, display_key):
        display_key = coerce_display_key(display_key)
        if display_key is None:
            return ""
        return self.state.get(display_key, "")

    def set_global_setting(self, key, value):
        kind = GLOBAL_KEYS.get(key)
        if kind is None:
            log(f"SetGlobalSetting ignored unknown key {key!r}")
            return
        if kind == "bool" and value not in ("true", "false"):
            log(f"SetGlobalSetting got a non-boolean for {key}: {value!r}")
            return
        # kwriteconfig6 is KConfig's own writer, so it takes the same lock KWin
        # does and does not clobber unrelated entries.
        try:
            subprocess.run(
                [
                    "kwriteconfig6",
                    "--file", KWIN_CONFIG,
                    "--group", KWIN_GROUP,
                    "--key", key,
                    "--type", kind,
                    value,
                ],
                check=True,
                timeout=5,
                stdout=subprocess.DEVNULL,
                stderr=subprocess.PIPE,
            )
        except (OSError, subprocess.SubprocessError) as exc:
            log(f"SetGlobalSetting could not write {key}: {exc}")
            return
        log(f"global {key} = {value}")

    def set_cursor_pos(self, x, y):
        """Update cursor position for hover desktop switching."""
        try:
            self.cursor_x = int(x)
            self.cursor_y = int(y)
        except (ValueError, TypeError):
            pass

    def warp_pointer(self, x, y, delay_ms=0):
        """Move the real pointer, off the D-Bus loop so polling keeps going.

        The overview hands us the screen point a click was transposed to.
        ydotool only moves relatively, so read the pointer back and step
        towards the target; a big single step would be mouse-accelerated.
        """
        threading.Thread(
            target=self._warp_pointer,
            args=(int(x), int(y), max(0, int(delay_ms)) / 1000.0),
            daemon=True,
        ).start()

    def _warp_pointer(self, x, y, delay=0.0):
        # A closing overview fades out first; an opening one is already there.
        if delay > 0:
            time.sleep(delay)
        prev = None
        for _ in range(6):
            pos = pointer_pos()
            if pos is None:
                log("warp: kdotool getmouselocation failed")
                return
            dx, dy = x - pos[0], y - pos[1]
            if abs(dx) <= 1 and abs(dy) <= 1:
                return
            if pos == prev:
                # A step that moved nothing will keep moving nothing.
                return
            prev = pos
            try:
                subprocess.run(
                    ["ydotool", "mousemove", "--", str(dx), str(dy)],
                    check=True,
                    timeout=1,
                )
            except (OSError, subprocess.SubprocessError) as exc:
                log(f"warp: ydotool failed: {exc!r}")
                return
            time.sleep(0.05)
        log(f"warp: pointer did not reach {x},{y}")


INTROSPECTION_XML = (
    '<!DOCTYPE node PUBLIC "-//freedesktop//DTD D-BUS Object Introspection 1.0//EN" '
    '"http://www.freedesktop.org/standards/dbus/1.0/introspect.dtd">\n'
    "<node>\n"
    f'  <interface name="{IFACE}">\n'
    '    <method name="GetSettings">\n'
    '      <arg name="display_key" type="s" direction="in"/>\n'
    '      <arg name="display_key" type="s" direction="out"/>\n'
    '      <arg name="bundle_json" type="s" direction="out"/>\n'
    "    </method>\n"
    '    <method name="SetSettings">\n'
    '      <arg name="display_key" type="s" direction="in"/>\n'
    '      <arg name="bundle_json" type="s" direction="in"/>\n'
    "    </method>\n"
    '    <method name="ResetSettings">\n'
    '      <arg name="display_key" type="s" direction="in"/>\n'
    "    </method>\n"
    '    <method name="SetGlobalSetting">\n'
    '      <arg name="key" type="s" direction="in"/>\n'
    '      <arg name="value" type="s" direction="in"/>\n'
    "    </method>\n"
    '    <method name="SetState">\n'
    '      <arg name="display_key" type="s" direction="in"/>\n'
    '      <arg name="state_json" type="s" direction="in"/>\n'
    "    </method>\n"
    '    <method name="GetState">\n'
    '      <arg name="display_key" type="s" direction="in"/>\n'
    '      <arg name="state_json" type="s" direction="out"/>\n'
    "    </method>\n"
    '    <method name="GetStates">\n'
    '      <arg name="states_json" type="s" direction="out"/>\n'
    "    </method>\n"
    '    <method name="SetRequest">\n'
    '      <arg name="request_json" type="s" direction="in"/>\n'
    "    </method>\n"
    '    <method name="TakeRequest">\n'
    '      <arg name="request_json" type="s" direction="out"/>\n'
    "    </method>\n"
    '    <method name="GetMedia">\n'
    '      <arg name="players_json" type="s" direction="out"/>\n'
    "    </method>\n"
    '    <method name="MediaAction">\n'
    '      <arg name="player" type="s" direction="in"/>\n'
    '      <arg name="action" type="s" direction="in"/>\n'
    '      <arg name="value" type="s" direction="in"/>\n'
    "    </method>\n"
    '    <method name="SetCursorPos">\n'
    '      <arg name="x" type="i" direction="in"/>\n'
    '      <arg name="y" type="i" direction="in"/>\n'
    "    </method>\n"
    '    <method name="GetCursorPos">\n'
    '      <arg name="x" type="i" direction="out"/>\n'
    '      <arg name="y" type="i" direction="out"/>\n'
    "    </method>\n"
    '    <method name="WarpPointer">\n'
    '      <arg name="x" type="i" direction="in"/>\n'
    '      <arg name="y" type="i" direction="in"/>\n'
    '      <arg name="delay_ms" type="i" direction="in"/>\n'
    "    </method>\n"
    "  </interface>\n"
    "</node>\n"
)


def make_reply(req, signature, body):
    """Build a method_return reply to req.

    Two non-obvious requirements, both learned the hard way:
      * jeepney's Message.serialise() only writes the body when the header
        carries a signature field, so the signature must be set explicitly.
      * dbus-daemon routes replies by the DESTINATION header field, not by
        reply_serial. Without DESTINATION it silently drops the message and
        the caller just times out, so it must be set to the original sender's
        unique name.
    """
    return _make_response(req, MessageType.method_return, {}, signature, body)


def make_error(req, error_name, text):
    return _make_response(
        req,
        MessageType.error,
        {HeaderFields.error_name: error_name},
        "s",
        (text,),
    )


def _make_response(req, message_type, extra_fields, signature, body):
    h = req.header
    fields = dict(extra_fields)
    fields[HeaderFields.reply_serial] = h.serial
    sender = h.fields.get(HeaderFields.sender)
    if sender is not None:
        fields[HeaderFields.destination] = sender
    if signature:
        fields[HeaderFields.signature] = signature
    return Message(
        Header(
            endianness=h.endianness,
            message_type=message_type,
            flags=MessageFlag(0),
            protocol_version=1,
            body_length=0,
            serial=0,
            fields=fields,
        ),
        body,
    )


def main():
    conn = open_dbus_connection(bus="SESSION")
    # Media calls use their own connection: send_and_get_reply() drops messages
    # it does not match, and those could be calls addressed to us.
    media_conn = open_dbus_connection(bus="SESSION")
    bus = DBusAddress(DBUS_PATH, bus_name=DBUS_IFACE, interface=DBUS_IFACE)

    # The call that triggers D-Bus activation can arrive while we are still
    # saying hello and asking for the name. send_and_get_reply() only keeps
    # messages that a filter matches and silently drops the rest, so without
    # this the very first request after a cold start was lost.
    pending = deque()
    conn.filter(MatchRule(type="method_call", path=PATH), queue=pending)

    reply = conn.send_and_get_reply(
        new_method_call(
            bus,
            "AddMatch",
            "s",
            (f"type='method_call',path='{PATH}'",),
        )
    )
    log(f"AddMatch -> {reply.body}")

    reply = conn.send_and_get_reply(
        new_method_call(bus, "RequestName", "su", (SERVICE, 0x4))
    )
    # 1 = primary owner, 4 = DBUS_NAME_FLAG_DO_NOT_QUEUE
    log(f"RequestName -> {reply.body} (1 = acquired)")

    saver = Saver(Store(STORE_PATH), media_conn)
    log(f"serving {IFACE} at {PATH}, store at {STORE_PATH}")

    try:
        while True:
            # Drain anything the handshake buffered first, then read more.
            if not pending:
                try:
                    conn.recv_messages(timeout=POLL_TIMEOUT)
                except TimeoutError:
                    pass
            while pending:
                msg = pending.popleft()
                header = msg.header
                member = header.fields.get(HeaderFields.member)
                path = header.fields.get(HeaderFields.path)
                iface = header.fields.get(HeaderFields.interface)
                try:
                    if path != PATH:
                        raise LookupError(f"no object at {path}")
                    if iface in ("org.freedesktop.DBus.Introspectable",):
                        signature, body = "s", (INTROSPECTION_XML,)
                    elif iface in ("org.freedesktop.DBus.Peer",):
                        signature, body = "", ()
                    elif iface in (IFACE, None, ""):
                        signature, body = saver.dispatch(member, msg.body)
                    else:
                        raise LookupError(f"no interface {iface}")
                except LookupError as exc:
                    conn.send(make_error(msg, ERROR_UNKNOWN_METHOD, str(exc)))
                except Exception as exc:  # never die on a bad call
                    log(f"error handling {member}: {exc!r}")
                    conn.send(make_error(msg, ERROR_UNKNOWN_METHOD, repr(exc)))
                else:
                    conn.send(make_reply(msg, signature, body))
            saver.store.tick()
    except (KeyboardInterrupt, BrokenPipeError):
        pass
    finally:
        saver.store.flush()
        log("shutting down, store flushed")


if __name__ == "__main__":
    main()