import SwiftUI
import KestrelCore

/// PREF: data-source settings, display options and data resets.
struct SettingsView: View {
    @Environment(FundamentalsService.self) private var sec
    @Environment(MarketStore.self) private var market
    @Environment(PaperBroker.self) private var broker
    @Environment(UserData.self) private var user
    @Environment(AuthService.self) private var auth
    @Environment(Theme.self) private var theme
    @State private var deleting = false
    @State private var deletePassword = ""
    @State private var deleteError: String?
    @AppStorage("universeInterval") private var interval: Double = 45

    @State private var contactDraft = ""
    @State private var confirm: Reset?

    enum Reset: String, Identifiable { case paper, alerts, lists; var id: String { rawValue } }

    var body: some View {
        @Bindable var theme = theme
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                account
                section("SEC EDGAR CONTACT (FOR FA)") {
                    Text("SEC's free API requires each app to identify itself with a contact email in its User-Agent. It is stored on this device and sent only to sec.gov.")
                        .font(.ui(11)).foregroundStyle(Theme.dim)
                    HStack(spacing: 8) {
                        TextField("", text: $contactDraft)
                .placeholder("you@example.com", when: contactDraft.isEmpty)
                            .font(.mono(13)).foregroundStyle(Theme.text).textFieldStyle(.plain)
                            .autocorrectionDisabled()
                            #if os(iOS)
                            .textInputAutocapitalization(.never).keyboardType(.emailAddress)
                            #endif
                            .padding(.horizontal, 8).frame(height: 32)
                            .background(Theme.canvas).overlay(Rectangle().stroke(Theme.rule))
                            .onSubmit(saveContact)
                        Button("SAVE", action: saveContact).font(.mono(11, .heavy)).foregroundStyle(Theme.canvas)
                            .frame(width: 64, height: 32).background(Theme.accent, in: .rect(cornerRadius: 3)).buttonStyle(.plain)
                            .disabled(!SECFacts.isValidContact(contactDraft))
                            .opacity(SECFacts.isValidContact(contactDraft) ? 1 : 0.4)
                    }
                    Text(sec.hasValidContact ? "Active: \(sec.contact)" : "Not set: FA is disabled.")
                        .font(.mono(10)).foregroundStyle(sec.hasValidContact ? theme.up : Theme.warn)
                    if sec.hasValidContact {
                        Button("Remove contact") { sec.contact = ""; contactDraft = "" }
                            .font(.mono(10, .bold)).foregroundStyle(Theme.cancel).buttonStyle(.plain)
                    }
                }

                section("DISPLAY") {
                    Toggle(isOn: $theme.colorBlindSafe) {
                        Text("Colour-vision-safe up/down colours (blue/orange)").font(.ui(12)).foregroundStyle(Theme.text)
                    }
                    .tint(Theme.accent)
                    HStack {
                        Text("Text size").font(.ui(12)).foregroundStyle(Theme.text)
                        Spacer()
                        Picker("Text size", selection: $theme.textScale) {
                            ForEach(Theme.textScales, id: \.self) { s in Text("\(Int((s * 100).rounded()))%").tag(s) }
                        }
                        .pickerStyle(.segmented).labelsHidden().frame(maxWidth: 320)
                    }
                    Text("Also follows your iPad's text size (Settings → Display & Brightness), up to 150% in total.")
                        .font(.ui(10)).foregroundStyle(Theme.dim)
                }

                section("DATA") {
                    HStack {
                        Text("Delayed-quote refresh").font(.ui(12)).foregroundStyle(Theme.text)
                        Spacer()
                        Picker("", selection: $interval) {
                            Text("30 s").tag(30.0); Text("45 s").tag(45.0); Text("90 s").tag(90.0)
                        }
                        .pickerStyle(.segmented).labelsHidden().frame(width: 200)
                    }
                    Text("Shorter is fresher but sends more requests to a free endpoint. Crypto always streams live.")
                        .font(.ui(10)).foregroundStyle(Theme.faint)
                    sourceRow("Crypto quotes, depth, tape", "Coinbase WebSocket", market.link.rawValue)
                    sourceRow("Equities, indices, FX, rates", "Yahoo Finance (delayed)", market.lastEquityRefresh.map { "UPDATED \($0.formatted(Fmt.clock))" } ?? "LOADING")
                    sourceRow("Options", "Deribit public API", "ON DEMAND")
                    sourceRow("Fundamentals", "SEC EDGAR", sec.hasValidContact ? "READY" : "NEEDS CONTACT")
                    sourceRow("News", "CNBC, MarketWatch, CoinDesk, Yahoo RSS", "2 MIN")
                }

                section("DIAGNOSTICS") {
                    diag("Messages / second", String(format: "%.0f", market.messagesPerSecond))
                    diag("Feed latency p50 / p95", ms(market.feedLatencyP50) + " / " + ms(market.feedLatencyP95),
                         "Coinbase send → local receipt, clock-offset corrected (± " + ms(market.clockUncertaintyMs) + ")")
                    diag("Clock offset vs Coinbase", ms(market.clockOffsetMs), "NTP-style, best of 5 round trips")
                    diag("Decode + book update p50 / p99", us(market.processP50) + " / " + us(market.processP99), "per message, off the main thread")
                    diag("Main-thread merge p50 / p99", us(market.mainApplyP50) + " / " + us(market.mainApplyP99), "per 100 ms batch")
                    HStack { Text("Render loop").font(.ui(12)).foregroundStyle(Theme.text); Spacer(); FrameMeter() }
                }

                section("SUBSCRIPTION") { SubscriptionStatusRow() }

                section("TRANSFER BETWEEN IPAD AND MAC") { TransferSection() }

                section("RESET") {
                    HStack(spacing: 8) {
                        resetButton("Reset paper account", .paper)
                        resetButton("Clear alerts", .alerts)
                        resetButton("Reset watchlists", .lists)
                    }
                }

                Text("Kestrel \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "") · no API keys; accounts and data stay on this device.")
                    .font(.mono(9)).foregroundStyle(Theme.faint)
            }
            .padding(12)
        }
        .onAppear { contactDraft = sec.contact }
        .confirmationDialog("This cannot be undone.", isPresented: Binding(get: { confirm != nil }, set: { if !$0 { confirm = nil } }), titleVisibility: .visible) {
            Button("Reset", role: .destructive) {
                switch confirm {
                case .paper: broker.reset()
                case .alerts: user.resetAlerts()
                case .lists: user.resetWatchlists()
                case nil: break
                }
            }
        }
    }

    private func ms(_ v: Double?) -> String { v.map { String(format: "%.0f ms", $0) } ?? "—" }
    private func us(_ v: Double?) -> String { v.map { $0 >= 1000 ? String(format: "%.2f ms", $0 / 1000) : String(format: "%.0f µs", $0) } ?? "—" }

    private func diag(_ k: String, _ v: String, _ note: String? = nil) -> some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 1) {
                Text(k).font(.ui(12)).foregroundStyle(Theme.text)
                if let note { Text(note).font(.ui(10)).foregroundStyle(Theme.faint) }
            }
            Spacer()
            Text(v).font(.mono(12, .semibold)).monospacedDigit().foregroundStyle(Theme.accent)
        }
    }

    private func saveContact() {
        let c = contactDraft.trimmingCharacters(in: .whitespaces)
        if SECFacts.isValidContact(c) { sec.contact = c }
    }

    @ViewBuilder private var account: some View {
        if let me = auth.current {
            section("ACCOUNT") {
                HStack(spacing: 10) {
                    Text(me.initials).font(.mono(12, .heavy)).foregroundStyle(Theme.canvas)
                        .frame(width: 32, height: 32).background(Theme.accent, in: .circle)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(me.displayName).font(.ui(13, .semibold)).foregroundStyle(Theme.text)
                        Text(me.email + " · since " + me.created.formatted(.dateTime.month(.abbreviated).year()))
                            .font(.mono(10)).foregroundStyle(Theme.dim)
                    }
                    Spacer()
                    Button { auth.signOut() } label: {
                        Text("Sign out").font(.mono(11, .bold)).foregroundStyle(Theme.text)
                            .padding(.horizontal, 12).frame(height: 28).overlay(RoundedRectangle(cornerRadius: 3).stroke(Theme.rule))
                    }
                    .buttonStyle(.plain)
                }
                if deleting {
                    HStack(spacing: 8) {
                        SecureField("", text: $deletePassword)
                .placeholder("Password to confirm", when: deletePassword.isEmpty)
                            .font(.mono(12)).foregroundStyle(Theme.text).textFieldStyle(.plain)
                            .padding(.horizontal, 8).frame(height: 30).background(Theme.canvas).overlay(Rectangle().stroke(Theme.rule))
                        Button {
                            Task {
                                do throws(AuthError) { try await auth.deleteAccount(password: deletePassword) }
                                catch { deleteError = error.errorDescription; deletePassword = "" }
                            }
                        } label: {
                            Text(auth.busy ? "Deleting…" : "Delete forever").font(.mono(11, .bold)).foregroundStyle(Theme.canvas)
                                .padding(.horizontal, 12).frame(height: 30).background(Theme.cancel, in: .rect(cornerRadius: 3))
                        }
                        .buttonStyle(.plain).disabled(deletePassword.isEmpty || auth.busy)
                        Button("Keep") { deleting = false; deletePassword = ""; deleteError = nil }
                            .font(.mono(11, .bold)).foregroundStyle(Theme.dim).buttonStyle(.plain)
                    }
                    Text(deleteError ?? "Removes this account and its paper book, watchlists and alerts from this device. This cannot be undone.")
                        .font(.mono(10)).foregroundStyle(deleteError == nil ? Theme.dim : Theme.cancel)
                } else {
                    Button("Delete account…") { deleting = true }
                        .font(.mono(10, .semibold)).foregroundStyle(Theme.cancel).buttonStyle(.plain)
                }
            }
        }
    }

    private func section(_ title: String, @ViewBuilder _ content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.mono(10, .heavy)).foregroundStyle(Theme.accent)
            content()
        }
        .padding(10)
        .frame(maxWidth: 720, alignment: .leading)
        .background(Theme.header, in: .rect(cornerRadius: 4))
    }

    private func sourceRow(_ what: String, _ source: String, _ status: String) -> some View {
        HStack {
            Text(what).font(.ui(11)).foregroundStyle(Theme.text)
            Spacer()
            Text(source).font(.ui(11)).foregroundStyle(Theme.dim)
            Text(status).font(.mono(9, .bold)).foregroundStyle(Theme.label).frame(width: 140, alignment: .trailing)
        }
    }

    private func resetButton(_ title: String, _ r: Reset) -> some View {
        Button(title) { confirm = r }
            .font(.mono(10, .bold)).foregroundStyle(Theme.cancel)
            .padding(.horizontal, 10).frame(height: 26)
            .overlay(RoundedRectangle(cornerRadius: 3).stroke(Theme.cancel.opacity(0.5)))
            .buttonStyle(.plain)
    }
}


