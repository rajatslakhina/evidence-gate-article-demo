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
        lines.append("These paths judge your change or decide which checks run: "
                     + policy.protectedChecks.map(\.pattern).joined(separator: ", ") + ".")
        lines.append("Don't modify or delete existing checks there. If a check looks wrong, stop and tell me "
                     + "which one and why. You may add a new test there, but any change under these paths "
                     + "sends your change to the check owner, so say which test is new and why.")
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
        lines.append("If the change is still blocked after \(policy.maxFixRounds) fix rounds, stop and hand over "
                     + "with the failing output.")
        // The flaky-test rule follows the Claude Code team's verification post (Addy Osmani, Nov 2026).
        lines.append("Flaky tests: don't skip them, add sleeps or retry until green. Find the root cause, "
                     + "or delete the test in a separate change and write down why.")
        lines.append("After a bug fix, add the property test that would have caught it as a new test, "
                     + "and name the input that broke it.")
        return lines.joined(separator: "\n")
    }
}
