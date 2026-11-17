import SwiftUI
import KestrelCore

/// GP: candlestick chart drawn in a single Canvas pass (one draw call per layer, no per-candle
/// views), so a few hundred candles with studies keep up with a 120 Hz display. Crypto charts
/// extend the last candle with live ticks.
struct ChartView: View {
    let instrument: Instrument
    @Environment(MarketStore.self) private var market
    @Environment(Theme.self) private var theme

    @AppStorage("gp.range") private var range: ChartRange = .d1
    @AppStorage("gp.sma") private var showSMA = true
    @AppStorage("gp.bb") private var showBB = false
    @AppStorage("gp.vwap") private var showVWAP = false
    @AppStorage("gp.rsi") private var showRSI = true
    @AppStorage("gp.line") private var lineStyle = false

    @State private var candles: [Candle] = []
    @State private var loading = false
    @State private var failed = false
    @State private var hover: Int?
    @State private var zoom: CGFloat = 1
    @State private var pinchBase: CGFloat = 1

    enum Mode: String, CaseIterable { case cross = "CROSS", pan = "PAN", draw = "DRAW" }
    @State private var mode = Mode.cross
    @State private var panOffset = 0
    @State private var panStart = 0
    @State private var compare: Instrument?
    @State private var compareCandles: [Candle] = []
    @State private var lines: [TrendLine] = []
    @State private var draft: TrendLine?

