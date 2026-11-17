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
    @State private var store = SubscriptionStore()
    @Environment(\.scenePhase) private var phase

    var body: some Scene {
        WindowGroup(id: "terminal") {
            SizeIsolated { AuthGate() }
                .environment(market)
                .environment(news)
                .environment(auth)
                .environment(fundamentals)
                .environment(macro)
                .environment(store)
                .environment(Theme.shared)
                .preferredColorScheme(.dark)
                #if os(macOS)
                .frame(minWidth: 1100, idealWidth: 1600, minHeight: 700, idealHeight: 1000)
                #endif
                .onAppear {
                    market.start()   // the sign-in screen shows live prices too
                    BackgroundAlerts.auth = auth
                    BackgroundAlerts.market = market
                    BackgroundAlerts.store = store
                    store.start()
                }
        }
        #if os(macOS)
        .defaultSize(width: 1600, height: 1000)
        .windowResizability(.contentMinSize)
        .windowStyle(.hiddenTitleBar)
        #endif
        .commands { TerminalCommands() }
        #if os(iOS)
        // A background launch may not build any views, so the task wires itself up.
        .backgroundTask(.appRefresh(BackgroundAlerts.taskID)) {
            await MainActor.run {
                if BackgroundAlerts.auth == nil { BackgroundAlerts.auth = auth; BackgroundAlerts.market = market; BackgroundAlerts.store = store }
            }
            await BackgroundAlerts.handleRefresh()
        }
        .onChange(of: phase) { if phase == .background { BackgroundAlerts.schedule() } }
        #endif
        #if os(macOS)
        // Closing the window keeps Kestrel (and its alerts) running from the menu bar.
        MenuBarExtra(isInserted: .constant(store.isPro)) {
            AlertsMenu().environment(auth).environment(market)
        } label: {
            Image(systemName: auth.space?.data.alerts.active.isEmpty == false ? "bell.badge.fill" : "bell")
        }
        #endif
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

/// The window's size must come only from its own frame limits, never from what a panel happens to
/// contain. A GeometryReader has no intrinsic size, so content wider than the window (a long
/// unbreakable headline, a wide table) is laid out in the space given and clipped, instead of
/// stretching the window across the screen, which happened twice on the Mac.
struct SizeIsolated<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        #if os(macOS)
        GeometryReader { g in
            content.frame(width: g.size.width, height: g.size.height).clipped()
        }
        #else
        content   // iPad windows are sized by the system, not by content; keep full-bleed backgrounds
        #endif
    }
}
