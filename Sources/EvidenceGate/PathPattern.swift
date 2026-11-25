/// Repository-relative path helpers.
public enum RepoPath {
    /// Resolves `.` and `..` segments and removes empty ones.
    ///
    /// Returns `nil` for an absolute path, an empty path, or one that climbs
    /// above the repository root. The gate treats a `nil` as a blocking finding,
    /// so `Sources/../Tests/X.swift` can't slip past a `Tests/**` rule.
    public static func normalize(_ raw: String) -> String? {
        guard !raw.hasPrefix("/") else { return nil }
        var out: [Substring] = []
        for segment in raw.split(separator: "/", omittingEmptySubsequences: true) {
            switch segment {
            case ".":
                continue
            case "..":
                guard !out.isEmpty else { return nil }
                out.removeLast()
            default:
                out.append(segment)
            }
        }
        return out.isEmpty ? nil : out.joined(separator: "/")
    }
}

/// A glob over normalized repository paths.
///
/// `*` matches any run of characters inside one path segment and `**` matches
/// zero or more whole segments. Matching ignores case on purpose: the default
/// macOS file system is case-insensitive, so `tests/` and `Tests/` are the same
/// folder on a developer's Mac and must be protected the same way.
public struct PathPattern: Hashable, Sendable, CustomStringConvertible {
    public let pattern: String
    private let segments: [String]

    public init(_ pattern: String) {
        self.pattern = pattern
        self.segments = pattern.lowercased()
            .split(separator: "/", omittingEmptySubsequences: true)
            .map(String.init)
    }

    public var description: String { pattern }

    /// `path` should already be normalized with ``RepoPath/normalize(_:)``.
    public func matches(_ path: String) -> Bool {
        let parts = path.lowercased()
            .split(separator: "/", omittingEmptySubsequences: true)
            .map(String.init)
        return Self.match(segments[...], parts[...])
    }

    private static func match(_ pattern: ArraySlice<String>, _ path: ArraySlice<String>) -> Bool {
        guard let head = pattern.first else { return path.isEmpty }
        if head == "**" {
            let rest = pattern.dropFirst()
            var tail = path
            while true {
                if match(rest, tail) { return true }
                guard !tail.isEmpty else { return false }
                tail = tail.dropFirst()
            }
        }
        guard let first = path.first, segmentMatches(head, first) else { return false }
        return match(pattern.dropFirst(), path.dropFirst())
    }

    /// Single-segment wildcard match where `*` is the only metacharacter.
    static func segmentMatches(_ pattern: String, _ text: String) -> Bool {
        let p = Array(pattern), t = Array(text)
        var pi = 0, ti = 0
        var star: Int? = nil
        var mark = 0
        while ti < t.count {
            if pi < p.count, p[pi] == "*" {
                star = pi
                mark = ti
                pi += 1
            } else if pi < p.count, p[pi] == t[ti] {
                pi += 1
                ti += 1
            } else if let s = star {
                pi = s + 1
                mark += 1
                ti = mark
            } else {
                return false
            }
        }
        while pi < p.count, p[pi] == "*" { pi += 1 }
        return pi == p.count
    }
}
