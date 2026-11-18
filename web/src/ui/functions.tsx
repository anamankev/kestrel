import type { Command } from "../core/command";
import { fn } from "../core/command";
import { Empty } from "./components";
import { Description } from "./functions/Description";
import { PriceChart } from "./functions/PriceChart";
import { Monitor } from "./functions/Monitor";
import { QuoteBoard, Movers, Heatmap } from "./functions/Boards";
import { News } from "./functions/News";
import { SecurityFinder } from "./functions/SecurityFinder";
import { Depth, TimeAndSales } from "./functions/Crypto";
import { Help } from "./functions/Help";
import { commodityGroups, currencyGroups, indices, rates, isStreaming } from "../core/universe";
import { market } from "../data/market";
import { useStore } from "../data/store";

export function FunctionView({ panel, cmd }: { panel: number; cmd: Command }) {
  useStore(market);
  const i = cmd.instrument;
  if (i && market.unknown.has(i.symbol)) return <Empty title={`${i.ticker}: security not found`} detail="No market data exists for this ticker. Check the symbol, or search with SECF." />;
  switch (cmd.fn) {
    case "DES": return <Description panel={panel} i={i!} />;
    case "GP": return <PriceChart key={i!.symbol} i={i!} />;
    case "W": return <Monitor panel={panel} />;
    case "WEI": return <QuoteBoard panel={panel} groups={(["AMERICAS", "EMEA", "ASIA/PACIFIC"] as const).map((r) => [r, indices.filter((x) => x.region === r)])} />;
    case "FX": return <QuoteBoard panel={panel} groups={currencyGroups()} />;
    case "COMD": return <QuoteBoard panel={panel} groups={commodityGroups()} />;
    case "RATES": return <QuoteBoard panel={panel} groups={[["US TREASURY YIELDS", rates]]} yields />;
    case "MOST": return <Movers panel={panel} />;
    case "HMAP": return <Heatmap panel={panel} />;
    case "TOP": return <News />;
    case "CN": return <News i={i} />;
    case "SECF": return <SecurityFinder panel={panel} initial={cmd.query} />;
    case "DEPTH": return isStreaming(i!) ? <Depth i={i!} /> : <Empty title="Depth is for live crypto" detail="Order books stream for Coinbase coins: try BTC DEPTH." />;
    case "TAS": return isStreaming(i!) ? <TimeAndSales i={i!} /> : <Empty title="Time & sales is for live crypto" detail="Trades stream for Coinbase coins: try ETH TAS." />;
    case "HELP": return <Help panel={panel} />;
  }
  return <Empty title={`${cmd.fn} is coming to the web`} detail={`${fn(cmd.fn).title} works in the Kestrel app for iPad and Mac and arrives on the web in the next phase.`} />;
}
