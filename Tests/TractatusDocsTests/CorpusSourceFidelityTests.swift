import Foundation
import XCTest
@testable import TractatusDocs

final class CorpusSourceFidelityTests: XCTestCase {
    func testCompletedPrefaceAndVolumesOneThroughThreeReconstructPinnedSources() throws {
        try assertCorpusFidelity(volumeNames: ["preface", "1", "2", "3"])
    }

    func testCompletedPrefaceAndVolumesOneThroughThreeHaveNoContentDiagnostics() throws {
        try assertNoContentDiagnostics(volumeNames: ["preface", "1", "2", "3"])
    }

    func testCompletedVolumeFourReconstructsPinnedSourcesAndHasNoContentDiagnostics() throws {
        try assertCorpusFidelity(volumeNames: ["4"])
        try assertNoContentDiagnostics(volumeNames: ["4"])
    }

    func testCompletedVolumeFiveReconstructsPinnedSourcesAndHasNoContentDiagnostics() throws {
        try assertCorpusFidelity(volumeNames: ["5"])
        try assertNoContentDiagnostics(volumeNames: ["5"])
    }

    func testCompletedVolumesSixAndSevenReconstructPinnedSourcesAndHaveNoContentDiagnostics() throws {
        try assertCorpusFidelity(volumeNames: ["6", "7"])
        try assertNoContentDiagnostics(volumeNames: ["6", "7"])
    }

    private func assertNoContentDiagnostics(volumeNames: [String]) throws {
        let tractatusRoot = repositoryRoot.appendingPathComponent(
            "docs/tractatus",
            isDirectory: true
        )
        let corpusDirectory = tractatusRoot.appendingPathComponent("corpus", isDirectory: true)
        let manifest = try SourceManifestYAMLDecoder.decode(
            contentsOf: tractatusRoot.appendingPathComponent("sources.yaml")
        )
        let volumes = try volumeNames.map {
            try CorpusYAMLDecoder.decodeVolume(
                contentsOf: corpusDirectory.appendingPathComponent("\($0).yaml")
            )
        }

        var diagnostics = SourceManifestValidator.validate(
            manifest,
            root: tractatusRoot,
            volumes: volumes
        )
        diagnostics += CorpusValidator.validateStructure(manifest: manifest, volumes: volumes)
            .filter { $0.code != "missing-proposition" }
        diagnostics += CorpusValidator.validateAlignment(manifest: manifest, volumes: volumes)
        diagnostics += CorpusValidator.validateRelations(volumes: volumes)
        diagnostics += CorpusValidator.validateEvidence(
            volumes: volumes,
            projectRoot: repositoryRoot
        )

        XCTAssertEqual(diagnostics.sorted(), [])
    }

    func testCompleteRepositoryCorpusReconstructsPinnedInlineSourcesExactly() throws {
        try assertCorpusFidelity(volumeNames: ["preface", "1", "2", "3", "4", "5", "6", "7"])
    }

    func testVolumeTwoRenderedPreviewPreservesRequiredDistinctions() throws {
        let tractatusRoot = repositoryRoot.appendingPathComponent(
            "docs/tractatus",
            isDirectory: true
        )
        let manifest = try SourceManifestYAMLDecoder.decode(
            contentsOf: tractatusRoot.appendingPathComponent("sources.yaml")
        )
        let volume = try CorpusYAMLDecoder.decodeVolume(
            contentsOf: tractatusRoot.appendingPathComponent("corpus/2.yaml")
        )

        let preview = TractatusMarkdownRenderer.render(manifest: manifest, volumes: [volume])

        XCTAssertTrue(preview.contains("事態是對象（物、事物）的結合。"))
        XCTAssertTrue(preview.contains("其 entity 並非 Akashic 資料模型中的 entity"))
        XCTAssertTrue(preview.contains("Akashic 明確拒絕把自己的 entity 記錄等同於本句的簡單對象"))
        XCTAssertTrue(preview.contains("圖像是實在的模型。"))
        XCTAssertTrue(preview.contains("不在外觀相似，而在其元素與配置能依表現規則對應實在"))
        XCTAssertTrue(preview.contains("Sachlage 譯為「狀況」"))
        XCTAssertTrue(preview.contains("拒絕把 Git branch 當成完整 possible world"))
        XCTAssertTrue(preview.contains("commit</code> <code>4c74860"))
    }

