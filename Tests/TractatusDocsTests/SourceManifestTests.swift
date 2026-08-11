import CryptoKit
import Foundation
import XCTest
@testable import TractatusDocs

final class SourceManifestTests: XCTestCase {
    func testRepositoryManifestPinsCompleteAuthorialScopeAndOfflineSources() throws {
        let root = repositoryRoot.appendingPathComponent("docs/tractatus", isDirectory: true)
        let manifest = try SourceManifestYAMLDecoder.decode(
            contentsOf: root.appendingPathComponent("sources.yaml")
        )

        XCTAssertEqual(manifest.schemaVersion, 1)
        XCTAssertEqual(manifest.scope.inventory.count, 534)
        XCTAssertEqual(
            Array(manifest.scope.inventory.prefix(8)),
            (1...8).map { "preface.\($0)" }
        )
        XCTAssertEqual(
            manifest.scope.inventory.filter { !$0.hasPrefix("preface.") }.count,
            526
        )
        XCTAssertEqual(manifest.scope.inventory.last, "7")
        let inventoryIDs = try manifest.scope.inventory.map(PropositionID.init(validating:))
        XCTAssertEqual(inventoryIDs, inventoryIDs.sorted())
        let inventorySet = Set(inventoryIDs)
        let orphaned = inventoryIDs.compactMap { id -> String? in
            guard let parent = id.inferredParent, !inventorySet.contains(parent) else { return nil }
            return "\(id.rawValue)->\(parent.rawValue)"
        }
        XCTAssertEqual(orphaned, [])
        XCTAssertEqual(
            manifest.scope.excluded,
            ["russell_introduction", "index"]
        )
        XCTAssertEqual(
            manifest.scope.dedication,
            "Dem Andenken meines Freundes DAVID H. PINSENT gewidmet"
        )
        XCTAssertTrue(manifest.scope.motto.text.hasPrefix(". . . und alles"))
        XCTAssertTrue(manifest.scope.motto.text.contains("in drei Worten sagen"))
        XCTAssertEqual(manifest.scope.motto.attribution, "Kürnberger")
        XCTAssertEqual(
            manifest.editions.map(\.id),
            ["de", "en_ogden_ramsey_1922", "en_pears_mcguinness"]
        )
        XCTAssertEqual(
            manifest.editions.map(\.inclusionMode),
            [.inline, .inline, .externalReference]
        )
        XCTAssertEqual(
            SourceManifestValidator.validate(manifest, root: root, volumes: []),
            []
        )
        let numberedInventory = Array(manifest.scope.inventory.dropFirst(8))
        let german = try String(
            contentsOf: root.appendingPathComponent(
                "source-snapshots/de-wittgenstein-project.md"
            ),
            encoding: .utf8
        )
        let english = try String(
            contentsOf: root.appendingPathComponent(
                "source-snapshots/en-ogden-ramsey-1922-wittgenstein-project.md"
            ),
            encoding: .utf8
        )
        XCTAssertEqual(
            numberedInventory,
            captures(in: german, pattern: #"(?m)^\*\*([1-7](?:\.[0-9]+)*)\*\*"#)
        )
        XCTAssertEqual(
            numberedInventory,
            captures(in: english, pattern: #"(?m)^\*\*\[([1-7](?:\.[0-9]+)*)\]\("#)
        )
        XCTAssertTrue(
            FileManager.default.fileExists(
                atPath: root.appendingPathComponent("README.md").path
            )
        )
    }

    func testRepositoryExternalReferencesMatchAll534OwnerRecords() throws {
        let root = repositoryRoot.appendingPathComponent("docs/tractatus", isDirectory: true)
        let manifest = try SourceManifestYAMLDecoder.decode(
            contentsOf: root.appendingPathComponent("sources.yaml")
        )
        let volumes = try ["preface", "1", "2", "3", "4", "5", "6", "7"].map {
            try CorpusYAMLDecoder.decodeVolume(
                contentsOf: root.appendingPathComponent("corpus/\($0).yaml")
            )
        }

        XCTAssertEqual(volumes.flatMap(\.propositions).count, 534)
        XCTAssertEqual(
            SourceManifestValidator.validate(manifest, root: root, volumes: volumes),
            []
        )
    }

    func testDecodesAuditableEditionMetadataAndAcceptsMatchingSnapshotDigest() throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }

        let manifest = try SourceManifestYAMLDecoder.decode(fixture.manifestYAML)
        let german = try XCTUnwrap(manifest.editions.first)

        XCTAssertEqual(german.id, "de")
        XCTAssertEqual(german.role, .original)
        XCTAssertEqual(german.language, "de")
        XCTAssertEqual(german.upstreamRevision, "fixture-revision")
        XCTAssertEqual(german.inclusionMode, .inline)
        XCTAssertEqual(german.copyrightStatus, .publicDomain)
        XCTAssertEqual(
            SourceManifestValidator.validate(manifest, root: fixture.root, volumes: []),
            []
        )
    }

