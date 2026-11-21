import SwiftUI
import FoundationModels
import KestrelCore

/// AI: a written brief from the data (works everywhere) and follow-up questions answered by Apple's
/// on-device model when Apple Intelligence is available. Nothing leaves the device. Mirrors web AI.tsx.
struct AIAnalystView: View {
    let instrument: Instrument
    let panelID: Int
    @Environment(FundamentalsService.self) private var sec
    @Environment(MarketStore.self) private var market
    @Environment(NewsService.self) private var news
    @Environment(Workspace.self) private var ws

    var body: some View {
        Group {
            if instrument.assetClass != .equity {
                EmptyNote(title: "The AI analyst covers companies", detail: "Load a US-listed stock, e.g. AAPL AI.", icon: "building.2")
            } else {
                switch sec.state(for: instrument) {
                case .needsContact:
                    VStack(spacing: 12) {
                        EmptyNote(title: "The analyst needs a contact email",
                                  detail: "SEC EDGAR is free, but asks every app to identify itself with a contact email. Add yours once in PREF; it is sent only to sec.gov.",
                                  icon: "building.columns")
                        Hotspot(number: 1, title: "PREF Open settings") { ws.load(Command(function: .pref), in: panelID) }
                    }
                case .loading:
                    ProgressView("Reading filings and headlines…").tint(Theme.accent).font(.mono(10)).foregroundStyle(Theme.dim)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                case .notFound:
                    EmptyNote(title: "No SEC filings for \(instrument.ticker)", detail: "The analyst works from 10-K filings, so it covers US-listed companies.", icon: "doc.text.magnifyingglass")
                case .failed(let why):
                    EmptyNote(title: "SEC request failed", detail: why, icon: "exclamationmark.triangle")
                case .ready(let f):
                    report(f)
                }
            }
        }
        .task(id: "\(instrument.symbol)|\(sec.hasValidContact)") {
            market.touch(instrument)
            if let t = Universe.resolve("US10Y") { market.touch(t) }
            async let a: Void = sec.load(instrument)
            async let b: Void = news.loadCompany(instrument)
            _ = await (a, b)
        }
    }

    private func report(_ f: CompanyFundamentals) -> some View {
        let q = market.quotes[instrument.symbol]
        let ten = Universe.resolve("US10Y").flatMap { market.quotes[$0.symbol]?.last }.map { $0 / 100 }
        let sections = AnalystBrief.make(.init(name: f.name, ticker: instrument.ticker, price: q?.last,
                                               changePercent: q.flatMap { q in q.previousClose.flatMap { $0 != 0 ? (q.last / $0 - 1) * 100 : nil } },
                                               years: f.years, shares: f.sharesOutstanding, tenYear: ten,
                                               headlines: (news.company[instrument.symbol] ?? []).prefix(5).map(\.title)))
        return ScrollView {
            VStack(alignment: .leading, spacing: 6) {
                ForEach(sections) { s in
                    SectionBar(title: s.title, trailing: s.title == "SNAPSHOT" ? "\(instrument.ticker) · WRITTEN FROM SEC FILINGS, PRICE AND HEADLINES" : nil)
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(Array(s.lines.enumerated()), id: \.offset) { _, l in
                            HStack(alignment: .firstTextBaseline, spacing: 6) {
                                Text("•").foregroundStyle(Theme.accent)
                                Text(l).foregroundStyle(Theme.text).fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                    .font(.ui(13)).padding(.horizontal, 10)
                }
                AskAnalyst(facts: AnalystBrief.facts(sections)).id(instrument.symbol)
                Text("Every sentence in the brief is computed from the numbers shown elsewhere in Kestrel (FA, DCF, CN). It is a study aid, not advice.")
                    .font(.ui(10)).foregroundStyle(Theme.faint).padding(.horizontal, 8)
            }
            .padding(.vertical, 8)
        }
    }
}

private struct AskAnalyst: View {
    let facts: String
    @State private var session: LanguageModelSession?
    @State private var chat: [(q: String, a: String, error: Bool)] = []
    @State private var text = ""
    @State private var busy = false

    private static let suggestions = ["What's the bull case and the bear case?", "Explain the valuation in simple terms.", "What should I watch in the next report?"]

    private var unavailableReason: String? {
        switch SystemLanguageModel.default.availability {
        case .available: return nil
        case .unavailable(.deviceNotEligible): return "This device can't run Apple Intelligence."
        case .unavailable(.appleIntelligenceNotEnabled): return "Turn on Apple Intelligence in Settings to ask questions."
        case .unavailable(.modelNotReady): return "Apple Intelligence is still downloading its model. Try again soon."
        default: return "Apple Intelligence isn't available right now."
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionBar(title: "ASK THE ANALYST", trailing: unavailableReason == nil ? "ON-DEVICE AI · NOTHING LEAVES THIS DEVICE" : nil)
            if let why = unavailableReason {
                Text("Questions use Apple's on-device model, so nothing you ask leaves the device. \(why) The brief above works everywhere.")
                    .font(.ui(12)).foregroundStyle(Theme.dim).padding(.horizontal, 10)
            } else {
                ForEach(Array(chat.enumerated()), id: \.offset) { _, m in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(m.q).font(.ui(12)).fontWeight(.semibold).foregroundStyle(Theme.text)
                        Text(m.a.isEmpty ? "…" : m.a).font(.ui(13)).foregroundStyle(m.error ? Theme.warn : Theme.text).fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.horizontal, 10)
                }
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(Self.suggestions, id: \.self) { s in
                            Button(s) { ask(s) }.font(.ui(12)).foregroundStyle(Theme.accent)
                                .padding(.horizontal, 10).frame(minHeight: barHeight(28))
                                .overlay(Capsule().stroke(Theme.accentDim)).buttonStyle(.terminal).disabled(busy)
                        }
                    }
                    .padding(.horizontal, 10)
                }
                HStack(spacing: 6) {
                    TextField("Ask about this company…", text: $text).accessibilityLabel("Ask the analyst").font(.ui(13)).textFieldStyle(.plain)
                        .padding(.horizontal, 8).frame(minHeight: barHeight(30)).background(Theme.panel).overlay(Rectangle().stroke(Theme.rule))
                        .onSubmit { ask(text) }.disabled(busy)
                    Button("ASK") { ask(text) }.font(.mono(11, .bold)).foregroundStyle(Theme.accent).buttonStyle(.terminal)
                        .disabled(busy || text.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                .padding(.horizontal, 10)
            }
        }
    }

    private func ask(_ raw: String) {
        let q = String(raw.trimmingCharacters(in: .whitespacesAndNewlines).prefix(300))
        guard !q.isEmpty, !busy else { return }
        text = ""; busy = true
        chat.append((q, "", false))
        let k = chat.count - 1
        Task {
            defer { busy = false }
            do {
                let s = session ?? LanguageModelSession(instructions: AnalystBrief.instructions + "\n\nFACTS\n" + facts)
                session = s
                for try await partial in s.streamResponse(to: q) { chat[k].a = partial.content }
            } catch {
                chat[k] = (q, "The on-device model couldn't answer. Check that Apple Intelligence is turned on in Settings and has finished downloading, then try again. (\(error.localizedDescription))", true)
                session = nil   // a full or failed session starts fresh next time
            }
        }
    }
}
