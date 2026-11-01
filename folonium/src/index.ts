// Folonium — rule-based tiling for KWin 6.
// SPDX-FileCopyrightText: 2026 Vaughan Milliman (Polonium, upstream)
// SPDX-FileCopyrightText: 2026 mj0x0 (Polonium fork)
// SPDX-FileCopyrightText: 2026 Sreinumder
// SPDX-License-Identifier: MIT

// folonium refuses to shrink a tile below this fraction of its parent
// (see setChildMinSize).
var MIN_CHILD_FRACTION = 0.15001;
function rotateDirection(d) {
  let ret = 0 /* None */;
  if (!(d & 4 /* Vertical */)) ret |= 4 /* Vertical */;
  if (d & 2 /* Right */) ret |= 1 /* Down */;
  if (d & 1 /* Down */) ret |= 2 /* Right */;
  return ret;
}
function directionFromPoint(r, p) {
  const x = p.x - r.x;
  const y = p.y - r.y;
  if (x < r.width / 2) {
    if (y < r.height / 2) {
      if (x > r.width * y / r.height) {
        return 4 /* Vertical */;
      } else {
        return 0 /* None */;
      }
    } else {
      if (x > r.width * y / r.height) {
        return 1 /* Down */ | 4 /* Vertical */;
      } else {
        return 1 /* Down */;
      }
    }
  } else {
    if (y < r.height / 2) {
      if (x < r.width * y / r.height) {
        return 2 /* Right */ | 4 /* Vertical */;
      } else {
        return 2 /* Right */;
      }
    } else {
      if (x < r.width * y / r.height) {
        return 1 /* Down */ | 2 /* Right */ | 4 /* Vertical */;
      } else {
        return 1 /* Down */ | 2 /* Right */;
      }
    }
  }
}

// src/util/stacklike.ts
var StackLike = class {
  getAtIndex(idx) {
    if (idx < 0) {
      return void 0;
    }
    let i = 0;
    for (const x of this) {
      if (idx == i) {
        return x;
      }
      i += 1;
    }
    return void 0;
  }
  multipush(values) {
    for (const value of values) {
      this.push(value);
    }
  }
  some(fn) {
    for (const x of this) {
      if (fn(x)) {
        return true;
      }
    }
    return false;
  }
  indexOf(fn) {
    let i = 0;
    for (const x of this) {
      if (fn(x)) {
        return i;
      }
      i += 1;
    }
    return -1;
  }
  find(fn) {
    for (const x of this) {
      if (fn(x)) {
        return x;
      }
    }
    return void 0;
  }
};

// src/util/queue.ts
var Node = class {
  constructor(value) {
    this.next = null;
    this.value = value;
  }
  append(node) {
    this.next = node;
    return this.next;
  }
};
var Queue = class extends StackLike {
  constructor() {
    super();
    this.head = null;
    this.tail = null;
    this.count = 0;
  }
  push(value) {
    if (this.head === null || this.tail === null) {
      this.head = new Node(value);
      this.tail = this.head;
    } else {
      this.tail = this.tail.append(new Node(value));
    }
    this.count += 1;
  }
  pop() {
    if (this.head === null) {
      return void 0;
    }
    const value = this.head.value;
    this.head = this.head.next;
    if (this.head === null) {
      this.tail = null;
    }
    this.count -= 1;
    return value;
  }
  peek() {
    return this.head?.value;
  }
  removeAtIndex(index) {
    if (index < 0 || index >= this.count) {
      return void 0;
    }
    let node = this.head;
    let prevNode = null;
    for (let i = 0; i < index; i += 1) {
      if (node === null) {
        return void 0;
      }
      prevNode = node;
      node = node.next;
    }
    if (node === null) return void 0;
    if (prevNode !== null) {
      prevNode.next = node.next;
      if (node === this.tail) {
        this.tail = prevNode;
      }
    } else {
      this.head = node.next;
    }
    this.count -= 1;
    return node.value;
  }
  get size() {
    return this.count;
  }
  get isEmpty() {
    return this.count === 0;
  }
  *[Symbol.iterator]() {
    let currNode = this.head;
    while (currNode !== null) {
      let ret = currNode.value;
      currNode = currNode.next;
      yield ret;
    }
  }
};

// src/controller/event.ts
var Display = class _Display {
  static setWorkspace(workspace) {
    this.workspace = workspace;
  }
  constructor(desktop, activity, output) {
    this.desktop = desktop;
    this.activity = activity;
    this.output = output;
  }
  toString() {
    // Same key order and spacing as before so saved saver entries still match,
    // but JSON.stringify escapes names instead of letting a quote break the key.
    return JSON.stringify({
      d: this.desktop.id,
      a: this.activity,
      o: this.output.name
    });
  }
  toSymbol() {
    return Symbol.for(this.toString());
  }
  equals(d) {
    return d && d.desktop === this.desktop && d.activity === this.activity && d.output === this.output;
  }
  static *generate(desktops, activities, outputs) {
    for (const desktop of desktops) {
      for (const activity of activities) {
        for (const output of outputs) {
          yield new _Display(desktop, activity, output);
        }
      }
    }
  }
  static *generateWindow(window) {
    // A window that is in the middle of being destroyed can already have lost
    // its output, desktops or activities, and reading those properties can
    // throw. Producing a Display with a null field would later throw in
    // toSymbol(), which used to make the delete event fail and leave the
    // window counted forever. Yield nothing instead; evDeleteWindow scans the
    // live drivers even when this list is empty.
    if (window === null || window === void 0) {
      return;
    }
    let output, onAllDesktops, desktops, activities;
    try {
      output = window.output;
      onAllDesktops = window.onAllDesktops;
      desktops = window.desktops;
      activities = window.activities;
    } catch (e) {
      return;
    }
    if (output === null || output === void 0) {
      return;
    }
    const desktopList = onAllDesktops ? this.workspace?.desktops ?? [] : desktops ?? [];
    // An empty activity list means "all activities" in KWin, not "none".
    const activityList = activities !== null && activities !== void 0 && activities.length > 0
      ? activities
      : this.workspace?.activities ?? [];
    for (const desktop of desktopList) {
      for (const activity of activityList) {
        yield new _Display(desktop, activity, output);
      }
    }
  }
  static activeDisplay() {
    if (this.workspace === void 0) {
      return null;
    }
    return new _Display(
      this.workspace.currentDesktop,
      this.workspace.currentActivity,
      this.workspace.activeScreen
    );
  }
  containsWindow(window) {
    return (window.desktops.includes(this.desktop) || window.onAllDesktops) && (window.activities.includes(this.activity) || window.activities.length == 0) && window.output === this.output;
  }
};
function eventsAreSame(ev1, ev2) {
  if (ev1.t !== ev2.t) return false;
  for (const prop in ev1) {
    if (prop === "display") {
      if (ev1.display?.equals(ev2.display)) {
        continue;
      }
      return false;
    } else if (prop === "displays") {
      if (ev1.displays === void 0 || ev2.displays === void 0) {
        return false;
      }
      for (let i = 0; i < ev1.displays.length; i += 1) {
        if (!ev1.displays[i].equals(ev2.displays[i])) {
          return false;
        }
      }
      continue;
    }
    const val1 = ev1[prop];
    const val2 = ev2[prop];
    if (val1 !== val2) return false;
  }
  return true;
}
function simplifyEvents(oldEvents) {
  const newEvents = new Queue();
  for (const ev of oldEvents) {
    if (ev.t === "tileWindow" || ev.t === "untileWindow" || ev.t === "placeWindow") {
      const newEv = newEvents.find(
        (e) => e.t === "newWindow" && e.window === ev.window
      );
      if (newEv !== void 0 && newEv.t === "newWindow") {
        if (ev.t === "tileWindow") {
          newEv.forceTile = true;
          newEv.tile = void 0;
          newEv.direction = void 0;
        } else if (ev.t === "untileWindow") {
          newEv.forceTile = false;
          newEv.tile = void 0;
          newEv.direction = void 0;
        } else if (ev.t === "placeWindow") {
          newEv.forceTile = true;
          newEv.tile = ev.tile;
          newEv.direction = ev.direction;
        }
        continue;
      }
      const parallelIdx = newEvents.indexOf(
        (e) => (e.t === "tileWindow" || e.t === "untileWindow" || e.t === "placeWindow") && e.window === ev.window
      );
      if (parallelIdx != -1) {
        newEvents.removeAtIndex(parallelIdx);
      }
    }
    if (ev.t === "deleteWindow") {
      const newIdx = newEvents.indexOf(
        (e) => e.t === "newWindow" && e.window === ev.window
      );
      if (newIdx != -1) {
        newEvents.removeAtIndex(newIdx);
        continue;
      }
    }
    if (ev.t === "modifyEngineSetting" && ev.op === "add") {
      const merged = newEvents.find(
        (e) => e.t === "modifyEngineSetting" && e.op === ev.op && e.setting === ev.setting && Math.sign(e.amount) === Math.sign(ev.amount) && e.min === ev.min && e.max === ev.max && e.display?.equals(ev.display) === true
      );
      if (merged !== void 0) {
        merged.amount = merged.amount + ev.amount;
        continue;
      }
    }
    if (newEvents.some((e) => eventsAreSame(ev, e))) {
      continue;
    }
    if (ev.t == "changeEngine" && ev.engineSettings === void 0 && ev.engineType === void 0) {
      continue;
    }
    newEvents.push(ev);
  }
  return newEvents;
}
function simplifyPostEvents(oldEvents) {
  const newEvents = new Queue();
  for (const ev of oldEvents) {
    if (newEvents.some((e) => eventsAreSame(ev, e))) {
      continue;
    }
    newEvents.push(ev);
  }
  return newEvents;
}

// src/engine/engine.ts
var Window = class {
  constructor(id, name, minSize) {
    this.id = id;
    this.name = name;
    this.minSize = minSize;
  }
};
var Tile = class _Tile {
  constructor(parent) {
    this.children = [];
    this.layoutDirection = 1 /* Horizontal */;
    // relative size to other children of this tile
    this.size = 1;
    this.windows = [];
    this.parent = parent ?? null;
    if (this.parent == null) {
      return;
    }
  }
  // adds a child that will split perpendicularly to the parent. Returns the child
  addChild() {
    let splitDirection = 1 /* Horizontal */;
    if (this.layoutDirection == 1 /* Horizontal */) {
      splitDirection = 2 /* Vertical */;
    }
    const childTile = new _Tile(this);
    this.children.push(childTile);
    childTile.layoutDirection = splitDirection;
    return childTile;
  }
  // split a tile, aka add two children
  split() {
    this.addChild();
    this.addChild();
  }
  // removes a tile and all its children
  remove() {
    const parent = this.parent;
    if (parent == null) {
      return;
    }
    parent.children.splice(parent.children.indexOf(this), 1);
    this.children = [];
    this.windows = [];
  }
  // remove child tiles
  removeChildren() {
    for (const tile of this.children) {
      tile.remove();
    }
    this.children = [];
  }
  totalChildrenSize() {
    return this.children.reduce((s, t) => s + t.size, 0);
  }
  toJSON(includeWindows = false) {
    return {
      layoutDirection: this.layoutDirection,
      size: this.size,
      children: this.children.map((c) => c.toJSON()),
      windows: includeWindows ? this.windows.map((w) => w.id.toString()) : []
    };
  }
  static fromJSON(json, parent) {
    const tile = new _Tile(parent);
    if (parent != null) {
      parent.children.push(tile);
    }
    let obj;
    try {
      obj = typeof json === "string" ? JSON.parse(json) : json;
    } catch (_e) {
      return tile;
    }
    tile.layoutDirection = obj.layoutDirection;
    tile.size = obj.size;
    for (const child of obj.children) {
      _Tile.fromJSON(child, tile);
    }
    return tile;
  }
};
var BaseEngineSettings = class {
  getProps() {
    const ret = {};
    for (const key in this) {
      if (typeof this[key] !== "function") {
        ret[key] = this[key];
      }
    }
    return ret;
  }
  setProps(obj) {
    if (obj == null) return;
    for (const key in this) {
      if (obj.hasOwnProperty(key)) this[key] = obj[key];
    }
  }
};

// src/engine/layouts/layout.ts
// A layout is a recursive slicing tree. `[...]` splits horizontally (side by
// side columns), `/.../` splits vertically (stacked rows), and a leaf holds one
// window. A bare number inside a group is a stack perpendicular to the group:
// `[1 2]` is one column beside a column of two stacked windows, and `/1 2/` is
// one row above a row of two side-by-side windows.
//
// Layouts are compared up to the eight symmetries of a rectangle (D4), so a
// rotation or reflection is the same topology. The canonical spelling is the
// smallest of the eight spellings under the ordering below. That is what the
// popup shows, and equivalent layouts are de-duplicated by it.
var CUSTOM_MAX_WINDOWS = 9;
var CUSTOM_ENGINE_TYPE = 6;
var KWIN_ENGINE_TYPE = 5;
var DEFAULT_RATIO_TEXT = "2:1 3:2 1:1 2:3 1:2\n1:1:1 2:1:1 1:2:1 1:1:2";

function layoutLeaf() {
  return { kind: "leaf" };
}
function layoutSplit(dir, children, sizes) {
  const node = { kind: "split", dir, children };
  if (sizes !== void 0) {
    node.sizes = sizes;
  }
  return node;
}
function layoutOpposite(dir) {
  return dir === 1 /* Horizontal */ ? 2 /* Vertical */ : 1 /* Horizontal */;
}
function layoutWindowCount(node) {
  if (node.kind === "leaf") {
    return 1;
  }
  let count = 0;
  for (const child of node.children) {
    count += layoutWindowCount(child);
  }
  return count;
}

// Flatten same-direction nesting and collapse unary groups. `[1 [1 1]]` and
// `[1 1 1]` are the same topology, and `[2]` is just a vertical stack.
function layoutNormalizeSplit(dir, children) {
  const flat = [];
  for (const child of children) {
    if (child.kind === "split" && child.dir === dir) {
      flat.push(...child.children);
    } else {
      flat.push(child);
    }
  }
  if (flat.length === 0) {
    throw new Error("empty layout group");
  }
  if (flat.length === 1) {
    return flat[0];
  }
  return layoutSplit(dir, flat);
}

// Parse the DSL. The parent direction says which way the enclosing group
// splits, because a bare number is a stack perpendicular to it.
function parseLayoutItem(text, state, parentDir) {
  while (state.i < text.length && /\s/.test(text[state.i])) {
    state.i += 1;
  }
  if (state.i >= text.length) {
    throw new Error("unexpected end of layout");
  }
  const ch = text[state.i];
  if (ch === "[" || ch === "/") {
    state.i += 1;
    const dir = ch === "[" ? 1 /* Horizontal */ : 2 /* Vertical */;
    const close = ch === "[" ? "]" : "/";
    const children = [];
    while (true) {
      while (state.i < text.length && /\s/.test(text[state.i])) {
        state.i += 1;
      }
      if (state.i >= text.length) {
        throw new Error("unterminated layout group");
      }
      if (text[state.i] === close) {
        state.i += 1;
        break;
      }
      children.push(parseLayoutItem(text, state, dir));
    }
    return layoutNormalizeSplit(dir, children);
  }
  const match = /^[0-9]+/.exec(text.slice(state.i));
  if (match === null) {
    throw new Error("expected a window count or a group");
  }
  state.i += match[0].length;
  const count = parseInt(match[0], 10);
  if (!Number.isInteger(count) || count < 1) {
    throw new Error("window count must be positive");
  }
  if (count === 1) {
    return layoutLeaf();
  }
  const stackDir = layoutOpposite(parentDir);
  const leaves = [];
  for (let i = 0; i < count; i += 1) {
    leaves.push(layoutLeaf());
  }
  return layoutNormalizeSplit(stackDir, leaves);
}
function parseLayout(text) {
  const state = { i: 0 };
  const root = parseLayoutItem(text, state, 1 /* Horizontal */);
  while (state.i < text.length && /\s/.test(text[state.i])) {
    state.i += 1;
  }
  if (state.i !== text.length) {
    throw new Error("trailing text in layout");
  }
  return root;
}
// A tab may hold several complete layouts separated by spaces or newlines.
// Layouts themselves also contain spaces, so this parses each complete
// expression instead of splitting on whitespace.
function parseLayoutList(text) {
  const state = { i: 0 };
  const out = [];
  while (true) {
    while (state.i < text.length && /\s/.test(text[state.i])) {
      state.i += 1;
    }
    if (state.i >= text.length) {
      break;
    }
    out.push(parseLayoutItem(text, state, 1 /* Horizontal */));
  }
  if (out.length === 0) {
    throw new Error("empty layout list");
  }
  return out;
}

// A vertical stack of leaves nested in a column is written as its count, which
// is the compact spelling the layout list uses (`[1 2]`). At the root a group
// is always written out, so a rotated root cannot collapse to a bare number.
function layoutSerialize(node, isRoot = true) {
  if (node.kind === "leaf") {
    // A single window has no split, but the DSL always shows the root as a
    // bracketed group so the popup never shows a bare count.
    return isRoot ? "[1]" : "1";
  }
  if (!isRoot && node.dir === 2 /* Vertical */ && node.children.every((child) => child.kind === "leaf")) {
    return String(node.children.length);
  }
  const open = node.dir === 1 /* Horizontal */ ? "[" : "/";
  const close = node.dir === 1 /* Horizontal */ ? "]" : "/";
  return open + node.children.map((child) => layoutSerialize(child, false)).join(" ") + close;
}
function layoutText(node) {
  return node.kind === "leaf" ? "[1]" : layoutSerialize(node, true);
}

// The eight symmetries of the rectangle. Transpose swaps the split axes;
// mirroring reverses the children (and proportions) of horizontal splits.
function layoutTranspose(node) {
  if (node.kind === "leaf") {
    return layoutLeaf();
  }
  return layoutSplit(
    layoutOpposite(node.dir),
    node.children.map(layoutTranspose),
    node.sizes === void 0 ? void 0 : node.sizes.slice()
  );
}
function layoutMirror(node) {
  if (node.kind === "leaf") {
    return layoutLeaf();
  }
  const children = node.children.map(layoutMirror);
  const sizes = node.sizes === void 0 ? void 0 : node.sizes.slice();
  if (node.dir === 1 /* Horizontal */) {
    children.reverse();
    if (sizes !== void 0) {
      sizes.reverse();
    }
  }
  return layoutSplit(node.dir, children, sizes);
}
function layoutRotate90(node) {
  return layoutMirror(layoutTranspose(node));
}
// Tags let a window order follow the leaves through a view transform. Mirroring
// must keep a vertical stack's top/bottom order while exchanging its place with
// the neighbouring column, so reversing the whole window list is wrong.
function layoutTagLeaves(node, state) {
  if (node.kind === "leaf") {
    const leaf = { kind: "leaf", tag: state.next };
    state.next += 1;
    return leaf;
  }
  return layoutSplit(
    node.dir,
    node.children.map((child) => layoutTagLeaves(child, state)),
    node.sizes === void 0 ? void 0 : node.sizes.slice()
  );
}
function layoutViewTagOrder(node, rotate, mirror) {
  if (node.kind === "leaf") {
    return [node.tag];
  }
  const dir = rotate ? layoutOpposite(node.dir) : node.dir;
  const children = mirror && dir === 1 /* Horizontal */
    ? node.children.slice().reverse()
    : node.children;
  const out = [];
  for (const child of children) {
    out.push(...layoutViewTagOrder(child, rotate, mirror));
  }
  return out;
}
function windowOrderForView(windows, ast, oldRotate, oldMirror, newRotate, newMirror) {
  const state = { next: 0 };
  const tagged = layoutTagLeaves(ast, state);
  const before = layoutViewTagOrder(tagged, oldRotate, oldMirror);
  const after = layoutViewTagOrder(tagged, newRotate, newMirror);
  const out = after.map((tag) => windows[before.indexOf(tag)]);
  for (let i = before.length; i < windows.length; i += 1) {
    out.push(windows[i]);
  }
  return out;
}
function layoutTransforms(node) {
  const out = [];
  let current = node;
  for (let i = 0; i < 4; i += 1) {
    out.push(current);
    out.push(layoutMirror(current));
    current = layoutRotate90(current);
  }
  return out;
}

