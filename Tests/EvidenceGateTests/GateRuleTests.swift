import Testing
@testable import EvidenceGate

private let head = "abc1234"
private let gate = EvidenceGate(policy: SampleWeek.policy())

private func unit(_ commit: String = head, passed: Bool = true,
                  producer: EvidenceProducer = .ci) -> Evidence {
    Evidence(kind: .unit, name: "AppTests", commit: commit, passed: passed, producer: producer)
}

@Suite("Path rules")
struct PathRuleTests {
    @Test("Globs", arguments: [
        ("Tests/**", "Tests/A/B.swift", true),
        ("Tests/**", "Tests", true),
        ("Tests/**", "Sources/Tests.swift", false),
        ("**/__Snapshots__/**", "Sources/X/__Snapshots__/a.png", true),
        ("**/*.xctestplan", "App.xctestplan", true),
        ("**/*.xctestplan", "Plans/Smoke.xctestplan", true),
        ("Sources/*.swift", "Sources/A/B.swift", false),
        ("Sources/Check*/**", "Sources/Checkout/A.swift", true),
        ("tests/**", "TESTS/a.swift", true),
    ])
    func glob(pattern: String, path: String, expected: Bool) {
        #expect(PathPattern(pattern).matches(path) == expected)
    }

    @Test("Normalization", arguments: [
        ("./Sources//A.swift", "Sources/A.swift" as String?),
        ("Sources/../Tests/A.swift", "Tests/A.swift"),
        ("../outside.swift", nil),
        ("/etc/passwd", nil),
        ("", nil),
    ])
    func normalize(raw: String, expected: String?) {
        #expect(RepoPath.normalize(raw) == expected)
    }

    @Test func dotDotCannotHideATestEdit() {
        let change = ChangeSet(id: "x", title: "", headCommit: head, files: [
            ChangedFile("Sources/App/A.swift"),
            ChangedFile("Sources/../Tests/AppTests/ATests.swift"),
        ], evidence: [unit()])
        #expect(gate.evaluate(change).findings.first == .modifiesOwnChecks(["Tests/AppTests/ATests.swift"]))
    }

    @Test func caseCannotHideATestEdit() {
        let change = ChangeSet(id: "x", title: "", headCommit: head, files: [
            ChangedFile("Sources/App/A.swift"), ChangedFile("tests/AppTests/ATests.swift"),
        ], evidence: [unit()])
        let v = gate.evaluate(change)
        #expect(v.decision == .needsHuman)
        #expect(v.findings == [.modifiesOwnChecks(["tests/AppTests/ATests.swift"])])
    }

    @Test func movingATestOutOfTestsIsATestEdit() {
        let change = ChangeSet(id: "x", title: "", headCommit: head, files: [
            ChangedFile("Sources/App/ATests.swift", .renamed(from: "Tests/AppTests/ATests.swift")),
        ], evidence: [unit()])
        #expect(gate.evaluate(change).findings.first == .modifiesOwnChecks(["Tests/AppTests/ATests.swift"]))
    }

    @Test func editingThePolicyFileIsACheckChange() {
        let change = ChangeSet(id: "x", title: "", headCommit: head,
                               files: [ChangedFile(".gate/policy.json")])
        #expect(gate.evaluate(change).decision == .needsHuman)
    }

    @Test func absolutePathBlocks() {
        let change = ChangeSet(id: "x", title: "", headCommit: head,
                               files: [ChangedFile("/Users/me/repo/Tests/A.swift")], evidence: [unit()])
        let v = gate.evaluate(change)
        #expect(v.decision == .block)
        #expect(v.findings.first == .invalidPath("/Users/me/repo/Tests/A.swift"))
    }
}

@Suite("Evidence rules")
struct EvidenceRuleTests {
    @Test func plainProductChangeWithUnitEvidencePasses() {
        let change = ChangeSet(id: "x", title: "", headCommit: head,
                               files: [ChangedFile("Sources/Profile/Avatar.swift")], evidence: [unit()])
        let v = gate.evaluate(change)
        #expect(v.decision == .pass)
        #expect(v.triggeredItems.isEmpty)
    }

