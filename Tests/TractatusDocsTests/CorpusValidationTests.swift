import CryptoKit
import Foundation
import XCTest
@testable import TractatusDocs

final class CorpusValidationTests: XCTestCase {
    func testDecodesManyToManyAlignmentWithoutFlatteningSourceUnits() throws {
        let volume = try CorpusYAMLDecoder.decodeVolume(validVolumeYAML)

        let proposition = try XCTUnwrap(volume.propositions.first)
        XCTAssertEqual(proposition.id.rawValue, "2.01")
        XCTAssertEqual(proposition.texts["de"], ["Ein erster Satz.", "Ein zweiter Satz."])
        XCTAssertEqual(proposition.texts["en_ogden_ramsey_1922"], ["Two German units align here."])
        let segment = try XCTUnwrap(proposition.segments.first)
        XCTAssertEqual(segment.id.rawValue, "2.01.a")
        XCTAssertEqual(segment.alignment["de"], [0, 1])
        XCTAssertEqual(segment.alignment["en_ogden_ramsey_1922"], [0])
    }

    func testRejectsUnknownKeysInsteadOfSilentlyIgnoringThem() throws {
        let yaml = validVolumeYAML.replacingOccurrences(
            of: "volume: \"2\"",
            with: "volume: \"2\"\nunknown_root_key: true"
        )

        XCTAssertThrowsError(try CorpusYAMLDecoder.decodeVolume(yaml)) { error in
            XCTAssertEqual(
                error as? CorpusSchemaError,
                .unknownKey("unknown_root_key"),
                String(reflecting: error)
            )
        }
    }

