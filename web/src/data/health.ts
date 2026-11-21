import { Store } from "./store";
import { classify, SOURCES, type Status } from "../core/health";
import { market } from "./market";

export interface Check { status: Status; ms: number; at: number; error?: string }

/** Results per source: updated passively by every relay request and actively by CHECK ALL. */
class HealthService extends Store {
  results = new Map<string, Check>();
  checking = false;
  record(id: string, ok: boolean, ms: number, error?: string) {
    this.results.set(id, { status: classify(ok, ms), ms: Math.round(ms), at: Date.now(), error });
    this.emit();
  }
  async checkAll(relay: (path: string) => Promise<Response>) {
    if (this.checking) return;
    this.checking = true; this.emit();
    await Promise.all(SOURCES.map(async (s) => {
      if (s.probe.kind === "feed") { this.record(s.id, market.live, 0, market.live ? undefined : "Not connected; reconnecting every 3 s"); return; }
      const t = performance.now();
      try {
        const r = s.probe.kind === "relay" ? await relay(s.probe.path) : await fetch(s.probe.url, { signal: AbortSignal.timeout(10_000) });
        if (!r.ok) throw new Error(`HTTP ${r.status}`);
        await r.arrayBuffer();
        this.record(s.id, true, performance.now() - t);
      } catch (e) {
        this.record(s.id, false, performance.now() - t, e instanceof Error ? e.message.slice(0, 80) : "failed");
      }
    }));
    this.checking = false; this.emit();
  }
}
export const health = new HealthService();