    @Test func failingCheckBeforeTheRoundLimitGoesBackToTheAgent() {
        let change = ChangeSet(id: "x", title: "", headCommit: head,
                               files: [ChangedFile("Sources/Profile/Avatar.swift")],
                               evidence: [unit(passed: false)], fixRounds: 2)
        #expect(gate.evaluate(change).decision == .block)
    }

    @Test func rerunningUntilGreenStillCountsTheFailure() {
        let change = ChangeSet(id: "x", title: "", headCommit: head,
                               files: [ChangedFile("Sources/Profile/Avatar.swift")],
                               evidence: [unit(), unit(passed: false), unit()])
        let v = gate.evaluate(change)
        #expect(v.decision == .block)
        #expect(v.findings == [.failingEvidence(item: "baseline", name: "AppTests")])
    }

    @Test func anOldFailureDoesNotCountAgainstTheHeadCommit() {
        let change = ChangeSet(id: "x", title: "", headCommit: head,
                               files: [ChangedFile("Sources/Profile/Avatar.swift")],
                               evidence: [unit("0ld0ld0", passed: false), unit()])
        #expect(gate.evaluate(change).decision == .pass)
    }

    @Test func editingChecksWhileStillFailingGoesBackToTheAgentFirst() {
        let change = ChangeSet(id: "x", title: "", headCommit: head, files: [
            ChangedFile("Sources/Profile/Avatar.swift"), ChangedFile("Tests/ProfileTests/AvatarTests.swift"),
        ], evidence: [unit(passed: false)], fixRounds: 1)
        let v = gate.evaluate(change)
        #expect(v.decision == .block)
        #expect(v.findings == [.failingEvidence(item: "baseline", name: "AppTests"),
                               .modifiesOwnChecks(["Tests/ProfileTests/AvatarTests.swift"])])
    }

    @Test func deletingATestWithoutAReasonBlocks() {
        let change = ChangeSet(id: "x", title: "", headCommit: head,
                               files: [ChangedFile("Tests/ProfileTests/AvatarTests.swift", .deleted)],
                               deletionReasons: ["Tests/ProfileTests/AvatarTests.swift": "   "])
        let v = gate.evaluate(change)
        #expect(v.decision == .block)
        #expect(v.findings == [.deletedCheckWithoutReason("Tests/ProfileTests/AvatarTests.swift")])
    }

    @Test func emptyChangeBlocks() {
        #expect(gate.evaluate(ChangeSet(id: "x", title: "", headCommit: head, files: [])).decision == .block)
    }

    @Test func trustingAgentReportsIsAPolicyChoice() {
        var policy = SampleWeek.policy()
        policy.trustedProducers.insert(.agent)
        let change = ChangeSet(id: "x", title: "", headCommit: head,
                               files: [ChangedFile("Sources/Profile/Avatar.swift")],
                               evidence: [unit(producer: .agent)])
        #expect(EvidenceGate(policy: policy).evaluate(change).decision == .pass)
        #expect(gate.evaluate(change).decision == .block)
    }

    @Test("Property case minimum is inclusive", arguments: [(1_000, Decision.pass), (999, .block)])
    func propertyBoundary(cases: Int, expected: Decision) {
        let change = ChangeSet(id: "x", title: "", headCommit: head,
                               files: [ChangedFile("Sources/Networking/RetryPolicy.swift")],
                               evidence: [unit(), Evidence(kind: .property, name: "retry-idempotent",
                                                           commit: head, passed: true, cases: cases)])
        #expect(gate.evaluate(change).decision == expected)
    }

    @Test func aRedRunNothingRequiredStillBlocks() {
        let change = ChangeSet(id: "x", title: "", headCommit: head,
                               files: [ChangedFile("Sources/Settings/SettingsView.swift")],
                               evidence: [unit(), Evidence(kind: .endToEnd, name: "checkout-flow",
                                                           commit: head, passed: false)])
        let v = gate.evaluate(change)
        #expect(v.decision == .block)
        #expect(v.findings == [.failingEvidence(item: "not required", name: "checkout-flow")])
    }

    @Test func missingEvidenceAfterTheRoundLimitEscalates() {
        let change = ChangeSet(id: "x", title: "", headCommit: head,
                               files: [ChangedFile("Sources/Profile/Avatar.swift")], fixRounds: 3)
        let v = gate.evaluate(change)
        #expect(v.decision == .needsHuman)
        #expect(v.findings.last == .stillBlockedAfterRounds(3))
    }

    @Test("Sensitive paths always go to a person", arguments: [
        "App/App.entitlements", "App/Info.plist", "App/PrivacyInfo.xcprivacy",
        "App.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved", "Sources/Auth/Token.swift",
    ])
    func sensitivePath(path: String) {
        let change = ChangeSet(id: "x", title: "", headCommit: head, files: [ChangedFile(path)], evidence: [unit()])
        let v = gate.evaluate(change)
        #expect(v.decision == .needsHuman)
        #expect(v.findings == [.sensitivePath([path])])
    }

    @Test("Files that decide which checks run are protected", arguments: [
        "Demo.xcodeproj/xcshareddata/xcschemes/Demo.xcscheme", "Demo.xcodeproj/project.pbxproj",
        "Package.swift", "Scripts/run-ui-tests.sh", ".claude/settings.json", ".claude/hooks/record-evidence.sh",
        ".github/CODEOWNERS", "Config/Debug.xcconfig", "ShopTests/CheckoutTests.swift", "ShopUITests/FlowTests.swift",
        "ci_scripts/ci_post_clone.sh", "fastlane/Fastfile", "Packages/Core/Package.swift", "Packages/Core/Tests/CoreTests/A.swift",
    ])
    func checkControlFilesAreProtected(path: String) {
        let change = ChangeSet(id: "x", title: "", headCommit: head,
                               files: [ChangedFile("Sources/Profile/Avatar.swift"), ChangedFile(path)],
                               evidence: [unit()])
        let v = gate.evaluate(change)
        #expect(v.decision == .needsHuman)
        #expect(v.findings == [.modifiesOwnChecks([path])])
    }

    @Test func anUnexplainedDeletionAfterTheRoundLimitEscalates() {
        let change = ChangeSet(id: "x", title: "", headCommit: head,
                               files: [ChangedFile("Tests/ProfileTests/AvatarTests.swift", .deleted)], fixRounds: 3)
        let v = gate.evaluate(change)
        #expect(v.decision == .needsHuman)
        #expect(v.findings == [.deletedCheckWithoutReason("Tests/ProfileTests/AvatarTests.swift"),
                               .stillBlockedAfterRounds(3)])
    }

    @Test func deletionWithNoReasonEntryBlocks() {
        let change = ChangeSet(id: "x", title: "", headCommit: head,
                               files: [ChangedFile("Tests/ProfileTests/AvatarTests.swift", .deleted)])
        #expect(gate.evaluate(change).decision == .block)
    }

    @Test func reasonKeyedByTheRawPathCounts() {
        let raw = "./Tests/ProfileTests/AvatarTests.swift"
        let change = ChangeSet(id: "x", title: "", headCommit: head, files: [ChangedFile(raw, .deleted)],
                               deletionReasons: [raw: "Duplicates AvatarFlowTests."])
        #expect(gate.evaluate(change).decision == .needsHuman)
    }

    @Test func roundLimitHasAFloorOfOne() {
        let policy = GatePolicy(protectedChecks: [], maxFixRounds: 0)
        #expect(policy.maxFixRounds == 1)
    }
}

