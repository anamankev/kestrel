import Foundation

/// Simulated execution. Money and quantities are `Decimal` so cash never drifts by float error.
public enum OrderType: Codable, Sendable, Equatable {
    case market
    case limit(Decimal)
    /// Becomes a market order once the last trade reaches the stop (buy: at or above, sell: at or below).
    case stop(Decimal)
    /// Becomes a limit order at `limit` once the last trade reaches `stop`.
    case stopLimit(stop: Decimal, limit: Decimal)

    public var limitPrice: Decimal? {
        switch self {
        case .limit(let p), .stopLimit(_, let p): p
        default: nil
        }
    }
    public var stopPrice: Decimal? {
        switch self {
        case .stop(let s), .stopLimit(let s, _): s
        default: nil
        }
    }
    /// Price used to reserve cash for a working buy: the limit, else the stop.
    public var reservePrice: Decimal? { limitPrice ?? stopPrice }

}

public enum OrderStatus: String, Codable, Sendable { case working = "WORKING", filled = "FILLED", cancelled = "CANCELLED", rejected = "REJECTED" }

public struct Order: Codable, Sendable, Identifiable, Equatable {
    public let id: Int
    public let symbol: String
    public let side: TradeSide
    public let quantity: Decimal
    public let type: OrderType
    public let created: Date
    public var status: OrderStatus
    public var fillPrice: Decimal?
    public var updated: Date
    public var note: String?
    /// Set when a stop's trigger price traded; nil for non-stop orders and for older saves.
    public var triggered: Bool? = nil

    /// Whether the order currently rests as a stop waiting for its trigger.
    public var isPendingStop: Bool { type.stopPrice != nil && triggered != true }
}

public struct Fill: Codable, Sendable, Identifiable, Equatable {
    public let id: Int
    public let orderID: Int
    public let symbol: String
    public let side: TradeSide
    public let quantity: Decimal
    public let price: Decimal
    public let time: Date
    /// P&L realised by this fill (sells only, long-only book).
    public let realized: Decimal
}

public struct Position: Codable, Sendable, Equatable {
    public let symbol: String
    public var quantity: Decimal
    public var averageCost: Decimal
    public var realized: Decimal

    public func unrealized(mark: Decimal) -> Decimal { (mark - averageCost) * quantity }
}

/// Top of book used to price fills: buys lift the ask, sells hit the bid, falling back to last.
public struct Touch: Sendable, Equatable {
    public var bid: Decimal?
    public var ask: Decimal?
    public var last: Decimal

    public init(bid: Decimal? = nil, ask: Decimal? = nil, last: Decimal) {
        self.bid = bid; self.ask = ask; self.last = last
    }

    public init?(market bid: Double?, ask: Double?, last: Double?) {
        guard let last, last.isFinite, last > 0 else { return nil }
        self.init(bid: bid.flatMap(Decimal.price), ask: ask.flatMap(Decimal.price), last: Decimal.price(last)!)
    }

    func executable(for side: TradeSide) -> Decimal { side == .buy ? (ask ?? last) : (bid ?? last) }
}

extension Decimal {
    /// Converts a market-data double to a Decimal rounded to 8 places (crypto tick precision).
    public static func price(_ d: Double) -> Decimal? {
        guard d.isFinite else { return nil }
        var raw = Decimal(d), out = Decimal()
        NSDecimalRound(&out, &raw, 8, .plain)
        return out
    }

    public var double: Double { NSDecimalNumber(decimal: self).doubleValue }
}

public enum OrderReject: Error, Equatable, LocalizedError {
    case invalidQuantity, invalidLimit, invalidStop, stopThroughMarket(TradeSide), noMarket, insufficientCash(needed: Decimal, available: Decimal), insufficientPosition(Decimal)
    case insufficientMargin(needed: Decimal, available: Decimal)

    public var errorDescription: String? {
        switch self {
        case .invalidQuantity: "Quantity must be positive"
        case .invalidLimit: "Limit price must be positive"
        case .invalidStop: "Stop price must be positive"
        case .stopThroughMarket(let side): side == .buy ? "Buy stop must be above the last price" : "Sell stop must be below the last price"
        case .noMarket: "No market data for this security yet"
        case .insufficientCash(let n, let a): "Insufficient cash: need \(n.formatted(.currency(code: "USD"))), have \(a.formatted(.currency(code: "USD")))"
        case .insufficientPosition(let q): "Shorting is off for this account: you hold \(q)"
        case .insufficientMargin(let n, let a): "Insufficient margin to short: need \(n.formatted(.currency(code: "USD"))), have \(a.formatted(.currency(code: "USD")))"
        }
    }
}

