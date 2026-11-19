import SwiftUI
import KestrelCore

/// A price that flashes up/down for a moment whenever it changes.
struct TickText: View {
    let value: Double?
    var cls: AssetClass? = nil
    var size: CGFloat = 12
    var weight: Font.Weight = .medium
    var color: Color = Theme.text
    @Environment(Theme.self) private var theme
    @State private var flash: Color = .clear

    var body: some View {
        Text(Fmt.price(value, cls))
            .font(.mono(size, weight))
            .monospacedDigit()
            .foregroundStyle(color)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .padding(.horizontal, 3)
            .background(flash.opacity(0.35), in: .rect(cornerRadius: 2))
            .onChange(of: value) { old, new in
                guard let old, let new, old != new else { return }
                flash = new > old ? theme.up : theme.down
                withAnimation(.easeOut(duration: 0.7)) { flash = .clear }
            }
    }
}

struct ChangeText: View {
    let value: Double?
    var percent = false
    var cls: AssetClass? = nil
    /// Price the change belongs to: the change takes its precision (CL1 +0.76, not +0.7600).
    var like: Double? = nil
    var size: CGFloat = 12
    @Environment(Theme.self) private var theme

    private var text: String {
        if percent { return Fmt.pct(value) }
        guard let like, let v = value, v.isFinite else { return Fmt.signed(value, cls) }
        return (v > 0 ? "+" : "") + Fmt.price(v, like: like, cls)
    }

    var body: some View {
        Text(text)
            .font(.mono(size, .medium))
            .monospacedDigit()
            .foregroundStyle(theme.tint(value))
            .lineLimit(1)
            .minimumScaleFactor(0.7)
    }
}

struct Sparkline: View {
    let values: [Double]
    var baseline: Double? = nil
    @Environment(Theme.self) private var theme

    var body: some View {
        Canvas { ctx, size in
            guard values.count > 1, let lo = values.min(), let hi = values.max() else { return }
            let span = max(hi - lo, hi * 1e-9, 1e-12)
            func pt(_ i: Int) -> CGPoint {
                CGPoint(x: size.width * CGFloat(i) / CGFloat(values.count - 1),
                        y: size.height * (1 - CGFloat((values[i] - lo) / span)))
            }
            var path = Path()
            path.move(to: pt(0))
            for i in 1..<values.count { path.addLine(to: pt(i)) }
            let ref = baseline ?? values[0]
            let color = values.last! >= ref ? theme.up : theme.down
            ctx.stroke(path, with: .color(color), lineWidth: 1.1)
            if let b = baseline, b > lo, b < hi {
                let y = size.height * (1 - CGFloat((b - lo) / span))
                ctx.stroke(Path { $0.move(to: .init(x: 0, y: y)); $0.addLine(to: .init(x: size.width, y: y)) },
                           with: .color(Theme.faint), style: .init(lineWidth: 0.5, dash: [2, 2]))
            }
        }
    }
}

/// Column header cell.
struct HeaderCell: View {
    let text: String
    var width: CGFloat? = nil
    var align: Alignment = .trailing

    var body: some View {
        Text(text)
            .font(.mono(10, .semibold))
            .foregroundStyle(Theme.label)
            .lineLimit(1)
            .frame(width: width, alignment: align)
            .frame(maxWidth: width == nil ? .infinity : nil, alignment: align)
    }
}

struct SectionBar: View {
    let title: String
    var trailing: String? = nil

    var body: some View {
        HStack {
            Text(title).font(.mono(10, .bold)).foregroundStyle(Theme.accent)
            Spacer()
            if let trailing { Text(trailing).font(.mono(10)).foregroundStyle(Theme.dim) }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Theme.header)
    }
}

struct EmptyNote: View {
    let title: String
    var detail: String? = nil
    var icon = "dot.radiowaves.left.and.right"

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: icon).font(.system(size: 22)).foregroundStyle(Theme.accentDim)
            Text(title).font(.mono(12, .semibold)).foregroundStyle(Theme.dim)
            if let detail {
                Text(detail).font(.ui(11)).foregroundStyle(Theme.faint).multilineTextAlignment(.center).frame(maxWidth: 320.pt)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// Numbered hotspot button: tap, or type the number on the command line in a real terminal.
struct Hotspot: View {
    let number: Int
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Text("\(number)")
                    .font(.mono(10, .bold))
                    .foregroundStyle(Theme.canvas)
                    .frame(width: 16.pt, height: 16.pt)
                    .background(Theme.accent, in: .rect(cornerRadius: 2))
                Text(title).font(.mono(11, .medium)).foregroundStyle(Theme.text)
            }
            .padding(.horizontal, 8).padding(.vertical, 5)
            .background(Theme.header, in: .rect(cornerRadius: 3))
            .overlay(RoundedRectangle(cornerRadius: 3).stroke(Theme.rule))
        }
        .buttonStyle(.terminal)
    }
}

/// 52-week (or any) range bar with a marker for the current price.
struct RangeBar: View {
    let low: Double?
    let high: Double?
    let value: Double?

