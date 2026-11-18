import { describe, expect, test } from "vitest";
import { handle, route, allow, type Env } from "./relay";

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
    expect(route(new URL("https://r/rss/cnbc"))?.upstream).toContain("cnbc.com");
    expect(route(new URL("https://r/rss/company?s=TSLA"))?.upstream).toContain("s=TSLA");
    expect(route(new URL("https://r/rss/evilfeed"))).toBeNull();
    expect(route(new URL("https://r/rss/company?s=<script>"))).toBeNull();
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
});