// Digits sort before groups and `[` sorts before `/`, so horizontal groups are
// preferred at the root and a leading `1` is preferred inside a vertical group.
function layoutCharRank(ch) {
  if (ch >= "0" && ch <= "9") return 0;
  if (ch === "[") return 1;
  if (ch === "/") return 2;
  if (ch === "]") return 3;
  if (ch === " ") return 4;
  return 5;
}
function layoutCompareText(a, b) {
  const length = Math.min(a.length, b.length);
  for (let i = 0; i < length; i += 1) {
    const ra = layoutCharRank(a[i]);
    const rb = layoutCharRank(b[i]);
    if (ra !== rb) {
      return ra - rb;
    }
    if (a[i] !== b[i]) {
      return a[i] < b[i] ? -1 : 1;
    }
  }
  return a.length - b.length;
}
// Ratio options are whitespace-separated `a:b[:c...]` patterns. Patterns of
// different arity never mix: a split only matches an option with the same
// number of children.
function parseRatioList(text) {
  const out = [];
  for (const token of String(text ?? "").trim().split(/\s+/)) {
    if (token === "") {
      continue;
    }
    const parts = token.split(":");
    if (parts.length < 2) {
      continue;
    }
    const values = [];
    let valid = true;
    for (const part of parts) {
      const value = Number(part);
      if (!Number.isFinite(value) || value <= 0) {
        valid = false;
        break;
      }
      values.push(value);
    }
    if (!valid) {
      continue;
    }
    const normalized = values.join(":");
    if (!out.some((option) => option.text === normalized)) {
      out.push({ text: normalized, values });
    }
  }
  return out;
}
function layoutCanonicalize(node) {
  let best = null;
  for (const candidate of layoutTransforms(node)) {
    const text = layoutSerialize(candidate, true);
    if (best === null || layoutCompareText(text, best.text) < 0) {
      best = { text, ast: candidate };
    }
  }
  return best;
}

function layoutCloneWithDefaultSizes(node) {
  if (node.kind === "leaf") {
    return layoutLeaf();
  }
  const children = node.children.map(layoutCloneWithDefaultSizes);
  return layoutSplit(node.dir, children, children.map(() => 1));
}

// Each KCM tab is a layout set. Its text may hold several layouts separated by
// spaces or newlines, so one tab can cover several window counts. Per-display
// settings remember which tab is active and, when a count has several shapes,
// which one of that tab's layouts is selected.
var customLayoutSetCache = new Map();
function configuredCustomLayoutTexts() {
  const cfg = config();
  return cfg !== void 0 && Array.isArray(cfg.customLayoutTexts) ? cfg.customLayoutTexts : [];
}
function configuredRatioOptions() {
  const cfg = config();
  return cfg !== void 0 && Array.isArray(cfg.customRatios) ? cfg.customRatios : [];
}
function customLayoutSets() {
  const out = [];
  const texts = configuredCustomLayoutTexts();
  for (let slot = 0; slot < texts.length; slot += 1) {
    const text = String(texts[slot] ?? "").trim();
    if (text === "") {
      continue;
    }
    let set = customLayoutSetCache.get(text);
    if (set === void 0) {
      try {
        const seen = new Set();
        const layouts = [];
        for (const ast of parseLayoutList(text)) {
          const count = layoutWindowCount(ast);
          if (count < 1 || count > CUSTOM_MAX_WINDOWS) {
            continue;
          }
          const canonical = layoutCanonicalize(ast).text;
          if (seen.has(canonical)) {
            continue;
          }
          seen.add(canonical);
          layouts.push({ text: layoutText(ast), ast, count, canonical });
        }
        set = { layouts };
      } catch (e) {
        set = { error: e.message };
        console().warn(
          "invalid custom layout tab",
          text.replace(/\s+/g, " ").slice(0, 80),
          "-",
          e.message
        );
      }
      customLayoutSetCache.set(text, set);
    }
    if (set.error !== void 0 || set.layouts.length === 0) {
      continue;
    }
    out.push({ index: slot, name: "L" + (slot + 1), text, layouts: set.layouts });
  }
  return out;
}

// src/engine/layouts/custom.ts
var CustomEngineSettings = class extends BaseEngineSettings {
  constructor() {
    super(...arguments);
    this.rotateLayout = false;
    this.mirrorLayout = false;
    // Every window shares one tile, so they stack instead of splitting.
    this.monocle = false;
    // L1 is the default. The selected tab is authoritative: a tab with no
    // matching layout leaves windows floating instead of using generated shapes.
    this.customLayoutTab = 0;
    // Window count -> selected layout text inside that tab.
    this.customLayouts = {};
    // Selected ratio option on each screen axis. Empty falls back to the
    // first applicable option (the equal split).
    this.horizontalRatio = "";
    this.verticalRatio = "";
  }
};

var CustomEngine = class {
  constructor() {
    this.tileMap = /* @__PURE__ */ new Map();
    this.windowTiles = /* @__PURE__ */ new Map();
    this.windows = [];
    // Sized trees, keyed by layout, count and view transform. Keeping the
    // proportions here means a divider drag survives the next rebuild, and each
    // layout remembers its own shape instead of reusing a track list.
    this.sizedLayouts = /* @__PURE__ */ new Map();
    this.currentAst = null;
    this.currentKey = null;
    this.builtKey = null;
    this.currentCount = 0;
    this.settings = new CustomEngineSettings();
  }
  getEngineSettings() {
    return this.settings.getProps();
  }
  setEngineSettings(settings) {
    const oldRotate = this.settings.rotateLayout;
    const oldMirror = this.settings.mirrorLayout;
    const oldTab = this.settings.customLayoutTab;
    const oldEntry = this.selectedCustomLayout(this.currentCount);
    const oldCustom = oldEntry === null ? "" : oldEntry.text;
    const oldLayout = this.selectedCustomLayout(this.windows.length);
    this.settings.setProps(settings);
    if (!(this.settings.customLayoutTab >= 0 && this.settings.customLayoutTab < CUSTOM_MAX_WINDOWS)) {
      this.settings.customLayoutTab = 0;
    }
    // Mirroring exchanges the windows at their reflected positions. A vertical
    // stack keeps its top/bottom order; only horizontal child order reverses.
    if (oldMirror !== this.settings.mirrorLayout && oldLayout !== null && oldTab === this.settings.customLayoutTab) {
      this.windows = windowOrderForView(
        this.windows,
        oldLayout.ast,
        oldRotate,
        oldMirror,
        this.settings.rotateLayout,
        this.settings.mirrorLayout
      );
    }
    // Preserve the proportions already on screen when the view is rotated or
    // mirrored. A different tab or custom text uses its own remembered sizes.
    const newEntry = this.selectedCustomLayout(this.currentCount);
    const newCustom = newEntry === null ? "" : newEntry.text;
    if (this.currentAst !== null && oldTab === this.settings.customLayoutTab && oldCustom === newCustom && this.currentCount === this.windows.length && (oldRotate !== this.settings.rotateLayout || oldMirror !== this.settings.mirrorLayout)) {
      // Invert the old view, then apply the new one. The build applies rotate
      // before mirror, so undoing mirror before rotating is what keeps the two
      // flags independent when both change at once.
      let next = this.currentAst;
      if (oldMirror) {
        next = layoutMirror(next);
      }
      if (oldRotate !== this.settings.rotateLayout) {
        next = layoutTranspose(next);
      }
      if (this.settings.mirrorLayout) {
        next = layoutMirror(next);
      }
      next = this.applyRatios(next);
      const custom = this.selectedCustomLayout(this.currentCount);
      if (custom !== null) {
        const key = this.customLayoutKey(custom.text, custom.count);
        this.sizedLayouts.set(key, next);
        this.currentAst = next;
        this.currentKey = key;
      }
    }
  }
  customLayoutFor(count) {
    const layouts = this.settings.customLayouts;
    if (layouts == null || typeof layouts !== "object") {
      return "";
    }
    const text = layouts[String(count)];
    return typeof text === "string" ? text.trim() : "";
  }
  selectedCustomLayoutSet() {
    // Old saved settings may still carry Automatic's -1. L1 is the default now.
    let tab = this.settings.customLayoutTab;
    if (!(tab >= 0 && tab < CUSTOM_MAX_WINDOWS)) {
      tab = 0;
    }
    for (const set of customLayoutSets()) {
      if (set.index === tab) {
        return set;
      }
    }
    return null;
  }
  // The selected tab is authoritative. Use the largest layout count that fits
  // the open windows; any extra windows stay untiled and float.
  customLayoutsForCount(count) {
    const set = this.selectedCustomLayoutSet();
    if (set === null || count < 1) {
      return [];
    }
    let layoutCount = 0;
    for (const layout of set.layouts) {
      if (layout.count <= count && layout.count > layoutCount) {
        layoutCount = layout.count;
      }
    }
    if (layoutCount === 0) {
      return [];
    }
    return set.layouts.filter((layout) => layout.count === layoutCount);
  }
  selectedCustomLayout(count) {
    const layouts = this.customLayoutsForCount(count);
    if (layouts.length === 0) {
      return null;
    }
    // The choice is stored per layout count, so it survives window changes
    // that still use the same shape.
    const text = this.customLayoutFor(layouts[0].count);
    if (text !== "") {
      for (const layout of layouts) {
        if (layout.text === text) {
          return layout;
        }
      }
    }
    return layouts[0];
  }
  customLayoutSets() {
    const out = [];
    const texts = configuredCustomLayoutTexts();
    const count = Math.max(CUSTOM_MAX_WINDOWS, texts.length);
    for (let i = 0; i < count; i += 1) {
      out.push({ index: i, name: "L" + (i + 1) });
    }
    return out;
  }
  layoutCount() {
    const layouts = this.customLayoutsForCount(this.windows.length);
    return layouts.length > 0 ? layouts.length : 1;
  }
  layoutIndex() {
    const layouts = this.customLayoutsForCount(this.windows.length);
    if (layouts.length === 0) {
      return -1;
    }
    const entry = this.selectedCustomLayout(this.windows.length);
    const index = entry === null ? -1 : layouts.indexOf(entry);
    return index >= 0 ? index : -1;
  }
  usingCustomLayout() {
    return this.currentKey !== null && this.currentKey.indexOf("custom:") === 0;
  }
  // Drops remembered divider proportions, so a settings reset truly starts
  // from the default balanced sizes.
  resetLayoutSizes() {
    this.sizedLayouts.clear();
    this.currentAst = null;
    this.currentKey = null;
    this.builtKey = null;
  }
  customLayoutKey(text, count) {
    return "custom:" + this.settings.customLayoutTab + ":" + text + ":" + count + ":" + (this.settings.rotateLayout ? 1 : 0) + ":" + (this.settings.mirrorLayout ? 1 : 0) + ":" + this.settings.horizontalRatio + ":" + this.settings.verticalRatio;
  }
  // A layout from the selected KCM tab. If that tab has several layouts for
  // the chosen count, the per-count choice wins; otherwise the first is used.
  getCustomLayout(count) {
    const entry = this.selectedCustomLayout(count);
    if (entry === null) {
      return null;
    }
    const key = this.customLayoutKey(entry.text, entry.count);
    const cached = this.sizedLayouts.get(key);
    if (cached !== void 0) {
      return { ast: cached, key };
    }
    let ast = layoutCloneWithDefaultSizes(entry.ast);
    if (this.settings.rotateLayout) {
      ast = layoutTranspose(ast);
    }
    if (this.settings.mirrorLayout) {
      ast = layoutMirror(ast);
    }
    ast = this.applyRatios(ast);
    this.sizedLayouts.set(key, ast);
    return { ast, key };
  }
  // A ratio option only fits splits with the same number of children. The
  // first split on an axis defines that axis's arity; every matching split
  // then shares the same proportions (both stacks in `[2 2]`, for example).
  axisArity(ast, dir) {
    let arity = 0;
    const walk = (node) => {
      if (arity !== 0 || node.kind !== "split") {
        return;
      }
      if (node.dir === dir) {
        arity = node.children.length;
        return;
      }
      for (const child of node.children) {
        walk(child);
      }
    };
    walk(ast);
    return arity;
  }
  ratioOptionsForArity(arity) {
    const matching = configuredRatioOptions().filter(
      (option) => option.values.length === arity
    );
    if (matching.length === 0) {
      return [];
    }
    const equalValues = new Array(arity).fill(1);
    const equal = { text: equalValues.join(":"), values: equalValues };
    const out = matching.some((option) => option.text === equal.text) ? [] : [equal];
    for (const option of matching) {
      out.push(option);
    }
    return out;
  }
  ratioOptionsForAxis(ast, dir) {
    const arity = this.axisArity(ast, dir);
    return arity === 0 ? [] : this.ratioOptionsForArity(arity);
  }
  selectedRatioOption(ast, dir) {
    const options = this.ratioOptionsForAxis(ast, dir);
    if (options.length === 0) {
      return null;
    }
    const selected = dir === 1 /* Horizontal */ ? this.settings.horizontalRatio : this.settings.verticalRatio;
    for (const option of options) {
      if (option.text === selected) {
        return option;
      }
    }
    return options[0];
  }
  applyRatios(ast) {
    const horizontal = this.selectedRatioOption(ast, 1 /* Horizontal */);
    const vertical = this.selectedRatioOption(ast, 2 /* Vertical */);
    const walk = (node) => {
      if (node.kind !== "split") {
        return;
      }
      const option = node.dir === 1 /* Horizontal */ ? horizontal : vertical;
      if (option !== null && node.children.length === option.values.length) {
        node.sizes = option.values.slice();
      }
      for (const child of node.children) {
        walk(child);
      }
    };
    walk(ast);
    return ast;
  }
  ratioMatches(ast, dir, option) {
    let seen = false;
    let matches = true;
    const expected = option.values.reduce((sum, value) => sum + value, 0);
    const walk = (node) => {
      if (!matches || node.kind !== "split") {
        return;
      }
      if (node.dir === dir && node.children.length === option.values.length) {
        seen = true;
        const sizes = node.sizes;
        if (sizes === void 0 || sizes.length !== option.values.length) {
          matches = false;
          return;
        }
        const total = sizes.reduce((sum, value) => sum + value, 0);
        if (!(total > 0)) {
          matches = false;
          return;
        }
        for (let i = 0; i < sizes.length; i += 1) {
          if (Math.abs(sizes[i] / total - option.values[i] / expected) > 1e-4) {
            matches = false;
            return;
          }
        }
      }
      for (const child of node.children) {
        walk(child);
      }
    };
    walk(ast);
    return seen && matches;
  }
  currentRatioOption(ast, dir) {
    for (const option of this.ratioOptionsForAxis(ast, dir)) {
      if (this.ratioMatches(ast, dir, option)) {
        return option;
      }
    }
    return null;
  }
  ratioInfo() {
    const ast = this.currentAst;
    if (ast === null) {
      return { horizontal: "", vertical: "", horizontalCount: 0, verticalCount: 0 };
    }
    const info = (dir) => {
      const options = this.ratioOptionsForAxis(ast, dir);
      if (options.length === 0) {
        return { text: "", count: 0 };
      }
      const current = this.currentRatioOption(ast, dir);
      return { text: current === null ? "custom" : current.text, count: options.length };
    };
    const horizontal = info(1 /* Horizontal */);
    const vertical = info(2 /* Vertical */);
    return {
      horizontal: horizontal.text,
      vertical: vertical.text,
      horizontalCount: horizontal.count,
      verticalCount: vertical.count
    };
  }
  // If the sizes on screen do not match any configured option, the next press
  // returns to the equal/default ratio instead of guessing a neighbour.
  cycleRatio(dir, backwards) {
    const ast = this.currentAst;
    if (ast === null) {
      return false;
    }
    const options = this.ratioOptionsForAxis(ast, dir);
    if (options.length === 0) {
      return false;
    }
    const current = this.currentRatioOption(ast, dir);
    let next;
    if (current === null) {
      next = options[0];
    } else {
      if (options.length <= 1) {
        return false;
      }
      const index = options.findIndex((option) => option.text === current.text);
      next = options[(index + (backwards ? -1 : 1) + options.length) % options.length];
    }
    if (dir === 1 /* Horizontal */) {
      this.settings.horizontalRatio = next.text;
    } else {
      this.settings.verticalRatio = next.text;
    }
    // A drag can leave a cached tree at a custom size under this ratio. Drop
    // both the old and the target cache entries so the next build reapplies
    // the selected ratio.
    const entry = this.selectedCustomLayout(this.currentCount);
    if (entry !== null) {
      this.sizedLayouts.delete(this.customLayoutKey(entry.text, entry.count));
    }
    this.sizedLayouts.delete(this.currentKey);
    this.currentAst = null;
    this.currentKey = null;
    this.builtKey = null;
    return true;
  }
  cycleHorizontalRatio(backwards) {
    return this.cycleRatio(1 /* Horizontal */, backwards);
  }
  cycleVerticalRatio(backwards) {
    return this.cycleRatio(2 /* Vertical */, backwards);
  }
  buildLayout() {
    const rootTile = new Tile();
    // Disown any tracked window beyond the selected layout's capacity so it
    // becomes floating instead of occupying a ghost slot.
    const capacity = this.tiledCapacity();
    if (this.windows.length > capacity) {
      this.windows = this.windows.slice(0, capacity);
    }
    this.tileMap.clear();
    this.windowTiles.clear();
    // A lone window has no split to rotate or mirror. Clearing the view flags
    // here stops the old state from shaping the next window added.
    if (this.windows.length === 1) {
      this.settings.rotateLayout = false;
      this.settings.mirrorLayout = false;
    }
    if (this.settings.monocle) {
      // One tile holds every window, so KWin stacks them full size and the
      // layout machinery stays out of the way.
      this.currentAst = null;
      this.currentKey = null;
      this.builtKey = null;
      this.currentCount = this.windows.length;
      for (const window of this.windows) {
        rootTile.windows.push(window);
        this.windowTiles.set(window, rootTile);
      }
      return rootTile;
    }
    const count = this.windows.length;
    if (count === 0) {
      this.currentAst = null;
      this.currentKey = null;
      this.builtKey = null;
      this.currentCount = 0;
      return rootTile;
    }
    const custom = this.getCustomLayout(count);
    if (custom === null) {
      this.currentAst = null;
      this.currentKey = null;
      this.builtKey = null;
      this.currentCount = count;
      return rootTile;
    }
    this.currentAst = custom.ast;
    this.currentKey = custom.key;
    this.builtKey = custom.key;
    this.currentCount = count;
    const cursor = { i: 0 };
    this.buildTile(rootTile, custom.ast, cursor);
    return rootTile;
  }
  buildTile(tile, node, cursor) {
    if (node.kind === "leaf") {
      const window = this.windows[cursor.i];
      cursor.i += 1;
      if (window === void 0) {
        return;
      }
      tile.windows.push(window);
      this.tileMap.set(tile, window);
      this.windowTiles.set(window, tile);
      return;
    }
    tile.layoutDirection = node.dir;
    tile.astNode = node;
    for (let i = 0; i < node.children.length; i += 1) {
      const child = tile.addChild();
      child.size = node.sizes[i] ?? 1;
      this.buildTile(child, node.children[i], cursor);
    }
  }
  addWindow(window) {
    // Re-adding the same engine window would build a layout with two leaves
    // pointing at one KWin window, so the count could grow while the screen
    // still shows a single tile. All add paths are idempotent.
    if (this.windows.some((candidate) => candidate === window)) {
      return;
    }
    if (this.isFull()) {
      console().warn(
        "Custom layout is full at",
        CUSTOM_MAX_WINDOWS,
        "windows - leaving this one untiled"
      );
      return;
    }
    if (this.settings.mirrorLayout) {
      this.windows.unshift(window);
    } else {
      this.windows.push(window);
    }
  }
  removeWindow(window) {
    // The leaf map still points at the previous build until the next rebuild.
    // Drop the entry now so isWindowTiled() is correct immediately.
    this.windowTiles.delete(window);
    const index = this.windows.findIndex((candidate) => candidate === window);
    if (index === -1) {
      return;
    }
    this.windows.splice(index, 1);
  }
  placeWindow(window, tile, _direction) {
    const target = this.tileMap.get(tile);
    if (target === void 0) {
      this.addWindow(window);
      return;
    }
    if (target === window) {
      return;
    }
    const sourceIndex = this.windows.findIndex(
      (candidate) => candidate === window
    );
    const targetIndex = this.windows.findIndex(
      (candidate) => candidate === target
    );
    if (sourceIndex === -1) {
      if (this.isFull()) {
        console().warn(
          "Custom layout is full at",
          CUSTOM_MAX_WINDOWS,
          "windows - leaving this one untiled"
        );
        return;
      }
      if (targetIndex === -1) {
        this.windows.push(window);
      } else {
        this.windows.splice(targetIndex, 0, window);
      }
      return;
    }
    if (targetIndex === -1) {
      return;
    }
    this.windows[sourceIndex] = target;
    this.windows[targetIndex] = window;
  }
  windowActivated(window) {
    return false;
  }
  tiledCapacity() {
    if (this.settings !== void 0 && this.settings.monocle === true) {
      return CUSTOM_MAX_WINDOWS;
    }
    const set = this.selectedCustomLayoutSet();
    let max = 0;
    if (set !== null && Array.isArray(set.layouts)) {
      for (const layout of set.layouts) {
        if (typeof layout.count === "number" && layout.count > max) {
          max = layout.count;
        }
      }
    }
    return max > 0 ? max : CUSTOM_MAX_WINDOWS;
  }
  isFull() {
    // Only tiled windows count: floating/extraneous windows are ignored so a
    // fifth window is disowned and floated instead of being squeezed in.
    const tiled = this.windowTiles instanceof Map ? this.windowTiles.size : 0;
    return tiled >= this.tiledCapacity();
  }
  windowCount() {
    if (this.windowTiles instanceof Map && this.windowTiles.size > 0) {
      return this.windowTiles.size;
    }
    return this.windows.length;
  }
  // Steps through the selected tab's layouts for the chosen count. A tab with
  // no matching layout has nothing to cycle.
  cycleVariant(backwards) {
    const layouts = this.customLayoutsForCount(this.windows.length);
    if (layouts.length <= 1) {
      return false;
    }
    let current = this.layoutIndex();
    if (current < 0 || current >= layouts.length) {
      current = 0;
    }
    const next = layouts[(current + (backwards ? -1 : 1) + layouts.length) % layouts.length];
    if (this.settings.customLayouts == null || typeof this.settings.customLayouts !== "object") {
      this.settings.customLayouts = {};
    }
    this.settings.customLayouts[String(layouts[0].count)] = next.text;
    return true;
  }
  // The shape on screen, written in the DSL.
  shapeText() {
    return this.settings.monocle ? "" : this.tiledShapeText();
  }
  // The shape monocle would apply if it were switched off, so the overview can
  // preview what a desktop is about to become.
  tiledShapeText() {
    const count = this.windowTiles instanceof Map && this.windowTiles.size > 0
      ? this.windowTiles.size
      : this.windows.length;
    if (count === 0) {
      return "";
    }
    if (this.currentAst !== null && this.currentCount === count) {
      return layoutText(this.currentAst);
    }
    const custom = this.getCustomLayout(count);
    return custom === null ? "" : layoutText(custom.ast);
  }
  // Cycles which window sits in which leaf.
  rotateWindows(backwards) {
    const tiled = this.windowTiles instanceof Map && this.windowTiles.size > 0
      ? this.windows.filter((w) => this.windowTiles.has(w))
      : this.windows.slice();
    if (tiled.length < 2) {
      return false;
    }
    if (backwards) {
      tiled.push(tiled.shift());
    } else {
      tiled.unshift(tiled.pop());
    }
    // Rebuild this.windows keeping only tiled windows in rotated order; drop
    // any tracked-but-floating extras so they stop affecting cycle/counts.
    this.windows = tiled;
    return true;
  }
  hasWindow(window) {
    return this.windows.some((candidate) => candidate === window);
  }
  // Reads divider positions back after KWin applies them. Every split is read,
  // not just the root, so nested layouts remember their own proportions.
  updateTiles(rootTile) {
    if (this.currentAst === null || this.builtKey !== this.currentKey) {
      return;
    }
    const walk = (node, tile) => {
      if (node.kind !== "split") {
        return;
      }
      if (tile.children.length !== node.children.length) {
        return;
      }
      const sizes = tile.children.map((child) => child.size);
      if (sizes.every((size) => typeof size === "number" && size > 0)) {
        node.sizes = sizes.slice();
      }
      for (let i = 0; i < node.children.length; i += 1) {
        walk(node.children[i], tile.children[i]);
      }
    };
    walk(this.currentAst, rootTile);
  }
};

