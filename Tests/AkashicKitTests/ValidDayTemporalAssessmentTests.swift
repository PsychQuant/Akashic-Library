import XCTest
@testable import AkashicCore

final class ValidDayTemporalAssessmentTests: XCTestCase {

    // 會抓到的 production break：parser 接受非 ASCII、非完整日或不存在的格里曆日。
    func testValidDayAcceptsOnlyRealASCIIGregorianFullDays() throws {
        XCTAssertEqual(try ValidDay("2000-02-29").rawValue, "2000-02-29")
        XCTAssertEqual(try ValidDay("2024-12-31").rawValue, "2024-12-31")

        let malformed = [
            "2024", "2024-02", "2024-2-01", "2024-02-1",
            "２０２４-０２-０１", "2024/02/01", "2024-02-01\n", " 2024-02-01",
            "10000-01-01",
        ]
        for raw in malformed {
            XCTAssertThrowsError(try ValidDay(raw), raw) { error in
                XCTAssertEqual(error as? ValidDayError, .invalidFormat)
            }
        }

        let nonexistent = [
            "0000-01-01", "1900-02-29", "2023-02-29", "2024-04-31", "2024-13-01",
        ]
        for raw in nonexistent {
            XCTAssertThrowsError(try ValidDay(raw), raw) { error in
                XCTAssertEqual(error as? ValidDayError, .invalidGregorianDay)
            }
        }
    }

    // 會抓到的 production break：比較器未按年月日排序，或型別失去值語意／Sendable。
    func testValidDayHasStableValueSemanticsAndChronologicalTotalOrder() throws {
        let early = try ValidDay("1999-12-31")
        let leap = try ValidDay("2000-02-29")
        let late = try ValidDay("2024-01-01")

        XCTAssertEqual([late, early, leap].sorted(), [early, leap, late])
        XCTAssertEqual(Set([early, early, leap]).count, 2)
        requireComparableHashableSendable(early)
    }

    // 會抓到的 production break：bounded endpoint 不是 inclusive，或區間外被誤報成立。
    func testExactBoundedRangeIsInclusiveAndDefinitelyExcludesOutsideDays() throws {
        let range = DateRange(start: "2020-01-01", end: "2020-12-31")

        XCTAssertEqual(range.assess(at: try day("2020-01-01")), .definitelyContains)
        XCTAssertEqual(range.assess(at: try day("2020-06-15")), .definitelyContains)
        XCTAssertEqual(range.assess(at: try day("2020-12-31")), .definitelyContains)
        XCTAssertEqual(range.assess(at: try day("2019-12-31")), .definitelyExcludes)
        XCTAssertEqual(range.assess(at: try day("2021-01-01")), .definitelyExcludes)
    }

    // 會抓到的 production break：粗精度 start 被偷補成月初／年初，或過了最晚可能
    // start 仍沒有轉成 definite containment。
    func testCoarseStartUsesItsCompletePossibleDayInterval() throws {
        let monthStart = DateRange(start: "2020-06")
        XCTAssertEqual(monthStart.assess(at: try day("2020-05-31")), .definitelyExcludes)
        XCTAssertEqual(
            monthStart.assess(at: try day("2020-06-15")),
            .indeterminate(.impreciseStart))
        XCTAssertEqual(monthStart.assess(at: try day("2020-07-01")), .definitelyContains)

        let yearStart = DateRange(start: "2020")
        XCTAssertEqual(
            yearStart.assess(at: try day("2020-07-01")),
            .indeterminate(.impreciseStart))
        XCTAssertEqual(yearStart.assess(at: try day("2021-01-01")), .definitelyContains)
    }

    // 會抓到的 production break：粗精度 end 被偷補成月末／年末，或已過最晚可能
    // end 仍被當成包含。
    func testCoarseEndUsesItsCompletePossibleDayInterval() throws {
        let monthEnd = DateRange(start: "2020-01-01", end: "2020-06")
        XCTAssertEqual(monthEnd.assess(at: try day("2020-05-31")), .definitelyContains)
        XCTAssertEqual(
            monthEnd.assess(at: try day("2020-06-15")),
            .indeterminate(.impreciseEnd))
        XCTAssertEqual(monthEnd.assess(at: try day("2020-07-01")), .definitelyExcludes)

        let yearEnd = DateRange(start: "2019-01-01", end: "2020")
        XCTAssertEqual(
            yearEnd.assess(at: try day("2020-07-01")),
            .indeterminate(.impreciseEnd))
        XCTAssertEqual(yearEnd.assess(at: try day("2021-01-01")), .definitelyExcludes)
    }

    // 會抓到的 production break：start precision 的 uncertainty 遮蔽了已由 end 建立的
    // definite exclusion。兩個端點都合法且不必然矛盾時，仍須先採可證明的排除。
    func testDefiniteEndExclusionPrecedesCoarseStartIndeterminacy() throws {
        let range = DateRange(start: "2020-12", end: "2020-12-15")
        XCTAssertEqual(range.assess(at: try day("2020-12-20")), .definitelyExcludes)
    }

    // 會抓到的 production break：粗精度 start 納入了不可能晚於 exact end 的日期，
    // 因而把所有一致端點配對都包含的 query 誤降格成 impreciseStart。
    func testExactEndConditionsOverlappingCoarseStartPossibilities() throws {
        let range = DateRange(start: "2020-12", end: "2020-12-15")
        XCTAssertEqual(range.assess(at: try day("2020-12-15")), .definitelyContains)
    }

    // 會抓到的 production break：粗精度 end 納入了不可能早於 exact start 的日期，
    // 因而把所有一致端點配對都包含的 query 誤降格成 impreciseEnd。
    func testExactStartConditionsOverlappingCoarseEndPossibilities() throws {
        let range = DateRange(start: "2020-12-15", end: "2020-12")
        XCTAssertEqual(range.assess(at: try day("2020-12-15")), .definitelyContains)
    }

