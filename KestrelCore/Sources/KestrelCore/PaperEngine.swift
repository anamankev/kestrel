import Foundation

/// Simulated execution. Money and quantities are `Decimal` so cash never drifts by float error.
public enum OrderType: Codable, Sendable, Equatable {
    case market
    case limit(Decimal)

    public var limitPrice: Decimal? { if case .limit(let p) = self { p } else { nil } }
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
    case invalidQuantity, invalidLimit, noMarket, insufficientCash(needed: Decimal, available: Decimal), insufficientPosition(Decimal)

    public var errorDescription: String? {
        switch self {
        case .invalidQuantity: "Quantity must be positive"
        case .invalidLimit: "Limit price must be positive"
        case .noMarket: "No market data for this security yet"
        case .insufficientCash(let n, let a): "Insufficient cash: need \(n.formatted(.currency(code: "USD"))), have \(a.formatted(.currency(code: "USD")))"
        case .insufficientPosition(let q): "Long-only account: you hold \(q)"
        }
    }
}

/// A long-only cash account with market and limit orders.
///
/// Pure value type: every state change goes through `submit`, `cancel` or `mark`, which makes it
/// deterministic to test and trivial to persist as JSON.
public struct PaperAccount: Codable, Sendable, Equatable {
    public static let startingCash: Decimal = 1_000_000

    public private(set) var cash: Decimal
    public private(set) var positions: [String: Position] = [:]
    public private(set) var orders: [Order] = []
    public private(set) var fills: [Fill] = []
    private var nextID = 1

    public init(cash: Decimal = PaperAccount.startingCash) { self.cash = cash }

    public var workingOrders: [Order] { orders.filter { $0.status == .working } }

    /// Cash committed to working buy limits, so they can't be double-spent.
    public var reservedCash: Decimal {
        workingOrders.filter { $0.side == .buy }.reduce(0) { $0 + $1.quantity * ($1.type.limitPrice ?? 0) }
    }
    public var buyingPower: Decimal { cash - reservedCash }

    private func reservedQuantity(_ symbol: String) -> Decimal {
        workingOrders.filter { $0.symbol == symbol && $0.side == .sell }.reduce(0) { $0 + $1.quantity }
    }

    /// Validates and enters an order. Marketable orders fill immediately at the touch.
    @discardableResult
    public mutating func submit(symbol: String, side: TradeSide, quantity: Decimal, type: OrderType,
                                touch: Touch?, now: Date = .now) throws(OrderReject) -> Order {
        guard quantity > 0 else { throw .invalidQuantity }
        if let lp = type.limitPrice, lp <= 0 { throw .invalidLimit }
        if type == .market, touch == nil { throw .noMarket }

        switch side {
        case .buy:
            let estimate = quantity * (type.limitPrice ?? touch!.executable(for: .buy))
            guard estimate <= buyingPower else { throw .insufficientCash(needed: estimate, available: buyingPower) }
        case .sell:
            let free = (positions[symbol]?.quantity ?? 0) - reservedQuantity(symbol)
            guard quantity <= free else { throw .insufficientPosition(free) }
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
            let o = orders[i]
            let px = touch.executable(for: o.side)
            let price: Decimal
            switch (o.type, o.side) {
            case (.market, _): price = px
            case (.limit(let l), .buy) where px <= l: price = px   // price improvement goes to the trader
            case (.limit(let l), .sell) where px >= l: price = px
            default: continue
            }
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
            // A limit's reservation is released by this fill, so check against cash itself.
            guard notional <= cash - (reservedCash - o.quantity * (o.type.limitPrice ?? 0)) else {
                orders[i].status = .rejected; orders[i].note = "Insufficient cash at fill"; orders[i].updated = now
                return nil
            }
            let qty = pos.quantity + o.quantity
            pos.averageCost = (pos.averageCost * pos.quantity + notional) / qty
            pos.quantity = qty
            cash -= notional
        case .sell:
            guard o.quantity <= pos.quantity else {
                orders[i].status = .rejected; orders[i].note = "Position no longer available"; orders[i].updated = now
                return nil
            }
            realized = (price - pos.averageCost) * o.quantity
            pos.quantity -= o.quantity
            pos.realized += realized
            cash += notional
            if pos.quantity == 0 { pos.averageCost = 0 }
        }
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
        positions.values.filter { $0.quantity > 0 }.sorted { $0.symbol < $1.symbol }
    }
    public var realizedPnL: Decimal { positions.values.reduce(0) { $0 + $1.realized } }

    /// Account value with positions marked at `marks` (falls back to cost when unmarked).
    public func equity(marks: [String: Decimal]) -> Decimal {
        cash + openPositions.reduce(0) { $0 + $1.quantity * (marks[$1.symbol] ?? $1.averageCost) }
    }
}