// src/engine/layouts/kwin.ts
var KwinEngine = class {
  constructor() {
    this.rootTile = new Tile();
    this.windowTiles = /* @__PURE__ */ new Map();
  }
  getEngineSettings() {
    return {
      tiles: this.rootTile.toJSON()
    };
  }
  setEngineSettings(settings) {
    const tiles = settings.tiles;
    if (tiles == void 0) {
      return;
    }
    this.rootTile = Tile.fromJSON(tiles);
  }
  buildLayout() {
    return this.rootTile;
  }
  addWindow(_window, _tile, _direction) {
    return;
  }
  removeWindow(window) {
    const tile = this.windowTiles.get(window);
    this.windowTiles.delete(window);
    if (tile === void 0) {
      return;
    }
    tile.windows.splice(tile.windows.indexOf(window), 1);
  }
  placeWindow(window, tile, _direction) {
    if (this.windowTiles.has(window)) {
      const oldTile = this.windowTiles.get(window);
      oldTile.windows.splice(oldTile.windows.indexOf(window), 1);
    }
    if (!tile.windows.includes(window)) {
      tile.windows.push(window);
    }
    this.windowTiles.set(window, tile);
  }
  windowActivated(_window) {
    return false;
  }
  hasWindow(window) {
    return this.windowTiles.has(window);
  }
  updateTiles(rootTile) {
    this.rootTile = rootTile;
  }
};

// src/engine/index.ts
var TilingEngine = class {
  constructor(type, settings) {
    // The script has one tiling engine plus KWin's own tiling. Old saved engine
    // numbers (Binary Tree, Half and the retired column engines) all resolve to
    // the Custom engine, which keeps their displays tiled after an upgrade.
    if (type === KWIN_ENGINE_TYPE) {
      this.engineType = KWIN_ENGINE_TYPE;
      this.engine = new KwinEngine();
    } else {
      this.engineType = CUSTOM_ENGINE_TYPE;
      this.engine = new CustomEngine();
    }
    this.engine.setEngineSettings(settings);
    this.engineRootTile = this.engine.buildLayout();
  }
  getEngineSettings() {
    return this.engine.getEngineSettings();
  }
  setEngineSettings(settings) {
    this.engine.setEngineSettings(settings);
  }
  buildLayout() {
    this.engineRootTile = this.engine.buildLayout();
    return this.engineRootTile;
  }
  addWindow(window, tile, direction) {
    return this.engine.addWindow(window, tile, direction);
  }
  hasWindow(window) {
    return typeof this.engine.hasWindow === "function" ? this.engine.hasWindow(window) : false;
  }
  // A window can be known to the engine (it counts toward the layout) but have
  // no leaf when the selected layout set has no shape for the current count.
  // Only the leaf assignment proves that the window is actually tiled.
  hasWindowTile(window) {
    return this.engine.windowTiles?.has(window) ?? false;
  }
  placeWindow(window, tile, direction) {
    return this.engine.placeWindow(window, tile, direction);
  }
  windowActivated(window) {
    return this.engine.windowActivated(window);
  }
  removeWindow(window) {
    return this.engine.removeWindow(window);
  }
  updateTiles(rootTile) {
    return this.engine.updateTiles(rootTile);
  }
  // Only the Custom engine understands these; KWin's own tiling keeps working
  // unchanged and simply returns false.
  resetLayoutSizes() {
    if (typeof this.engine.resetLayoutSizes === "function") {
      this.engine.resetLayoutSizes();
    }
  }
  rotateWindows(backwards) {
    if (typeof this.engine.rotateWindows === "function") {
      return this.engine.rotateWindows(backwards);
    }
    return false;
  }
  cycleVariant(backwards) {
    if (typeof this.engine.cycleVariant === "function") {
      return this.engine.cycleVariant(backwards);
    }
    return false;
  }
  cycleHorizontalRatio(backwards) {
    if (typeof this.engine.cycleHorizontalRatio === "function") {
      return this.engine.cycleHorizontalRatio(backwards);
    }
    return false;
  }
  cycleVerticalRatio(backwards) {
    if (typeof this.engine.cycleVerticalRatio === "function") {
      return this.engine.cycleVerticalRatio(backwards);
    }
    return false;
  }
  ratioInfo() {
    if (typeof this.engine.ratioInfo === "function") {
      return this.engine.ratioInfo();
    }
    return { horizontal: "", vertical: "", horizontalCount: 0, verticalCount: 0 };
  }
  // Only the Custom engine keeps a window list it can count and reshape; the
  // others report -1 so the dialog hides the rows rather than guessing.
  windowCount() {
    return typeof this.engine.windowCount === "function" ? this.engine.windowCount() : -1;
  }
  shapeText() {
    return typeof this.engine.shapeText === "function" ? this.engine.shapeText() : "";
  }
  tiledShapeText() {
    return typeof this.engine.tiledShapeText === "function" ? this.engine.tiledShapeText() : this.shapeText();
  }
  layoutCount() {
    return typeof this.engine.layoutCount === "function" ? this.engine.layoutCount() : 1;
  }
  layoutIndex() {
    return typeof this.engine.layoutIndex === "function" ? this.engine.layoutIndex() : -1;
  }
  usingCustomLayout() {
    return typeof this.engine.usingCustomLayout === "function" ? this.engine.usingCustomLayout() : false;
  }
  customLayoutSets() {
    return typeof this.engine.customLayoutSets === "function" ? this.engine.customLayoutSets() : [];
  }
  isFull() {
    return typeof this.engine.isFull === "function" ? this.engine.isFull() : false;
  }
};

// src/controller/config.ts
// Declared before its first textual use: QV4 warns otherwise at script load.
var neverMatch = /(?!)/;
var Config = class {
  constructor(kwinApi) {
    const rc = kwinApi.readConfig;
    this.rebuildDelay = rc("RebuildDelay", 10);
    this.tileResizeAmount = rc("TileResizeAmount", 10);
    this.useDBusSaver = rc("UseDBusSaver", false);
    this.logLevel = rc("LogLevel", 1 /* Warn */);
    this.rawRegex = rc("RawRegex", false);
    const ignoreWindowClasses = rc(
      "IgnoreWindowClasses",
      "krunner, yakuake, kded, polkit, plasmashell, xwaylandvideobridge, kwin_wayland"
    );
    const ignoreWindowCaptions = rc("IgnoreWindowCaptions", "");
    const untileWindowClasses = rc("UntileWindowClasses", "");
    const untileWindowCaptions = rc("UntileWindowCaptions", "");
    // Console is not available while config is read, so bad patterns are
    // collected here and logged once the controller exists.
    this.regexErrors = [];
    this.ignoreWindowClasses = this.buildRegex(ignoreWindowClasses);
    this.ignoreWindowCaptions = this.buildRegex(ignoreWindowCaptions);
    this.untileWindowClasses = this.buildRegex(untileWindowClasses);
    this.untileWindowCaptions = this.buildRegex(untileWindowCaptions);
    this.borders = rc("Borders", 4 /* All */);
    this.tiledWindowsBelow = rc("TiledWindowsBelow", true);
    this.tilePopups = rc("TilePopups", false);
    this.windowDragPolicy = rc("WindowDragPolicy", 1 /* Tiled */);
    this.dragRetilePoint = rc("DragRetilePoint", 0 /* Mouse */);
    // Dragged window is always shown at the tiled size scaled by the custom
    // percent (100% is exactly the tiled size).
    this.dragWindowSizePercent = rc("DragWindowSizePercent", 100);
    // 0 leaves placement to KWin; 1..9 are the cells of a 3x3 output grid.
    this.floatingSpawnPoint = rc("FloatingSpawnPoint", 0);
    this.mouseFollowsFocus = rc("MouseFollowsFocus", false);
    this.mouseFollowsFocusDelay = rc("MouseFollowsFocusDelay", 50);
    this.mouseFollowsFocusIgnoreEffects = rc(
      "MouseFollowsFocusIgnoreEffects",
      "foloniumoverview"
    ).split(",").map((x) => x.trim()).filter(Boolean);
    // Keep all nine slots so L1..L9 indices do not shift when a tab is empty.
    this.customLayoutTexts = [];
    for (let i = 1; i <= CUSTOM_MAX_WINDOWS; i += 1) {
      this.customLayoutTexts.push(String(rc("CustomLayout" + i, "") ?? "").trim());
    }
    this.customRatios = parseRatioList(rc("CustomRatios", DEFAULT_RATIO_TEXT));
    this.customSettings = {
      mirrorLayout: rc("CustomMirrorLayout", false),
      rotateLayout: rc("CustomRotateLayout", false),
      monocle: rc("CustomMonocle", false),
      customLayoutTab: 0,
      customLayouts: {}
    };
  }
  // A bad user-supplied pattern must never stop the whole script from loading.
  // Upstream 1.2.2 groups the comma-separated alternatives and treats an empty
  // list as "match nothing"; the old /^$/ form matched windows whose metadata
  // had not been filled in yet.
  buildRegex(str) {
    if (this.rawRegex) {
      if (str === "") {
        return neverMatch;
      }
      try {
        return new RegExp(str);
      } catch (e) {
        this.regexErrors.push(
          `invalid regex "${str}" (${e.message}), ignoring it`
        );
        return neverMatch;
      }
    }
    const parts = str.split(",").map((x) => x.trim()).filter(Boolean).map((part) => {
      try {
        new RegExp(part);
        return part;
      } catch (e) {
        this.regexErrors.push(
          `invalid regex "${part}" (${e.message}), matching it literally`
        );
        return escapeRegex(part);
      }
    });
    if (parts.length == 0) {
      return neverMatch;
    }
    return new RegExp("^(?:" + parts.join("|") + ")$");
  }
};
function escapeRegex(str) {
  return str.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
}