    static let compareChoices = ["SPX", "CCMP", "QQQ", "BTC", "ETH", "GC1", "CL1"]

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            readout
            GeometryReader { g in
                let data = visible
                let comparing = compare != nil && !compareCandles.isEmpty
                let (shown, cmp) = comparing ? rebased(data) : (data, [])
                ZStack {
                    if data.count > 1 {
                        ChartCanvas(candles: shown, instrument: instrument, theme: theme, range: range,
                                    showSMA: showSMA && !comparing, showBB: showBB && !comparing,
                                    showVWAP: showVWAP && range.isIntraday && !comparing,
                                    showRSI: showRSI, line: lineStyle || comparing, hover: hover,
                                    previousClose: comparing ? nil : previousClose,
                                    compare: cmp, compareLabel: compare?.ticker, percent: comparing,
                                    lines: lines, draft: draft)
                    } else if loading {
                        ProgressView().tint(Theme.accent)
                    } else {
                        EmptyNote(title: failed ? "Chart data unavailable" : "No data",
                                  detail: failed ? "The free data source didn't answer. Retrying shortly." : nil)
                    }
                }
                .contentShape(.rect)
                .onContinuousHover { phase in
                    if case .active(let p) = phase { hover = index(at: p.x, width: g.size.width, count: data.count) } else { hover = nil }
                }
                .gesture(DragGesture(minimumDistance: 0)
                    .onChanged { v in
                        switch mode {
                        case .cross:
                            hover = index(at: v.location.x, width: g.size.width, count: data.count)
                        case .pan:
                            let step = (g.size.width - ChartCanvas.axisWidth) / CGFloat(max(data.count, 1))
                            panOffset = max(0, panStart + Int((v.translation.width / step).rounded()))
                        case .draw:
                            guard !comparing, data.count > 1 else { return }
                            let sc = ChartScale(size: g.size, candles: data, showRSI: showRSI,
                                                bands: showBB ? Indicators.bollinger(data.map(\.close)) : [], previousClose: previousClose)
                            draft = TrendLine(t1: sc.time(atX: v.startLocation.x, in: data), p1: sc.price(atY: v.startLocation.y),
                                              t2: sc.time(atX: v.location.x, in: data), p2: sc.price(atY: v.location.y))
                        }
                    }
                    .onEnded { v in
                        switch mode {
                        case .cross: hover = nil
                        case .pan: panStart = panOffset
                        case .draw:
                            if let d = draft, hypot(v.translation.width, v.translation.height) > 12 { lines.append(d); saveLines() }
                            draft = nil
                        }
                    })
                .simultaneousGesture(MagnifyGesture()
                    .onChanged { zoom = min(max(pinchBase * $0.magnification, 1), 8) }
                    .onEnded { _ in pinchBase = zoom })
            }
        }
        .task(id: range) { panOffset = 0; panStart = 0; await load(loop: true) }
        .task(id: "\(compare?.symbol ?? "")|\(range.rawValue)") {
            compareCandles = []
            guard let c = compare else { return }
            compareCandles = (try? await market.candles(for: c, range: range)) ?? []
        }
        .onAppear(perform: loadLines)
    }

    private var previousClose: Double? { range == .d1 ? market.quotes[instrument.symbol]?.previousClose : nil }

    private func rebased(_ data: [Candle]) -> ([Candle], [Double?]) {
        let r = Indicators.rebase(data, against: compareCandles)
        return (r.main, r.other)
    }

    private var linesKey: String { "gp.lines.\(instrument.symbol)" }
    private func loadLines() {
        lines = (UserDefaults.standard.data(forKey: linesKey)).flatMap { try? JSONDecoder().decode([TrendLine].self, from: $0) } ?? []
    }
    private func saveLines() {
        UserDefaults.standard.set(try? JSONEncoder().encode(Array(lines.suffix(50))), forKey: linesKey)
    }

    /// Live-extended and zoomed candle window.
    private var visible: [Candle] {
        var c = candles
        if instrument.isStreaming, let q = market.quotes[instrument.symbol], var last = c.last {
            let g = TimeInterval(range.coinbase.granularity)
            if q.time >= last.time.addingTimeInterval(g) {
                let t = Date(timeIntervalSince1970: (q.time.timeIntervalSince1970 / g).rounded(.down) * g)
                c.append(Candle(time: t, open: last.close, high: max(last.close, q.last), low: min(last.close, q.last), close: q.last, volume: 0))
            } else {
                last.close = q.last
                last.high = max(last.high, q.last)
                last.low = min(last.low, q.last)
                c[c.count - 1] = last
            }
        }
        let n = min(max(Int(CGFloat(c.count) / zoom), 20), c.count)
        let off = min(panOffset, max(c.count - n, 0))
        let end = c.count - off
        return Array(c[max(end - n, 0)..<end])
    }

    private func index(at x: CGFloat, width: CGFloat, count: Int) -> Int? {
        let plot = width - ChartCanvas.axisWidth
        guard count > 0, x >= 0, x <= plot else { return nil }
        return min(Int(x / plot * CGFloat(count)), count - 1)
    }

    private func load(loop: Bool) async {
        repeat {
            loading = candles.isEmpty
            do {
                candles = try await market.candles(for: instrument, range: range)
                failed = false
            } catch {
                failed = candles.isEmpty
            }
            loading = false
            try? await Task.sleep(for: .seconds(instrument.isStreaming ? 120 : 60))
        } while loop && !Task.isCancelled
    }

    private var toolbar: some View {
        HStack(spacing: 4) {
            ForEach(ChartRange.allCases) { r in
                chip(r.rawValue, on: range == r) { range = r; zoom = 1; pinchBase = 1 }
            }
            Theme.rule.frame(width: 1, height: 14).padding(.horizontal, 4)
            chip(lineStyle ? "LINE" : "OHLC", on: true) { lineStyle.toggle() }
            chip("SMA 20/50", on: showSMA) { showSMA.toggle() }
            chip("BOLL", on: showBB) { showBB.toggle() }
            if range.isIntraday { chip("VWAP", on: showVWAP) { showVWAP.toggle() } }
            chip("RSI", on: showRSI) { showRSI.toggle() }
            Theme.rule.frame(width: 1, height: 14).padding(.horizontal, 4)
            ForEach(Mode.allCases, id: \.self) { m in chip(m.rawValue, on: mode == m) { mode = m; hover = nil } }
            if !lines.isEmpty { chip("CLR \(lines.count)", on: false) { lines = []; saveLines() } }
            Menu {
                Button("None") { compare = nil }
                ForEach(Self.compareChoices.filter { $0 != instrument.ticker }, id: \.self) { t in
                    Button(t) { compare = Universe.all.first { $0.ticker == t } }
                }
            } label: {
                Text(compare.map { "VS \($0.ticker)" } ?? "VS…").font(.mono(10, .bold))
                    .foregroundStyle(compare == nil ? Theme.dim : Theme.canvas)
                    .padding(.horizontal, 7).frame(height: 20)
                    .background(compare == nil ? Theme.header : Theme.warn, in: .rect(cornerRadius: 2))
            }
            .menuStyle(.button).buttonStyle(.plain).fixedSize()
            if panOffset > 0 { chip("⇥ LIVE", on: false) { panOffset = 0; panStart = 0 } }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 6).padding(.vertical, 4)
    }

    private var readout: some View {
        let data = visible
        let c = hover.flatMap { data[safe: $0] } ?? data.last
        let ref = hover.flatMap { $0 > 0 ? data[$0 - 1].close : nil } ?? data.first?.open
        return HStack(spacing: 10) {
            if let c {
                Text(c.time.formatted(range.isIntraday ? .dateTime.month(.abbreviated).day().hour().minute() : .dateTime.year().month(.abbreviated).day()))
                    .foregroundStyle(Theme.dim)
                field("O", c.open); field("H", c.high); field("L", c.low); field("C", c.close)
                if c.volume > 0 { Text("\(Text("V ").foregroundStyle(Theme.label))\(Text(Fmt.compact(c.volume)).foregroundStyle(Theme.text))") }
                if let ref, ref != 0 {
                    Text(Fmt.pct((c.close - ref) / ref * 100)).foregroundStyle(theme.tint(c.close - ref))
                }
            }
            Spacer()
        }
        .font(.mono(10, .medium))
        .monospacedDigit()
        .lineLimit(1)
        .padding(.horizontal, 8)
        .frame(height: 18)
    }

    private func field(_ k: String, _ v: Double) -> Text {
        Text("\(Text(k + " ").foregroundStyle(Theme.label))\(Text(Fmt.price(v, instrument.assetClass)).foregroundStyle(Theme.text))")
    }

    private func chip(_ t: String, on: Bool, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(t).font(.mono(10, .bold))
                .foregroundStyle(on ? Theme.canvas : Theme.dim)
                .padding(.horizontal, 7).frame(height: 20)
                .background(on ? Theme.accent : Theme.header, in: .rect(cornerRadius: 2))
        }
        .buttonStyle(.plain)
    }
}

