import SwiftUI
import EvidenceGate

@main
struct DemoApp: App {
    var body: some Scene {
        WindowGroup { RootView() }
    }
}

private enum Tab: String { case week, observe, prompt }

struct RootView: View {
    // Launch with `-tab week|observe|prompt` to open a tab directly.
    @State private var tab = Tab(rawValue: UserDefaults.standard.string(forKey: "tab") ?? "") ?? .week

    var body: some View {
        TabView(selection: $tab) {
            NavigationStack { WeekView(mode: .enforce) }
                .tabItem { Label("Enforce", systemImage: "checkmark.shield") }
                .tag(Tab.week)
            NavigationStack { WeekView(mode: .observe) }
                .tabItem { Label("Observe", systemImage: "eye") }
                .tag(Tab.observe)
            NavigationStack { PromptView() }
                .tabItem { Label("Prompt", systemImage: "text.alignleft") }
                .tag(Tab.prompt)
        }
    }
}

struct WeekView: View {
    let mode: GateMode
    private var verdicts: [Verdict] { SampleWeek.verdicts(mode: mode) }

    var body: some View {
        let v = verdicts
        List {
            Section {
                HStack(spacing: 10) {
                    Tally(count: v.filter { $0.decision == .pass }.count,
                          label: mode == .observe ? "would pass" : "pass", color: .green)
                    Tally(count: v.filter { $0.decision == .block }.count,
                          label: mode == .observe ? "would go to agent" : "back to agent", color: .orange)
                    Tally(count: v.filter { $0.decision == .needsHuman }.count,
                          label: mode == .observe ? "would need a person" : "need a person", color: .blue)
                }
                .listRowInsets(EdgeInsets(top: 8, leading: 12, bottom: 8, trailing: 12))
            } footer: {
                Text(mode == .observe
                     ? "Observe mode merges all 8 and logs what enforce would have done."
                     : "8 agent changes in a constructed week, judged by evidence on the head commit.")
            }
            Section("Changes") {
                ForEach(SampleWeek.changes) { change in
                    if let verdict = v.first(where: { $0.changeID == change.id }) {
                        NavigationLink { DetailView(change: change, verdict: verdict) } label: {
                            Row(change: change, verdict: verdict, mode: mode)
                        }
                    }
                }
            }
        }
        .navigationTitle(mode == .observe ? "Observe mode" : "Evidence gate")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct Tally: View {
    let count: Int, label: String, color: Color
    var body: some View {
        VStack(spacing: 2) {
            Text("\(count)").font(.title.bold()).foregroundStyle(color)
            Text(label).font(.caption).foregroundStyle(.secondary).lineLimit(1).minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity)
    }
}

private struct Row: View {
    let change: ChangeSet, verdict: Verdict, mode: GateMode
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(change.id).font(.caption.monospaced().bold())
                Spacer()
                Badge(decision: verdict.decision, observing: mode == .observe)
            }
            Text(change.title).font(.subheadline)
            Text(verdict.findings.first?.message ?? verdict.stamp)
                .font(.caption).foregroundStyle(.secondary).lineLimit(2)
        }
        .padding(.vertical, 2)
    }
}

private struct Badge: View {
    let decision: Decision, observing: Bool
    var body: some View {
        let (text, color): (String, Color) = switch decision {
        case .pass: ("PASS", .green)
        case .block: (observing ? "WOULD GO TO AGENT" : "TO AGENT", .orange)
        case .needsHuman: (observing ? "WOULD GO TO PERSON" : "PERSON", .blue)
        case .notEvaluated: ("NOT RUN", .gray)
        }
        Text(text).font(.caption2.bold()).padding(.horizontal, 6).padding(.vertical, 2)
            .background(color.opacity(0.18), in: Capsule()).foregroundStyle(color)
    }
}

struct DetailView: View {
    let change: ChangeSet, verdict: Verdict
    var body: some View {
        List {
            Section("Files") {
                ForEach(change.files, id: \.path) { Text($0.path).font(.caption.monospaced()) }
            }
            Section("Findings") {
                if verdict.findings.isEmpty { Text("None") }
                ForEach(Array(verdict.findings.enumerated()), id: \.offset) { _, f in
                    Text(f.message).font(.callout)
                }
            }
            Section("Commit trailer") { Text(verdict.stamp).font(.caption.monospaced()) }
        }
        .navigationTitle(change.id)
    }
}

struct PromptView: View {
    private let path = "Sources/Checkout/PlaceOrderButton.swift"
    var body: some View {
        ScrollView {
            Text(PromptRenderer.instructions(policy: SampleWeek.policy(), plannedPaths: [path]))
                .font(.system(.caption, design: .monospaced))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
                .padding(.bottom, 80)
        }
        .navigationTitle("Rendered prompt")
        .navigationBarTitleDisplayMode(.inline)
    }
}
