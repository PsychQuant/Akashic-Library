import CryptoKit
import Foundation
import XCTest
import AkashicCore
@testable import AkashicProposition

/// #214 task 1.3：Unicode 15.1.0 信任鏈、資源上限與正典 bytes 的 RED。
///
/// 放在獨立檔案但延伸 `ExpressionConstructionTests`，避免與 task 1.2 同檔衝突，
/// 同時保留 design Decision 10 指定的穩定 test locator。
extension ExpressionConstructionTests {
    private enum UnicodeFixtureError: Error {
        case invalidJSON(String)
        case invalidNormalizationLine(String)
        case invalidScalar(String)
        case missingReplayOutput(String)
    }

    private static let atomGolden =
        "000000000000001b616b61736869632d70726f706f736974696f6e2d61746f6d2d7631"
        + "000000000000000000017000000000000000000177"

    private static let notExpressionGolden =
        "0000000000000021616b61736869632d70726f706f736974696f6e2d6578707265737369"
        + "6f6e2d763100000000000000010000000000000038"
        + atomGolden
        + "000000000000000201000000000000000000"

    private static let truthTableGolden =
        "0000000000000020616b61736869632d636c6173736963616c2d74727574682d7461626c"
        + "652d763100000000000000010000000000000038"
        + atomGolden
        + "0000000000000002000000000000000001000000000000000100"

    private static let functionTableGolden =
        "0000000000000021616b61736869632d626f6f6c65616e2d66756e6374696f6e2d746162"
        + "6c652d763100000000000000010000000000000038"
        + atomGolden
        + "0000000000000002000000000000000001000000000000000100"

    private static let norRepresentativeGolden =
        "0000000000000021616b61736869632d70726f706f736974696f6e2d6578707265737369"
        + "6f6e2d763100000000000000010000000000000038"
        + atomGolden
        + "000000000000000305000000000000000000000000000000000000"

    private var unicodeRepositoryRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    private var unicodeTestBundleURL: URL {
        for bundle in Bundle.allBundles where bundle.bundlePath.hasSuffix(".xctest") {
            return bundle.bundleURL
        }
        fatalError("找不到目前的 XCTest bundle")
    }

    private func authored(person: EntityRef, work: EntityRef = .key("w")) -> Proposition {
        .authored(person: person, work: work)
    }

    private func atomExpression(_ proposition: Proposition) throws -> PropositionExpression {
        try PropositionExpression.atom(proposition)
    }

    private func atomExpression(literal: String) throws -> PropositionExpression {
        try atomExpression(authored(person: .literal(literal)))
    }

    private func assertPropositionError<T>(
        _ expected: PropositionError,
        _ operation: () throws -> T,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertThrowsError(try operation(), file: file, line: line) { error in
            XCTAssertEqual(error as? PropositionError, expected, file: file, line: line)
        }
    }

