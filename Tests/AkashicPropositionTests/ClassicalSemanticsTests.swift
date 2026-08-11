import Foundation
import XCTest
import AkashicCore
@testable import AkashicProposition

/// #214 classical 層的承重契約。
///
/// 這些測試刻意只處理完整二值賦值；store-bound 的三值知識狀態由
/// `SupervaluationTests` 負責。每個 locator 都對應 design 的 mutation matrix，
/// 不能以 structural equality、缺值預設或 caller 可調上限替代。
final class ClassicalSemanticsTests: XCTestCase {
    private var p: Proposition { atom("p") }
    private var q: Proposition { atom("q") }

    private func atom(_ label: String) -> Proposition {
        .authored(
            person: .key("person-\(label)"),
            work: .key("work-\(label)")
        )
    }

    private func numberedAtoms(_ count: Int) -> [Proposition] {
        (0..<count).map { atom(String(format: "%02d", $0)) }
    }

    private func expression(_ proposition: Proposition) throws -> PropositionExpression {
        try PropositionExpression.atom(proposition)
    }

    /// 建立低深度的 conjunction tree，使 63-atom fixture 只測列舉界線，
    /// 不會先撞到 expression depth 或 node budget。
    private func balancedAnd(_ propositions: [Proposition]) throws -> PropositionExpression {
        precondition(!propositions.isEmpty)
        var level = try propositions.map { try expression($0) }

        while level.count > 1 {
            var next: [PropositionExpression] = []
            next.reserveCapacity((level.count + 1) / 2)
            var index = 0
            while index < level.count {
                if index + 1 < level.count {
                    next.append(try PropositionExpression.and(level[index], level[index + 1]))
                } else {
                    next.append(level[index])
                }
                index += 2
            }
            level = next
        }

        return level[0]
    }

    private var productsDirectory: URL {
        for bundle in Bundle.allBundles where bundle.bundlePath.hasSuffix(".xctest") {
            return bundle.bundleURL.deletingLastPathComponent()
        }
        fatalError("找不到 SwiftPM products directory")
    }

    private func externalTypecheck(
        _ source: String
    ) throws -> (status: Int32, output: String) {
        let fileManager = FileManager.default
        let scratchRoot = URL(
            fileURLWithPath: "/tmp/akashic-214-red-classical",
            isDirectory: true
        )
        try fileManager.createDirectory(
            at: scratchRoot,
            withIntermediateDirectories: true
        )
        let directory = scratchRoot.appendingPathComponent(UUID().uuidString)
        try fileManager.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        defer { try? fileManager.removeItem(at: directory) }

        let sourceURL = directory.appendingPathComponent("Probe.swift")
        try source.write(to: sourceURL, atomically: true, encoding: .utf8)

        let modules = productsDirectory.appendingPathComponent("Modules")
        let buildRoot = productsDirectory
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let cyamlInclude = buildRoot
            .appendingPathComponent("checkouts/Yams/Sources/CYaml/include")
        let cyamlModuleMap = cyamlInclude.appendingPathComponent("module.modulemap")
        XCTAssertTrue(
            fileManager.fileExists(atPath: modules.path),
            "external probe 找不到 SwiftPM Modules：\(modules.path)"
        )
        XCTAssertTrue(
            fileManager.fileExists(atPath: cyamlModuleMap.path),
            "external probe 找不到 CYaml module map：\(cyamlModuleMap.path)"
        )

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
        process.arguments = [
            "swiftc",
            "-typecheck",
            "-warnings-as-errors",
            "-I", modules.path,
            "-Xcc", "-fmodule-map-file=\(cyamlModuleMap.path)",
            "-Xcc", "-I",
            "-Xcc", cyamlInclude.path,
            sourceURL.path,
        ]
        process.environment = ProcessInfo.processInfo.environment
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        try process.run()
        let output = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return (process.terminationStatus, String(decoding: output, as: UTF8.self))
    }

    // Production mutation caught: missing lookup defaults to false or missing payload is not canonical.
    func testClassicalEvaluationRequiresCompleteBivalentAssignment() throws {
        let pExpression = try expression(p)
        let qExpression = try expression(q)
        let compound = try PropositionExpression.and(
            qExpression,
            try PropositionExpression.not(pExpression)
        )
        let complete = try ClassicalValuation(assignments: [
            (atom: q, value: true),
            (atom: p, value: false),
        ])

        XCTAssertTrue(try compound.classicalValue(under: complete))

        let reversed = try PropositionExpression.and(qExpression, pExpression)
        let empty = try ClassicalValuation(assignments: [])
        XCTAssertThrowsError(try reversed.classicalValue(under: empty)) { error in
            XCTAssertEqual(
                error as? ClassicalSemanticsError,
                .incompleteValuation(missing: [p, q]),
                "missing payload 必須依 canonical atom order 回報，且不可把缺值當 false"
            )
        }
    }

