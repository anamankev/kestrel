import SwiftUI
import KestrelCore

/// DATA: whether each source is answering, how fast, and what depends on it. Mirrors web DataSources.tsx.
struct DataSourcesView: View {
    let panelID: Int
    @Environment(MarketStore.self) private var market
    @Environment(FundamentalsService.self) private var sec
    @Environment(Workspace.self) private var ws
    @Environment(Theme.self) private var theme

    struct Check { var status: DataSources.Status; var ms: Int; var at: Date; var note: String? }
    @State private var results: [String: Check] = [:]
    @State private var checking = false

    private let sources = DataSources.all()

    var body: some View {
        let down = sources.filter { results[$0.id]?.status == .down }.count
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(checking ? "CHECKING EVERY SOURCE…" : down > 0 ? "\(down) SOURCE\(down > 1 ? "S" : "") DOWN" : "ALL CHECKED SOURCES ANSWERING")
                        .font(.mono(10, .bold)).foregroundStyle(down > 0 ? theme.down : Theme.label)
                    Spacer()
                    Button("CHECK ALL") { Task { await checkAll() } }.font(.mono(10, .bold)).foregroundStyle(Theme.accent)
                        .buttonStyle(.terminal).disabled(checking)
                }
                .padding(.horizontal, 8)
                SectionBar(title: "DATA SOURCES", trailing: "FREE PUBLIC SOURCES · PRICES DELAYED EXCEPT LIVE CRYPTO")
                VStack(spacing: 0) {
                    HStack(spacing: 0) {
                        HeaderCell(text: "SOURCE", width: 240.pt, align: .leading)
                        HeaderCell(text: "POWERS", align: .leading)
                        HeaderCell(text: "STATUS", width: 160.pt); HeaderCell(text: "RESPONSE", width: 90.pt)
                    }
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    ForEach(Array(sources.enumerated()), id: \.element.id) { n, s in
                        let r = results[s.id]
                        HStack(spacing: 0) {
                            Text(s.name).font(.mono(11, .bold)).foregroundStyle(Theme.text).frame(width: 240.pt, alignment: .leading)
                            Text(s.powers).font(.ui(11)).foregroundStyle(Theme.dim).frame(maxWidth: .infinity, alignment: .leading).lineLimit(2)
                            Text(r.map { $0.status.rawValue + ($0.note.map { " · \($0)" } ?? "") } ?? "…")
                                .font(.mono(11, .bold)).lineLimit(2).multilineTextAlignment(.trailing)
                                .foregroundStyle(r?.status == .ok ? theme.up : r?.status == .down ? theme.down : r == nil ? Theme.dim : Theme.warn)
                                .frame(width: 160.pt, alignment: .trailing)
                            Text(r.flatMap { s.probe == .feed ? nil : "\($0.ms) ms" } ?? "—").font(.mono(11)).monospacedDigit()
                                .foregroundStyle(Theme.text).frame(width: 90.pt, alignment: .trailing)
                        }
                        .padding(.horizontal, 8).frame(minHeight: 30.pt).rowBackground(n)
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel("\(s.name): \(r?.status.rawValue ?? "checking")\(r?.note.map { ", \($0)" } ?? ""). Powers \(s.powers).")
                    }
                }
                if sources.contains(where: { results[$0.id]?.note?.contains("PREF") == true }) {
                    Hotspot(number: 1, title: "PREF Add the SEC contact email") { ws.load(Command(function: .pref), in: panelID) }.padding(.horizontal, 8)
                }
                Text("Over 3 seconds counts as slow. If a source is down, the screens it powers show a short note and retry on their own. The live feed's status comes from the connection itself.")
                    .font(.ui(10)).foregroundStyle(Theme.faint).padding(.horizontal, 8)
            }
            .padding(.vertical, 8)
        }
        .task { await checkAll() }
    }

    private func checkAll() async {
        guard !checking else { return }
        checking = true
        defer { checking = false }
        let contact = sec.hasValidContact ? sec.contact : nil
        await withTaskGroup(of: (String, Check).self) { g in
            for s in sources {
                switch s.probe {
                case .feed:
                    let live = market.link == .live
                    results[s.id] = Check(status: live ? .ok : .down, ms: 0, at: .now, note: live ? "\(Int(market.messagesPerSecond)) msg/s" : market.link.rawValue.lowercased())
                case .needsSECContact(let url) where contact == nil:
                    _ = url
                    results[s.id] = Check(status: .slow, ms: 0, at: .now, note: "add contact in PREF")
                case .get(let url), .needsSECContact(let url):
                    let ua = contact.map { SECFacts.userAgent(contact: $0) }
                    g.addTask { (s.id, await Self.probe(url, userAgent: s.id == "sec" ? ua : nil)) }
                }
            }
            for await (id, c) in g { results[id] = c }
        }
    }

    private static func probe(_ url: URL, userAgent: String?) async -> Check {
        var req = URLRequest(url: url, timeoutInterval: 10)
        req.setValue(userAgent ?? "Mozilla/5.0 (Kestrel Terminal)", forHTTPHeaderField: "User-Agent")
        let start = Date()
        do {
            let (_, r) = try await URLSession.shared.data(for: req)
            let code = (r as? HTTPURLResponse)?.statusCode ?? 0
            let secs = Date().timeIntervalSince(start)
            return Check(status: DataSources.classify(ok: (200..<300).contains(code), seconds: secs), ms: Int(secs * 1000), at: .now,
                         note: (200..<300).contains(code) ? nil : "HTTP \(code)")
        } catch {
            return Check(status: .down, ms: Int(Date().timeIntervalSince(start) * 1000), at: .now, note: (error as? URLError)?.code == .timedOut ? "timed out" : "unreachable")
        }
    }
}
