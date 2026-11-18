/** US macro (BLS, New York Fed) and World Bank decoders. */
export interface Point { date: number; value: number }
export interface MacroIndicator { id: string; name: string; group: string; transform: "level" | "yoy" | "change"; unit: string }
export const MACRO: MacroIndicator[] = [
  { id: "CUSR0000SA0", name: "CPI inflation (YoY)", group: "INFLATION", transform: "yoy", unit: "%" },
  { id: "CUSR0000SA0L1E", name: "Core CPI ex food & energy (YoY)", group: "INFLATION", transform: "yoy", unit: "%" },
  { id: "WPSFD4", name: "PPI final demand (YoY)", group: "INFLATION", transform: "yoy", unit: "%" },
  { id: "LNS14000000", name: "Unemployment rate", group: "LABOR", transform: "level", unit: "%" },
  { id: "CES0000000001", name: "Nonfarm payrolls (monthly change)", group: "LABOR", transform: "change", unit: "K" },
  { id: "CES0500000003", name: "Average hourly earnings (YoY)", group: "LABOR", transform: "yoy", unit: "%" },
  { id: "LNS11300000", name: "Labor force participation", group: "LABOR", transform: "level", unit: "%" },
];
export function transform(i: MacroIndicator, raw: Point[]): Point[] {
  if (i.transform === "level") return raw;
  if (i.transform === "change") return raw.slice(1).map((p, k) => ({ date: p.date, value: p.value - raw[k].value }));
  return raw.length > 12 ? raw.slice(12).flatMap((p, k) => (raw[k].value === 0 ? [] : [{ date: p.date, value: (p.value / raw[k].value - 1) * 100 }])) : [];
}
export function decodeBLS(json: any): Record<string, Point[]> {
  if (json?.status !== "REQUEST_SUCCEEDED") throw new Error(`BLS: ${json?.status}`);
  const out: Record<string, Point[]> = {};
  for (const s of json?.Results?.series ?? []) out[s.seriesID] = (s.data ?? []).flatMap((p: any) => {
    const m = /^M(\d\d)$/.exec(p.period); const y = Number(p.year), v = Number(p.value);
    return m && Number(m[1]) >= 1 && Number(m[1]) <= 12 && Number.isFinite(v) ? [{ date: Date.UTC(y, Number(m[1]) - 1, 1), value: v }] : [];
  }).sort((a: Point, b: Point) => a.date - b.date);
  return out;
}
export function decodeNYFed(json: any) {
  const rows: any[] = json?.refRates ?? [];
  return { series: rows.map((r) => ({ date: Date.parse(r.effectiveDate + "T00:00:00Z"), value: r.percentRate })).filter((p) => Number.isFinite(p.date)).sort((a, b) => a.date - b.date),
    targetLow: rows[0]?.targetRateFrom as number | undefined, targetHigh: rows[0]?.targetRateTo as number | undefined };
}

// MARK: World Bank

export type WBUnit = "percent" | "usd" | "count";
export const WB_INDICATORS: { id: string; name: string; short: string; unit: WBUnit }[] = [
  { id: "NY.GDP.MKTP.KD.ZG", name: "Real GDP growth", short: "GDP GROWTH", unit: "percent" },
  { id: "NY.GDP.MKTP.CD", name: "GDP (current US$)", short: "GDP", unit: "usd" },
  { id: "NY.GDP.PCAP.CD", name: "GDP per capita (current US$)", short: "GDP / CAPITA", unit: "usd" },
  { id: "FP.CPI.TOTL.ZG", name: "Inflation, consumer prices", short: "CPI INFLATION", unit: "percent" },
  { id: "SL.UEM.TOTL.ZS", name: "Unemployment (% of labour force, ILO)", short: "UNEMPLOYMENT", unit: "percent" },
  { id: "BN.CAB.XOKA.GD.ZS", name: "Current account balance (% of GDP)", short: "CURRENT ACCOUNT", unit: "percent" },
  { id: "GC.DOD.TOTL.GD.ZS", name: "Central government debt (% of GDP)", short: "GOVT DEBT", unit: "percent" },
  { id: "NE.EXP.GNFS.ZS", name: "Exports of goods and services (% of GDP)", short: "EXPORTS", unit: "percent" },
  { id: "BX.KLT.DINV.WD.GD.ZS", name: "Foreign direct investment, net inflows (% of GDP)", short: "FDI INFLOWS", unit: "percent" },
  { id: "FR.INR.RINR", name: "Real interest rate", short: "REAL RATE", unit: "percent" },
  { id: "SP.POP.TOTL", name: "Population", short: "POPULATION", unit: "count" },
];
export interface Country { id: string; name: string; region: string; income: string }
export function decodeCountries(json: any): Country[] {
  const rows: any[] = Array.isArray(json) ? json[1] ?? [] : [];
  return rows.filter((r) => String(r.region?.value ?? "").trim() !== "Aggregates" && String(r.id).length === 3)
    .map((r) => ({ id: r.id, name: r.name, region: String(r.region?.value ?? "").trim(), income: String(r.incomeLevel?.value ?? "").trim() }))
    .sort((a, b) => a.name.localeCompare(b.name));
}
/** One RFC 4180 line: quoted fields may contain commas ("Korea, Rep."). */
export function csvFields(line: string): string[] {
  const out: string[] = []; let cur = "", q = false;
  for (let i = 0; i < line.length; i++) {
    const c = line[i];
    if (q) { if (c === '"') { if (line[i + 1] === '"') { cur += '"'; i++; } else q = false; } else cur += c; }
    else if (c === '"') q = true; else if (c === ",") { out.push(cur); cur = ""; } else if (c !== "﻿") cur += c;
  }
  out.push(cur);
  return out;
}
/** The bulk ZIP's API_*.csv → ISO3 → yearly points. */
export function decodeBulkCSV(text: string): Map<string, Point[]> {
  let years: (number | null)[] = [];
  const out = new Map<string, Point[]>();
  for (const line of text.split(/\r?\n/)) {
    const c = csvFields(line);
    if (c[0] === "Country Name") { years = c.map((x) => (/^\d{4}$/.test(x) ? Number(x) : null)); continue; }
    if (!years.length || c.length <= 4 || c[1].length !== 3) continue;
    const pts: Point[] = [];
    for (let k = 4; k < c.length && k < years.length; k++) { const y = years[k], v = Number(c[k]); if (y && c[k] !== "" && Number.isFinite(v)) pts.push({ date: y, value: v }); }
    if (pts.length) out.set(c[1], pts);
  }
  return out;
}
