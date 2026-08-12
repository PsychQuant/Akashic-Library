import Foundation
import XCTest
@testable import AkashicProposition

/// #214 的 opaque expression construction 與固定資源界線 RED。
final class ExpressionConstructionTests: XCTestCase {
    private func proposition(_ index: Int) -> Proposition {
        .authored(
            person: .key("person-\(index)"),
            work: .key("work-\(index)")
        )
    }

    private func balancedAnd(
        _ expressions: [PropositionExpression]
    ) throws -> PropositionExpression {
        precondition(!expressions.isEmpty)
        var level = expressions
        while level.count > 1 {
            var next: [PropositionExpression] = []
            next.reserveCapacity((level.count + 1) / 2)
            var index = 0
            while index < level.count {
                if index + 1 < level.count {
                    next.append(try PropositionExpression.and(
                        level[index],
                        level[index + 1]
                    ))
                } else {
                    next.append(level[index])
                }
                index += 2
            }
            level = next
        }
        return level[0]
    }

    private func hashFeedComponents(
        _ expression: PropositionExpression
    ) -> [String] {
        expression.structuralHashFeed.map { component in
            switch component {
            case .atomTableCount(let count):
                "atomTableCount:\(count)"
            case .atomPayload(let length, let bytes):
                "atomPayload:\(length):\(bytes.map { String(format: "%02x", $0) }.joined())"
            case .nodeTag(let tag):
                "nodeTag:\(tag)"
            case .childBoundary(let parentTag, let childIndex):
                "childBoundary:\(parentTag):\(childIndex)"
            case .atomIndex(let index):
                "atomIndex:\(index)"
            }
        }
    }

    private func externalTypecheck(
        _ source: String
    ) throws -> (status: Int32, output: String) {
        let fileManager = FileManager.default
        let directory = fileManager.temporaryDirectory
            .appendingPathComponent("akashic-expression-typecheck-\(UUID().uuidString)")
        try fileManager.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        defer { try? fileManager.removeItem(at: directory) }

        let sourceURL = directory.appendingPathComponent("Probe.swift")
        try source.write(to: sourceURL, atomically: true, encoding: .utf8)

        let modules = productsDirectory.appendingPathComponent("Modules")
        let scratchRoot = productsDirectory
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let cyamlInclude = scratchRoot
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
        SwiftcProbe.configure(process, arguments: [
            "-typecheck",
            "-warnings-as-errors",
            "-I", modules.path,
            "-Xcc", "-fmodule-map-file=\(cyamlModuleMap.path)",
            "-Xcc", "-I",
            "-Xcc", cyamlInclude.path,
            sourceURL.path,
        ])
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        try process.run()
        let output = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        let text = String(decoding: output, as: UTF8.self)
        SwiftcProbe.assertToolchainMatched(text, process)
        return (process.terminationStatus, text)
    }

    private var productsDirectory: URL {
        for bundle in Bundle.allBundles where bundle.bundlePath.hasSuffix(".xctest") {
            return bundle.bundleURL.deletingLastPathComponent()
        }
        fatalError("找不到 SwiftPM products directory")
    }

