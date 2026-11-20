import SwiftUI
import KestrelCore

/// LEARN: guided drills. Each opens a real function in the next panel and asks what the screen teaches;
/// a module's badge is earned when every drill is answered correctly. Progress is saved with the account.
struct LearnView: View {
    let panelID: Int
    @Environment(UserData.self) private var user
    @Environment(Workspace.self) private var ws
    @Environment(Theme.self) private var theme
    @State private var open: String?
    @State private var drill = 0
    @State private var picked: Int?

    var body: some View {
        if let m = Learn.modules.first(where: { $0.id == open }) { module(m) } else { list }
    }

    // MARK: Modules

    private var list: some View {
        let total = Learn.modules.reduce(0) { $0 + $1.drills.count }, got = Learn.modules.reduce(0) { $0 + Learn.done($1, user.learned) }
        let badges = Learn.modules.filter { Learn.earned($0, user.learned) }.count
        return ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                SectionBar(title: "LEARNING MODE", trailing: "\(got) OF \(total) DRILLS · \(badges) OF \(Learn.modules.count) BADGES")
                Text("Each drill opens a real Kestrel function in the next panel and asks one question about what it shows. Answer every drill in a module to earn its badge.")
                    .font(.ui(12)).foregroundStyle(Theme.dim).padding(.horizontal, 10)
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 230.pt), spacing: 8)], spacing: 8) {
                    ForEach(Learn.modules) { m in card(m) }
                }
                .padding(.horizontal, 8)
            }
            .padding(.vertical, 8)
        }
    }

    private func card(_ m: Learn.Module) -> some View {
        let n = Learn.done(m, user.learned), won = Learn.earned(m, user.learned)
        return Button {
            open = m.id; drill = Learn.next(m, user.learned); picked = nil
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                Text(m.title).font(.mono(13, .bold)).foregroundStyle(Theme.accent)
                Text(m.summary).font(.ui(12)).foregroundStyle(Theme.dim).multilineTextAlignment(.leading).fixedSize(horizontal: false, vertical: true)
                GeometryReader { g in
                    ZStack(alignment: .leading) {
                        Rectangle().fill(Theme.rule)
                        Rectangle().fill(Theme.accent).frame(width: g.size.width * CGFloat(n) / CGFloat(m.drills.count))
                    }
                }
                .frame(height: 4)
                HStack(spacing: 6) {
                    Text("\(n) / \(m.drills.count) DRILLS").foregroundStyle(Theme.label)
                    if won { Text("★ \(m.badge)").foregroundStyle(Theme.warn) } else { Text("· BADGE: \(m.badge)").foregroundStyle(Theme.faint) }
                }
                .font(.mono(10, .bold))
            }
            .padding(12).frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.panel).overlay(RoundedRectangle(cornerRadius: 6).stroke(won ? Theme.accentDim : Theme.rule))
        }
        .buttonStyle(.terminal)
        .accessibilityLabel("\(m.title): \(n) of \(m.drills.count) drills done\(won ? ", \(m.badge) badge earned" : "")")
    }

    // MARK: Drills

    private func module(_ m: Learn.Module) -> some View {
        let d = m.drills[min(drill, m.drills.count - 1)], right = picked == d.answer, won = Learn.earned(m, user.learned)
        return ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Button("‹ ALL MODULES") { open = nil }.font(.mono(10, .bold)).foregroundStyle(Theme.dim).buttonStyle(.terminal)
                    Spacer()
                    Text("\(m.title) · DRILL \(drill + 1) OF \(m.drills.count)").font(.mono(10, .bold)).foregroundStyle(Theme.label)
                    if won { Text("★ \(m.badge)").font(.mono(10, .bold)).foregroundStyle(Theme.warn) }
                }
                .padding(.horizontal, 10)
                HStack(spacing: 6) {
                    ForEach(Array(m.drills.enumerated()), id: \.element.id) { i, x in
                        let ok = user.learned.contains(x.id)
                        Button { go(i) } label: {
                            Text("\(i + 1)").font(.mono(11, .bold)).frame(width: 28, height: 28)
                                .foregroundStyle(i == drill ? Theme.accent : ok ? Theme.text : Theme.dim)
                                .background(Circle().fill(ok ? Theme.accentDim : Theme.canvas))
                                .overlay(Circle().stroke(i == drill ? Theme.accent : Theme.rule))
                        }
                        .buttonStyle(.terminal)
                        .accessibilityLabel("Drill \(i + 1)\(ok ? ", done" : "")")
                    }
                }
                .padding(.horizontal, 10).padding(.bottom, 6)
                step(1) {
                    VStack(alignment: .leading, spacing: 6) {
                        (Text("Open ") + Text(d.command).font(.mono(12, .bold)).foregroundColor(Theme.accent) + Text(" in the next panel."))
                        Button { openDrill(d) } label: {
                            Text("OPEN \(d.command) ›").font(.mono(11, .bold)).foregroundStyle(Theme.label).padding(.horizontal, 10)
                                .frame(minHeight: barHeight(26)).overlay(RoundedRectangle(cornerRadius: 3).stroke(Theme.rule))
                        }
                        .buttonStyle(.terminal)
                    }
                }
                step(2) { Text("Look at: \(d.look)") }
                step(3) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(d.question).fontWeight(.semibold)
                        ForEach(Learn.order(d), id: \.self) { c in
                            let color: Color = picked == nil ? Theme.rule : (c == d.answer && right) ? theme.up : c == picked ? theme.down : Theme.rule
                            Button { answer(d, c) } label: {
                                Text(d.choices[c]).font(.ui(13)).multilineTextAlignment(.leading)
                                    .foregroundStyle(color == Theme.rule ? Theme.text : color)
                                    .padding(.horizontal, 10).padding(.vertical, 8).frame(maxWidth: .infinity, minHeight: 36, alignment: .leading)
                                    .background(Theme.canvas).overlay(RoundedRectangle(cornerRadius: 4).stroke(color))
                            }
                            .buttonStyle(.terminal)
                            .accessibilityAddTraits(picked == c ? .isSelected : [])
                        }
                        if picked != nil {
                            (Text(right ? "Correct. " : "Not quite: look again and try another answer.").foregroundColor(right ? theme.up : theme.down)
                             + Text(right ? d.why : "").foregroundColor(Theme.dim))
                                .font(.ui(12)).fixedSize(horizontal: false, vertical: true)
                                .accessibilityAddTraits(.updatesFrequently)
                        }
                    }
                }
                HStack {
                    Button("‹ PREVIOUS") { go(drill - 1) }.disabled(drill == 0)
                    Spacer()
                    if drill < m.drills.count - 1 { Button("NEXT DRILL ›") { go(drill + 1) } } else { Button("FINISH ›") { open = nil } }
                }
                .font(.mono(10, .bold)).foregroundStyle(Theme.dim).buttonStyle(.terminal).padding(.horizontal, 10).padding(.top, 6)
                if won {
                    Button("RESET THIS MODULE") { user.resetLearning(m.drills.map(\.id)); go(0) }
                        .font(.mono(10, .bold)).foregroundStyle(Theme.cancel).buttonStyle(.terminal).padding(.horizontal, 10)
                }
            }
            .frame(maxWidth: 760, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 8)
        }
    }

    private func step<C: View>(_ n: Int, @ViewBuilder _ content: () -> C) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text("\(n)").font(.mono(11, .bold)).foregroundStyle(Theme.accent).frame(width: 22, height: 22).background(Circle().fill(Theme.rule))
            content().font(.ui(13)).foregroundStyle(Theme.text).frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 10).padding(.vertical, 8)
        .overlay(alignment: .bottom) { Rectangle().fill(Theme.rule).frame(height: 1) }
    }

    private func go(_ i: Int) { drill = i; picked = nil }

    private func answer(_ d: Learn.Drill, _ c: Int) {
        if picked == d.answer { return }
        picked = c
        if c == d.answer { user.learn(d.id) }
    }

    /// Opens the drill's function beside the lesson: the first other visible panel, or a second panel.
    private func openDrill(_ d: Learn.Drill) {
        guard let cmd = try? CommandParser.parse(d.command, current: nil) else { return }
        ws.maximized = nil
        if ws.layout == .one { ws.layout = .two }
        let target = ws.panels.prefix(ws.layout.count).first { $0.id != panelID }?.id ?? panelID
        ws.load(cmd, in: target)
        ws.focus(panelID)
    }
}
