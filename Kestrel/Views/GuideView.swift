import SwiftUI
import KestrelCore

/// Floating guide button (bottom right) and its chat panel.
struct GuideOverlay: View {
    @Bindable var guide: GuideService

    var body: some View {
        VStack(alignment: .trailing, spacing: 10) {
            if guide.isOpen {
                GuidePanel(guide: guide)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
            GuideButton(open: guide.isOpen) {
                withAnimation(.spring(duration: 0.3)) { guide.isOpen.toggle() }
            }
        }
        .padding(.trailing, 14)
        .padding(.bottom, 52)          // clear of the function key bar
    }
}

/// The guide's mascot: the Kestrel mark in a round badge that bobs gently until opened.
struct GuideButton: View {
    let open: Bool
    let action: () -> Void
    @State private var bob = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle().fill(Theme.header)
                Circle().stroke(Theme.accent.opacity(0.7), lineWidth: 1.5)
                if open {
                    Image(systemName: "xmark").font(.system(size: 18, weight: .bold)).foregroundStyle(Theme.accent)
                } else {
                    KestrelMark().frame(width: 26.pt, height: 22.pt).offset(y: 1)
                    Text("?").font(.ui(12, .heavy)).foregroundStyle(Theme.canvas)
                        .frame(width: 18.pt, height: 18.pt).background(Theme.accent, in: .circle)
                        .offset(x: 18, y: -18)
                }
            }
            .frame(width: 54.pt, height: 54.pt)
            .shadow(color: Theme.accent.opacity(0.25), radius: 10)
            .offset(y: bob && !open ? -3 : 0)
            .contentShape(.circle)
        }
        .buttonStyle(.terminal)
        .accessibilityLabel(open ? "Close the guide" : "Ask the Kestrel guide")
        .keyboardShortcut("/", modifiers: .command)
        .onAppear {
            // No bobbing under Reduce Motion (or in UI tests).
            guard !reduceMotion, !SnapshotTour.isUITest else { return }
            withAnimation(.easeInOut(duration: 1.6).repeatForever(autoreverses: true)) { bob = true }
        }
    }
}

struct GuidePanel: View {
    @Bindable var guide: GuideService
    @State private var draft = ""
    @FocusState private var focused: Bool

