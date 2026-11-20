import SwiftUI
import Charts
import KestrelCore

private func bp(_ v: Double?) -> String {
    guard let v, v.isFinite else { return "—" }
    let r = Int(v.rounded())
    return "\(r > 0 ? "+" : "")\(r) bp"
}
private func pctY(_ v: Double?) -> String { v.map { String(format: "%.2f%%", $0) } ?? "—" }
private let dayFormat: Date.FormatStyle = .dateTime.year().month(.twoDigits).day(.twoDigits).locale(Locale(identifier: "en_CA"))
private func ymd(_ d: Date) -> String { var f = dayFormat; f.timeZone = TimeZone(identifier: "UTC")!; return d.formatted(f) }
/// A local calendar day as the UTC midnight the bond math uses.
private func utcDay(_ d: Date) -> Date {
    let c = Calendar.current.dateComponents([.year, .month, .day], from: d)
    var utc = Calendar(identifier: .gregorian); utc.timeZone = TimeZone(identifier: "UTC")!
    return utc.date(from: c) ?? d
}

/// GC: today's Treasury par curve against 1 month, 1 year and 5 years ago, and the 10Y–2Y spread history.
struct YieldCurveView: View {
    @Environment(MacroService.self) private var macro
    @Environment(Theme.self) private var theme

    private struct Curve: Identifiable { let name: String; let day: Treasury.CurveDay; let color: Color; let dash: [CGFloat]; var id: String { name } }