    // Production mutation caught: a factory simplifies double negation, swaps binary children,
    // exposes the wrong kind/arity, or loses structural occurrences from cached metadata.
    func testOpaqueFactoriesCoverEveryOperatorAndPreserveStructuralIdentity() throws {
        let p = proposition(0)
        let q = proposition(1)
        let pe = try PropositionExpression.atom(p)
        let qe = try PropositionExpression.atom(q)
        let notP = try PropositionExpression.not(pe)
        let notNotP = try PropositionExpression.not(notP)
        let andPQ = try PropositionExpression.and(pe, qe)
        let orPQ = try PropositionExpression.or(pe, qe)
        let impliesPQ = try PropositionExpression.implies(pe, qe)
        let norPQ = try PropositionExpression.nor(pe, qe)

        XCTAssertEqual(pe.kind, .atom)
        XCTAssertEqual(pe.proposition, p)
        XCTAssertEqual(pe.children, [])
        XCTAssertEqual(pe.operatorDepth, 0)
        XCTAssertEqual(pe.nodeCount, 1)

        XCTAssertEqual(notP.kind, .not)
        XCTAssertNil(notP.proposition)
        XCTAssertEqual(notP.children, [pe])
        XCTAssertEqual(notP.operatorDepth, 1)
        XCTAssertEqual(notP.nodeCount, 2)

        let binaryCases: [(
            expression: PropositionExpression,
            kind: PropositionExpression.Kind
        )] = [
            (andPQ, .and),
            (orPQ, .or),
            (impliesPQ, .implies),
            (norPQ, .nor),
        ]
        for item in binaryCases {
            XCTAssertEqual(item.expression.kind, item.kind)
            XCTAssertNil(item.expression.proposition)
            XCTAssertEqual(item.expression.children, [pe, qe])
            XCTAssertEqual(item.expression.operatorDepth, 1)
            XCTAssertEqual(item.expression.nodeCount, 3)
        }

        XCTAssertNotEqual(pe, notP)
        XCTAssertNotEqual(pe, notNotP)
        XCTAssertNotEqual(notP, notNotP)
        XCTAssertEqual(Set([pe, notP, notNotP]).count, 3)
        XCTAssertEqual(Set(binaryCases.map(\.expression)).count, 4)

        let swapped = try PropositionExpression.and(qe, pe)
        XCTAssertNotEqual(andPQ, swapped)
        XCTAssertEqual(andPQ.children, [pe, qe])
        XCTAssertEqual(swapped.children, [qe, pe])

        let repeated = try PropositionExpression.and(pe, pe)
        XCTAssertEqual(repeated.nodeCount, 3, "重複 occurrence 不得被 storage sharing 折疊")
        XCTAssertEqual(repeated.atoms, [p], "重複 atom 只占一個 distinct-atom budget")
    }

    // Production mutation caught: structural hashing omits the canonical atom payload, any node
    // tag, child boundary, or occurrence atom index.
    func testStructuralHashFeedIncludesAtomTableEveryNodeTagAndChildBoundary() throws {
        let p = try PropositionExpression.atom(proposition(0))
        let q = try PropositionExpression.atom(proposition(1))
        let expressions = [
            p,
            try PropositionExpression.not(p),
            try PropositionExpression.and(p, q),
            try PropositionExpression.or(p, q),
            try PropositionExpression.implies(p, q),
            try PropositionExpression.nor(p, q),
        ]
        let feeds = expressions.map(hashFeedComponents)

        XCTAssertNotEqual(
            hashFeedComponents(p),
            hashFeedComponents(q),
            "單一 atom feed 必須先包含完整 canonical atom-table payload"
        )
        XCTAssertEqual(
            Set(feeds).count,
            expressions.count,
            "六種 node tag 不得在 feed 中互相折疊"
        )

        let nested = try PropositionExpression.and(
            try PropositionExpression.not(p),
            q
        )
        let nestedFeed = hashFeedComponents(nested)
        XCTAssertEqual(
            nestedFeed.filter { $0.contains("atomPayload") }.count,
            nested.atoms.count,
            "每個 canonical atom-table entry 都須有一個 atomPayload component"
        )
        XCTAssertEqual(
            nestedFeed.filter { $0.contains("nodeTag") }.count,
            nested.nodeCount,
            "每個 structural occurrence 都須有一個 nodeTag component"
        )
        XCTAssertEqual(
            nestedFeed.filter { $0.contains("childBoundary") }.count,
            nested.nodeCount - 1,
            "每條 parent-child edge 都須有明示 childBoundary component"
        )
        XCTAssertEqual(
            nestedFeed.filter { $0.contains("atomIndex") }.count,
            2,
            "每個 atom occurrence 都須指向 canonical atom table"
        )
    }

