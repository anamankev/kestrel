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

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            readout
            GeometryReader { g in
                let data = visible
                ZStack {
                    if data.count > 1 {
                        ChartCanvas(candles: data, instrument: instrument, theme: theme, range: range,
                                    showSMA: showSMA, showBB: showBB, showVWAP: showVWAP && range.isIntraday,
                                    showRSI: showRSI, line: lineStyle, hover: hover,
                                    previousClose: range == .d1 ? market.quotes[instrument.symbol]?.previousClose : nil)
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
                    .onChanged { hover = index(at: $0.location.x, width: g.size.width, count: data.count) }
                    .onEnded { _ in hover = nil })
                .simultaneousGesture(MagnifyGesture()
                    .onChanged { zoom = min(max(pinchBase * $0.magnification, 1), 8) }
                    .onEnded { _ in pinchBase = zoom })
            }
        }
        .task(id: range) { await load(loop: true) }
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
        let n = max(Int(CGFloat(c.count) / zoom), 20)
        return Array(c.suffix(n))
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
    static let axisWidth: CGFloat = 68
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

    var body: some View {
        let closes = candles.map(\.close)
        let sma20 = showSMA ? Indicators.sma(closes, period: 20) : []
        let sma50 = showSMA ? Indicators.sma(closes, period: 50) : []
        let bb = showBB ? Indicators.bollinger(closes) : []
        let vwap = showVWAP ? Indicators.vwap(candles) : []
        let rsi = showRSI ? Indicators.rsi(closes) : []
        Canvas { ctx, size in
            let up = theme.up, down = theme.down
            let plotW = size.width - Self.axisWidth
            let timeAxis: CGFloat = 16
            let rsiH: CGFloat = showRSI ? min(80, size.height * 0.18) : 0
            let volH = (size.height - rsiH - timeAxis) * 0.16
            let priceH = size.height - rsiH - timeAxis - volH
            let n = candles.count
            let step = plotW / CGFloat(n)
            func x(_ i: Int) -> CGFloat { step * (CGFloat(i) + 0.5) }

            // Price scale (include visible studies so bands never clip).
            var lo = candles.map(\.low).min()!, hi = candles.map(\.high).max()!
            for b in bb.compactMap({ $0 }) { lo = min(lo, b.lower); hi = max(hi, b.upper) }
            if let pc = previousClose { lo = min(lo, pc); hi = max(hi, pc) }
            let pad = (hi - lo) * 0.06 + hi * 1e-9
            lo -= pad; hi += pad
            func y(_ v: Double) -> CGFloat { priceH * (1 - CGFloat((v - lo) / (hi - lo))) }

            // Grid + right axis labels.
            for t in Self.ticks(lo, hi, count: max(Int(priceH / 60), 3)) {
                let yy = y(t)
                ctx.stroke(Path { $0.move(to: .init(x: 0, y: yy)); $0.addLine(to: .init(x: plotW, y: yy)) },
                           with: .color(Theme.rule.opacity(0.7)), lineWidth: 0.5)
                ctx.draw(Text(Fmt.price(t, instrument.assetClass)).font(.mono(9)).foregroundStyle(Theme.dim),
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
            tag(&ctx, Fmt.price(last, instrument.assetClass), at: .init(x: plotW + 2, y: y(last)), bg: lastColor)

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

            // Crosshair.
            if let h = hover, h < n {
                let c = candles[h]
                let cx = x(h), cy = y(c.close)
                let style = StrokeStyle(lineWidth: 0.7, dash: [3, 3])
                ctx.stroke(Path { $0.move(to: .init(x: cx, y: 0)); $0.addLine(to: .init(x: cx, y: size.height - timeAxis)) }, with: .color(Theme.text.opacity(0.5)), style: style)
                ctx.stroke(Path { $0.move(to: .init(x: 0, y: cy)); $0.addLine(to: .init(x: plotW, y: cy)) }, with: .color(Theme.text.opacity(0.5)), style: style)
                tag(&ctx, Fmt.price(c.close, instrument.assetClass), at: .init(x: plotW + 2, y: cy), bg: Theme.accentDim)
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