    // Production mutations caught: raw cap after syntax/trim; full-buffer or platform NFC;
    // normalized cap off-by-one; assigned-scalar scan after normalization.
    func testReferenceByteBudgetsPrecedeSyntaxAndPinnedNormalization() throws {
        XCTAssertEqual(PropositionLogicLimits.maximumReferenceUTF8ByteCount, 4_096)

        let exactRawKey = String(repeating: "a", count: 4_096)
        let exactRawLiteral = String(repeating: "b", count: 4_096)
        XCTAssertNoThrow(try atomExpression(authored(person: .key(exactRawKey))))
        XCTAssertNoThrow(try atomExpression(literal: exactRawLiteral))

        let rawOverflow = String(repeating: "a", count: 4_097)
        assertPropositionError(
            .referenceUTF8ByteCountExceeded(
                stage: .rawUTF8,
                minimumObserved: 4_097,
                maximum: 4_096
            )
        ) {
            try atomExpression(literal: rawOverflow)
        }
        assertPropositionError(
            .referenceUTF8ByteCountExceeded(
                stage: .rawUTF8,
                minimumObserved: 4_097,
                maximum: 4_096
            )
        ) {
            try atomExpression(authored(person: .key(rawOverflow)))
        }
        assertPropositionError(
            .referenceUTF8ByteCountExceeded(
                stage: .rawUTF8,
                minimumObserved: 4_097,
                maximum: 4_096
            )
        ) {
            try atomExpression(literal: String(repeating: " ", count: 4_097))
        }

        let exactNormalized = String(repeating: "\u{0344}", count: 1_024)
        XCTAssertEqual(exactNormalized.utf8.count, 2_048)
        XCTAssertNoThrow(try atomExpression(literal: exactNormalized),
                         "pinned NFC 恰好 4,096 bytes 必須接受")

        let normalizedOverflow = String(repeating: "\u{0344}", count: 2_048)
        XCTAssertEqual(normalizedOverflow.utf8.count, 4_096)
        assertPropositionError(
            .referenceUTF8ByteCountExceeded(
                stage: .normalizedUTF8,
                minimumObserved: 4_097,
                maximum: 4_096
            )
        ) {
            try atomExpression(literal: normalizedOverflow)
        }

        let unsupportedScalar = try XCTUnwrap(UnicodeScalar(0x1CC00))
        let unsupportedBeforeExpansion = String(unsupportedScalar)
            + String(repeating: "\u{0344}", count: 2_046)
        XCTAssertEqual(unsupportedBeforeExpansion.utf8.count, 4_096)
        assertPropositionError(
            .unsupportedUnicodeScalar(
                value: unsupportedScalar.value,
                normalizationVersion: "15.1.0"
            )
        ) {
            try atomExpression(literal: unsupportedBeforeExpansion)
        }

        let malformedKey = String(unsupportedScalar)
        assertPropositionError(.malformedKey(malformedKey)) {
            try atomExpression(authored(person: .key(malformedKey)))
        }
    }