    // Production mutation caught: another operator is copied over one matrix or one cell is inverted.
    func testEveryBinaryOperatorHasCompleteFourRowMatrix() throws {
        let pExpression = try expression(p)
        let qExpression = try expression(q)
        let expectedInputs = [
            [false, false],
            [false, true],
            [true, false],
            [true, true],
        ]
        let operators: [
            (name: String, expression: PropositionExpression, outputs: [Bool])
        ] = [
            ("and", try .and(pExpression, qExpression), [false, false, false, true]),
            ("or", try .or(pExpression, qExpression), [false, true, true, true]),
            ("implies", try .implies(pExpression, qExpression), [true, true, false, true]),
            ("nor", try .nor(pExpression, qExpression), [true, false, false, false]),
        ]

        for fixture in operators {
            let table = try fixture.expression.truthTable()
            XCTAssertEqual(table.atoms, [p, q], fixture.name)
            XCTAssertEqual(table.rows.map(\.inputs), expectedInputs, fixture.name)
            XCTAssertEqual(table.rows.map(\.output), fixture.outputs, fixture.name)
        }

        let notTable = try PropositionExpression.not(pExpression).truthTable()
        XCTAssertEqual(notTable.rows.map(\.inputs), [[false], [true]])
        XCTAssertEqual(notTable.rows.map(\.output), [true, false])
    }

    // Production mutation caught: validation occurs after indexing, duplicates become first/last wins,
    // or a public raw-Proposition dictionary initializer is introduced.
    func testClassicalValuationEntryListValidatesBeforeIndexing() throws {
        let malformed = Proposition.authored(
            person: .key("Not A Key"),
            work: .key("work-valid")
        )
        let oversizedMalformed = Array(
            repeating: (atom: malformed, value: true),
            count: 64
        )

        XCTAssertThrowsError(
            try ClassicalValuation(assignments: oversizedMalformed)
        ) { error in
            XCTAssertEqual(
                error as? ClassicalSemanticsError,
                .valuationAtomLimitExceeded(actual: 64, maximum: 63),
                "entry count 必須在 malformed validation、duplicate comparison 與 indexing 之前"
            )
        }

        XCTAssertThrowsError(
            try ClassicalValuation(assignments: [(atom: malformed, value: true)])
        ) { error in
            XCTAssertEqual(error as? PropositionError, .malformedKey("Not A Key"))
        }

        XCTAssertThrowsError(
            try ClassicalValuation(assignments: [
                (atom: p, value: false),
                (atom: p, value: true),
            ])
        ) { error in
            XCTAssertEqual(
                error as? ClassicalSemanticsError,
                .duplicateValuationAtom(p)
            )
        }

        let acceptedEntryList = try externalTypecheck(
            """
            import AkashicProposition
            let atom = Proposition.authored(person: .key("person-p"), work: .key("work-p"))
            let entries: [(atom: Proposition, value: Bool)] = [(atom: atom, value: true)]
            _ = try ClassicalValuation(assignments: entries)
            """
        )
        XCTAssertEqual(acceptedEntryList.status, 0, acceptedEntryList.output)

        let refusedDictionary = try externalTypecheck(
            """
            import AkashicProposition
            let atom = Proposition.authored(person: .key("person-p"), work: .key("work-p"))
            let assignments: [Proposition: Bool] = [atom: true]
            _ = try ClassicalValuation(assignments: assignments)
            """
        )
        XCTAssertNotEqual(
            refusedDictionary.status,
            0,
            "public API 不得先要求 caller 對 raw Proposition 做 Dictionary hashing"
        )
        XCTAssertTrue(
            refusedDictionary.output.contains("ClassicalValuation")
                || refusedDictionary.output.contains("assignments"),
            refusedDictionary.output
        )
    }

    // Production mutation caught: duplicate comparison is interleaved with validation, allowing
    // an early duplicate to hide a later malformed atom after the container count guard passes.
    func testClassicalValuationValidatesEveryAtomBeforeDuplicatePhase() throws {
        let malformed = Proposition.authored(
            person: .key("Not A Key"),
            work: .key("work-valid")
        )

        XCTAssertThrowsError(
            try ClassicalValuation(assignments: [
                (atom: p, value: false),
                (atom: p, value: true),
                (atom: malformed, value: true),
            ])
        ) { error in
            XCTAssertEqual(
                error as? PropositionError,
                .malformedKey("Not A Key"),
                "count guard 後須先驗證全部 atoms；early duplicate 不得遮蔽 later malformed"
            )
        }
    }