/// Frames the SwiftUI render loop actually delivers per second (sampled over 1 s).
struct FrameMeter: View {
    /// Plain reference type: counting must not itself trigger SwiftUI invalidations.
    final class Counter {
        var frames = 0, start = Date(), fps = 0.0
        func tick(_ now: Date) -> Double {
            frames += 1
            let dt = now.timeIntervalSince(start)
            if dt >= 1 { fps = Double(frames) / dt; frames = 0; start = now }
            return fps
        }
    }
    @State private var counter = Counter()

    var body: some View {
        TimelineView(.animation) { ctx in
            Text(String(format: "%.0f fps", counter.tick(ctx.date)))
                .font(.mono(12, .semibold)).monospacedDigit().foregroundStyle(Theme.accent)
        }
    }
}

struct SubscriptionStatusRow: View {
    @Environment(SubscriptionStore.self) private var store
    @Environment(Workspace.self) private var ws

    var body: some View {
        HStack {
            switch store.entitlement {
            case .free:
                Text("No active subscription.")
                    .font(.ui(11)).foregroundStyle(Theme.dim)
            case .pro(let plan, let expires, let willRenew):
                Text("Kestrel Pro · \(plan.title)" + (expires.map { " · \(willRenew ? "renews" : "ends") \($0.formatted(.dateTime.month(.abbreviated).day().year()))" } ?? ""))
                    .font(.mono(11, .semibold)).foregroundStyle(Theme.text)
            }
            Spacer()
            Button(store.isPro ? "Manage" : "See plans") { _ = ws.run("PRO") }
                .font(.mono(11, .bold)).foregroundStyle(Theme.accent).buttonStyle(.plain)
        }
    }
}
