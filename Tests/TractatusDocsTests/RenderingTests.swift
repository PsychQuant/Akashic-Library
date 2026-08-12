import CryptoKit
import Foundation
import XCTest
@testable import TractatusDocs

final class RenderingTests: XCTestCase {
    func testFourColumnRenderingMatchesSnapshot() throws {
        let rendered = TractatusMarkdownRenderer.render(
            manifest: try manifest(),
            volumes: [try volume()]
        )
        let expectedURL = try XCTUnwrap(
            Bundle.module.url(forResource: "rendering-expected", withExtension: "md", subdirectory: "Fixtures")
        )
        let expected = try String(contentsOf: expectedURL, encoding: .utf8)

        XCTAssertEqual(rendered, expected)
    }

    func testRenderingEscapesHTMLInTextMetadataLinksAndProjectClaims() throws {
        let rendered = TractatusMarkdownRenderer.render(
            manifest: try manifest(),
            volumes: [try volume()]
        )

        XCTAssertTrue(rendered.contains("Die Welt &amp; alles."), rendered)
        XCTAssertTrue(rendered.contains("Nicht &lt;Dinge&gt;."), rendered)
        XCTAssertTrue(rendered.contains("Not &quot;things&quot;."), rendered)
        XCTAssertTrue(rendered.contains("x=1&amp;y=2"), rendered)
        XCTAssertTrue(rendered.contains("專案 &amp; 主張"), rendered)
        XCTAssertFalse(rendered.contains("<Dinge>"), rendered)
    }

    func testRenderingTwiceProducesIdenticalSHA256() throws {
        let manifest = try manifest()
        let volumes = [try volume()]
        let first = TractatusMarkdownRenderer.render(manifest: manifest, volumes: volumes)
        let second = TractatusMarkdownRenderer.render(manifest: manifest, volumes: volumes)

        XCTAssertEqual(first, second)
        XCTAssertEqual(sha256(first), sha256(second))
        XCTAssertFalse(first.contains(projectRoot.path), first)
        XCTAssertFalse(first.contains("2026-08-08T"), first)
    }

    func testRenderingRewritesPinnedSourceImagesToOfflineAssets() throws {
        let imageVolume = try CorpusYAMLDecoder.decodeVolume("""
        schema_version: 1
        volume: "5"
        propositions:
          - id: "5"
            texts:
              de: ["Bild: ![](images/form.svg)"]
              en_ogden_ramsey_1922: ["Figure: ![truth [table]](images/form.svg)"]
            edition_references:
              en_pears_mcguinness: "5"
            segments:
              - id: "5.a"
                alignment:
                  de: [0]
                  en_ogden_ramsey_1922: [0]
                translation_zh_tw: "圖式。"
                interpretation_zh_tw: "圖式是命題的一部分。"
            project_relations: []
        """)

        let rendered = TractatusMarkdownRenderer.render(
            manifest: try manifest(),
            volumes: [imageVolume]
        )

        XCTAssertTrue(
            rendered.contains("<img src=\"../source-assets/images/form.svg\" alt=\"truth [table]\">"),
            rendered
        )
        XCTAssertFalse(rendered.contains("](images/form.svg)"), rendered)
    }

    func testRenderingUsesImageGrammarForSpacesAndEveryRichTextField() throws {
        let imageVolume = try CorpusYAMLDecoder.decodeVolume("""
        schema_version: 1
        volume: "5"
        propositions:
          - id: "5"
            texts:
              de: ["![source](images/source figure.svg)"]
              en_ogden_ramsey_1922: ["Plain source text."]
            edition_references:
              en_pears_mcguinness: "5"
            segments:
              - id: "5.a"
                alignment:
                  de: [0]
                  en_ogden_ramsey_1922: [0]
                translation_zh_tw: "![translation](images/translation figure.svg)"
                interpretation_zh_tw: "![interpretation](images/interpretation figure.svg)"
            project_relations:
              - status: implemented
                mode: instance
                claim_zh_tw: "![claim](images/claim figure.svg)"
                rationale_zh_tw: "![rationale](images/rationale figure.svg)"
                evidence:
                  - path: "Package.swift"
                    kind: symbol
                    locator: "Package"
                    note_zh_tw: "![evidence](images/evidence figure.svg)"
            history:
              - kind: branch
                reference: "fixture/history"
                disposition: retained
                note_zh_tw: "![history](images/history figure.svg)"
        """)
        let rendered = TractatusMarkdownRenderer.render(
            manifest: try manifest(),
            volumes: [imageVolume]
        )

        for name in [
            "source figure.svg",
            "translation figure.svg",
            "interpretation figure.svg",
            "claim figure.svg",
            "rationale figure.svg",
            "evidence figure.svg",
            "history figure.svg",
        ] {
            XCTAssertTrue(
                rendered.contains("<img src=\"../source-assets/images/\(name)\""),
                "renderer 應處理 \(name)：\n\(rendered)"
            )
        }
    }

