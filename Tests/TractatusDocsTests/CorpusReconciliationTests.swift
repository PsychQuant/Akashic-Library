import Foundation
import XCTest
@testable import TractatusDocs

final class CorpusReconciliationTests: XCTestCase {
    private let issue203 = "https://github.com/PsychQuant/Akashic-Library/issues/203"
    private let issue204 = "https://github.com/PsychQuant/Akashic-Library/issues/204"
    private let pr210Merge = "e821378372932004720961ba7a1a12dc6f10c331"

    private let issue203IDs: Set<String> = ["4.023", "4.06", "4.2", "4.25", "6.5"]
    private let volumeFiveIssue204IDs: Set<String> = [
        "5", "5.01", "5.1", "5.101", "5.234", "5.2341", "5.3", "5.31",
        "5.32", "5.41", "5.42", "5.43", "5.44", "5.441", "5.442", "5.5",
        "5.501", "5.502", "5.503", "5.51", "5.512", "5.513", "5.52", "5.54",
    ]
    private let specialIDs: Set<String> = [
        "4.431", "4.05", "4.26", "4.0621", "4.064", "4.0641",
    ]

    func testIssueHistorySetsAreExactAndAuditedSetHasThirtyFiveRecords() throws {
        let volumes = try loadCanonicalVolumes()
        let records = Dictionary(uniqueKeysWithValues: volumes.flatMap(\.propositions).map {
            ($0.id.rawValue, $0)
        })

        let actual203 = Set(records.values.filter {
            $0.history.contains { $0.reference == issue203 }
        }.map { $0.id.rawValue })
        let volumeFive = try XCTUnwrap(volumes.first { $0.volume == "5" })
        let actual204 = Set(volumeFive.propositions.filter {
            $0.history.contains { $0.reference == issue204 }
        }.map { $0.id.rawValue })

        XCTAssertEqual(actual203, issue203IDs)
        XCTAssertEqual(actual204, volumeFiveIssue204IDs)
        let actualSpecials = specialIDs.intersection(records.keys)
        XCTAssertEqual(actualSpecials, specialIDs)
        let actualAudited = actual203.union(actual204).union(actualSpecials)
        XCTAssertEqual(
            actualAudited,
            issue203IDs.union(volumeFiveIssue204IDs).union(specialIDs)
        )
        XCTAssertEqual(actualAudited.count, 35)
        XCTAssertTrue(records["4.431"]?.history.contains { $0.reference == issue204 } == true)
    }

    func testVolumeFiveDispositionsAreTwentyTwoPartialTwoAspirationalAndZeroImplemented() throws {
        let volume = try XCTUnwrap(try loadVolumes("5").first)
        let selected = volume.propositions.filter {
            volumeFiveIssue204IDs.contains($0.id.rawValue)
        }
        let statusByID = Dictionary(uniqueKeysWithValues: try selected.map { record in
            let relation = try XCTUnwrap(record.projectRelations.first)
            return (record.id.rawValue, relation.status.rawValue)
        })

        XCTAssertEqual(Set(statusByID.keys), volumeFiveIssue204IDs)
        XCTAssertEqual(statusByID.values.filter { $0 == "partial" }.count, 22)
        XCTAssertEqual(statusByID.values.filter { $0 == "aspirational" }.count, 2)
        XCTAssertEqual(statusByID.values.filter { $0 == "implemented" }.count, 0)
        XCTAssertEqual(statusByID["5.441"], "aspirational")
        XCTAssertEqual(statusByID["5.52"], "aspirational")
    }

    func testEveryVolumeFiveIssue204HistoryIsRevisedAndUsesCurrentEvidence() throws {
        let volume = try XCTUnwrap(try loadVolumes("5").first)
        let currentPaths: Set<String> = [
            "Sources/AkashicProposition/Expression.swift",
            "Sources/AkashicProposition/ClassicalSemantics.swift",
            "Sources/AkashicProposition/Projection.swift",
            "Sources/AkashicProposition/TruthFunctionSynthesis.swift",
            "Tests/AkashicPropositionTests/ExpressionConstructionTests.swift",
            "Tests/AkashicPropositionTests/ClassicalSemanticsTests.swift",
            "Tests/AkashicPropositionTests/SupervaluationTests.swift",
            "Tests/AkashicPropositionTests/TruthFunctionSynthesisTests.swift",
        ]

        for record in volume.propositions where volumeFiveIssue204IDs.contains(record.id.rawValue) {
            let history = try XCTUnwrap(record.history.first { $0.reference == issue204 })
            XCTAssertEqual(history.disposition, .revised, record.id.rawValue)

            let relation = try XCTUnwrap(record.projectRelations.first)
            if record.id.rawValue != "5.441", record.id.rawValue != "5.52" {
                XCTAssertTrue(
                    relation.evidence.contains { currentPaths.contains($0.path) },
                    "\(record.id.rawValue) 缺少 #214 current source/test evidence"
                )
                XCTAssertFalse(relation.claimZhTW.contains("尚未實作"), record.id.rawValue)
                if record.id.rawValue != "5.1" {
                    XCTAssertFalse(relation.rationaleZhTW.contains("尚未實作"), record.id.rawValue)
                }
            }
        }
    }

