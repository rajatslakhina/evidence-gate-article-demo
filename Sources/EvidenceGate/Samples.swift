/// A constructed week of agent changes on a made-up shopping app.
/// The policy, paths and commits are illustrative, not from a real codebase.
/// Commits are short SHAs for readability; record full SHAs in CI.
public enum SampleWeek {
    public static let propertyMinimum = 1_000

    public static func policy(mode: GateMode = .enforce) -> GatePolicy {
        GatePolicy(
            protectedChecks: [
                PathPattern("**/*Tests/**"),
                PathPattern("**/__Snapshots__/**"),
                PathPattern("**/*.xctestplan"),
                PathPattern("**/*.xcscheme"),
                PathPattern("**/project.pbxproj"),
                PathPattern("**/*.xcconfig"),
                PathPattern("**/Package.swift"),
                PathPattern("**/Package@swift-*.swift"),
                PathPattern("**/CODEOWNERS"),
                PathPattern(".github/workflows/**"),
                PathPattern("Scripts/**"),
                PathPattern("ci_scripts/**"),
                PathPattern("fastlane/**"),
                PathPattern(".claude/**"),
                PathPattern(".gate/**"),
            ],
            sensitivePaths: [
                PathPattern("**/*.entitlements"),
                PathPattern("**/Info.plist"),
                PathPattern("**/PrivacyInfo.xcprivacy"),
                PathPattern("**/Package.resolved"),
                PathPattern("Sources/Auth/**"),
            ],
            baseline: [EvidenceRequirement(.unit)],
            checklist: [
                ChecklistItem(
                    id: "REL-01",
                    title: "Old stores still open after a schema change",
                    triggers: [PathPattern("Sources/Persistence/**")],
                    requires: [
                        EvidenceRequirement(.differential, name: "store-migration"),
                        EvidenceRequirement(.property, name: "order-round-trip",
                                            minimumCases: propertyMinimum),
                    ],
                    origin: "Illustrative: a launch crash for users upgrading with an older store"),
                ChecklistItem(
                    id: "REL-02",
                    title: "Checkout still completes end to end",
                    triggers: [PathPattern("Sources/Checkout/**")],
                    requires: [
                        EvidenceRequirement(.endToEnd, name: "checkout-flow"),
                        EvidenceRequirement(.simulatorRun),
                    ],
                    origin: "Illustrative: a Place Order button that stayed disabled"),
                ChecklistItem(
                    id: "REL-03",
                    title: "Retries stay idempotent",
                    triggers: [PathPattern("Sources/Networking/**")],
                    requires: [
                        EvidenceRequirement(.property, name: "retry-idempotent",
                                            minimumCases: propertyMinimum),
                    ],
                    origin: "Illustrative: a double charge after a retried request"),
            ],
            mode: mode)
    }

    public static let changes: [ChangeSet] = [
        ChangeSet(
            id: "CHK-101", title: "Fix disabled Place Order button", headCommit: "a41c9e2",
            files: [ChangedFile("Sources/Checkout/PlaceOrderButton.swift")],
            evidence: [
                Evidence(kind: .unit, name: "CheckoutTests", commit: "a41c9e2", passed: true),
                Evidence(kind: .endToEnd, name: "checkout-flow", commit: "a41c9e2", passed: true,
                         producer: .hook),
                Evidence(kind: .simulatorRun, name: "iPhone 17 Pro", commit: "a41c9e2", passed: true,
                         producer: .hook),
            ]),
        ChangeSet(
            id: "CHK-102", title: "Same fix, and the agent \"fixed\" the flow test", headCommit: "b7d0f13",
            files: [
                ChangedFile("Sources/Checkout/PlaceOrderButton.swift"),
                ChangedFile("UITests/CheckoutFlowTests.swift"),
            ],
            evidence: [
                Evidence(kind: .unit, name: "CheckoutTests", commit: "b7d0f13", passed: true),
                Evidence(kind: .endToEnd, name: "checkout-flow", commit: "b7d0f13", passed: true,
                         producer: .hook),
                Evidence(kind: .simulatorRun, name: "iPhone 17 Pro", commit: "b7d0f13", passed: true,
                         producer: .hook),
            ]),
        ChangeSet(
            id: "PER-201", title: "Add giftNote to the Order model", headCommit: "c22e8a0",
            files: [ChangedFile("Sources/Persistence/OrderSchema.swift")],
            evidence: [
                Evidence(kind: .unit, name: "PersistenceTests", commit: "c22e8a0", passed: true),
            ]),
        ChangeSet(
            id: "PER-202", title: "Add giftNote, with migration evidence", headCommit: "d903b5c",
            files: [ChangedFile("Sources/Persistence/OrderSchema.swift")],
            evidence: [
                Evidence(kind: .unit, name: "PersistenceTests", commit: "d903b5c", passed: true),
                Evidence(kind: .differential, name: "store-migration", commit: "d903b5c", passed: true),
                Evidence(kind: .property, name: "order-round-trip", commit: "d903b5c", passed: true,
                         cases: 2_000),
            ]),
        ChangeSet(
            id: "NET-301", title: "Retry on HTTP 429", headCommit: "e15f7d4",
            files: [ChangedFile("Sources/Networking/RetryPolicy.swift")],
            evidence: [
                Evidence(kind: .unit, name: "NetworkingTests", commit: "e15f7d4", passed: true),
                Evidence(kind: .property, name: "retry-idempotent", commit: "e15f7d4", passed: true,
                         cases: 50),
            ]),
        ChangeSet(
            id: "SET-401", title: "Rename the Sign Out label", headCommit: "f6a2c71",
            files: [ChangedFile("Sources/Settings/SettingsView.swift")],
            evidence: [
                Evidence(kind: .unit, name: "SettingsTests", commit: "9e0b4d8", passed: true),
                Evidence(kind: .unit, name: "SettingsTests", commit: "f6a2c71", passed: true,
                         producer: .agent),
            ]),
        ChangeSet(
            id: "FLK-501", title: "Delete a flaky sign-out snapshot test", headCommit: "0b8e3f9",
            files: [ChangedFile("Tests/SettingsTests/SignOutSnapshotTests.swift", .deleted)],
            deletionReasons: [
                "Tests/SettingsTests/SignOutSnapshotTests.swift":
                    "Fails about 1 run in 8 on CI only. Root cause not found in 3 rounds; the sign-out flow test covers the screen.",
            ]),
        ChangeSet(
            id: "CHK-103", title: "Show the Apple Pay sheet from checkout", headCommit: "1c4d9a6",
            files: [ChangedFile("Sources/Checkout/ApplePaySheet.swift", .added)],
            evidence: [
                Evidence(kind: .unit, name: "CheckoutTests", commit: "1c4d9a6", passed: true),
                Evidence(kind: .endToEnd, name: "checkout-flow", commit: "1c4d9a6", passed: false,
                         producer: .hook),
                Evidence(kind: .simulatorRun, name: "iPhone 17 Pro", commit: "1c4d9a6", passed: true,
                         producer: .hook),
            ],
            fixRounds: 3),
    ]

    public static func verdicts(mode: GateMode = .enforce) -> [Verdict] {
        let gate = EvidenceGate(policy: policy(mode: mode))
        return changes.map(gate.evaluate)
    }
}
