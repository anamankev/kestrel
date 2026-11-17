import SwiftUI
import KestrelCore

@main
struct KestrelApp: App {
    @State private var market = MarketStore()
    @State private var news = NewsService()
    @State private var broker = PaperBroker()
    @State private var userData = UserData()
    @State private var fundamentals = FundamentalsService()
    @State private var macro = MacroService()
    @State private var workspace = Workspace()

    var body: some Scene {
        WindowGroup {
            TerminalView()
                .environment(market)
                .environment(news)
                .environment(broker)
                .environment(userData)
                .environment(fundamentals)
                .environment(macro)
                .environment(workspace)
                .environment(Theme.shared)
                .preferredColorScheme(.dark)
                #if os(macOS)
                .frame(minWidth: 1100, idealWidth: 1600, minHeight: 700, idealHeight: 1000)
                #endif
                .onAppear {
                    let broker = broker
                    let userData = userData
                    market.onQuote = { symbol, quote in
                        broker.mark(symbol, quote)
                        userData.check(symbol, quote)
                    }
                    market.extraSymbols = { userData.watchedSymbols }
                    market.start()
                }
        }
        #if os(macOS)
        .defaultSize(width: 1600, height: 1000)
        .windowResizability(.contentMinSize)
        .windowStyle(.hiddenTitleBar)
        #endif
        .commands { TerminalCommands(workspace: workspace) }
    }
}

/// Keyboard map: ⌘1–⌘6 focus a panel, ⌘[ goes back, ⌘↩ maximises, ⌘L cycles layouts.
struct TerminalCommands: Commands {
    let workspace: Workspace

    var body: some Commands {
        CommandMenu("Panels") {
            ForEach(0..<6, id: \.self) { i in
                Button("Focus Panel \(i + 1)") { workspace.focus(i) }
                    .keyboardShortcut(KeyEquivalent(Character("\(i + 1)")), modifiers: .command)
            }
            Divider()
            Button("Back") { workspace.back() }.keyboardShortcut("[", modifiers: .command)
            Button("Maximize Panel") { workspace.toggleMaximize(workspace.focused) }
                .keyboardShortcut(.return, modifiers: .command)
            Button("Cycle Layout") {
                let all = PanelLayout.allCases
                workspace.layout = all[(all.firstIndex(of: workspace.layout)! + 1) % all.count]
            }.keyboardShortcut("l", modifiers: .command)
        }
    }
}