// src/controller/handlers/window.ts
var WindowHandler = class {
  constructor(window, workspace) {
    this.wasTiledBeforeMove = false;
    this.tiledRect = null;
    this.dragSizeApplied = false;
    this.window = window;
    this.workspace = workspace;
    this.wantsTiled = this.startTiled();
    // startTiled still decides intent first; then the real state stops the first
    // rebuild from unmaximizing an already-maximized window.
    this.maximized = this.window.maximizeMode !== 0;
    this.window.desktopsChanged.connect(this.updateWindow.bind(this));
    this.window.activitiesChanged.connect(this.updateWindow.bind(this));
    this.window.outputChanged.connect(this.updateWindow.bind(this));
    this.window.fullScreenChanged.connect(
      this.fullscreenChanged.bind(this)
    );
    this.window.minimizedChanged.connect(this.minimizedChanged.bind(this));
    this.window.maximizedAboutToChange.connect(
      this.maximizedChanged.bind(this)
    );
    this.window.interactiveMoveResizeStarted.connect(
      this.interactiveMoveResizeStarted.bind(this)
    );
    this.window.interactiveMoveResizeStepped.connect(
      this.interactiveMoveResizeStepped.bind(this)
    );
    this.window.interactiveMoveResizeFinished.connect(
      this.interactiveMoveResizeFinished.bind(this)
    );
    this.window.tileChanged.connect(this.tileChanged.bind(this));
  }
  startTiled() {
    if (!isTrackableWindow(this.window)) {
      return false;
    }
    if (!this.canBeTiled()) {
      return false;
    }
    if (config().untileWindowClasses.test(this.window.resourceClass)) {
      return false;
    }
    if (config().untileWindowCaptions.test(this.window.caption)) {
      return false;
    }
    return true;
  }
  updateWindow() {
    console().debug(
      "updating displays for window",
      this.window.resourceClass
    );
    controller().queueEvent({
      t: "updateWindow",
      window: this.window
    }, true);
  }
  fullscreenChanged() {
    console().debug(
      "fullscreen changed on window",
      this.window.resourceClass
    );
    // Keep a tiled window in its slot while fullscreen. Removing it would
    // reflow the whole layout and move every other window.
    if (this.canBeTiled() && this.wantsTiled) {
      controller().queueEvent({
        t: "tileWindow",
        window: this.window
      });
    }
    if (this.window.fullScreen) {
      controller().queuePostEvent({
        t: "setWindowProperties",
        window: this.window,
        fullscreen: false
      });
      controller().queuePostEvent({
        t: "setWindowProperties",
        window: this.window,
        fullscreen: true,
        keepAbove: true
      });
    } else {
      controller().queuePostEvent({
        t: "setWindowProperties",
        window: this.window,
        keepAbove: false
      });
    }
  }
  minimizedChanged() {
    console().debug(
      "minimized changed on window",
      this.window.resourceClass
    );
    // Minimizing keeps the window's slot, so restoring it does not shuffle the
    // layout. The slot is simply left empty while it is minimized.
    if (this.canBeTiled() && this.wantsTiled) {
      controller().queueEvent({
        t: "tileWindow",
        window: this.window
      });
    }
  }
  maximizedChanged(state) {
    if (controller().isWindowOnKwinEngine(this.window)) {
      return;
    }
    console().debug(
      "maximized state changed on window",
      this.window.resourceClass
    );
    this.maximized = state !== 0 /* MaximizeRestore */;
    // Maximizing keeps the window in its tile slot. On restore, reassert the
    // tile so KWin puts it back where it was instead of at the end.
    if (this.canBeTiled() && this.wantsTiled) {
      controller().queueEvent({
        t: "tileWindow",
        window: this.window
      });
    }
  }
  // multiple step move resize -
  // a tiled window is marked as dragging so the engine keeps its slot and the
  // layout does not retile for n-1 windows; the drop either swaps it or floats it
  interactiveMoveResizeStarted() {
    this.wasTiledBeforeMove = controller().isWindowTiled(this.window) ?? false;
    // The tile is still attached when the move starts; remember its size for
    // the "keep the tiled size" and custom drag-size modes.
    const geometry = this.window.tile?.absoluteGeometry ?? this.window.frameGeometry;
    this.tiledRect = qt().rect(geometry.x, geometry.y, geometry.width, geometry.height);
    this.dragSizeApplied = false;
  }
  interactiveMoveResizeStepped() {
    if (controller().isWindowOnKwinEngine(this.window)) {
      return;
    }
    if (!controller().isWindowTiled(this.window) || !this.canBeTiled() || this.window.tile != null) {
      return;
    }
    if (controller().isWindowInMonocle(this.window)) {
      return;
    }
    if (!this.wasTiledBeforeMove && config().windowDragPolicy !== 2 /* Never */) {
      return;
    }
    console().debug("move started on window", this.window.resourceClass);
    this.applyDragSize();
    if (config().windowDragPolicy == 2 /* Never */) {
      this.wantsTiled = false;
      controller().queueEvent({
        t: "untileWindow",
        window: this.window
      });
      return;
    }
    // Leave the window in the engine, but out of KWin's tile, so the other
    // windows keep their slots while it is dragged over them.
    controller().queueEvent({
      t: "dragWindow",
      window: this.window
    });
  }
  // A dragged window can be shown at the tiled size or a scaled-down version
  // so it is easy to drop between tiles. Natural KWin behaviour is the other
  // option; the custom percent defaults to 100%, which is the tiled size.
  applyDragSize() {
    if (this.dragSizeApplied) {
      return;
    }
    this.dragSizeApplied = true;
    const source = this.tiledRect;
    if (source === null || source.width <= 0 || source.height <= 0) {
      return;
    }
    const percent = Math.min(100, Math.max(10, Number(config().dragWindowSizePercent) || 100));
    const width = Math.round(source.width * percent / 100);
    const height = Math.round(source.height * percent / 100);
    const frame = this.window.frameGeometry;
    const cursor = this.workspace.cursorPos;
    // Keep the cursor at the same spot of the window so it does not jump
    // out from under the pointer.
    const relX = frame.width > 0 ? (cursor.x - frame.x) / frame.width : 0.5;
    const relY = frame.height > 0 ? (cursor.y - frame.y) / frame.height : 0.5;
    this.window.frameGeometry = qt().rect(
      Math.round(cursor.x - width * relX),
      Math.round(cursor.y - height * relY),
      width,
      height
    );
  }
  interactiveMoveResizeFinished() {
    if (!this.canBeTiled()) {
      return;
    }
    if (!controller().isWindowOnKwinEngine(this.window) && this.wasTiledBeforeMove && this.wantsTiled && !controller().isWindowInMonocle(this.window)) {
      controller().queueEvent({
        t: "placeWindowPoint",
        window: this.window,
        point: this.getInsertionPoint()
      });
      return;
    }
    let tiled = controller().isWindowTiled(this.window) === true;
    // A drag can make KWin drop its tile before the stepped signal is
    // delivered. Reconcile the engine here instead of leaving a floating
    // window that Folonium still counts as part of the layout.
    if (tiled && this.window.tile == null) {
      controller().queueEvent({
        t: "untileWindow",
        window: this.window
      });
      tiled = false;
    }
    if (!this.wantsTiled || tiled || this.window.tile != null) {
      return;
    }
    if (!this.wasTiledBeforeMove && config().windowDragPolicy == 1 /* Tiled */) {
      return;
    }
    console().debug("move finished on window", this.window.resourceClass);
    controller().queueEvent({
      t: "placeWindowPoint",
      window: this.window,
      point: this.getInsertionPoint()
    });
  }
  // Where a released drag asks to be inserted. Upstream 1.2.2 made this
  // configurable; the cursor default preserves the old behaviour.
  getInsertionPoint() {
    switch (config().dragRetilePoint) {
      case 1 /* Center */:
        return qt().point(
          this.window.frameGeometry.x + this.window.frameGeometry.width / 2,
          this.window.frameGeometry.y + this.window.frameGeometry.height / 2
        );
      case 2 /* Top */:
        return qt().point(
          this.window.frameGeometry.x + this.window.frameGeometry.width / 2,
          this.window.frameGeometry.y
        );
      default:
        return this.workspace.cursorPos;
    }
  }
  // this only tracks manual insertion into a tile
  tileChanged(tile) {
    if (controller().isWindowOnKwinEngine(this.window) || controller().isWindowInMonocle(this.window)) {
      return;
    }
    // Trust the live tiling state instead of the previous signal value: a
    // shift-drag can land in a tile while KWin still reports the old tile.
    if (tile != null && !controller().isWindowTiled(this.window)) {
      this.wantsTiled = true;
      controller().queueEvent({
        t: "placeWindow",
        window: this.window,
        tile,
        // frameGeometry equals the tile geometry after insertion, so the
        // cursor is the only reliable direction hint.
        direction: directionFromPoint(tile.absoluteGeometry, this.workspace.cursorPos)
      });
    }
  }
  canBeTiled() {
    return !(this.window.fullScreen || this.window.minimized || this.maximized);
  }
};

// src/controller/handlers/workspace.ts
var WorkspaceHandler = class {
  constructor(workspace) {
    this.workspace = workspace;
    this.previousActivated = null;
    this.currentActivated = this.workspace.activeWindow;
    this.workspace.windowAdded.connect(this.windowAdded.bind(this));
    this.workspace.windowRemoved.connect(this.windowRemoved.bind(this));
    this.workspace.windowActivated.connect(this.windowActivated.bind(this));
    this.workspace.currentActivityChanged.connect(
      this.rebuildDesktops.bind(this)
    );
    this.workspace.currentActivityChanged.connect(
      () => controller().mouseFollowsFocus()?.displayChanged()
    );
    this.workspace.currentDesktopChanged.connect(
      () => controller().mouseFollowsFocus()?.displayChanged()
    );
    this.workspace.screensChanged.connect(this.updateDrivers.bind(this));
    this.workspace.desktopsChanged.connect(this.updateDrivers.bind(this));
    this.workspace.activityAdded.connect(this.updateDrivers.bind(this));
    this.workspace.activityRemoved.connect(this.updateDrivers.bind(this));
    this.workspace.activitiesChanged.connect(this.updateDrivers.bind(this));
  }
  windowAdded(window, adopt = false) {
    if (!isTrackableWindow(window)) {
      return;
    }
    if (config().ignoreWindowClasses.test(window.resourceClass) || config().ignoreWindowCaptions.test(window.caption)) {
      return;
    }
    let tile, direction = void 0;
    // Adoption happens on startup, where previousActivated still points at a
    // window from the previous script instance; its tile must not be reused.
    if (!adopt && this.previousActivated?.tile != null) {
      tile = this.previousActivated.tile;
      direction = directionFromPoint(
        tile.absoluteGeometry,
        this.workspace.cursorPos
      );
    }
    // Lifecycle events must not be dropped just because a rebuild is in
    // flight; a lost add/delete is what leaves a window counted forever.
    controller().queueEvent({
      t: "newWindow",
      window,
      tile,
      direction
    }, true);
  }
  windowRemoved(window) {
    controller().mouseFollowsFocus()?.windowRemoved(window);
    // KWin may clear a window's desktop/activity/output before emitting this
    // signal. Never let that stop the delete event: the controller also
    // searches its live drivers for the window.
    let displays = [];
    try {
      displays = [...Display.generateWindow(window)];
    } catch (e) {
      console().debug("could not resolve displays for closing window", e);
    }
    controller().queueEvent({
      t: "deleteWindow",
      window,
      displays
    }, true);
  }
  rebuildDesktops() {
    controller().queueEvent({ t: "rebuildDisplays" });
  }
  updateDrivers() {
    controller().queueEvent({ t: "updateDrivers" });
  }
  windowActivated(window) {
    controller().mouseFollowsFocus()?.windowActivated(window);
    // Popups are not part of the tiled workspace, so activating a context menu
    // must not replace the tiled window that the next window inherits from.
    if (window !== null && !isTrackableWindow(window)) {
      return;
    }
    this.previousActivated = this.currentActivated;
    this.currentActivated = window;
    const borders = config().borders;
    if (this.previousActivated !== null && (borders === 2 /* Active */ || borders === 3 /* FloatingActive */ && controller().isWindowTiled(this.previousActivated))) {
      controller().queuePostEvent({
        t: "setWindowProperties",
        window: this.previousActivated,
        noBorder: true
      });
    }
    if (window === null) {
      return;
    }
    if ((borders === 2 /* Active */ || borders === 3 /* FloatingActive */) && controller().isWindowTiled(window)) {
      controller().queuePostEvent({
        t: "setWindowProperties",
        window,
        noBorder: false
      });
    }
    controller().queueEvent({
      t: "windowActivated",
      window
    });
  }
};

// src/controller/handlers/mousefollowsfocus.ts
var displayChangeQuietMs = 250;
var hitTestDepth = 8;
// KWin's delayed focus-follows-mouse lands up to 300 ms after the pointer stops.
var pointerQuietMs = 400;
var MouseFollowsFocusHandler = class {
  constructor(workspace, timer, dbus) {
    this.target = null;
    this.armPos = null;
    this.lastWindow = null;
    this.quietUntil = 0;
    this.lastMotion = 0;
    this.wasInside = false;
    this.rebuildPos = null;
    this.workspace = workspace;
    this.timer = timer;
    this.dbus = dbus;
    this.timer.interval = config().mouseFollowsFocusDelay;
    this.timer.repeat = false;
    this.timer.triggered.connect(this.warp.bind(this));
    this.workspace.cursorPosChanged.connect(() => {
      this.lastMotion = Date.now();
    });
  }
  windowActivated(window) {
    if (this.effectOpen()) {
      this.reset();
      return;
    }
    if (!isMouseTargetable(window)) {
      return;
    }
    // Focus handed back after a shell popup or effect closes.
    if (window === this.lastWindow) {
      return;
    }
    this.lastWindow = window;
    if (Date.now() < this.quietUntil) {
      return;
    }
    if (this.cursorInside(window)) {
      // Focus landed under a stationary cursor on its own - that is
      // focus-follows-mouse reverting a keyboard focus change, so keep the
      // pending warp. A moved cursor means the user did it.
      if (this.target !== null && !this.cursorMoved()) {
        return;
      }
      this.target = null;
      this.armPos = null;
      this.timer.stop();
      return;
    }
    // Keyboard and script activations raise the window first; a delayed
    // focus-follows-mouse activation never does.
    if (!this.isRaised(window) && this.motionAge() < pointerQuietMs) {
      return;
    }
    this.target = window;
    this.armPos = copyPos(this.workspace.cursorPos);
    this.timer.restart();
  }
  // Called by the controller right before it rebuilds layouts.
  beforeRebuild() {
    const active = this.workspace.activeWindow;
    this.wasInside = isMouseTargetable(active) && this.cursorInside(active);
    this.rebuildPos = copyPos(this.workspace.cursorPos);
  }
  // Called after rebuilding; a retile can move the focused window out from
  // under the cursor without any activation.
  retiled() {
    if (this.effectOpen()) {
      this.reset();
      return;
    }
    if (Date.now() < this.quietUntil) {
      return;
    }
    if (this.target === null && !this.wasInside) {
      this.timer.stop();
      return;
    }
    this.timer.restart();
  }
  // Desktop switches, drags and move-to-desktop change focus without a
  // keyboard focus move.
  displayChanged() {
    this.quietUntil = Date.now() + displayChangeQuietMs;
    this.target = null;
    this.armPos = null;
    this.timer.stop();
  }
  windowRemoved(window) {
    if (this.lastWindow === window) {
      this.lastWindow = null;
    }
    if (this.target === window) {
      this.target = null;
      this.armPos = null;
    }
  }
  // A full-screen effect owns the pointer; its activations must not arm or
  // fire a warp.
  effectOpen() {
    return config().mouseFollowsFocusIgnoreEffects.some(
      (id) => this.workspace.isEffectActive(id)
    );
  }
  reset() {
    this.target = null;
    this.armPos = null;
    this.timer.stop();
  }
  motionAge() {
    return this.lastMotion === 0 ? Infinity : Date.now() - this.lastMotion;
  }
  cursorMoved() {
    return this.cursorMovedSince(this.armPos);
  }
  cursorMovedSince(p) {
    const pos = this.workspace.cursorPos;
    return p === null || pos.x !== p.x || pos.y !== p.y;
  }
  // KWin's own hit test, past shell overlays; a cursor in a gap is inside
  // nothing.
  cursorInside(window) {
    const under = this.workspace.windowAt(this.workspace.cursorPos, hitTestDepth).find((w) => isMouseTargetable(w));
    return under === window;
  }
  // Topmost targetable window of its layer on this desktop; a window KWin has
  // not stacked yet was just mapped and goes on top.
  isRaised(window) {
    const order = this.workspace.stackingOrder;
    if (!order.includes(window)) {
      return true;
    }
    const desktop = this.workspace.currentDesktop;
    for (let i = order.length - 1; i >= 0; i -= 1) {
      const w = order[i];
      if (!isMouseTargetable(w) || w.layer !== window.layer || w.minimized || w.hidden || (w.transient && w !== window) || (!w.onAllDesktops && !w.desktops.includes(desktop))) {
        continue;
      }
      return w === window;
    }
    return false;
  }
  warp() {
    if (this.effectOpen()) {
      this.reset();
      return;
    }
    const target = this.target;
    const moved = this.cursorMoved();
    this.target = null;
    this.armPos = null;
    let active = this.workspace.activeWindow;
    if (active !== null && !isMouseTargetable(active)) {
      return;
    }
    // A retile only earns a warp if it moved the window from under a still
    // cursor.
    if (target === null && this.cursorMovedSince(this.rebuildPos)) {
      return;
    }
    if (target !== null && !moved && active !== target) {
      this.workspace.activeWindow = target;
      active = target;
    }
    if (active === null) {
      return;
    }
    if (active.move || active.resize) {
      return;
    }
    if (this.cursorInside(active)) {
      return;
    }
    this.dbus.moveMouseToFocus().call();
  }
};
// Layer-shell surfaces report a Normal window type, so specialWindow misses
// them.
function isMouseTargetable(window) {
  return window !== null && window !== void 0 && !window.specialWindow && !window.popupWindow && !(window.skipTaskbar && !window.moveable);
}
function copyPos(p) {
  return { x: p.x, y: p.y };
}