    func testMalformedDigestMatchingSnapshotFailsClosedWithoutCorpusVolumes() throws {
        let fixture = try makeFixture(snapshot: "source snapshot\n")
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let manifest = try SourceManifestYAMLDecoder.decode(fixture.manifestYAML)

        let issues = SourceManifestValidator.validate(
            manifest,
            root: fixture.root,
            volumes: []
        )

        XCTAssertTrue(issues.contains {
            $0.code == "source-mismatch" && $0.recordID == "de"
        })
    }

    func testDigestMatchingPartialSnapshotFailsClosedWithoutCorpusVolumes() throws {
        let fixture = try makeFixture(
            snapshot: "**1** source snapshot\n",
            inventory: ["1", "1.1"]
        )
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let manifest = try SourceManifestYAMLDecoder.decode(fixture.manifestYAML)

        let issues = SourceManifestValidator.validate(
            manifest,
            root: fixture.root,
            volumes: []
        )

        XCTAssertTrue(issues.contains {
            $0.code == "source-mismatch" && $0.recordID == "de"
        })
    }

    func testDigestMatchingDuplicateSnapshotHeadingFailsClosed() throws {
        let fixture = try makeFixture(
            snapshot: "**1** first passage\n**1** duplicate passage\n"
        )
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let manifest = try SourceManifestYAMLDecoder.decode(fixture.manifestYAML)

        let issues = SourceManifestValidator.validate(
            manifest,
            root: fixture.root,
            volumes: []
        )

        XCTAssertTrue(issues.contains {
            $0.code == "source-mismatch" && $0.recordID == "de"
        })
    }

    func testDigestMatchingReorderedSnapshotHeadingsFailClosed() throws {
        let fixture = try makeFixture(
            snapshot: "**1.1** child passage\n**1** root passage\n",
            inventory: ["1", "1.1"]
        )
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let manifest = try SourceManifestYAMLDecoder.decode(fixture.manifestYAML)

        let issues = SourceManifestValidator.validate(
            manifest,
            root: fixture.root,
            volumes: []
        )

        XCTAssertTrue(issues.contains {
            $0.code == "source-mismatch" && $0.recordID == "de"
        })
    }

    func testDigestMatchingSnapshotRejectsNumberedPassageBeforePreface() throws {
        let fixture = try makeFixture(
            snapshot: "**1** numbered passage\n\n## Vorwort\n\npreface passage\n\n*L. W.*\n",
            inventory: ["preface.1", "1"]
        )
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let manifest = try SourceManifestYAMLDecoder.decode(fixture.manifestYAML)

        let issues = SourceManifestValidator.validate(
            manifest,
            root: fixture.root,
            volumes: []
        )

        XCTAssertTrue(issues.contains {
            $0.code == "source-mismatch" && $0.recordID == "de"
        })
    }

    func testExternalReferenceWithoutDigestUsesBibliographicProvenance() throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let manifest: SourceManifest
        do {
            manifest = try SourceManifestYAMLDecoder.decode(fixture.manifestYAML)
        } catch {
            XCTFail("external_reference 省略內容 digest 時仍應可解碼：\(error)")
            return
        }