    var body: some View {
        Group {
            if macro.curves.count > 1, macro.curveYears >= 5 {
                report(macro.curves)
            } else if let e = macro.curveError {
                EmptyNote(title: "Treasury data unavailable", detail: e, icon: "exclamationmark.triangle")
            } else {
                ProgressView("Loading Treasury yield curves…").tint(Theme.accent).font(.mono(10)).foregroundStyle(Theme.dim)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .task { await macro.loadCurves(years: 5) }
    }

    private func spread(_ d: Treasury.CurveDay) -> Double? {
        guard let a = d.yields["10Y"], let b = d.yields["2Y"] else { return nil }
        return (a - b) * 100
    }

    private func report(_ days: [Treasury.CurveDay]) -> some View {
        let today = days[days.count - 1]
        func back(_ n: Double) -> Treasury.CurveDay? { Treasury.curve(on: today.date.addingTimeInterval(-n * 86_400), in: days) }
        let y1 = back(365), y5 = back(5 * 365 + 1)
        let curves = [Curve(name: "TODAY", day: today, color: Theme.accent, dash: []), back(30).map { Curve(name: "1M AGO", day: $0, color: Theme.text, dash: [4, 3]) },
                      y1.map { Curve(name: "1Y AGO", day: $0, color: Theme.warn, dash: [4, 3]) }, y5.map { Curve(name: "5Y AGO", day: $0, color: Theme.dim, dash: [2, 3]) }].compactMap { $0 }
        let tenors = Treasury.tenors.filter { today.yields[$0.label] != nil }
        let hist = days.enumerated().filter { $0.offset % 3 == 0 || $0.offset == days.count - 1 }.compactMap { e in spread(e.element).map { (e.element.date, $0) } }
        let s10 = spread(today)
        let inverted = Double(days.filter { (spread($0) ?? 0) < 0 }.count) / Double(days.count)
        func chg(_ t: String, _ c: Treasury.CurveDay?) -> Double? {
            guard let now = today.yields[t], let then = c?.yields[t] else { return nil }
            return (now - then) * 100
        }
        return ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 1), count: 4), spacing: 1) {
                    ForEach(["2Y", "10Y", "30Y"], id: \.self) { t in
                        StatTile(key: "\(t) TREASURY", value: pctY(today.yields[t]), sub: "1Y CHANGE \(bp(chg(t, y1)))")
                    }
                    StatTile(key: "10Y – 2Y SPREAD", value: bp(s10), sub: s10.map { $0 < 0 ? "INVERTED" : "UPWARD SLOPING" } ?? "",
                             color: (s10 ?? 0) < 0 ? theme.down : theme.up)
                }
                .background(Theme.rule).padding(.horizontal, 8)
                SectionBar(title: "U.S. TREASURY PAR YIELD CURVE", trailing: "AS OF \(ymd(today.date)) · TREASURY.GOV")
                Chart {
                    ForEach(curves) { c in
                        ForEach(tenors, id: \.label) { t in
                            if let v = c.day.yields[t.label] {
                                LineMark(x: .value("Tenor", t.label), y: .value("Yield", v), series: .value("Curve", c.name))
                                    .foregroundStyle(c.color).lineStyle(StrokeStyle(lineWidth: c.name == "TODAY" ? 2.2 : 1.3, dash: c.dash))
                            }
                        }
                    }
                }
                .chartXScale(domain: tenors.map(\.label))
                .chartYScale(domain: .automatic(includesZero: false))
                .chartYAxis { AxisMarks { v in AxisGridLine().foregroundStyle(Theme.rule); AxisValueLabel { if let d = v.as(Double.self) { Text(String(format: "%.1f%%", d)).font(.mono(9)).foregroundStyle(Theme.dim) } } } }
                .chartXAxis { AxisMarks { v in AxisValueLabel { if let s = v.as(String.self) { Text(s).font(.mono(9)).foregroundStyle(Theme.dim) } } } }
                .frame(height: 200.pt).padding(.horizontal, 8)
                .accessibilityLabel("Par yield curve: today 2-year \(pctY(today.yields["2Y"])), 10-year \(pctY(today.yields["10Y"])), 30-year \(pctY(today.yields["30Y"])).")
                HStack(spacing: 14) {
                    ForEach(curves) { c in
                        HStack(spacing: 4) { Rectangle().fill(c.color).frame(width: 14, height: 2); Text("\(c.name) \(ymd(c.day.date))") }
                    }
                }
                .font(.mono(9)).foregroundStyle(Theme.dim).padding(.horizontal, 8)
                SectionBar(title: "10Y – 2Y SPREAD (BP)", trailing: "\(ymd(days[0].date)) – \(ymd(today.date)) · INVERTED \(Int((inverted * 100).rounded()))% OF DAYS")
                Chart {
                    RuleMark(y: .value("Zero", 0)).foregroundStyle(Theme.faint).lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
                    ForEach(hist, id: \.0) { p in LineMark(x: .value("Date", p.0), y: .value("Spread", p.1)).foregroundStyle(Theme.accent).lineStyle(StrokeStyle(lineWidth: 1.3)) }
                }
                .chartYAxis { AxisMarks { v in AxisGridLine().foregroundStyle(Theme.rule); AxisValueLabel { if let d = v.as(Double.self) { Text("\(Int(d))").font(.mono(9)).foregroundStyle(Theme.dim) } } } }
                .chartXAxis { AxisMarks(values: .stride(by: .year)) { v in AxisValueLabel { if let d = v.as(Date.self) { Text(String(ymd(d).prefix(4))).font(.mono(9)).foregroundStyle(Theme.dim) } } } }
                .frame(height: 170.pt).padding(.horizontal, 8)
                .accessibilityLabel("10-year minus 2-year spread history, now \(bp(s10)); inverted on \(Int((inverted * 100).rounded())) percent of days since \(ymd(days[0].date)).")
                HStack {
                    Spacer()
                    CopyTableButton(csv: csv(curves, tenors))
                    ShareLink(item: CSVFile(name: "treasury-curve-\(ymd(today.date)).csv", text: csv(curves, tenors)), preview: SharePreview("Treasury curve")) {
                        Label("EXPORT CSV", systemImage: "square.and.arrow.up").font(.mono(10, .bold))
                    }
                    .buttonStyle(.terminal).foregroundStyle(Theme.accent)
                }
                .padding(.horizontal, 8)
                VStack(spacing: 0) {
                    HStack(spacing: 0) {
                        HeaderCell(text: "TENOR", width: 60.pt, align: .leading)
                        ForEach(curves) { HeaderCell(text: $0.name) }
                        HeaderCell(text: "1Y CHG"); HeaderCell(text: "5Y CHG")
                    }
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    ForEach(Array(tenors.enumerated()), id: \.element.label) { n, t in
                        HStack(spacing: 0) {
                            Text(t.label).font(.mono(11, .bold)).foregroundStyle(Theme.text).frame(width: 60.pt, alignment: .leading)
                            ForEach(curves) { c in cell(pctY(c.day.yields[t.label]), Theme.text) }
                            cell(bp(chg(t.label, y1)), theme.tint(chg(t.label, y1).map { $0.rounded() }))
                            cell(bp(chg(t.label, y5)), theme.tint(chg(t.label, y5).map { $0.rounded() }))
                        }
                        .padding(.horizontal, 8).frame(minHeight: 24.pt).rowBackground(n)
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel("\(t.label): today \(pctY(today.yields[t.label])), one-year change \(bp(chg(t.label, y1))), five-year change \(bp(chg(t.label, y5)))")
                    }
                }
                Text("Par yields from the U.S. Treasury's daily yield curve (bond-equivalent, percent). A negative 10Y–2Y spread (an inverted curve) has preceded most U.S. recessions, with long and variable lags.")
                    .font(.ui(10)).foregroundStyle(Theme.faint).padding(.horizontal, 8)
            }
            .padding(.vertical, 8)
        }
    }

    private func cell(_ t: String, _ c: Color) -> some View {
        Text(t).font(.mono(11)).monospacedDigit().foregroundStyle(c).frame(maxWidth: .infinity, alignment: .trailing)
    }

    private func csv(_ curves: [Curve], _ tenors: [Treasury.Tenor]) -> String {
        CSV.make(header: ["Tenor"] + curves.map { "\($0.name) (\(ymd($0.day.date)))" },
                 rows: tenors.map { t in [t.label] + curves.map { CSV.number($0.day.yields[t.label]) } })
    }
}