// src/controller/handlers/shortcuts.ts
var ShortcutsHandler = class {
  constructor(workspace, shortcuts) {
    this.workspace = workspace;
    this.shortcuts = shortcuts;
    this.shortcuts.toggleActiveTiling().activated.connect(this.toggleActiveTiling.bind(this));
    this.shortcuts.activateBelow().activated.connect(
      this.activateRelative.bind(this, false)
    );
    this.shortcuts.activateAbove().activated.connect(
      this.activateRelative.bind(this, true)
    );
    this.shortcuts.activateLeft().activated.connect(
      this.activateRelative.bind(this, true)
    );
    this.shortcuts.activateRight().activated.connect(
      this.activateRelative.bind(this, false)
    );
    this.shortcuts.placeBelow().activated.connect(
      this.placeInDirection.bind(this, 8 /* BottomEdge */)
    );
    this.shortcuts.placeAbove().activated.connect(this.placeInDirection.bind(this, 1 /* TopEdge */));
    this.shortcuts.placeLeft().activated.connect(this.placeInDirection.bind(this, 2 /* LeftEdge */));
    this.shortcuts.placeRight().activated.connect(
      this.placeInDirection.bind(this, 4 /* RightEdge */)
    );
    this.shortcuts.resizeDown().activated.connect(
      this.resizeInDirection.bind(this, 8 /* BottomEdge */)
    );
    this.shortcuts.resizeUp().activated.connect(this.resizeInDirection.bind(this, 1 /* TopEdge */));
    this.shortcuts.resizeLeft().activated.connect(
      this.resizeInDirection.bind(this, 2 /* LeftEdge */)
    );
    this.shortcuts.resizeRight().activated.connect(
      this.resizeInDirection.bind(this, 4 /* RightEdge */)
    );
    this.shortcuts.toggleSettingsMenu().activated.connect(
      this.toggleSettingsMenu.bind(this)
    );
    this.shortcuts.rotateLayout().activated.connect(
      this.modifyEngineSetting.bind(this, "rotateLayout", "toggle", void 0, void 0, 2)
    );
    this.shortcuts.mirrorLayout().activated.connect(
      this.modifyEngineSetting.bind(this, "mirrorLayout", "toggle", void 0, void 0, 2)
    );
    this.shortcuts.rotateWindows().activated.connect(
      this.rotateWindows.bind(this, false)
    );
    this.shortcuts.cycleLayout().activated.connect(
      this.cycleVariant.bind(this, false)
    );
    this.shortcuts.cycleHorizontalRatio().activated.connect(
      this.cycleHorizontalRatio.bind(this, false)
    );
    this.shortcuts.cycleVerticalRatio().activated.connect(
      this.cycleVerticalRatio.bind(this, false)
    );
    this.shortcuts.toggleKwinEngine().activated.connect(
      this.toggleKwinEngine.bind(this)
    );
    this.shortcuts.toggleMonocle().activated.connect(
      this.modifyEngineSetting.bind(this, "monocle", "toggle")
    );
  }
  // Returns the driver for the display in view, but only if it holds at least
  // `min` windows. Shortcuts like "rotate the split" are meaningless below that.
  driverFor(min) {
    const display = new Display(
      this.workspace.currentDesktop,
      this.workspace.currentActivity,
      this.workspace.activeScreen
    );
    const driver = controller().getDriver(display);
    if (driver === void 0) {
      return void 0;
    }
    if (min !== void 0) {
      const count = driver.windowCount();
      if (count < 0 || count < min) {
        return void 0;
      }
    }
    return driver;
  }
  rotateWindows(backwards) {
    const driver = this.driverFor(2);
    if (driver === void 0) {
      return;
    }
    if (driver.rotateWindows(backwards)) {
      controller().queueEvent({
        t: "updateTiles",
        display: new Display(
          this.workspace.currentDesktop,
          this.workspace.currentActivity,
          this.workspace.activeScreen
        ),
        rebuild: true
      });
    }
  }
  toggleKwinEngine() {
    // One implementation, so the shortcut and the popup save the engine switch
    // to the per-display store the same way.
    controller().toggleKwinEngine();
  }
  // Steps the Custom engine through the shapes available for however many
  // windows are open right now.
  cycleVariant(backwards) {
    const display = new Display(
      this.workspace.currentDesktop,
      this.workspace.currentActivity,
      this.workspace.activeScreen
    );
    const driver = controller().getDriver(display);
    if (driver === void 0 || driver.windowCount() < 2) {
      return;
    }
    if (driver.cycleVariant(backwards)) {
      controller().queueEvent({
        t: "updateTiles",
        display,
        rebuild: true
      });
    }
  }
  cycleRatio(dir, backwards) {
    const display = new Display(
      this.workspace.currentDesktop,
      this.workspace.currentActivity,
      this.workspace.activeScreen
    );
    const driver = controller().getDriver(display);
    if (driver === void 0) {
      return;
    }
    const changed = dir === 1 /* Horizontal */ ? driver.cycleHorizontalRatio(backwards) : driver.cycleVerticalRatio(backwards);
    if (changed) {
      controller().queueEvent({
        t: "updateTiles",
        display,
        rebuild: true
      });
    }
  }
  cycleHorizontalRatio(backwards) {
    this.cycleRatio(1 /* Horizontal */, backwards);
  }
  cycleVerticalRatio(backwards) {
    this.cycleRatio(2 /* Vertical */, backwards);
  }
  toggleActiveTiling() {
    const window = this.workspace.activeWindow;
    if (window == null) return;
    const windowHandler = controller().getWindowHandler(window);
    if (windowHandler == void 0) return;
    if (controller().isWindowTiled(window)) {
      windowHandler.wantsTiled = false;
      controller().queueEvent({
        t: "untileWindow",
        window
      });
    } else {
      windowHandler.wantsTiled = true;
      controller().queueEvent({
        t: "tileWindow",
        window
      });
    }
  }
  getTileInDirection(tile, rootTile, edge) {
    if (tile == rootTile) return null;
    let x = tile.absoluteGeometry.x;
    let y = tile.absoluteGeometry.y;
    switch (edge) {
      case 8 /* BottomEdge */:
        x += tile.absoluteGeometry.width / 2;
        y += tile.absoluteGeometry.height + 2;
        break;
      case 1 /* TopEdge */:
        x += tile.absoluteGeometry.width / 2;
        y -= 2;
        break;
      case 2 /* LeftEdge */:
        x -= 2;
        y += tile.absoluteGeometry.height / 2;
        break;
      case 4 /* RightEdge */:
        x += tile.absoluteGeometry.width + 2;
        y += tile.absoluteGeometry.height / 2;
        break;
      default:
        return null;
    }
    const point = qt().point(Math.floor(x), Math.floor(y));
    console().debug("selecting tile for point", point);
    return rootTile.pick(point);
  }
  // Left/Up step back through the engine's window order, Right/Down step
  // forward, wrapping at the ends. No geometry picking.
  activateRelative(backwards) {
    const window = this.workspace.activeWindow;
    if (window === null || window === void 0) {
      return;
    }
    const driver = controller().windowDriver(window);
    if (driver === void 0) {
      return;
    }
    const order = driver.windowOrder();
    const index = order.indexOf(window);
    if (index === -1 || order.length < 2) {
      return;
    }
    const next = (index + (backwards ? -1 : 1) + order.length) % order.length;
    this.workspace.activeWindow = order[next];
  }
  placeInDirection(edge) {
    const window = this.workspace.activeWindow;
    if (window === null) {
      return;
    }
    const currentTile = window.tile;
    if (currentTile === null) return;
    let rootTile = currentTile;
    while (rootTile.parent != null) {
      rootTile = rootTile.parent;
    }
    const targetTile = this.getTileInDirection(currentTile, rootTile, edge);
    if (targetTile == null) return;
    let direction = void 0;
    switch (edge) {
      case 1 /* TopEdge */:
        direction = 4 /* Vertical */;
        break;
      case 8 /* BottomEdge */:
        direction = 1 /* Down */ | 4 /* Vertical */;
        break;
      case 2 /* LeftEdge */:
        direction = 0 /* None */;
        break;
      case 4 /* RightEdge */:
        direction = 2 /* Right */;
        break;
      default:
        break;
    }
    if (edge & 8 /* BottomEdge */ || edge & 1 /* TopEdge */) {
      const currentCenter = currentTile.absoluteGeometry.x + currentTile.absoluteGeometry.width / 2;
      const targetCenter = targetTile.absoluteGeometry.x + targetTile.absoluteGeometry.width / 2;
      if (currentCenter > targetCenter && direction !== void 0) {
        direction |= 2 /* Right */;
      }
    } else if (edge & 2 /* LeftEdge */ || edge & 4 /* RightEdge */) {
      const currentCenter = currentTile.absoluteGeometry.y + currentTile.absoluteGeometry.height / 2;
      const targetCenter = targetTile.absoluteGeometry.y + targetTile.absoluteGeometry.height / 2;
      if (currentCenter > targetCenter && direction !== void 0) {
        direction |= 1 /* Down */;
      }
    }
    controller().queueEvent({
      t: "placeWindow",
      window,
      tile: targetTile,
      direction
    });
  }
  resizeInDirection(edge) {
    const currentTile = this.workspace.activeWindow?.tile;
    if (currentTile == null) return;
    const amount = config().tileResizeAmount;
    // A tile already at the window/screen edge cannot grow outwards, so push
    // the opposite edge inwards instead. Upstream 1.2.2 added this so the
    // resize shortcut keeps working at maximum size.
    switch (edge) {
      case 1 /* TopEdge */: {
        const oldTop = currentTile.absoluteGeometry.y;
        currentTile.resizeByPixels(-amount, 1 /* TopEdge */);
        if (oldTop === currentTile.absoluteGeometry.y) {
          currentTile.resizeByPixels(-amount, 8 /* BottomEdge */);
        }
        break;
      }
      case 8 /* BottomEdge */: {
        const oldBottom = currentTile.absoluteGeometry.y + currentTile.absoluteGeometry.height;
        currentTile.resizeByPixels(amount, 8 /* BottomEdge */);
        if (oldBottom === currentTile.absoluteGeometry.y + currentTile.absoluteGeometry.height) {
          currentTile.resizeByPixels(amount, 1 /* TopEdge */);
        }
        break;
      }
      case 2 /* LeftEdge */: {
        const oldLeft = currentTile.absoluteGeometry.x;
        currentTile.resizeByPixels(-amount, 2 /* LeftEdge */);
        if (oldLeft === currentTile.absoluteGeometry.x) {
          currentTile.resizeByPixels(-amount, 4 /* RightEdge */);
        }
        break;
      }
      case 4 /* RightEdge */: {
        const oldRight = currentTile.absoluteGeometry.x + currentTile.absoluteGeometry.width;
        currentTile.resizeByPixels(amount, 4 /* RightEdge */);
        if (oldRight === currentTile.absoluteGeometry.x + currentTile.absoluteGeometry.width) {
          currentTile.resizeByPixels(amount, 2 /* LeftEdge */);
        }
        break;
      }
      default:
        break;
    }
  }
  toggleSettingsMenu() {
    controller().queuePostEvent({
      t: "toggleSettingsMenu",
      display: new Display(
        this.workspace.currentDesktop,
        this.workspace.currentActivity,
        this.workspace.activeScreen
      )
    });
  }
  modifyEngineSetting(setting, op, amount, min, max, minWindows) {
    if (minWindows !== void 0 && this.driverFor(minWindows) === void 0) {
      return;
    }
    const ev = {
      t: "modifyEngineSetting",
      display: new Display(
        this.workspace.currentDesktop,
        this.workspace.currentActivity,
        this.workspace.activeScreen
      ),
      setting,
      op
    };
    if (amount !== void 0) {
      ev.amount = amount;
    }
    if (min !== void 0) {
      ev.min = min;
    }
    if (max !== void 0) {
      ev.max = max;
    }
    controller().queueEvent(ev);
  }
};

// src/controller/handlers/settings.ts
var SettingsHandler = class {
  constructor(settingsQml) {
    this.settingsQml = settingsQml;
    this.display = null;
    this.settingsQml.saveSettings.connect(this.saveSettings.bind(this));
    this.settingsQml.resetSettings.connect(this.resetSettings.bind(this));
    this.settingsQml.cycleVariant.connect(this.cycleVariant.bind(this));
    this.settingsQml.cycleHorizontalRatio.connect(this.cycleHorizontalRatio.bind(this));
    this.settingsQml.cycleVerticalRatio.connect(this.cycleVerticalRatio.bind(this));
    this.settingsQml.rotateWindows.connect(this.rotateWindows.bind(this));
    this.settingsQml.toggleKwinEngine.connect(this.toggleKwinEngine.bind(this));
    this.settingsQml.selectCustomLayoutTab.connect(this.selectCustomLayoutTab.bind(this));
  }
  // Live state the dialog shows but must never edit itself.
  show(display, engineType, engineSettings, windowCount, layoutCount, shapeText, layoutIndex, customSelected, customLayoutSets, ratioInfo) {
    console().debug("showing settings");
    this.display = display;
    this.settingsQml.show(
      display.desktop,
      display.activity,
      display.output,
      engineType,
      engineSettings,
      windowCount,
      layoutCount,
      shapeText,
      layoutIndex,
      customSelected === true,
      customLayoutSets ?? [],
      ratioInfo ?? { horizontal: "", vertical: "", horizontalCount: 0, verticalCount: 0 }
    );
  }
  hide() {
    this.settingsQml.hide();
  }
  isVisible() {
    return this.settingsQml.visible;
  }
  saveSettings(desktop, activity, output, engineType, engineSettings) {
    controller().queueEvent({
      t: "changeEngine",
      display: new Display(desktop, activity, output),
      engineType,
      engineSettings
    });
  }
  resetSettings(desktop, activity, output) {
    controller().queueEvent({
      t: "resetEngine",
      display: new Display(desktop, activity, output)
    });
  }
  // The dialog's rotate buttons reuse the same code paths as the shortcuts.
  cycleVariant(backwards) {
    controller().cycleVariant(backwards === true);
  }
  cycleHorizontalRatio(backwards) {
    controller().cycleHorizontalRatio(backwards === true);
  }
  cycleVerticalRatio(backwards) {
    controller().cycleVerticalRatio(backwards === true);
  }
  rotateWindows(backwards) {
    controller().rotateWindows(backwards === true);
  }
  toggleKwinEngine() {
    controller().toggleKwinEngine();
  }
  selectCustomLayoutTab(desktop, activity, output, tabIndex) {
    controller().selectCustomLayoutTab(
      new Display(desktop, activity, output),
      tabIndex
    );
  }
};

// src/controller/handlers/dbus.ts
function settingsBundle(engineType, engineSettings, lastEngine, lastEngineSettings) {
  const bundle = {
    engineType,
    engineSettings
  };
  // Only sent once something has been remembered; keeps old bundles byte-identical.
  if (typeof lastEngine === "number") {
    bundle.lastEngine = lastEngine;
  }
  // When KWin is in charge, remember the Custom settings too. Without this a
  // restart while KWin is active makes "Back to Tiling" come back with
  // defaults, even though the same display remembers its layout in-session.
  if (lastEngineSettings !== null && lastEngineSettings !== void 0 && typeof lastEngineSettings === "object") {
    bundle.lastEngineSettings = lastEngineSettings;
  }
  return JSON.stringify(bundle);
}
var DBusHandler = class {
  constructor(dbusQml) {
    this.dbusQml = dbusQml;
    dbusQml.getSettings().finished.connect(this.getSettingsCallback.bind(this));
    dbusQml.takeRequest().finished.connect(this.takeRequestCallback.bind(this));
  }
  // Ask the saver for the command the overview left behind, if any.
  takeRequest() {
    this.dbusQml.takeRequest().call();
  }
  takeRequestCallback([requestStr]) {
    if (requestStr === void 0 || requestStr === "") return;
    let request;
    try {
      request = JSON.parse(requestStr);
    } catch (e) {
      console().error(e);
      return;
    }
    if (request === null || typeof request !== "object") return;
    controller().handleRequest(request);
  }
  getSettings(display) {
    console().debug("getSettings called");
    this.dbusQml.getSettings().arguments = [display.toString()];
    this.dbusQml.getSettings().call();
  }
  getSettingsCallback([
    desktopIdStr,
    settingsBundleStr
  ]) {
    console().debug(
      "getSettings dbus callback activated -",
      desktopIdStr,
      settingsBundleStr
    );
    try {
      if (settingsBundleStr === void 0 || settingsBundleStr === "") {
        return;
      }
      const settingsBundle2 = JSON.parse(
        settingsBundleStr
      );
      if (settingsBundle2 === null || typeof settingsBundle2 !== "object" || settingsBundle2.engineType === null || settingsBundle2.engineType === void 0 || settingsBundle2.engineSettings === null || settingsBundle2.engineSettings === void 0) {
        console().warn(
          "saver returned an incomplete bundle for",
          desktopIdStr,
          "- keeping current settings"
        );
        return;
      }
      const display = controller().parseDisplay(desktopIdStr);
      if (display === void 0) return;
      const driver = controller().getDriver(display);
      if (driver !== void 0) {
        // Only Custom can be a return target; older bundles may still name a
        // removed engine here.
        const last = settingsBundle2.lastEngine;
        driver.lastEngine =
          typeof last === "number" && last !== KWIN_ENGINE_TYPE
            ? CUSTOM_ENGINE_TYPE
            : null;
        // Restore the Custom settings that were active before KWin took over.
        // Set this before the changeEngine event so setEngineType() does not
        // replace it with the freshly constructed default settings.
        if (settingsBundle2.engineType === KWIN_ENGINE_TYPE && settingsBundle2.lastEngineSettings !== null && typeof settingsBundle2.lastEngineSettings === "object") {
          driver.lastEngineSettings = settingsBundle2.lastEngineSettings;
        }
      }
      controller().queueEvent(
        {
          t: "changeEngine",
          display,
          engineType: settingsBundle2.engineType,
          engineSettings: settingsBundle2.engineSettings,
          noDBusUpdate: true
        },
        true
      );
    } catch (e) {
      console().error(e);
    }
  }
  setSettings(display, engineType, engineSettings, lastEngine, lastEngineSettings) {
    console().debug("setSettings called");
    this.dbusQml.setSettings().arguments = [
      display.toString(),
      settingsBundle(engineType, engineSettings, lastEngine, lastEngineSettings)
    ];
    this.dbusQml.setSettings().call();
  }
  resetSettings(display) {
    console().debug("resetSettings called");
    this.dbusQml.resetSettings().arguments = [display.toString()];
    this.dbusQml.resetSettings().call();
  }
  // Volatile layout/monocle state for the overview effect.
  setState(display, stateJson) {
    this.dbusQml.setState().arguments = [display.toString(), stateJson];
    this.dbusQml.setState().call();
  }
  // Script-wide options live in kwinrc, which the script itself cannot write,
  // so the saver writes the file for us on the rare occasion one changes.
  setGlobalSetting(key, value) {
    console().debug("setGlobalSetting called -", key, value);
    this.dbusQml.setGlobalSetting().arguments = [key, value];
    this.dbusQml.setGlobalSetting().call();
  }
};

// src/controller/console.ts
var Console = class {
  constructor(console2) {
    this.console = console2;
  }
  debug(...args) {
    if (config().logLevel < 3 /* Debug */) return;
    this.console.info("Folonium DBG:", ...args);
  }
  log(...args) {
    if (config().logLevel < 2 /* Log */) return;
    this.console.info("Folonium LOG:", ...args);
  }
  warn(...args) {
    if (config().logLevel < 1 /* Warn */) return;
    this.console.warn("Folonium WRN:", ...args);
  }
  error(...args) {
    this.console.error("Folonium ERR:", ...args);
  }
};

// src/driver/buildlayout.ts
function buildLayout(kwinRootTile, engineRootTile) {
  const tileMap = /* @__PURE__ */ new Map();
  const queue = new Queue();
  queue.push([kwinRootTile, engineRootTile]);
  while (!queue.isEmpty) {
    const [kwinTile, engineTile] = queue.pop();
    if (kwinTile == null) {
      console().warn("kwin tile is null");
      continue;
    }
    tileMap.set(kwinTile, engineTile);
    if (kwinTile.layoutDirection !== engineTile.layoutDirection) {
      while (kwinTile.tiles.length > 0) {
        kwinTile.tiles[kwinTile.tiles.length - 1].remove();
      }
      kwinTile.layoutDirection = engineTile.layoutDirection;
    }
    console().debug("kwin children", kwinTile.tiles.length);
    console().debug("engine children", engineTile.children.length);
    if (engineTile.children.length == 1) {
      console().warn(
        "engine tile at",
        kwinTile.absoluteGeometry,
        "has only one child"
      );
      while (kwinTile.tiles.length > 0) {
        kwinTile.tiles[kwinTile.tiles.length - 1].remove();
      }
      queue.push([kwinTile, engineTile.children[0]]);
    } else if (childrenAreSame(kwinTile, engineTile)) {
      // Re-setting identical geometry makes KWin jitter and emits another
      // relativeGeometryChanged, so skip it when nothing actually changed.
      console().debug("skipping resize for this tile as it is unchanged");
    } else {
      matchChildren(kwinTile, engineTile);
    }
    if (engineTile.children.length > 1) {
      for (let i = 0; i < engineTile.children.length; i += 1) {
        queue.push([kwinTile.tiles[i], engineTile.children[i]]);
      }
    }
  }
  return tileMap;
}
// True when KWin's children already have exactly the proportions the engine
// is about to ask for.
function childrenAreSame(kwinTile, engineTile) {
  if (kwinTile.tiles.length != engineTile.children.length) {
    return false;
  }
  const totalChildrenSize = engineTile.totalChildrenSize();
  const layoutDirection = kwinTile.layoutDirection;
  for (let i = 0; i < kwinTile.tiles.length; i += 1) {
    const kwinChild = kwinTile.tiles[i];
    const engineChildSize = engineTile.children[i].size / totalChildrenSize;
    let relativeSize = 1;
    if (layoutDirection === 1 /* Horizontal */) {
      relativeSize = kwinChild.relativeGeometry.width / kwinTile.relativeGeometry.width;
    } else if (layoutDirection === 2 /* Vertical */) {
      relativeSize = kwinChild.relativeGeometry.height / kwinTile.relativeGeometry.height;
    }
    if (!(Math.abs(relativeSize - engineChildSize) <= 1e-5)) {
      return false;
    }
  }
  return true;
}
function matchChildren(kwinTile, engineTile) {
  const layoutDirection = engineTile.layoutDirection;
  while (kwinTile.tiles.length > engineTile.children.length) {
    kwinTile.tiles[kwinTile.tiles.length - 1].remove();
  }
  if (engineTile.children.length === 0) return;
  for (let i = 0; i < kwinTile.tiles.length - 1; i += 1) {
    setChildMinSize(kwinTile, i);
  }
  while (kwinTile.tiles.length < engineTile.children.length) {
    if (kwinTile.tiles.length == 0) {
      kwinTile.split(layoutDirection);
      setChildMinSize(kwinTile, 0);
    } else {
      kwinTile.tiles[kwinTile.tiles.length - 1].split(layoutDirection);
      setChildMinSize(kwinTile, kwinTile.tiles.length - 2);
    }
  }
  for (let i = kwinTile.tiles.length - 1; i >= 0; i -= 1) {
    setChildRelativeSize(kwinTile, engineTile, i);
  }
}
function setChildMinSize(kwinTile, index) {
  const minSize = MIN_CHILD_FRACTION;
  console().debug("setMinChildSize on idx", index);
  const kwinChild = kwinTile.tiles[index];
  const parentGeom = kwinTile.relativeGeometry;
  console().debug("previous dimensions", kwinChild.relativeGeometry);
  const geom = qt().rect(
    parentGeom.x,
    parentGeom.y,
    parentGeom.width,
    parentGeom.height
  );
  if (kwinTile.layoutDirection === 1 /* Horizontal */) {
    geom.width *= minSize;
    geom.x += geom.width * index;
  } else if (kwinTile.layoutDirection === 2 /* Vertical */) {
    geom.height *= minSize;
    geom.y += geom.height * index;
  }
  console().debug("target dimensions", geom);
  kwinChild.relativeGeometry = geom;
  console().debug("new dimensions", kwinChild.relativeGeometry);
}
function setChildRelativeSize(kwinTile, engineTile, index) {
  console().debug("setChildRelativeSize on idx", index);
  const totalSize = engineTile.totalChildrenSize();
  const kwinChild = kwinTile.tiles[index];
  const engineChild = engineTile.children[index];
  console().debug("target size -", engineChild.size);
  const oldGeom = kwinChild.relativeGeometry;
  console().debug("previous dimensions -", oldGeom);
  const geom = qt().rect(
    kwinTile.relativeGeometry.x,
    kwinTile.relativeGeometry.y,
    kwinTile.relativeGeometry.width,
    kwinTile.relativeGeometry.height
  );
  if (engineTile.layoutDirection === 1 /* Horizontal */) {
    geom.width *= engineChild.size / totalSize;
    let previousChildrenSize = 0;
    for (let i = 0; i < index; i += 1) {
      previousChildrenSize += engineTile.children[i].size;
    }
    previousChildrenSize /= totalSize;
    previousChildrenSize *= kwinTile.relativeGeometry.width;
    geom.x += previousChildrenSize;
  } else if (engineTile.layoutDirection === 2 /* Vertical */) {
    geom.height *= engineChild.size / totalSize;
    let previousChildrenSize = 0;
    for (let i = 0; i < index; i += 1) {
      previousChildrenSize += engineTile.children[i].size;
    }
    previousChildrenSize /= totalSize;
    previousChildrenSize *= kwinTile.relativeGeometry.height;
    geom.y += previousChildrenSize;
  }
  console().debug("target dimensions -", geom);
  kwinChild.relativeGeometry = geom;
  console().debug("final dimensions -", kwinChild.relativeGeometry);
}

