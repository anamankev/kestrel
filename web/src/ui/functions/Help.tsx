import { functions } from "../../core/command";
import { workspace } from "../../data/workspace";
import { Section } from "../components";

/** Functions live on the web today; the rest arrive in later phases. */
export const WEB_READY = new Set(["DES", "GP", "W", "WEI", "FX", "COMD", "RATES", "MOST", "HMAP", "TOP", "CN", "SECF", "DEPTH", "TAS", "HELP", "FA", "EVTS", "DVD", "ERN", "HP", "BETA", "FACT", "EVST", "BT", "COMP", "MVO", "CORR", "EQS", "ECO", "ECST", "TRADE", "PORT", "BLOT", "ALRT", "PREF", "PRO", "OMON", "OSA", "RV"]);
const EXAMPLES: Record<string, string> = { DES: "AAPL DES", GP: "NVDA GP", HP: "SPY HP", FA: "MSFT FA", EVTS: "AAPL EVTS", CN: "TSLA CN", DEPTH: "BTC DEPTH", TAS: "ETH TAS", OMON: "BTC OMON", OSA: "ETH OSA", TRADE: "SOL BUY", BT: "SPY BT", BETA: "NVDA BETA", FACT: "MSFT FACT", DVD: "KO DVD", EVST: "NVDA EVST", SECF: "SECF TOYOTA", ECST: "ECST JAPAN", ALRT: "NVDA ALRT", RV: "AAPL RV", SEAS: "CL1 SEAS" };

export function Help({ panel }: { panel: number }) {
  const ready = functions.filter((f) => WEB_READY.has(f.code)), later = functions.filter((f) => !WEB_READY.has(f.code));
  const row = (f: (typeof functions)[number], on: boolean) => {
    const ex = EXAMPLES[f.code] ?? f.code;
    return (
      <tr key={f.code} className="click" tabIndex={0} onClick={() => { workspace.focus(panel); workspace.run(ex); }}>
        <td className={on ? "accent" : "faint"}><b>{f.code}</b></td>
        <td style={{ textAlign: "left", fontFamily: "var(--ui)" }} className={on ? "" : "dim"}>{f.title}</td>
        <td className="dim">{ex} &lt;GO&gt;</td>
      </tr>
    );
  };
  return (
    <div>
      <div style={{ padding: "10px 8px", fontSize: 12 }} className="dim">Type a security, a function, or both, then press GO (↩). <span className="faint">Syntax: TICKER [CLASS] FUNCTION. Classes: EQUITY CRYPTO INDEX CURNCY CMDTY GOVT</span></div>
      <Section title="ON THE WEB NOW" right={`${ready.length} FUNCTIONS`} />
      <table className="t"><tbody>{ready.map((f) => row(f, true))}</tbody></table>
      <Section title="IN THE IPAD & MAC APP · COMING TO THE WEB" right={`${later.length} FUNCTIONS`} />
      <table className="t"><tbody>{later.map((f) => row(f, false))}</tbody></table>
    </div>
  );
}
