import Testing
@testable import EvidenceGate

/// Deterministic generator so a failing seed reproduces exactly.
struct SplitMix64: RandomNumberGenerator {
    private var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}

private let productRoots = ["Sources/Checkout", "Sources/Persistence", "Sources/Networking",
                            "Sources/Settings", "Sources/Profile"]
/// Product paths a person always reviews; mixed into generated changes so the
/// "a pass never touches a sensitive path" property can actually fail.
private let sensitiveFiles = ["Sources/Auth/Token.swift", "App/Info.plist", "App/App.entitlements"]
private let checkRoots = ["Tests/AppTests", "UITests", "Sources/Checkout/__Snapshots__",
                          ".github/workflows", ".gate", "tests/AppTests", ".claude", "Scripts"]
private let commits = ["aaa1111", "bbb2222", "ccc3333"]
private let casesPerSeed = 250
private let seeds: [UInt64] = [1, 2, 3, 4, 5, 6, 7, 8]

private extension SplitMix64 {
    mutating func pick<T>(_ items: [T]) -> T {
        items[Int.random(in: 0..<items.count, using: &self)]
    }

    mutating func path(in roots: [String]) -> String {
        "\(pick(roots))/F\(Int.random(in: 0..<20, using: &self)).swift"
    }

    /// Occasionally dresses a path up with `./` or `x/../`, which must not change the verdict
    /// unless it climbs out of the repository.
    mutating func disguised(_ path: String) -> String {
        switch Int.random(in: 0..<12, using: &self) {
        case 0: "./" + path
        case 1: "Sources/../" + path
        case 2: "../" + path
        default: path
        }
    }

    mutating func file() -> ChangedFile {
        let path = Int.random(in: 0..<10, using: &self) == 0
            ? pick(sensitiveFiles)
            : disguised(self.path(in: Bool.random(using: &self) ? productRoots : checkRoots))
        switch Int.random(in: 0..<6, using: &self) {
        case 0: return ChangedFile(path, .deleted)
        case 1: return ChangedFile(path, .renamed(from: self.path(in: Bool.random(using: &self) ? productRoots : checkRoots)))
        case 2: return ChangedFile(path, .added)
        default: return ChangedFile(path)
        }
    }

    mutating func evidence(head: String) -> Evidence {
        let kind = pick(EvidenceKind.allCases)
        let name: String = switch kind {
        case .endToEnd: "checkout-flow"
        case .differential: "store-migration"
        case .property: pick(["order-round-trip", "retry-idempotent"])
        case .unit: "AppTests"
        case .simulatorRun: "iPhone 17 Pro"
        }
        return Evidence(kind: kind, name: name,
                        commit: Bool.random(using: &self) ? head : pick(commits),
                        passed: Int.random(in: 0..<5, using: &self) > 0,
                        cases: kind == .property ? pick([nil, 10, 999, 1_000, 5_000]) : nil,
                        producer: pick(EvidenceProducer.allCases))
    }

    mutating func change() -> ChangeSet {
        let head = pick(commits)
        // A quarter of the time, build a change that's close to passing, so the
        // properties about passes see plenty of them.
        if Int.random(in: 0..<4, using: &self) == 0 {
            var files = (0..<Int.random(in: 1...3, using: &self)).map { _ in ChangedFile(path(in: productRoots)) }
            if Int.random(in: 0..<8, using: &self) == 0 { files.append(ChangedFile(pick(sensitiveFiles))) }
            var evidence = [Evidence(kind: .unit, name: "AppTests", commit: head, passed: true)]
            for kind in [EvidenceKind.endToEnd, .simulatorRun, .differential] where Bool.random(using: &self) {
                let name = kind == .endToEnd ? "checkout-flow" : kind == .differential ? "store-migration" : "iPhone 17 Pro"
                evidence.append(Evidence(kind: kind, name: name, commit: head, passed: true))
            }
            for name in ["order-round-trip", "retry-idempotent"] where Bool.random(using: &self) {
                evidence.append(Evidence(kind: .property, name: name, commit: head, passed: true,
                                         cases: pick([999, 1_000, 5_000])))
            }
            if Int.random(in: 0..<4, using: &self) == 0 { evidence.append(self.evidence(head: head)) }
            return ChangeSet(id: "gen", title: "", headCommit: head, files: files, evidence: evidence,
                             fixRounds: Int.random(in: 0...4, using: &self))
        }
        let files = (0..<Int.random(in: 1...4, using: &self)).map { _ in file() }
        let evidence = (0..<Int.random(in: 0...6, using: &self)).map { _ in self.evidence(head: head) }
        var reasons: [String: String] = [:]
        for f in files where f.change == .deleted && Bool.random(using: &self) {
            reasons[f.path] = "Flaky on CI; root cause not found."
        }
        return ChangeSet(id: "gen", title: "", headCommit: head, files: files, evidence: evidence,
                         fixRounds: Int.random(in: 0...4, using: &self), deletionReasons: reasons)
    }
}

