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
    var size: CGFloat = 12
    @Environment(Theme.self) private var theme

    var body: some View {
        Text(percent ? Fmt.pct(value) : Fmt.signed(value, cls))
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
                Text(detail).font(.ui(11)).foregroundStyle(Theme.faint).multilineTextAlignment(.center).frame(maxWidth: 320)
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
                    .frame(width: 16, height: 16)
                    .background(Theme.accent, in: .rect(cornerRadius: 2))
                Text(title).font(.mono(11, .medium)).foregroundStyle(Theme.text)
            }
            .padding(.horizontal, 8).padding(.vertical, 5)
            .background(Theme.header, in: .rect(cornerRadius: 3))
            .overlay(RoundedRectangle(cornerRadius: 3).stroke(Theme.rule))
        }
        .buttonStyle(.plain)
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
                Capsule().fill(Theme.rule).frame(height: 4)
                if let lo = low, let hi = high, let v = value, hi > lo {
                    let x = g.size.width * CGFloat(min(max((v - lo) / (hi - lo), 0), 1))
                    Capsule().fill(Theme.accentDim).frame(width: x, height: 4)
                    Rectangle().fill(Theme.accent).frame(width: 2, height: 12).offset(x: x - 1)
                }
            }
            .frame(maxHeight: .infinity)
        }
        .frame(height: 12)
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
