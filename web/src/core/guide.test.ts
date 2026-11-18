import { describe, expect, it } from "vitest";
import { answer, glossary, howTos, securityMentioned, topics, type Context } from "./guide";
import { parse } from "./command";

const top = (q: string) => answer(q).commands[0];

describe("guide (ported from KestrelGuide tests)", () => {
  it("answers plain questions", () => {
    expect(top("how do I see Apple's dividends?")).toBe("AAPL DVD");
    expect(top("show me a chart of bitcoin")).toBe("BTC GP");
    expect(top("I want to buy some NVDA")).toBe("NVDA BUY");
    expect(top("compare my watchlist performance")).toBe("COMP");
    expect(top("add a stock to my watchlist")).toBe("W");
    expect(top("find the ticker for toyota")).toBe("SECF TOYOTA");
    expect(top("what's inflation doing in the us")).toBe("ECO");
    expect(top("gdp of japan")).toBe("ECST JAPAN");
    expect(top("how did aapl react to earnings")).toBe("AAPL EVST");
    expect(top("advanced chart please")).toBe("NVDA GP");
    expect(answer("hello").commands).toContain("HELP");
    expect(answer("what is beta?").text.startsWith("Beta measures")).toBe(true);
    expect(answer("qwerty zxcv").commands).toContain("SECF");
    expect(securityMentioned("is the bank open")).toBeUndefined();
    expect(securityMentioned("price of 7203.T")?.symbol).toBe("7203.T");
  });
  it("has steps for every function and only runnable commands", () => {
    expect(topics.every((t) => t.steps.length > 0)).toBe(true);
    const cmds = [...howTos.flatMap((h) => h.commands), ...Object.keys(glossary).flatMap((k) => answer(`what is ${k}`).commands.slice(0, 1))];
    for (const c of cmds) expect(() => parse(c), c).not.toThrow();
    const text = JSON.stringify([topics, howTos]);
    for (const app of ["long-press", "AirDrop", "Apple ID", "menu bar", "SEC contact email in PREF", "PAGES"]) expect(text, app).not.toContain(app);
  });
  it("explains trading", () => {
    const r = answer("how do I trade?");
    expect(r.text).toContain("CONFIRM"); expect(r.commands[0]).toBe("AAPL BUY");
    expect(top("how do I buy apple stock")).toBe("AAPL BUY");
    expect(answer("what's the difference between limit and stop?").text).toContain("STOP LMT");
    const s = answer("can I short tesla?");
    expect(s.text).toContain("150%"); expect(s.commands[0]).toBe("TSLA SELL");
    expect(answer("how do I cancel an order").commands).toEqual(["BLOT"]);
    expect(answer("is the data live?").text).toContain("15 minutes");
  });
  it("remembers the conversation", () => {
    const c: Context = {};
    const first = answer("show me Apple's dividends", c);
    expect(first.commands[0]).toBe("AAPL DVD"); expect(first.text.startsWith("DVD for AAPL")).toBe(true);
    const more = answer("how do I use it?", c);
    expect(more.text.startsWith("How to use DVD")).toBe(true); expect(more.commands[0]).toBe("AAPL DVD");
    expect(answer("and for Microsoft?", c).commands[0]).toBe("MSFT DVD");
    expect(answer("what about NVDA", c).commands[0]).toBe("NVDA DVD");
    expect(answer("thanks!", c).text.startsWith("You're welcome")).toBe(true);
  });
  it("never recommends trades", () => {
    for (const q of ["is apple a good buy?", "should I invest in nvidia", "will bitcoin go up", "what stock should I buy", "give me a tip"]) {
      const r = answer(q);
      expect(r.text, q).toContain("can't tell you what to buy");
      expect(r.commands.some((c) => c.endsWith(" BUY") || c.endsWith(" SELL")), q).toBe(false);
    }
  });
  it("routes everyday questions", () => {
    expect(top("what's my profit")).toBe("PORT");
    expect(top("how much cash do I have")).toBe("PORT");
    expect(top("tesla news")).toBe("TSLA CN");
    expect(top("japan economy")).toBe("ECST JAPAN");
    expect(top("compare apple and microsoft")).toBe("AAPL GP");
    expect(answer("how do I make the chart bigger").text).toContain("full screen");
    expect(answer("does it work offline").text).toContain("internet");
    expect(top("how do I change colours")).toBe("PREF");
    expect(top("bitcoin options")).toBe("BTC OMON");
    expect(top("germany gdp")).toBe("ECST GERMANY");
    expect(top("what is the market doing today")).toBe("WEI");
    expect(answer("how does the guide work").text).toContain("in your browser");
  });
});

describe("guide additions", () => {
  it("routes 'how do I short' to short selling with a SELL ticket", () => {
    const r = answer("how do I short tesla?");
    expect(r.text).toContain("150%"); expect(r.commands[0]).toBe("TSLA SELL");
  });
});