    // Production mutations caught: manifest/data/source edited together under v1; partial UCD;
    // platform White_Space/NFC; generator that reads network or produces nondeterministic bytes.
    func testUnicodeV1TrustChainAndOfficialConformanceArePinned() throws {
        let officialDigests = [
            "UnicodeData.txt":
                "2fc713e6a31a87c4850a37fe2caffa4218180fadb5de86b43a143ddb4581fb86",
            "CompositionExclusions.txt":
                "59d2d9e3dfdf0a999cf9dae11d594f053631222679a2f5710315ea07f7fe82af",
            "DerivedNormalizationProps.txt":
                "8875dccee2bc1a7c1fe568a3b502a9e78c9e0495afd96b6568b4294d0ed1f7e1",
            "PropList.txt":
                "05672956317b6296bc2ec3d6cef1f6452b57ff4f2efc6dc55b0a19277d5fcfd1",
            "NormalizationTest.txt":
                "871238e37e3be0696ec2bd0891119a041b052da1a84485eda05a5438724b223e",
        ]
        let ucdRoot = unicodeRepositoryRoot
            .appendingPathComponent("Vendor/Unicode/15.1.0", isDirectory: true)
        let manifestURL = unicodeRepositoryRoot
            .appendingPathComponent("unicode-normalization-v1.manifest.json")
        let generatorURL = unicodeRepositoryRoot
            .appendingPathComponent("Tools/UnicodeNormalizationGenerator/main.swift")
        let runtimeURL = unicodeRepositoryRoot
            .appendingPathComponent("Sources/AkashicProposition/UnicodeNormalizationV1.swift")
        let generatedURL = unicodeRepositoryRoot.appendingPathComponent(
            "Sources/AkashicProposition/Generated/UnicodeNormalizationTablesV1.swift"
        )
        let trustAnchorURL = unicodeRepositoryRoot.appendingPathComponent(
            "Tests/AkashicPropositionTests/Fixtures/UnicodeNormalizationV1TrustAnchor.json"
        )

        for (name, expectedDigest) in officialDigests {
            let url = ucdRoot.appendingPathComponent(name)
            XCTAssertEqual(try sha256(at: url), expectedDigest,
                           "Unicode 15.1.0 官方輸入 (name) 不得漂移")
        }

        let anchors = try jsonDictionary(at: trustAnchorURL)
        let pinnedSHA = try stringDictionary(anchors["sha256"], name: "sha256")
        let requiredSources = [
            "unicode-normalization-v1.manifest.json": manifestURL,
            "Tools/UnicodeNormalizationGenerator/main.swift": generatorURL,
            "Sources/AkashicProposition/UnicodeNormalizationV1.swift": runtimeURL,
            "Sources/AkashicProposition/Generated/UnicodeNormalizationTablesV1.swift": generatedURL,
        ]
        for (path, url) in requiredSources {
            let expected = try XCTUnwrap(
                pinnedSHA[path],
                "tests-only trust anchor 必須獨立固定 (path) 的 SHA-256"
            )
            XCTAssertEqual(try sha256(at: url), expected, "v1 source 漂移：\(path)")
        }
        for (name, officialDigest) in officialDigests {
            let path = "Vendor/Unicode/15.1.0/\(name)"
            XCTAssertEqual(pinnedSHA[path], officialDigest,
                           "tests-only anchor 必須固定官方 (name) digest")
        }

        let manifest = try jsonDictionary(at: manifestURL)
        XCTAssertEqual(manifest["schema_version"] as? Int, 1)
        XCTAssertEqual(manifest["unicode_version"] as? String, "15.1.0")
        let manifestStrings = flattenedStrings(manifest)
        for domain in [
            "akashic-proposition-atom-v1",
            "akashic-proposition-expression-v1",
            "akashic-classical-truth-table-v1",
            "akashic-boolean-function-table-v1",
        ] {
            XCTAssertTrue(manifestStrings.contains(domain), "manifest 未固定 domain：\(domain)")
        }
        for (name, digest) in officialDigests {
            XCTAssertTrue(manifestStrings.contains(digest), "manifest 未固定 (name) digest")
            XCTAssertTrue(
                manifestStrings.contains("https://www.unicode.org/Public/15.1.0/ucd/\(name)"),
                "manifest 未固定 (name) 官方 URL"
            )
        }
        for (path, url) in requiredSources where path != "unicode-normalization-v1.manifest.json" {
            XCTAssertTrue(manifestStrings.contains(path), "manifest 未固定 source path：\(path)")
            XCTAssertTrue(manifestStrings.contains(try sha256(at: url)),
                          "manifest 未固定 source digest：\(path)")
        }
        XCTAssertTrue(
            manifestStrings.contains(
                "swift run UnicodeNormalizationGenerator --ucd-root Vendor/Unicode/15.1.0 "
                + "--manifest unicode-normalization-v1.manifest.json --output "
                + "Sources/AkashicProposition/Generated/UnicodeNormalizationTablesV1.swift "
                + "--verify-v1"
            ),
            "manifest 必須固定可離線重播的 generator command"
        )

        try assertPinnedWhiteSpaceFixtures()
        try assertOfficialNormalizationConformance(
            at: ucdRoot.appendingPathComponent("NormalizationTest.txt")
        )
        try assertOfflineRegenerationMatches(
            ucdRoot: ucdRoot,
            manifestURL: manifestURL,
            generatedURL: generatedURL
        )
    }