/// A margin account with market, limit, stop and stop-limit orders, long and short.
///
/// Positions are signed (negative = short). Short sales credit the proceeds to cash, and a
/// Reg T-style initial requirement of 150% of short value (the proceeds plus 50%) is held out of
/// buying power. Pure value type: every state change goes through `submit`, `cancel` or `mark`,
/// which makes it deterministic to test and trivial to persist as JSON.
public struct PaperAccount: Codable, Sendable, Equatable {
    public static let startingCash: Decimal = 1_000_000
    public static let shortRequirement: Decimal = 1.5
    public static let maxQuantity: Decimal = 1_000_000_000
    public static let maxPrice: Decimal = 1_000_000_000_000

    public private(set) var cash: Decimal
    public private(set) var positions: [String: Position] = [:]
    public private(set) var orders: [Order] = []
    public private(set) var fills: [Fill] = []
    private var nextID = 1
    public var allowShort: Bool

    public init(cash: Decimal = PaperAccount.startingCash, allowShort: Bool = true) {
        self.cash = cash
        self.allowShort = allowShort
    }

    // Older saved accounts predate `allowShort`; decode it optionally so they still load.
    private enum CodingKeys: String, CodingKey { case cash, positions, orders, fills, nextID, allowShort }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        cash = try c.decode(Decimal.self, forKey: .cash)
        positions = try c.decode([String: Position].self, forKey: .positions)
        orders = try c.decode([Order].self, forKey: .orders)
        fills = try c.decode([Fill].self, forKey: .fills)
        nextID = try c.decode(Int.self, forKey: .nextID)
        allowShort = try c.decodeIfPresent(Bool.self, forKey: .allowShort) ?? true
    }

    public var workingOrders: [Order] { orders.filter { $0.status == .working } }

    /// Cash committed to working buy limits, so they can't be double-spent.
    public var reservedCash: Decimal {
        workingOrders.filter { $0.side == .buy }.reduce(0) { $0 + $1.quantity * ($1.type.reservePrice ?? 0) }
    }
    /// Margin held against open shorts, valued at their average sale price.
    public var shortMarginHeld: Decimal {
        positions.values.filter { $0.quantity < 0 }.reduce(0) { $0 + (-$1.quantity) * $1.averageCost * Self.shortRequirement }
    }
    public var buyingPower: Decimal { cash - reservedCash - shortMarginHeld }

    private func reservedQuantity(_ symbol: String) -> Decimal {
        workingOrders.filter { $0.symbol == symbol && $0.side == .sell }.reduce(0) { $0 + $1.quantity }
    }

    /// Validates and enters an order. Marketable orders fill immediately at the touch.
    @discardableResult
    public mutating func submit(symbol: String, side: TradeSide, quantity: Decimal, type: OrderType,
                                touch: Touch?, now: Date = .now) throws(OrderReject) -> Order {
        // Bounds stop absurd input (fat fingers, pasted garbage) before it can reach the book.
        guard quantity > 0, quantity <= Self.maxQuantity else { throw .invalidQuantity }
        for p in [type.limitPrice, type.stopPrice].compactMap({ $0 }) where p > Self.maxPrice { throw .invalidLimit }
        if let lp = type.limitPrice, lp <= 0 { throw .invalidLimit }
        if let sp = type.stopPrice {
            guard sp > 0 else { throw .invalidStop }
            // A stop already through the market would fill at once: almost always a typo.
            if let last = touch?.last, side == .buy ? sp <= last : sp >= last { throw .stopThroughMarket(side) }
        }
        if type == .market, touch == nil { throw .noMarket }

        let px = type.reservePrice ?? touch!.executable(for: side)
        let held = positions[symbol]?.quantity ?? 0
        switch side {
        case .buy:
            // Covering a short releases its margin, so only the part that opens/extends a long needs cash.
            let covering = min(quantity, max(-held, 0))
            let released = covering * (positions[symbol]?.averageCost ?? 0) * Self.shortRequirement
            let estimate = quantity * px
            guard estimate <= buyingPower + released else {
                throw .insufficientCash(needed: estimate, available: buyingPower + released)
            }
        case .sell:
            let free = max(held, 0) - reservedQuantity(symbol)
            let shortPart = quantity - max(free, 0)
            if shortPart > 0 {
                // Writing options needs a portfolio margin model; options are long-premium only.
                guard allowShort, Deribit.parse(symbol) == nil else { throw .insufficientPosition(max(free, 0)) }
                let needed = shortPart * px * (Self.shortRequirement - 1)  // proceeds cover the other 100%
                guard needed <= buyingPower else { throw .insufficientMargin(needed: needed, available: buyingPower) }
            }
        }

        var order = Order(id: nextID, symbol: symbol, side: side, quantity: quantity, type: type,
                          created: now, status: .working, fillPrice: nil, updated: now, note: nil)
        nextID += 1
        orders.append(order)
        if let touch { _ = mark(symbol: symbol, touch: touch, now: now) }
        order = orders.first { $0.id == order.id }!
        return order
    }

    public mutating func cancel(_ id: Int, now: Date = .now) {
        guard let i = orders.firstIndex(where: { $0.id == id && $0.status == .working }) else { return }
        orders[i].status = .cancelled
        orders[i].updated = now
    }

    /// Feeds a new touch for `symbol`; fills every working order it crosses. Returns new fills.
    @discardableResult
    public mutating func mark(symbol: String, touch: Touch, now: Date = .now) -> [Fill] {
        var new: [Fill] = []
        for i in orders.indices where orders[i].symbol == symbol && orders[i].status == .working {
            if orders[i].isPendingStop, let sp = orders[i].type.stopPrice {
                // Stops trigger on the last trade, not the quote, like exchange stop orders.
                guard orders[i].side == .buy ? touch.last >= sp : touch.last <= sp else { continue }
                orders[i].triggered = true
                orders[i].updated = now
                orders[i].note = "Triggered at \(touch.last.formatted(.number.precision(.fractionLength(0...8))))"
            }
            let o = orders[i]
            let px = touch.executable(for: o.side)
            let limit = o.type.limitPrice
            switch o.side {
            case _ where limit == nil: break                         // market, or a triggered stop
            case .buy where px <= limit!: break                      // price improvement goes to the trader
            case .sell where px >= limit!: break
            default: continue
            }
            let price = px
            if let fill = execute(i, price: price, now: now) { new.append(fill) }
        }
        return new
    }

    private mutating func execute(_ i: Int, price: Decimal, now: Date) -> Fill? {
        let o = orders[i]
        let notional = o.quantity * price
        var realized: Decimal = 0
        var pos = positions[o.symbol] ?? Position(symbol: o.symbol, quantity: 0, averageCost: 0, realized: 0)

        switch o.side {
        case .buy:
            // A limit's reservation is released by this fill, and covering releases short margin.
            let covering = min(o.quantity, max(-pos.quantity, 0))
            let available = cash - (reservedCash - o.quantity * (o.type.reservePrice ?? 0)) - shortMarginHeld
                + covering * pos.averageCost * Self.shortRequirement
            guard notional <= available else {
                orders[i].status = .rejected; orders[i].note = "Insufficient cash at fill"; orders[i].updated = now
                return nil
            }
            if covering > 0 {
                realized = (pos.averageCost - price) * covering
                pos.quantity += covering
            }
            let opening = o.quantity - covering
            if opening > 0 {
                let q = pos.quantity + opening
                pos.averageCost = (pos.averageCost * pos.quantity + opening * price) / q
                pos.quantity = q
            }
            cash -= notional
        case .sell:
            let closing = min(o.quantity, max(pos.quantity, 0))
            let opening = o.quantity - closing
            if opening > 0, !allowShort || Deribit.parse(o.symbol) != nil {
                orders[i].status = .rejected; orders[i].note = "Position no longer available"; orders[i].updated = now
                return nil
            }
            if closing > 0 {
                realized = (price - pos.averageCost) * closing
                pos.quantity -= closing
            }
            if opening > 0 {
                let shortQty = -pos.quantity + opening
                pos.averageCost = ((-pos.quantity) * pos.averageCost + opening * price) / shortQty
                pos.quantity = -shortQty
            }
            cash += notional
        }
        pos.realized += realized
        if pos.quantity == 0 { pos.averageCost = 0 }
        positions[o.symbol] = pos
        orders[i].status = .filled
        orders[i].fillPrice = price
        orders[i].updated = now
        let fill = Fill(id: fills.count + 1, orderID: o.id, symbol: o.symbol, side: o.side,
                        quantity: o.quantity, price: price, time: now, realized: realized)
        fills.append(fill)
        return fill
    }

    public var openPositions: [Position] {
        positions.values.filter { $0.quantity != 0 }.sorted { $0.symbol < $1.symbol }
    }
    public var realizedPnL: Decimal { positions.values.reduce(0) { $0 + $1.realized } }

    /// Account value with positions marked at `marks` (falls back to cost when unmarked).
    public func equity(marks: [String: Decimal]) -> Decimal {
        cash + openPositions.reduce(0) { $0 + $1.quantity * (marks[$1.symbol] ?? $1.averageCost) }
    }
}