/// YAS: price ↔ yield for a fixed-coupon bond, with duration, convexity, DV01 and the spread to Treasuries.
struct BondCalculatorView: View {
    @Environment(MacroService.self) private var macro
    @Environment(Theme.self) private var theme

    enum Mode: String, CaseIterable { case toPrice = "YIELD→PRICE", toYield = "PRICE→YIELD" }

    @AppStorage("yas.coupon") private var coupon = ""
    @AppStorage("yas.maturity") private var maturity: Double = 0
    @AppStorage("yas.mode") private var mode: Mode = .toPrice
    @AppStorage("yas.yield") private var yieldText = ""
    @AppStorage("yas.price") private var priceText = "100"
    @AppStorage("yas.face") private var faceText = "1000000"

    private static let shocks = [-100, -50, -25, 0, 25, 50, 100]

    private struct Result { var sched: Bond.Schedule; var y: Double; var r: Bond.Risk; var face: Double; var spread: Double?; var tsy: Double? }

    private var latest: Treasury.CurveDay? { macro.curves.last }

    private func num(_ s: String) -> Double? { Double(s.replacingOccurrences(of: ",", with: "").trimmingCharacters(in: .whitespaces)) }

    private var result: Result? {
        guard let c = num(coupon).map({ $0 / 100 }), c >= 0, c < 1, let face = num(faceText), face > 0,
              let s = Bond.schedule(settle: utcDay(.now), maturity: utcDay(Date(timeIntervalSince1970: maturity))), s.years <= 100 else { return nil }
        let y: Double? = mode == .toPrice ? num(yieldText).map { $0 / 100 } : num(priceText).flatMap { Bond.yield(coupon: c, s, clean: $0) }
        guard let y, y.isFinite, y > -0.05, y < 1 else { return nil }
        let tsy = latest.flatMap { Treasury.interpolate($0, years: s.years) }
        return Result(sched: s, y: y, r: Bond.risk(coupon: c, s, yield: y), face: face, spread: tsy.map { (y * 100 - $0) * 100 }, tsy: tsy)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                inputs
                if let r = result { report(r) } else if !coupon.isEmpty {
                    EmptyNote(title: "Check the inputs", detail: mode == .toYield ? "Enter a coupon, a future maturity (up to 100 years), a positive face and a price some yield between −5% and 100% can reach."
                              : "Enter a coupon from 0 to 100%, a future maturity (up to 100 years), a yield between −5% and 100% and a positive face.", icon: "slider.horizontal.3")
                }
            }
            .padding(.vertical, 8)
        }
        .task {
            await macro.loadCurves(years: 0)
            // First visit: a 10-year bond with a coupon near today's 10Y yield.
            if coupon.isEmpty {
                let y10 = latest?.yields["10Y"] ?? 4
                coupon = String(format: "%.3f", (y10 * 8).rounded() / 8)
                yieldText = String(format: "%.3f", y10)
                maturity = Calendar.current.date(byAdding: .year, value: 10, to: Calendar.current.startOfDay(for: .now))!.timeIntervalSince1970
            }
        }
    }

    private var inputs: some View {
        let cols = [GridItem(.adaptive(minimum: 150.pt), spacing: 10, alignment: .leading)]
        return LazyVGrid(columns: cols, alignment: .leading, spacing: 10) {
            field("COUPON %", $coupon)
            VStack(alignment: .leading, spacing: 3) {
                Text("MATURITY").font(.mono(9, .bold)).foregroundStyle(Theme.label)
                DatePicker("Maturity", selection: Binding(get: { Date(timeIntervalSince1970: maturity) }, set: { maturity = $0.timeIntervalSince1970 }), displayedComponents: .date)
                    .labelsHidden().font(.mono(12))
            }
            VStack(alignment: .leading, spacing: 3) {
                Text("SOLVE FOR").font(.mono(9, .bold)).foregroundStyle(Theme.label)
                Picker("Solve for", selection: $mode) { ForEach(Mode.allCases, id: \.self) { Text($0 == .toPrice ? "PRICE" : "YIELD") } }.pickerStyle(.segmented).labelsHidden()
            }
            if mode == .toPrice { field("YIELD %", $yieldText) } else { field("CLEAN PRICE", $priceText) }
            field("FACE $", $faceText)
        }
        .padding(.horizontal, 8)
    }

    private func field(_ label: String, _ text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label).font(.mono(9, .bold)).foregroundStyle(Theme.label)
            TextField(label, text: text).accessibilityLabel(label).font(.mono(14, .semibold)).textFieldStyle(.plain)
                #if os(iOS)
                .keyboardType(.decimalPad)
                #endif
                .padding(.horizontal, 8).frame(minHeight: barHeight(30)).background(Theme.panel).overlay(Rectangle().stroke(Theme.rule))
        }
    }

    private func money(_ v: Double) -> String { v.formatted(.currency(code: "USD").precision(.fractionLength(0))) }

    private func report(_ o: Result) -> some View {
        let c = (num(coupon) ?? 0) / 100
        return VStack(alignment: .leading, spacing: 8) {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 1), count: 3), spacing: 1) {
                StatTile(key: "CLEAN PRICE", value: String(format: "%.4f", o.r.clean), sub: String(format: "DIRTY %.4f · ACCRUED %.4f", o.r.dirty, o.r.accrued))
                StatTile(key: "YIELD TO MATURITY", value: String(format: "%.4f%%", o.y * 100), sub: String(format: "SEMI-ANNUAL · %.2f YEARS · %d COUPONS LEFT", o.sched.years, o.sched.n))
                StatTile(key: "SPREAD TO TREASURIES", value: bp(o.spread), sub: o.tsy.map { String(format: "CURVE AT MATURITY %.3f%%", $0) } ?? "CURVE LOADING",
                         color: theme.tint(o.spread.map { $0.rounded() }))
                StatTile(key: "MODIFIED DURATION", value: String(format: "%.3f", o.r.modified), sub: String(format: "MACAULAY %.3f YEARS", o.r.macaulay))
                StatTile(key: "CONVEXITY", value: String(format: "%.2f", o.r.convexity), sub: "PRICE CURVATURE")
                StatTile(key: "DV01", value: money(o.r.dv01 * o.face / 100), sub: String(format: "%.5f PER 100 · VALUE ", o.r.dv01) + money(o.r.dirty * o.face / 100))
            }
            .background(Theme.rule).padding(.horizontal, 8)
            SectionBar(title: "YIELD SCENARIOS", trailing: "FULL REPRICE VS DURATION + CONVEXITY ESTIMATE")
            VStack(spacing: 0) {
                HStack(spacing: 0) {
                    HeaderCell(text: "SHIFT", width: 80.pt, align: .leading)
                    ForEach(["YIELD", "CLEAN PRICE", "P&L ON FACE", "% CHANGE", "ESTIMATE"], id: \.self) { HeaderCell(text: $0) }
                }
                .padding(.horizontal, 8).padding(.vertical, 3)
                ForEach(Array(Self.shocks.enumerated()), id: \.element) { n, s in
                    let dy = Double(s) / 10_000, p = Bond.risk(coupon: c, o.sched, yield: o.y + dy)
                    let pct = p.dirty / o.r.dirty - 1, est = -o.r.modified * dy + 0.5 * o.r.convexity * dy * dy
                    HStack(spacing: 0) {
                        Text("\(s > 0 ? "+" : "")\(s) bp").font(.mono(11, .bold)).foregroundStyle(Theme.text).frame(width: 80.pt, alignment: .leading)
                        cell(String(format: "%.3f%%", (o.y + dy) * 100), Theme.text)
                        cell(String(format: "%.4f", p.clean), Theme.text)
                        cell(money((p.dirty - o.r.dirty) * o.face / 100), theme.tint(s == 0 ? 0 : pct))
                        cell(String(format: "%+.2f%%", pct * 100), theme.tint(s == 0 ? 0 : pct))
                        cell(String(format: "%+.2f%%", est * 100), Theme.dim)
                    }
                    .padding(.horizontal, 8).frame(minHeight: 24.pt).rowBackground(n)
                    .overlay(s == 0 ? Rectangle().stroke(Theme.accentDim) : nil)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("Yield \(s > 0 ? "up" : "down") \(abs(s)) basis points: price \(String(format: "%.2f", p.clean)), change \(String(format: "%+.2f", pct * 100)) percent")
                }
            }
            Text("Semi-annual coupons, settlement today, accrued interest for the elapsed part of the coupon period, actual/actual day count. Spread is the yield over the Treasury par curve interpolated at the bond's maturity. A teaching calculator, not a pricing source.")
                .font(.ui(10)).foregroundStyle(Theme.faint).padding(.horizontal, 8)
        }
    }

    private func cell(_ t: String, _ c: Color) -> some View {
        Text(t).font(.mono(11)).monospacedDigit().foregroundStyle(c).frame(maxWidth: .infinity, alignment: .trailing)
    }
}
