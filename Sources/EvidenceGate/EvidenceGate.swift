import Foundation

/// Judges a change by the evidence recorded for its head commit, not by what
/// the agent says about it.
///
/// Build the ``ChangeSet`` in CI from git (``ChangeSet/fromGitNameStatus(_:id:title:headCommit:evidence:fixRounds:deletionReasons:)``)
/// and CI's own round counter. Never build it from anything the agent reports:
/// the gate trusts every field it's given.
public struct EvidenceGate: Sendable {
    public let policy: GatePolicy

    public init(policy: GatePolicy) {
        self.policy = policy
    }

    public func evaluate(_ change: ChangeSet) -> Verdict {
        guard policy.mode != .off else {
            return Verdict(changeID: change.id, decision: .notEvaluated, enforced: .pass,
                           findings: [], triggeredItems: [], stamp: "verified-by: none")
        }

        // 1. Split the diff into product code and checks.
        var productPaths = Set<String>()
        var checkPaths = Set<String>()
        var sensitive = Set<String>()
        var invalid = Set<String>()
        var deletedWithoutReason = Set<String>()
        for file in change.files {
            for raw in file.touchedPaths {
                guard let path = RepoPath.normalize(raw) else { invalid.insert(raw); continue }
                if policy.isProtected(path) { checkPaths.insert(path) } else { productPaths.insert(path) }
                if policy.isSensitive(path) { sensitive.insert(path) }
            }
            if case .deleted = file.change, let path = RepoPath.normalize(file.path),
               policy.isProtected(path), !hasReason(for: path, raw: file.path, in: change) {
                deletedWithoutReason.insert(path)
            }
        }

        var findings: [Finding] = invalid.sorted().map(Finding.invalidPath)
        if change.files.isEmpty { findings.append(.emptyChange) }
        if !checkPaths.isEmpty && !productPaths.isEmpty {
            findings.append(.modifiesOwnChecks(checkPaths.sorted()))
        }
        if !sensitive.isEmpty { findings.append(.sensitivePath(sensitive.sorted())) }
        findings += deletedWithoutReason.sorted().map(Finding.deletedCheckWithoutReason)

        // 2. Work out what this diff has to prove.
        var requirements: [(item: String, requirement: EvidenceRequirement)] = []
        let triggered = policy.triggeredItems(for: productPaths)
        if !productPaths.isEmpty {
            requirements += policy.baseline.map { ("baseline", $0) }
            for item in triggered {
                requirements += item.requires.map { (item.id, $0) }
            }
        }

        // 3. Keep only evidence about this commit, from producers the policy trusts.
        //    Commits are compared exactly, so record full SHAs everywhere.
        var notes = Set<Finding>()
        var usable: [Evidence] = []
        for e in change.evidence {
            if e.commit != change.headCommit {
                notes.insert(.staleEvidence(name: e.name, commit: e.commit))
            } else if !policy.trustedProducers.contains(e.producer) {
                notes.insert(.untrustedEvidence(name: e.name, producer: e.producer))
            } else {
                usable.append(e)
            }
        }
        usable.sort(by: Self.canonicalOrder)

        // 4. Match evidence to requirements.
        var stampEntries = Set<String>()
        var reportedFailures: [(EvidenceKind, String)] = []
        for (item, requirement) in requirements {
            let candidates = usable.filter(requirement.accepts)
            let minimum = requirement.minimumCases ?? 0
            let satisfying = candidates.filter { $0.passed && ($0.cases ?? 0) >= minimum }
            // A failed run on the head commit isn't erased by a later green run of the
            // same code: rerunning until it passes is how flaky checks get waved through.
            if let failed = candidates.first(where: { !$0.passed }) {
                reportedFailures.append((failed.kind, failed.name))
                findings.append(.failingEvidence(item: item, name: failed.name))
            } else if !satisfying.isEmpty {
                satisfying.forEach { stampEntries.insert("\($0.kind.rawValue)(\($0.name))") }
            } else if let best = candidates.max(by: { ($0.cases ?? 0) < ($1.cases ?? 0) }) {
                findings.append(.insufficientCases(item: item, name: best.name,
                                                   ran: best.cases ?? 0, required: minimum))
            } else {
                findings.append(.missingEvidence(item: item, requirement: requirement))
            }
        }
        // A trusted failure on the head commit counts even if nothing required that check.
        let unrequiredFailures = Set(usable.filter { e in
            !e.passed && !reportedFailures.contains { $0.0 == e.kind && $0.1 == e.name }
        }.map(\.name))
        findings += unrequiredFailures.sorted().map { Finding.failingEvidence(item: "not required", name: $0) }

        // 5. Decide. Problems the agent can fix go back to the agent, up to the round limit.
        //    A change that edits its own checks or touches a sensitive path never passes
        //    on its own evidence: once everything else is green, it goes to a person.
        let structural = findings.contains {
            switch $0 {
            case .emptyChange, .invalidPath, .deletedCheckWithoutReason: true
            default: false
            }
        }
        let fixable = findings.contains { $0.severity == .blocking }
        let decision: Decision
        if structural {
            decision = .block
        } else if fixable && change.fixRounds >= policy.maxFixRounds {
            findings.append(.stillBlockedAfterRounds(change.fixRounds))
            decision = .needsHuman
        } else if fixable {
            decision = .block
        } else if findings.contains(where: { $0.severity == .escalation }) {
            decision = .needsHuman
        } else if productPaths.isEmpty && !checkPaths.isEmpty {
            findings.append(.checkChangeNeedsOwner(checkPaths.sorted()))
            decision = .needsHuman
        } else {
            decision = .pass
        }

        let ordered = Self.stableOrder(findings) + notes.sorted { $0.message < $1.message }
        let stamp = stampEntries.isEmpty
            ? "verified-by: none"
            : "verified-by: " + stampEntries.sorted().joined(separator: ", ")
        return Verdict(changeID: change.id,
                       decision: decision,
                       enforced: policy.mode == .observe ? .pass : decision,
                       findings: ordered,
                       triggeredItems: triggered.map(\.id),
                       stamp: stamp)
    }

    private func hasReason(for path: String, raw: String, in change: ChangeSet) -> Bool {
        let reason = change.deletionReasons[path] ?? change.deletionReasons[raw] ?? ""
        return !reason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// Input order must not change the verdict, so evidence is sorted first.
    static func canonicalOrder(_ a: Evidence, _ b: Evidence) -> Bool {
        let ka = (a.kind.rawValue, a.name, a.passed ? 1 : 0, a.cases ?? -1, a.producer.rawValue)
        let kb = (b.kind.rawValue, b.name, b.passed ? 1 : 0, b.cases ?? -1, b.producer.rawValue)
        return ka < kb
    }

    /// Severity first; within a severity, the order the checks produced them.
    static func stableOrder(_ findings: [Finding]) -> [Finding] {
        findings.enumerated()
            .sorted { ($0.element.severity, $0.offset) < ($1.element.severity, $1.offset) }
            .map(\.element)
    }
}