    var body: some View {
        GeometryReader { g in
            ZStack(alignment: .leading) {
                Capsule().fill(Theme.rule).frame(height: 4.pt)
                if let lo = low, let hi = high, let v = value, hi > lo {
                    let x = g.size.width * CGFloat(min(max((v - lo) / (hi - lo), 0), 1))
                    Capsule().fill(Theme.accentDim).frame(width: x, height: 4.pt)
                    Rectangle().fill(Theme.accent).frame(width: 2.pt, height: 12.pt).offset(x: x - 1)
                }
            }
            .frame(maxHeight: .infinity)
        }
        .frame(height: 12.pt)
    }
}

extension View {
    func rowBackground(_ index: Int) -> some View {
        background(index.isMultiple(of: 2) ? Theme.panel : Theme.rowAlt)
    }
}

extension Date {
    var ago: String {
        let s = Int(Date().timeIntervalSince(self))
        if s < 60 { return "\(max(s, 0))s" }
        if s < 3600 { return "\(s / 60)m" }
        if s < 86400 { return "\(s / 3600)h" }
        return "\(s / 86400)d"
    }
}

extension View {
    /// Faint hint text shown while a field is empty. SwiftUI's `prompt:` takes the field's
    /// foreground colour on macOS, so the hint would render as bright as real input there.
    func placeholder(_ hint: String, when empty: Bool) -> some View {
        overlay(alignment: .leading) {
            if empty { Text(hint).foregroundStyle(Theme.faint).lineLimit(1).allowsHitTesting(false) }
        }
    }
}

/// Label / value / footnote tile used across the research functions.
struct StatTile: View {
    let key: String
    let value: String
    var sub: String? = nil
    var color: Color = Theme.text

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(key).font(.mono(8, .bold)).foregroundStyle(Theme.label)
            Text(value).font(.mono(16, .semibold)).monospacedDigit().foregroundStyle(color).lineLimit(1).minimumScaleFactor(0.7)
            Text(sub ?? " ").font(.mono(8)).foregroundStyle(Theme.faint).lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading).padding(8).background(Theme.panel)
    }
}

/// Watchlist instruments usable for return analysis (no option contracts), de-duplicated.
@MainActor func researchBasket(_ symbols: [String], max: Int) -> [Instrument] {
    var seen = Set<String>()
    return Array(symbols.compactMap { Universe.instrument(symbol: $0) ?? Universe.resolve($0) }
        .filter { $0.assetClass != .option && seen.insert($0.symbol).inserted }.prefix(max))
}

extension View {
    /// Tracks the view's laid-out size (tables use the width to decide how many columns fit).
    func readSize(_ size: Binding<CGSize>) -> some View {
        onGeometryChange(for: CGSize.self) { $0.size } action: { size.wrappedValue = $0 }
    }
}

/// How many fixed-width columns fit beside `reserved` points of other content (at least 1).
func columnsThatFit(_ width: CGFloat, reserved: CGFloat, column: CGFloat, max: Int) -> Int {
    guard width > 0 else { return max }
    return Swift.max(1, Swift.min(max, Int((width - reserved) / column)))
}

/// A toolbar row that scrolls sideways instead of forcing a narrow panel wider.
struct ControlBar<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) { content }.padding(8)
        }
        .scrollBounceBehavior(.basedOnSize, axes: .horizontal)
    }
}

/// Kestrel's button style: plain (no chrome) everywhere. On iPad every button also gets Apple's 44 pt minimum touch
/// target; the Mac keeps the dense pointer sizes a terminal needs.
struct TerminalButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.6 : 1)
            #if os(iOS)
            .frame(minWidth: 44, minHeight: 44)
            .contentShape(Rectangle())
            #endif
    }
}

/// Height for bars that hold buttons: 44 pt on iPad (touch), the compact size on Mac.
func barHeight(_ compact: CGFloat) -> CGFloat {
    #if os(iOS)
    max(44, compact)
    #else
    compact
    #endif
}

extension ButtonStyle where Self == TerminalButtonStyle {
    static var terminal: TerminalButtonStyle { TerminalButtonStyle() }
}

/// COPY beside EXPORT CSV: puts the table on the clipboard as tab-separated text, which pastes into Excel or
/// Numbers cells and reads with pandas.read_clipboard().
struct CopyTableButton: View {
    let csv: String
    @State private var copied = false

    var body: some View {
        Button {
            let text = CSV.tsv(fromCSV: csv)
            #if os(iOS)
            UIPasteboard.general.string = text
            #else
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(text, forType: .string)
            #endif
            copied = true
            Task { try? await Task.sleep(for: .seconds(1.5)); copied = false }
        } label: {
            Label(copied ? "COPIED" : "COPY", systemImage: copied ? "checkmark" : "doc.on.doc").font(.mono(10, .bold))
        }
        .buttonStyle(.terminal).foregroundStyle(Theme.accent)
        .help("Copy the table: paste into Excel or Numbers, or pandas.read_clipboard()")
        .accessibilityLabel(copied ? "Copied" : "Copy table")
    }
}