private func reordered(_ c: ChangeSet, _ rng: inout SplitMix64) -> ChangeSet {
    ChangeSet(id: c.id, title: c.title, headCommit: c.headCommit,
              files: c.files.shuffled(using: &rng), evidence: c.evidence.shuffled(using: &rng),
              fixRounds: c.fixRounds, deletionReasons: c.deletionReasons)
}

@Suite("Gate properties")
struct GatePropertyTests {
    let gate = EvidenceGate(policy: SampleWeek.policy())

    @Test("Order of files and evidence never changes the verdict", arguments: seeds)
    func orderInvariance(seed: UInt64) {
        var rng = SplitMix64(seed: seed)
        for _ in 0..<casesPerSeed {
            let c = rng.change()
            let a = gate.evaluate(c), b = gate.evaluate(reordered(c, &rng))
            #expect(a.decision == b.decision && a.findings == b.findings && a.stamp == b.stamp)
        }
    }

    @Test("Adding a test edit to a product change never lets it pass", arguments: seeds)
    func checkEditsNeverPass(seed: UInt64) {
        var rng = SplitMix64(seed: seed)
        for _ in 0..<casesPerSeed {
            let c = rng.change()
            let withEdit = ChangeSet(
                id: c.id, title: c.title, headCommit: c.headCommit,
                files: c.files + [ChangedFile(rng.path(in: productRoots)), ChangedFile(rng.path(in: checkRoots))],
                evidence: c.evidence, fixRounds: c.fixRounds)
            let v = gate.evaluate(withEdit)
            #expect(v.decision != .pass)
            #expect(v.findings.contains { if case .modifiesOwnChecks = $0 { true } else { false } })
        }
    }

    @Test("Evidence about another commit never satisfies anything", arguments: seeds)
    func staleEvidenceNeverCounts(seed: UInt64) {
        var rng = SplitMix64(seed: seed)
        for _ in 0..<casesPerSeed {
            let c = rng.change()
            let stale = c.evidence.map {
                Evidence(kind: $0.kind, name: $0.name, commit: "deadbee", passed: $0.passed,
                         cases: $0.cases, producer: $0.producer)
            }
            let v = gate.evaluate(ChangeSet(id: c.id, title: "", headCommit: c.headCommit, files: c.files,
                                            evidence: stale, fixRounds: c.fixRounds))
            #expect(v.decision != .pass)
            #expect(v.stamp == "verified-by: none")
        }
    }

    @Test("Observe mode changes what happens, never what the policy decides", arguments: seeds)
    func observeMatchesEnforce(seed: UInt64) {
        var rng = SplitMix64(seed: seed)
        let observe = EvidenceGate(policy: SampleWeek.policy(mode: .observe))
        for _ in 0..<casesPerSeed {
            let c = rng.change()
            let o = observe.evaluate(c), e = gate.evaluate(c)
            #expect(o.enforced == .pass)
            #expect(o.decision == e.decision && o.findings == e.findings)
        }
    }

    @Test("A pass always means every required check has fresh, trusted, green evidence", arguments: seeds)
    func passImpliesEvidence(seed: UInt64) {
        var rng = SplitMix64(seed: seed)
        let policy = SampleWeek.policy()
        for _ in 0..<casesPerSeed {
            let c = rng.change()
            guard gate.evaluate(c).decision == .pass else { continue }
            let raw = c.files.flatMap(\.touchedPaths)
            let paths = raw.compactMap(RepoPath.normalize)
            #expect(paths.count == raw.count)
            #expect(!paths.contains(where: policy.isProtected))
            #expect(!paths.contains(where: policy.isSensitive))
            let requirements = policy.baseline + policy.triggeredItems(for: paths).flatMap(\.requires)
            let fresh = c.evidence.filter { $0.commit == c.headCommit && policy.trustedProducers.contains($0.producer) }
            #expect(fresh.allSatisfy { $0.passed })
            for r in requirements {
                let runs = fresh.filter(r.accepts)
                #expect(runs.allSatisfy { $0.passed })
                #expect(runs.contains { ($0.cases ?? 0) >= (r.minimumCases ?? 0) })
            }
        }
    }

    @Test("The generator reaches every decision, so the properties above aren't vacuous")
    func generatorCoversEveryDecision() {
        var counts: [Decision: Int] = [:]
        for seed in seeds {
            var rng = SplitMix64(seed: seed)
            for _ in 0..<casesPerSeed { counts[gate.evaluate(rng.change()).decision, default: 0] += 1 }
        }
        for decision in [Decision.pass, .block, .needsHuman] { #expect(counts[decision, default: 0] >= 20) }
    }
}