    var body: some View {
        VStack(spacing: 0) {
            header
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(guide.messages) { m in bubble(m, latest: m.id == guide.messages.last?.id).id(m.id) }
                    }
                    .padding(12)
                }
                .onChange(of: guide.messages.count) {
                    if let last = guide.messages.last { withAnimation { proxy.scrollTo(last.id, anchor: .bottom) } }
                }
            }
            input
        }
        .frame(width: 380.pt, height: 500.pt)
        .background(Theme.panel)
        .clipShape(.rect(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Theme.accentDim))
        .shadow(color: .black.opacity(0.5), radius: 24, y: 8)
        .onAppear { focused = true }
    }

    private var header: some View {
        HStack(spacing: 8) {
            KestrelMark().frame(width: 18.pt, height: 15.pt)
            Text("Kestrel Guide").font(.ui(14, .semibold)).foregroundStyle(Theme.text)
            Text("ON DEVICE")
                .font(.mono(8, .bold)).foregroundStyle(Theme.canvas)
                .padding(.horizontal, 5).frame(height: 15.pt)
                .background(Theme.dim, in: .rect(cornerRadius: 2))
                .help("The guide runs entirely on this device; your questions never leave it.")
            Spacer()
            Button { guide.reset() } label: { Image(systemName: "arrow.counterclockwise").font(.system(size: 12, weight: .semibold)) }
                .buttonStyle(.terminal).foregroundStyle(Theme.dim).accessibilityLabel("Start over")
        }
        .padding(.horizontal, 12).frame(height: 40.pt)
        .background(Theme.header)
    }

    private func bubble(_ m: GuideService.Message, latest: Bool) -> some View {
        VStack(alignment: m.role == .user ? .trailing : .leading, spacing: 6) {
            Text(m.text)
                .font(.ui(13)).foregroundStyle(m.role == .user ? Theme.canvas : Theme.text)
                .textSelection(.enabled)
                .padding(.horizontal, 10).padding(.vertical, 8)
                .background(m.role == .user ? Theme.accent : Theme.header, in: .rect(cornerRadius: 8))
                .frame(maxWidth: 300.pt, alignment: m.role == .user ? .trailing : .leading)
            if !m.commands.isEmpty {
                FlowChips(items: m.commands) { cmd in _ = guide.run(cmd) }
            }
            // Suggested next questions, on the latest answer only.
            if latest, !m.followUps.isEmpty {
                VStack(alignment: .leading, spacing: 5) {
                    ForEach(m.followUps, id: \.self) { f in
                        Button { guide.ask(f) } label: {
                            Text(f).font(.ui(12)).foregroundStyle(Theme.accent)
                                .padding(.horizontal, 10).padding(.vertical, 5)
                                .overlay(RoundedRectangle(cornerRadius: 13).stroke(Theme.accentDim))
                        }
                        .buttonStyle(.terminal)
                    }
                }
                .padding(.top, 2)
            }
        }
        .frame(maxWidth: .infinity, alignment: m.role == .user ? .trailing : .leading)
    }

    private var input: some View {
        HStack(spacing: 8) {
            TextField("", text: $draft, axis: .vertical)
                .placeholder("Ask anything about Kestrel…", when: draft.isEmpty)
                .font(.ui(13)).foregroundStyle(Theme.text).textFieldStyle(.plain)
                .lineLimit(1...4).focused($focused)
                .onSubmit(send)
            Button(action: send) {
                Image(systemName: "arrow.up").font(.system(size: 13, weight: .bold)).foregroundStyle(Theme.canvas)
                    .frame(width: 28.pt, height: 28.pt).background(draft.isEmpty ? Theme.faint : Theme.accent, in: .circle)
            }
            .buttonStyle(.terminal).disabled(draft.isEmpty)
            .accessibilityLabel("Send")
        }
        .padding(10)
        .background(Theme.canvas)
        .overlay(alignment: .top) { Rectangle().fill(Theme.rule).frame(height: 1.pt) }
    }

    private func send() {
        let q = draft
        draft = ""
        guide.ask(q)
    }
}

/// Tap-to-run command chips that wrap onto new lines.
struct FlowChips: View {
    let items: [String]
    let tap: (String) -> Void

    var body: some View {
        FlowLayout(spacing: 6) {
            ForEach(items, id: \.self) { c in
                Button { tap(c) } label: {
                    HStack(spacing: 4) {
                        Text(c).font(.mono(11, .bold))
                        Image(systemName: "arrow.up.forward").font(.system(size: 8, weight: .bold))
                    }
                    .foregroundStyle(Theme.accent)
                    .padding(.horizontal, 8).padding(.vertical, 5)
                    .background(Theme.selection, in: .rect(cornerRadius: 4))
                }
                .buttonStyle(.terminal)
                .accessibilityLabel("Run \(c)")
            }
        }
    }
}

/// Minimal wrapping layout for chips.
struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? 300
        var x: CGFloat = 0, y: CGFloat = 0, line: CGFloat = 0
        for s in subviews {
            let d = s.sizeThatFits(.unspecified)
            if x > 0, x + d.width > width { x = 0; y += line + spacing; line = 0 }
            x += d.width + spacing
            line = max(line, d.height)
        }
        return CGSize(width: width, height: y + line)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, line: CGFloat = 0
        for s in subviews {
            let d = s.sizeThatFits(.unspecified)
            if x > bounds.minX, x + d.width > bounds.maxX { x = bounds.minX; y += line + spacing; line = 0 }
            s.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(d))
            x += d.width + spacing
            line = max(line, d.height)
        }
    }
}
