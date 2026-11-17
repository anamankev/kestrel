import SwiftUI
import KestrelCore

/// Sign in / create account. Live prices stream behind the form so the first screen is already
/// the product, not a placeholder.
struct AuthView: View {
    @Environment(AuthService.self) private var auth
    @Environment(MarketStore.self) private var market
    @Environment(Theme.self) private var theme

    enum Mode: String, CaseIterable { case signIn = "Sign in", create = "Create account" }
    enum Field: Hashable { case name, email, password, confirm }

    @State private var mode: Mode = .signIn
    @State private var name = ""
    @State private var email = ""
    @State private var password = ""
    @State private var confirm = ""
    @State private var reveal = false
    @State private var error: String?
    @FocusState private var focus: Field?

    private static let tiles = ["BTC", "ETH", "SOL", "SPX", "CCMP", "EURUSD"]

    var body: some View {
        GeometryReader { g in
            let wide = g.size.width > 900
            ZStack {
                Theme.canvas.ignoresSafeArea()
                if wide {
                    HStack(spacing: 0) {
                        brand.frame(maxWidth: .infinity, maxHeight: .infinity).padding(48)
                        Rectangle().fill(Theme.rule).frame(width: 1)
                        form.frame(width: 460).frame(maxHeight: .infinity).padding(.horizontal, 40)
                    }
                } else {
                    ScrollView {
                        VStack(spacing: 32) {
                            header
                            form.frame(maxWidth: 460)
                        }
                        .padding(24)
                        .frame(maxWidth: .infinity)
                    }
                }
            }
        }
        .onAppear { if auth.directory.accounts.isEmpty { mode = .create } }
        #if DEBUG
        .task { if SnapshotTour.isEnabled { await SnapshotTour.signIn(auth) } }
        #endif   // a fresh device starts on sign-up
        .onChange(of: mode) { error = nil; confirm = ""; password = "" }
        .onChange(of: [name, email, password, confirm]) { error = nil }   // stale errors go once you edit
    }

    // MARK: Brand side

    private var header: some View {
        HStack(spacing: 12) {
            KestrelMark().frame(width: 30, height: 26)
            Text("KESTREL").font(.mono(22, .heavy)).tracking(6).foregroundStyle(Theme.text)
        }
    }

