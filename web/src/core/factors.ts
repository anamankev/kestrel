/** Fama-French factors (Kenneth R. French Data Library) and models. */
export type FactorSet = "F-F_Research_Data_Factors_daily_CSV.zip" | "F-F_Research_Data_5_Factors_2x3_daily_CSV.zip" | "F-F_Momentum_Factor_daily_CSV.zip";
export interface FactorTable { names: string[]; rows: Map<number, number[]> }

export const MODELS: Record<string, { factors: string[]; sets: FactorSet[] }> = {
  CAPM: { factors: ["Mkt-RF"], sets: ["F-F_Research_Data_Factors_daily_CSV.zip"] },
  FF3: { factors: ["Mkt-RF", "SMB", "HML"], sets: ["F-F_Research_Data_Factors_daily_CSV.zip"] },
  "CARHART 4": { factors: ["Mkt-RF", "SMB", "HML", "Mom"], sets: ["F-F_Research_Data_Factors_daily_CSV.zip", "F-F_Momentum_Factor_daily_CSV.zip"] },
  FF5: { factors: ["Mkt-RF", "SMB", "HML", "RMW", "CMA"], sets: ["F-F_Research_Data_5_Factors_2x3_daily_CSV.zip"] },
};
export const DESCRIBE: Record<string, string> = { "Mkt-RF": "Market excess return", SMB: "Size: small minus big", HML: "Value: high minus low book-to-market",
  RMW: "Profitability: robust minus weak", CMA: "Investment: conservative minus aggressive", Mom: "Momentum: winners minus losers" };

/** First daily block: a header starting with "," then `yyyymmdd, v1, v2…` (percent → fraction). */
export function parseFactors(text: string): FactorTable {
  let names: string[] = [];
  const rows = new Map<number, number[]>();
  let inBlock = false;
  for (const raw of text.split(/\r?\n/)) {
    const line = raw.trim();
    if (!inBlock) { if (line.startsWith(",")) { names = line.split(",").map((s) => s.trim()).filter(Boolean); inBlock = names.length > 0; } continue; }
    const cells = line.split(",").map((s) => s.trim());
    const d = Number(cells[0]);
    if (!(d > 19000000)) { if (rows.size) break; else continue; }
    const vals = cells.slice(1).map(Number);
    if (vals.length === names.length && vals.every(Number.isFinite)) rows.set(d, vals.map((v) => v / 100));
  }
  return { names, rows };
}

export function mergeFactors(a: FactorTable, b: FactorTable): FactorTable {
  const extra = b.names.map((n, i) => [n, i] as const).filter(([n]) => !a.names.includes(n));
  const rows = new Map<number, number[]>();
  for (const [d, v] of a.rows) { const o = b.rows.get(d); if (o) rows.set(d, [...v, ...extra.map(([, i]) => o[i])]); }
  return { names: [...a.names, ...extra.map(([n]) => n)], rows };
}
