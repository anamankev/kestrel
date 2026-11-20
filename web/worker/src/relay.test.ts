import { describe, expect, test } from "vitest";
import { handle, route, allow, configProblem, type Env } from "./relay";

const env: Env = { ALLOWED_ORIGINS: "https://kestrel.example", SEC_CONTACT: "owner@example.com" };
const req = (path: string, origin = "https://kestrel.example", method = "GET") =>
  new Request(`https://relay.example${path}`, { method, headers: { Origin: origin } });

describe("relay routes", () => {
  test("allows only known, validated requests", () => {
    expect(route(new URL("https://r/yahoo/chart/AAPL?range=1y&interval=1d"))?.upstream).toContain("/v8/finance/chart/AAPL?range=1y");
    expect(route(new URL("https://r/yahoo/chart/%5EGSPC?range=1d&interval=5m"))?.upstream).toContain("%5EGSPC");
    expect(route(new URL("https://r/yahoo/chart/AAPL?range=forever"))).toBeNull();
    expect(route(new URL("https://r/yahoo/chart/AA%2FPL"))).toBeNull();
    expect(route(new URL("https://r/yahoo/search?q=toyota"))?.upstream).toContain("q=toyota");
    expect(route(new URL("https://r/yahoo/search?q="))).toBeNull();
    expect(route(new URL("https://r/sec/submissions/320193"))?.upstream).toBe("https://data.sec.gov/submissions/CIK0000320193.json");
    expect(route(new URL("https://r/sec/submissions/../etc"))).toBeNull();
    expect(route(new URL("https://r/sec/frames/Revenues/CY2025"))?.upstream).toContain("/Revenues/USD/CY2025.json");
    expect(route(new URL("https://r/sec/frames/Revenues/2025"))).toBeNull();
    expect(route(new URL("https://r/french/F-F_Momentum_Factor_daily_CSV.zip"))).not.toBeNull();
    expect(route(new URL("https://r/french/other.zip"))).toBeNull();
    expect(route(new URL("https://r/anything?url=https://evil"))).toBeNull();
    expect(route(new URL("https://r/yahoo/spark?symbols=AAPL,%5EGSPC,EURUSD%3DX"))?.upstream).toContain("symbols=AAPL%2C%5EGSPC%2CEURUSD%3DX");
    expect(route(new URL(`https://r/yahoo/spark?symbols=${Array(21).fill("A").join(",")}`))).toBeNull();
    expect(route(new URL("https://r/yahoo/spark?symbols=AAPL,<x>"))).toBeNull();
    expect(route(new URL("https://r/wb/bulk/SP.POP.TOTL"))?.upstream).toContain("downloadformat=csv");
    expect(route(new URL("https://r/wb/bulk/ANY.THING"))).toBeNull();
    expect(route(new URL("https://r/bls"))?.post).toContain("CUSR0000SA0");
    expect(route(new URL("https://r/rss/cnbc"))?.upstream).toContain("cnbc.com");
    expect(route(new URL("https://r/rss/company?s=TSLA"))?.upstream).toContain("s=TSLA");
    expect(route(new URL("https://r/rss/evilfeed"))).toBeNull();
    expect(route(new URL("https://r/rss/company?s=<script>"))).toBeNull();
    expect(route(new URL("https://r/sec/sic/3571?start=100"))?.upstream).toContain("SIC=3571&type=10-K&dateb=&owner=include&start=100&count=100&output=atom");
    expect(route(new URL("https://r/sec/sic/3571?start=50"))).toBeNull();
    expect(route(new URL("https://r/sec/sic/35711"))).toBeNull();
    expect(route(new URL("https://r/sec/sic/3571?start=99999"))).toBeNull();
    expect(route(new URL("https://r/tsy/2021"))?.upstream).toContain("daily-treasury-rates.csv/2021/all?type=daily_treasury_yield_curve&field_tdr_date_value=2021");
    expect(route(new URL("https://r/tsy/1989"))).toBeNull();
    expect(route(new URL(`https://r/tsy/${new Date().getUTCFullYear() + 1}`))).toBeNull();
    expect(route(new URL("https://r/tsy/20211"))).toBeNull();
    expect(route(new URL("https://r/sec/shares/CY2025Q4I"))?.upstream).toContain("/dei/EntityCommonStockSharesOutstanding/shares/CY2025Q4I.json");
    expect(route(new URL("https://r/sec/shares/2025"))).toBeNull();
  });
});