// src/driver/updatetiles.ts
function updateTiles(rootTile, tileMap) {
  // The root may sit at the top of a single-child chain (buildLayout ties such
  // a chain to one KWin tile); any tile in the chain maps to the KWin root.
  const rootChain = /* @__PURE__ */ new Set([rootTile]);
  for (let t = rootTile; t.children.length == 1; t = t.children[0]) {
    rootChain.add(t.children[0]);
  }
  let kwinRootTile = null;
  for (const [kwinTile, engineTile] of tileMap) {
    if (!rootChain.has(engineTile)) {
      continue;
    }
    kwinRootTile = kwinTile;
    break;
  }
  if (kwinRootTile == null) {
    return rootTile;
  }
  const queue = new Queue();
  queue.push([kwinRootTile, rootTile]);
  while (!queue.isEmpty) {
    const [kwinTile, engineTile] = queue.pop();
    engineTile.layoutDirection = kwinTile.layoutDirection;
    let relativeSize = 1;
    if (kwinTile.parent != null) {
      const parent = kwinTile.parent;
      const direction = parent.layoutDirection;
      if (direction === 1 /* Horizontal */) {
        relativeSize = kwinTile.relativeGeometry.width / parent.relativeGeometry.width;
      } else if (direction === 2 /* Vertical */) {
        relativeSize = kwinTile.relativeGeometry.height / parent.relativeGeometry.height;
      } else {
        relativeSize /= parent.tiles.length;
      }
      relativeSize *= parent.tiles.length;
    }
    engineTile.size = relativeSize;
    // buildLayout may tie a single-child engine tile to the same KWin tile.
    // Follow that chain down to the tile whose children match KWin's.
    let innerTile = engineTile;
    while (innerTile.children.length == 1) {
      innerTile = innerTile.children[0];
    }
    innerTile.layoutDirection = kwinTile.layoutDirection;
    // Pair children through the tile map, not by index: a tile added or
    // removed in KWin must not shift sizes onto the wrong engine branch.
    const engineChildren = [];
    for (const kwinChild of kwinTile.tiles) {
      const engineChild = getEngineChild(kwinChild, innerTile, tileMap);
      engineChildren.push(engineChild);
      queue.push([kwinChild, engineChild]);
    }
    innerTile.children = engineChildren;
  }
  return rootTile;
}
function getEngineChild(kwinChild, engineTile, tileMap) {
  let engineChild = tileMap.get(kwinChild);
  if (engineChild === void 0) {
    engineChild = new Tile(engineTile);
    tileMap.set(kwinChild, engineChild);
    return engineChild;
  }
  // The map points at the innermost tile of a single-child chain; walk back up
  // to the tile that is actually a child of this engine tile.
  while (engineChild.parent !== engineTile && engineChild.parent !== null && engineChild.parent.children.length == 1) {
    engineChild = engineChild.parent;
  }
  engineChild.parent = engineTile;
  return engineChild;
}

// src/driver/index.ts
var Driver = class {
  constructor(engineType, engineSettings) {
    // Filled in by the controller. Used to reconcile a window against every
    // driver without having to regenerate displays from the current workspace.
    this.display = null;
    this.engineRootTile = null;
    this.kwinRootTile = null;
    this.tileMap = /* @__PURE__ */ new Map();
    this.hookedTiles = /* @__PURE__ */ new Set();
    this.windowMap = /* @__PURE__ */ new Map();
    // The tiling engine to return to when KWin's untiled mode is toggled off,
    // and its per-display settings so the switch back is lossless.
    this.lastEngine = null;
    this.lastEngineSettings = null;
    this.invertedWindowMap = /* @__PURE__ */ new Map();
    this.untiledWindows = /* @__PURE__ */ new Set();
    // Tiled windows the user is dragging in place. The engine keeps their
    // slot, so the rest of the layout does not retile for one fewer window.
    this.draggingWindows = /* @__PURE__ */ new Set();
    this.savedActiveWindow = null;
    if (engineSettings === void 0) {
      engineSettings = getConfigEngineSettings(engineType);
    }
    this.tilingEngine = new TilingEngine(engineType, engineSettings);
    // What the per-display store was last told. Variant cycles and divider
    // changes mutate the engine in place, so the controller compares against
    // this rather than against the value from just before an event.
    this.lastSavedEngineType = this.tilingEngine.engineType;
    this.lastSavedSettings = JSON.stringify(this.tilingEngine.getEngineSettings());
  }
  setEngineType(engineType, engineSettings) {
    // KWin's own tiling is the only alternative to the Custom engine now. Old
    // saved engine numbers resolve to Custom inside TilingEngine.
    if (engineType === KWIN_ENGINE_TYPE) {
      // Keep the Custom settings around so toggling back is lossless. If the
      // saver already restored them from disk, do not overwrite that with the
      // freshly constructed defaults.
      if (this.tilingEngine.engineType !== KWIN_ENGINE_TYPE && this.lastEngineSettings === null) {
        this.lastEngineSettings = this.tilingEngine.getEngineSettings();
      }
    } else {
      if (this.lastEngineSettings !== null) {
        engineSettings = this.lastEngineSettings;
        this.lastEngineSettings = null;
      }
      this.lastEngine = CUSTOM_ENGINE_TYPE;
    }
    // KWin leaves most windows untiled, so leaving it has to retile every
    // window. In every other case a window the user floated stays floated
    // when only a setting changes.
    const retileAll = this.tilingEngine.engineType === KWIN_ENGINE_TYPE;
    this.tilingEngine = new TilingEngine(engineType, engineSettings);
    for (const [kwinWindow, engineWindow] of this.windowMap) {
      if (engineType === KWIN_ENGINE_TYPE) {
        // Hand every window back to KWin exactly once. After this Folonium
        // never manages, tiles or resizes anything on this display.
        this.untiledWindows.add(kwinWindow);
        releaseWindowTile(kwinWindow);
        setUntiledProps(kwinWindow);
        continue;
      }
      if (!retileAll && this.untiledWindows.has(kwinWindow)) {
        continue;
      }
      this.untiledWindows.delete(kwinWindow);
      this.tilingEngine.addWindow(engineWindow);
    }
    this.draggingWindows.clear();
  }
  // Swaps between KWin's untiled mode and the Custom engine.
  toggleKwinEngine() {
    const current = this.tilingEngine.engineType;
    if (current === KWIN_ENGINE_TYPE) {
      const back = this.lastEngine ?? CUSTOM_ENGINE_TYPE;
      const engineType = back === KWIN_ENGINE_TYPE ? CUSTOM_ENGINE_TYPE : back;
      this.setEngineType(engineType, getConfigEngineSettings(engineType));
      return true;
    }
    this.setEngineType(KWIN_ENGINE_TYPE, {});
    return true;
  }
  changeTilingEngine(engineType, engineSettings) {
    if (engineType !== void 0 && this.tilingEngine.engineType != engineType) {
      if (engineSettings === void 0) {
        engineSettings = getConfigEngineSettings(engineType);
      }
      this.setEngineType(engineType, engineSettings);
    } else if (engineSettings !== void 0) {
      this.tilingEngine.setEngineSettings(engineSettings);
    }
  }
  hasWindow(kwinWindow) {
    return this.windowMap.has(kwinWindow);
  }
  hasTile(kwinTile) {
    return this.tileMap.has(kwinTile);
  }
  getKwinRootTile() {
    if (this.kwinRootTile !== null && this.tileMap.has(this.kwinRootTile)) {
      return this.kwinRootTile;
    }
    for (const [kwinTile, engineTile] of this.tileMap) {
      if (engineTile === this.engineRootTile) {
        this.kwinRootTile = kwinTile;
        return kwinTile;
      }
    }
    return null;
  }
  getEngineType() {
    return this.tilingEngine.engineType;
  }
  getEngineSettings() {
    return this.tilingEngine.getEngineSettings();
  }
  isWindowTiled(kwinWindow) {
    if (!this.windowMap.has(kwinWindow)) {
      return void 0;
    }
    // Folonium does not track tiling while KWin owns the layout.
    if (this.tilingEngine.engineType === KWIN_ENGINE_TYPE) {
      return void 0;
    }
    // With the Custom engine a window can be tracked but have no leaf when the
    // selected set has fewer slots than open windows. Only a real tile counts.
    if (this.tilingEngine.engineType === CUSTOM_ENGINE_TYPE) {
      const engineWindow = this.windowMap.get(kwinWindow);
      // TilingEngine wraps the actual engine; windowTiles lives on that engine,
      // not on the wrapper. Reading the missing property made every drag and
      // maximize handler throw before it could update Folonium's state.
      return engineWindow !== void 0 && this.tilingEngine.hasWindowTile(engineWindow);
    }
    return !this.untiledWindows.has(kwinWindow);
  }
  isWindowDragging(kwinWindow) {
    return this.draggingWindows.has(kwinWindow);
  }
  setWindowDragging(kwinWindow, dragging) {
    if (dragging) {
      this.draggingWindows.add(kwinWindow);
    } else {
      this.draggingWindows.delete(kwinWindow);
    }
  }
  isMonocle() {
    return this.tilingEngine.engineType === CUSTOM_ENGINE_TYPE && this.getEngineSettings().monocle === true;
  }
  // KWin windows in engine order, which is the order the layout uses.
  windowOrder() {
    const windows = this.tilingEngine.engine?.windows;
    if (!Array.isArray(windows)) {
      return [];
    }
    const out = [];
    for (const engineWindow of windows) {
      const kwinWindow = this.invertedWindowMap.get(engineWindow);
      if (kwinWindow !== void 0) {
        out.push(kwinWindow);
      }
    }
    return out;
  }
  stateJson() {
    return JSON.stringify({
      layout: this.shapeText(),
      mono: this.isMonocle(),
      shape: this.tiledShapeText()
    });
  }
  resetTilingEngine() {
    const defaultSettings = getConfigEngineSettings(CUSTOM_ENGINE_TYPE);
    this.lastEngineSettings = null;
    if (this.tilingEngine.engineType !== CUSTOM_ENGINE_TYPE) {
      this.setEngineType(CUSTOM_ENGINE_TYPE, defaultSettings);
    } else {
      this.tilingEngine.setEngineSettings(defaultSettings);
    }
    // Dragged proportions live in the engine's per-layout cache, not in the
    // saved settings, so a reset has to drop them explicitly.
    this.tilingEngine.resetLayoutSizes();
  }
  buildLayout(rootTile, display) {
    for (const [kwinWindow, _ew] of this.windowMap) {
      if (!controller().windowExists(kwinWindow) || !display.containsWindow(kwinWindow)) {
        console().warn("invalid window in windowMap");
        this.removeWindow(kwinWindow);
      }
    }
    if (this.tilingEngine.engineType === KWIN_ENGINE_TYPE) {
      // KWin owns the tile tree here. Touching it every rebuild is what made a
      // drag alternate between the tiled and the natural size.
      this.tileMap.clear();
      this.kwinRootTile = null;
      this.engineRootTile = null;
      this.draggingWindows.clear();
      return;
    }
    this.engineRootTile = this.tilingEngine.buildLayout();
    this.tileMap = buildLayout(rootTile, this.engineRootTile);
    this.kwinRootTile = rootTile;
    for (const hookedTile of this.hookedTiles) {
      if (!this.tileMap.has(hookedTile)) {
        this.hookedTiles.delete(hookedTile);
      }
    }
    const invertedWindowMap = new Map(
      Array.from(this.windowMap, (a) => [a[1], a[0]])
    );
    this.invertedWindowMap = invertedWindowMap;
    const tiledWindows = /* @__PURE__ */ new Set();
    for (const [kwinTile, engineTile] of this.tileMap) {
      if (!this.hookedTiles.has(kwinTile)) {
        kwinTile.relativeGeometryChanged.connect(
          this.updateTileSizesCallback.bind(this, display)
        );
        kwinTile.childTilesChanged.connect(
          this.updateTileCountCallback.bind(this, display)
        );
        this.hookedTiles.add(kwinTile);
      }
      for (const engineWindow of engineTile.windows) {
        const kwinWindow = invertedWindowMap.get(engineWindow);
        if (kwinWindow === void 0) {
          continue;
        }
        // A window being dragged keeps its leaf and its neighbours' tiles; it
        // is just not re-managed until the drop decides where it belongs.
        if (this.draggingWindows.has(kwinWindow)) {
          tiledWindows.add(kwinWindow);
          continue;
        }
        console().debug(
          "setting",
          kwinWindow.resourceClass,
          "as tiled"
        );
        if (this.untiledWindows.has(kwinWindow)) {
          this.untiledWindows.delete(kwinWindow);
        }
        // A maximized, fullscreen or minimized window keeps its slot but KWin
        // owns its current geometry. Touching it here would unmaximize it or
        // pull it out of fullscreen on the next unrelated rebuild.
        const handler = controller().getWindowHandler(kwinWindow);
        if (handler !== void 0 && !handler.canBeTiled()) {
          tiledWindows.add(kwinWindow);
          continue;
        }
        setTiledProps(kwinWindow);
        if (kwinWindow.tile !== kwinTile) kwinTile.manage(kwinWindow);
        tiledWindows.add(kwinWindow);
      }
    }
    for (const kwinWindow of this.windowMap.keys()) {
      if (!tiledWindows.has(kwinWindow)) {
        console().debug(
          "setting",
          kwinWindow.resourceClass,
          "as untiled"
        );
        this.untiledWindows.add(kwinWindow);
        // The old tile is often no longer in the freshly built tileMap, so a
        // membership test here left stale KWin tile pointers behind.
        releaseWindowTile(kwinWindow);
        setUntiledProps(kwinWindow);
      }
    }
  }
  // Rebuilds the engine's own state without touching KWin. This is what a
  // display on another activity needs: tiles are shared between activities, so
  // the driver must not rearrange them, but it still has to know which of its
  // windows are tiled when the user switches back.
  buildState(display) {
    for (const [kwinWindow, _ew] of this.windowMap) {
      if (!controller().windowExists(kwinWindow) || !display.containsWindow(kwinWindow)) {
        console().warn("invalid window in windowMap");
        this.removeWindow(kwinWindow);
      }
    }
    this.tileMap.clear();
    this.kwinRootTile = null;
    this.engineRootTile = null;
    const engineRootTile = this.tilingEngine.buildLayout();
    this.engineRootTile = engineRootTile;
    const invertedWindowMap = new Map(
      Array.from(this.windowMap, (a) => [a[1], a[0]])
    );
    const tiledWindows = /* @__PURE__ */ new Set();
    const stack = [engineRootTile];
    while (stack.length > 0) {
      const engineTile = stack.pop();
      for (const engineWindow of engineTile.windows) {
        const kwinWindow = invertedWindowMap.get(engineWindow);
        if (kwinWindow === void 0) {
          continue;
        }
        if (this.untiledWindows.has(kwinWindow)) {
          this.untiledWindows.delete(kwinWindow);
        }
        tiledWindows.add(kwinWindow);
      }
      stack.push(...engineTile.children);
    }
    for (const kwinWindow of this.windowMap.keys()) {
      if (!tiledWindows.has(kwinWindow)) {
        this.untiledWindows.add(kwinWindow);
      }
    }
  }
  initializeWindow(kwinWindow) {
    if (this.windowMap.has(kwinWindow)) {
      return this.windowMap.get(kwinWindow);
    }
    const engineWindow = new Window(
      kwinWindow.internalId,
      kwinWindow.caption,
      kwinWindow.minSize
    );
    this.windowMap.set(kwinWindow, engineWindow);
    return engineWindow;
  }
  addWindow(kwinWindow, tile, direction) {
    if (this.windowMap.has(kwinWindow)) {
      console().warn(
        "initializeWindow error - window already exists in map"
      );
      return;
    }
    const window = this.initializeWindow(kwinWindow);
    this.tilingEngine.addWindow(
      window,
      tile ? this.tileMap.get(tile) : void 0,
      direction
    );
    if (this.savedActiveWindow === kwinWindow) {
      this.tilingEngine.windowActivated(window);
    }
  }
  addWindowUntiled(kwinWindow) {
    if (this.windowMap.has(kwinWindow)) {
      console().warn(
        "initializeWindow error - window already exists in map"
      );
      return;
    }
    this.initializeWindow(kwinWindow);
    // Mark it straight away so isWindowTiled() is correct before the rebuild.
    this.untiledWindows.add(kwinWindow);
  }
  tileWindow(kwinWindow) {
    const window = this.windowMap.get(kwinWindow);
    if (window === void 0) {
      console().warn("tileWindow error - window not found in map");
      return;
    }
    if (!this.tilingEngine.hasWindow(window)) {
      if (this.isFull()) {
        return;
      }
      this.tilingEngine.addWindow(window);
    }
    this.untiledWindows.delete(kwinWindow);
    if (this.savedActiveWindow === kwinWindow) {
      this.tilingEngine.windowActivated(window);
    }
  }
  untileWindow(kwinWindow) {
    const window = this.windowMap.get(kwinWindow);
    if (window === void 0) {
      console().warn("untileWindow error - window not found in map");
      return;
    }
    this.tilingEngine.removeWindow(window);
    this.untiledWindows.add(kwinWindow);
    try {
      releaseWindowTile(kwinWindow);
      setUntiledProps(kwinWindow);
    } catch (e) {
      console().debug("could not restore properties on untiled window", e);
    }
  }
  placeWindow(kwinWindow, kwinTile, direction) {
    let window = this.initializeWindow(kwinWindow);
    const tile = this.tileMap.get(kwinTile);
    if (tile == void 0) {
      console().warn("tile undefined during window placement");
      this.tilingEngine.addWindow(window);
      return;
    }
    this.tilingEngine.placeWindow(window, tile, direction);
    if (this.savedActiveWindow === kwinWindow) {
      this.tilingEngine.windowActivated(window);
    }
  }
  windowActivated(kwinWindow) {
    this.savedActiveWindow = kwinWindow;
    const engineWindow = this.windowMap.get(kwinWindow);
    if (engineWindow === void 0) {
      return false;
    }
    return this.tilingEngine.windowActivated(engineWindow);
  }
  removeWindow(kwinWindow) {
    const wasUntiled = this.untiledWindows.delete(kwinWindow);
    this.draggingWindows.delete(kwinWindow);
    const engineWindow = this.windowMap.get(kwinWindow);
    if (engineWindow === void 0) {
      console().warn(
        "Window",
        kwinWindow?.resourceClass,
        "not registered in windowMap"
      );
      return;
    }
    // Drop the engine/map entry before touching the KWin window. During
    // windowRemoved the properties can already be invalid; a throw there must
    // not leave the closed window counted in the layout.
    this.tilingEngine.removeWindow(engineWindow);
    this.windowMap.delete(kwinWindow);
    if (wasUntiled) {
      return;
    }
    try {
      if (controller().windowExists(kwinWindow)) {
        setUntiledProps(kwinWindow);
        releaseWindowTile(kwinWindow);
      }
    } catch (e) {
      console().debug("could not restore properties on removed window", e);
    }
  }
  // as of right now, can only update sizes (ie cannot add/remove tiles)
  rotateWindows(backwards) {
    return this.tilingEngine.rotateWindows(backwards);
  }
  cycleVariant(backwards) {
    return this.tilingEngine.cycleVariant(backwards);
  }
  cycleHorizontalRatio(backwards) {
    return this.tilingEngine.cycleHorizontalRatio(backwards);
  }
  cycleVerticalRatio(backwards) {
    return this.tilingEngine.cycleVerticalRatio(backwards);
  }
  ratioInfo() {
    return this.tilingEngine.ratioInfo();
  }
  windowCount() {
    // Prefer the tiled count so floating/disowned windows do not inflate
    // the popup or settings counts.
    const eng = this.tilingEngine;
    const base = eng.windowCount();
    if (eng.engine && eng.engine.windowTiles instanceof Map) {
      const size = eng.engine.windowTiles.size;
      if (size > 0) return size;
    }
    return base;
  }
  shapeText() {
    return this.tilingEngine.shapeText();
  }
  tiledShapeText() {
    return this.tilingEngine.tiledShapeText();
  }
  layoutCount() {
    return this.tilingEngine.layoutCount();
  }
  layoutIndex() {
    return this.tilingEngine.layoutIndex();
  }
  usingCustomLayout() {
    return this.tilingEngine.usingCustomLayout();
  }
  customLayoutSets() {
    return this.tilingEngine.customLayoutSets();
  }
  isFull() {
    return this.tilingEngine.isFull();
  }
  updateTiles() {
    if (this.engineRootTile === null) {
      console().warn("updateTiles called, but engine layout not built");
      return;
    }
    const tile = updateTiles(this.engineRootTile, this.tileMap);
    this.tilingEngine.updateTiles(tile);
  }
  updateTileSizesCallback(display) {
    controller().queueEvent({
      t: "updateTiles",
      display,
      rebuild: false
    });
  }
  // when updating tile count we want to rebuild as for most engines this is an error
  // for kwin this is fine though
  updateTileCountCallback(display) {
    controller().queueEvent({
      t: "updateTiles",
      display,
      rebuild: true
    });
  }
};
function getConfigEngineSettings(engineType) {
  if (engineType === KWIN_ENGINE_TYPE) {
    return {};
  }
  // Custom is the only Folonium layout engine; anything saved by a removed
  // engine resolves to its defaults rather than failing to load.
  const settings = Object.assign({}, config().customSettings);
  settings.customLayouts = Object.assign(
    {},
    config().customSettings.customLayouts ?? {}
  );
  return settings;
}
function kwinClassOf(window) {
  const rc = window.resourceClass;
  return rc == null || rc === "" ? "window" : rc;
}
// Windows that Folonium must not track at all. In particular, context menus
// and other popups used to be registered as floating windows even though they
// can never be tiled, and every rebuild that followed could disturb the real
// tiled windows underneath them.
function isTrackableWindow(window) {
  if (window === null || window === void 0) {
    return false;
  }
  if (!window.normalWindow || window.specialWindow || window.skipTaskbar || window.onScreenDisplay || window.pid < 0) {
    return false;
  }
  // A fixed-size window cannot fill a tile. Chromium's screen-share indicator
  // is a normal, non-transient 456x62 window; tiling it squeezed the real
  // window beside it instead of leaving the indicator floating.
  if (window.resizeable === false) {
    return false;
  }
  if (!config().tilePopups && (window.popupWindow || window.transient || window.modal)) {
    return false;
  }
  return true;
}
// KWin keeps its own tile pointer on a window independently of Folonium's
// engine. Releasing it whenever the engine stops tiling a window prevents the
// window from floating on screen while KWin still treats it as part of a tile.
function releaseWindowTile(window) {
  if (window.tile == null) {
    return;
  }
  try {
    window.tile.unmanage(window);
  } catch (e) {
    console().debug("could not release window tile", e);
  }
}
function setTiledProps(window) {
  if (config().tiledWindowsBelow) {
    window.keepBelow = true;
  }
  if (config().borders === 1 /* Floating */ || config().borders === 0 /* None */ || (config().borders === 2 /* Active */ || config().borders === 3 /* FloatingActive */) && !window.active) {
    window.noBorder = true;
  }
  window.setMaximize(false, false);
}
function setUntiledProps(window) {
  if (config().tiledWindowsBelow) {
    window.keepBelow = false;
  }
  if (config().borders === 1 /* Floating */ || config().borders === 3 /* FloatingActive */) {
    window.noBorder = false;
  }
}