@Suite("Evidence report")
struct EvidenceReportTests {
    @Test func proseIsKeptButNotCounted() {
        let text = """
        {"kind":"unit","name":"AppTests","commit":"abc1234","passed":true,"producer":"ci"}
        All tests pass! I also checked checkout manually.

        {"kind":"property","name":"p","commit":"abc1234","passed":true,"cases":-5,"producer":"ci"}
        {"kind":"property","name":"","commit":"abc1234","passed":true,"producer":"ci"}
        """
        let report = EvidenceReport.parse(jsonLines: text)
        #expect(report.evidence == [Evidence(kind: .unit, name: "AppTests", commit: "abc1234", passed: true)])
        #expect(report.unparsedLines.count == 3)
        #expect(report.unparsedLines.first == "All tests pass! I also checked checkout manually.")
    }
}

@Suite("Prompt")
struct PromptTests {
    @Test func promptIsRenderedFromThePolicy() {
        let prompt = PromptRenderer.instructions(policy: SampleWeek.policy(),
                                                 plannedPaths: ["Sources/Checkout/PlaceOrderButton.swift"])
        #expect(prompt.contains("**/*Tests/**, **/__Snapshots__/**, **/*.xctestplan, **/*.xcscheme, **/project.pbxproj, **/*.xcconfig, **/Package.swift, **/CODEOWNERS, .github/workflows/**, Scripts/**, ci_scripts/**, fastlane/**, .claude/**, .gate/**"))
        #expect(prompt.contains("These paths always go to a person, however complete the evidence: **/*.entitlements"))
        #expect(prompt.contains("as part of this change"))
        #expect(prompt.contains("You may add a new test there"))
        #expect(prompt.contains("add the property test that would have caught it as a new test"))
        #expect(prompt.contains("- baseline: unit (any)"))
        #expect(prompt.contains("- REL-02 Checkout still completes end to end: end-to-end \"checkout-flow\"; simulator run (any)"))
        #expect(!prompt.contains("REL-01"))
        #expect(prompt.contains("still blocked after 3 fix rounds"))
        #expect(prompt.contains("recorded by ci or hook"))
    }