    // Production mutation caught: function-table duplicate rejection runs before every atom has
    // completed syntax validation and canonical-byte capture.
    func testBooleanFunctionTableValidatesEveryAtomBeforeDuplicatePhase() throws {
        let malformed = Proposition.authored(
            person: .key("Not A Key"),
            work: .key("work-valid")
        )

        XCTAssertThrowsError(
            try BooleanFunctionTable(
                atomsInInputBitOrder: [p, p, malformed],
                outputsInInputBitRowOrder: Array(repeating: false, count: 8)
            )
        ) { error in
            XCTAssertEqual(
                error as? PropositionError,
                .malformedKey("Not A Key"),
                "arity guard 後須先驗證全部 atoms；early duplicate 不得遮蔽 later malformed"
            )
        }
    }

    // Production mutation caught: extra values become an error or influence the result; limit is removed.
    func testClassicalValuationIgnoresExtraAssignmentsWithinFixedContainerLimit() throws {
        let atoms = numberedAtoms(64)
        let subject = try expression(atoms[0])
        let first = try ClassicalValuation(assignments: atoms.prefix(63).enumerated().map {
            (atom: $0.element, value: $0.offset == 0)
        })
        let second = try ClassicalValuation(assignments: atoms.prefix(63).enumerated().map {
            (atom: $0.element, value: $0.offset == 0 || $0.offset.isMultiple(of: 2))
        })

        XCTAssertTrue(try subject.classicalValue(under: first))
        XCTAssertTrue(try subject.classicalValue(under: second))

        XCTAssertThrowsError(
            try ClassicalValuation(assignments: atoms.map { (atom: $0, value: false) })
        ) { error in
            XCTAssertEqual(
                error as? ClassicalSemanticsError,
                .valuationAtomLimitExceeded(actual: 64, maximum: 63)
            )
        }
    }

    // Production mutation caught: atom iteration is unstable or assignment bit significance is reversed.
    func testTruthTableAtomAndRowOrderIsDeterministic() throws {
        let expression = try PropositionExpression.implies(
            self.expression(q),
            self.expression(p)
        )
        let first = try expression.truthTable()
        let second = try expression.truthTable()

        XCTAssertEqual(first, second)
        XCTAssertEqual(first.atoms, [p, q])
        XCTAssertEqual(
            first.rows.map(\.inputs),
            [[false, false], [false, true], [true, false], [true, true]]
        )
        XCTAssertEqual(first.rows.map(\.output), [true, false, true, true])
    }

    // Production mutation caught: row guard is moved after shift/allocation or raised to 64 atoms.
    func testTwelveAtomsProduceFourThousandNinetySixRowsAndThirteenRejectBeforeShift() throws {
        let twelve = try balancedAnd(numberedAtoms(12))
        var acceptedShiftCount = 0
        var acceptedAllocations: [Int] = []
        let accepted = try twelve.truthTable(
            shift: { exponent in
                acceptedShiftCount += 1
                guard exponent >= 0, exponent < Int.bitWidth else { return nil }
                return 1 << exponent
            },
            workspaceProbe: EnumerationWorkspaceProbe(onAllocate: {
                acceptedAllocations.append($0)
            })
        )

        XCTAssertEqual(accepted.rows.count, 4_096)
        XCTAssertEqual(acceptedShiftCount, 1)
        XCTAssertEqual(acceptedAllocations, [4_096])

        let thirteen = try balancedAnd(numberedAtoms(13))
        var rejectedShiftCount = 0
        var rejectedAllocationCount = 0
        XCTAssertThrowsError(
            try thirteen.truthTable(
                shift: { _ in
                    rejectedShiftCount += 1
                    return nil
                },
                workspaceProbe: EnumerationWorkspaceProbe(onAllocate: { _ in
                    rejectedAllocationCount += 1
                })
            )
        ) { error in
            XCTAssertEqual(
                error as? ClassicalSemanticsError,
                .rowLimitExceeded(atomCount: 13, maximumRows: 4_096)
            )
        }
        XCTAssertEqual(rejectedShiftCount, 0)
        XCTAssertEqual(rejectedAllocationCount, 0)

        var directShiftCount = 0
        let direct = checkedPowerOfTwoCount(
            variableCount: 13,
            maximum: 4_096,
            shift: { _ in
                directShiftCount += 1
                return nil
            }
        )
        XCTAssertNil(direct)
        XCTAssertEqual(directShiftCount, 0, "shared helper 自身也必須 guard-before-shift")
    }