    // Production mutations caught: domain/tag/length/count/row-index remap, child swap,
    // or rewrite/synthesis selecting a semantically equivalent but byte-different NOR tree.
    func testCanonicalByteGoldenVectorsAndStructuralCollisionPairs() throws {
        let p = authored(person: .key("p"))
        let q = authored(person: .key("q"))
        let pe = try atomExpression(p)
        let qe = try atomExpression(q)
        let notP = try PropositionExpression.not(pe)
        let table = try notP.truthTable()
        let function = try BooleanFunctionTable(
            atomsInInputBitOrder: [p],
            outputsInInputBitRowOrder: [true, false]
        )

        XCTAssertEqual(hex(try firstCanonicalAtom(in: pe.canonicalBytes)), Self.atomGolden)
        XCTAssertEqual(hex(notP.canonicalBytes), Self.notExpressionGolden)
        XCTAssertEqual(hex(table.canonicalBytes), Self.truthTableGolden)
        XCTAssertEqual(hex(function.canonicalBytes), Self.functionTableGolden)
        XCTAssertNotEqual(table.canonicalBytes, function.canonicalBytes,
                          "兩種 table 必須使用不同 domain")

        let reverseDiscovery = try PropositionExpression.implies(qe, pe)
        let reverseDiscoveryReplay = try PropositionExpression.implies(qe, pe)
        let orderedTable = try reverseDiscovery.truthTable()
        XCTAssertEqual(orderedTable.atoms, [p, q])
        XCTAssertEqual(
            orderedTable.rows.map(\.inputs),
            [[false, false], [false, true], [true, false], [true, true]]
        )
        XCTAssertEqual(orderedTable.canonicalBytes,
                       try reverseDiscoveryReplay.truthTable().canonicalBytes)

        let callerOrderFunction = try BooleanFunctionTable(
            atomsInInputBitOrder: [q, p],
            outputsInInputBitRowOrder: [false, true, false, true]
        )
        let canonicalOrderFunction = try BooleanFunctionTable(
            atomsInInputBitOrder: [p, q],
            outputsInInputBitRowOrder: [false, false, true, true]
        )
        XCTAssertEqual(callerOrderFunction.atoms, [p, q])
        XCTAssertEqual(callerOrderFunction.outputs, [false, false, true, true])
        XCTAssertEqual(callerOrderFunction.canonicalBytes, canonicalOrderFunction.canonicalBytes)

        let nfc = try atomExpression(literal: "\u{00E9}")
        let nfd = try atomExpression(literal: "e\u{0301}")
        XCTAssertEqual(nfc.canonicalBytes, nfd.canonicalBytes)
        XCTAssertEqual(try nfc.truthTable().canonicalBytes, try nfd.truthTable().canonicalBytes)

        let nodePayloads: [(PropositionExpression, String)] = [
            (pe, "000000000000000000"),
            (notP, "01000000000000000000"),
            (try PropositionExpression.and(pe, qe),
             "02000000000000000000000000000000000001"),
            (try PropositionExpression.or(pe, qe),
             "03000000000000000000000000000000000001"),
            (try PropositionExpression.implies(pe, qe),
             "04000000000000000000000000000000000001"),
            (try PropositionExpression.nor(pe, qe),
             "05000000000000000000000000000000000001"),
            (try PropositionExpression.and(try PropositionExpression.not(qe), pe),
             "0201000000000000000001000000000000000000"),
        ]
        for (expression, expected) in nodePayloads {
            XCTAssertEqual(hex(try expressionNodePayload(expression.canonicalBytes)), expected)
        }

        let keyAtom = try atomExpression(authored(person: .key("ab")))
        let literalAtom = try atomExpression(authored(person: .literal("ab")))
        let authoredAtom = try atomExpression(authored(person: .key("p"), work: .key("w")))
        let affiliatedAtom = try atomExpression(
            .affiliated(person: .key("p"), organization: .key("w"))
        )
        let splitLeft = try atomExpression(
            authored(person: .key("ab"), work: .key("c"))
        )
        let splitRight = try atomExpression(
            authored(person: .key("a"), work: .key("bc"))
        )
        for (left, right) in [
            (keyAtom, literalAtom),
            (authoredAtom, affiliatedAtom),
            (splitLeft, splitRight),
        ] {
            XCTAssertNotEqual(
                try firstCanonicalAtom(in: left.canonicalBytes),
                try firstCanonicalAtom(in: right.canonicalBytes),
                "predicate/reference tags 與 UInt64 lengths 必須防止 concatenation collision"
            )
        }

        let rewritten = try notP.rewrittenUsingNor()
        let synthesized = try PropositionExpression.synthesizeUsingNor(function)
        XCTAssertEqual(rewritten, try PropositionExpression.nor(pe, pe))
        XCTAssertEqual(synthesized, try PropositionExpression.nor(pe, pe))
        XCTAssertEqual(hex(rewritten.canonicalBytes), Self.norRepresentativeGolden)
        XCTAssertEqual(hex(synthesized.canonicalBytes), Self.norRepresentativeGolden)
    }

