import { Store } from "./store";
import { parse, fn, tokens, type Command, CommandError } from "../core/command";
import type { Instrument } from "../core/instrument";
import { crypto, equities, resolve, token } from "../core/universe";

export type Layout = 1 | 2 | 4 | 6;
export interface Panel { id: number; cmd: Command; history: Command[] }
export type Hotspot = { cmd: Command } | { link: Instrument };

const DEFAULTS = ["BTC CRYPTO GP", "W", "BTC CRYPTO DEPTH", "TOP", "BTC CRYPTO TAS", "WEI"];
const KEY = "kestrel.workspace.v1";

/** Saved form: commands as text, so a stored workspace can't inject anything but a command. */
const text = (c: Command) => c.query ? `${c.fn} ${c.query}` : [c.instrument ? token(c.instrument) : "", c.instrument?.assetClass === "CRYPTO" ? "CRYPTO" : "", c.side ?? c.fn].filter(Boolean).join(" ");

export class Workspace extends Store {
  panels: Panel[] = DEFAULTS.map((d, id) => ({ id, cmd: parse(d), history: [] }));
  layout: Layout = 4;
  focused = 0;
  maximized: number | null = null;
  error: string | null = null;
  hotspots = new Map<number, Hotspot[]>();

  constructor() {
    super();
    try {
      const raw = JSON.parse(localStorage.getItem(KEY) ?? "null");
      if (raw && Array.isArray(raw.panels)) {
        this.panels = DEFAULTS.map((d, id) => {
          let cmd: Command;
          try { cmd = parse(String(raw.panels[id] ?? d)); } catch { cmd = parse(d); }
          return { id, cmd, history: [] };
        });
        if ([1, 2, 4, 6].includes(raw.layout)) this.layout = raw.layout;
      }
    } catch { /* fresh workspace */ }
  }

  private save() {
    try { localStorage.setItem(KEY, JSON.stringify({ layout: this.layout, panels: this.panels.map((p) => text(p.cmd)) })); } catch { /* private mode */ }
  }

  get visible(): Panel[] { return this.maximized !== null ? [this.panels[this.maximized]] : this.panels.slice(0, this.layout); }
  get current(): Instrument | undefined { return this.panels[this.focused].cmd.instrument; }

  /** Runs a command line in the focused panel. `n <GO>` presses numbered item n. */
  run(input: string): boolean {
    const bare = tokens(input);
    if (bare.length === 1 && /^\d+$/.test(bare[0])) {
      const list = this.hotspots.get(this.focused) ?? [];
      const n = Number(bare[0]);
      const h = list[n - 1];
      if (!h) { this.error = `No item ${n} on this screen`; this.emit(); return false; }
      if ("cmd" in h) this.load(h.cmd, this.focused); else this.link(h.link, this.focused);
      this.error = null; this.emit(); return true;
    }
    try {
      this.load(parse(input, this.current), this.focused);
      this.error = null; this.emit(); return true;
    } catch (e) {
      this.error = e instanceof CommandError ? e.message : String(e);
      this.emit(); return false;
    }
  }

  load(cmd: Command, index: number) {
    const p = this.panels[index];
    if (text(p.cmd) !== text(cmd)) p.history = [...p.history.slice(-49), p.cmd];
    p.cmd = cmd;
    this.focused = index;
    if (index >= this.layout && this.maximized === null) this.layout = index < 2 ? 2 : index < 4 ? 4 : 6;
    this.save(); this.emit();
  }

  /** Picking a security in a list retargets every other visible panel showing a single security. */
  link(i: Instrument, from: number) {
    let linked = false;
    for (const p of this.panels.slice(0, this.layout)) {
      if (p.id === from || !fn(p.cmd.fn).needsSecurity) continue;
      if (p.cmd.instrument?.symbol !== i.symbol) { p.history = [...p.history.slice(-49), p.cmd]; p.cmd = { ...p.cmd, instrument: i }; }
      linked = true;
    }
    if (!linked) {
      const target = this.panels.slice(0, this.layout).find((p) => p.id !== from)?.id ?? from;
      this.load({ fn: "GP", instrument: i }, target);
      return;
    }
    this.save(); this.emit();
  }