    // 會抓到的 production break：真正 open end 沒延續，或缺席 start 被當成負無限。
    func testOpenEndContinuesButUnknownStartDoesNotBecomeNegativeInfinity() throws {
        let open = DateRange(start: "2020-06-15")
        XCTAssertEqual(open.assess(at: try day("2020-06-14")), .definitelyExcludes)
        XCTAssertEqual(open.assess(at: try day("2020-06-15")), .definitelyContains)
        XCTAssertEqual(open.assess(at: try day("2030-01-01")), .definitelyContains)

        let unknownStart = DateRange(end: "2020-12-31")
        XCTAssertEqual(
            unknownStart.assess(at: try day("2020-06-15")),
            .indeterminate(.unknownStart))
        XCTAssertEqual(unknownStart.assess(at: try day("2021-01-01")), .definitelyExcludes)
        XCTAssertEqual(
            DateRange().assess(at: try day("2020-06-15")),
            .indeterminate(.unknownStart))
    }

    // 會抓到的 production break：endedUnknown 被當成正無限，或連精確 start day 也
    // 無法由 inclusive start 建立。
    func testEndedUnknownContainsOnlyItsExactKnownStartDayAndOtherwiseStaysUnknown() throws {
        let exactStart = DateRange(start: "2020-06-15", endedUnknown: true)
        XCTAssertEqual(exactStart.assess(at: try day("2020-06-14")), .definitelyExcludes)
        XCTAssertEqual(exactStart.assess(at: try day("2020-06-15")), .definitelyContains)
        XCTAssertEqual(
            exactStart.assess(at: try day("2020-06-16")),
            .indeterminate(.unknownEnd))

        let coarseStart = DateRange(start: "2020-06", endedUnknown: true)
        XCTAssertEqual(
            coarseStart.assess(at: try day("2020-06-15")),
            .indeterminate(.impreciseStart))
        XCTAssertEqual(
            coarseStart.assess(at: try day("2020-07-01")),
            .indeterminate(.unknownEnd))
        XCTAssertEqual(
            DateRange(endedUnknown: true).assess(at: try day("2020-06-15")),
            .indeterminate(.unknownStart))
    }

    // 會抓到的 production break：單點 observation 被延伸成區間，或粗精度 observation
    // 被擅自猜成精確日期。
    func testAttestedOnlyEstablishesExactObservedDaysWithoutRangeExtension() throws {
        let exact = DateRange(attested: ["2020-06-15", "2021-01-01"])
        XCTAssertEqual(exact.assess(at: try day("2020-06-15")), .definitelyContains)
        XCTAssertEqual(exact.assess(at: try day("2020-06-16")), .definitelyExcludes)

        let coarse = DateRange(attested: ["2020-06"])
        XCTAssertEqual(
            coarse.assess(at: try day("2020-06-15")),
            .indeterminate(.impreciseAttestation))
        XCTAssertEqual(coarse.assess(at: try day("2020-07-01")), .definitelyExcludes)

        let exactOverridesCompatibleCoarse = DateRange(attested: ["2020-06", "2020-06-15"])
        XCTAssertEqual(
            exactOverridesCompatibleCoarse.assess(at: try day("2020-06-15")),
            .definitelyContains)
    }

    // 會抓到的 production break：矛盾 shape 或 malformed endpoint 被降格成 epistemic
    // uncertainty，而不是結構化 invalid evidence。
    func testContradictoryAndMalformedRangesFailClosedWithNamedReasons() throws {
        let query = try day("2020-06-15")

        for mixed in [
            DateRange(start: "2020", attested: ["2020-06-15"]),
            DateRange(end: "2020", attested: ["2020-06-15"]),
            DateRange(endedUnknown: true, attested: ["2020-06-15"]),
        ] {
            XCTAssertEqual(
                mixed.assess(at: query),
                .invalidEvidence(.mixedAttestationAndRange))
        }

        XCTAssertEqual(
            DateRange(start: "2020", end: "2021", endedUnknown: true).assess(at: query),
            .invalidEvidence(.endAndEndedUnknown))
        XCTAssertEqual(
            DateRange(start: "2020-13").assess(at: query),
            .invalidEvidence(.malformedStart))
        XCTAssertEqual(
            DateRange(start: "2020", end: "2020-02-30").assess(at: query),
            .invalidEvidence(.malformedEnd))
        XCTAssertEqual(
            DateRange(attested: ["not-a-date"]).assess(at: query),
            .invalidEvidence(.malformedAttestation))
        XCTAssertEqual(
            DateRange(start: "2021", end: "2020").assess(at: query),
            .invalidEvidence(.endBeforeStart))
        XCTAssertEqual(
            DateRange(start: "2020-12", end: "2020-01").assess(at: query),
            .invalidEvidence(.endBeforeStart))
    }

    // 會抓到的 production break：公開結果理由失去 typed value semantics，迫使 trace
    // 退回字串判定。
    func testTemporalAssessmentTypesHaveHashableSendableValueSemantics() {
        requireComparableHashableSendable(DateRange())
        requireHashableSendable(TemporalIndeterminacyReason.unknownStart)
        requireHashableSendable(TemporalInvalidEvidenceReason.endBeforeStart)
        requireHashableSendable(
            TemporalContainment.indeterminate(.impreciseAttestation))
    }

    private func day(_ raw: String) throws -> ValidDay { try ValidDay(raw) }

    private func requireComparableHashableSendable<T: Comparable & Hashable & Sendable>(_: T) {}
    private func requireHashableSendable<T: Hashable & Sendable>(_: T) {}
}