    // Production mutation caught: any hard bound is off by one, repeated atoms consume the wrong
    // budget, or a rejected candidate leaves partially constructed public storage.
    func testExpressionBudgetsAcceptExactBoundaryAndRejectNextValue() throws {
        XCTAssertEqual(PropositionLogicLimits.maximumOperatorDepth, 64)
        XCTAssertEqual(PropositionLogicLimits.maximumNodeCount, 4_096)
        XCTAssertEqual(PropositionLogicLimits.maximumDistinctAtomCount, 63)

        let atom = try PropositionExpression.atom(proposition(0))

        var depthBoundary = atom
        for _ in 0..<64 {
            depthBoundary = try PropositionExpression.not(depthBoundary)
        }
        XCTAssertEqual(depthBoundary.operatorDepth, 64)
        XCTAssertThrowsError(try PropositionExpression.not(depthBoundary)) { error in
            XCTAssertEqual(
                error as? PropositionExpressionError,
                .operatorDepthExceeded(actual: 65, maximum: 64)
            )
        }

        var nodeBoundary = atom
        for _ in 0..<11 {
            nodeBoundary = try PropositionExpression.and(nodeBoundary, nodeBoundary)
        }
        XCTAssertEqual(nodeBoundary.nodeCount, 4_095)
        nodeBoundary = try PropositionExpression.not(nodeBoundary)
        XCTAssertEqual(nodeBoundary.nodeCount, 4_096)
        XCTAssertThrowsError(try PropositionExpression.not(nodeBoundary)) { error in
            XCTAssertEqual(
                error as? PropositionExpressionError,
                .nodeCountExceeded(actual: 4_097, maximum: 4_096)
            )
        }

        let sixtyThreeAtoms = try (0..<63).map {
            try PropositionExpression.atom(proposition($0))
        }
        let atomBoundary = try balancedAnd(sixtyThreeAtoms)
        XCTAssertEqual(atomBoundary.atoms.count, 63)
        XCTAssertThrowsError(try PropositionExpression.and(
            atomBoundary,
            PropositionExpression.atom(proposition(63))
        )) { error in
            XCTAssertEqual(
                error as? PropositionExpressionError,
                .distinctAtomCountExceeded(actual: 64, maximum: 63)
            )
        }
    }

    // Production mutation caught: malformed raw atoms are wrapped as expression errors or reach a
    // binary operand, question, projection, or epistemic result.
    func testMalformedAtomsPreserveOriginalErrorsBeforeExpressionStorageExists() throws {
        let malformed = Proposition.authored(
            person: .key("Not A Key"),
            work: .key("work-a")
        )
        let empty = Proposition.affiliated(
            person: .literal("   "),
            organization: .key("org-a")
        )

        XCTAssertThrowsError(try PropositionExpression.atom(malformed)) { error in
            XCTAssertEqual(error as? PropositionError, .malformedKey("Not A Key"))
        }
        XCTAssertThrowsError(try malformed.asExpression()) { error in
            XCTAssertEqual(error as? PropositionError, .malformedKey("Not A Key"))
        }
        XCTAssertThrowsError(try PropositionExpression.atom(empty)) { error in
            XCTAssertEqual(error as? PropositionError, .emptyLiteral)
        }
        XCTAssertThrowsError(try empty.asExpression()) { error in
            XCTAssertEqual(error as? PropositionError, .emptyLiteral)
        }
    }

