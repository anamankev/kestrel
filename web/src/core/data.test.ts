import { describe, expect, test } from "vitest";
import { decodeFacts, decodeFilings, earningsReleases, earningsEstimate, listings, screenRows, decodeFrame, screenMetrics } from "./sec";
import { parseFactors, mergeFactors } from "./factors";
import { decodeBLS, transform, MACRO, decodeNYFed, csvFields, decodeBulkCSV, decodeCountries } from "./econ";
import { zipFile } from "./zip";

describe("SEC", () => {
  test("company facts → fiscal years from 10-Ks", () => {
    const fact = (start: string, end: string, val: number, form = "10-K", filed = "2025-02-01") => ({ start, end, val, form, filed });
    const f = decodeFacts({ cik: 1, entityName: "Acme", facts: { "us-gaap": {
      Revenues: { units: { USD: [fact("2023-01-01", "2023-12-31", 100), fact("2024-01-01", "2024-12-31", 120), fact("2024-10-01", "2024-12-31", 30, "10-Q")] } },
      NetIncomeLoss: { units: { USD: [fact("2024-01-01", "2024-12-31", 12)] } },
      Assets: { units: { USD: [{ end: "2024-12-31", val: 500, form: "10-K", filed: "2025-02-01" }] } } } } });
    expect(f.years.map((y) => y.year)).toEqual([2023, 2024]);
    expect(f.years[1]).toMatchObject({ revenue: 120, netIncome: 12, assets: 500 });
  });
  test("filings, earnings releases and estimate", () => {
    const json = { cik: "320193", filings: { recent: { accessionNumber: ["0001-26-1", "0001-26-2", "0001-26-3", "0001-26-4"], filingDate: ["2026-10-30", "2026-10-31", "2026-07-31", "2026-04-30"],
      form: ["8-K", "8-K", "8-K", "8-K"], items: ["2.02,9.01", "2.02", "2.02", "2.02"], primaryDocument: ["a.htm", "b.htm", "c.htm", "../x"] } } };
    const fl = decodeFilings(json);
    expect(fl.length).toBe(3); // the path-traversal document name is dropped
    expect(fl[0].url).toBe("https://www.sec.gov/Archives/edgar/data/320193/000126 1/a.htm".replace(" ", ""));
    const rel = earningsReleases(json);
    expect(rel.length).toBe(3);
    const est = earningsEstimate(rel, Date.parse("2026-11-17T00:00:00Z"))!;
    expect(est.next).toBeGreaterThan(Date.parse("2026-11-17T00:00:00Z"));
  });
  test("screener rows derive missing totals", () => {
    const l = listings({ "0": { cik_str: 1, ticker: "AMZN", title: "Amazon" }, "9": { cik_str: 1, ticker: "AMZN2", title: "Amazon" } });
    const rows = screenRows(l, { contract: new Map([[1, 700]]), profitLoss: new Map([[1, 70]]), equityNCI: new Map([[1, 300]]), liabEquity: new Map([[1, 800]]) });
    expect(rows[0]).toMatchObject({ ticker: "AMZN", revenue: 700, liabilities: 500, assets: 800 });
    expect(screenMetrics(rows[0]).roe).toBeCloseTo(70 / 300);
    expect(decodeFrame({ data: [{ cik: 5, val: 9 }] }).get(5)).toBe(9);
  });
});

describe("factors, macro, world bank, zip", () => {
  test("French CSV parse and merge", () => {
    const t = parseFactors("header\n\n,Mkt-RF,SMB,HML,RF\n20260929,  -0.21, -0.03, -0.50, 0.01\n20260930, -0.26, 0.32, -0.88, 0.01\n\n Annual\n,Mkt-RF\n2025, 10\n");
    expect(t.names).toEqual(["Mkt-RF", "SMB", "HML", "RF"]);
    expect(t.rows.size).toBe(2);
    expect(t.rows.get(20260930)![2]).toBeCloseTo(-0.0088);
    expect(mergeFactors(t, { names: ["Mom"], rows: new Map([[20260930, [0.0032]]]) }).rows.get(20260930)!.length).toBe(5);
  });
  test("BLS and NY Fed", () => {
    const b = decodeBLS({ status: "REQUEST_SUCCEEDED", Results: { series: [{ seriesID: "X", data: [{ year: "2026", period: "M02", value: "2" }, { year: "2026", period: "M01", value: "1" }, { year: "2026", period: "M13", value: "9" }] }] } });
    expect(b.X.map((p) => p.value)).toEqual([1, 2]);
    expect(transform(MACRO[4], b.X)[0].value).toBe(1);
    expect(() => decodeBLS({ status: "REQUEST_NOT_PROCESSED" })).toThrow();
    expect(decodeNYFed({ refRates: [{ effectiveDate: "2026-11-01", percentRate: 4.1, targetRateFrom: 4, targetRateTo: 4.25 }] }).targetHigh).toBe(4.25);
  });
  test("World Bank CSV and countries", () => {
    expect(csvFields('"a, b","c""d",,e')).toEqual(["a, b", 'c"d', "", "e"]);
    const m = decodeBulkCSV('﻿"Data Source","WDI",\n"Country Name","Country Code","Indicator Name","Indicator Code","2023","2024",\n"Korea, Rep.","KOR","X","Y","44.1","",\n');
    expect(m.get("KOR")).toEqual([{ date: 2023, value: 44.1 }]);
    expect(decodeCountries([{}, [{ id: "WLD", name: "World", region: { value: "Aggregates" } }, { id: "JPN", name: "Japan", region: { value: "East Asia & Pacific " }, incomeLevel: { value: "High income" } }]])).toEqual([{ id: "JPN", name: "Japan", region: "East Asia & Pacific", income: "High income" }]);
  });
  test("zip: stored and deflate entries, named lookup", async () => {
    // A real two-file zip (deflate), built with Python's zipfile.
    const b64 = "UEsDBBQAAAAIAAAAIQA1FPLXBgAAAAQAAAAIAAAAbWV0YS5jc3bLTS1JBABQSwMEFAAAAAgAAAAhALPhWvIYAAAAFgAAAAkAAABBUElfeC5jc3bLSM3JyddRKM8vyklRSErMy1ZISSxJBABQSwECFAMUAAAACAAAACEANRTy1wYAAAAEAAAACAAAAAAAAAAAAAAAgAEAAAAAbWV0YS5jc3ZQSwECFAMUAAAACAAAACEAs+Fa8hgAAAAWAAAACQAAAAAAAAAAAAAAgAEsAAAAQVBJX3guY3N2UEsFBgAAAAACAAIAbQAAAGsAAAAAAA==";
    const zip = Uint8Array.from(atob(b64), (c) => c.charCodeAt(0));
    const text = new TextDecoder().decode(await zipFile(zip, (n) => n.startsWith("API_")));
    expect(text).toBe("hello, world bank data");
    await expect(zipFile(new Uint8Array(40))).rejects.toThrow();
  });
});