    func testVolumeThreeRenderedPreviewPreservesRequiredDistinctions() throws {
        let tractatusRoot = repositoryRoot.appendingPathComponent(
            "docs/tractatus",
            isDirectory: true
        )
        let manifest = try SourceManifestYAMLDecoder.decode(
            contentsOf: tractatusRoot.appendingPathComponent("sources.yaml")
        )
        let volume = try CorpusYAMLDecoder.decodeVolume(
            contentsOf: tractatusRoot.appendingPathComponent("corpus/3.yaml")
        )

        let preview = TractatusMarkdownRenderer.render(manifest: manifest, volumes: [volume])

        XCTAssertTrue(preview.contains("這些東西彼此的空間位置，於是表達命題的意義"))
        XCTAssertTrue(preview.contains("該關係再依投射方法對應到事態"))
        XCTAssertTrue(preview.contains("不是符號列，而是符號之間真的有配置"))
        XCTAssertTrue(preview.contains("同一個詞極常以不同方式指示——因而屬於不同符號"))
        XCTAssertTrue(preview.contains("不宣稱已建成無歧義的完整符號語言"))
        XCTAssertTrue(preview.contains("這不是一般程式呼叫堆疊的敘述"))
        XCTAssertTrue(preview.contains("不推廣成程式函式不得遞迴或所有自我參照皆非法"))
        XCTAssertTrue(preview.contains("思想包含它所思之狀況的可能性"))
        XCTAssertTrue(preview.contains("Sachlage"))
        XCTAssertFalse(preview.contains("事況"))
    }

    func testVolumeFourRenderedPreviewPreservesRequiredDistinctions() throws {
        let preview = try renderedPreview(volumeName: "4")

        XCTAssertTrue(preview.contains("命題是現實的圖像。"))
        XCTAssertTrue(preview.contains("Bild 應譯為「圖像」"))
        XCTAssertTrue(preview.contains("內在相似由可重複的往返轉換成立"))
        XCTAssertTrue(preview.contains("顯示的是 truth condition"))
        XCTAssertTrue(preview.contains("搜尋只顯示字串或索引條件成立"))
        XCTAssertTrue(preview.contains("這是 showing，不是另一句 saying"))
        XCTAssertTrue(preview.contains("拒絕把 view 存成 entity"))
    }

    func testVolumeFiveRenderedPreviewPreservesRequiredDistinctions() throws {
        let preview = try renderedPreview(volumeName: "5")

        XCTAssertTrue(preview.contains("現在的事實不會邏輯地強制唯一未來"))
        XCTAssertTrue(preview.contains("不把 Git branch 當成 possible world"))
        XCTAssertTrue(preview.contains("熟悉同一字形的其他用法"))
        XCTAssertTrue(preview.contains("錯的是記號的位置與符號化關係"))
        XCTAssertTrue(preview.contains("不用同一性記號"))
        XCTAssertTrue(preview.contains("不把資料庫鍵直接等同於本命題的邏輯名稱"))
    }

    func testPropositionFivePointSixThreeThreeKeepsEachClaimWithItsTranslation() throws {
        let tractatusRoot = repositoryRoot.appendingPathComponent(
            "docs/tractatus",
            isDirectory: true
        )
        let volume = try CorpusYAMLDecoder.decodeVolume(
            contentsOf: tractatusRoot.appendingPathComponent("corpus/5.yaml")
        )
        let proposition = try XCTUnwrap(
            volume.propositions.first { $0.id.rawValue == "5.633" }
        )

        XCTAssertEqual(proposition.texts["de"]?.count, 4)
        XCTAssertEqual(proposition.texts["en_ogden_ramsey_1922"]?.count, 4)
        XCTAssertEqual(
            proposition.segments.map(\.translationZhTW),
            [
                "形上主體究竟能在世界的哪裡被注意到？",
                "你會說，這完全像眼睛與視野的情形。",
                "但你其實看不見眼睛。",
                "而且視野中的任何東西，都不能讓人推出它是由一隻眼睛看見的。",
            ]
        )
        for (index, segment) in proposition.segments.enumerated() {
            XCTAssertEqual(segment.alignment["de"], [index])
            XCTAssertEqual(segment.alignment["en_ogden_ramsey_1922"], [index])
        }
    }

    func testVolumesSixAndSevenRenderedPreviewsPreserveRequiredDistinctions() throws {
        let volumeSix = try renderedPreview(volumeName: "6")
        let volumeSeven = try renderedPreview(volumeName: "7")

        XCTAssertTrue(volumeSix.contains("過往規律可支持預期"))
        XCTAssertTrue(volumeSix.contains("事件先後不自動構成邏輯蘊涵"))
        XCTAssertTrue(volumeSix.contains("不是要求工程系統取消證據、嚴重度或規範優先級"))
        XCTAssertTrue(volumeSix.contains("不保證容易、可計算或已知"))
        XCTAssertTrue(volumeSix.contains("梯子是閱讀方法比喻，不是刪除來源或版本歷史的指令"))
        XCTAssertTrue(volumeSeven.contains("並不禁止保存未知原文或未決狀態"))
        XCTAssertTrue(volumeSeven.contains("沉默約束針對無根據的斷言，不是資料刪除"))
    }

    private func renderedPreview(volumeName: String) throws -> String {
        let tractatusRoot = repositoryRoot.appendingPathComponent(
            "docs/tractatus",
            isDirectory: true
        )
        let manifest = try SourceManifestYAMLDecoder.decode(
            contentsOf: tractatusRoot.appendingPathComponent("sources.yaml")
        )
        let volume = try CorpusYAMLDecoder.decodeVolume(
            contentsOf: tractatusRoot.appendingPathComponent("corpus/\(volumeName).yaml")
        )
        return TractatusMarkdownRenderer.render(manifest: manifest, volumes: [volume])
    }