    @Test func promptForATestOnlyChangeHasNoEvidenceList() {
        let prompt = PromptRenderer.instructions(policy: SampleWeek.policy(),
                                                 plannedPaths: ["Tests/A.swift"])
        #expect(!prompt.contains("- baseline"))
        #expect(!prompt.contains("Evidence this change needs"))
        #expect(prompt.contains("This change touches only checks; the check owner reviews it."))
    }
}

@Suite("Git name-status")
struct GitNameStatusTests {
    @Test func parsesEveryStatus() {
        let output = "M\tSources/A.swift\nA\tSources/B.swift\nD\tTests/CTests.swift\nR087\tTests/D.swift\tSources/D.swift\nC100\tSources/E.swift\tSources/F.swift\nT\tScripts/g.sh\n"
        let change = ChangeSet.fromGitNameStatus(output, id: "x", title: "", headCommit: head)
        #expect(change.files == [
            ChangedFile("Sources/A.swift", .modified),
            ChangedFile("Sources/B.swift", .added),
            ChangedFile("Tests/CTests.swift", .deleted),
            ChangedFile("Sources/D.swift", .renamed(from: "Tests/D.swift")),
            ChangedFile("Sources/F.swift", .added),
            ChangedFile("Scripts/g.sh", .modified),
        ])
    }

    @Test("Quoted or empty fields fail closed", arguments: [
        "A\t\"Tests/caf\\303\\251.swift\"",
        "A\t\".github/workflows/\\303\\251vil.yml\"",
        "\tSources/A.swift",
        "M\t",
    ])
    func quotedPathsFailClosed(line: String) {
        let change = ChangeSet.fromGitNameStatus(line, id: "x", title: "", headCommit: head, evidence: [unit()])
        #expect(change.files == [ChangedFile("/unparsed: " + line)])
        #expect(gate.evaluate(change).decision == .block)
    }

    @Test func anUnreadableLineBecomesAnInvalidPathInsteadOfVanishing() {
        let change = ChangeSet.fromGitNameStatus("X\tweird", id: "x", title: "", headCommit: head, evidence: [unit()])
        let v = gate.evaluate(change)
        #expect(v.decision == .block)
        #expect(v.findings.first == .invalidPath("/unparsed: X\tweird"))
        #expect(v.findings.first?.message == "Couldn't read this git line, so the gate fails closed: X\tweird")
    }
}