  back(index = this.focused) {
    const p = this.panels[index];
    const prev = p.history.pop();
    if (prev) { p.cmd = prev; this.save(); this.emit(); }
  }

  setLayout(l: Layout) { this.layout = l; this.maximized = null; if (this.focused >= l) this.focused = 0; this.save(); this.emit(); }
  focus(i: number) { if (this.focused !== i) { this.focused = i; this.emit(); } }
  toggleMaximize(i: number) { this.maximized = this.maximized === i ? null : i; this.focused = i; this.emit(); }
  clear() { this.error = null; this.maximized = null; this.emit(); }
  setHotspots(panel: number, list: Hotspot[]) { this.hotspots.set(panel, list); }

  /** Symbols on screen, for faster quote refresh. */
  get symbolsOnScreen(): string[] { return this.visible.map((p) => p.cmd.instrument?.symbol).filter((s): s is string => !!s); }
}

export interface Watchlist { id: string; name: string; symbols: string[] }
const WKEY = "kestrel.watchlists.v1";
export const MAX_SYMBOLS = 100;

/** Watchlists (browser storage; per-account encryption arrives with sign-in). */
export class UserData extends Store {
  lists: Watchlist[] = [{ id: "core", name: "CORE", symbols: [...crypto, ...equities].map((i) => i.symbol) }];
  activeId = "core";

  constructor() {
    super();
    try {
      const raw = JSON.parse(localStorage.getItem(WKEY) ?? "null");
      if (raw && Array.isArray(raw.lists) && raw.lists.length) {
        this.lists = raw.lists.slice(0, 50).map((l: Watchlist) => ({ id: String(l.id).slice(0, 40), name: String(l.name).slice(0, 40),
          symbols: (Array.isArray(l.symbols) ? l.symbols : []).map(String).filter((s: string) => s.length <= 24).slice(0, MAX_SYMBOLS) }));
        this.activeId = this.lists.some((l) => l.id === raw.activeId) ? raw.activeId : this.lists[0].id;
      }
    } catch { /* defaults */ }
  }

  get active(): Watchlist { return this.lists.find((l) => l.id === this.activeId) ?? this.lists[0]; }
  private save() { try { localStorage.setItem(WKEY, JSON.stringify({ lists: this.lists, activeId: this.activeId })); } catch { /* private mode */ } this.emit(); }

  /** Resolves a typed ticker and adds it; returns an error message, or null on success. */
  add(text: string): string | null {
    const t = text.trim();
    if (!t) return null;
    const i = t.length <= 24 ? resolve(t) : undefined;
    if (!i) return `Unknown security: ${t.toUpperCase()}`;
    const l = this.active;
    if (l.symbols.includes(i.symbol)) return `${i.ticker} is already on ${l.name}`;
    if (l.symbols.length >= MAX_SYMBOLS) return `List is full (${MAX_SYMBOLS})`;
    l.symbols = [...l.symbols, i.symbol];
    this.save();
    return null;
  }
  remove(symbol: string) { this.active.symbols = this.active.symbols.filter((s) => s !== symbol); this.save(); }
  select(id: string) { this.activeId = id; this.save(); }
  create(name: string) { const id = globalThis.crypto.randomUUID(); this.lists = [...this.lists, { id, name: name.trim().slice(0, 40) || "LIST", symbols: [] }]; this.activeId = id; this.save(); }
  rename(name: string) { this.active.name = name.trim().slice(0, 40) || this.active.name; this.save(); }
  deleteActive() { if (this.lists.length > 1) { this.lists = this.lists.filter((l) => l.id !== this.activeId); this.activeId = this.lists[0].id; this.save(); } }
}

export const workspace = new Workspace();
export const userData = new UserData();