    private func assertCorpusFidelity(volumeNames: [String]) throws {
        let tractatusRoot = repositoryRoot.appendingPathComponent(
            "docs/tractatus",
            isDirectory: true
        )
        let german = try String(
            contentsOf: tractatusRoot.appendingPathComponent(
                "source-snapshots/de-wittgenstein-project.md"
            ),
            encoding: .utf8
        )
        let english = try String(
            contentsOf: tractatusRoot.appendingPathComponent(
                "source-snapshots/en-ogden-ramsey-1922-wittgenstein-project.md"
            ),
            encoding: .utf8
        )
        let sourceByEdition = [
            "de": numberedPassages(
                in: german,
                headingPattern: #"(?m)^\*\*([1-7](?:\.[0-9]+)*)\*\*[ \t]*"#
            ).merging(
                prefacePassages(
                    in: german,
                    heading: "## Vorwort",
                    signature: "*L. W.*"
                ),
                uniquingKeysWith: { first, _ in first }
            ),
            "en_ogden_ramsey_1922": numberedPassages(
                in: english,
                headingPattern: #"(?m)^\*\*\[([1-7](?:\.[0-9]+)*)\]\([^\n]*\)\*\*[ \t]*"#
            ).merging(
                prefacePassages(
                    in: english,
                    heading: "## Preface",
                    signature: "*L.W.*"
                ),
                uniquingKeysWith: { first, _ in first }
            ),
        ]

        let corpusDirectory = tractatusRoot.appendingPathComponent("corpus", isDirectory: true)
        let volumeURLs = volumeNames.map {
            corpusDirectory.appendingPathComponent("\($0).yaml")
        }

        XCTAssertFalse(volumeURLs.isEmpty)
        for url in volumeURLs {
            let volume = try CorpusYAMLDecoder.decodeVolume(contentsOf: url)
            for proposition in volume.propositions {
                let expectedExternalReference = proposition.id.rawValue.hasPrefix("preface.")
                    ? "Preface paragraph \(proposition.id.rawValue.dropFirst("preface.".count))"
                    : proposition.id.rawValue
                XCTAssertEqual(
                    proposition.editionReferences["en_pears_mcguinness"],
                    expectedExternalReference,
                    "\(url.lastPathComponent):\(proposition.id.rawValue) 的 Pears／McGuinness 參照錯位"
                )
                for editionID in ["de", "en_ogden_ramsey_1922"] {
                    let source = try XCTUnwrap(
                        sourceByEdition[editionID]?[proposition.id.rawValue],
                        "\(editionID) snapshot 缺少 \(proposition.id.rawValue)"
                    )
                    let units = try XCTUnwrap(
                        proposition.texts[editionID],
                        "\(url.lastPathComponent):\(proposition.id.rawValue) 缺少 \(editionID)"
                    )
                    XCTAssertEqual(
                        canonicalSourceText(units.joined()),
                        canonicalSourceText(source),
                        "\(url.lastPathComponent):\(proposition.id.rawValue):\(editionID) 未逐字回組來源"
                    )
                }
            }
        }
    }

    private var repositoryRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    private func prefacePassages(
        in snapshot: String,
        heading: String,
        signature: String
    ) -> [String: String] {
        guard let headingRange = snapshot.range(of: heading),
              let signatureRange = snapshot.range(
                of: signature,
                range: headingRange.upperBound..<snapshot.endIndex
              ) else {
            return [:]
        }
        let body = snapshot[headingRange.upperBound..<signatureRange.lowerBound]
        let paragraphs = body
            .components(separatedBy: "\n\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        return Dictionary(uniqueKeysWithValues: paragraphs.enumerated().map { index, paragraph in
            ("preface.\(index + 1)", paragraph)
        })
    }

    private func numberedPassages(
        in snapshot: String,
        headingPattern: String
    ) -> [String: String] {
        let expression = try! NSRegularExpression(pattern: headingPattern)
        let fullRange = NSRange(snapshot.startIndex..<snapshot.endIndex, in: snapshot)
        let matches = expression.matches(in: snapshot, range: fullRange)
        var result: [String: String] = [:]
        for (index, match) in matches.enumerated() {
            guard let idRange = Range(match.range(at: 1), in: snapshot),
                  let headingRange = Range(match.range, in: snapshot) else {
                continue
            }
            let end = index + 1 < matches.count
                ? Range(matches[index + 1].range, in: snapshot)!.lowerBound
                : snapshot.endIndex
            result[String(snapshot[idRange])] = String(snapshot[headingRange.upperBound..<end])
        }
        return result
    }

    private func canonicalSourceText(_ text: String) -> String {
        let withoutEditorialFootnotes = text.replacingOccurrences(
            of: #"\[\^[^\]]+\]"#,
            with: "",
            options: .regularExpression
        )
        return String(withoutEditorialFootnotes.filter { !$0.isWhitespace })
    }
}
