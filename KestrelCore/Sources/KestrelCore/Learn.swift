import Foundation

/// LEARN: guided drills. Each drill opens a real function beside the lesson and asks a question the screen
/// teaches; a module's badge is earned when every drill in it is answered correctly. Answers don't depend on
/// live numbers, so they stay right as markets move. The web copy is generated from the JSON below by
/// web/scripts/gen-learn.py (`npm run learn`).
public enum Learn {
    public struct Drill: Codable, Sendable, Equatable, Identifiable {
        public let id: String
        /// The command the drill opens, e.g. "AAPL FA".
        public let command: String
        /// What to look at on that screen.
        public let look: String
        public let question: String
        public let choices: [String]
        public let answer: Int
        /// Shown after answering.
        public let why: String
    }

    public struct Module: Codable, Sendable, Equatable, Identifiable {
        public let id: String
        public let title: String
        public let badge: String
        public let summary: String
        public let drills: [Drill]
    }

    public static let modules: [Module] = (try? JSONDecoder().decode([Module].self, from: Data(json.utf8))) ?? []

    /// Drills answered correctly in a module.
    public static func done(_ m: Module, _ completed: Set<String>) -> Int { m.drills.filter { completed.contains($0.id) }.count }
    public static func earned(_ m: Module, _ completed: Set<String>) -> Bool { done(m, completed) == m.drills.count }
    /// The first drill not yet answered correctly, or the first drill when the module is complete.
    public static func next(_ m: Module, _ completed: Set<String>) -> Int { m.drills.firstIndex { !completed.contains($0.id) } ?? 0 }
    /// Display order of a drill's choices: shuffled the same way on every device (FNV-1a of id and index),
    /// so the right answer isn't always first. Mirrors choiceOrder in web/src/core/learn.ts.
    public static func order(_ d: Drill) -> [Int] {
        func fnv(_ s: String) -> UInt32 { s.utf8.reduce(2_166_136_261) { ($0 ^ UInt32($1)) &* 16_777_619 } }
        return d.choices.indices.sorted { (fnv("\(d.id)#\($0)"), $0) < (fnv("\(d.id)#\($1)"), $1) }
    }

    /// Only known drill ids survive (a stored list from an older or tampered copy is filtered).
    public static func sanitize(_ ids: some Sequence<String>) -> Set<String> {
        let known = Set(modules.flatMap { $0.drills.map(\.id) })
        return Set(ids).intersection(known)
    }

