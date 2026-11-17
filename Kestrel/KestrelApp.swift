import SwiftUI
import KestrelCore

@main
struct KestrelApp: App {
    @State private var market = MarketStore()
    @State private var news = NewsService()
    @State private var auth: AuthService = {
        #if DEBUG
        if SnapshotTour.isEnabled { return SnapshotTour.makeAuth() }
        #endif
        return AuthService()
    }()
    @State private var fundamentals = FundamentalsService()
    @State private var macro = MacroService()

    var body: some Scene {
        WindowGroup {
            AuthGate()
                .environment(market)
                .environment(news)
                .environment(auth)
                .environment(fundamentals)
                .environment(macro)
                .environment(Theme.shared)
                .preferredColorScheme(.dark)
                #if os(macOS)
                .frame(minWidth: 1100, idealWidth: 1600, minHeight: 700, idealHeight: 1000)
                #endif
                .onAppear { market.start() }   // the sign-in screen shows live prices too
        }
        #if os(macOS)
        .defaultSize(width: 1600, height: 1000)
        .windowResizability(.contentMinSize)
        .windowStyle(.hiddenTitleBar)
        #endif
        .commands { TerminalCommands() }
    }
}

/// Shows sign-in until someone is signed in, then that person's terminal. Their paper account,
/// watchlists and alerts load from their own folder and are rebuilt when the user changes.
struct AuthGate: View {
    @Environment(AuthService.self) private var auth
    @Environment(MarketStore.self) private var market
    @Environment(\.scenePhase) private var phase

    var body: some View {
        Group {
            if let space = auth.space {
                WindowRoot()
                    .environment(space.broker)
                    .environment(space.data)
                    .id(space.id)
            } else {
                AuthView()
            }
        }
        #if os(iOS)
        // Hide balances and positions from the app switcher snapshot.
        .overlay { if phase != .active { PrivacyCover() } }
        #endif
        .onAppear(perform: wire)
        .onChange(of: auth.space?.id) { wire() }
    }

    /// Routes quotes to whoever is signed in. One space is shared by every window.
    private func wire() {
        guard let s = auth.space else {
            market.onQuote = nil
            market.extraSymbols = { [] }
            market.heldOptions = { [] }
            return
        }
        let broker = s.broker, userData = s.data
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

/// Shown over the terminal while the app isn't active (iPad app switcher, Control Center).
struct PrivacyCover: View {
    var body: some View {
        ZStack {
            Theme.canvas.ignoresSafeArea()
            HStack(spacing: 12) {
                KestrelMark().frame(width: 30, height: 26)
                Text("KESTREL").font(.mono(22, .heavy)).tracking(6).foregroundStyle(Theme.text)
            }
        }
    }
}