// src/controller/index.ts
var Controller = class {
  constructor(qmlApi, qmlObjects) {
    this.eventQueue = new Queue();
    this.postEventQueue = new Queue();
    this.processingEvents = false;
    this.drivers = /* @__PURE__ */ new Map();
    this.windowHandlers = /* @__PURE__ */ new Map();
    this.previousDisplays = /* @__PURE__ */ new Map();
    this.dbusHandler = null;
    this.mffHandler = null;
    this.workspace = qmlApi.workspace;
    this.qmlObjects = qmlObjects;
    this.eventTimer = this.qmlObjects.eventTimer;
    this.eventTimer.interval = config().rebuildDelay;
    this.eventTimer.repeat = false;
    this.eventTimer.triggered.connect(this.processEvents.bind(this));
    if (config().useDBusSaver) {
      this.dbusHandler = new DBusHandler(this.qmlObjects.dbus);
    }
    this.requestTimer = this.qmlObjects.requestTimer;
    this.requestTimer.interval = 500;
    this.requestTimer.triggered.connect(this.pollRequest.bind(this));
    if (config().mouseFollowsFocus) {
      this.mffHandler = new MouseFollowsFocusHandler(
        this.workspace,
        this.qmlObjects.mffTimer,
        this.qmlObjects.dbus
      );
    }
    this.settingsHandler = new SettingsHandler(this.qmlObjects.settings);
    this.workspaceHandler = new WorkspaceHandler(this.workspace);
    this.shortcutsHandler = new ShortcutsHandler(
      this.workspace,
      this.qmlObjects.shortcuts
    );
    this.updateDrivers();
  }
  // The popup button and the shortcut land here: hand this display's tiling to
  // KWin, or take it back from KWin.
  toggleKwinEngine() {
    const display = new Display(
      this.workspace.currentDesktop,
      this.workspace.currentActivity,
      this.workspace.activeScreen
    );
    const driver = this.getDriver(display);
    if (driver === void 0) {
      return;
    }
    driver.toggleKwinEngine();
    // This is an engine change, not a resize: persist it immediately so a
    // restart comes back on the same side of the toggle.
    this.dbusHandler?.setSettings(
      display,
      driver.getEngineType(),
      driver.getEngineSettings(),
      driver.lastEngine,
      driver.lastEngineSettings
    );
    driver.lastSavedEngineType = driver.getEngineType();
    driver.lastSavedSettings = JSON.stringify(driver.getEngineSettings());
    this.queueEvent({ t: "updateTiles", display, rebuild: true });
  }
  // The popup's shape buttons share the shortcut implementations, which already
  // resolve the active display and queue the rebuild.
  cycleVariant(backwards) {
    this.shortcutsHandler.cycleVariant(backwards === true);
  }
  cycleHorizontalRatio(backwards) {
    this.shortcutsHandler.cycleHorizontalRatio(backwards === true);
  }
  cycleVerticalRatio(backwards) {
    this.shortcutsHandler.cycleVerticalRatio(backwards === true);
  }
  refreshSettings() {
    if (!this.settingsHandler.isVisible()) {
      return;
    }
    const display = this.settingsHandler.display;
    if (display === null || display === void 0) {
      return;
    }
    const driver = this.getDriver(display);
    if (driver === void 0) {
      return;
    }
    this.settingsHandler.show(
      display,
      driver.getEngineType(),
      driver.getEngineSettings(),
      driver.windowCount(),
      driver.layoutCount(),
      driver.shapeText(),
      driver.layoutIndex(),
      driver.usingCustomLayout(),
      driver.customLayoutSets(),
      driver.ratioInfo()
    );
  }
  // The popup picks one of the KCM tabs. L1 is the default; an empty tab leaves
  // windows floating instead of falling back to generated layouts.
  selectCustomLayoutTab(display, tabIndex) {
    const driver = this.getDriver(display);
    if (driver === void 0) {
      return;
    }
    const tab = Number.isInteger(tabIndex) ? tabIndex : 0;
    if (!driver.customLayoutSets().some((set) => set.index === tab)) {
      return;
    }
    this.queueEvent({
      t: "changeEngine",
      display,
      engineSettings: { customLayoutTab: tab, customLayouts: {} }
    });
  }
  rotateWindows(backwards) {
    this.shortcutsHandler.rotateWindows(backwards === true);
  }
  // The overview effect lives in the effect engine and cannot touch this
  // script, so it round-trips its window commands through the saver.
  pollRequest() {
    this.dbusHandler?.takeRequest();
  }
  handleRequest(request) {
    if (request.t === "swap") {
      const windows = this.workspace.stackingOrder;
      const a = windows.find((w) => String(w.internalId) === request.a);
      const b = windows.find((w) => String(w.internalId) === request.b);
      if (a === void 0 || b === void 0 || a === b) return;
      // Different desktops: exchange the windows instead of the slots.
      const aDesktop = a.desktops[0];
      const bDesktop = b.desktops[0];
      if (aDesktop === void 0 || bDesktop === void 0) return;
      if (aDesktop !== bDesktop) {
        a.desktops = [bDesktop];
        b.desktops = [aDesktop];
        return;
      }
      const tile = b.tile;
      if (tile === null) return;
      this.queueEvent({ t: "placeWindow", window: a, tile });
      return;
    }
    // The overview cannot move the real pointer, so focus the window it was
    // asked for and let KWin's MoveMouseToFocus shortcut centre the cursor on
    // it. Runs after the effect closed because the saver is polled.
    if (request.t === "warp") {
      const target = this.workspace.stackingOrder.find(
        (w) => String(w.internalId) === request.id
      );
      if (target === undefined) return;
      if (target.minimized) target.minimized = false;
      this.workspace.activeWindow = target;
      this.qmlObjects.dbus?.moveMouseToFocus().call();
      return;
    }
    // A monocle desktop is previewed with the tiled shape it would use, so the
    // user can see where windows would go. Picking one only focuses it: the
    // desktop stays in monocle, which then stacks it full size again.
    if (request.t === "tiled") {
      const target = this.workspace.stackingOrder.find(
        (w) => String(w.internalId) === request.id
      );
      if (target === undefined) return;
      if (target.minimized) target.minimized = false;
      this.workspace.activeWindow = target;
      this.qmlObjects.dbus?.moveMouseToFocus().call();
    }
  }
  queueEvent(ev, forcePush = false) {
    if (this.processingEvents && !forcePush) return;
    this.eventQueue.push(ev);
    if (this.eventTimer && typeof this.eventTimer.start === "function") this.eventTimer.start();
  }
  queuePostEvent(ev, forcePush = false) {
    if (this.processingEvents && !forcePush) return;
    this.postEventQueue.push(ev);
    if (this.eventTimer && typeof this.eventTimer.start === "function") this.eventTimer.start();
  }
  processEvents() {
    this.processingEvents = true;
    try {
      const queue = simplifyEvents(this.eventQueue);
      this.eventQueue = new Queue();
      console().debug("Handling", queue.size, "event(s)");
      const rebuildDisplays = /* @__PURE__ */ new Map();
      while (!queue.isEmpty) {
        const ev = queue.pop();
        if (ev === void 0) {
          break;
        }
        const displays = this.handleEvent(ev);
        for (const display of displays) {
          rebuildDisplays.set(display.toSymbol(), display);
        }
      }
      let rebuilt = false;
      if (rebuildDisplays.size > 0) {
        this.mffHandler?.beforeRebuild();
      }
      for (const [_, display] of rebuildDisplays) {
        if (display.desktop == void 0 || display.output == void 0) {
          continue;
        }
        console().debug("Rebuilding for display", display.toString());
        const driver = this.getDriver(display);
        if (driver == void 0) {
          console().error(
            "no driver found for display",
            display.toString()
          );
          continue;
        }
        if (display.activity !== this.workspace.currentActivity) {
          // Tiles are shared between activities, so do not touch KWin here.
          // Rebuilding the engine state keeps the driver consistent when the
          // user switches back to this activity.
          driver.buildState(display);
          this.dbusHandler?.setState(display, driver.stateJson());
          continue;
        }
        const rootTile = this.workspace.rootTile(
          display.output,
          display.desktop
        );
        if (rootTile != void 0) {
          driver.buildLayout(rootTile, display);
          this.dbusHandler?.setState(display, driver.stateJson());
          rebuilt = true;
        }
      }
      if (rebuildDisplays.size > 0) {
        this.mffHandler?.retiled();
      }
      // Refresh the popup from its own display. Rebuilding several displays
      // used to end with the popup showing whichever one happened to be last.
      if (rebuilt) {
        this.refreshSettings();
      }
      const postQueue = simplifyPostEvents(this.postEventQueue);
      this.postEventQueue = new Queue();
      console().debug("Handling", postQueue.size, "post event(s)");
      while (!postQueue.isEmpty) {
        const ev = postQueue.pop();
        if (ev === void 0) {
          break;
        }
        this.handlePostEvent(ev);
      }
    } catch (e) {
      // A single bad event must not leave processingEvents stuck at true for
      // the rest of the session (which used to drop every later event).
      console().error("ran into error during ev handling -", e);
    } finally {
      this.processingEvents = false;
    }
  }
  // returns a list of displays that need a rebuild
  // one event returning yes guarantees a rebuild
  // error handling - break in case statement to exit and log error message
  handleEvent(ev) {
    console().debug("handling event", ev.t);
    try {
      switch (ev.t) {
        case "newWindow":
          return this.evNewWindow(
            ev.window,
            ev.forceTile,
            ev.tile,
            ev.direction
          );
        case "deleteWindow":
          return this.evDeleteWindow(ev.window, ev.displays);
        case "updateWindow":
          return this.evUpdateWindow(ev.window);
        case "tileWindow":
          return this.evTileWindow(ev.window);
        case "untileWindow":
          return this.evUntileWindow(ev.window);
        case "placeWindow":
          return this.evPlaceWindow(ev.window, ev.tile, ev.direction);
        case "placeWindowPoint":
          return this.evPlaceWindowPoint(ev.window, ev.point);
        case "dragWindow":
          return this.evDragWindow(ev.window);
        case "windowActivated":
          return this.evWindowActivated(ev.window);
        case "updateDrivers":
          return this.updateDrivers();
        case "rebuildDisplays":
          return this.displaysToRebuild();
        case "updateTiles":
          return this.evUpdateTiles(ev.display, ev.rebuild);
        case "changeEngine":
          return this.evChangeEngine(
            ev.display,
            ev.engineType,
            ev.engineSettings,
            ev.noDBusUpdate
          );
        case "modifyEngineSetting":
          return this.evModifyEngineSetting(
            ev.display,
            ev.setting,
            ev.op,
            ev.amount,
            ev.min,
            ev.max
          );
        case "resetEngine":
          return this.evResetEngine(ev.display);
        default: {
          console().error("invalid event type", ev.t);
          return [];
        }
      }
    } catch (e) {
      console().error("event type", ev.t, "failed to execute");
      console().error("error message -", e.message);
    }
    return [];
  }
  // Optional placement for windows that start out floating. 1..9 are the
  // cells of a 3x3 grid over the window's output; 0 leaves it to KWin.
  placeFloatingWindow(window, output) {
    const spot = config().floatingSpawnPoint;
    if (!(spot >= 1 && spot <= 9) || output === null || output === void 0) {
      return;
    }
    if (window.fullScreen || window.minimized || window.maximizeMode !== 0) {
      return;
    }
    const area = output.geometry;
    if (area === null || area === void 0) {
      return;
    }
    const frame = window.frameGeometry;
    const width = frame.width;
    const height = frame.height;
    const col = (spot - 1) % 3;
    const row = Math.floor((spot - 1) / 3);
    let x = area.x;
    let y = area.y;
    if (col === 1) {
      x = area.x + Math.round((area.width - width) / 2);
    } else if (col === 2) {
      x = area.x + area.width - width;
    }
    if (row === 1) {
      y = area.y + Math.round((area.height - height) / 2);
    } else if (row === 2) {
      y = area.y + area.height - height;
    }
    window.frameGeometry = qt().rect(x, y, width, height);
  }
  evNewWindow(window, forceTile, tile, direction) {
    console().log("registering window", window.resourceClass);
    const handler = new WindowHandler(window, this.workspace);
    this.windowHandlers.set(window, handler);
    const ret = [];
    for (const display of Display.generateWindow(window)) {
      const driver = this.getDriver(display);
      if (driver === void 0) {
        continue;
      }
      if (driver.getEngineType() === KWIN_ENGINE_TYPE || forceTile === false || forceTile === void 0 && !handler.wantsTiled) {
        driver.addWindowUntiled(window);
        if (driver.getEngineType() !== KWIN_ENGINE_TYPE) {
          this.placeFloatingWindow(window, display.output);
        }
      } else if (forceTile === true && tile != void 0 && driver.hasTile(tile)) {
        driver.placeWindow(window, tile, direction);
      } else if (driver.isFull()) {
        // The engine has no room left, so this one floats from the start
        // instead of being squeezed into a tenth slot.
        driver.addWindowUntiled(window);
        this.floatWindow(window);
      } else {
        driver.addWindow(window, tile, direction);
      }
      ret.push(display);
    }
    // Remember only what actually happened. A missing driver used to leave
    // phantom displays in this list, so later updates warned about windows
    // that were never registered and could miss the one that was.
    this.previousDisplays.set(window, ret);
    return ret;
  }
  evDeleteWindow(window, displays) {
    // Do not read properties off a window that KWin may already have torn down.
    console().log("destroying window");
    if (this.previousDisplays.has(window)) {
      this.previousDisplays.delete(window);
    }
    // The display list captured by the signal is only a hint. A window that
    // was closed right after a desktop switch can still be registered on the
    // driver it came from, so check every live driver instead.
    const candidates = /* @__PURE__ */ new Map();
    for (const display of displays ?? []) {
      if (display === null || display === void 0 || display.output == null) {
        continue;
      }
      // Do not create a driver just to tear it down again; only existing
      // registrations matter here.
      const driver = this.drivers.get(display.toSymbol());
      if (driver !== void 0) {
        candidates.set(display.toSymbol(), { display, driver });
      }
    }
    for (const driver of this.drivers.values()) {
      const display = driver.display;
      if (display !== null && display !== void 0 && display.output != null && driver.hasWindow(window)) {
        candidates.set(display.toSymbol(), { display, driver });
      }
    }
    const ret = [];
    for (const { display, driver } of candidates.values()) {
      if (!driver.hasWindow(window)) {
        continue;
      }
      driver.removeWindow(window);
      ret.push(display);
    }
    this.windowHandlers.delete(window);
    return ret;
  }
  evUpdateWindow(window) {
    // An update queued just before the window closed must not re-add it.
    if (!this.windowExists(window)) {
      return this.evDeleteWindow(window, []);
    }
    console().log("updating window", window.resourceClass);
    const newDisplays = [...Display.generateWindow(window)];
    // Compare by the stable desktop/activity/output key rather than object
    // identity: window.desktops and workspace.desktops are not guaranteed to
    // hand out the same wrappers after a KWin reconfigure.
    const newDisplayKeys = new Set(newDisplays.map((display) => display.toSymbol()));
    let tiled = false;
    const ret = [];
    // Work from the drivers themselves, not just the remembered display list:
    // a placement or a missed signal can leave an extra driver holding the
    // window, and that entry would otherwise survive every later move.
    for (const driver of this.drivers.values()) {
      if (!driver.hasWindow(window)) {
        continue;
      }
      if (driver.isWindowTiled(window)) {
        tiled = true;
      }
      const display = driver.display;
      if (display !== null && display !== void 0 && display.output != null && newDisplayKeys.has(display.toSymbol())) {
        continue;
      }
      driver.removeWindow(window);
      if (display !== null && display !== void 0 && display.output != null) {
        ret.push(display);
      }
    }
    for (const newDisplay of newDisplays) {
      const driver = this.getDriver(newDisplay);
      if (driver === void 0) {
        continue;
      }
      if (driver.hasWindow(window)) {
        // Repair a driver that had it untiled while the window was tiled
        // elsewhere, or vice versa, without adding a second engine window.
        if (tiled && !driver.isWindowTiled(window)) {
          driver.tileWindow(window);
          ret.push(newDisplay);
        } else if (!tiled && driver.isWindowTiled(window)) {
          driver.untileWindow(window);
          ret.push(newDisplay);
        }
        continue;
      }
      if (tiled) {
        driver.addWindow(window);
      } else {
        driver.addWindowUntiled(window);
      }
      ret.push(newDisplay);
    }
    this.previousDisplays.set(window, newDisplays);
    return ret;
  }
  evTileWindow(window) {
    console().log("tiling window");
    const ret = [];
    for (const display of Display.generateWindow(window)) {
      const driver = this.getDriver(display);
      if (driver === void 0) {
        throw new Error(
          "driver not found for display " + display.toString()
        );
      }
      ret.push(display);
      driver.tileWindow(window);
    }
    return ret;
  }
  evUntileWindow(window) {
    console().log("untiling window");
    const ret = [];
    for (const display of Display.generateWindow(window)) {
      const driver = this.getDriver(display);
      if (driver === void 0) {
        throw new Error(
          "driver not found for display " + display.toString()
        );
      }
      ret.push(display);
      driver.untileWindow(window);
    }
    return ret;
  }
  evPlaceWindow(window, tile, direction) {
    // A drag can finish just as the window closes; never resurrect it.
    if (!this.windowExists(window)) {
      return this.evDeleteWindow(window, []);
    }
    console().log(
      "placing window",
      window.resourceClass,
      "in tile at",
      tile.absoluteGeometry
    );
    const displays = [];
    for (const display of Display.generateWindow(window)) {
      const driver = this.getDriver(display);
      if (driver == void 0) continue;
      // Any of these branches can change the engine's window list, so the
      // display always needs a rebuild. Leaving the add path out of the return
      // value was what let a window be counted but never given a tile.
      displays.push(display);
      if (!driver.hasTile(tile)) {
        if (driver.hasWindow(window)) {
          driver.tileWindow(window);
        } else {
          driver.addWindow(window);
        }
        continue;
      }
      driver.placeWindow(window, tile, direction);
    }
    const previous = this.previousDisplays.get(window);
    if (previous !== void 0) {
      const keys = new Set(previous.map((display) => display.toSymbol()));
      for (const display of displays) {
        if (!keys.has(display.toSymbol())) {
          keys.add(display.toSymbol());
          previous.push(display);
        }
      }
    }
    return displays;
  }
  evDragWindow(window) {
    const ret = [];
    for (const display of Display.generateWindow(window)) {
      const driver = this.getDriver(display);
      if (driver === void 0) {
        continue;
      }
      driver.setWindowDragging(window, true);
      ret.push(display);
    }
    return ret;
  }
  evPlaceWindowPoint(window, point) {
    if (!this.windowExists(window)) {
      return this.evDeleteWindow(window, []);
    }
    console().log(
      "placing window",
      window.resourceClass,
      "at point",
      point
    );
    const displays = [];
    for (const display of Display.generateWindow(window)) {
      const driver = this.getDriver(display);
      if (driver == void 0) continue;
      displays.push(display);
      driver.setWindowDragging(window, false);
      if (display.activity !== this.workspace.currentActivity) {
        if (driver.hasWindow(window)) {
          driver.tileWindow(window);
        } else {
          driver.addWindow(window);
        }
        continue;
      }
      const rootTile = this.workspace.rootTile(
        display.output,
        display.desktop
      );
      const tile = rootTile.tiles.length == 0 ? rootTile : rootTile.pick(point);
      if (tile === null || !driver.hasTile(tile)) {
        // Dropped outside the tiles: it floats where the user left it.
        if (driver.hasWindow(window)) {
          driver.untileWindow(window);
        } else {
          driver.addWindowUntiled(window);
        }
      } else {
        const direction = directionFromPoint(
          tile.absoluteGeometry,
          point
        );
        driver.placeWindow(window, tile, direction);
      }
    }
    const previous = this.previousDisplays.get(window);
    if (previous !== void 0) {
      const keys = new Set(previous.map((display) => display.toSymbol()));
      for (const display of displays) {
        if (!keys.has(display.toSymbol())) {
          keys.add(display.toSymbol());
          previous.push(display);
        }
      }
    }
    return displays;
  }
  evWindowActivated(window) {
    console().log("window activated");
    const displays = [];
    for (const display of Display.generateWindow(window)) {
      const driver = this.getDriver(display);
      if (driver == void 0) continue;
      if (driver.windowActivated(window)) {
        displays.push(display);
      }
    }
    return displays;
  }
  updateDrivers() {
    const ret = [];
    for (const display of Display.generate(
      this.workspace.desktops,
      this.workspace.activities,
      this.workspace.screens
    )) {
      const id = display.toSymbol();
      const driver = this.drivers.get(id);
      if (driver === void 0) {
        console().debug(
          "adding driver for display",
          display.toString()
        );
        const driver2 = new Driver(CUSTOM_ENGINE_TYPE);
        driver2.display = display;
        this.drivers.set(id, driver2);
        this.dbusHandler?.getSettings(display);
        ret.push(display);
      }
    }
    return ret;
  }
  displaysToRebuild() {
    const displays = [];
    for (const display of Display.generate(
      this.workspace.desktops,
      [this.workspace.currentActivity],
      this.workspace.screens
    )) {
      if (this.getDriver(display) !== void 0) {
        displays.push(display);
      }
    }
    return displays;
  }
  evUpdateTiles(display, rebuild) {
    console().log("updating tiles for display", display.toString());
    const driver = this.getDriver(display);
    if (driver === void 0) {
      return [];
    }
    // KWin owns the layout; Folonium has no tiles of its own to update.
    if (driver.getEngineType() === KWIN_ENGINE_TYPE) {
      return [];
    }
    driver.updateTiles();
    const engine = driver.getEngineType();
    const settings = driver.getEngineSettings();
    const settingsJson = JSON.stringify(settings);
    if (driver.lastSavedEngineType !== engine || driver.lastSavedSettings !== settingsJson) {
      this.dbusHandler?.setSettings(display, engine, settings, driver.lastEngine, driver.lastEngineSettings);
      driver.lastSavedEngineType = engine;
      driver.lastSavedSettings = settingsJson;
    }
    return rebuild ? [display] : [];
  }
  evModifyEngineSetting(display, setting, op, amount, min, max) {
    const driver = this.getDriver(display);
    if (driver === void 0) {
      throw new Error("no driver for display " + display.toString());
    }
    const settings = driver.getEngineSettings();
    if (!settings.hasOwnProperty(setting)) {
      console().warn(
        "setting",
        setting,
        "is not supported by engine",
        driver.getEngineType(),
        "- ignoring"
      );
      return [];
    }
    const current = settings[setting];
    let value;
    if (op === "toggle") {
      value = !current;
    } else if (op === "add") {
      value = current + amount;
    } else {
      value = amount;
    }
    if (typeof value === "number") {
      if (min !== void 0) {
        value = Math.max(min, value);
      }
      if (max !== void 0) {
        value = Math.min(max, value);
      }
      value = Math.round(value * 1e6) / 1e6;
    }
    console().debug(
      "modifying engine setting",
      setting,
      "from",
      current,
      "to",
      value
    );
    const engineSettings = {};
    engineSettings[setting] = value;
    return this.evChangeEngine(display, void 0, engineSettings);
  }
  evChangeEngine(display, engineType, engineSettings, noDBusUpdate) {
    console().log(
      "changing engine type/settings for display",
      display.toString()
    );
    const driver = this.getDriver(display);
    if (driver === void 0) {
      throw new Error("no driver for display " + display.toString());
    }
    const oldEngine = driver.getEngineType();
    const oldSettings = JSON.stringify(driver.getEngineSettings());
    driver.changeTilingEngine(engineType, engineSettings);
    const engine = driver.getEngineType();
    const settings = driver.getEngineSettings();
    if (oldEngine === engine && oldSettings === JSON.stringify(settings)) {
      return [];
    }
    if (this.settingsHandler.isVisible()) {
      this.settingsHandler.show(
        display,
        engine,
        settings,
        driver.windowCount(),
        driver.layoutCount(),
        driver.shapeText(),
        driver.layoutIndex(),
        driver.usingCustomLayout(),
        driver.customLayoutSets(),
        driver.ratioInfo()
      );
    }
    if (noDBusUpdate === void 0 || !noDBusUpdate) {
      this.dbusHandler?.setSettings(display, engine, settings, driver.lastEngine, driver.lastEngineSettings);
      driver.lastSavedEngineType = engine;
      driver.lastSavedSettings = JSON.stringify(settings);
    }
    return [display];
  }
  evResetEngine(display) {
    console().log(
      "resetting to default engine settings for display",
      display.toString()
    );
    const driver = this.getDriver(display);
    if (driver === void 0) {
      throw new Error(
        "driver undefined for display " + display.toString()
      );
    }
    driver.resetTilingEngine();
    this.dbusHandler?.resetSettings(display);
    // Always rebuild: a reset also drops the engine's remembered divider
    // proportions, which do not show up in the settings comparison.
    const engine = driver.getEngineType();
    const settings = driver.getEngineSettings();
    // The store entry was just deleted, so do not recreate it from the next
    // geometry event with what are now the global defaults.
    driver.lastSavedEngineType = engine;
    driver.lastSavedSettings = JSON.stringify(settings);
    if (this.settingsHandler.isVisible()) {
      this.settingsHandler.show(
        display,
        engine,
        settings,
        driver.windowCount(),
        driver.layoutCount(),
        driver.shapeText(),
        driver.layoutIndex(),
        driver.usingCustomLayout(),
        driver.customLayoutSets(),
        driver.ratioInfo()
      );
    }
    return [display];
  }
  handlePostEvent(ev) {
    console().debug("handling post event", ev.t);
    switch (ev.t) {
      case "setWindowProperties": {
        if (!this.windowExists(ev.window)) {
          break;
        }
        console().log(
          "setting properties for window",
          ev.window.resourceClass
        );
        if (ev.fullscreen !== void 0) {
          ev.window.fullScreen = ev.fullscreen;
        }
        if (ev.noBorder !== void 0) {
          ev.window.noBorder = ev.noBorder;
        }
        if (ev.keepAbove !== void 0) {
          ev.window.keepAbove = ev.keepAbove;
        }
        return;
      }
      case "toggleSettingsMenu": {
        console().log("toggling settings menu");
        if (this.settingsHandler.isVisible()) {
          this.settingsHandler.hide();
          return;
        }
        const driver = this.getDriver(ev.display);
        if (driver === void 0) {
          break;
        }
        this.settingsHandler.show(
          ev.display,
          driver.getEngineType(),
          driver.getEngineSettings(),
          driver.windowCount(),
          driver.layoutCount(),
          driver.shapeText(),
          driver.layoutIndex(),
          driver.usingCustomLayout(),
          driver.customLayoutSets(),
          driver.ratioInfo()
        );
        return;
      }
      default: {
        console().error("invalid post event type", ev.t);
        return;
      }
    }
    console().error("post event type", ev.t, "failed to execute");
    return;
  }
  // Hands a window back to the user as a floating window: folonium stops
  // tiling it but keeps tracking it, so the toggle shortcut still works.
  floatWindow(window) {
    const handler = this.windowHandlers.get(window);
    if (handler !== void 0) {
      handler.wantsTiled = false;
    }
    this.queueEvent({
      t: "untileWindow",
      window
    });
  }
  parseDisplay(display) {
    let str;
    if (typeof display === "symbol") {
      str = Symbol.keyFor(display);
    } else if (typeof display === "string") {
      str = display;
    }
    if (str === void 0) {
      return void 0;
    }
    let parsed;
    try {
      parsed = JSON.parse(str);
    } catch (_) {
      return void 0;
    }
    const d = this.workspace.desktops.find((d2) => d2.id === parsed.d);
    const a = this.workspace.activities.find((a2) => a2 === parsed.a);
    const o = this.workspace.screens.find((s) => s.name === parsed.o);
    if (d === void 0 || a === void 0 || o === void 0) {
      return void 0;
    }
    return new Display(d, a, o);
  }
  // gets a driver, if it doesn't exist then it calls updateDrivers and tries to get it again.
  // if it still doesn't exist, then it returns undefined.
  getDriver(display) {
    let id;
    if (typeof display === "string") {
      id = Symbol.for(display);
    } else if (typeof display === "symbol") {
      id = display;
    } else if (typeof display === "object") {
      id = display.toSymbol();
    } else {
      console().error("Invalid call to getDriver");
      return void 0;
    }
    let driver = this.drivers.get(id);
    if (driver !== void 0) return driver;
    console().warn(
      "driver not found for id",
      id,
      "updating drivers and trying again"
    );
    this.updateDrivers();
    driver = this.drivers.get(id);
    if (driver === void 0) {
      console().error("driver was still not found for id", id);
    }
    return driver;
  }
  getWindowHandler(window) {
    return this.windowHandlers.get(window);
  }
  mouseFollowsFocus() {
    return this.mffHandler;
  }
  // sometimes the window can be destroyed before rebuild but the ref will still exist, so make sure it exists before calling stuff on it
  windowExists(window) {
    return window !== null && window !== void 0 && this.workspace.windows.includes(window);
  }
  // avoid making driver instance public and get current tiling layout to enable cycling
  getEngineType(display) {
    return this.drivers.get(display.toSymbol())?.getEngineType();
  }
  isWindowTiled(window, display) {
    if (display != void 0) {
      return this.getDriver(display)?.isWindowTiled(window);
    }
    for (const display2 of Display.generateWindow(window)) {
      const driver = this.getDriver(display2);
      if (driver?.isWindowTiled(window)) {
        return true;
      }
    }
    return false;
  }
  // The driver that actually holds this window, for engine questions that do
  // not need a full display rebuild.
  windowDriver(window) {
    for (const display of Display.generateWindow(window)) {
      const driver = this.getDriver(display);
      if (driver !== void 0 && driver.hasWindow(window)) {
        return driver;
      }
    }
    return void 0;
  }
  isWindowInMonocle(window) {
    return this.windowDriver(window)?.isMonocle() === true;
  }
  isWindowOnKwinEngine(window) {
    return this.windowDriver(window)?.getEngineType() === KWIN_ENGINE_TYPE;
  }
};
var controllerObj;
var consoleObj;
var configObj;
var qtObject;
function initializeController(qmlApi, qmlObjects) {
  configObj = new Config(qmlApi.kwin);
  consoleObj = new Console(qmlApi.console);
  qtObject = qmlApi.qt;
  console().debug("config -", JSON.stringify(config()));
  // Bad window filters are logged after the console wrapper exists, without
  // stopping the script from loading.
  for (const err of config().regexErrors) {
    console().error(err);
  }
  controllerObj = new Controller(qmlApi, qmlObjects);
  console().log("controller initialized. Welcome to Folonium!");
}
function controller() {
  return controllerObj;
}
function console() {
  return consoleObj;
}
function config() {
  return configObj;
}
function qt() {
  return qtObject;
}

// src/index.ts
function main(api, qmlObjects) {
  Display.setWorkspace(api.workspace);
  initializeController(api, qmlObjects);
  // KWin only emits windowAdded for windows created after a script starts, so a
  // reload would otherwise leave every open window orphaned while the tiles the
  // previous instance created still sit on the screen. Adopt what is already
  // there and let the normal event queue rebuild the layout from scratch.
  for (const window of api.workspace.stackingOrder ?? []) {
    if (!isTrackableWindow(window)) {
      continue;
    }
    controller().workspaceHandler.windowAdded(window, true);
  }
}
export {
  main
};