describe("relay handler", () => {
  const ok = async (u: string, i?: RequestInit) => new Response(JSON.stringify({ u, ua: (i?.headers as Record<string, string>)["User-Agent"] }), { status: 200 });

  test("rejects foreign origins and non-GET", async () => {
    expect((await handle(req("/yahoo/search?q=a", "https://evil.example"), env, ok)).status).toBe(403);
    expect((await handle(req("/yahoo/search?q=a", undefined, "POST"), env, ok)).status).toBe(405);
    const pre = await handle(req("/yahoo/search?q=a", undefined, "OPTIONS"), env, ok);
    expect(pre.status).toBe(204);
    expect(pre.headers.get("Access-Control-Allow-Origin")).toBe("https://kestrel.example");
  });

  test("forwards with the right User-Agent and security headers", async () => {
    const sec = await handle(req("/sec/tickers"), env, ok);
    expect((await sec.json()).ua).toBe("Kestrel/1.0 (owner@example.com)");
    expect(sec.headers.get("X-Content-Type-Options")).toBe("nosniff");
    const y = await handle(req("/yahoo/chart/AAPL"), env, ok);
    expect((await y.json()).ua).not.toContain("owner@");
    expect((await handle(req("/nope"), env, ok)).status).toBe(404);
  });

  test("SEC routes need the contact secret; upstream errors map to 502", async () => {
    expect((await handle(req("/sec/tickers"), { ALLOWED_ORIGINS: env.ALLOWED_ORIGINS }, ok)).status).toBe(503);
    const bad = async () => new Response("x", { status: 500 });
    expect((await handle(req("/yahoo/search?q=a"), env, bad)).status).toBe(502);
  });

  test("rate limit", () => {
    for (let i = 0; i < 120; i++) expect(allow("1.2.3.4", 0)).toBe(true);
    expect(allow("1.2.3.4", 0)).toBe(false);
    expect(allow("1.2.3.4", 61_000)).toBe(true);
  });

  test("refuses unsafe configuration", async () => {
    expect(configProblem(env)).toBeNull();
    expect(configProblem({ ALLOWED_ORIGINS: "" })).toMatch(/empty/);
    expect(configProblem({ ALLOWED_ORIGINS: "*" })).toMatch(/wildcard/);
    expect(configProblem({ ALLOWED_ORIGINS: "https://*.pages.dev" })).toMatch(/wildcard/);
    expect(configProblem({ ALLOWED_ORIGINS: "http://kestrel.example" })).toMatch(/https/);
    expect(configProblem({ ALLOWED_ORIGINS: "https://kestrel.example/app" })).toMatch(/bare origins/);
    expect(configProblem({ ALLOWED_ORIGINS: "http://localhost:5173" })).toBeNull();
    expect(configProblem({ ...env, SEC_CONTACT: "not an email" })).toMatch(/SEC_CONTACT/);
    const r = await handle(req("/yahoo/search?q=a"), { ALLOWED_ORIGINS: "*" }, ok, undefined, () => {});
    expect(r.status).toBe(500);
    expect(r.headers.get("Access-Control-Allow-Origin")).toBeNull();
  });

  test("logs suspicious requests with a hashed IP, never the address", async () => {
    const events: Record<string, unknown>[] = [];
    const log = (e: Record<string, unknown>) => events.push(e);
    const r = (path: string, origin?: string, method?: string) => { const q = req(path, origin, method); q.headers.set("CF-Connecting-IP", "203.0.113.9"); return q; };
    await handle(r("/yahoo/search?q=a", "https://evil.example"), env, ok, undefined, log);
    await handle(r("/anything?url=https://evil"), env, ok, undefined, log);
    await handle(r("/yahoo/search?q=a", undefined, "POST"), env, ok, undefined, log);
    expect(events.map((e) => e.event)).toEqual(["origin_rejected", "route_rejected", "method_rejected"]);
    expect(JSON.stringify(events)).not.toContain("203.0.113.9");
    expect(events[0].ip).toMatch(/^[0-9a-f]{12}$/);
  });

  test("responses can't run or be framed", async () => {
    const html = async () => new Response("<script>alert(1)</script>", { status: 200, headers: { "Content-Type": "text/html" } });
    const res = await handle(req("/rss/cnbc"), env, html, undefined, () => {});
    expect(res.headers.get("Content-Security-Policy")).toContain("sandbox");
    expect(res.headers.get("X-Frame-Options")).toBe("DENY");
  });
});
