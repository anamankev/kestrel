import SwiftUI
import KestrelCore

/// ALRT: create price alerts for the loaded security, see every active alert with its distance
/// to trigger, and review what fired.
struct AlertsView: View {
    let instrument: Instrument?
    let panelID: Int
    @Environment(MarketStore.self) private var market
    @Environment(UserData.self) private var user
    @Environment(Workspace.self) private var ws
    @Environment(Theme.self) private var theme

    enum Kind: String, CaseIterable { case above = "ABOVE", below = "BELOW", move = "MOVE %" }
    @State private var kind = Kind.above
    @State private var levelText = ""
    @State private var message: (String, Bool)?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                if let i = instrument { creator(i) } else {
                    Text("Load a security to create an alert: AAPL ALRT, BTC ALRT. Or long-press any row and choose Set alert.")
                        .font(.ui(11)).foregroundStyle(Theme.dim).padding(.horizontal, 8).padding(.top, 8)
                }
                SectionBar(title: "ACTIVE", trailing: "\(user.alerts.active.count)")
                if user.alerts.active.isEmpty {
                    Text("No active alerts.").font(.mono(11)).foregroundStyle(Theme.dim).padding(.horizontal, 8)
                }
                ForEach(Array(user.alerts.active.enumerated()), id: \.element.id) { n, a in activeRow(a).rowBackground(n) }
                SectionBar(title: "TRIGGERED", trailing: user.alerts.history.isEmpty ? nil : "\(user.alerts.history.count)")
                ForEach(Array(user.alerts.history.prefix(50).enumerated()), id: \.element.id) { n, a in historyRow(a).rowBackground(n) }
                if !user.alerts.history.isEmpty {
                    Button("Clear history") { user.clearAlertHistory() }
                        .font(.mono(10, .bold)).foregroundStyle(Theme.dim).buttonStyle(.plain).padding(.horizontal, 8)
                }
            }
            .padding(.vertical, 8)
        }
    }

    private func creator(_ i: Instrument) -> some View {
        let last = market.quotes[i.symbol]?.last
        return VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text("NEW ALERT").font(.mono(10, .heavy)).foregroundStyle(Theme.accent)
                Text(i.ticker).font(.mono(13, .bold)).foregroundStyle(Theme.text)
                Text("LAST").font(.mono(9, .bold)).foregroundStyle(Theme.label)
                TickText(value: last, cls: i.assetClass, size: 13, weight: .semibold)
                ChangeText(value: market.quotes[i.symbol]?.changePercent, percent: true, size: 11)
            }
            Picker("", selection: $kind) { ForEach(Kind.allCases, id: \.self) { Text($0.rawValue).tag($0) } }
                .pickerStyle(.segmented).labelsHidden()
                .onChange(of: kind) { prefill(last, i) }
            HStack(spacing: 8) {
                TextField("", text: $levelText)
                .placeholder(kind == .move ? "e.g. 5" : "price", when: levelText.isEmpty)
                    .font(.mono(15, .semibold)).foregroundStyle(Theme.text).textFieldStyle(.plain)
                    #if os(iOS)
                    .keyboardType(.decimalPad)
                    #endif
                    .padding(.horizontal, 8).frame(height: 34.pt)
                    .background(Theme.canvas).overlay(Rectangle().stroke(Theme.rule))
                    .onSubmit { create(i, last) }
                if kind != .move, let last, let level = Double(levelText.replacingOccurrences(of: ",", with: "")), last > 0 {
                    Text(Fmt.pct((level / last - 1) * 100) + " away").font(.mono(10)).foregroundStyle(Theme.dim).fixedSize()
                }
                Button { create(i, last) } label: {
                    Text("SET").font(.mono(12, .heavy)).foregroundStyle(Theme.canvas)
                        .frame(width: 64.pt, height: 34.pt).background(Theme.accent, in: .rect(cornerRadius: 3))
                }
                .buttonStyle(.plain)
            }
            if let (text, ok) = message {
                Text(text).font(.mono(11, .medium)).foregroundStyle(ok ? theme.up : Theme.cancel)
            }
            Text("Alerts fire once, on the first quote that meets the condition. Delayed securities are checked on each refresh.")
                .font(.ui(10)).foregroundStyle(Theme.faint)
        }
        .padding(.horizontal, 8)
        .onAppear { if levelText.isEmpty { prefill(last, i) } }
    }

    /// Suggests a level 2% away (or a 3% move) so one tap creates a sensible alert.
    private func prefill(_ last: Double?, _ i: Instrument) {
        switch kind {
        case .move: levelText = "3"
        case .above: levelText = last.map { Fmt.price($0 * 1.02, i.assetClass).replacingOccurrences(of: ",", with: "") } ?? ""
        case .below: levelText = last.map { Fmt.price($0 * 0.98, i.assetClass).replacingOccurrences(of: ",", with: "") } ?? ""
        }
    }

    private func create(_ i: Instrument, _ last: Double?) {
        guard let v = Double(levelText.replacingOccurrences(of: ",", with: "")) else { message = ("Enter a number", false); return }
        let c: AlertCondition = switch kind { case .above: .above(v); case .below: .below(v); case .move: .movePercent(v) }
        do {
            try user.addAlert(i, c, last: last)
            message = ("Alert set: \(i.ticker) \(c.label)", true)
        } catch {
            message = (error.errorDescription ?? "Rejected", false)
        }
    }

    private func ticker(_ s: String) -> String { Universe.instrument(symbol: s)?.ticker ?? s }

    private func activeRow(_ a: PriceAlert) -> some View {
        let q = market.quotes[a.symbol]
        let distance: String = {
            guard let last = q?.last, last > 0 else { return "—" }
            switch a.condition {
            case .above(let p), .below(let p): return Fmt.pct((p / last - 1) * 100)
            case .movePercent: return Fmt.pct(q?.changePercent)
            }
        }()
        return HStack(spacing: 10) {
            Image(systemName: "bell.fill").font(.system(size: 10)).foregroundStyle(Theme.warn)
            Text(ticker(a.symbol)).font(.mono(12, .bold)).foregroundStyle(Theme.text).frame(width: 64.pt, alignment: .leading)
            Text(a.condition.label).font(.mono(11)).foregroundStyle(Theme.label)
            Spacer()
            Text("LAST \(Fmt.price(q?.last))").font(.mono(11)).foregroundStyle(Theme.text)
            Text(distance).font(.mono(11)).foregroundStyle(Theme.dim).frame(width: 70.pt, alignment: .trailing)
            Button { user.cancelAlert(a.id) } label: {
                Text("CXL").font(.mono(9, .heavy)).foregroundStyle(Theme.canvas)
                    .padding(.horizontal, 6).frame(height: 18.pt).background(Theme.cancel, in: .rect(cornerRadius: 2))
            }
            .buttonStyle(.plain)
        }
        .monospacedDigit()
        .padding(.horizontal, 8).frame(height: 28.pt)
        .contentShape(.rect)
        .onTapGesture { if let i = Universe.instrument(symbol: a.symbol) ?? Universe.resolve(a.symbol) { ws.link(i, from: panelID) } }
    }

    private func historyRow(_ a: PriceAlert) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "checkmark.circle.fill").font(.system(size: 10)).foregroundStyle(theme.up)
            Text(ticker(a.symbol)).font(.mono(12, .bold)).foregroundStyle(Theme.text).frame(width: 64.pt, alignment: .leading)
            Text(a.condition.label).font(.mono(11)).foregroundStyle(Theme.dim)
            Spacer()
            Text("@ \(Fmt.price(a.triggerPrice))").font(.mono(11)).foregroundStyle(Theme.text)
            Text(a.triggered.map { $0.formatted(.dateTime.month(.abbreviated).day().hour().minute()) } ?? "")
                .font(.mono(10)).foregroundStyle(Theme.dim)
        }
        .monospacedDigit()
        .padding(.horizontal, 8).frame(height: 26.pt)
    }
}