struct ChartCanvas: View {
    nonisolated static let axisWidth: CGFloat = 68
    let candles: [Candle]
    let instrument: Instrument
    let theme: Theme
    let range: ChartRange
    let showSMA: Bool
    let showBB: Bool
    let showVWAP: Bool
    let showRSI: Bool
    let line: Bool
    let hover: Int?
    let previousClose: Double?
    var compare: [Double?] = []
    var compareLabel: String? = nil
    var percent = false
    var lines: [TrendLine] = []
    var draft: TrendLine? = nil

    var body: some View {
        let closes = candles.map(\.close)
        let sma20 = showSMA ? Indicators.sma(closes, period: 20) : []
        let sma50 = showSMA ? Indicators.sma(closes, period: 50) : []
        let bb = showBB ? Indicators.bollinger(closes) : []
        let vwap = showVWAP ? Indicators.vwap(candles) : []
        let rsi = showRSI ? Indicators.rsi(closes) : []
        Canvas { ctx, size in
            let up = theme.up, down = theme.down
            let sc = ChartScale(size: size, candles: candles, showRSI: showRSI, bands: bb,
                                previousClose: previousClose, extra: compare.compactMap { $0 })
            let plotW = sc.plotW, timeAxis = sc.timeAxis, rsiH = sc.rsiH, volH = sc.volH, priceH = sc.priceH
            let n = candles.count, step = sc.step, lo = sc.lo, hi = sc.hi
            func x(_ i: Int) -> CGFloat { sc.x(i) }
            func y(_ v: Double) -> CGFloat { sc.y(v) }
            func label(_ v: Double) -> String { percent ? String(format: "%+.1f%%", v) : Fmt.price(v, instrument.assetClass) }

            // Grid + right axis labels.
            for t in Self.ticks(lo, hi, count: max(Int(priceH / 60), 3)) {
                let yy = y(t)
                ctx.stroke(Path { $0.move(to: .init(x: 0, y: yy)); $0.addLine(to: .init(x: plotW, y: yy)) },
                           with: .color(Theme.rule.opacity(0.7)), lineWidth: 0.5)
                ctx.draw(Text(label(t)).font(.mono(9)).foregroundStyle(Theme.dim),
                         at: .init(x: plotW + 6, y: yy), anchor: .leading)
            }
            // Time labels.
            let labelEvery = max(n / max(Int(plotW / 110), 1), 1)
            for i in stride(from: labelEvery / 2, to: n, by: labelEvery) {
                let d = candles[i].time
                let s = range.isIntraday && range == .d1 ? d.formatted(.dateTime.hour(.twoDigits(amPM: .omitted)).minute())
                    : range == .y5 ? d.formatted(.dateTime.month(.abbreviated).year(.twoDigits))
                    : d.formatted(.dateTime.month(.abbreviated).day())
                ctx.draw(Text(s).font(.mono(9)).foregroundStyle(Theme.faint),
                         at: .init(x: x(i), y: size.height - timeAxis / 2), anchor: .center)
                ctx.stroke(Path { $0.move(to: .init(x: x(i), y: 0)); $0.addLine(to: .init(x: x(i), y: priceH + volH)) },
                           with: .color(Theme.rule.opacity(0.35)), lineWidth: 0.5)
            }

            if let pc = previousClose {
                ctx.stroke(Path { $0.move(to: .init(x: 0, y: y(pc))); $0.addLine(to: .init(x: plotW, y: y(pc))) },
                           with: .color(Theme.faint), style: .init(lineWidth: 0.7, dash: [3, 3]))
            }

            // Bollinger fill.
            if !bb.isEmpty {
                var band = Path(), started = false
                for (i, b) in bb.enumerated() { guard let b else { continue }; started ? band.addLine(to: .init(x: x(i), y: y(b.upper))) : band.move(to: .init(x: x(i), y: y(b.upper))); started = true }
                for (i, b) in bb.enumerated().reversed() { if let b { band.addLine(to: .init(x: x(i), y: y(b.lower))) } }
                ctx.fill(band, with: .color(Theme.accent.opacity(0.07)))
                stroke(&ctx, bb.map { $0?.upper }, x: x, y: y, color: Theme.accentDim, width: 0.8)
                stroke(&ctx, bb.map { $0?.lower }, x: x, y: y, color: Theme.accentDim, width: 0.8)
            }

            // Volume.
            let maxVol = candles.map(\.volume).max() ?? 0
            if maxVol > 0 {
                var vu = Path(), vd = Path()
                for (i, c) in candles.enumerated() {
                    let h = volH * 0.9 * CGFloat(c.volume / maxVol)
                    let r = CGRect(x: x(i) - step * 0.35, y: priceH + volH - h, width: max(step * 0.7, 1), height: h)
                    c.close >= c.open ? vu.addRect(r) : vd.addRect(r)
                }
                ctx.fill(vu, with: .color(up.opacity(0.35)))
                ctx.fill(vd, with: .color(down.opacity(0.35)))
            }

            // Price.
            if line {
                var p = Path()
                for (i, c) in candles.enumerated() { i == 0 ? p.move(to: .init(x: x(i), y: y(c.close))) : p.addLine(to: .init(x: x(i), y: y(c.close))) }
                var area = p
                area.addLine(to: .init(x: x(n - 1), y: priceH)); area.addLine(to: .init(x: x(0), y: priceH)); area.closeSubpath()
                let color = candles.last!.close >= (previousClose ?? candles[0].open) ? up : down
                ctx.fill(area, with: .linearGradient(.init(colors: [color.opacity(0.25), color.opacity(0)]), startPoint: .zero, endPoint: .init(x: 0, y: priceH)))
                ctx.stroke(p, with: .color(color), lineWidth: 1.4)
            } else {
                var wu = Path(), wd = Path(), bu = Path(), bd = Path()
                let bw = max(step * 0.68, 1)
                for (i, c) in candles.enumerated() {
                    let isUp = c.close >= c.open
                    let wick = Path { $0.move(to: .init(x: x(i), y: y(c.high))); $0.addLine(to: .init(x: x(i), y: y(c.low))) }
                    let top = y(max(c.open, c.close)), bottom = y(min(c.open, c.close))
                    let body = CGRect(x: x(i) - bw / 2, y: top, width: bw, height: max(bottom - top, 1))
                    if isUp { wu.addPath(wick); bu.addRect(body) } else { wd.addPath(wick); bd.addRect(body) }
                }
                ctx.stroke(wu, with: .color(up), lineWidth: 1)
                ctx.stroke(wd, with: .color(down), lineWidth: 1)
                ctx.fill(bu, with: .color(up))
                ctx.fill(bd, with: .color(down))
            }

            if !sma20.isEmpty {
                stroke(&ctx, sma20, x: x, y: y, color: Theme.accent, width: 1.2)
                stroke(&ctx, sma50, x: x, y: y, color: Theme.warn, width: 1.2)
            }
            if !vwap.isEmpty { stroke(&ctx, vwap, x: x, y: y, color: Color(hex: 0xC48CFF), width: 1.2, dash: [4, 2]) }

            // Last price tag.
            let last = candles.last!.close
            let lastColor = last >= (previousClose ?? candles.first!.open) ? up : down
            ctx.stroke(Path { $0.move(to: .init(x: 0, y: y(last))); $0.addLine(to: .init(x: plotW, y: y(last))) },
                       with: .color(lastColor.opacity(0.6)), style: .init(lineWidth: 0.7, dash: [2, 3]))
            tag(&ctx, label(last), at: .init(x: plotW + 2, y: y(last)), bg: lastColor)

            // RSI pane.
            if showRSI {
                let top = priceH + volH + 4, h = rsiH - 8
                func ry(_ v: Double) -> CGFloat { top + h * (1 - CGFloat(v / 100)) }
                ctx.fill(Path(CGRect(x: 0, y: ry(70), width: plotW, height: ry(30) - ry(70))), with: .color(Theme.accent.opacity(0.05)))
                for lvl in [30.0, 70.0] {
                    ctx.stroke(Path { $0.move(to: .init(x: 0, y: ry(lvl))); $0.addLine(to: .init(x: plotW, y: ry(lvl))) },
                               with: .color(Theme.faint), style: .init(lineWidth: 0.5, dash: [2, 2]))
                    ctx.draw(Text("\(Int(lvl))").font(.mono(8)).foregroundStyle(Theme.faint), at: .init(x: plotW + 6, y: ry(lvl)), anchor: .leading)
                }
                stroke(&ctx, rsi, x: x, y: ry, color: Color(hex: 0xC48CFF), width: 1)
                ctx.draw(Text("RSI 14  " + (rsi.last.flatMap { $0 }.map { String(format: "%.1f", $0) } ?? "")).font(.mono(9, .bold)).foregroundStyle(Theme.label),
                         at: .init(x: 4, y: top + 2), anchor: .topLeading)
            }

            // Legend.
            if showSMA {
                ctx.draw(Text("\(Text("SMA20").foregroundStyle(Theme.accent))  \(Text("SMA50").foregroundStyle(Theme.warn))").font(.mono(9, .bold)),
                         at: .init(x: 6, y: 4), anchor: .topLeading)
            }

            // Comparison series (both rebased to % change from the first visible bar).
            if !compare.isEmpty {
                var p = Path(), pen = false
                for (i, v) in compare.enumerated() {
                    guard let v else { pen = false; continue }
                    pen ? p.addLine(to: .init(x: x(i), y: y(v))) : p.move(to: .init(x: x(i), y: y(v)))
                    pen = true
                }
                ctx.stroke(p, with: .color(Theme.warn), lineWidth: 1.4)
                if let lastV = compare.last(where: { $0 != nil }) ?? nil, let name = compareLabel {
                    tag(&ctx, "\(name) \(label(lastV))", at: .init(x: plotW + 2, y: y(lastV)), bg: Theme.warn.opacity(0.85))
                }
            }

            // Trendlines (anchored in time/price, so they survive zoom, pan and range changes).
            if !percent {
                for (k, l) in (lines + (draft.map { [$0] } ?? [])).enumerated() {
                    let a = CGPoint(x: sc.x(time: l.t1, in: candles), y: y(l.p1))
                    let b = CGPoint(x: sc.x(time: l.t2, in: candles), y: y(l.p2))
                    let isDraft = draft != nil && k == lines.count
                    ctx.stroke(Path { $0.move(to: a); $0.addLine(to: b) }, with: .color(Color(hex: 0xF5F5F5).opacity(isDraft ? 0.6 : 0.9)),
                               style: .init(lineWidth: 1.3, dash: isDraft ? [4, 3] : []))
                    for pt in [a, b] { ctx.fill(Path(ellipseIn: CGRect(x: pt.x - 2.5, y: pt.y - 2.5, width: 5, height: 5)), with: .color(Theme.accent)) }
                }
            }

            // Crosshair.
            if let h = hover, h < n {
                let c = candles[h]
                let cx = x(h), cy = y(c.close)
                let style = StrokeStyle(lineWidth: 0.7, dash: [3, 3])
                ctx.stroke(Path { $0.move(to: .init(x: cx, y: 0)); $0.addLine(to: .init(x: cx, y: size.height - timeAxis)) }, with: .color(Theme.text.opacity(0.5)), style: style)
                ctx.stroke(Path { $0.move(to: .init(x: 0, y: cy)); $0.addLine(to: .init(x: plotW, y: cy)) }, with: .color(Theme.text.opacity(0.5)), style: style)
                tag(&ctx, label(c.close), at: .init(x: plotW + 2, y: cy), bg: Theme.accentDim)
                ctx.fill(Path(ellipseIn: CGRect(x: cx - 3, y: cy - 3, width: 6, height: 6)), with: .color(Theme.accent))
            }
        }
    }