    // Production mutation caught: 63 variables bypass the shared helper or execute a machine-width shift.
    func testSixtyThreeAndSixtyFourAtomEnumerationFailsClosedBeforeShift() throws {
        let sixtyThree = try balancedAnd(numberedAtoms(63))
        var shiftCount = 0
        var allocationCount = 0
        XCTAssertThrowsError(
            try sixtyThree.truthTable(
                shift: { _ in
                    shiftCount += 1
                    return nil
                },
                workspaceProbe: EnumerationWorkspaceProbe(onAllocate: { _ in
                    allocationCount += 1
                })
            )
        ) { error in
            XCTAssertEqual(
                error as? ClassicalSemanticsError,
                .rowLimitExceeded(atomCount: 63, maximumRows: 4_096)
            )
        }
        XCTAssertEqual(shiftCount, 0)
        XCTAssertEqual(allocationCount, 0)

        var sixtyFourShiftCount = 0
        XCTAssertNil(
            checkedPowerOfTwoCount(
                variableCount: 64,
                maximum: 4_096,
                shift: { _ in
                    sixtyFourShiftCount += 1
                    return nil
                }
            )
        )
        XCTAssertEqual(sixtyFourShiftCount, 0)
    }

    // Production mutation caught: semantic equivalence delegates to structural equality.
    func testClassicalEquivalenceIsNotStructuralEquality() throws {
        let pExpression = try expression(p)
        let qExpression = try expression(q)
        let pq = try PropositionExpression.or(pExpression, qExpression)
        let qp = try PropositionExpression.or(qExpression, pExpression)

        XCTAssertNotEqual(pq, qp)
        XCTAssertTrue(try pq.isClassicallyEquivalent(to: qp))

        let qTautology = try PropositionExpression.or(
            qExpression,
            try PropositionExpression.not(qExpression)
        )
        let expandedP = try PropositionExpression.and(pExpression, qTautology)
        XCTAssertNotEqual(pExpression, expandedP)
        XCTAssertTrue(try pExpression.isClassicallyEquivalent(to: expandedP))
    }

    // Production mutation caught: implication or either De Morgan operator is implemented incorrectly.
    func testClassicalLawsUseSemanticEquivalence() throws {
        let pExpression = try expression(p)
        let qExpression = try expression(q)
        let notP = try PropositionExpression.not(pExpression)
        let notQ = try PropositionExpression.not(qExpression)

        XCTAssertTrue(
            try PropositionExpression.not(notP).isClassicallyEquivalent(to: pExpression)
        )
        XCTAssertTrue(
            try PropositionExpression.implies(pExpression, qExpression)
                .isClassicallyEquivalent(to: .or(notP, qExpression))
        )
        XCTAssertTrue(
            try PropositionExpression.not(.and(pExpression, qExpression))
                .isClassicallyEquivalent(to: .or(notP, notQ))
        )
        XCTAssertTrue(
            try PropositionExpression.not(.or(pExpression, qExpression))
                .isClassicallyEquivalent(to: .and(notP, notQ))
        )
        XCTAssertFalse(
            try PropositionExpression.implies(pExpression, qExpression)
                .isClassicallyEquivalent(to: .implies(qExpression, pExpression))
        )
    }

    // Production mutation caught: classification uses a shortcut instead of every complete row.
    func testTautologyAndContradictionAreDefinedByCompleteTruthTables() throws {
        let pExpression = try expression(p)
        let notP = try PropositionExpression.not(pExpression)
        let excludedMiddle = try PropositionExpression.or(pExpression, notP)
        let contradiction = try PropositionExpression.and(pExpression, notP)

        XCTAssertEqual(try excludedMiddle.truthTable().rows.map(\.output), [true, true])
        XCTAssertTrue(try excludedMiddle.isClassicalTautology())
        XCTAssertFalse(try excludedMiddle.isClassicalContradiction())

        XCTAssertEqual(try contradiction.truthTable().rows.map(\.output), [false, false])
        XCTAssertFalse(try contradiction.isClassicalTautology())
        XCTAssertTrue(try contradiction.isClassicalContradiction())

        XCTAssertEqual(try pExpression.truthTable().rows.map(\.output), [false, true])
        XCTAssertFalse(try pExpression.isClassicalTautology())
        XCTAssertFalse(try pExpression.isClassicalContradiction())
    }
}
