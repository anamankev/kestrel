/** LEARN: guided drills with badges. The curriculum is generated from KestrelCore/Learn.swift (`npm run learn`). */
import { MODULES } from "./learn.generated";

export interface Drill { id: string; command: string; look: string; question: string; choices: string[]; answer: number; why: string }
export interface Module { id: string; title: string; badge: string; summary: string; drills: Drill[] }

export { MODULES };

export const done = (m: Module, completed: Set<string>) => m.drills.filter((d) => completed.has(d.id)).length;
export const earned = (m: Module, completed: Set<string>) => done(m, completed) === m.drills.length;
/** The first drill not yet answered correctly, or the first when the module is complete. */
export const next = (m: Module, completed: Set<string>) => Math.max(0, m.drills.findIndex((d) => !completed.has(d.id)));

/** Only known drill ids survive (stored data from an older or tampered copy is filtered). */
export function sanitize(ids: unknown): Set<string> {
  const known = new Set(MODULES.flatMap((m) => m.drills.map((d) => d.id)));
  return new Set(Array.isArray(ids) ? ids.filter((x): x is string => typeof x === "string" && known.has(x)) : []);
}

/** Choices shuffled the same way on every device (FNV-1a of id and index). Mirrors Learn.order in Swift. */
export function choiceOrder(d: Drill): number[] {
  const fnv = (s: string) => { let h = 2166136261; for (const b of new TextEncoder().encode(s)) h = Math.imul(h ^ b, 16777619) >>> 0; return h; };
  return d.choices.map((_, k) => k).sort((a, b) => fnv(`${d.id}#${a}`) - fnv(`${d.id}#${b}`) || a - b);
}
