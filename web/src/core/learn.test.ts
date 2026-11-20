import { describe, expect, it } from "vitest";
import swift from "../../../KestrelCore/Sources/KestrelCore/Learn.swift?raw";
import { choiceOrder, done, earned, MODULES, next, sanitize } from "./learn";
import { parse } from "./command";

describe("LEARN", () => {
  it("matches the Swift curriculum", () => {
    const body = /\/\/ BEGIN CURRICULUM\n\s*static let json = #"""\n([\s\S]*?)\n\s*"""#/.exec(swift)![1];
    expect(MODULES).toEqual(JSON.parse(body));   // run `npm run learn` after editing Learn.swift
  });
  it("has well-formed drills that open real commands", () => {
    const ids = MODULES.flatMap((m) => m.drills.map((d) => d.id));
    expect(new Set(ids).size).toBe(ids.length);
    for (const d of MODULES.flatMap((m) => m.drills)) {
      expect(d.answer).toBeGreaterThanOrEqual(0);
      expect(d.answer).toBeLessThan(d.choices.length);
      expect(parse(d.command), d.command).toBeTruthy();
    }
  });
  it("shuffles choices the same way as the app", () => {
    const d = MODULES[0].drills[0];
    const order = choiceOrder(d);
    expect([...order].sort()).toEqual([0, 1, 2, 3]);
    expect(order).toEqual([2, 3, 0, 1]);   // the same order Learn.order gives in Swift
    // Not every right answer lands in the same slot.
    expect(new Set(MODULES.flatMap((m) => m.drills.map((x) => choiceOrder(x).indexOf(x.answer)))).size).toBeGreaterThan(2);
  });
  it("tracks progress and badges", () => {
    const m = MODULES[1];
    const some = sanitize([m.drills[0].id, "bogus", 7]);
    expect([...some]).toEqual([m.drills[0].id]);
    expect(done(m, some)).toBe(1);
    expect(next(m, some)).toBe(1);
    expect(earned(m, new Set(m.drills.map((d) => d.id)))).toBe(true);
    expect(next(m, new Set(m.drills.map((d) => d.id)))).toBe(0);
  });
});
