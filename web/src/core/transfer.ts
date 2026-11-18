/**
 * Kestrel transfer files, byte-compatible with the iPad/Mac app's TransferBundle (KestrelCore/Transfer.swift):
 * "KXF1" · salt (16) · PBKDF2 iterations (UInt32 big-endian) · "KSV1" AES-256-GCM sealed JSON.
 * The JSON uses Swift's Codable shapes: dates are seconds since 2001-01-01, enums with values are {"case":{"_0":v}},
 * ids are UUIDs. Imports are untrusted input and get the same limits as typed input.
 */
import { importDataKey, open, pbkdf2, randomBytes, seal, type Bytes } from "./auth";
import { PaperAccount, type Order, type OrderType } from "./paper";
import { AlertBook, type AlertCondition, type PriceAlert } from "./alerts";
import { parseOption } from "./options";

export const FORMAT = 1;
export const ITERATIONS = 600_000;
export const MAX_FILE = 8 * 1024 * 1024;
const MAGIC = new TextEncoder().encode("KXF1");
const REF = 978_307_200_000; // 2001-01-01T00:00:00Z in ms (Foundation's reference date)
const toSwiftDate = (ms: number) => (ms - REF) / 1000;
const fromSwiftDate = (s: unknown) => (Number.isFinite(s) ? (s as number) * 1000 + REF : 0);
const UUID_RE = /^[0-9A-F]{8}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{12}$/i;
const uuid = () => globalThis.crypto.randomUUID().toUpperCase();
const SYMBOL_RE = /^[A-Z0-9^=\-.]{1,32}$/;

export interface Watchlist { id: string; name: string; symbols: string[] }
export interface Bundle { exported: number; watchlists: Watchlist[]; activeID: string; alerts: AlertBook; account: PaperAccount }

export class TransferError extends Error {}
const fail = (m: string): never => { throw new TransferError(m); };

// MARK: Swift JSON shapes

function orderTypeOut(t: OrderType): unknown {
  switch (t.kind) {
    case "market": return { market: {} };
    case "limit": return { limit: { _0: t.limit } };
    case "stop": return { stop: { _0: t.stop } };
    case "stopLimit": return { stopLimit: { stop: t.stop, limit: t.limit } };
  }
}
function orderTypeIn(v: any): OrderType {
  if (v?.market) return { kind: "market" };
  if (v?.limit) return { kind: "limit", limit: Number(v.limit._0) };
  if (v?.stopLimit) return { kind: "stopLimit", stop: Number(v.stopLimit.stop), limit: Number(v.stopLimit.limit) };
  if (v?.stop) return { kind: "stop", stop: Number(v.stop._0) };
  return fail("The file's contents were rejected: order type");
}
const conditionOut = (c: AlertCondition) => (c.kind === "above" ? { above: { _0: c.level } } : c.kind === "below" ? { below: { _0: c.level } } : { movePercent: { _0: c.percent } });
function conditionIn(v: any): AlertCondition {
  if (v?.above) return { kind: "above", level: Number(v.above._0) };
  if (v?.below) return { kind: "below", level: Number(v.below._0) };
  if (v?.movePercent) return { kind: "move", percent: Number(v.movePercent._0) };
  return fail("The file's contents were rejected: alert condition");
}
const opt = <T,>(k: string, v: T | undefined) => (v === undefined || v === null ? {} : { [k]: v });

/** The bundle as the app's JSON. Non-UUID ids (the web's "core" list) get fresh UUIDs, since the app requires them. */
export function toSwiftJSON(b: Bundle): unknown {
  const ids = new Map(b.watchlists.map((w) => [w.id, UUID_RE.test(w.id) ? w.id.toUpperCase() : uuid()]));
  const a = b.account;
  return {
    format: FORMAT, exported: toSwiftDate(b.exported),
    watchlists: b.watchlists.map((w) => ({ id: ids.get(w.id), name: w.name, symbols: w.symbols })),
    activeID: ids.get(b.activeID) ?? ids.values().next().value,
    alerts: { alerts: b.alerts.alerts.map((x) => ({ id: UUID_RE.test(x.id) ? x.id.toUpperCase() : uuid(), symbol: x.symbol, condition: conditionOut(x.condition), created: toSwiftDate(x.created), ...opt("triggered", x.triggered != null ? toSwiftDate(x.triggered) : undefined), ...opt("triggerPrice", x.triggerPrice)
    })) },
    account: {
      cash: a.cash, nextID: a.nextID, allowShort: a.allowShort,
      positions: Object.fromEntries(Object.entries(a.positions).map(([k, p]) => [k, { symbol: p.symbol, quantity: p.quantity, averageCost: p.averageCost, realized: p.realized }])),
      orders: a.orders.map((o) => ({ id: o.id, symbol: o.symbol, side: o.side, quantity: o.quantity, type: orderTypeOut(o.type), created: toSwiftDate(o.created), status: o.status, updated: toSwiftDate(o.updated),
        ...opt("fillPrice", o.fillPrice), ...opt("note", o.note), ...opt("triggered", o.triggered) })),
      fills: a.fills.map((f) => ({ ...f, time: toSwiftDate(f.time) })),
    },
  };
}

