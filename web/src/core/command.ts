import type { AssetClass, Instrument } from "./instrument";
import { functions, aliases, type FunctionInfo } from "./functions.generated";
import { resolve, search, token } from "./universe";

export { functions, type FunctionInfo };
export type TradeSide = "BUY" | "SELL";

const byCode = new Map(functions.map((f) => [f.code, f]));
export const fn = (code: string) => byCode.get(code)!;
export const functionFrom = (t: string): FunctionInfo | undefined => byCode.get(t) ?? (aliases[t] ? byCode.get(aliases[t]) : undefined);

export interface Command {
  fn: string;
  instrument?: Instrument;
  side?: TradeSide;
  /** Free text for SECF and ECST. */
  query?: string;
}

export class CommandError extends Error {}

const yellowKeys: Record<string, AssetClass> = {
  EQUITY: "EQUITY", EQUITIES: "EQUITY", CRYPTO: "CRYPTO", INDEX: "INDEX", CURNCY: "CURNCY", CMDTY: "CMDTY", COMDTY: "CMDTY", GOVT: "GOVT",
};

/** Longest command accepted; anything longer is rejected before parsing. */
export const maxLength = 64;

export function tokens(input: string): string[] {
  if (input.length > maxLength) return [];
  return input.toUpperCase().replaceAll("<", " ").replaceAll(">", " ").split(/\s+/).filter((t) => t && t !== "GO");
}

/** Parses `TICKER [EXCH] [YELLOW KEY] [FUNCTION] [<GO>]` in any order. */
export function parse(input: string, current?: Instrument): Command {
  const all = tokens(input);
  if (!all.length) throw new CommandError("Enter a security, a function, or HELP <GO>");
  const free = all.findIndex((t) => ["SECF", "ECST"].includes(functionFrom(t)?.code ?? ""));
  if (free >= 0) {
    const rest = all.filter((_, i) => i !== free);
    return { fn: functionFrom(all[free])!.code, query: rest.length ? rest.join(" ").slice(0, 64) : undefined };
  }
  let f: FunctionInfo | undefined, side: TradeSide | undefined, hint: AssetClass | undefined, ticker: string | undefined;
  for (const t of all) {
    const g = !f ? functionFrom(t) : undefined;
    if (g) { f = g; if (t === "BUY") side = "BUY"; else if (t === "SELL") side = "SELL"; }
    else if (yellowKeys[t]) hint = yellowKeys[t];
    else if (!ticker) ticker = t;
  }
  let instrument: Instrument | undefined;
  if (ticker) {
    instrument = resolve(ticker, hint);
    if (!instrument) throw new CommandError(`Unknown security: ${ticker}. Search every market with SECF <GO>`);
  }
  const code = f?.code ?? (instrument ? "DES" : undefined);
  if (!code) throw new CommandError("Enter a security, a function, or HELP <GO>");
  if (!instrument) {
    if (fn(code).needsSecurity) {
      if (!current) throw new CommandError(`${code} needs a security, e.g. AAPL ${code} <GO>`);
      instrument = current;
    } else if (code === "ALRT") instrument = current;
  }
  return { fn: code, instrument, side };
}

export interface Suggestion { completion: string; label: string; detail: string }

/** Autocomplete for the token being typed: securities first, then functions. */
export function suggestions(input: string, limit = 8): Suggestion[] {
  const upper = input.toUpperCase();
  if (!upper || upper.endsWith(" ")) return [];
  const parts = upper.split(" ");
  const last = parts[parts.length - 1];
  if (/^\d+$/.test(last)) return []; // "3 <GO>" picks hotspot 3
  const head = upper.slice(0, upper.length - last.length);
  const fns = functions.filter((f) => f.code.startsWith(last)).map((f) => ({ completion: head + f.code, label: f.code, detail: f.title }));
  const secs = head ? [] : search(last, limit).map((i) => ({ completion: token(i), label: `${token(i)} ${i.assetClass}`, detail: i.name }));
  return [...secs, ...fns].slice(0, limit);
}
