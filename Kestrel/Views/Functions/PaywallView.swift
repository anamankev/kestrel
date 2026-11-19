import SwiftUI
import StoreKit
import KestrelCore

/// The subscribe page (Kestrel is subscription-only) and, for subscribers, PRO's plan status:
/// the three plans, the renewal terms App Review requires, restore, and management.
struct PaywallView: View {
    /// The function that led here, if any.
    var feature: ProFeature?
    @Environment(SubscriptionStore.self) private var store
    @Environment(AuthService.self) private var auth
    @Environment(Theme.self) private var theme
    @Environment(\.openURL) private var openURL
    @State private var selected: ProPlan = .annual
    @State private var managing = false

    static let included = [
        "Live crypto order book, trades and charts, with indicators and trendlines",
        "Stocks, indices, FX, commodities and Treasury rates; heat map and movers",
        "News search, SEC filings, financials and an earnings calendar (ERN)",
        "Options monitor with greeks, and the strategy builder (OSA)",
        "Strategy backtester (BT) and correlation matrix (CORR)",
        "Paper trading with stops, risk and VaR; up to 6 panels; alerts, even when closed",
    ]

    static let terms = URL(string: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/")!
    static let privacy = URL(string: "https://github.com/anamankev/kestrel/blob/main/docs/PRIVACY.md")!

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header
                if store.isPro { status } else { plans }
                features
                footer
            }
            .padding(16)
            .frame(maxWidth: 760.pt, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .task { if store.products.isEmpty { await store.loadProducts() } }
        #if os(iOS)
        .manageSubscriptionsSheet(isPresented: $managing)
        #endif
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("KESTREL PRO").font(.ui(12, .semibold)).tracking(1.5).foregroundStyle(Theme.accent)
            Text(store.isPro ? "You're subscribed." : "Subscribe to Kestrel")
                .font(.ui(26, .semibold)).foregroundStyle(Theme.text)
            Text(store.isPro ? "Your subscription includes everything in Kestrel." : "Kestrel is a subscription. Choose a plan to start; everything below is included.")
                .font(.ui(13)).foregroundStyle(Theme.dim)
        }
    }

    private var plans: some View {
        let monthly = store.product(.monthly)?.price
        return VStack(alignment: .leading, spacing: 10) {
            if let e = store.loadError, store.products.isEmpty {
                Text(e).font(.ui(12)).foregroundStyle(Theme.cancel)
            }
            HStack(alignment: .top, spacing: 10) {
                ForEach(ProPlan.allCases.reversed(), id: \.self) { plan in planCard(plan, monthly: monthly) }
            }
            .fixedSize(horizontal: false, vertical: true)   // equal-height cards
            Text("Crossed-out prices are what the same period costs on the monthly plan.")
                .font(.ui(11)).foregroundStyle(Theme.faint)
            Button {
                Task { await store.purchase(selected, account: auth.current?.id) }
            } label: {
                HStack(spacing: 8) {
                    if store.purchasing != nil { ProgressView().controlSize(.small).tint(Theme.canvas) }
                    Text(store.product(selected).map { "Subscribe · \($0.displayPrice) / \(selected.periodLabel)" } ?? "Subscribe")
                        .font(.ui(15, .semibold))
                }
                .foregroundStyle(Theme.canvas).frame(maxWidth: .infinity).frame(height: 44.pt)
                .background(Theme.accent, in: .rect(cornerRadius: 3))
                .opacity(store.product(selected) == nil || store.purchasing != nil ? 0.5 : 1)
            }
            .buttonStyle(.terminal)
            .disabled(store.product(selected) == nil || store.purchasing != nil)
            if let m = store.message { Text(m).font(.ui(12, .medium)).foregroundStyle(store.isPro ? theme.up : Theme.warn) }
        }
    }

    private func planCard(_ plan: ProPlan, monthly: Decimal?) -> some View {
        let p = store.product(plan)
        let on = selected == plan
        return Button { selected = plan } label: {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(plan.title).font(.ui(11, .semibold)).foregroundStyle(on ? Theme.accent : Theme.label)
                    Spacer()
                    if let p, let m = monthly, let save = plan.saving(price: p.price, monthlyPrice: m) {
                        Text("Save \(Int((save * 100).rounded()))%").font(.ui(11, .semibold)).foregroundStyle(Theme.canvas)
                            .padding(.horizontal, 5).frame(height: 16.pt).background(theme.up, in: .rect(cornerRadius: 2))
                    }
                }
                // Crossed-out price = the same period on the monthly plan (never an invented "was" price).
                if let p, let m = monthly, let ref = plan.referencePrice(monthlyPrice: m) {
                    Text(p.priceFormatStyle.format(ref)).font(.ui(13)).strikethrough().foregroundStyle(Theme.faint)
                        .accessibilityLabel("\(p.priceFormatStyle.format(ref)) if paid monthly")
                } else {
                    Text(" ").font(.ui(13))
                }
                Text(p?.displayPrice ?? "—").font(.ui(28, .semibold)).monospacedDigit().foregroundStyle(Theme.text)
                Text("per \(plan.periodLabel)").font(.ui(11)).foregroundStyle(Theme.dim)
                if let p, plan != .monthly {
                    Text(p.priceFormatStyle.format(plan.perMonth(p.price)) + " / month").font(.ui(11)).foregroundStyle(Theme.faint)
                } else {
                    Text(" ").font(.ui(11))
                }
            }
            .padding(12).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(Theme.panel)
            .overlay(RoundedRectangle(cornerRadius: 3).stroke(on ? Theme.accent : Theme.rule, lineWidth: on ? 1.5 : 1))
            .contentShape(.rect)
        }
        .buttonStyle(.terminal)
    }

    private var status: some View {
        VStack(alignment: .leading, spacing: 6) {
            if case .pro(let plan, let expires, let willRenew) = store.entitlement {
                Text("Plan: \(plan.title)").font(.ui(15, .semibold)).foregroundStyle(Theme.text)
                if let expires {
                    Text("\(willRenew ? "Renews" : "Ends") \(expires.formatted(.dateTime.month(.wide).day().year()))")
                        .font(.ui(12)).foregroundStyle(willRenew ? Theme.dim : Theme.warn)
                }
            }
            Button("Manage subscription") {
                #if os(iOS)
                managing = true
                #else
                openURL(URL(string: "https://apps.apple.com/account/subscriptions")!)
                #endif
            }
            .font(.ui(12, .bold)).foregroundStyle(Theme.accent).buttonStyle(.terminal)
        }
        .padding(12).frame(maxWidth: .infinity, alignment: .leading).background(Theme.panel)
    }

    private var features: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Included").font(.ui(11, .bold)).foregroundStyle(Theme.label)
            ForEach(Self.included, id: \.self) { line in
                Label(line, systemImage: "checkmark").font(.ui(12)).foregroundStyle(Theme.dim)
            }
        }
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Payment is charged to your Apple ID when you confirm. Subscriptions renew automatically at the same price and period unless cancelled at least 24 hours before the current period ends; your account is charged for renewal within 24 hours before that. Manage or cancel anytime in your Apple ID's subscription settings. Paper trading only: Pro does not connect a brokerage or move real money.")
                .font(.ui(10)).foregroundStyle(Theme.faint).fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 16) {
                Button("Restore purchases") { Task { await store.restore() } }
                Link("Terms of Use", destination: Self.terms)
                Link("Privacy Policy", destination: Self.privacy)
            }
            .font(.ui(11, .semibold)).foregroundStyle(Theme.accent).buttonStyle(.terminal)
        }
    }
}

/// Full-screen subscribe page shown at launch until this Apple ID has an active subscription.
/// No account is needed to buy (the subscription belongs to the Apple ID); sign-in comes after.
struct SubscribeGate: View {
    @Environment(AuthService.self) private var auth

    var body: some View {
        ZStack(alignment: .top) {
            Theme.canvas.ignoresSafeArea()
            VStack(spacing: 0) {
                HStack(spacing: 12) {
                    KestrelMark().frame(width: 26.pt, height: 22.pt)
                    Text("KESTREL").font(.mono(20, .heavy)).tracking(6).foregroundStyle(Theme.text)
                    Spacer()
                    if auth.current != nil {
                        Button("Sign out") { auth.signOut() }
                            .font(.ui(12, .semibold)).foregroundStyle(Theme.dim).buttonStyle(.terminal)
                    }
                }
                .padding(.horizontal, 24).padding(.top, 20)
                PaywallView()
            }
        }
        #if DEBUG
        .task { if SnapshotTour.isEnabled { await SnapshotTour.subscribeStep() } else if DemoTour.isEnabled { await DemoTour.subscribeStep() } }
        #endif
    }
}