    func testSchemaDiagnosticsEscapeHostileControlAndDirectionCharacters() throws {
        let hostile = "field\n\u{001B}\u{202E}\\tail"
        let schemaErrors: [CorpusSchemaError] = [
            .unknownKey(hostile),
            .invalidID(hostile),
            .invalidRelation(hostile),
        ]

        for error in schemaErrors {
            let description = try XCTUnwrap(error.errorDescription)
            XCTAssertFalse(description.contains("\n"))
            XCTAssertFalse(description.unicodeScalars.contains("\u{001B}"))
            XCTAssertFalse(description.unicodeScalars.contains("\u{202E}"))
            XCTAssertTrue(description.contains(#"\u{000A}"#))
            XCTAssertTrue(description.contains(#"\u{001B}"#))
            XCTAssertTrue(description.contains(#"\u{202E}"#))
            XCTAssertTrue(description.contains(#"\u{005C}"#))
        }

        let formatted = CorpusDiagnostic(
            path: hostile,
            recordID: hostile,
            code: hostile,
            message: hostile
        ).formatted
        XCTAssertFalse(formatted.contains("\n"))
        XCTAssertFalse(formatted.unicodeScalars.contains("\u{001B}"))
        XCTAssertFalse(formatted.unicodeScalars.contains("\u{202E}"))
        XCTAssertTrue(formatted.contains(#"\u{000A}"#))
        XCTAssertTrue(formatted.contains(#"\u{001B}"#))
        XCTAssertTrue(formatted.contains(#"\u{202E}"#))
        XCTAssertTrue(formatted.contains(#"\u{005C}"#))
    }

    func testRejectsMalformedPropositionAndSegmentIdentifiers() throws {
        XCTAssertThrowsError(try PropositionID(validating: "2.bad")) { error in
            XCTAssertEqual(error as? CorpusSchemaError, .invalidID("2.bad"))
        }
        XCTAssertThrowsError(try SegmentID(validating: "2.01.A")) { error in
            XCTAssertEqual(error as? CorpusSchemaError, .invalidID("2.01.A"))
        }
    }

    func testCanonicalOrderUsesPrintedDecimalSemanticsAndNumericPrefaceParagraphs() throws {
        let propositionIDs = try ["2.1", "2.012", "2.01", "2.011"]
            .map(PropositionID.init(validating:))
            .sorted()
            .map(\.rawValue)
        let prefaceIDs = try ["preface.10", "preface.2", "preface.1"]
            .map(PropositionID.init(validating:))
            .sorted()
            .map(\.rawValue)

        XCTAssertEqual(propositionIDs, ["2.01", "2.011", "2.012", "2.1"])
        XCTAssertEqual(prefaceIDs, ["preface.1", "preface.2", "preface.10"])
    }

    func testDerivesPrintedHierarchyWithoutTreatingDecimalAsFloatingPoint() throws {
        XCTAssertEqual(try PropositionID(validating: "2.0121").inferredParent?.rawValue, "2.012")
        XCTAssertEqual(try PropositionID(validating: "2.01").inferredParent?.rawValue, "2")
        XCTAssertEqual(try PropositionID(validating: "5.101").inferredParent?.rawValue, "5.1")
        XCTAssertEqual(try PropositionID(validating: "3.001").inferredParent?.rawValue, "3")
        XCTAssertNil(try PropositionID(validating: "2").inferredParent)
        XCTAssertNil(try PropositionID(validating: "preface.3").inferredParent)
    }

    func testStructureReportsManifestInventoryOmissionsAndExtras() throws {
        let missingManifest = try makeManifest(inventory: canonicalRootIDs + ["1.1"])
        let missing = CorpusValidator.validateStructure(
            manifest: missingManifest,
            volumes: try makeBaselineVolumes()
        )

        var extraVolumes = try makeBaselineVolumes()
        extraVolumes[1] = try makeVolume("1", records: [("1", nil), ("1.1", "1")])
        let extra = CorpusValidator.validateStructure(
            manifest: try makeManifest(inventory: canonicalRootIDs),
            volumes: extraVolumes
        )

        XCTAssertTrue(missing.contains { $0.code == "missing-proposition" && $0.recordID == "1.1" })
        XCTAssertTrue(extra.contains { $0.code == "extra-proposition" && $0.recordID == "1.1" })
    }

    func testTruncatedRootOnlyScopeIsRejectedEvenWhenCorpusMatchesManifest() throws {
        let issues = CorpusValidator.validateStructure(
            manifest: try makeManifest(inventory: canonicalRootIDs),
            volumes: try makeBaselineVolumes()
        )

        XCTAssertTrue(issues.contains {
            $0.code == "invalid-scope" && $0.recordID == "inventory"
        })
    }

    func testFixedScopeRejectsMissingCanonicalEditions() throws {
        let issues = CorpusValidator.validateStructure(
            manifest: try makeManifest(inventory: canonicalRootIDs),
            volumes: try makeBaselineVolumes()
        )

        XCTAssertTrue(issues.contains {
            $0.code == "invalid-scope" && $0.recordID == "editions"
        })
    }

    func testStructureReportsDuplicateIDsAcrossVolumes() throws {
        var volumes = try makeBaselineVolumes()
        volumes.append(try makeVolume("1", records: [("1", nil)]))

        let issues = CorpusValidator.validateStructure(
            manifest: try makeManifest(inventory: canonicalRootIDs),
            volumes: volumes
        )

        XCTAssertTrue(issues.contains { $0.code == "duplicate-id" && $0.recordID == "1" })
    }

    func testStructureRequiresThePrintedParentToExist() throws {
        var volumes = try makeBaselineVolumes()
        volumes[1] = try makeVolume("1", records: [("1", nil), ("1.1", nil)])

        let issues = CorpusValidator.validateStructure(
            manifest: try makeManifest(inventory: canonicalRootIDs + ["1.1"]),
            volumes: volumes
        )

        XCTAssertTrue(issues.contains { $0.code == "missing-parent" && $0.recordID == "1.1" })
    }

    func testAlignmentAcceptsAValidManyToManySegment() throws {
        let issues = CorpusValidator.validateAlignment(
            manifest: try makeInlineManifest(),
            volumes: [try CorpusYAMLDecoder.decodeVolume(validVolumeYAML)]
        )

        XCTAssertEqual(issues, [])
    }

    func testAlignmentReportsGapsAndDuplicateIndexes() throws {
        let gapYAML = validVolumeYAML.replacingOccurrences(of: "de: [0, 1]", with: "de: [0]")
        let duplicateYAML = validVolumeYAML.replacingOccurrences(
            of: "de: [0, 1]",
            with: "de: [0, 0, 1]"
        )

        let gap = CorpusValidator.validateAlignment(
            manifest: try makeInlineManifest(),
            volumes: [try CorpusYAMLDecoder.decodeVolume(gapYAML)]
        )
        let duplicate = CorpusValidator.validateAlignment(
            manifest: try makeInlineManifest(),
            volumes: [try CorpusYAMLDecoder.decodeVolume(duplicateYAML)]
        )

        XCTAssertTrue(gap.contains { $0.code == "alignment-gap" })
        XCTAssertTrue(duplicate.contains { $0.code == "alignment-duplicate" })
    }

    func testAlignmentRejectsMegaSegmentsThatHideSentenceLevelInterpretation() throws {
        let yaml = validVolumeYAML
            .replacingOccurrences(
                of: "            - \"Ein zweiter Satz.\"",
                with: "            - \"Ein zweiter Satz.\"\n            - \"Ein dritter Satz.\""
            )
            .replacingOccurrences(of: "de: [0, 1]", with: "de: [0, 1, 2]")
        let volume = try CorpusYAMLDecoder.decodeVolume(yaml)

        let issues = CorpusValidator.validateAlignment(
            manifest: try makeInlineManifest(),
            volumes: [volume]
        )

        XCTAssertTrue(issues.contains {
            $0.code == "alignment-granularity" && $0.recordID == "2.01.a"
        })
    }

    func testAlignmentRejectsTwoByTwoAggregationWithoutEditionBoundaryDifference() throws {
        let yaml = validVolumeYAML
            .replacingOccurrences(
                of: "            - \"Two German units align here.\"",
                with: "            - \"An English first sentence.\"\n            - \"An English second sentence.\""
            )
            .replacingOccurrences(
                of: "en_ogden_ramsey_1922: [0]",
                with: "en_ogden_ramsey_1922: [0, 1]"
            )
        let volume = try CorpusYAMLDecoder.decodeVolume(yaml)

        let issues = CorpusValidator.validateAlignment(
            manifest: try makeInlineManifest(),
            volumes: [volume]
        )

        XCTAssertTrue(issues.contains {
            $0.code == "alignment-granularity" && $0.recordID == "2.01.a"
        })
    }

    func testAlignmentRejectsOneByOneUnitsThatEachHideMultipleSentences() throws {
        let volume = try CorpusYAMLDecoder.decodeVolume("""
        schema_version: 1
        volume: "2"
        propositions:
          - id: "2.01"
            parent: "2"
            texts:
              de: ["Ein erster Satz. Ein zweiter Satz."]
              en_ogden_ramsey_1922: ["A first sentence. A second sentence."]
            edition_references:
              en_pears_mcguinness: "2.01"
            segments:
              - id: "2.01.a"
                alignment:
                  de: [0]
                  en_ogden_ramsey_1922: [0]
                translation_zh_tw: "第一句。第二句。"
                interpretation_zh_tw: "兩個完整句子不應藏在一個 1↔1 來源單位裡。"
        """)

        let issues = CorpusValidator.validateAlignment(
            manifest: try makeInlineManifest(),
            volumes: [volume]
        )

        XCTAssertTrue(issues.contains {
            $0.code == "source-unit-granularity" && $0.recordID == "2.01.a"
        })
    }

    func testAlignmentRejectsTwoByOneThatUsesAnArbitrarySplitToHideSentences() throws {
        let volume = try CorpusYAMLDecoder.decodeVolume("""
        schema_version: 1
        volume: "2"
        propositions:
          - id: "2.01"
            parent: "2"
            texts:
              de: ["Ein erster Sa", "tz. Ein zweiter Satz."]
              en_ogden_ramsey_1922: ["A first sentence. A second sentence."]
            edition_references:
              en_pears_mcguinness: "2.01"
            segments:
              - id: "2.01.a"
                alignment:
                  de: [0, 1]
                  en_ogden_ramsey_1922: [0]
                translation_zh_tw: "第一句。第二句。"
                interpretation_zh_tw: "任意切字不能把兩個句子偽裝成版本句界差異。"
        """)

        let issues = CorpusValidator.validateAlignment(
            manifest: try makeInlineManifest(),
            volumes: [volume]
        )

        XCTAssertTrue(issues.contains {
            $0.code == "alignment-granularity" && $0.recordID == "2.01.a"
        })
    }

    func testAlignmentRejectsCrossEditionIndexesThatAreCoveredOutOfOrder() throws {
        let volume = try CorpusYAMLDecoder.decodeVolume("""
        schema_version: 1
        volume: "2"
        propositions:
          - id: "2.01"
            parent: "2"
            texts:
              de: ["Erster Satz.", "Zweiter Satz."]
              en_ogden_ramsey_1922: ["First sentence.", "Second sentence."]
            edition_references:
              en_pears_mcguinness: "2.01"
            segments:
              - id: "2.01.a"
                alignment:
                  de: [0]
                  en_ogden_ramsey_1922: [1]
                translation_zh_tw: "第一句。"
                interpretation_zh_tw: "英文索引錯接到第二句。"
              - id: "2.01.b"
                alignment:
                  de: [1]
                  en_ogden_ramsey_1922: [0]
                translation_zh_tw: "第二句。"
                interpretation_zh_tw: "英文索引錯接到第一句。"
        """)

        let issues = CorpusValidator.validateAlignment(
            manifest: try makeInlineManifest(),
            volumes: [volume]
        )

        XCTAssertTrue(issues.contains {
            $0.code == "alignment-order" && $0.recordID == "2.01"
        })
    }

    func testAlignmentRequiresEverySegmentToConnectEveryInlineEdition() throws {
        let volume = try CorpusYAMLDecoder.decodeVolume("""
        schema_version: 1
        volume: "2"
        propositions:
          - id: "2.01"
            parent: "2"
            texts:
              de: ["Ein erster Satz.", "Ein zweiter Satz."]
              en_ogden_ramsey_1922: ["One English sentence."]
            edition_references:
              en_pears_mcguinness: "2.01"
            segments:
              - id: "2.01.a"
                alignment:
                  de: [0, 1]
                translation_zh_tw: "兩個德文來源單位。"
                interpretation_zh_tw: "這一段沒有連到英文版本。"
              - id: "2.01.b"
                alignment:
                  en_ogden_ramsey_1922: [0]
                translation_zh_tw: "一個英文來源單位。"
                interpretation_zh_tw: "這一段沒有連到德文版本。"
        """)

        let issues = CorpusValidator.validateAlignment(
            manifest: try makeInlineManifest(),
            volumes: [volume]
        )

        XCTAssertTrue(issues.contains {
            $0.code == "alignment-gap" && $0.recordID == "2.01.a"
        })
        XCTAssertTrue(issues.contains {
            $0.code == "alignment-gap" && $0.recordID == "2.01.b"
        })
    }

    func testAlignmentRejectsMissingOrPlaceholderChineseContent() throws {
        let missingTranslation = validVolumeYAML.replacingOccurrences(
            of: "translation_zh_tw: \"兩個德文單位在此合成一個對齊句段。\"",
            with: "translation_zh_tw: \"<unfinished>\""
        )
        let missingInterpretation = validVolumeYAML.replacingOccurrences(
            of: "interpretation_zh_tw: \"來源版本的句界不必相同；索引保存多對多關係。\"",
            with: "interpretation_zh_tw: \"   \""
        )

        let translationIssues = CorpusValidator.validateAlignment(
            manifest: try makeInlineManifest(),
            volumes: [try CorpusYAMLDecoder.decodeVolume(missingTranslation)]
        )
        let interpretationIssues = CorpusValidator.validateAlignment(
            manifest: try makeInlineManifest(),
            volumes: [try CorpusYAMLDecoder.decodeVolume(missingInterpretation)]
        )

        XCTAssertTrue(translationIssues.contains { $0.code == "missing-translation" })
        XCTAssertTrue(interpretationIssues.contains { $0.code == "missing-interpretation" })
    }

    func testAlignmentRejectsNonHanTranslationAndInterpretation() throws {
        let nonHanTranslation = validVolumeYAML.replacingOccurrences(
            of: "translation_zh_tw: \"兩個德文單位在此合成一個對齊句段。\"",
            with: "translation_zh_tw: \"A complete English translation.\""
        )
        let nonHanInterpretation = validVolumeYAML.replacingOccurrences(
            of: "interpretation_zh_tw: \"來源版本的句界不必相同；索引保存多對多關係。\"",
            with: "interpretation_zh_tw: \"A distinct English interpretation.\""
        )

        let translationIssues = CorpusValidator.validateAlignment(
            manifest: try makeInlineManifest(),
            volumes: [try CorpusYAMLDecoder.decodeVolume(nonHanTranslation)]
        )
        let interpretationIssues = CorpusValidator.validateAlignment(
            manifest: try makeInlineManifest(),
            volumes: [try CorpusYAMLDecoder.decodeVolume(nonHanInterpretation)]
        )

        XCTAssertTrue(translationIssues.contains {
            $0.code == "missing-translation" && $0.recordID == "2.01.a"
        })
        XCTAssertTrue(interpretationIssues.contains {
            $0.code == "missing-interpretation" && $0.recordID == "2.01.a"
        })
    }

    func testAlignmentAcceptsUnicode17ExtensionJAsHan() throws {
        let extensionJStart = String(Unicode.Scalar(0x323B0)!)
        let extensionJEnd = String(Unicode.Scalar(0x33479)!)
        let yaml = validVolumeYAML
            .replacingOccurrences(
                of: "translation_zh_tw: \"兩個德文單位在此合成一個對齊句段。\"",
                with: "translation_zh_tw: \"\(extensionJStart) translation.\""
            )
            .replacingOccurrences(
                of: "interpretation_zh_tw: \"來源版本的句界不必相同；索引保存多對多關係。\"",
                with: "interpretation_zh_tw: \"\(extensionJEnd) interpretation.\""
            )

        let issues = CorpusValidator.validateAlignment(
            manifest: try makeInlineManifest(),
            volumes: [try CorpusYAMLDecoder.decodeVolume(yaml)]
        )

        XCTAssertFalse(issues.contains {
            $0.code == "missing-translation" || $0.code == "missing-interpretation"
        })
    }

    func testAlignmentRejectsUnassignedCompatibilityGapAsHan() throws {
        let unassignedGap = String(Unicode.Scalar(0xFA6E)!)
        let yaml = validVolumeYAML
            .replacingOccurrences(
                of: "translation_zh_tw: \"兩個德文單位在此合成一個對齊句段。\"",
                with: "translation_zh_tw: \"\(unassignedGap) translation.\""
            )
            .replacingOccurrences(
                of: "interpretation_zh_tw: \"來源版本的句界不必相同；索引保存多對多關係。\"",
                with: "interpretation_zh_tw: \"\(unassignedGap) interpretation.\""
            )

        let issues = CorpusValidator.validateAlignment(
            manifest: try makeInlineManifest(),
            volumes: [try CorpusYAMLDecoder.decodeVolume(yaml)]
        )

        XCTAssertTrue(issues.contains {
            $0.code == "missing-translation" && $0.recordID == "2.01.a"
        })
        XCTAssertTrue(issues.contains {
            $0.code == "missing-interpretation" && $0.recordID == "2.01.a"
        })
    }

    func testAlignmentAcceptsAssignedCompatibilityIdeographsAsHan() throws {
        let compatibilityBMP = String(Unicode.Scalar(0xFA6D)!)
        let compatibilitySupplement = String(Unicode.Scalar(0x2FA1D)!)
        let yaml = validVolumeYAML
            .replacingOccurrences(
                of: "translation_zh_tw: \"兩個德文單位在此合成一個對齊句段。\"",
                with: "translation_zh_tw: \"\(compatibilityBMP) translation.\""
            )
            .replacingOccurrences(
                of: "interpretation_zh_tw: \"來源版本的句界不必相同；索引保存多對多關係。\"",
                with: "interpretation_zh_tw: \"\(compatibilitySupplement) interpretation.\""
            )

        let issues = CorpusValidator.validateAlignment(
            manifest: try makeInlineManifest(),
            volumes: [try CorpusYAMLDecoder.decodeVolume(yaml)]
        )

        XCTAssertFalse(issues.contains {
            $0.code == "missing-translation" || $0.code == "missing-interpretation"
        })
    }

    func testDecoratedTODOAndTBDStillCountAsPlaceholders() throws {
        let yaml = validVolumeYAML
            .replacingOccurrences(
                of: "translation_zh_tw: \"兩個德文單位在此合成一個對齊句段。\"",
                with: "translation_zh_tw: \"TODO：2.01\""
            )
            .replacingOccurrences(
                of: "interpretation_zh_tw: \"來源版本的句界不必相同；索引保存多對多關係。\"",
                with: "interpretation_zh_tw: \"TBD：2.01\""
            )
        let volume = try CorpusYAMLDecoder.decodeVolume(yaml)

        let alignmentIssues = CorpusValidator.validateAlignment(
            manifest: try makeInlineManifest(),
            volumes: [volume]
        )

        XCTAssertTrue(alignmentIssues.contains { $0.code == "missing-translation" })
        XCTAssertTrue(alignmentIssues.contains { $0.code == "missing-interpretation" })
    }

    func testAlignmentRejectsCorpusConstructionBoilerplateAsInterpretation() throws {
        let yaml = validVolumeYAML.replacingOccurrences(
            of: "interpretation_zh_tw: \"來源版本的句界不必相同；索引保存多對多關係。\"",
            with: "interpretation_zh_tw: \"此句以譯文片段收束本命題；其意義由命題層摘要補足。\""
        )

        let issues = CorpusValidator.validateAlignment(
            manifest: try makeInlineManifest(),
            volumes: [try CorpusYAMLDecoder.decodeVolume(yaml)]
        )

        XCTAssertTrue(issues.contains {
            $0.code == "generic-interpretation" && $0.recordID == "2.01.a"
        })
    }

    func testAlignmentRequiresExternalReferencesAndRejectsUnknownEditionKeys() throws {
        let missingReference = validVolumeYAML.replacingOccurrences(
            of: "edition_references:\n      en_pears_mcguinness: \"2.01\"",
            with: "edition_references: {}"
        )
        let unknownText = validVolumeYAML.replacingOccurrences(
            of: "texts:\n      de:",
            with: "texts:\n      invented_edition: [\"invented text\"]\n      de:"
        )
        let unknownReference = validVolumeYAML.replacingOccurrences(
            of: "en_pears_mcguinness: \"2.01\"",
            with: "en_pears_mcguinness: \"2.01\"\n      invented_edition: \"2.01\""
        )

        for yaml in [missingReference, unknownText, unknownReference] {
            let issues = CorpusValidator.validateAlignment(
                manifest: try makeInlineManifest(),
                volumes: [try CorpusYAMLDecoder.decodeVolume(yaml)]
            )
            XCTAssertTrue(issues.contains { $0.code == "alignment-gap" }, issues.description)
        }
    }

    func testRelationEnumsExposeEveryClosedContractValue() {
        XCTAssertEqual(Set(RelationStatus.allCases.map(\.rawValue)), Set([
            "implemented", "partial", "aspirational", "analogy_only", "rejected",
            "not_applicable", "intentional_nonconformance",
        ]))
        XCTAssertEqual(Set(RelationMode.allCases.map(\.rawValue)), Set([
            "instance", "structural_invariant", "semantic_operation", "formal_derivation",
            "refusal", "shown_constraint", "meta_elucidation", "declared_nonconformance",
        ]))
    }

    func testRelationAllowsHonestNotApplicableWithoutInventedEvidence() throws {
        let volume = try makeRelationVolume("""
          - status: not_applicable
            claim_zh_tw: "此命題沒有可辯護的專案對應。"
            rationale_zh_tw: "硬套工程類比會把哲學界線誤當成產品功能。"
        """)

        XCTAssertEqual(CorpusValidator.validateRelations(volumes: [volume]), [])
    }

    func testRelationRejectsContradictoryNotApplicableModeOrEvidence() throws {
        let volume = try makeRelationVolume("""
          - status: not_applicable
            mode: instance
            claim_zh_tw: "此命題沒有可辯護的專案對應。"
            rationale_zh_tw: "不適用不能同時聲稱為一個實例。"
            evidence:
              - path: Package.swift
                kind: symbol
                locator: TractatusDocs
        """)

        let issues = CorpusValidator.validateRelations(volumes: [volume])

        XCTAssertTrue(issues.contains { $0.code == "invalid-relation" })
    }

    func testRelationRejectsMissingRelationAndEmptyClaim() throws {
        let noRelation = try makeRelationVolume("")
        let emptyClaim = try makeRelationVolume("""
          - status: not_applicable
            claim_zh_tw: ""
            rationale_zh_tw: "硬套類比會誤導。"
        """)

        let noRelationIssues = CorpusValidator.validateRelations(volumes: [noRelation])
        let emptyClaimIssues = CorpusValidator.validateRelations(volumes: [emptyClaim])

        XCTAssertTrue(noRelationIssues.contains { $0.code == "invalid-relation" })
        XCTAssertTrue(emptyClaimIssues.contains { $0.code == "invalid-relation" })
    }

    func testRelationRejectsDecoratedTODOFields() throws {
        let volume = try makeRelationVolume("""
          - status: not_applicable
            claim_zh_tw: "TODO：命題 1"
            rationale_zh_tw: "TBD：命題 1"
        """)

        let issues = CorpusValidator.validateRelations(volumes: [volume])

        XCTAssertTrue(issues.contains { $0.code == "invalid-relation" })
    }

    func testRelationRejectsRationaleReusedAcrossDifferentPropositions() throws {
        let volume = try CorpusYAMLDecoder.decodeVolume("""
        schema_version: 1
        volume: "1"
        propositions:
          - id: "1"
            texts: {}
            segments: []
            project_relations:
              - status: not_applicable
                claim_zh_tw: "命題 1 沒有可辯護的直接對應。"
                rationale_zh_tw: "硬套工程類比會把哲學條件 冒充產品功能。"
          - id: "1.1"
            parent: "1"
            texts: {}
            segments: []
            project_relations:
              - status: not_applicable
                claim_zh_tw: "命題 1.1 沒有可辯護的直接對應。"
                rationale_zh_tw: "硬套工程類比會把哲學條件  冒充產品功能。"
        """)

        let issues = CorpusValidator.validateRelations(volumes: [volume])

        XCTAssertTrue(issues.contains {
            $0.code == "duplicate-rationale" && $0.recordID == "1.1"
        })
    }

    func testRelationRequiresEvidenceExceptForNotApplicable() throws {
        let volume = try makeRelationVolume("""
          - status: implemented
            mode: instance
            claim_zh_tw: "專案已有具體實例。"
            rationale_zh_tw: "此關係聲稱的是現況，不只是願景。"
            evidence: []
        """)

        let issues = CorpusValidator.validateRelations(volumes: [volume])

        XCTAssertTrue(issues.contains { $0.code == "missing-evidence" })
    }

    func testAspirationalRelationRejectsMissingOrIncompleteGitHubIssueHistory() throws {
        let completeIssueURL = "https://github.com/PsychQuant/Akashic-Library/issues/200"
        let fixtures: [(kind: HistoryReferenceKind?, reference: String?)] = [
            (nil, nil),
            (.issue, "github.com/PsychQuant/Akashic-Library/issues/200"),
            (.issue, "https://github.com/PsychQuant/Akashic-Library/extra/issues/200"),
            (.issue, "https://github.com/PsychQuant/Akashic-Library/issues/0"),
            (.issue, "https://github.com/PsychQuant/Akashic-Library/issues/-1"),
            (.commit, completeIssueURL),
        ]

        for fixture in fixtures {
            let volume = try makeAspirationalRelationVolume(
                historyKind: fixture.kind,
                reference: fixture.reference
            )
            let issues = CorpusValidator.validateRelations(volumes: [volume])
            let diagnostic = try XCTUnwrap(issues.first {
                $0.code == "invalid-relation" && $0.recordID == "5.101"
            }, issues.description)

            XCTAssertTrue(diagnostic.message.contains("GitHub issue"), diagnostic.formatted)
        }
    }

    func testAspirationalRelationAcceptsCompleteGitHubIssueHistory() throws {
        let volume = try makeAspirationalRelationVolume(
            historyKind: .issue,
            reference: "https://github.com/PsychQuant/Akashic-Library/issues/200"
        )

        XCTAssertEqual(CorpusValidator.validateRelations(volumes: [volume]), [])
    }

    func testRelationRejectsUnknownStatusAsInvalidRelation() throws {
        let yaml = try relationVolumeYAML("""
          - status: metaphysically_identical
            mode: instance
            claim_zh_tw: "不應接受。"
            rationale_zh_tw: "不在封閉值域。"
            evidence: []
        """)

        XCTAssertThrowsError(try CorpusYAMLDecoder.decodeVolume(yaml)) { error in
            XCTAssertEqual(error as? CorpusSchemaError, .invalidRelation("metaphysically_identical"))
        }
    }

    func testEvidenceResolvesAProjectRelativePathAndStableSymbol() throws {
        let volume = try makeEvidenceVolume(
            path: "Sources/TractatusDocs/Validation.swift",
            locator: "CorpusValidator"
        )

        XCTAssertEqual(
            CorpusValidator.validateEvidence(volumes: [volume], projectRoot: projectRoot),
            []
        )
    }

    func testEvidenceReportsBrokenPathAndMissingSymbol() throws {
        let broken = try makeEvidenceVolume(
            path: "Sources/TractatusDocs/DoesNotExist.swift",
            locator: "MissingType"
        )
        let missingSymbol = try makeEvidenceVolume(
            path: "Package.swift",
            locator: "ThisSymbolCannotExistInPackageManifest"
        )

        let brokenIssues = CorpusValidator.validateEvidence(
            volumes: [broken],
            projectRoot: projectRoot
        )
        let symbolIssues = CorpusValidator.validateEvidence(
            volumes: [missingSymbol],
            projectRoot: projectRoot
        )

        XCTAssertTrue(brokenIssues.contains { $0.code == "broken-path" })
        XCTAssertTrue(symbolIssues.contains { $0.code == "missing-symbol" })
    }

    func testEvidenceRejectsLocatorThatDoesNotMatchDeclaredKind() throws {
        let volume = try CorpusYAMLDecoder.decodeVolume("""
        schema_version: 1
        volume: "1"
        propositions:
          - id: "1"
            texts: {}
            segments: []
            project_relations:
              - status: implemented
                mode: instance
                claim_zh_tw: "這筆證據假稱指向測試。"
                rationale_zh_tw: "普通子字串不能冒充穩定的測試定位點。"
                evidence:
                  - path: Package.swift
                    kind: test
                    locator: import
        """)

        let issues = CorpusValidator.validateEvidence(
            volumes: [volume],
            projectRoot: projectRoot
        )

        XCTAssertTrue(issues.contains { $0.code == "invalid-evidence" })
    }

    func testEvidenceRejectsSwiftDeclarationsInsideCommentsAndStrings() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("tractatus-evidence-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let sources = root.appendingPathComponent("Sources", isDirectory: true)
        let tests = root.appendingPathComponent("Tests", isDirectory: true)
        try FileManager.default.createDirectory(at: sources, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: tests, withIntermediateDirectories: true)
        try #"""
        // struct LineCommentSymbol {}
        /* outer /* struct NestedBlockSymbol {} */ outer */
        let ordinary = "struct OrdinaryStringSymbol {}"
        let multiline = """
        struct MultilineStringSymbol {}
        """
        let raw = #"struct RawStringSymbol {}"#
        let interpolated = "value \(render("struct InterpolatedStringSymbol {}"))"
        """#.write(
            to: sources.appendingPathComponent("Fake.swift"),
            atomically: true,
            encoding: .utf8
        )
        try #"""
        // func testLineCommentOnly() {}
        /* outer /* func testNestedBlockOnly() {} */ outer */
        let ordinary = "func testOrdinaryStringOnly() {}"
        let multiline = """
        func testMultilineStringOnly() {}
        """
        let raw = #"func testRawStringOnly() {}"#
        let interpolated = "value \(render("func testInterpolatedStringOnly() {}"))"
        """#.write(
            to: tests.appendingPathComponent("FakeTests.swift"),
            atomically: true,
            encoding: .utf8
        )

        for locator in [
            "LineCommentSymbol",
            "NestedBlockSymbol",
            "OrdinaryStringSymbol",
            "MultilineStringSymbol",
            "RawStringSymbol",
            "InterpolatedStringSymbol",
        ] {
            let volume = try makeEvidenceVolume(
                path: "Sources/Fake.swift",
                kind: .symbol,
                locator: locator
            )
            let issues = CorpusValidator.validateEvidence(volumes: [volume], projectRoot: root)
            XCTAssertTrue(
                issues.contains { $0.code == "invalid-evidence" },
                "\(locator) 只存在於註解或字串，不得作為 symbol evidence"
            )
        }
        for locator in [
            "testLineCommentOnly",
            "testNestedBlockOnly",
            "testOrdinaryStringOnly",
            "testMultilineStringOnly",
            "testRawStringOnly",
            "testInterpolatedStringOnly",
        ] {
            let volume = try makeEvidenceVolume(
                path: "Tests/FakeTests.swift",
                kind: .test,
                locator: locator
            )
            let issues = CorpusValidator.validateEvidence(volumes: [volume], projectRoot: root)
            XCTAssertTrue(
                issues.contains { $0.code == "invalid-evidence" },
                "\(locator) 只存在於註解或字串，不得作為 test evidence"
            )
        }
    }

    func testEvidenceRequiresExactRequirementName() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("tractatus-requirement-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let specs = root.appendingPathComponent("openspec/specs/fake", isDirectory: true)
        try FileManager.default.createDirectory(at: specs, withIntermediateDirectories: true)
        try "### Requirement: Stable evidence name with suffix\n".write(
            to: specs.appendingPathComponent("spec.md"),
            atomically: true,
            encoding: .utf8
        )
        let volume = try makeEvidenceVolume(
            path: "openspec/specs/fake/spec.md",
            kind: .requirement,
            locator: "Stable evidence name"
        )

        let issues = CorpusValidator.validateEvidence(volumes: [volume], projectRoot: root)

        XCTAssertTrue(issues.contains { $0.code == "invalid-evidence" })
    }

    func testEvidenceAcceptsStructuralSymbolTestAndExactRequirementLocators() throws {
        let fixtures: [(String, EvidenceLocatorKind, String)] = [
            ("Sources/TractatusDocs/Validation.swift", .symbol, "CorpusValidator"),
            (
                "Tests/TractatusDocsTests/CorpusValidationTests.swift",
                .test,
                "testEvidenceAcceptsStructuralSymbolTestAndExactRequirementLocators"
            ),
            (
                "openspec/specs/tractatus-project-map/spec.md",
                .requirement,
                "Current evidence and historical context SHALL remain separate"
            ),
        ]

        for (path, kind, locator) in fixtures {
            let volume = try makeEvidenceVolume(path: path, kind: kind, locator: locator)
            XCTAssertEqual(
                CorpusValidator.validateEvidence(volumes: [volume], projectRoot: projectRoot),
                [],
                "\(kind.rawValue) \(locator) 應解析為結構化定位點"
            )
        }
    }

    func testEvidenceRejectsCanonicalCorpusAsSelfSupportingSource() throws {
        let volume = try CorpusYAMLDecoder.decodeVolume("""
        schema_version: 1
        volume: "1"
        propositions:
          - id: "1"
            texts: {}
            segments: []
            project_relations:
              - status: implemented
                mode: instance
                claim_zh_tw: "語料不能自己證成這項關係。"
                rationale_zh_tw: "否則任何 project relation 都能循環地引用自身。"
                evidence:
                  - path: docs/tractatus/corpus/1.yaml
                    kind: symbol
                    locator: project_relations
        """)

        let issues = CorpusValidator.validateEvidence(
            volumes: [volume],
            projectRoot: projectRoot
        )

        XCTAssertTrue(issues.contains { $0.code == "invalid-evidence" })
    }

    func testHistoryReportsCommitThatCannotResolveLocally() throws {
        let volume = try CorpusYAMLDecoder.decodeVolume("""
        schema_version: 1
        volume: "1"
        propositions:
          - id: "1"
            texts: {}
            segments: []
            project_relations:
              - status: not_applicable
                claim_zh_tw: "無直接對應。"
                rationale_zh_tw: "不應硬套類比。"
            history:
              - kind: commit
                reference: "ffffffffffffffffffffffffffffffffffffffff"
                disposition: rejected
                note_zh_tw: "不存在的 fixture commit。"
        """)

        let issues = CorpusValidator.validateEvidence(volumes: [volume], projectRoot: projectRoot)

        XCTAssertTrue(issues.contains { $0.code == "unknown-commit" })
    }

    func testHistoryReportsBranchThatCannotResolveLocally() throws {
        let volume = try makeHistoryVolume(
            kind: .branch,
            reference: "codex/nonexistent-branch-validation-audit"
        )

        let issues = CorpusValidator.validateEvidence(
            volumes: [volume],
            projectRoot: projectRoot
        )

        XCTAssertTrue(issues.contains {
            $0.code == "unknown-branch" && $0.recordID == "1"
        })
    }

    func testHistoryAcceptsResolvableBranchThatIsNotMainAncestor() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("tractatus-branch-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let sideBranch = "branch-audit-\(UUID().uuidString.lowercased())"
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        XCTAssertEqual(try runGit(["init", "--quiet", "--initial-branch=main"], at: root), 0)
        try "main\n".write(
            to: root.appendingPathComponent("main.txt"),
            atomically: true,
            encoding: .utf8
        )
        XCTAssertEqual(try runGit(["add", "main.txt"], at: root), 0)
        XCTAssertEqual(try runGit([
            "-c", "user.name=Tractatus Fixture",
            "-c", "user.email=tractatus@example.invalid",
            "commit", "--quiet", "-m", "main fixture",
        ], at: root), 0)
        XCTAssertEqual(try runGit(["switch", "--quiet", "-c", sideBranch], at: root), 0)
        try "side\n".write(
            to: root.appendingPathComponent("side.txt"),
            atomically: true,
            encoding: .utf8
        )
        XCTAssertEqual(try runGit(["add", "side.txt"], at: root), 0)
        XCTAssertEqual(try runGit([
            "-c", "user.name=Tractatus Fixture",
            "-c", "user.email=tractatus@example.invalid",
            "commit", "--quiet", "-m", "side fixture",
        ], at: root), 0)
        XCTAssertEqual(try runGit(["switch", "--quiet", "main"], at: root), 0)
        XCTAssertNotEqual(
            try runGit(["merge-base", "--is-ancestor", sideBranch, "main"], at: root),
            0
        )
        for reference in [sideBranch, "refs/heads/\(sideBranch)"] {
            let volume = try makeHistoryVolume(kind: .branch, reference: reference)
            XCTAssertEqual(
                CorpusValidator.validateEvidence(volumes: [volume], projectRoot: root),
                []
            )
        }
    }

    func testHistoryBranchKindRejectsCommitishReferencesOutsideBranchNamespaces() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("tractatus-branch-kind-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let tagName = "branch-audit-tag-\(UUID().uuidString.lowercased())"
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        XCTAssertEqual(try runGit(["init", "--quiet", "--initial-branch=main"], at: root), 0)
        try "fixture\n".write(
            to: root.appendingPathComponent("fixture.txt"),
            atomically: true,
            encoding: .utf8
        )
        XCTAssertEqual(try runGit(["add", "fixture.txt"], at: root), 0)
        XCTAssertEqual(try runGit([
            "-c", "user.name=Tractatus Fixture",
            "-c", "user.email=tractatus@example.invalid",
            "commit", "--quiet", "-m", "branch-kind fixture",
        ], at: root), 0)
        XCTAssertEqual(try runGit(["tag", tagName], at: root), 0)
        let commitSHA = try gitOutput(["rev-parse", "HEAD"], at: root)

        for reference in [commitSHA, tagName, "refs/tags/\(tagName)", "HEAD"] {
            let issues = CorpusValidator.validateEvidence(
                volumes: [try makeHistoryVolume(kind: .branch, reference: reference)],
                projectRoot: root
            )

            XCTAssertTrue(issues.contains {
                $0.code == "unknown-branch" && $0.recordID == "1"
            }, "branch history 不得接受非 branch ref：\(reference)")
        }
    }

    func testHistoryAcceptsResolvableRemoteTrackingBranch() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("tractatus-remote-branch-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let remoteBranch = "origin/branch-audit-\(UUID().uuidString.lowercased())"
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        XCTAssertEqual(try runGit(["init", "--quiet", "--initial-branch=main"], at: root), 0)
        try "fixture\n".write(
            to: root.appendingPathComponent("fixture.txt"),
            atomically: true,
            encoding: .utf8
        )
        XCTAssertEqual(try runGit(["add", "fixture.txt"], at: root), 0)
        XCTAssertEqual(try runGit([
            "-c", "user.name=Tractatus Fixture",
            "-c", "user.email=tractatus@example.invalid",
            "commit", "--quiet", "-m", "remote branch fixture",
        ], at: root), 0)
        XCTAssertEqual(
            try runGit(["update-ref", "refs/remotes/\(remoteBranch)", "HEAD"], at: root),
            0
        )
        for reference in [remoteBranch, "refs/remotes/\(remoteBranch)"] {
            let volume = try makeHistoryVolume(kind: .branch, reference: reference)
            XCTAssertEqual(
                CorpusValidator.validateEvidence(volumes: [volume], projectRoot: root),
                []
            )
        }
    }

    func testGeneratedDocumentCannotBeLoadBearingCurrentEvidence() throws {
        let volume = try makeEvidenceVolume(
            path: "docs/tractatus/generated/tractatus-project-map.md",
            locator: "1"
        )

        let issues = CorpusValidator.validateEvidence(volumes: [volume], projectRoot: projectRoot)

        XCTAssertTrue(issues.contains { $0.code == "broken-path" })
    }

    func testReferencedSourceImagesMustExistInTheOfflineAssetDirectory() throws {
        let volume = try CorpusYAMLDecoder.decodeVolume("""
        schema_version: 1
        volume: "5"
        propositions:
          - id: "5"
            texts:
              de: ["Eine Abbildung: ![{ [x] }](images/missing.svg)"]
              en_ogden_ramsey_1922: ["A figure: ![{ [x] }](images/missing.svg)"]
            edition_references:
              en_pears_mcguinness: "5"
            segments: []
            project_relations: []
        """)
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("tractatus-assets-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let issues = CorpusValidator.validateAssets(volumes: [volume], root: root)

        XCTAssertTrue(issues.contains {
            $0.code == "broken-path" && $0.recordID == "5"
        })
    }

    func testReferencedSourceImageDigestMustMatchTheOfflineManifest() throws {
        let volume = try CorpusYAMLDecoder.decodeVolume("""
        schema_version: 1
        volume: "5"
        propositions:
          - id: "5"
            texts:
              de: ["![](images/proof.svg)"]
              en_ogden_ramsey_1922: ["![](images/proof.svg)"]
            edition_references:
              en_pears_mcguinness: "5"
            segments: []
            project_relations: []
        """)
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("tractatus-assets-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let assets = root.appendingPathComponent("source-assets", isDirectory: true)
        let images = assets.appendingPathComponent("images", isDirectory: true)
        try FileManager.default.createDirectory(at: images, withIntermediateDirectories: true)
        try Data("tampered".utf8).write(to: images.appendingPathComponent("proof.svg"))
        let zeros = String(repeating: "0", count: 64)
        try Data("\(zeros)  images/proof.svg\n".utf8)
            .write(to: assets.appendingPathComponent("SHA256SUMS"))

        let issues = CorpusValidator.validateAssets(volumes: [volume], root: root)

        XCTAssertTrue(issues.contains {
            $0.code == "digest-mismatch" && $0.recordID == "5"
        })
    }

    func testAssetManifestAndReferencedImageHaveFixedByteLimits() throws {
        let volume = try CorpusYAMLDecoder.decodeVolume("""
        schema_version: 1
        volume: "5"
        propositions:
          - id: "5"
            texts:
              de: ["![](images/proof.svg)"]
              en_ogden_ramsey_1922: ["![](images/proof.svg)"]
            edition_references:
              en_pears_mcguinness: "5"
            segments: []
            project_relations: []
        """)
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("tractatus-asset-limits-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let assets = root.appendingPathComponent("source-assets", isDirectory: true)
        let images = assets.appendingPathComponent("images", isDirectory: true)
        try FileManager.default.createDirectory(at: images, withIntermediateDirectories: true)
        let checksumURL = assets.appendingPathComponent("SHA256SUMS")
        let imageURL = images.appendingPathComponent("proof.svg")

        try Data(repeating: 0x20, count: CorpusResourceLimits.maximumAssetManifestUTF8Bytes + 1)
            .write(to: checksumURL)
        try Data("proof".utf8).write(to: imageURL)
        XCTAssertEqual(
            CorpusValidator.validateAssets(volumes: [volume], root: root)
                .map(\.code),
            ["resource-limit"]
        )

        let zeros = String(repeating: "0", count: 64)
        try Data("\(zeros)  images/proof.svg\n".utf8).write(to: checksumURL)
        try Data(
            repeating: 0x41,
            count: CorpusResourceLimits.maximumReferencedAssetBytes + 1
        ).write(to: imageURL)
        XCTAssertEqual(
            CorpusValidator.validateAssets(volumes: [volume], root: root)
                .map(\.code),
            ["resource-limit"]
        )
    }

    func testCanonicalAssetPathIsCapturedOnceAcrossRawAliasesAndPropositions() throws {
        let volume = try CorpusYAMLDecoder.decodeVolume("""
        schema_version: 1
        volume: "5"
        propositions:
          - id: "5"
            texts:
              de: ["![](images/a/../proof.svg)"]
              en_ogden_ramsey_1922: ["proof"]
            edition_references:
              en_pears_mcguinness: "5"
            segments: []
            project_relations: []
          - id: "5.01"
            texts:
              de: ["![](images/b/../proof.svg)"]
              en_ogden_ramsey_1922: ["proof"]
            edition_references:
              en_pears_mcguinness: "5.01"
            segments: []
            project_relations: []
        """)
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("tractatus-asset-cache-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let assets = root.appendingPathComponent("source-assets", isDirectory: true)
        let images = assets.appendingPathComponent("images", isDirectory: true)
        try FileManager.default.createDirectory(at: images, withIntermediateDirectories: true)
        let data = Data("proof".utf8)
        try data.write(to: images.appendingPathComponent("proof.svg"))
        let digest = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        try Data("""
        \(digest)  images/a/../proof.svg
        \(digest)  images/b/../proof.svg

        """.utf8).write(to: assets.appendingPathComponent("SHA256SUMS"))
        var captureCount = 0

        let issues = CorpusValidator.validateAssets(
            volumes: [volume],
            root: root,
            maximumTotalBytes: CorpusResourceLimits.maximumTotalReferencedAssetBytes,
            maximumReferenceCount: CorpusResourceLimits.maximumReferencedAssetReferences,
            assetLoader: { candidate, maximumBytes in
                captureCount += 1
                return try exactlyBoundedFileData(
                    contentsOf: candidate,
                    maximumBytes: maximumBytes,
                    kind: "referenced-asset-bytes"
                )
            }
        )

        XCTAssertEqual(issues, [])
        XCTAssertEqual(captureCount, 1)
    }

    func testTotalAssetCaptureLimitStopsLaterReadsAfterFirstOverflow() throws {
        let volume = try CorpusYAMLDecoder.decodeVolume("""
        schema_version: 1
        volume: "5"
        propositions:
          - id: "5"
            texts:
              de: ["![](images/a.svg)"]
              en_ogden_ramsey_1922: ["a"]
            edition_references:
              en_pears_mcguinness: "5"
            segments: []
            project_relations: []
          - id: "5.01"
            texts:
              de: ["![](images/b.svg)"]
              en_ogden_ramsey_1922: ["b"]
            edition_references:
              en_pears_mcguinness: "5.01"
            segments: []
            project_relations: []
          - id: "5.02"
            texts:
              de: ["![](images/c.svg)"]
              en_ogden_ramsey_1922: ["c"]
            edition_references:
              en_pears_mcguinness: "5.02"
            segments: []
            project_relations: []
        """)
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("tractatus-asset-total-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let assets = root.appendingPathComponent("source-assets", isDirectory: true)
        let images = assets.appendingPathComponent("images", isDirectory: true)
        try FileManager.default.createDirectory(at: images, withIntermediateDirectories: true)
        let captured = Data("ok".utf8)
        let digest = SHA256.hash(data: captured).map { String(format: "%02x", $0) }.joined()
        for name in ["a.svg", "b.svg", "c.svg"] {
            try Data().write(to: images.appendingPathComponent(name))
        }
        try Data("""
        \(digest)  images/a.svg
        \(digest)  images/b.svg
        \(digest)  images/c.svg

        """.utf8).write(to: assets.appendingPathComponent("SHA256SUMS"))
        var captureCount = 0
        var capturedByteCount = 0
        var requestedLimits: [Int] = []

        let issues = CorpusValidator.validateAssets(
            volumes: [volume],
            root: root,
            maximumTotalBytes: 3,
            maximumReferenceCount: CorpusResourceLimits.maximumReferencedAssetReferences,
            assetLoader: { _, maximumBytes in
                captureCount += 1
                requestedLimits.append(maximumBytes)
                guard captured.count <= maximumBytes else {
                    throw CorpusSchemaError.resourceLimit(
                        kind: "referenced-asset-bytes",
                        actual: captured.count,
                        maximum: maximumBytes
                    )
                }
                capturedByteCount += captured.count
                return captured
            }
        )

        XCTAssertEqual(issues.map(\.code), ["resource-limit", "resource-limit"])
        XCTAssertTrue(issues.allSatisfy {
            $0.message.contains("referenced-assets-total-bytes")
        })
        XCTAssertEqual(captureCount, 2)
        XCTAssertEqual(capturedByteCount, 2)
        XCTAssertEqual(requestedLimits, [3, 1])
    }

    func testReferencedImageCountFailsBeforeAnyPathOrAssetWork() throws {
        let volume = try CorpusYAMLDecoder.decodeVolume("""
        schema_version: 1
        volume: "5"
        propositions:
          - id: "5"
            texts:
              de: ["![](images/a.svg) ![](images/b.svg) ![](images/c.svg)"]
              en_ogden_ramsey_1922: ["bounded"]
            edition_references:
              en_pears_mcguinness: "5"
            segments: []
            project_relations: []
        """)
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("tractatus-asset-reference-limit-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let assets = root.appendingPathComponent("source-assets", isDirectory: true)
        let images = assets.appendingPathComponent("images", isDirectory: true)
        try FileManager.default.createDirectory(at: images, withIntermediateDirectories: true)
        let data = Data("asset".utf8)
        let digest = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        for name in ["a.svg", "b.svg", "c.svg"] {
            try data.write(to: images.appendingPathComponent(name))
        }
        try Data("""
        \(digest)  images/a.svg
        \(digest)  images/b.svg
        \(digest)  images/c.svg

        """.utf8).write(to: assets.appendingPathComponent("SHA256SUMS"))
        var captureCount = 0

        let issues = CorpusValidator.validateAssets(
            volumes: [volume],
            root: root,
            maximumTotalBytes: CorpusResourceLimits.maximumTotalReferencedAssetBytes,
            maximumReferenceCount: 2,
            assetLoader: { _, _ in
                captureCount += 1
                return data
            }
        )

        XCTAssertEqual(issues.map(\.code), ["resource-limit"])
        XCTAssertTrue(issues[0].message.contains("referenced-asset-references"))
        XCTAssertEqual(captureCount, 0)
    }

    func testReferencedImageAndAggregateAssetConstantsAreLoadBearing() throws {
        XCTAssertEqual(
            CorpusResourceLimits.maximumTotalReferencedAssetBytes,
            64 * 1024 * 1024
        )
        XCTAssertEqual(CorpusResourceLimits.maximumReferencedAssetReferences, 4_096)

        let reference = "![](images/proof.svg) "
        let boundary = String(
            repeating: reference,
            count: CorpusResourceLimits.maximumReferencedAssetReferences
        )
        XCTAssertEqual(
            try MarkdownImageReferenceParser.references(
                in: boundary,
                maximumCount: CorpusResourceLimits.maximumReferencedAssetReferences
            ).count,
            4_096
        )

        let excess = boundary + reference
        XCTAssertThrowsError(
            try MarkdownImageReferenceParser.references(
                in: excess,
                maximumCount: CorpusResourceLimits.maximumReferencedAssetReferences
            )
        ) { error in
            XCTAssertEqual(
                error as? CorpusSchemaError,
                .resourceLimit(
                    kind: "referenced-asset-references",
                    actual: 4_097,
                    maximum: 4_096
                )
            )
        }
    }

    func testSourceAssetsRootCannotEscapeCorpusThroughSymlink() throws {
        let volume = try CorpusYAMLDecoder.decodeVolume("""
        schema_version: 1
        volume: "5"
        propositions:
          - id: "5"
            texts:
              de: ["![](images/proof.svg)"]
              en_ogden_ramsey_1922: ["proof"]
            edition_references:
              en_pears_mcguinness: "5"
            segments: []
            project_relations: []
        """)
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("tractatus-asset-root-\(UUID().uuidString)")
        let external = FileManager.default.temporaryDirectory
            .appendingPathComponent("tractatus-asset-external-\(UUID().uuidString)")
        defer {
            try? FileManager.default.removeItem(at: root)
            try? FileManager.default.removeItem(at: external)
        }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let images = external.appendingPathComponent("images", isDirectory: true)
        try FileManager.default.createDirectory(at: images, withIntermediateDirectories: true)
        let data = Data("proof".utf8)
        try data.write(to: images.appendingPathComponent("proof.svg"))
        let digest = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        try Data("\(digest)  images/proof.svg\n".utf8)
            .write(to: external.appendingPathComponent("SHA256SUMS"))
        try FileManager.default.createSymbolicLink(
            at: root.appendingPathComponent("source-assets"),
            withDestinationURL: external
        )

        let issues = CorpusValidator.validateAssets(volumes: [volume], root: root)

        XCTAssertEqual(issues.map(\.code), ["broken-path"])
        XCTAssertTrue(issues[0].message.contains("source-assets"))
    }

    func testAssetManifestCannotEscapeSourceAssetsThroughSymlink() throws {
        let volume = try CorpusYAMLDecoder.decodeVolume("""
        schema_version: 1
        volume: "5"
        propositions:
          - id: "5"
            texts:
              de: ["![](images/proof.svg)"]
              en_ogden_ramsey_1922: ["proof"]
            edition_references:
              en_pears_mcguinness: "5"
            segments: []
            project_relations: []
        """)
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("tractatus-manifest-root-\(UUID().uuidString)")
        let externalManifest = FileManager.default.temporaryDirectory
            .appendingPathComponent("tractatus-manifest-external-\(UUID().uuidString)")
        defer {
            try? FileManager.default.removeItem(at: root)
            try? FileManager.default.removeItem(at: externalManifest)
        }
        let images = root.appendingPathComponent("source-assets/images", isDirectory: true)
        try FileManager.default.createDirectory(at: images, withIntermediateDirectories: true)
        let data = Data("proof".utf8)
        try data.write(to: images.appendingPathComponent("proof.svg"))
        let digest = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        try Data("\(digest)  images/proof.svg\n".utf8).write(to: externalManifest)
        try FileManager.default.createSymbolicLink(
            at: root.appendingPathComponent("source-assets/SHA256SUMS"),
            withDestinationURL: externalManifest
        )

        let issues = CorpusValidator.validateAssets(volumes: [volume], root: root)

        XCTAssertEqual(issues.map(\.code), ["broken-path"])
        XCTAssertTrue(issues[0].message.contains("SHA256SUMS"))
    }

    func testOversizedCurrentEvidenceReportsResourceLimitNotBrokenPath() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("tractatus-evidence-limit-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try Data(
            repeating: 0x41,
            count: CorpusResourceLimits.maximumEvidenceFileUTF8Bytes + 1
        ).write(to: root.appendingPathComponent("proof.swift"))
        let volume = try makeEvidenceVolume(path: "proof.swift", locator: "proof")

        XCTAssertEqual(
            CorpusValidator.validateEvidence(volumes: [volume], projectRoot: root)
                .map(\.code),
            ["resource-limit"]
        )
    }

    func testEveryRendererRichTextFieldReportsMissingImagesWithSpaces() throws {
        let volume = try CorpusYAMLDecoder.decodeVolume("""
        schema_version: 1
        volume: "5"
        propositions:
          - id: "5"
            texts:
              de: ["![source](images/source missing.svg)"]
              en_ogden_ramsey_1922: ["Plain source text."]
            edition_references:
              en_pears_mcguinness: "5"
            segments:
              - id: "5.a"
                alignment:
                  de: [0]
                  en_ogden_ramsey_1922: [0]
                translation_zh_tw: "![translation](images/translation missing.svg)"
                interpretation_zh_tw: "![interpretation](images/interpretation missing.svg)"
            project_relations:
              - status: implemented
                mode: instance
                claim_zh_tw: "![claim](images/claim missing.svg)"
                rationale_zh_tw: "![rationale](images/rationale missing.svg)"
                evidence:
                  - path: "Package.swift"
                    kind: symbol
                    locator: "Package"
                    note_zh_tw: "![evidence](images/evidence missing.svg)"
            history:
              - kind: branch
                reference: "fixture/history"
                disposition: retained
                note_zh_tw: "![history](images/history missing.svg)"
        """)
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("tractatus-rich-images-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let expectedReferences = [
            "images/source missing.svg",
            "images/translation missing.svg",
            "images/interpretation missing.svg",
            "images/claim missing.svg",
            "images/rationale missing.svg",
            "images/evidence missing.svg",
            "images/history missing.svg",
        ]

        let issues = CorpusValidator.validateAssets(volumes: [volume], root: root)

        XCTAssertEqual(issues.map(\.code), Array(repeating: "broken-path", count: 7))
        for reference in expectedReferences {
            XCTAssertTrue(
                issues.contains { $0.message.contains(reference) },
                "validator 應掃描 renderer 會處理的 \(reference)"
            )
        }
    }

    func testExistingRichTextImageWithSpacesMustBeListedInChecksumManifest() throws {
        let volume = try CorpusYAMLDecoder.decodeVolume("""
        schema_version: 1
        volume: "5"
        propositions:
          - id: "5"
            texts:
              de: ["Plain source text."]
              en_ogden_ramsey_1922: ["Plain source text."]
            edition_references:
              en_pears_mcguinness: "5"
            segments:
              - id: "5.a"
                alignment:
                  de: [0]
                  en_ogden_ramsey_1922: [0]
                translation_zh_tw: "![unlisted](images/unlisted figure.svg)"
                interpretation_zh_tw: "此圖仍須經 checksum 驗證。"
            project_relations: []
            history: []
        """)
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("tractatus-unlisted-image-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let images = root.appendingPathComponent("source-assets/images", isDirectory: true)
        try FileManager.default.createDirectory(at: images, withIntermediateDirectories: true)
        try Data("fixture".utf8).write(
            to: images.appendingPathComponent("unlisted figure.svg")
        )
        try Data().write(
            to: root.appendingPathComponent("source-assets/SHA256SUMS")
        )

        let issues = CorpusValidator.validateAssets(volumes: [volume], root: root)

        XCTAssertEqual(issues.map(\.code), ["digest-mismatch"])
        XCTAssertTrue(issues.first?.message.contains("images/unlisted figure.svg") == true)
    }

    func testForbiddenEvidencePathsCannotUseDotSegmentsToBypassPolicy() throws {
        let generated = try evidenceHeadingVolume(
            path: "docs/tractatus/./generated/tractatus-project-map.md",
            heading: "# 《邏輯哲學論》× Akashic-Library 逐條對照"
        )
        let snapshot = try evidenceHeadingVolume(
            path: "docs/tractatus/./source-snapshots/de-wittgenstein-project.md",
            heading: "## Vorwort"
        )

        let generatedIssues = CorpusValidator.validateEvidence(
            volumes: [generated],
            projectRoot: projectRoot
        )
        let snapshotIssues = CorpusValidator.validateEvidence(
            volumes: [snapshot],
            projectRoot: projectRoot
        )

        XCTAssertTrue(generatedIssues.contains { $0.code == "broken-path" })
        XCTAssertTrue(snapshotIssues.contains { $0.code == "invalid-evidence" })
    }

    private let validVolumeYAML = """
    schema_version: 1
    volume: "2"
    propositions:
      - id: "2.01"
        parent: "2"
        texts:
          de:
            - "Ein erster Satz."
            - "Ein zweiter Satz."
          en_ogden_ramsey_1922:
            - "Two German units align here."
        edition_references:
          en_pears_mcguinness: "2.01"
        segments:
          - id: "2.01.a"
            alignment:
              de: [0, 1]
              en_ogden_ramsey_1922: [0]
            translation_zh_tw: "兩個德文單位在此合成一個對齊句段。"
            interpretation_zh_tw: "來源版本的句界不必相同；索引保存多對多關係。"
        synthesis_zh_tw: "命題層可有綜合說明。"
        project_relations: []
        history: []
    """

    private var canonicalRootIDs: [String] {
        ["preface.1", "1", "2", "3", "4", "5", "6", "7"]
    }

    private func makeManifest(inventory: [String]) throws -> SourceManifest {
        let quotedInventory = inventory.map { "\"\($0)\"" }.joined(separator: ", ")
        return try SourceManifestYAMLDecoder.decode("""
        schema_version: 1
        scope:
          inventory: [\(quotedInventory)]
          dedication: "dedication metadata"
          motto:
            text: "motto metadata"
            attribution: "attribution metadata"
          excluded: [russell_introduction, index]
        editions: []
        """)
    }

    private func makeInlineManifest() throws -> SourceManifest {
        try SourceManifestYAMLDecoder.decode("""
        schema_version: 1
        scope:
          inventory: ["2.01"]
          dedication: "dedication metadata"
          motto:
            text: "motto metadata"
            attribution: "attribution metadata"
          excluded: [russell_introduction, index]
        editions:
          - id: de
            role: original
            language: de
            bibliography: "German fixture"
            source_url: "https://example.invalid/de"
            retrieval_date: "2026-08-08"
            upstream_revision: "fixture"
            sha256: "0000000000000000000000000000000000000000000000000000000000000000"
            copyright_status: public_domain
            rights_note: "Fixture only."
            inclusion_mode: inline
            snapshot: source-snapshots/de.md
          - id: en_ogden_ramsey_1922
            role: translation
            language: en
            bibliography: "English fixture"
            source_url: "https://example.invalid/en"
            retrieval_date: "2026-08-08"
            upstream_revision: "fixture"
            sha256: "0000000000000000000000000000000000000000000000000000000000000000"
            copyright_status: public_domain
            rights_note: "Fixture only."
            inclusion_mode: inline
            snapshot: source-snapshots/en.md
          - id: en_pears_mcguinness
            role: translation
            language: en
            bibliography: "External fixture"
            source_url: "https://example.invalid/reference"
            retrieval_date: "2026-08-08"
            upstream_revision: "fixture"
            sha256: "0000000000000000000000000000000000000000000000000000000000000000"
            copyright_status: copyrighted
            rights_note: "Reference only."
            inclusion_mode: external_reference
        """)
    }

    private func makeBaselineVolumes() throws -> [CorpusVolume] {
        try [
            makeVolume("preface", records: [("preface.1", nil)]),
            makeVolume("1", records: [("1", nil)]),
            makeVolume("2", records: [("2", nil)]),
            makeVolume("3", records: [("3", nil)]),
            makeVolume("4", records: [("4", nil)]),
            makeVolume("5", records: [("5", nil)]),
            makeVolume("6", records: [("6", nil)]),
            makeVolume("7", records: [("7", nil)]),
        ]
    }

    private func makeVolume(
        _ name: String,
        records: [(id: String, parent: String?)]
    ) throws -> CorpusVolume {
        let body = records.map { record in
            let parent = record.parent.map { "\n    parent: \"\($0)\"" } ?? ""
            return """
              - id: "\(record.id)"\(parent)
                texts: {}
                segments: []
            """
        }.joined(separator: "\n")
        return try CorpusYAMLDecoder.decodeVolume("""
        schema_version: 1
        volume: "\(name)"
        propositions:
        \(body)
        """)
    }

    private func makeRelationVolume(_ relations: String) throws -> CorpusVolume {
        try CorpusYAMLDecoder.decodeVolume(relationVolumeYAML(relations))
    }

    private func relationVolumeYAML(_ relations: String) throws -> String {
        let relationLines = relations.isEmpty
            ? "[]"
            : "\n" + relations.split(separator: "\n", omittingEmptySubsequences: false)
                .map { "    " + $0 }
                .joined(separator: "\n")
        return """
        schema_version: 1
        volume: "1"
        propositions:
          - id: "1"
            texts: {}
            segments: []
            project_relations: \(relationLines)
            history: []
        """
    }

    private func makeEvidenceVolume(
        path: String,
        kind: EvidenceLocatorKind = .symbol,
        locator: String
    ) throws -> CorpusVolume {
        try CorpusYAMLDecoder.decodeVolume("""
        schema_version: 1
        volume: "1"
        propositions:
          - id: "1"
            texts: {}
            segments: []
            project_relations:
              - status: implemented
                mode: instance
                claim_zh_tw: "此主張有現況證據。"
                rationale_zh_tw: "定位點必須能在專案檔案中解析。"
                evidence:
                  - path: "\(path)"
                    kind: \(kind.rawValue)
                    locator: "\(locator)"
            history: []
        """)
    }

    private func makeAspirationalRelationVolume(
        historyKind: HistoryReferenceKind?,
        reference: String?
    ) throws -> CorpusVolume {
        let history: String
        if let historyKind, let reference {
            history = "\n      - kind: \(historyKind.rawValue)"
                + "\n        reference: \"\(reference)\""
                + "\n        disposition: retained"
                + "\n        note_zh_tw: \"此參照追蹤尚未完成的真值函數組合。\""
        } else {
            history = "[]"
        }

        return try CorpusYAMLDecoder.decodeVolume("""
        schema_version: 1
        volume: "5"
        propositions:
          - id: "5.101"
            parent: "5.1"
            texts: {}
            segments: []
            project_relations:
              - status: aspirational
                mode: semantic_operation
                claim_zh_tw: "專案仍需真值函數組合能力。"
                rationale_zh_tw: "命題 5.101 的真值模式尚無完整的組合求值器。"
                evidence:
                  - path: Sources/TractatusDocs/Validation.swift
                    kind: symbol
                    locator: CorpusValidator
            history: \(history)
        """)
    }

    private func makeHistoryVolume(
        kind: HistoryReferenceKind,
        reference: String
    ) throws -> CorpusVolume {
        try CorpusYAMLDecoder.decodeVolume("""
        schema_version: 1
        volume: "1"
        propositions:
          - id: "1"
            texts: {}
            segments: []
            project_relations:
              - status: not_applicable
                claim_zh_tw: "此 fixture 不建立現況專案對應。"
                rationale_zh_tw: "本測試只驗證歷史參照，不以歷史證成現況。"
            history:
              - kind: \(kind.rawValue)
                reference: "\(reference)"
                disposition: retained
                note_zh_tw: "此參照只保存可稽核的歷史脈絡。"
        """)
    }

    @discardableResult
    private func runGit(_ arguments: [String], at root: URL) throws -> Int32 {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["git", "-C", root.path] + arguments
        process.standardOutput = Pipe()
        process.standardError = Pipe()
        try process.run()
        process.waitUntilExit()
        return process.terminationStatus
    }

    private func gitOutput(_ arguments: [String], at root: URL) throws -> String {
        let process = Process()
        let output = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["git", "-C", root.path] + arguments
        process.standardOutput = output
        process.standardError = Pipe()
        try process.run()
        process.waitUntilExit()
        XCTAssertEqual(process.terminationStatus, 0)
        return String(
            decoding: output.fileHandleForReading.readDataToEndOfFile(),
            as: UTF8.self
        ).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func evidenceHeadingVolume(path: String, heading: String) throws -> CorpusVolume {
        try CorpusYAMLDecoder.decodeVolume("""
        schema_version: 1
        volume: "1"
        propositions:
          - id: "1"
            texts: {}
            segments: []
            project_relations:
              - status: implemented
                mode: instance
                claim_zh_tw: "此主張假稱有文件證據。"
                rationale_zh_tw: "禁止路徑不能以點號片段繞過。"
                evidence:
                  - path: "\(path)"
                    kind: heading
                    locator: "\(heading)"
            history: []
        """)
    }

    private var projectRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }
}
