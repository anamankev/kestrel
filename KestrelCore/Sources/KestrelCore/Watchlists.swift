import Foundation

// MARK: - Watchlists

/// A named, ordered list of data-source symbols (`AAPL`, `BTC-USD`, `^GSPC`).
public struct Watchlist: Codable, Sendable, Equatable, Identifiable {
    public static let maxSymbols = 100
    public static let maxNameLength = 24

    public let id: UUID
    public private(set) var name: String
    public private(set) var symbols: [String]

    public init(id: UUID = UUID(), name: String, symbols: [String] = []) {
        self.id = id
        self.name = Self.clean(name)
        self.symbols = []
        for s in symbols { add(s) }
    }

    static func clean(_ name: String) -> String {
        let t = name.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        return t.isEmpty ? "UNTITLED" : String(t.prefix(maxNameLength))
    }

    public mutating func rename(_ name: String) { self.name = Self.clean(name) }

    /// Appends a symbol. Returns false for duplicates or when the list is full.
    @discardableResult
    public mutating func add(_ symbol: String) -> Bool {
        guard !symbols.contains(symbol), symbols.count < Self.maxSymbols, !symbol.isEmpty else { return false }
        symbols.append(symbol)
        return true
    }

    public mutating func remove(_ symbol: String) { symbols.removeAll { $0 == symbol } }

    /// Moves a symbol up (negative) or down (positive), clamped to the list bounds.
    public mutating func move(_ symbol: String, by offset: Int) {
        guard let i = symbols.firstIndex(of: symbol) else { return }
        let j = min(max(i + offset, 0), symbols.count - 1)
        guard i != j else { return }
        symbols.insert(symbols.remove(at: i), at: j)
    }

    public static let core = Watchlist(name: "CORE", symbols: Universe.crypto.map(\.symbol) + Universe.equities.map(\.symbol))
}

// MARK: - Price alerts

public enum AlertCondition: Codable, Sendable, Equatable {
    /// Last price trades at or above the level.
    case above(Double)
    /// Last price trades at or below the level.
    case below(Double)
    /// Absolute day change reaches this percentage (e.g. 5 = ±5%).
    case movePercent(Double)

    public var label: String {
        switch self {
        case .above(let p): "LAST ≥ \(p.formatted(.number.precision(.significantDigits(1...10))))"
        case .below(let p): "LAST ≤ \(p.formatted(.number.precision(.significantDigits(1...10))))"
        case .movePercent(let x): "|CHG| ≥ \(x.formatted(.number.precision(.fractionLength(0...2))))%"
        }
    }
}

public struct PriceAlert: Codable, Sendable, Equatable, Identifiable {
    public let id: UUID
    public let symbol: String
    public let condition: AlertCondition
    public let created: Date
    public internal(set) var triggered: Date?
    public internal(set) var triggerPrice: Double?

    public var isActive: Bool { triggered == nil }
}

public enum AlertError: Error, Equatable, LocalizedError {
    case invalidLevel
    case alreadyThrough(Double)
    case tooMany

    public var errorDescription: String? {
        switch self {
        case .invalidLevel: "Enter a positive level (move % must be between 0 and 100)"
        case .alreadyThrough(let p): "Price is already through that level (last \(p.formatted()))"
        case .tooMany: "Alert limit reached: cancel some first"
        }
    }
}

/// Active alerts plus history. Each alert fires once, on the first quote that satisfies it.
public struct AlertBook: Codable, Sendable, Equatable {
    public static let maxActive = 200
    public static let maxHistory = 200

    public private(set) var alerts: [PriceAlert] = []

    public init() {}

    public var active: [PriceAlert] { alerts.filter(\.isActive) }
    public var history: [PriceAlert] {
        alerts.filter { !$0.isActive }.sorted { ($0.triggered ?? .distantPast) > ($1.triggered ?? .distantPast) }
    }
    public var watchedSymbols: Set<String> { Set(active.map(\.symbol)) }

    /// Adds an alert. Level alerts must be on the far side of the current price, so a new alert
    /// never fires instantly by accident.
    @discardableResult
    public mutating func add(symbol: String, condition: AlertCondition, last: Double?, now: Date = .now) throws(AlertError) -> PriceAlert {
        guard active.count < Self.maxActive else { throw .tooMany }
        switch condition {
        case .above(let p), .below(let p):
            guard p.isFinite, p > 0 else { throw .invalidLevel }
        case .movePercent(let x):
            guard x.isFinite, x > 0, x <= 100 else { throw .invalidLevel }
        }
        if let last {
            switch condition {
            case .above(let p) where last >= p: throw .alreadyThrough(last)
            case .below(let p) where last <= p: throw .alreadyThrough(last)
            default: break
            }
        }
        let a = PriceAlert(id: UUID(), symbol: symbol, condition: condition, created: now, triggered: nil, triggerPrice: nil)
        alerts.append(a)
        return a
    }

    public mutating func cancel(_ id: UUID) { alerts.removeAll { $0.id == id && $0.isActive } }

    public mutating func clearHistory() { alerts.removeAll { !$0.isActive } }

    /// Checks a fresh quote against every active alert on `symbol`; returns the ones that fired.
    public mutating func evaluate(symbol: String, last: Double, changePercent: Double?, now: Date = .now) -> [PriceAlert] {
        var fired: [PriceAlert] = []
        for i in alerts.indices where alerts[i].symbol == symbol && alerts[i].isActive {
            let hit: Bool = switch alerts[i].condition {
            case .above(let p): last >= p
            case .below(let p): last <= p
            case .movePercent(let x): changePercent.map { abs($0) >= x } ?? false
            }
            if hit {
                alerts[i].triggered = now
                alerts[i].triggerPrice = last
                fired.append(alerts[i])
            }
        }
        if !fired.isEmpty {
            let old = history.dropFirst(Self.maxHistory).map(\.id)
            alerts.removeAll { old.contains($0.id) }
        }
        return fired
    }
}
