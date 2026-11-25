/// One piece of evidence a change has to bring.
public struct EvidenceRequirement: Hashable, Sendable {
    public let kind: EvidenceKind
    /// A specific check, such as `checkout-flow`. `nil` accepts any check of `kind`.
    public let name: String?
    /// For property tests: the fewest generated inputs that count.
    public let minimumCases: Int?

    public init(_ kind: EvidenceKind, name: String? = nil, minimumCases: Int? = nil) {
        self.kind = kind
        self.name = name
        self.minimumCases = minimumCases
    }

    func accepts(_ e: Evidence) -> Bool {
        e.kind == kind && (name == nil || e.name == name)
    }

    public var summary: String {
        var text = kind.label
        if let name { text += " \"\(name)\"" } else { text += " (any)" }
        if let minimumCases { text += ", at least \(minimumCases) cases" }
        return text
    }
}

/// A reliability checklist item whose trigger can be read from the diff.
public struct ChecklistItem: Hashable, Sendable, Identifiable {
    public let id: String
    public let title: String
    public let triggers: [PathPattern]
    public let requires: [EvidenceRequirement]
    /// The incident or pull request the item came from.
    public let origin: String

    public init(id: String, title: String, triggers: [PathPattern],
                requires: [EvidenceRequirement], origin: String) {
        self.id = id
        self.title = title
        self.triggers = triggers
        self.requires = requires
        self.origin = origin
    }

    func isTriggered(by path: String) -> Bool {
        triggers.contains { $0.matches(path) }
    }
}

public enum GateMode: String, Sendable, CaseIterable {
    /// The gate doesn't run.
    case off
    /// The gate runs and records what it would have done, but lets everything through.
    case observe
    /// The gate's decision stands.
    case enforce
}

/// The rules a change is judged by.
///
/// Load this from the base branch, never from the change being judged.
/// The gate can't check where the value came from; your CI has to.
public struct GatePolicy: Sendable {
    /// Paths that judge changes: tests, snapshots, CI config and this policy's own file.
    public var protectedChecks: [PathPattern]
    /// Evidence every change to product code needs.
    public var baseline: [EvidenceRequirement]
    public var checklist: [ChecklistItem]
    public var trustedProducers: Set<EvidenceProducer>
    /// Fix rounds after which a still-failing check goes to a person.
    public var maxFixRounds: Int
    public var mode: GateMode

    public init(protectedChecks: [PathPattern],
                baseline: [EvidenceRequirement] = [EvidenceRequirement(.unit)],
                checklist: [ChecklistItem] = [],
                trustedProducers: Set<EvidenceProducer> = [.ci, .hook],
                maxFixRounds: Int = 3,
                mode: GateMode = .enforce) {
        self.protectedChecks = protectedChecks
        self.baseline = baseline
        self.checklist = checklist
        self.trustedProducers = trustedProducers
        self.maxFixRounds = max(1, maxFixRounds)
        self.mode = mode
    }

    public func isProtected(_ normalizedPath: String) -> Bool {
        protectedChecks.contains { $0.matches(normalizedPath) }
    }

    public func triggeredItems(for normalizedPaths: some Sequence<String>) -> [ChecklistItem] {
        let paths = Array(normalizedPaths)
        return checklist.filter { item in paths.contains { item.isTriggered(by: $0) } }
    }
}