    func testResidueAndSpecialReviewsStayHonest() throws {
        let records = Dictionary(uniqueKeysWithValues: try loadVolumes("4", "5")
            .flatMap(\.propositions).map { ($0.id.rawValue, $0) })

        let fiveOne = try XCTUnwrap(records["5.1"]?.projectRelations.first)
        XCTAssertEqual(fiveOne.status, .partial)
        XCTAssertTrue(fiveOne.rationaleZhTW.contains("機率"))
        XCTAssertTrue(fiveOne.rationaleZhTW.contains("未實作"))

        for id in ["5.441", "5.52"] {
            let relation = try XCTUnwrap(records[id]?.projectRelations.first)
            XCTAssertEqual(relation.status, .aspirational)
            XCTAssertTrue(relation.rationaleZhTW.contains("量化"), id)
        }

        let four431 = try XCTUnwrap(records["4.431"]?.projectRelations.first)
        XCTAssertEqual(four431.status, .partial)
        XCTAssertTrue(four431.evidence.contains { $0.locator == "truthTable" })
        XCTAssertTrue(four431.evidence.contains { $0.locator == "isClassicallyEquivalent" })

        XCTAssertEqual(records["4.05"]?.projectRelations.first?.status, .partial)
        XCTAssertEqual(records["4.26"]?.projectRelations.first?.status, .intentionalNonconformance)
        for id in ["4.0621", "4.064", "4.0641"] {
            let relation = try XCTUnwrap(records[id]?.projectRelations.first)
            XCTAssertEqual(relation.status, .notApplicable, id)
            XCTAssertTrue(relation.rationaleZhTW.contains("覆核"), id)
            XCTAssertTrue(relation.rationaleZhTW.contains("不足"), id)
        }
    }

    func testReconciliationPinsPR210BaselineAndAllLocatorsResolveInOneTree() throws {
        let volumes = try loadCanonicalVolumes()
        XCTAssertTrue(volumes.flatMap(\.propositions).contains { record in
            record.history.contains { $0.kind == .commit && $0.reference == pr210Merge }
        })
        XCTAssertEqual(
            CorpusValidator.validateEvidence(volumes: volumes, projectRoot: repositoryRoot),
            []
        )
    }

    func testCorpusResourceLimitsRejectAliasAmplificationAndOversizedVolume() throws {
        let evidence = """
              - &e
                path: Sources/AkashicProposition/Projection.swift
                kind: symbol
                locator: evaluate
        """
        let aliases = Array(
            repeating: "      - *e",
            count: CorpusResourceLimits.maximumEvidencePerRelation
        ).joined(separator: "\n")
        let yaml = """
        schema_version: 1
        volume: "1"
        propositions:
        - id: "1"
          texts:
            de: ["x"]
            en: ["x"]
          segments:
          - id: "1.a"
            alignment:
              de: [0]
              en: [0]
            translation_zh_tw: "x"
            interpretation_zh_tw: "x"
          project_relations:
          - status: partial
            mode: instance
            claim_zh_tw: "x"
            rationale_zh_tw: "x"
            evidence:
        \(evidence)
        \(aliases)
        """

        XCTAssertThrowsError(try CorpusYAMLDecoder.decodeVolume(yaml)) { error in
            XCTAssertEqual(
                error as? CorpusSchemaError,
                .resourceLimit(
                    kind: "evidence-per-relation",
                    actual: CorpusResourceLimits.maximumEvidencePerRelation + 1,
                    maximum: CorpusResourceLimits.maximumEvidencePerRelation
                )
            )
        }

        let oversized = String(
            repeating: " ",
            count: CorpusResourceLimits.maximumVolumeUTF8Bytes + 1
        )
        XCTAssertThrowsError(try CorpusYAMLDecoder.decodeVolume(oversized)) { error in
            XCTAssertEqual(
                error as? CorpusSchemaError,
                .resourceLimit(
                    kind: "volume-utf8-bytes",
                    actual: CorpusResourceLimits.maximumVolumeUTF8Bytes + 1,
                    maximum: CorpusResourceLimits.maximumVolumeUTF8Bytes
                )
            )
        }

        var aliasBomb = "root: &a0 [x]\n"
        for level in 1...7 {
            let references = Array(repeating: "*a\(level - 1)", count: 9)
                .joined(separator: ", ")
            aliasBomb += "level\(level): &a\(level) [\(references)]\n"
        }
        XCTAssertThrowsError(try CorpusYAMLDecoder.decodeVolume(aliasBomb)) { error in
            guard case let .resourceLimit(kind, actual, maximum) = error as? CorpusSchemaError else {
                return XCTFail("預期 resource-limit，實際為 \(error)")
            }
            XCTAssertEqual(kind, "volume-alias-expanded-nodes")
            XCTAssertGreaterThan(actual, maximum)
        }
    }

    private func loadCanonicalVolumes() throws -> [CorpusVolume] {
        try CorpusValidationEngine.validate(
            root: repositoryRoot.appendingPathComponent("docs/tractatus"),
            allowIncomplete: false
        ).corpus.volumes
    }

    private func loadVolumes(_ names: String...) throws -> [CorpusVolume] {
        try names.map { name in
            try CorpusYAMLDecoder.decodeVolume(
                contentsOf: repositoryRoot
                    .appendingPathComponent("docs/tractatus/corpus/\(name).yaml")
            )
        }
    }

    private var repositoryRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }
}
