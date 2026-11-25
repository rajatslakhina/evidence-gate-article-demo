import Foundation

/// The kinds of check a change can be asked to prove itself with.
public enum EvidenceKind: String, Codable, Sendable, CaseIterable {
    case endToEnd
    case property
    case differential
    case unit
    case simulatorRun

    public var label: String {
        switch self {
        case .endToEnd: "end-to-end"
        case .property: "property"
        case .differential: "differential"
        case .unit: "unit"
        case .simulatorRun: "simulator run"
        }
    }
}

/// Who wrote the evidence record down.
///
/// `ci` and `hook` records are written by tooling that ran the command.
/// `agent` records are the agent typing "tests pass" into its own report.
/// The default policy only trusts the first two.
public enum EvidenceProducer: String, Codable, Sendable, CaseIterable {
    case ci
    case hook
    case agent
}

/// One record of a check that ran against one commit.
public struct Evidence: Codable, Hashable, Sendable {
    public let kind: EvidenceKind
    public let name: String
    public let commit: String
    public let passed: Bool
    /// Generated inputs a property test ran. `nil` for other kinds.
    public let cases: Int?
    public let producer: EvidenceProducer

    public init(kind: EvidenceKind, name: String, commit: String, passed: Bool,
                cases: Int? = nil, producer: EvidenceProducer = .ci) {
        self.kind = kind
        self.name = name
        self.commit = commit
        self.passed = passed
        self.cases = cases
        self.producer = producer
    }
}

/// Evidence read from a JSON Lines file, one record per line.
public struct EvidenceReport: Sendable, Equatable {
    public let evidence: [Evidence]
    /// Lines that weren't a valid record: usually prose such as
    /// "All tests pass!". They're kept so a reviewer can see them,
    /// but they never count as evidence.
    public let unparsedLines: [String]

    public static func parse(jsonLines text: String) -> EvidenceReport {
        let decoder = JSONDecoder()
        var evidence: [Evidence] = []
        var unparsed: [String] = []
        for rawLine in text.split(whereSeparator: \.isNewline) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty else { continue }
            if let record = try? decoder.decode(Evidence.self, from: Data(line.utf8)),
               Self.isValid(record) {
                evidence.append(record)
            } else {
                unparsed.append(line)
            }
        }
        return EvidenceReport(evidence: evidence, unparsedLines: unparsed)
    }

    static func isValid(_ e: Evidence) -> Bool {
        !e.name.trimmingCharacters(in: .whitespaces).isEmpty
            && !e.commit.trimmingCharacters(in: .whitespaces).isEmpty
            && (e.cases ?? 0) >= 0
    }
}