/// Banner for a fired alert (the system notification covers the background case).
struct AlertToast: View {
    @Environment(UserData.self) private var user
    @State private var visible: PriceAlert?

    var body: some View {
        Group {
            if let a = visible {
                HStack(spacing: 10) {
                    Image(systemName: "bell.badge.fill").foregroundStyle(Theme.warn)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("ALERT · \(Universe.instrument(symbol: a.symbol)?.ticker ?? a.symbol)").font(.mono(9, .bold)).foregroundStyle(Theme.label)
                        Text("\(a.condition.label) · last \(Fmt.price(a.triggerPrice))").font(.mono(12, .semibold)).foregroundStyle(Theme.text)
                    }
                }
                .padding(10)
                .background(Theme.header, in: .rect(cornerRadius: 4))
                .overlay(RoundedRectangle(cornerRadius: 4).stroke(Theme.warn.opacity(0.7)))
                .shadow(color: .black.opacity(0.5), radius: 10)
                .transition(.move(edge: .trailing).combined(with: .opacity))
            }
        }
        .onChange(of: user.lastAlert) { _, a in
            guard let a else { return }
            withAnimation(.spring(duration: 0.3)) { visible = a }
            Task {
                try? await Task.sleep(for: .seconds(6))
                if visible == a { withAnimation { visible = nil } }
            }
        }
    }
}