    private var brand: some View {
        VStack(alignment: .leading, spacing: 28) {
            header
            VStack(alignment: .leading, spacing: 10) {
                Text("Command-line market terminal")
                    .font(.ui(34, .semibold)).foregroundStyle(Theme.text)
                Text("Live crypto depth and tape, delayed equities, FX, rates, options with greeks, filings, macro, and a paper book to trade it all.")
                    .font(.ui(15)).foregroundStyle(Theme.dim).frame(maxWidth: 560, alignment: .leading)
            }
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 170), spacing: 1)], spacing: 1) {
                ForEach(Self.tiles, id: \.self) { t in tile(t) }
            }
            .background(Theme.rule)
            .frame(maxWidth: 560)
            HStack(spacing: 16) {
                ForEach(["BTC GP", "AAPL DES", "BTC OMON", "CORR"], id: \.self) { c in
                    Text(c + " <GO>").font(.mono(11, .semibold)).foregroundStyle(Theme.accent)
                }
            }
            Spacer()
            Text("Paper trading only. No real money moves, and no brokerage is connected.")
                .font(.ui(11)).foregroundStyle(Theme.faint)
        }
    }

    private func tile(_ ticker: String) -> some View {
        let i = Universe.resolve(ticker)
        let q = i.flatMap { market.quotes[$0.symbol] }
        return VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(ticker).font(.ui(12, .bold)).foregroundStyle(Theme.label)
                Spacer()
                if i?.isStreaming == true { Circle().fill(Theme.go).frame(width: 5, height: 5) }
            }
            Text(q.map { Fmt.price($0.last, i!.assetClass) } ?? "—")
                .font(.ui(20, .semibold)).monospacedDigit().foregroundStyle(Theme.text)
                .contentTransition(.numericText())
            Text(Fmt.pct(q?.changePercent)).font(.ui(12, .medium)).monospacedDigit().foregroundStyle(theme.tint(q?.changePercent))
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.panel)
    }

    // MARK: Form

    private var form: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 22) {
                ForEach(Mode.allCases, id: \.self) { m in
                    Button { mode = m } label: {
                        VStack(spacing: 6) {
                            Text(m.rawValue).font(.ui(13, .bold)).foregroundStyle(mode == m ? Theme.text : Theme.dim)
                            Rectangle().fill(mode == m ? Theme.accent : .clear).frame(height: 2)
                        }
                        .fixedSize()
                    }
                    .buttonStyle(.plain)
                }
                Spacer()
            }

            Text(mode == .signIn ? "Sign in" : "Create an account")
                .font(.ui(24, .semibold)).foregroundStyle(Theme.text)

            if mode == .create {
                input("Name", text: $name, field: .name, prompt: "Ada Lovelace")
                    #if os(iOS)
                    .textContentType(.name)
                    #endif
            }
            input("Email", text: $email, field: .email, prompt: "you@firm.com")
                #if os(iOS)
                .textContentType(.username).keyboardType(.emailAddress).textInputAutocapitalization(.never)
                #endif
            secure("Password", text: $password, field: .password)
            if mode == .create {
                secure("Confirm password", text: $confirm, field: .confirm)
                strength
            }

            if let error {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .font(.ui(12, .medium)).foregroundStyle(Theme.cancel)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Button(action: submit) {
                HStack(spacing: 8) {
                    if auth.busy { ProgressView().controlSize(.small).tint(Theme.canvas) }
                    Text(auth.busy ? (mode == .signIn ? "Signing in…" : "Creating account…") : (mode == .signIn ? "Sign in" : "Create account"))
                        .font(.ui(15, .semibold))
                }
                .foregroundStyle(Theme.canvas)
                .frame(maxWidth: .infinity).frame(height: 44)
                .background(Theme.accent, in: .rect(cornerRadius: 3))
                .opacity(canSubmit || auth.busy ? 1 : 0.45)
            }
            .buttonStyle(.plain)
            .disabled(!canSubmit)
            .keyboardShortcut(.defaultAction)

            Text(mode == .signIn
                 ? "Accounts are stored on this device. Forgot your password? Accounts can't be recovered until cloud sync launches; create a new one."
                 : "Your account lives on this device: a salted PBKDF2 hash, never the password. Each account has its own paper book, watchlists and alerts.")
                .font(.ui(11)).foregroundStyle(Theme.faint)
                .fixedSize(horizontal: false, vertical: true)
        }
        .onSubmit(advance)
    }

    private var canSubmit: Bool {
        guard !auth.busy, !email.isEmpty, !password.isEmpty else { return false }
        return mode == .signIn || (!name.isEmpty && !confirm.isEmpty)
    }

    /// Live guidance against the same rules the account store enforces.
    private var strength: some View {
        let problem = password.isEmpty ? nil : Credentials.passwordProblem(password, email: email)
        let ok = !password.isEmpty && problem == nil
        return HStack(spacing: 6) {
            Image(systemName: ok ? "checkmark.circle.fill" : "circle").font(.system(size: 11))
            Text(password.isEmpty ? "At least \(Credentials.minPasswordLength) characters. A phrase works well." : (problem ?? "Strong enough"))
        }
        .font(.ui(11)).foregroundStyle(ok ? theme.up : Theme.dim)
    }

    private func input(_ label: String, text: Binding<String>, field: Field, prompt: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(label).font(.ui(11, .bold)).foregroundStyle(Theme.label)
            TextField("", text: text)
                .placeholder(prompt, when: text.wrappedValue.isEmpty)
                .font(.ui(16)).foregroundStyle(Theme.text).textFieldStyle(.plain)
                .autocorrectionDisabled()
                .focused($focus, equals: field)
                .submitLabel(.next)
                .padding(.horizontal, 10).frame(height: 40)
                .background(Theme.panel)
                .overlay(Rectangle().stroke(focus == field ? Theme.accent : Theme.rule))
        }
    }

    private func secure(_ label: String, text: Binding<String>, field: Field) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text(label).font(.ui(11, .bold)).foregroundStyle(Theme.label)
                Spacer()
                if field == .password {
                    Button(reveal ? "Hide" : "Show") { reveal.toggle() }
                        .font(.ui(11, .bold)).foregroundStyle(Theme.dim).buttonStyle(.plain)
                }
            }
            Group {
                if reveal { TextField("", text: text) } else { SecureField("", text: text) }
            }
            .font(.ui(16)).foregroundStyle(Theme.text).textFieldStyle(.plain)
            .autocorrectionDisabled()
            #if os(iOS)
            .textInputAutocapitalization(.never)
            .textContentType(mode == .signIn ? .password : .newPassword)
            #endif
            .focused($focus, equals: field)
            .submitLabel(field == .password && mode == .signIn || field == .confirm ? .go : .next)
            .padding(.horizontal, 10).frame(height: 40)
            .background(Theme.panel)
            .overlay(Rectangle().stroke(focus == field ? Theme.accent : Theme.rule))
        }
    }

    private func advance() {
        switch (mode, focus) {
        case (.create, .name): focus = .email
        case (_, .email): focus = .password
        case (.create, .password): focus = .confirm
        default: submit()
        }
    }

    private func submit() {
        guard canSubmit else { return }
        error = nil
        Task {
            do throws(AuthError) {
                if mode == .signIn {
                    try await auth.signIn(email: email, password: password)
                } else {
                    try await auth.register(name: name, email: email, password: password, confirm: confirm)
                }
                password = ""; confirm = ""
            } catch {
                self.error = error.errorDescription
                if case .invalidCredentials = error { password = "" }
            }
        }
    }
}
