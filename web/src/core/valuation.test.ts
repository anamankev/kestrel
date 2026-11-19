import { describe, expect, it } from "vitest";
import { decodeSicFeed, median, pickPeers, premium, rvRow } from "./valuation";
import type { ScreenRow } from "./sec";

const row = (cik: number, revenue?: number, extra: Partial<ScreenRow> = {}): ScreenRow => ({ cik, ticker: `T${cik}`, name: `Co ${cik}`, sizeRank: cik, revenue, ...extra });

describe("RV", () => {
  it("reads EDGAR's company list", () => {
    const xml = `<entry><content type="text/xml"><company-info><addresses/><cik>0000320193</cik>
      <name>APPLE INC</name><sic>3571</sic></company-info></content></entry>
      <entry><company-info><cik>0000861289</cik>
      <name>AT&amp;T LOGIC</name></company-info></entry>`;
    expect(decodeSicFeed(xml)).toEqual([{ cik: 320193, name: "APPLE INC" }, { cik: 861289, name: "AT&T LOGIC" }]);
    expect(decodeSicFeed("<html>not a feed</html>")).toEqual([]);
    // Dell's real entry: former names sit between the CIK and the name.
    const dell = `<entry><content type="text/xml"><company-info><cik>0001571996</cik>
      <formerly-names>&lt;name&gt;Dell Technologies Inc&lt;/name&gt;&lt;last_date&gt;Wed Jan 29 2020&lt;/last_date&gt;</formerly-names>
      <name>Dell Technologies Inc.</name><sic>3571</sic></company-info></content></entry>`;
    expect(decodeSicFeed(dell)).toEqual([{ cik: 1571996, name: "Dell Technologies Inc." }]);
  });
  it("picks same-industry peers closest in size", () => {
    const target = row(1, 100);
    const rows = [target, row(2, 110), row(3, 1000), row(4, 95), row(5, 10), row(6, 100)];
    const peers = pickPeers(target, rows, new Set([1, 2, 3, 4, 5]), 3);
    expect(peers.map((p) => p.cik)).toEqual([4, 2, 3]);   // 6 isn't in the industry; 5 and 3 are both 10x away
  });
  it("computes valuation and quality ratios", () => {
    const r = rvRow(row(1, 200, { netIncome: 20, equity: 100, assets: 400, liabilities: 300 }), true, 10, 50, 160);
    expect(r).toMatchObject({ marketCap: 500, pe: 25, ps: 2.5, pb: 5, growth: 0.25, margin: 0.1, roe: 0.2, leverage: 0.75 });
    expect(rvRow(row(2, 100, { netIncome: -5 }), false, 10, 10).pe).toBeUndefined();   // no P/E on losses
    expect(rvRow(row(3, 100), false).marketCap).toBeUndefined();
  });
  it("benchmarks against the peer median", () => {
    expect(median([3, undefined, 1, 2])).toBe(2);
    expect(median([4, 1, 3, 2])).toBe(2.5);
    expect(median([undefined])).toBeUndefined();
    expect(premium(30, 20)).toBeCloseTo(0.5);
  });
});
