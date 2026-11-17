import Foundation
import KestrelCore

/// One terminal panel: a running function plus its back-stack.
@Observable final class Panel: Identifiable {
    let id: Int
    var command: Command
    var history: [Command] = []
    var side: TradeSide?

    init(id: Int, command: Command) {
        self.id = id
        self.command = command
    }

    var canGoBack: Bool { !history.isEmpty }
}

enum PanelLayout: String, CaseIterable, Identifiable {
    case one = "1", two = "2", four = "4", six = "6"
    var id: String { rawValue }
    var count: Int { Int(rawValue)! }
    var symbol: String {
        switch self {
        case .one: "square"
        case .two: "rectangle.split.2x1"
        case .four: "square.grid.2x2"
        case .six: "square.grid.3x2"
        }
    }
}

/// Panel arrangement, focus and command routing. Persisted across launches.
@Observable final class Workspace {
    let panels: [Panel]
    var focused: Int = 0
    var layout: PanelLayout {
        didSet { persist?(serializedPanels, layout.rawValue) }
    }
    var error: String?
    var maximized: Int?

    static let defaults = ["BTC CRYPTO GP", "W", "BTC CRYPTO DEPTH", "TOP", "BTC CRYPTO TAS", "WEI"]

    /// Writes this window's state (scene storage), so every window restores its own panels.
    @ObservationIgnored var persist: ((String, String) -> Void)?

    /// Numbered hotspots each panel publishes, for `n <GO>`.
    enum Hotspot { case command(Command), link(Instrument) }
    @ObservationIgnored var hotspots: [Int: [Hotspot]] = [:]

    /// - Parameters: `saved` is the panel commands joined by "|" (empty → legacy/global defaults).
    init(saved: String = "", layout savedLayout: String = "") {
        let list = saved.isEmpty
            ? (UserDefaults.standard.stringArray(forKey: "panels") ?? Self.defaults)
            : saved.components(separatedBy: "|")
        panels = (0..<6).map { i in
            let text = list[safe: i] ?? Self.defaults[i]
            let cmd = (try? CommandParser.parse(text, current: nil)) ?? (try! CommandParser.parse(Self.defaults[i], current: nil))
            return Panel(id: i, command: cmd)
        }
        let l = savedLayout.isEmpty ? (UserDefaults.standard.string(forKey: "layout") ?? "") : savedLayout
        layout = PanelLayout(rawValue: l) ?? .four
    }

    var serializedPanels: String { panels.map { Self.text(for: $0.command) }.joined(separator: "|") }

    // MARK: Pages (named layouts, like Launchpad views)

    struct Page: Codable, Identifiable, Equatable { var name: String; var layout: String; var panels: String; var id: String { name } }

    static var pages: [Page] {
        get { (UserDefaults.standard.data(forKey: "pages")).flatMap { try? JSONDecoder().decode([Page].self, from: $0) } ?? [] }
        set { UserDefaults.standard.set(try? JSONEncoder().encode(Array(newValue.prefix(12))), forKey: "pages") }
    }

    func savePage(_ raw: String) {
        let name = String(raw.trimmingCharacters(in: .whitespaces).uppercased().prefix(20))
        guard !name.isEmpty else { return }
        var all = Self.pages.filter { $0.name != name }
        all.append(Page(name: name, layout: layout.rawValue, panels: serializedPanels))
        Self.pages = all
    }

    func open(_ page: Page) {
        let list = page.panels.components(separatedBy: "|")
        for (i, p) in panels.enumerated() {
            if let t = list[safe: i], let cmd = try? CommandParser.parse(t, current: nil), cmd != p.command {
                p.history.append(p.command)
                p.command = cmd
            }
        }
        maximized = nil
        layout = PanelLayout(rawValue: page.layout) ?? layout
        focused = 0
        save()
    }

    static func deletePage(_ name: String) { pages = pages.filter { $0.name != name } }

    var visible: [Panel] {
        if let m = maximized { return [panels[m]] }
        return Array(panels.prefix(layout.count))
    }

    var focusedPanel: Panel { panels[focused] }

    /// Security loaded in the focused panel, used when a function is typed without one.
    var currentInstrument: Instrument? { focusedPanel.command.instrument }

    /// Parses and runs a command line in the focused panel. Returns false on error.
    @discardableResult
    func run(_ text: String) -> Bool {
        // `n <GO>`: drill into numbered item n of the focused panel.
        let bare = CommandParser.tokens(text)
        if bare.count == 1, let n = Int(bare[0]) {
            guard let list = hotspots[focused], (1...list.count).contains(n) else {
                error = "No item \(n) on this screen"
                return false
            }
            switch list[n - 1] {
            case .command(let c): load(c, in: focused)
            case .link(let i): link(i, from: focused)
            }
            error = nil
            return true
        }
        do {
            let cmd = try CommandParser.parse(text, current: currentInstrument)
            load(cmd, in: focused)
            error = nil
            return true
        } catch {
            self.error = error.errorDescription
            return false
        }
    }

    func load(_ cmd: Command, in index: Int) {
        let p = panels[index]
        if p.command != cmd { p.history.append(p.command) }
        if p.history.count > 50 { p.history.removeFirst() }
        p.command = cmd
        p.side = cmd.side
        focused = index
        save()
    }

    /// Security linking: picking a security in a list panel retargets every other panel that
    /// is showing a security function (chart, depth, tape, news, ticket, description).
    func link(_ i: Instrument, from source: Int) {
        var linked = false
        for p in panels.prefix(layout.count) where p.id != source && p.command.function.requiresSecurity {
            if p.command.instrument != i {
                p.history.append(p.command)
                p.command.instrument = i
            }
            linked = true
        }
        if !linked {
            let target = panels.prefix(layout.count).first { $0.id != source }?.id ?? source
            load(Command(function: .gp, instrument: i), in: target)
        }
        save()
    }

    func back(_ index: Int? = nil) {
        let p = panels[index ?? focused]
        guard let prev = p.history.popLast() else { return }
        p.command = prev
        save()
    }

    func focus(_ i: Int) {
        guard i < panels.count else { return }
        if i >= layout.count && maximized == nil { layout = i < 2 ? .two : i < 4 ? .four : .six }
        focused = i
    }

    func toggleMaximize(_ i: Int) { maximized = maximized == i ? nil : i; focused = i }

    private func save() {
        persist?(serializedPanels, layout.rawValue)
    }

    static func text(for c: Command) -> String {
        [c.instrument.map { "\($0.ticker) \($0.assetClass.rawValue)" }, c.function.rawValue]
            .compactMap { $0 }.joined(separator: " ")
    }

    /// Securities on screen, for the fast refresh cycle.
    var symbolsOnScreen: Set<String> { Set(visible.compactMap { $0.command.instrument?.symbol }) }
}

extension Array {
    subscript(safe i: Int) -> Element? { indices.contains(i) ? self[i] : nil }
}
