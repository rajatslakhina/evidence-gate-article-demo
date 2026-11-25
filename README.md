# EvidenceGate

A small Swift package that judges a coding agent's change by the **evidence recorded for its head commit**, not by what the agent says about it. It's the demo for the article *More Reviewers Won't Fix the Coding Agent Review Bottleneck. Verification the Agent Can't Edit Might.*

Article: (added after publish)

![The demo app on the iOS Simulator: a constructed week of 8 agent changes, 2 pass, 3 go back to the agent, 3 need a person](Demo/Screenshots/week-cropped.png)

## What it does

Each rule comes from the Claude Code team's [verification playbook](https://claude.dev/blog/how-the-claude-code-team-thinks-about-verification/) (Addy Osmani, 16 Nov 2026), translated for an iOS repo:

| Rule | What the gate does |
|------|--------------------|
| Checks trigger on the diff | A `ChecklistItem` names the paths that trigger it (`Sources/Persistence/**`) and the evidence it needs (a differential migration test, a property test with at least 1,000 cases). Only triggered items apply. |
| Evidence is about the head commit | Records for any other commit are ignored and listed as notes. |
| Only tooling writes evidence | Records from `ci` or `hook` count by default. An `agent` record ("all tests pass") doesn't. |
| A rerun doesn't erase a failure | If a required check failed on the head commit, a later green run of the same code doesn't cancel it. |
| A change can't pass on its own evidence if it edits its checks | Tests, UI tests, snapshots, test plans, CI workflows and `.gate/**` are protected. Editing them in a product change sends it to a person. Paths are normalized (`Sources/../Tests/x` is caught), renames count at both ends, and matching ignores case, because the default macOS file system does. |
| Three fix rounds, then a person | A check still failing after `maxFixRounds` (default 3) escalates. Fewer rounds go back to the agent. |
| No quiet deletions | Deleting a protected file without a written reason blocks; with one, the check owner reviews it. |
| Start in observe mode | `.observe` lets everything through and records what `.enforce` would have done. `.off` doesn't run. |
| Stamp every commit | Each verdict carries a `verified-by:` trailer. `verified-by: none` is a valid answer. |

```swift
import EvidenceGate

let gate = EvidenceGate(policy: SampleWeek.policy())     // load your real policy from the base branch
let verdict = gate.evaluate(change)

switch verdict.enforced {
case .pass:       print(verdict.stamp)                   // verified-by: endToEnd(checkout-flow), ...
case .block:      print(verdict.findings.map(\.message)) // back to the agent
case .needsHuman: print(verdict.findings.map(\.message)) // the reason a person is reading it
}
```

The agent's instructions are rendered from the same policy, so the prompt and the gate can't drift:

```swift
let prompt = PromptRenderer.instructions(policy: policy,
                                         plannedPaths: ["Sources/Checkout/PlaceOrderButton.swift"])
```

## The constructed week

`SampleWeek` is eight illustrative changes to a made-up shopping app (not real data):

| Change | Decision | Why |
|--------|----------|-----|
| CHK-101 Fix disabled Place Order button | pass | unit, `checkout-flow` end-to-end and a Simulator run, all on the head commit |
| CHK-102 Same fix, agent also edited the flow test | person | edits `UITests/CheckoutFlowTests.swift` |
| PER-201 Add `giftNote` to the Order model | back to agent | REL-01 needs a differential migration test and a property test |
| PER-202 Same, with migration evidence | pass | differential + 2,000 property cases |
| NET-301 Retry on HTTP 429 | back to agent | property test ran 50 cases; needs 1,000 |
| SET-401 Rename the Sign Out label | back to agent | its only unit evidence is from an old commit or self-reported |
| FLK-501 Delete a flaky snapshot test | person | checks-only change with a written reason: the owner reviews it |
| CHK-103 Show the Apple Pay sheet | person | `checkout-flow` still failing after 3 fix rounds |

In observe mode all eight merge, and the verdicts record the 3 that enforce would block and the 3 it would escalate.

## How to run it

1. `git clone https://github.com/rajatslakhina/evidence-gate-article-demo.git`
2. Open `Demo.xcodeproj` in Xcode 16 or later (built here with Xcode 27.2).
3. Pick any iPhone Simulator and press Run. No other setup: the app uses this repo's package through a local package reference.

Tabs: **Enforce** (the week), **Observe** (the same week in observe mode), **Prompt** (the rendered instructions for a checkout change). Tap a change to see every finding and its commit trailer.

Library only: `swift build` and `swift test`.

## Tests

36 Swift Testing tests in 6 suites, including five property tests. Each property runs 2,000 generated changes (8 fixed seeds × 250, with a deterministic SplitMix64 generator so a failure reproduces):

- the order of files and evidence never changes the verdict;
- adding a test edit to a product change never lets it pass;
- evidence about another commit never satisfies anything;
- observe mode changes what happens, never what the policy decides;
- a pass always means every required check has fresh, trusted, green evidence.

A sixth test checks the generator reaches every decision at least 20 times, so the properties aren't passing on empty input. Before publishing I broke the gate twice on purpose (ignoring the commit check, and letting a later pass cancel a failure); the suite failed both times.

## Questions you might have

**How do I use this on my own repo?** Write your protected paths and two or three checklist items from real incidents, have CI and your verify hook write evidence as JSON Lines (`EvidenceReport.parse(jsonLines:)`), and run the gate in `.observe` for a couple of weeks before `.enforce`. Load the policy from the base branch in CI, never from the pull request.

**Isn't this CODEOWNERS plus required checks?** Those are parts of it. CODEOWNERS routes test edits to a reviewer, and required checks are fixed per branch. Neither knows which evidence a diff needs, whether a pass was for the head commit, or whether it followed a failure. The gate joins those up per change.

**What if a feature legitimately needs new or updated tests?** It still works: the change goes to the check owner instead of merging on its own evidence. The finding names the test files to read.

**Can the agent fake evidence?** Yes, if your hook writes records somewhere the agent can write. The gate trusts the `producer` label; it doesn't verify signatures. Produce evidence in CI, or sign it, before enforcing.

**What does it cost?** Writing checklist items, and keeping end-to-end and property tests fast enough to run on every change.

**What doesn't it guarantee?** That a test is any good. A weak end-to-end test still passes, which is why checks have owners.

## Limits

- Paths only: it doesn't read diffs, so a checklist trigger is a path glob, not a code pattern.
- No provenance: evidence records aren't signed or attested.
- The policy's origin isn't checked: your CI has to load it from the base branch.
- `**` matching is backtracking; fine for a handful of patterns, not for thousands.
- The week, the paths and the incidents behind the checklist items are constructed for illustration.

## Verification status

For the version in this repo: clean `swift build -Xswiftc -warnings-as-errors` and `swift test` (36 tests in 6 suites passed) on macOS with Xcode 27.2 / Swift 6.4.2. The demo app was built with `xcodebuild`, installed and launched on a fresh iPhone 17 Pro Simulator (iOS 27.2) for each tab, confirmed still running, and the screenshots in `Demo/Screenshots/` were captured from that run. CI: (added after the first run)

## Sources

- Addy Osmani, [How the Claude Code team thinks about verification](https://claude.dev/blog/how-the-claude-code-team-thinks-about-verification/), claude.dev, 16 Nov 2026.
- ComplexDiscovery, [Harvard researchers find AI coding agents shifted the bottleneck to code review](https://complexdiscovery.com/harvard-researchers-find-ai-coding-agents-shifted-the-bottleneck-to-code-review/), 13 Oct 2026, on Fiona Chen and James Stratton's working paper.

## License

MIT
