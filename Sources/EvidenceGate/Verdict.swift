public enum Decision: String, Sendable, CaseIterable {
    /// Merge without a person reading it.
    case pass
    /// Back to the agent. Something it can fix itself is missing or wrong.
    case block
    /// A person has to look, and the findings say why.
    case needsHuman
}

public enum Finding: Hashable, Sendable {
    public enum Severity: Int, Sendable, Comparable {
        case blocking = 0, escalation = 1, note = 2
        public static func < (a: Severity, b: Severity) -> Bool { a.rawValue < b.rawValue }
    }

    case emptyChange
    case invalidPath(String)
    case modifiesOwnChecks([String])
    case deletedCheckWithoutReason(String)
    case missingEvidence(item: String, requirement: EvidenceRequirement)
    case failingEvidence(item: String, name: String)
    case insufficientCases(item: String, name: String, ran: Int, required: Int)
    case stillFailingAfterRounds(Int)
    case checkChangeNeedsOwner([String])
    case staleEvidence(name: String, commit: String)
    case untrustedEvidence(name: String, producer: EvidenceProducer)

    public var severity: Severity {
        switch self {
        case .stillFailingAfterRounds, .checkChangeNeedsOwner, .modifiesOwnChecks: .escalation
        case .staleEvidence, .untrustedEvidence: .note
        default: .blocking
        }
    }

    public var message: String {
        switch self {
        case .emptyChange:
            "The change touches no files."
        case .invalidPath(let p):
            "Path \"\(p)\" is absolute or climbs out of the repository."
        case .modifiesOwnChecks(let paths):
            "Edits the checks that judge it (\(paths.joined(separator: ", "))). It can't pass on its own evidence; the check owner reviews it."
        case .deletedCheckWithoutReason(let p):
            "Deletes \(p) without writing down why."
        case .missingEvidence(let item, let r):
            "\(item): no usable evidence for \(r.summary)."
        case .failingEvidence(let item, let name):
            "\(item): \(name) failed."
        case .insufficientCases(let item, let name, let ran, let required):
            "\(item): \(name) ran \(ran) cases; needs \(required)."
        case .stillFailingAfterRounds(let n):
            "Still failing after \(n) fix rounds. Stop and hand over."
        case .checkChangeNeedsOwner(let paths):
            "Changes only checks (\(paths.joined(separator: ", "))). The check owner reviews it."
        case .staleEvidence(let name, let commit):
            "Ignored \(name): recorded on \(commit), not the head commit."
        case .untrustedEvidence(let name, let producer):
            "Ignored \(name): written by \(producer.rawValue), which this policy doesn't trust."
        }
    }
}

public struct Verdict: Sendable {
    public let changeID: String
    /// What the policy decided.
    public let decision: Decision
    /// What actually happens. In observe mode this is always `.pass`.
    public let enforced: Decision
    /// Blocking findings first, then escalations, then notes.
    public let findings: [Finding]
    public let triggeredItems: [String]
    /// How the change was verified, for the commit trailer. "none" is a valid answer.
    public let stamp: String

    public var wouldHaveBlocked: Bool { decision == .block && enforced != .block }
    /// True when observe mode let through something enforce would have sent to a person.
    public var wouldHaveEscalated: Bool { decision == .needsHuman && enforced != .needsHuman }
}
