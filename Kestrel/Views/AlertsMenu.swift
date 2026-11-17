#if os(macOS)
import SwiftUI
import KestrelCore

/// The Mac menu-bar item: armed alerts with live distance to trigger, and a way back in.
struct AlertsMenu: View {
    @Environment(AuthService.self) private var auth
    @Environment(MarketStore.self) private var market
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        if let data = auth.space?.data {
            let active = data.alerts.active
            Text(active.isEmpty ? "No alerts armed" : "\(active.count) alert\(active.count == 1 ? "" : "s") armed · watching live")
            if !active.isEmpty { Divider() }
            ForEach(active.prefix(12)) { a in
                let ticker = Universe.instrument(symbol: a.symbol)?.ticker ?? a.symbol
                let last = market.quotes[a.symbol]?.last
                Text("\(ticker)  \(a.condition.label)  ·  last \(Fmt.price(last))")
            }
        } else {
            Text("Signed out: alerts paused")
        }
        Divider()
        Button("Open Kestrel") { NSApp.activate(); openWindow(id: "terminal") }
            .keyboardShortcut("o")
        Button("Quit Kestrel") { NSApp.terminate(nil) }
            .keyboardShortcut("q")
    }
}
#endif