    // Production mutation caught: a compatibility wrapper bypasses validation or the legacy
    // depth symbol becomes a second, independently adjustable budget.
    @available(*, deprecated, message: "故意在 deprecated scope 驗證 #214 遷移橋接")
    func testDeprecatedWrappersAndMaximumOperatorDepthRemainSafeAliases() throws {
        let p = proposition(0)
        let expression = try PropositionExpression.makeAtom(p)
        let negated = try PropositionExpression.makeNot(expression)

        XCTAssertEqual(expression, try PropositionExpression.atom(p))
        XCTAssertEqual(negated, try PropositionExpression.not(expression))
        XCTAssertEqual(
            PropositionExpression.maximumOperatorDepth,
            PropositionLogicLimits.maximumOperatorDepth
        )

        let malformed = Proposition.authored(
            person: .key("Not A Key"),
            work: .key("work-a")
        )
        XCTAssertThrowsError(try PropositionExpression.makeAtom(malformed)) { error in
            XCTAssertEqual(error as? PropositionError, .malformedKey("Not A Key"))
        }
    }

    // Production mutation caught: expression storage/cases become public, or a public limit
    // parameter lets callers raise a library-owned hard bound.
    func testExternalClientsCannotConstructRawExpressionStorageOrRaiseLimits() throws {
        let boundedFactories = try externalTypecheck("""
            import AkashicProposition

            func constructEveryOperator(_ p: Proposition, _ q: Proposition) throws {
                let pe = try PropositionExpression.atom(p)
                let qe = try PropositionExpression.atom(q)
                _ = try PropositionExpression.not(pe)
                _ = try PropositionExpression.and(pe, qe)
                _ = try PropositionExpression.or(pe, qe)
                _ = try PropositionExpression.implies(pe, qe)
                _ = try PropositionExpression.nor(pe, qe)
                _ = try p.asExpression()
            }
            """)
        XCTAssertEqual(
            boundedFactories.status,
            0,
            "non-@testable client 必須能使用六種 throwing factory：\(boundedFactories.output)"
        )

        let rawStorage = try externalTypecheck("""
            import AkashicProposition

            func bypass(_ p: Proposition) -> PropositionExpression {
                .atom(p)
            }
            """)
        XCTAssertNotEqual(
            rawStorage.status,
            0,
            "non-@testable client 不得以 enum-style case 或 raw storage 繞過 atom factory"
        )
        XCTAssertTrue(
            rawStorage.output.contains("throw")
                || rawStorage.output.contains("unavailable")
                || rawStorage.output.contains("no member"),
            rawStorage.output
        )

        let callerLimit = try externalTypecheck("""
            import AkashicProposition

            func raiseLimit(_ p: PropositionExpression, _ q: PropositionExpression) throws {
                _ = try PropositionExpression.and(p, q, limit: Int.max)
                _ = try PropositionExpression.not(p, maximumOperatorDepth: Int.max)
            }
            """)
        XCTAssertNotEqual(
            callerLimit.status,
            0,
            "任何 public factory 都不得接受 caller-selected limit／budget"
        )
        XCTAssertTrue(
            callerLimit.output.contains("extra argument")
                || callerLimit.output.contains("no exact matches")
                || callerLimit.output.contains("no member"),
            callerLimit.output
        )

        let legacyAlias = try externalTypecheck("""
            import AkashicProposition

            @available(*, deprecated)
            func legacyDepthAlias() -> Bool {
                let p = Proposition.authored(person: .key("p"), work: .key("w"))
                guard let expression = try? PropositionExpression.makeAtom(p),
                      let negated = try? PropositionExpression.makeNot(expression)
                else { return false }
                return PropositionExpression.maximumOperatorDepth
                        == PropositionLogicLimits.maximumOperatorDepth
                    && negated.operatorDepth == 1
            }
            """)
        XCTAssertEqual(
            legacyAlias.status,
            0,
            "deprecated maximumOperatorDepth 必須仍是可讀、不可提高的 safe alias：\(legacyAlias.output)"
        )

        let nonthrowingProperty = try externalTypecheck("""
            import AkashicProposition

            func bypassValidation(_ p: Proposition) -> PropositionExpression {
                p.expression
            }
            """)
        XCTAssertNotEqual(
            nonthrowingProperty.status,
            0,
            "Proposition.expression 不得保留 nonthrowing expression construction path"
        )
    }
}