    private func stroke(_ ctx: inout GraphicsContext, _ v: [Double?], x: (Int) -> CGFloat, y: (Double) -> CGFloat,
                        color: Color, width: CGFloat, dash: [CGFloat] = []) {
        var p = Path(), pen = false
        for (i, val) in v.enumerated() {
            guard let val else { pen = false; continue }
            let pt = CGPoint(x: x(i), y: y(val))
            pen ? p.addLine(to: pt) : p.move(to: pt)
            pen = true
        }
        ctx.stroke(p, with: .color(color), style: .init(lineWidth: width, dash: dash))
    }

    private func tag(_ ctx: inout GraphicsContext, _ s: String, at p: CGPoint, bg: Color) {
        let r = CGRect(x: p.x, y: p.y - 8, width: Self.axisWidth - 4, height: 16)
        ctx.fill(Path(roundedRect: r, cornerRadius: 2), with: .color(bg))
        ctx.draw(Text(s).font(.mono(9, .bold)).foregroundStyle(.white), at: .init(x: r.minX + 4, y: p.y), anchor: .leading)
    }

    /// "Nice" axis ticks (1, 2, 2.5, 5 × 10ⁿ).
    static func ticks(_ lo: Double, _ hi: Double, count: Int) -> [Double] {
        let raw = (hi - lo) / Double(max(count, 1))
        guard raw > 0, raw.isFinite else { return [] }
        let mag = pow(10, floor(log10(raw)))
        let step = [1, 2, 2.5, 5, 10].map { $0 * mag }.first { $0 >= raw } ?? raw
        var t = (lo / step).rounded(.up) * step, out: [Double] = []
        while t <= hi && out.count < 20 { out.append(t); t += step }
        return out
    }
}