    // Production mutations caught: platform normalization/whitespace table or an eager full-input
    // scalar count in displaySafe before applying the caller-visible budget.
    func testProductionCanonicalizationStaticBanAndBoundedDisplaySafe() throws {
        let canonicalizationFiles = [
            "Sources/AkashicProposition/Proposition.swift",
            "Sources/AkashicProposition/UnicodeNormalizationV1.swift",
            "Sources/AkashicProposition/Generated/UnicodeNormalizationTablesV1.swift",
        ]
        let bannedTokens = [
            "precomposedStringWithCanonicalMapping",
            "decomposedStringWithCanonicalMapping",
            "applyingTransform",
            "StringTransform",
            "CFStringNormalize",
            "CharacterSet.whitespaces",
            "CharacterSet.whitespacesAndNewlines",
            "trimmingCharacters(in:",
            ".whitespaces",
            ".whitespacesAndNewlines",
        ]
        for path in canonicalizationFiles {
            let source = try String(
                contentsOf: unicodeRepositoryRoot.appendingPathComponent(path),
                encoding: .utf8
            )
            for token in bannedTokens {
                XCTAssertFalse(source.contains(token), "production 平台 API static ban：\(path): \(token)")
            }
        }

        let models = try String(
            contentsOf: unicodeRepositoryRoot.appendingPathComponent("Sources/AkashicCore/Models.swift"),
            encoding: .utf8
        )
        let displayStart = try XCTUnwrap(models.range(of: "public func displaySafe("))
        let displayEnd = try XCTUnwrap(
            models.range(of: "public struct ValidationIssue", range: displayStart.upperBound..<models.endIndex)
        )
        let displaySource = String(models[displayStart.lowerBound..<displayEnd.lowerBound])
        for eagerPattern in [
            "s.unicodeScalars.count",
            "Array(s.unicodeScalars)",
            "Array(s)",
        ] {
            XCTAssertFalse(
                displaySource.contains(eagerPattern),
                "displaySafe 套用 budget 前不得全量計數／配置：\(eagerPattern)"
            )
        }

        let combiningBomb = "a" + String(repeating: "\u{0301}", count: 1_000_000)
        let safe = displaySafe(combiningBomb, max: 120)
        XCTAssertLessThan(safe.unicodeScalars.count, 160)
        XCTAssertTrue(safe.hasSuffix("…（已截斷）"))
    }

    // Production mutations caught: randomized Hasher/collection iteration, process-dependent
    // encoding, or canonical replay that only succeeds in the originating process.
    func testCanonicalBytesReplayInFreshSubprocesses() throws {
        let first = try canonicalReplayFromFreshProcess()
        let second = try canonicalReplayFromFreshProcess()
        let expected = [
            Self.atomGolden,
            Self.notExpressionGolden,
            Self.truthTableGolden,
            Self.functionTableGolden,
            Self.norRepresentativeGolden,
            Self.norRepresentativeGolden,
        ].joined(separator: "|")
        XCTAssertEqual(first, expected)
        XCTAssertEqual(second, expected)
        XCTAssertEqual(first, second)
    }

    /// Fresh-process replay 的單一 child locator。一般完整 suite 直接通過；parent test
    /// 直接另啟兩個 xctest processes 並擷取固定 marker，避免遞迴取得 SwiftPM scratch lock。
    func testCanonicalReplayChild() throws {
        guard ProcessInfo.processInfo.environment["AKASHIC_CANONICAL_REPLAY_CHILD"] == "1" else {
            return
        }
        let payload = try canonicalReplayPayload()
        FileHandle.standardOutput.write(Data("AKASHIC_CANONICAL_REPLAY:\(payload)\n".utf8))
    }

    private func canonicalReplayPayload() throws -> String {
        let p = authored(person: .key("p"))
        let pe = try atomExpression(p)
        let notP = try PropositionExpression.not(pe)
        let truthTable = try notP.truthTable()
        let functionTable = try BooleanFunctionTable(
            atomsInInputBitOrder: [p],
            outputsInInputBitRowOrder: [true, false]
        )
        let rewritten = try notP.rewrittenUsingNor()
        let synthesized = try PropositionExpression.synthesizeUsingNor(functionTable)
        return [
            hex(try firstCanonicalAtom(in: pe.canonicalBytes)),
            hex(notP.canonicalBytes),
            hex(truthTable.canonicalBytes),
            hex(functionTable.canonicalBytes),
            hex(rewritten.canonicalBytes),
            hex(synthesized.canonicalBytes),
        ].joined(separator: "|")
    }

