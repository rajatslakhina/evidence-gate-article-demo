import Testing
@testable import EvidenceGate

private func verdict(_ id: String, mode: GateMode = .enforce) throws -> Verdict {
    try #require(SampleWeek.verdicts(mode: mode).first { $0.changeID == id })
}

@Suite("Sample week")
struct SampleWeekTests {
    @Test("Each change gets the decision the article describes", arguments: [
        ("CHK-101", Decision.pass),
        ("CHK-102", .needsHuman),
        ("PER-201", .block),
        ("PER-202", .pass),
        ("NET-301", .block),
        ("SET-401", .block),
        ("FLK-501", .needsHuman),
        ("CHK-103", .needsHuman),
    ])
    func decision(id: String, expected: Decision) throws {
        #expect(try verdict(id).decision == expected)
    }

    @Test func weekTotals() {
        let v = SampleWeek.verdicts()
        #expect(v.count == 8)
        #expect(v.filter { $0.decision == .pass }.count == 2)
        #expect(v.filter { $0.decision == .block }.count == 3)
        #expect(v.filter { $0.decision == .needsHuman }.count == 3)
    }

    @Test func editingTheFlowTestGoesToAPersonEvenWithGreenEvidence() throws {
        let v = try verdict("CHK-102")
        #expect(v.findings == [.modifiesOwnChecks(["UITests/CheckoutFlowTests.swift"])])
        #expect(v.decision == .needsHuman)
        #expect(v.triggeredItems == ["REL-02"])
    }

    @Test func schemaChangeNeedsMigrationEvidence() throws {
        let v = try verdict("PER-201")
        #expect(v.triggeredItems == ["REL-01"])
        #expect(v.findings.contains(.missingEvidence(
            item: "REL-01", requirement: EvidenceRequirement(.differential, name: "store-migration"))))
        #expect(v.findings.contains { if case .missingEvidence(item: "REL-01", _) = $0 { true } else { false } })
        #expect(v.findings.count == 2)
    }

    @Test func fiftyPropertyCasesIsNotEnough() throws {
        let v = try verdict("NET-301")
        #expect(v.findings == [.insufficientCases(item: "REL-03", name: "retry-idempotent",
                                                  ran: 50, required: SampleWeek.propertyMinimum)])
    }

    @Test func staleAndSelfReportedEvidenceDontCount() throws {
        let v = try verdict("SET-401")
        #expect(v.findings.first == .missingEvidence(item: "baseline", requirement: EvidenceRequirement(.unit)))
        #expect(v.findings.contains(.staleEvidence(name: "SettingsTests", commit: "9e0b4d8")))
        #expect(v.findings.contains(.untrustedEvidence(name: "SettingsTests", producer: .agent)))
        #expect(v.stamp == "verified-by: none")
    }

    @Test func deletingAFlakyTestWithAReasonGoesToTheOwner() throws {
        let v = try verdict("FLK-501")
        #expect(v.findings == [.checkChangeNeedsOwner(["Tests/SettingsTests/SignOutSnapshotTests.swift"])])
    }

    @Test func threeFailedRoundsEscalate() throws {
        let v = try verdict("CHK-103")
        #expect(v.findings == [.failingEvidence(item: "REL-02", name: "checkout-flow"),
                               .stillFailingAfterRounds(3)])
    }

    @Test func passingChangesCarryAStamp() throws {
        #expect(try verdict("CHK-101").stamp
                == "verified-by: endToEnd(checkout-flow), simulatorRun(iPhone 17 Pro), unit(CheckoutTests)")
        #expect(try verdict("PER-202").stamp
                == "verified-by: differential(store-migration), property(order-round-trip), unit(PersistenceTests)")
    }

    @Test func observeModeLetsEverythingThroughButRecordsIt() {
        let observed = SampleWeek.verdicts(mode: .observe)
        let enforced = SampleWeek.verdicts(mode: .enforce)
        #expect(observed.allSatisfy { $0.enforced == .pass })
        #expect(observed.filter(\.wouldHaveBlocked).count == 3)
        #expect(observed.filter(\.wouldHaveEscalated).count == 3)
        #expect(zip(observed, enforced).allSatisfy { $0.decision == $1.decision })
    }

    @Test func offModeDoesNotRun() {
        let off = SampleWeek.verdicts(mode: .off)
        #expect(off.allSatisfy { $0.decision == .pass && $0.findings.isEmpty && $0.stamp == "verified-by: none" })
    }
}