        let external = try XCTUnwrap(
            manifest.editions.first { $0.id == "en_pears_mcguinness" }
        )
        XCTAssertNil(external.sha256)
        XCTAssertEqual(
            SourceManifestValidator.validate(manifest, root: fixture.root, volumes: []),
            []
        )
    }

    func testInlineEditionWithoutDigestReportsInvalidSource() throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let yaml = fixture.manifestYAML.replacingOccurrences(
            of: "    sha256: \"\(fixture.digest)\"\n    copyright_status: public_domain",
            with: "    copyright_status: public_domain"
        )
        let manifest: SourceManifest
        do {
            manifest = try SourceManifestYAMLDecoder.decode(yaml)
        } catch {
            XCTFail("inline 缺 digest 應由 validator 回報 invalid-source，而非解碼失敗：\(error)")
            return
        }

        let issues = SourceManifestValidator.validate(
            manifest,
            root: fixture.root,
            volumes: []
        )

        XCTAssertEqual(issues.map(\.code), ["invalid-source"])
        XCTAssertEqual(issues.first?.recordID, "de")
    }

    func testExternalReferenceWithDigestReportsInvalidSource() throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let yaml = fixture.manifestYAML.replacingOccurrences(
            of: "    copyright_status: copyrighted",
            with: "    sha256: \"\(String(repeating: "0", count: 64))\"\n    copyright_status: copyrighted"
        )
        let manifest = try SourceManifestYAMLDecoder.decode(yaml)

        let issues = SourceManifestValidator.validate(
            manifest,
            root: fixture.root,
            volumes: []
        )

        XCTAssertEqual(issues.map(\.code), ["invalid-source"])
        XCTAssertEqual(issues.first?.recordID, "en_pears_mcguinness")
    }

    func testReportsDigestMismatchForChangedOrUnpinnedSnapshot() throws {
        let fixture = try makeFixture(digest: String(repeating: "0", count: 64))
        defer { try? FileManager.default.removeItem(at: fixture.root) }

        let manifest = try SourceManifestYAMLDecoder.decode(fixture.manifestYAML)
        let issues = SourceManifestValidator.validate(manifest, root: fixture.root, volumes: [])

        XCTAssertEqual(issues.map(\.code), ["digest-mismatch"])
        XCTAssertEqual(issues.first?.recordID, "de")
    }

    func testLicensedInlineEditionRequiresAuditableLicenseEvidenceURL() throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let yaml = fixture.manifestYAML
            .replacingOccurrences(of: "copyright_status: public_domain", with: "copyright_status: licensed")
            .replacingOccurrences(of: "rights_note: \"Public domain source text.\"", with: "rights_note: \"ok\"")
        let manifest = try SourceManifestYAMLDecoder.decode(yaml)

        let issues = SourceManifestValidator.validate(manifest, root: fixture.root, volumes: [])

        XCTAssertTrue(issues.contains {
            $0.code == "license-violation" && $0.recordID == "de"
        })
    }

    func testEveryEditionRequiresAuditableNonemptyProvenance() throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let yaml = fixture.manifestYAML
            .replacingOccurrences(
                of: "bibliography: \"Ludwig Wittgenstein, Logisch-philosophische Abhandlung.\"",
                with: "bibliography: \"\""
            )
            .replacingOccurrences(
                of: "source_url: \"https://www.wittgensteinproject.org/\"",
                with: "source_url: \"not-a-url\""
            )
            .replacingOccurrences(
                of: "retrieval_date: \"2026-08-08\"",
                with: "retrieval_date: \"08/08/2026\""
            )
            .replacingOccurrences(
                of: "upstream_revision: \"fixture-revision\"",
                with: "upstream_revision: \"\""
            )
            .replacingOccurrences(
                of: "rights_note: \"No reproduction permission recorded; references only.\"",
                with: "rights_note: \"\""
            )
        let manifest = try SourceManifestYAMLDecoder.decode(yaml)

        let issues = SourceManifestValidator.validate(
            manifest,
            root: fixture.root,
            volumes: []
        )

        XCTAssertTrue(issues.contains {
            $0.code == "invalid-source" && $0.recordID == "de"
        })
        XCTAssertTrue(issues.contains {
            $0.code == "invalid-source" && $0.recordID == "en_pears_mcguinness"
        })
    }

    func testRejectsCorpusTextThatDoesNotReconstructPinnedInlineSource() throws {
        let root = repositoryRoot.appendingPathComponent("docs/tractatus", isDirectory: true)
        let manifest = try SourceManifestYAMLDecoder.decode(
            contentsOf: root.appendingPathComponent("sources.yaml")
        )
        let original = try String(
            contentsOf: root.appendingPathComponent("corpus/1.yaml"),
            encoding: .utf8
        )
        let altered = original.replacingOccurrences(
            of: "Die Welt ist alles, was der Fall ist.",
            with: "Dieser erfundene Satz steht nicht in der Quelle."
        )
        let volume = try CorpusYAMLDecoder.decodeVolume(altered)

        let issues = SourceManifestValidator.validate(manifest, root: root, volumes: [volume])

        XCTAssertTrue(issues.contains {
            $0.code == "source-mismatch" && $0.recordID == "1"
        })
    }

    func testUnreadableSnapshotStructureFailsClosedWhenCorpusIsPresent() throws {
        let fixture = try makeFixture(snapshot: "source snapshot\n")
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let manifest = try SourceManifestYAMLDecoder.decode(fixture.manifestYAML)
        let volume = try CorpusYAMLDecoder.decodeVolume("""
        schema_version: 1
        volume: "1"
        propositions:
          - id: "1"
            texts:
              de: ["source snapshot"]
            edition_references:
              en_pears_mcguinness: "1"
            segments: []
            project_relations: []
            history: []
        """)

        let issues = SourceManifestValidator.validate(
            manifest,
            root: fixture.root,
            volumes: [volume]
        )

        XCTAssertTrue(issues.contains {
            $0.code == "source-mismatch" && $0.recordID == "de"
        })
    }

    func testExternalReferenceRejectsReproducedCorpusText() throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let manifest = try SourceManifestYAMLDecoder.decode(fixture.manifestYAML)
        let volume = try CorpusYAMLDecoder.decodeVolume("""
        schema_version: 1
        volume: "1"
        propositions:
          - id: "1"
            texts:
              de: ["Die Welt ist alles, was der Fall ist."]
              en_pears_mcguinness: ["Copied copyrighted wording."]
            edition_references:
              en_pears_mcguinness: "1"
            segments:
              - id: "1.a"
                alignment:
                  de: [0]
                translation_zh_tw: "世界是一切實情。"
                interpretation_zh_tw: "此處界定世界為事實的總體。"
            project_relations: []
            history: []
        """)

        let issues = SourceManifestValidator.validate(
            manifest,
            root: fixture.root,
            volumes: [volume]
        )

        XCTAssertTrue(issues.contains {
            $0.code == "license-violation" && $0.recordID == "1"
        })
    }

    func testExternalReferenceRejectsTranslationProseInReferenceField() throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let manifest = try SourceManifestYAMLDecoder.decode(fixture.manifestYAML)
        let volume = try CorpusYAMLDecoder.decodeVolume("""
        schema_version: 1
        volume: "1"
        propositions:
          - id: "1"
            texts:
              de: ["source snapshot"]
            edition_references:
              en_pears_mcguinness: "The world is all that is the case."
            segments: []
            project_relations: []
            history: []
        """)

        let issues = SourceManifestValidator.validate(
            manifest,
            root: fixture.root,
            volumes: [volume]
        )

        XCTAssertTrue(issues.contains {
            $0.code == "license-violation" && $0.recordID == "1"
        })
    }

    func testManifestAlsoRejectsUnknownKeys() throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let yaml = fixture.manifestYAML.replacingOccurrences(
            of: "role: original",
            with: "role: original\n    invented_right: true"
        )

        XCTAssertThrowsError(try SourceManifestYAMLDecoder.decode(yaml)) { error in
            XCTAssertEqual(error as? CorpusSchemaError, .unknownKey("invented_right"))
        }
    }

    func testFixedScopeRejectsDuplicateEditionIDBeforeRendering() throws {
        let root = repositoryRoot.appendingPathComponent("docs/tractatus", isDirectory: true)
        let yaml = try String(
            contentsOf: root.appendingPathComponent("sources.yaml"),
            encoding: .utf8
        )
        let deStart = try XCTUnwrap(yaml.range(of: "  - id: de\n"))
        let englishStart = try XCTUnwrap(yaml.range(of: "  - id: en_ogden_ramsey_1922\n"))
        let germanBlock = String(yaml[deStart.lowerBound..<englishStart.lowerBound])
        let duplicated = yaml.replacingCharacters(
            in: englishStart.lowerBound..<englishStart.lowerBound,
            with: germanBlock
        )
        let manifest = try SourceManifestYAMLDecoder.decode(duplicated)

        let issues = CorpusValidator.validateStructure(manifest: manifest, volumes: [])

        XCTAssertTrue(issues.contains {
            $0.code == "invalid-scope" && $0.recordID == "editions"
        })
    }

    func testFixedScopeRejectsAlteredDedicationOrMottoMetadata() throws {
        let root = repositoryRoot.appendingPathComponent("docs/tractatus", isDirectory: true)
        let source = try String(
            contentsOf: root.appendingPathComponent("sources.yaml"),
            encoding: .utf8
        )
        let altered = source
            .replacingOccurrences(
                of: "Dem Andenken meines Freundes DAVID H. PINSENT gewidmet",
                with: "invented dedication"
            )
            .replacingOccurrences(of: "Kürnberger", with: "invented attribution")
        let manifest = try SourceManifestYAMLDecoder.decode(altered)

        let issues = CorpusValidator.validateStructure(manifest: manifest, volumes: [])

        XCTAssertTrue(issues.contains {
            $0.code == "invalid-scope" && $0.recordID == "scope-metadata"
        })
    }

    private func makeFixture(
        snapshot: String = "**1** source snapshot\n",
        digest: String? = nil,
        inventory: [String] = ["1"]
    ) throws -> (root: URL, manifestYAML: String, digest: String) {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("tractatus-source-\(UUID().uuidString)", isDirectory: true)
        let snapshots = root.appendingPathComponent("source-snapshots", isDirectory: true)
        try FileManager.default.createDirectory(at: snapshots, withIntermediateDirectories: true)
        let snapshotData = Data(snapshot.utf8)
        try snapshotData.write(
            to: snapshots.appendingPathComponent("de.md")
        )
        let actualDigest = SHA256.hash(data: snapshotData)
            .map { String(format: "%02x", $0) }
            .joined()
        let manifestDigest = digest ?? actualDigest
        let serializedInventory = inventory.map { "\"\($0)\"" }.joined(separator: ", ")

        let yaml = """
        schema_version: 1
        scope:
          inventory: [\(serializedInventory)]
          dedication: "Dem Andenken meines Freundes David H. Pinsent"
          motto:
            text: "... und alles, was man weiß, nicht bloß rauschen und brausen gehört hat, läßt sich in drei Worte sagen."
            attribution: "Kürnberger"
          excluded: [russell_introduction, index]
        editions:
          - id: de
            role: original
            language: de
            bibliography: "Ludwig Wittgenstein, Logisch-philosophische Abhandlung."
            source_url: "https://www.wittgensteinproject.org/"
            retrieval_date: "2026-08-08"
            upstream_revision: "fixture-revision"
            sha256: "\(manifestDigest)"
            copyright_status: public_domain
            rights_note: "Public domain source text."
            inclusion_mode: inline
            snapshot: source-snapshots/de.md
          - id: en_pears_mcguinness
            role: translation
            language: en
            bibliography: "Pears and McGuinness translation; edition reference only."
            source_url: "https://www.routledge.com/"
            retrieval_date: "2026-08-08"
            upstream_revision: "bibliographic-reference"
            copyright_status: copyrighted
            rights_note: "No reproduction permission recorded; references only."
            inclusion_mode: external_reference
        """
        return (root, yaml, manifestDigest)
    }

    private var repositoryRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    private func captures(in text: String, pattern: String) -> [String] {
        let expression = try! NSRegularExpression(pattern: pattern)
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return expression.matches(in: text, range: range).compactMap { match in
            Range(match.range(at: 1), in: text).map { String(text[$0]) }
        }
    }
}