    private func canonicalReplayFromFreshProcess() throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
        process.arguments = [
            "xctest",
            "-XCTest",
            "AkashicPropositionTests.ExpressionConstructionTests/testCanonicalReplayChild",
            unicodeTestBundleURL.path,
        ]
        var environment = ProcessInfo.processInfo.environment
        environment["AKASHIC_CANONICAL_REPLAY_CHILD"] = "1"
        environment["LC_ALL"] = "C"
        process.environment = environment
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        try process.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        let output = String(decoding: data, as: UTF8.self)
        XCTAssertEqual(process.terminationStatus, 0, output)
        let marker = "AKASHIC_CANONICAL_REPLAY:"
        guard let line = output.split(whereSeparator: \Character.isNewline)
            .first(where: { $0.contains(marker) }),
              let markerRange = line.range(of: marker) else {
            throw UnicodeFixtureError.missingReplayOutput(output)
        }
        return String(line[markerRange.upperBound...])
    }

    private func assertPinnedWhiteSpaceFixtures() throws {
        let whiteSpaceValues: [UInt32] = Array(0x0009...0x000D)
            + [0x0020, 0x0085, 0x00A0, 0x1680]
            + Array(0x2000...0x200A)
            + [0x2028, 0x2029, 0x202F, 0x205F, 0x3000]
        XCTAssertEqual(whiteSpaceValues.count, 25)
        for value in whiteSpaceValues {
            let scalar = try XCTUnwrap(UnicodeScalar(value))
            assertPropositionError(.emptyLiteral) {
                try atomExpression(literal: String(scalar))
            }
        }
        for value: UInt32 in [0x180E, 0x200B, 0x2060, 0xFEFF] {
            let scalar = try XCTUnwrap(UnicodeScalar(value))
            XCTAssertNoThrow(try atomExpression(literal: String(scalar)),
                             "U+\(String(format: "%04X", value)) 不屬於 pinned White_Space")
        }
    }

    private func assertOfficialNormalizationConformance(at url: URL) throws {
        let text = try String(contentsOf: url, encoding: .utf8)
        var checked = 0
        for rawLine in text.split(whereSeparator: \Character.isNewline) {
            let line = rawLine.firstIndex(of: "#").map { rawLine[..<$0] }
                ?? rawLine[rawLine.startIndex...]
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty, !trimmed.hasPrefix("@") else { continue }
            let columns = line.split(separator: ";", omittingEmptySubsequences: false)
            guard columns.count >= 5 else {
                throw UnicodeFixtureError.invalidNormalizationLine(String(rawLine))
            }
            let values = try columns.prefix(5).map(parseScalarSequence)
            // NormalizationTest 包含純 White_Space vectors；語法 gate 已由獨立 fixture
            // 驗證。U+1F600 在 Unicode 15.1.0 已指派且不參與 canonical composition，
            // 以相同 sentinel 前綴即可讓這裡只比較 pinned NFC payload。
            let expressions = try values.map { value in
                try atomExpression(literal: "\u{1F600}" + value)
            }
            let bytes = expressions.map(\.canonicalBytes)
            XCTAssertEqual(bytes[0], bytes[1], "NFC(c1) != c2：\(rawLine)")
            XCTAssertEqual(bytes[1], bytes[2], "NFC(c3) != c2：\(rawLine)")
            XCTAssertEqual(bytes[3], bytes[4], "NFC(c5) != c4：\(rawLine)")
            checked += 1
        }
        XCTAssertGreaterThan(checked, 10_000, "NormalizationTest.txt 必須全量執行")
    }

    private func parseScalarSequence(_ field: Substring) throws -> String {
        var view = String.UnicodeScalarView()
        for token in field.split(whereSeparator: \Character.isWhitespace) {
            guard let value = UInt32(token, radix: 16), let scalar = UnicodeScalar(value) else {
                throw UnicodeFixtureError.invalidScalar(String(token))
            }
            view.append(scalar)
        }
        return String(view)
    }

    private func assertOfflineRegenerationMatches(
        ucdRoot: URL,
        manifestURL: URL,
        generatedURL: URL
    ) throws {
        let runRoot = URL(fileURLWithPath: "/tmp/akashic-214-red-unicode", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: runRoot, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: runRoot) }
        let outputURL = runRoot.appendingPathComponent("UnicodeNormalizationTablesV1.swift")
        let scratchURL = runRoot.appendingPathComponent("swiftpm", isDirectory: true)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = [
            "swift", "run",
            "--disable-automatic-resolution",
            "--scratch-path", scratchURL.path,
            "UnicodeNormalizationGenerator",
            "--ucd-root", ucdRoot.path,
            "--manifest", manifestURL.path,
            "--output", outputURL.path,
            "--verify-v1",
        ]
        process.currentDirectoryURL = unicodeRepositoryRoot
        var environment = ProcessInfo.processInfo.environment
        environment["http_proxy"] = "http://127.0.0.1:9"
        environment["https_proxy"] = "http://127.0.0.1:9"
        environment["ALL_PROXY"] = "http://127.0.0.1:9"
        process.environment = environment
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        try process.run()
        let output = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        XCTAssertEqual(
            process.terminationStatus,
            0,
            "offline regeneration 失敗：\(String(decoding: output, as: UTF8.self))"
        )
        XCTAssertEqual(try Data(contentsOf: outputURL), try Data(contentsOf: generatedURL),
                       "offline regeneration 必須 byte-identical")
    }

    private func sha256(at url: URL) throws -> String {
        SHA256.hash(data: try Data(contentsOf: url))
            .map { String(format: "%02x", $0) }
            .joined()
    }

    private func jsonDictionary(at url: URL) throws -> [String: Any] {
        let object = try JSONSerialization.jsonObject(with: Data(contentsOf: url))
        guard let dictionary = object as? [String: Any] else {
            throw UnicodeFixtureError.invalidJSON(url.path)
        }
        return dictionary
    }

    private func stringDictionary(_ value: Any?, name: String) throws -> [String: String] {
        guard let dictionary = value as? [String: String] else {
            throw UnicodeFixtureError.invalidJSON(name)
        }
        return dictionary
    }

    private func flattenedStrings(_ value: Any) -> [String] {
        if let string = value as? String { return [string] }
        if let array = value as? [Any] { return array.flatMap(flattenedStrings) }
        if let dictionary = value as? [String: Any] {
            return dictionary.flatMap { key, child in [key] + flattenedStrings(child) }
        }
        return []
    }

    private func hex(_ data: Data) -> String {
        data.map { String(format: "%02x", $0) }.joined()
    }

    private func readUInt64(_ data: Data, offset: inout Int) throws -> Int {
        guard offset <= data.count - 8 else {
            throw UnicodeFixtureError.invalidJSON("canonical UInt64 framing")
        }
        var value: UInt64 = 0
        for byte in data[offset..<(offset + 8)] {
            value = (value << 8) | UInt64(byte)
        }
        offset += 8
        guard value <= UInt64(Int.max) else {
            throw UnicodeFixtureError.invalidJSON("canonical UInt64 exceeds Int")
        }
        return Int(value)
    }

    private func skipBytes(_ count: Int, in data: Data, offset: inout Int) throws {
        guard count >= 0, offset <= data.count - count else {
            throw UnicodeFixtureError.invalidJSON("canonical length framing")
        }
        offset += count
    }

    private func firstCanonicalAtom(in expressionBytes: Data) throws -> Data {
        var offset = 0
        let domainLength = try readUInt64(expressionBytes, offset: &offset)
        try skipBytes(domainLength, in: expressionBytes, offset: &offset)
        let atomCount = try readUInt64(expressionBytes, offset: &offset)
        guard atomCount > 0 else {
            throw UnicodeFixtureError.invalidJSON("expression atom table is empty")
        }
        let atomLength = try readUInt64(expressionBytes, offset: &offset)
        let start = offset
        try skipBytes(atomLength, in: expressionBytes, offset: &offset)
        return expressionBytes.subdata(in: start..<offset)
    }

    private func expressionNodePayload(_ expressionBytes: Data) throws -> Data {
        var offset = 0
        let domainLength = try readUInt64(expressionBytes, offset: &offset)
        try skipBytes(domainLength, in: expressionBytes, offset: &offset)
        let atomCount = try readUInt64(expressionBytes, offset: &offset)
        for _ in 0..<atomCount {
            let atomLength = try readUInt64(expressionBytes, offset: &offset)
            try skipBytes(atomLength, in: expressionBytes, offset: &offset)
        }
        _ = try readUInt64(expressionBytes, offset: &offset)
        return expressionBytes.subdata(in: offset..<expressionBytes.count)
    }
}
