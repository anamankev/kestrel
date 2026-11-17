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

    var body: some Scene {
        WindowGroup {
            WindowRoot()
                .environment(market)
                .environment(news)
                .environment(broker)
                .environment(userData)
                .environment(fundamentals)
                .environment(macro)
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
                    market.heldOptions = {
                        let a = broker.account
                        let syms = a.openPositions.map(\.symbol) + a.workingOrders.map(\.symbol)
                        return Set(syms.filter { Deribit.parse($0) != nil })
                    }
                    market.start()
                }
        }
        #if os(macOS)
        .defaultSize(width: 1600, height: 1000)
        .windowResizability(.contentMinSize)
        .windowStyle(.hiddenTitleBar)
        #endif
        .commands { TerminalCommands() }
    }
}

/// Each window owns its workspace (panels, layout, history), restored per window via scene
/// storage, so a desk can run Kestrel across several monitors or Stage Manager windows.
struct WindowRoot: View {
    @SceneStorage("ws.panels") private var savedPanels = ""
    @SceneStorage("ws.layout") private var savedLayout = ""
    @State private var workspace: Workspace?

    var body: some View {
        Group {
            if let workspace {
                TerminalView()
                    .environment(workspace)
                    .focusedSceneValue(\.workspace, workspace)
            } else {
                Theme.canvas
            }
        }
        .onAppear {
            guard workspace == nil else { return }
            let w = Workspace(saved: savedPanels, layout: savedLayout)
            w.persist = { panels, layout in
                savedPanels = panels
                savedLayout = layout
            }
            workspace = w
        }
    }
}

extension FocusedValues {
    @Entry var workspace: Workspace?
}

/// Keyboard map (acts on the focused window): ⌘1–⌘6 focus a panel, ⌘[ back, ⌘↩ maximise, ⌘L layouts.
struct TerminalCommands: Commands {
    @FocusedValue(\.workspace) private var workspace

    var body: some Commands {
        CommandMenu("Panels") {
            ForEach(0..<6, id: \.self) { i in
                Button("Focus Panel \(i + 1)") { workspace?.focus(i) }
                    .keyboardShortcut(KeyEquivalent(Character("\(i + 1)")), modifiers: .command)
            }
            Divider()
            Button("Back") { workspace?.back() }.keyboardShortcut("[", modifiers: .command)
            Button("Maximize Panel") { if let w = workspace { w.toggleMaximize(w.focused) } }
                .keyboardShortcut(.return, modifiers: .command)
            Button("Cycle Layout") {
                guard let w = workspace else { return }
                let all = PanelLayout.allCases
                w.layout = all[(all.firstIndex(of: w.layout)! + 1) % all.count]
            }.keyboardShortcut("l", modifiers: .command)
        }
    }
}
