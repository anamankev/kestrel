import SwiftUI
import KestrelCore

/// ECST: World Bank development indicators. PROFILE shows one country's headline macro over
/// 15 years; RANK compares one indicator across every country. `ECST JAPAN` opens a profile.
struct WorldEconomyView: View {
    let panelID: Int
    var initial: String?
    @Environment(MacroService.self) private var macro
    @Environment(Theme.self) private var theme

    enum Mode: String, CaseIterable { case profile = "COUNTRY PROFILE", rank = "RANK COUNTRIES" }

    @AppStorage("ecst.mode") private var mode: Mode = .profile
    @AppStorage("ecst.country") private var country = "USA"
    @AppStorage("ecst.indicator") private var indicator = "NY.GDP.MKTP.KD.ZG"
    @State private var region = "ALL"
    @State private var ascending = false

    private var current: WorldBank.Country? { macro.countries.first { $0.id == country } }
    private var info: WorldBank.Indicator { WorldBank.indicators.first { $0.id == indicator } ?? WorldBank.indicators[0] }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                Picker("Mode", selection: $mode) { ForEach(Mode.allCases, id: \.self) { Text($0.rawValue) } }
                    .pickerStyle(.segmented).labelsHidden().frame(maxWidth: 320)
                if mode == .profile {
                    Picker("Country", selection: $country) { ForEach(macro.countries) { Text($0.name).tag($0.id) } }
                        .labelsHidden().frame(maxWidth: 240)
                } else {
                    Picker("Indicator", selection: $indicator) { ForEach(WorldBank.indicators) { Text($0.name).tag($0.id) } }
                        .labelsHidden().frame(maxWidth: 300)
                    Picker("Region", selection: $region) {
                        Text("All regions").tag("ALL")
                        ForEach(Array(Set(macro.countries.map(\.region))).filter { !$0.isEmpty }.sorted(), id: \.self) { Text($0).tag($0) }
                    }
                    .labelsHidden().frame(maxWidth: 220)
                }
                Spacer()
                ShareLink(item: CSVFile(name: csvName, text: csv), preview: SharePreview("World Bank data")) {
                    Label("EXPORT CSV", systemImage: "square.and.arrow.up").font(.mono(10, .bold))
                }
                .buttonStyle(.plain).foregroundStyle(Theme.accent)
            }
            .padding(8)
            if let e = macro.worldError, macro.countries.isEmpty {
                EmptyNote(title: "World Bank unavailable", detail: e, icon: "globe.europe.africa")
            } else if mode == .profile {
                profile
            } else {
                ranking
            }
            Text("Source: World Bank, World Development Indicators (CC BY 4.0). Annual data; the latest year varies by country and series.")
                .font(.ui(10)).foregroundStyle(Theme.faint).padding(8)
        }
        .task { await macro.loadCountries(); applyInitial() }
        .onChange(of: initial) { applyInitial() }
        .task { await macro.loadWorld(first: indicator) }
    }

    private func applyInitial() {
        guard let q = initial, let c = WorldBank.match(q, in: macro.countries) else { return }
        country = c.id
        mode = .profile
    }

    // MARK: Profile

    private var years: [Int] {
        let all = Set(macro.profile(country).values.flatMap { $0.map(\.year) })
        return Array(all.sorted().suffix(7))
    }

    private var profile: some View {
        let data = macro.profile(country)
        let loaded = WorldBank.indicators.filter { macro.panels[$0.id] != nil }.count
        return VStack(alignment: .leading, spacing: 0) {
            SectionBar(title: "\((current?.name ?? country).uppercased()) · \(current?.region.uppercased() ?? "") · \(current?.income.uppercased() ?? "")",
                       trailing: loaded < WorldBank.indicators.count ? "LOADED \(loaded)/\(WorldBank.indicators.count) INDICATORS" : "\(loaded) INDICATORS")
            if loaded > 0 {
                HStack(spacing: 6) {
                    Text("INDICATOR").frame(maxWidth: .infinity, alignment: .leading)
                    ForEach(years, id: \.self) { Text(String($0)).frame(width: 74, alignment: .trailing) }
                    Text("15Y").frame(width: 90, alignment: .center)
                }
                .font(.mono(9, .bold)).foregroundStyle(Theme.label).padding(.horizontal, 8).padding(.vertical, 5)
                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(Array(WorldBank.indicators.enumerated()), id: \.element.id) { n, i in
                            let points = data[i.id] ?? []
                            Button { indicator = i.id; mode = .rank } label: {
                                HStack(spacing: 6) {
                                    Text(i.name).font(.ui(11)).foregroundStyle(Theme.text).lineLimit(1).frame(maxWidth: .infinity, alignment: .leading)
                                    if macro.panels[i.id] == nil {
                                        Text(macro.failedIndicators.contains(i.id) ? "WORLD BANK DIDN'T RESPOND · REOPEN TO RETRY" : "LOADING…")
                                            .font(.mono(9)).foregroundStyle(Theme.faint).frame(width: CGFloat(years.count) * 80 + 90, alignment: .trailing)
                                    } else {
                                    ForEach(years, id: \.self) { y in
                                        let v = points.first { $0.year == y }?.value
                                        Text(format(v, i.unit)).font(.mono(11)).monospacedDigit()
                                            .foregroundStyle(v == nil ? Theme.faint : (["NY.GDP.MKTP.KD.ZG", "BN.CAB.XOKA.GD.ZS"].contains(i.id) ? theme.tint(v) : Theme.text))
                                            .frame(width: 74, alignment: .trailing)
                                    }
                                    Sparkline(values: points.suffix(15).map(\.value)).frame(width: 90, height: 18)
                                    }
                                }
                                .padding(.horizontal, 8).padding(.vertical, 6).contentShape(.rect)
                            }
                            .buttonStyle(.plain)
                            .rowBackground(n)
                        }
                        Text("Tap an indicator to rank every country on it.").font(.ui(10)).foregroundStyle(Theme.faint)
                            .frame(maxWidth: .infinity, alignment: .leading).padding(8)
                    }
                }
            } else if let e = macro.worldError {
                EmptyNote(title: "World Bank unavailable", detail: e, icon: "exclamationmark.triangle")
            } else {
                ProgressView().tint(Theme.accent).frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    // MARK: Ranking

    private var ranked: [(WorldBank.Country, WorldBank.Point)] {
        let values = macro.ranking(indicator) ?? [:]
        return macro.countries
            .filter { region == "ALL" || $0.region == region }
            .compactMap { c in values[c.id].map { (c, $0) } }
            .sorted { ascending ? $0.1.value < $1.1.value : $0.1.value > $1.1.value }
    }

    private var ranking: some View {
        let rows = ranked
        return VStack(alignment: .leading, spacing: 0) {
            SectionBar(title: "\(info.short) · LATEST AVAILABLE YEAR", trailing: macro.ranking(indicator) == nil ? (macro.failedIndicators.contains(indicator) ? "WORLD BANK DIDN'T RESPOND" : "LOADING…") : "\(rows.count) COUNTRIES")
            HStack(spacing: 6) {
                Text("#").frame(width: 34, alignment: .trailing)
                Text("COUNTRY").frame(maxWidth: .infinity, alignment: .leading)
                Text("REGION").frame(width: 200, alignment: .leading)
                Button { ascending.toggle() } label: {
                    Text("VALUE " + (ascending ? "▲" : "▼")).foregroundStyle(Theme.accent)
                }
                .buttonStyle(.plain).frame(width: 110, alignment: .trailing)
                Text("YEAR").frame(width: 50, alignment: .trailing)
            }
            .font(.mono(9, .bold)).foregroundStyle(Theme.label).padding(.horizontal, 8).padding(.vertical, 5)
            if macro.ranking(indicator) == nil, macro.failedIndicators.contains(indicator) {
                EmptyNote(title: "The World Bank didn't respond for this indicator", detail: "Its servers are slow at times. Reopen ECST to retry.", icon: "exclamationmark.triangle")
            } else if macro.ranking(indicator) == nil {
                ProgressView().tint(Theme.accent).frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(Array(rows.enumerated()), id: \.element.0.id) { n, r in
                            Button { country = r.0.id; mode = .profile } label: {
                                HStack(spacing: 6) {
                                    Text("\(n + 1)").foregroundStyle(Theme.faint).frame(width: 34, alignment: .trailing)
                                    Text(r.0.name).font(.ui(11)).foregroundStyle(r.0.id == country ? Theme.accent : Theme.text).lineLimit(1)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                    Text(r.0.region).font(.ui(10)).foregroundStyle(Theme.dim).lineLimit(1).frame(width: 200, alignment: .leading)
                                    Text(format(r.1.value, info.unit)).foregroundStyle(Theme.text).frame(width: 110, alignment: .trailing)
                                    Text(String(r.1.year)).foregroundStyle(Theme.dim).frame(width: 50, alignment: .trailing)
                                }
                                .font(.mono(11)).monospacedDigit().padding(.horizontal, 8).padding(.vertical, 5).contentShape(.rect)
                            }
                            .buttonStyle(.plain)
                            .rowBackground(n)
                        }
                    }
                }
            }
        }
    }

    // MARK: Formatting & export

    private func format(_ v: Double?, _ unit: WorldBank.Unit) -> String {
        guard let v, v.isFinite else { return "—" }
        switch unit {
        case .percent: return String(format: "%.1f%%", v)
        case .usd: return "$" + Fmt.compact(v)
        case .count: return Fmt.compact(v)
        case .ratio: return String(format: "%.2f", v)
        }
    }

    private var csvName: String { mode == .profile ? "\(country)-profile.csv" : "\(info.id)-ranking.csv" }

    private var csv: String {
        if mode == .profile {
            let data = macro.profile(country)
            let ys = Array(Set(data.values.flatMap { $0.map(\.year) })).sorted()
            return CSV.make(header: ["Indicator", "Code"] + ys.map(String.init), rows: WorldBank.indicators.map { i in
                [i.name, i.id] + ys.map { y in CSV.number(data[i.id]?.first { $0.year == y }?.value, digits: 4) }
            })
        }
        return CSV.make(header: ["Rank", "Country", "ISO3", "Region", info.name, "Year"], rows: ranked.enumerated().map { n, r in
            [String(n + 1), r.0.name, r.0.id, r.0.region, CSV.number(r.1.value, digits: 4), String(r.1.year)]
        })
    }
}