    func testRenderWritesAtomicallyAndCheckLeavesMatchingBytesUntouched() throws {
        let root = try TractatusDiskFixture.make()
        defer { TractatusDiskFixture.remove(root) }
        let output = root.appendingPathComponent("generated/map.md")

        let rendered = try TractatusDocuments.render(root: root, output: output, check: false)
        let before = try Data(contentsOf: output)
        let checked = try TractatusDocuments.render(root: root, output: output, check: true)
        let after = try Data(contentsOf: output)

        XCTAssertTrue(rendered.contains("rendered:"), rendered)
        XCTAssertTrue(checked.contains("render-check: clean"), checked)
        XCTAssertEqual(before, after)
        XCTAssertTrue(String(decoding: before, as: UTF8.self).hasPrefix("<!-- GENERATED FILE"))
    }

    func testRenderCheckReportsDriftWithoutChangingExistingBytes() throws {
        let root = try TractatusDiskFixture.make()
        defer { TractatusDiskFixture.remove(root) }
        let output = root.appendingPathComponent("generated/map.md")
        try FileManager.default.createDirectory(
            at: output.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let stale = Data("stale bytes\n".utf8)
        try stale.write(to: output)

        XCTAssertThrowsError(
            try TractatusDocuments.render(root: root, output: output, check: true)
        ) { error in
            let failure = error as? TractatusValidationFailure
            XCTAssertEqual(failure?.diagnostics.map(\.code), ["generated-drift"])
        }
        XCTAssertEqual(try Data(contentsOf: output), stale)
    }

    func testRenderSurfacesIOFailureWithoutReplacingDirectoryTarget() throws {
        let root = try TractatusDiskFixture.make()
        defer { TractatusDiskFixture.remove(root) }
        let output = root.appendingPathComponent("generated/directory-target", isDirectory: true)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)

        XCTAssertThrowsError(
            try TractatusDocuments.render(root: root, output: output, check: false)
        ) { error in
            let failure = error as? TractatusValidationFailure
            XCTAssertEqual(failure?.diagnostics.map(\.code), ["write-failed"])
        }
        var isDirectory: ObjCBool = false
        XCTAssertTrue(FileManager.default.fileExists(atPath: output.path, isDirectory: &isDirectory))
        XCTAssertTrue(isDirectory.boolValue)
    }

    private func sha256(_ value: String) -> String {
        SHA256.hash(data: Data(value.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    private func manifest() throws -> SourceManifest {
        try SourceManifestYAMLDecoder.decode("""
        schema_version: 1
        scope:
          inventory: ["1"]
          dedication: "Dedicated & remembered."
          motto:
            text: "Motto <three>."
            attribution: "Attribution"
          excluded: [russell_introduction, index]
        editions:
          - id: de
            role: original
            language: de
            bibliography: "German & edition"
            source_url: "https://example.invalid/de?x=1&y=2"
            retrieval_date: "2026-08-08"
            upstream_revision: "fixture"
            sha256: "0000000000000000000000000000000000000000000000000000000000000000"
            copyright_status: public_domain
            rights_note: "Fixture."
            inclusion_mode: inline
            snapshot: source-snapshots/de.md
          - id: en_ogden_ramsey_1922
            role: translation
            language: en
            bibliography: "Ogden/Ramsey 1922"
            source_url: "https://example.invalid/ogden"
            retrieval_date: "2026-08-08"
            upstream_revision: "fixture"
            sha256: "0000000000000000000000000000000000000000000000000000000000000000"
            copyright_status: public_domain
            rights_note: "Fixture."
            inclusion_mode: inline
            snapshot: source-snapshots/en.md
          - id: en_pears_mcguinness
            role: translation
            language: en
            bibliography: "Pears & McGuinness reference"
            source_url: "https://example.invalid/pears?x=1&y=2"
            retrieval_date: "2026-08-08"
            upstream_revision: "fixture"
            sha256: "0000000000000000000000000000000000000000000000000000000000000000"
            copyright_status: copyrighted
            rights_note: "Reference only."
            inclusion_mode: external_reference
        """)
    }

    private func volume() throws -> CorpusVolume {
        try CorpusYAMLDecoder.decodeVolume("""
        schema_version: 1
        volume: "1"
        propositions:
          - id: "1"
            texts:
              de: ["Die Welt & alles.", "Nicht <Dinge>."]
              en_ogden_ramsey_1922: ["The world <is> all.", "Not \\"things\\"."]
            edition_references:
              en_pears_mcguinness: "1"
            segments:
              - id: "1.a"
                alignment:
                  de: [0]
                  en_ogden_ramsey_1922: [0]
                translation_zh_tw: "<世界>是一切。"
                interpretation_zh_tw: "「世界」在此不是物件清單。"
              - id: "1.b"
                alignment:
                  de: [1]
                  en_ogden_ramsey_1922: [1]
                translation_zh_tw: "不是事物。"
                interpretation_zh_tw: "重點在事實結構，而非羅列東西。"
            synthesis_zh_tw: "命題層綜合。"
            project_relations:
              - status: implemented
                mode: structural_invariant
                claim_zh_tw: "專案 & 主張"
                rationale_zh_tw: "結構對應，不是 <同一性>。"
                evidence:
                  - path: "Package.swift"
                    kind: symbol
                    locator: "TractatusDocs"
                    note_zh_tw: "library target"
            history:
              - kind: branch
                reference: "agent/wittgenstein-picture-future"
                disposition: retained
                note_zh_tw: "保留 <洞見>。"
        """)
    }

    private var projectRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }
}