/** Parses and validates the app's JSON with the same limits typed input gets. */
export function fromSwiftJSON(j: any): Bundle {
  if (!j || typeof j !== "object") fail("The file's contents were rejected: unreadable");
  if (Number(j.format) > FORMAT) fail("This file comes from a newer version of Kestrel");
  const lists: Watchlist[] = Array.isArray(j.watchlists) ? j.watchlists.map((w: any) => ({ id: String(w?.id ?? ""), name: String(w?.name ?? ""), symbols: Array.isArray(w?.symbols) ? w.symbols.map(String) : [] })) : [];
  if (!lists.length || lists.length > 20) fail("The file's contents were rejected: watchlist count");
  for (const w of lists) {
    if (!UUID_RE.test(w.id) || !w.name || w.name.length > 24 || w.symbols.length > 100) fail(`The file's contents were rejected: watchlist ${w.name.slice(0, 24)}`);
    if (!w.symbols.every((s) => SYMBOL_RE.test(s))) fail(`The file's contents were rejected: symbol in ${w.name.slice(0, 24)}`);
  }
  if (!lists.some((w) => w.id === j.activeID)) fail("The file's contents were rejected: active list");
  const raw: any[] = Array.isArray(j.alerts?.alerts) ? j.alerts.alerts : [];
  if (raw.length > AlertBook.maxActive + AlertBook.maxHistory) fail("The file's contents were rejected: alerts");
  const alerts: PriceAlert[] = raw.map((x) => {
    const symbol = String(x?.symbol ?? "");
    if (!SYMBOL_RE.test(symbol) && !parseOption(symbol)) fail("The file's contents were rejected: alert symbol");
    return { id: String(x.id), symbol, condition: conditionIn(x.condition), created: fromSwiftDate(x.created),
      ...(x.triggered != null ? { triggered: fromSwiftDate(x.triggered) } : {}), ...(Number.isFinite(x.triggerPrice) ? { triggerPrice: x.triggerPrice } : {}) };
  });
  const book = AlertBook.from({ alerts });
  if (book.active.length > AlertBook.maxActive) fail("The file's contents were rejected: alerts");
  const acc = j.account;
  if (!acc || !Number.isFinite(acc.cash)) fail("The file's contents were rejected: paper account");
  const orders: Order[] = (Array.isArray(acc.orders) ? acc.orders : []).map((o: any) => ({ ...o, type: orderTypeIn(o.type), created: fromSwiftDate(o.created), updated: fromSwiftDate(o.updated) }));
  const account = PaperAccount.from({ ...acc, orders, fills: (Array.isArray(acc.fills) ? acc.fills : []).map((f: any) => ({ ...f, time: fromSwiftDate(f.time) })) });
  if (account.openPositions.length > 500 || account.orders.length > 10_000) fail("The file's contents were rejected: paper account");
  return { exported: fromSwiftDate(j.exported), watchlists: lists, activeID: j.activeID, alerts: book, account };
}

// MARK: Sealing

export async function sealBundle(b: Bundle, passphrase: string, iterations = ITERATIONS): Promise<Bytes> {
  if ([...passphrase].length < 10) fail("Use a passphrase of at least 10 characters");
  const salt = randomBytes(16);
  const key = await importDataKey(await pbkdf2(passphrase, salt, iterations));
  const sealed = await seal(new TextEncoder().encode(JSON.stringify(toSwiftJSON(b))) as Bytes, key);
  const out = new Uint8Array(4 + 16 + 4 + sealed.length);
  out.set(MAGIC); out.set(salt, 4); new DataView(out.buffer).setUint32(20, iterations, false); out.set(sealed, 24);
  return out;
}

export async function openBundle(data: Bytes, passphrase: string): Promise<Bundle> {
  if (data.length > MAX_FILE || data.length <= 24 || !MAGIC.every((b, i) => data[i] === b)) fail("That isn't a Kestrel transfer file");
  const iterations = new DataView(data.buffer, data.byteOffset).getUint32(20, false);
  // Bound the work an attacker-supplied file can demand.
  if (iterations < 1_000 || iterations > 5_000_000) fail("That isn't a Kestrel transfer file");
  const key = await importDataKey(await pbkdf2(passphrase, data.slice(4, 20), iterations));
  let json: Bytes;
  try { json = await open(data.slice(24), key); } catch { return fail("Wrong passphrase, or the file was changed"); }
  let parsed: unknown;
  try { parsed = JSON.parse(new TextDecoder().decode(json)); } catch { return fail("The file's contents were rejected: unreadable"); }
  return fromSwiftJSON(parsed);
}
