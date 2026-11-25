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
/// Build this in CI from git, never from the agent's own report: the gate
/// trusts every field.
public struct ChangeSet: Sendable, Identifiable {
    public let id: String
    public let title: String
    /// The commit the evidence has to be about. Use the full SHA: commits are compared exactly.
    public let headCommit: String
    public let files: [ChangedFile]
    public let evidence: [Evidence]
    /// Rounds the agent has already spent on this change, counted by CI.
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

public extension ChangeSet {
    /// Reads the output of `git -c core.quotePath=false diff --name-status -M <base>...<head>`.
    ///
    /// Handles `A`, `M`, `D`, `T` and `R<score>`/`C<score>` lines. A line it
    /// can't read, including any path git quoted (it does that for tabs, quotes,
    /// backslashes and, unless `core.quotePath=false`, non-ASCII names), is kept
    /// as a file whose path is the raw line, so the gate reports it as an invalid
    /// path and fails closed instead of silently dropping or misfiling it.
    static func fromGitNameStatus(_ output: String, id: String, title: String, headCommit: String,
                                  evidence: [Evidence] = [], fixRounds: Int = 0,
                                  deletionReasons: [String: String] = [:]) -> ChangeSet {
        var files: [ChangedFile] = []
        for line in output.split(whereSeparator: \.isNewline) where !line.isEmpty {
            let fields = line.split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
            let unparsed = ChangedFile("/unparsed: " + line)
            guard let status = fields.first?.first,
                  !fields.dropFirst().contains(where: { $0.isEmpty || $0.hasPrefix("\"") }) else {
                files.append(unparsed)
                continue
            }
            switch (status, fields.count) {
            case ("A", 2): files.append(ChangedFile(fields[1], .added))
            case ("M", 2), ("T", 2): files.append(ChangedFile(fields[1], .modified))
            case ("D", 2): files.append(ChangedFile(fields[1], .deleted))
            case ("R", 3): files.append(ChangedFile(fields[2], .renamed(from: fields[1])))
            case ("C", 3): files.append(ChangedFile(fields[2], .added))
            default: files.append(unparsed)
            }
        }
        return ChangeSet(id: id, title: title, headCommit: headCommit, files: files,
                         evidence: evidence, fixRounds: fixRounds, deletionReasons: deletionReasons)
    }
}
