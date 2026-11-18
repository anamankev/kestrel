import { useSyncExternalStore } from "react";

/** Minimal observable store: mutate, then `emit()`; React reads via `useStore`. */
export class Store {
  private listeners = new Set<() => void>();
  version = 0;
  private pending = false;
  subscribe = (l: () => void) => { this.listeners.add(l); return () => this.listeners.delete(l); };
  getVersion = () => this.version;
  /** Notifies at most once per animation frame (the live feed sends 100+ messages a second). */
  emit() {
    if (this.pending) return;
    this.pending = true;
    const flush = () => { this.pending = false; this.version++; this.listeners.forEach((l) => l()); };
    if (typeof requestAnimationFrame === "function") requestAnimationFrame(flush); else setTimeout(flush, 16);
  }
}

export function useStore(s: Store): number {
  return useSyncExternalStore(s.subscribe, s.getVersion);
}