/// One trendline in data space.
nonisolated struct TrendLine: Codable, Equatable, Sendable {
    var t1: Date, p1: Double, t2: Date, p2: Double
}

/// Layout and value↔pixel mapping shared by the canvas and the gestures, so a drawn line lands
/// exactly where the finger (or Pencil) was.
nonisolated struct ChartScale {
    let plotW, timeAxis, rsiH, volH, priceH, step: CGFloat
    let lo, hi: Double
    let n: Int

    init(size: CGSize, candles: [Candle], showRSI: Bool, bands: [Indicators.Band?] = [], previousClose: Double? = nil, extra: [Double] = []) {
        plotW = size.width - ChartCanvas.axisWidth
        timeAxis = 16
        rsiH = showRSI ? min(80, size.height * 0.18) : 0
        volH = (size.height - rsiH - timeAxis) * 0.16
        priceH = size.height - rsiH - timeAxis - volH
        n = max(candles.count, 1)
        step = plotW / CGFloat(n)
        var lo = candles.map(\.low).min() ?? 0, hi = candles.map(\.high).max() ?? 1
        for b in bands.compactMap({ $0 }) { lo = min(lo, b.lower); hi = max(hi, b.upper) }
        if let pc = previousClose { lo = min(lo, pc); hi = max(hi, pc) }
        for v in extra { lo = min(lo, v); hi = max(hi, v) }
        let pad = (hi - lo) * 0.06 + abs(hi) * 1e-9 + 1e-12
        self.lo = lo - pad
        self.hi = hi + pad
    }

    func x(_ i: Int) -> CGFloat { step * (CGFloat(i) + 0.5) }
    func y(_ v: Double) -> CGFloat { priceH * (1 - CGFloat((v - lo) / (hi - lo))) }
    func price(atY y: CGFloat) -> Double { lo + Double(1 - y / priceH) * (hi - lo) }
    func index(atX x: CGFloat) -> CGFloat { x / step - 0.5 }

    /// Fractional bar position for a timestamp: interpolated between bars, extrapolated beyond
    /// the window using the average bar spacing.
    func x(time t: Date, in c: [Candle]) -> CGFloat {
        guard c.count > 1 else { return x(0) }
        let ts = c.map(\.time.timeIntervalSince1970), v = t.timeIntervalSince1970
        let avg = (ts.last! - ts.first!) / Double(ts.count - 1)
        let fi: Double
        if v <= ts[0] { fi = (v - ts[0]) / avg }
        else if v >= ts.last! { fi = Double(ts.count - 1) + (v - ts.last!) / avg }
        else {
            var lo = 0, hi = ts.count - 1
            while hi - lo > 1 { let m = (lo + hi) / 2; if ts[m] <= v { lo = m } else { hi = m } }
            fi = Double(lo) + (v - ts[lo]) / max(ts[hi] - ts[lo], 1)
        }
        return step * (CGFloat(fi) + 0.5)
    }

    func time(atX px: CGFloat, in c: [Candle]) -> Date {
        guard c.count > 1 else { return c.first?.time ?? .now }
        let fi = Double(index(atX: px))
        let ts = c.map(\.time.timeIntervalSince1970)
        let avg = (ts.last! - ts.first!) / Double(ts.count - 1)
        if fi <= 0 { return Date(timeIntervalSince1970: ts[0] + fi * avg) }
        if fi >= Double(ts.count - 1) { return Date(timeIntervalSince1970: ts.last! + (fi - Double(ts.count - 1)) * avg) }
        let i = Int(fi.rounded(.down))
        return Date(timeIntervalSince1970: ts[i] + (fi - Double(i)) * (ts[i + 1] - ts[i]))
    }
}