    // BEGIN CURRICULUM
    static let json = #"""
    [
      {"id": "econ", "title": "ECONOMICS", "badge": "ECONOMIST", "summary": "Policy rates, inflation, growth and what the yield curve says about them.", "drills": [
        {"id": "econ.fed", "command": "ECO", "look": "The FED FUNDS (EFFR) tile: the effective rate and the Fed's target range under it.",
         "question": "The effective fed funds rate sits inside the target range. What does that tell you?",
         "choices": ["The Fed is hitting the target it set", "The Fed has lost control of rates", "The Fed is about to cut", "Banks have stopped lending to each other"], "answer": 0,
         "why": "The Fed sets a range and steers the overnight rate banks charge each other into it. Inside the range means policy is working as set."},
        {"id": "econ.cpi", "command": "ECO", "look": "The INFLATION table: CPI inflation (YoY) and Core CPI ex food and energy.",
         "question": "CPI inflation 'YoY' compares this month's price level with…",
         "choices": ["The same month a year earlier", "Last month", "The Fed's 2% target", "Core CPI"], "answer": 0,
         "why": "Year-over-year compares like-for-like months, which removes seasonal swings. Core strips out food and energy, the most volatile parts."},
        {"id": "econ.gdp", "command": "ECST JAPAN", "look": "Japan's profile: Real GDP growth beside GDP in current U.S. dollars.",
         "question": "Real GDP growth differs from nominal growth because it removes…",
         "choices": ["Inflation", "Population growth", "Exchange-rate moves", "Government debt"], "answer": 0,
         "why": "Real growth is measured at constant prices, so it counts more goods and services, not higher prices. Per-capita figures remove population."},
        {"id": "econ.curve", "command": "GC", "look": "The 10Y – 2Y SPREAD tile and its history chart.",
         "question": "When the 10-year yield is below the 2-year yield, the curve is…",
         "choices": ["Inverted", "Steep", "Normal", "Humped"], "answer": 0,
         "why": "Investors usually demand more to lend for longer. An inverted curve means markets expect short rates to fall, which has preceded most U.S. recessions."}
      ]},
      {"id": "fi", "title": "FIXED INCOME", "badge": "BOND DESK", "summary": "Prices, yields, duration and convexity, priced on a real calculator.", "drills": [
        {"id": "fi.inverse", "command": "YAS", "look": "The YIELD SCENARIOS table: yield shifts and the price beside each.",
         "question": "When a bond's yield rises, its price…",
         "choices": ["Falls", "Rises", "Stays at 100", "Rises by the coupon"], "answer": 0,
         "why": "A bond's cash flows are fixed. A higher yield discounts them more heavily, so the same payments are worth less today."},
        {"id": "fi.duration", "command": "YAS", "look": "MODIFIED DURATION, then the +100 bp row's % CHANGE.",
         "question": "For a 1% (100 bp) rise in yield, the price falls by roughly…",
         "choices": ["The modified duration, in percent", "The coupon rate", "Exactly 1%", "The years to maturity, in dollars"], "answer": 0,
         "why": "Modified duration is the percentage price change per 1% move in yield. A duration of 7.8 means about −7.8% for +100 bp."},
        {"id": "fi.dv01", "command": "YAS", "look": "The DV01 tile, in dollars on the face amount.",
         "question": "DV01 measures…",
         "choices": ["The dollar change in value for a 1 bp move in yield", "The daily coupon income", "The bid-ask spread", "Default risk"], "answer": 0,
         "why": "DV01 (dollar value of an 01) is how traders size rate risk: it adds up across bonds, so a desk can hedge a whole book with one number."},
        {"id": "fi.convexity", "command": "YAS", "look": "The −100 bp and +100 bp rows: compare the size of the gain and the loss, and the ESTIMATE column.",
         "question": "The gain at −100 bp is larger than the loss at +100 bp. Why?",
         "choices": ["Convexity: the price-yield curve bends", "Accrued interest", "The spread to Treasuries", "The coupon is paid twice a year"], "answer": 0,
         "why": "Price is a curved function of yield. Duration is the straight-line slope; convexity adds the curvature, which is why the estimate matches the full reprice."}
      ]},
      {"id": "fx", "title": "CURRENCIES", "badge": "FX TRADER", "summary": "How quotes work, which side strengthens, and why rates drive currencies.", "drills": [
        {"id": "fx.quote", "command": "FX", "look": "EURUSD in the major pairs.",
         "question": "EURUSD at 1.0900 means…",
         "choices": ["One euro buys 1.09 dollars", "One dollar buys 1.09 euros", "The euro rose 1.09% today", "The spread is 1.09 pips"], "answer": 0,
         "why": "A pair quotes the second currency per one unit of the first (the base). EUR is the base in EURUSD."},
        {"id": "fx.yen", "command": "FX", "look": "USDJPY and its change today.",
         "question": "USDJPY rises from 150 to 160. The yen has…",
         "choices": ["Weakened", "Strengthened", "Not changed against the dollar", "Been revalued by Japan"], "answer": 0,
         "why": "Each dollar now buys more yen, so each yen is worth less. When the base currency rises, the quote currency falls."},
        {"id": "fx.pip", "command": "FX", "look": "The decimal places on EURUSD and USDJPY.",
         "question": "A pip on EURUSD is…",
         "choices": ["0.0001", "0.01", "1 dollar", "1% of the price"], "answer": 0,
         "why": "Most pairs quote to four decimals, so a pip is 0.0001. Yen pairs quote to two, so a USDJPY pip is 0.01."},
        {"id": "fx.carry", "command": "RATES", "look": "U.S. Treasury yields: what dollar cash earns today.",
         "question": "A carry trade borrows in a low-rate currency and…",
         "choices": ["Invests in a higher-rate currency to earn the difference", "Buys gold", "Shorts the higher-rate currency", "Holds cash at zero"], "answer": 0,
         "why": "Carry earns the interest-rate gap. The risk is the exchange rate: a sharp move in the funding currency can wipe out years of carry."}
      ]},
      {"id": "eq", "title": "EQUITIES", "badge": "ANALYST", "summary": "Reading financials, valuing against peers, and measuring risk.", "drills": [
        {"id": "eq.margin", "command": "AAPL FA", "look": "Revenue and net income in the annual figures.",
         "question": "Net margin is…",
         "choices": ["Net income divided by revenue", "Revenue minus costs", "Revenue growth", "Earnings per share"], "answer": 0,
         "why": "Net margin is the share of each sales dollar kept as profit after all costs, interest and taxes."},
        {"id": "eq.pe", "command": "AAPL RV", "look": "The P/E VS PEERS tile and the PEER MEDIAN row.",
         "question": "A P/E premium of +50% to peers means investors pay…",
         "choices": ["50% more per dollar of earnings than the median peer", "50% more for the shares than last year", "A 50% dividend", "50% less for growth"], "answer": 0,
         "why": "P/E is price over earnings. A premium usually means the market expects faster growth or steadier profits than peers."},
        {"id": "eq.beta", "command": "NVDA BETA", "look": "The beta against SPX (the S&P 500), from the regression of returns.",
         "question": "A beta of 1.5 means the stock has tended to move…",
         "choices": ["About 1.5% for each 1% move in the market", "1.5% a day", "1.5 times its own average", "Against the market"], "answer": 0,
         "why": "Beta is the slope of the stock's returns on the market's. Above 1 amplifies market moves; it says nothing about risk unrelated to the market."},
        {"id": "eq.seas", "command": "SPY SEAS", "look": "The % UP column in the month table.",
         "question": "SEAS's % UP column shows…",
         "choices": ["The share of years that month had a positive return", "The average gain", "The chance the month rises next year", "Trading volume"], "answer": 0,
         "why": "It counts history, not a forecast. With 10 to 20 years per month, a few big years can skew the average, so check the median too."}
      ]}
    ]
    """#
    // END CURRICULUM
}
