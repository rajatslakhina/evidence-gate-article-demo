/// Renders the agent's instructions from the same policy the gate enforces,
/// so the prompt and the check can't drift apart.
public enum PromptRenderer {
    public static func instructions(policy: GatePolicy, plannedPaths: [String]) -> String {
        let paths = plannedPaths.compactMap(RepoPath.normalize)
        let product = paths.filter { !policy.isProtected($0) }
        let items = policy.triggeredItems(for: product)

        var lines: [String] = []
        lines.append("You are changing: \(paths.joined(separator: ", ")).")
        lines.append("Done means the evidence gate passes on the commit you push. "
                     + "Describing the fix is not evidence.")
        lines.append("")
        lines.append("Do not edit these paths. They judge your change: "
                     + policy.protectedChecks.map(\.pattern).joined(separator: ", ") + ".")
        lines.append("If a check looks wrong, stop and tell me which one and why. Don't change it.")
        lines.append("")
        lines.append("Evidence this change needs, recorded by "
                     + policy.trustedProducers.map(\.rawValue).sorted().joined(separator: " or ")
                     + " on the commit you push:")
        for r in policy.baseline where !product.isEmpty {
            lines.append("- baseline: \(r.summary)")
        }
        for item in items {
            let needs = item.requires.map(\.summary).joined(separator: "; ")
            lines.append("- \(item.id) \(item.title): \(needs)")
        }
        lines.append("")
        lines.append("If a check still fails after \(policy.maxFixRounds) fix rounds, stop and hand over "
                     + "with the failing output.")
        lines.append("Flaky tests: don't skip them, add sleeps or retry until green. Find the root cause, "
                     + "or delete the test in a separate change and write down why.")
        lines.append("After a bug fix, write the property test that would have caught it, "
                     + "and name the input that broke it.")
        return lines.joined(separator: "\n")
    }
}
