import SwiftUI
import KestrelCore

extension Color {
    init(hex: UInt32, opacity: Double = 1) {
        self.init(.sRGB,
                  red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255,
                  opacity: opacity)
    }
}

/// Kestrel's identity: graphite canvas, ice-cyan accent, crisp white figures.
/// Up/down colours switch to a blue/orange pair for colour-vision deficiency.
@Observable final class Theme {
    static let shared = Theme()

    var colorBlindSafe: Bool = UserDefaults.standard.bool(forKey: "cvd") {
        didSet { UserDefaults.standard.set(colorBlindSafe, forKey: "cvd") }
    }

    /// Text size chosen in PREF (0.9 to 1.5). Every `Font.mono`/`Font.ui` size is multiplied by it, and by the
    /// system text size (Dynamic Type on iPad), capped at 1.5 in total so the dense terminal stays usable.
    static let textScales: [Double] = [0.9, 1.0, 1.15, 1.3, 1.5]
    var textScale: Double = Theme.storedTextScale() {
        didSet { UserDefaults.standard.set(textScale, forKey: "textScale") }
    }
    private static func storedTextScale() -> Double {
        let v = UserDefaults.standard.double(forKey: "textScale")
        return textScales.contains(v) ? v : 1
    }

    /// The factor fonts use right now; set by `ScaledRoot` before the view tree is (re)built.
    nonisolated(unsafe) static var fontScale: CGFloat = 1

    static func dynamicTypeFactor(_ size: DynamicTypeSize) -> Double {
        switch size {
        case .xSmall: 0.82
        case .small: 0.88
        case .medium: 0.94
        case .large: 1
        case .xLarge: 1.12
        case .xxLarge: 1.24
        case .xxxLarge: 1.35
        default: 1.5            // accessibility sizes
        }
    }

    static let canvas = Color(hex: 0x05070A)
    static let panel = Color(hex: 0x0A0E13)
    static let header = Color(hex: 0x0F151C)
    static let rule = Color(hex: 0x1A232E)
    static let rowAlt = Color(hex: 0x0D1218)
    static let selection = Color(hex: 0x12324A)
    static let text = Color(hex: 0xE4EAF0)
    static let dim = Color(hex: 0x95A1AF)      // WCAG AA: ≥ 5:1 on every surface, highlighted rows included
    static let faint = Color(hex: 0x7A8694)    // WCAG AA: ≥ 4.9:1 on every text surface
    static let accent = Color(hex: 0x3CD6FF)
    static let accentDim = Color(hex: 0x1E6F88)
    static let label = Color(hex: 0x8FB7C9)
    static let warn = Color(hex: 0xFFC24A)
    static let go = Color(hex: 0x1FCB6E)
    static let cancel = Color(hex: 0xE5484D)

    var up: Color { colorBlindSafe ? Color(hex: 0x3FA7FF) : Color(hex: 0x22D27A) }
    var down: Color { colorBlindSafe ? Color(hex: 0xFF9F1C) : Color(hex: 0xFF4D5E) }

    func tint(_ value: Double?) -> Color {
        guard let value, value != 0 else { return Theme.text }
        return value > 0 ? up : down
    }
}

extension Font {
    static func mono(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        .system(size: size * Theme.fontScale, weight: weight, design: .monospaced)
    }
    static func ui(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        .system(size: size * Theme.fontScale, weight: weight, design: .default)
    }
}

/// Layout sizes that sit next to text (column widths, row heights) grow with the text size, so columns stay aligned
/// and nothing truncates at 130–150%. `64.pt` is 64 points at 100%.
extension BinaryInteger { var pt: CGFloat { CGFloat(Int(self)) * Theme.fontScale } }
extension Double { var pt: CGFloat { CGFloat(self) * Theme.fontScale } }

/// Applies the text size (PREF setting × system Dynamic Type, capped at 1.5) and rebuilds the tree when it changes,
/// because the font helpers read a static factor.
struct ScaledRoot<Content: View>: View {
    @Environment(Theme.self) private var theme
    @Environment(\.dynamicTypeSize) private var dynamicType
    @ViewBuilder var content: Content

    var body: some View {
        let scale = min(theme.textScale * Theme.dynamicTypeFactor(dynamicType), 1.5)
        let _ = { Theme.fontScale = scale }()
        content.id(scale)
    }
}

nonisolated enum Fmt {
    /// Decimal places appropriate to the instrument and price magnitude.
    static func places(_ v: Double, _ cls: AssetClass? = nil) -> Int {
        switch cls {
        case .fx: return v > 20 ? 3 : 4
        case .rate: return 3
        default:
            let a = abs(v)
            return a >= 1000 ? 2 : a >= 1 ? 2 : a >= 0.01 ? 4 : 6
        }
    }

    static func price(_ v: Double?, _ cls: AssetClass? = nil) -> String {
        guard let v, v.isFinite else { return "—" }
        return v.formatted(.number.precision(.fractionLength(places(v, cls))).grouping(.automatic))
    }

    /// Formats `v` with the same precision as a reference price (e.g. a spread next to its mid).
    static func price(_ v: Double?, like ref: Double?, _ cls: AssetClass? = nil) -> String {
        guard let v, v.isFinite else { return "—" }
        return v.formatted(.number.precision(.fractionLength(places(ref ?? v, cls))))
    }

    static func signed(_ v: Double?, _ cls: AssetClass? = nil) -> String {
        guard let v, v.isFinite else { return "—" }
        return (v > 0 ? "+" : "") + price(v, cls)
    }

    static func pct(_ v: Double?) -> String {
        guard let v, v.isFinite else { return "—" }
        return (v > 0 ? "+" : "") + v.formatted(.number.precision(.fractionLength(2))) + "%"
    }

    static func compact(_ v: Double?) -> String {
        guard let v, v.isFinite else { return "—" }
        let a = abs(v)
        let (d, s): (Double, String) = a >= 1e12 ? (1e12, "T") : a >= 1e9 ? (1e9, "B") : a >= 1e6 ? (1e6, "M") : a >= 1e3 ? (1e3, "K") : (1, "")
        return (v / d).formatted(.number.precision(.fractionLength(s.isEmpty ? 0 : 2))) + s
    }

    static func size(_ v: Double) -> String {
        v >= 1000 ? compact(v) : v.formatted(.number.precision(.fractionLength(v >= 1 ? 3 : 5)))
    }

    static func money(_ d: Decimal) -> String { d.formatted(.currency(code: "USD").precision(.fractionLength(2))) }

    static func qty(_ d: Decimal) -> String { d.formatted(.number.precision(.fractionLength(0...8))) }

    /// 24-hour HH:mm:ss whatever the device's 12/24-hour setting: with AM/PM omitted, a
    /// 12-hour locale would show 7:53 PM as "07:53".
    static let clock: Date.FormatStyle = Date.FormatStyle().locale(Locale(identifier: "en_GB"))
        .hour(.twoDigits(amPM: .omitted)).minute(.twoDigits).second(.twoDigits)
}
