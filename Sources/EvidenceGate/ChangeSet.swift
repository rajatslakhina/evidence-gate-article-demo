/// One file in a change.
public struct ChangedFile: Hashable, Sendable {
    public enum Change: Hashable, Sendable {
        case added
        case modified
        case deleted
        case renamed(from: String)
    }

    public let path: String
    public let change: Change

    public init(_ path: String, _ change: Change = .modified) {
        self.path = path
        self.change = change
    }

    /// Every path the change touches. A rename touches both ends, so moving
    /// a test out of `Tests/` counts as editing a check.
    public var touchedPaths: [String] {
        if case .renamed(let source) = change { return [source, path] }
        return [path]
    }
}

/// A change an agent wants to merge, with the evidence recorded for it.
public struct ChangeSet: Sendable, Identifiable {
    public let id: String
    public let title: String
    /// The commit the evidence has to be about.
    public let headCommit: String
    public let files: [ChangedFile]
    public let evidence: [Evidence]
    /// Rounds the agent has already spent trying to fix failing checks.
    public let fixRounds: Int
    /// Why each deleted check was deleted, keyed by path.
    public let deletionReasons: [String: String]

    public init(id: String, title: String, headCommit: String, files: [ChangedFile],
                evidence: [Evidence] = [], fixRounds: Int = 0,
                deletionReasons: [String: String] = [:]) {
        self.id = id
        self.title = title
        self.headCommit = headCommit
        self.files = files
        self.evidence = evidence
        self.fixRounds = max(0, fixRounds)
        self.deletionReasons = deletionReasons
    }
}
