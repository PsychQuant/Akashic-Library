import XCTest
import Foundation
@testable import AkashicCore

/// `YAMLProfileScan`（#629：原 `scripts/scan-yaml-profile.py` 的 Swift 移植；開發用）。
///
/// 期望值是**移植前 Python 版對同一批 fixture 的輸出**（29 個檔，除了「parse 失敗」一欄——見
/// `testParserLayerFollowsLibyamlNotPyYAML`——兩邊逐行相同）。fixture 涵蓋 profile 外的每一種語法，
/// 以及兩個最容易誤判的形狀：regex 命中但 parser 層為 0（`&amp;` 與 `*keyword*` 在引號內）、
/// 顯式 core tag（`!!str`，profile §4 同樣禁止，與自訂 tag 分欄）。
final class YAMLProfileScanTests: XCTestCase {
    private var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("akashic-yprof-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: root) }

    private func write(_ files: [String: Data]) throws {
        for (rel, data) in files {
            let url = root.appendingPathComponent(rel)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: url)
        }
    }

    private func scan(_ files: [String: String]) throws -> YAMLProfileScan.Result {
        try write(files.mapValues { Data($0.utf8) })
        return try YAMLProfileScan.scan(root: root.path)
    }

    private func names(_ r: YAMLProfileScan.Result, _ feature: String) -> [String] { (r.buckets[feature] ?? []).sorted() }

    // MARK: regex 層

    func testEachFeatureIsDetectedByItsOwnPattern() throws {
        let r = try scan([
            "plain.yaml": "a: 1\nb:\n  c: 2\n",
            "anchor.yaml": "base: &b {x: 1}\nuse: *b\n",
            "tag.yaml": "v: !custom 1\n",
            "merge.yaml": "a: &x {k: 1}\nb:\n  <<: *x\n",
            "block.yaml": "k: |\n  text\n",
            "folded.yaml": "k: >-\n  text\n",
            "flow.yaml": "k: [1, 2]\nm: {a: 1}\n",
            "complex.yaml": "? key\n: value\n",
            "comments.yaml": "# head\na: 1  # tail\n",
            "multidoc.yaml": "a: 1\n---\nb: 2\n",
            "tab.yaml": "a:\t1\n",
            "nel.yaml": "a: \"x\u{2028}y\"\n",
        ])
        XCTAssertEqual(r.files.count, 12)
        XCTAssertEqual(names(r, "anchor/alias"), ["anchor.yaml", "merge.yaml"])
        XCTAssertEqual(names(r, "explicit tag"), ["tag.yaml"])
        XCTAssertEqual(names(r, "merge key"), ["merge.yaml"])
        XCTAssertEqual(names(r, "block scalar |>"), ["block.yaml", "folded.yaml"])
        XCTAssertEqual(names(r, "flow seq [..]"), ["flow.yaml"])
        // `base: &b {x: 1}` 的 `{` 前隔著 `&b`，樣式 `:\s*\{` 不命中——只有 `m: {a: 1}` 命中
        XCTAssertEqual(names(r, "flow map {..}"), ["flow.yaml"])
        XCTAssertEqual(names(r, "complex key ? k"), ["complex.yaml"])
        XCTAssertEqual(names(r, "comment line"), ["comments.yaml"])
        XCTAssertEqual(names(r, "inline comment"), ["comments.yaml"])
        XCTAssertEqual(names(r, "multi-doc ---"), ["multidoc.yaml"])
        XCTAssertEqual(names(r, "tab"), ["tab.yaml"])
        XCTAssertEqual(names(r, "NEL/LS/PS"), ["nel.yaml"])
    }

    func testBOMAndCRAreDetectedFromBytes() throws {
        try write(["bom.yaml": Data([0xEF, 0xBB, 0xBF]) + Data("a: 1\n".utf8), "crlf.yaml": Data("a: 1\r\nb: 2\r\n".utf8)])
        let r = try YAMLProfileScan.scan(root: root.path)
        XCTAssertEqual(names(r, "BOM"), ["bom.yaml"])
        XCTAssertEqual(names(r, "CR"), ["crlf.yaml"])
    }

    /// 檔名判準同 `Path.rglob('*.yaml')`：遞迴、大小寫敏感。
    func testOnlyLowercaseYamlFilesAreScannedRecursively() throws {
        let r = try scan(["a/deep/x.yaml": "a: 1\n", "b/UP.YAML": "a: 1\n", "c/readme.txt": "x"])
        XCTAssertEqual(r.files, ["x.yaml"])
    }

    func testNestingDepthIsMaxLeadingSpacesOverTwoPerFile() throws {
        let r = try scan(["flat.yaml": "a: 1\n", "deep.yaml": "a:\n    b:\n        c:\n            d: 1\n", "one.yaml": "a:\n  b: 1\n"])
        XCTAssertEqual(r.depth, [0: 1, 1: 1, 6: 1])
    }

    /// 空白判準是 Python 的 `\s`（含 `\v`、U+001C–001F、U+0085…），不是 ICU 的：垂直 tab 隔開的 `# ` 算 inline comment。
    func testInlineCommentUsesPythonWhitespaceSemantics() throws {
        let r = try scan(["vt.yaml": "a: 1\u{0B}# not really\n"])
        XCTAssertEqual(names(r, "inline comment"), ["vt.yaml"])
    }

    // MARK: parser 層

    /// **regex 命中而 parser 層為 0**：`&amp;` 與引號內的 `*keyword*` 不是 anchor（2026-08-01 實測 13 個命中全是這兩種）。
    func testRegexHitsInsideQuotesAreNotParserAnchors() throws {
        let r = try scan(["amp.yaml": "journal: \"Dept. of Stats &amp; Prob.\"\nnote: \"*keyword* here\"\n"])
        XCTAssertEqual(names(r, "anchor/alias"), ["amp.yaml"], "regex 層會命中（已知的 false positive）")
        XCTAssertEqual(r.anchored, [], "parser 層 0 命中")
    }

    func testParserLayerSeparatesAnchorsCustomTagsAndExplicitCoreTags() throws {
        let r = try scan([
            "anchor.yaml": "base: &b {x: 1}\nuse: *b\n",
            "custom.yaml": "v: !custom 1\n",
            "core.yaml": "v: !!str 1\n",
            "core-seq.yaml": "v: !!seq [1]\n",
            "bang.yaml": "v: ! 1\n",
            // 一個事件同時有 anchor 與 tag：先算 anchor（Python 版同）
            "both.yaml": "a: !!str &x hi\nb: *x\n",
            // tag 在 anchor 之前：第一個帶 tag 的事件就停，不再看後面的 anchor
            "tag-first.yaml": "a: !custom 1\nb: &y 2\n",
            "plain.yaml": "a: 1\n",
        ])
        XCTAssertEqual(r.anchored.sorted(), ["anchor.yaml", "both.yaml"])
        XCTAssertEqual(r.tagged.sorted(), ["bang.yaml", "custom.yaml", "tag-first.yaml"])
        XCTAssertEqual(r.taggedCore.sorted(), ["core-seq.yaml", "core.yaml"], "顯式 core tag 與自訂 tag 分欄，不得被 startswith 濾掉後歸零（R11）")
    }

    func testParseFailuresAreReportedNotSkipped() throws {
        let r = try scan(["broken.yaml": "a: [1, 2\nb: }\n", "ok.yaml": "a: 1\n"])
        XCTAssertEqual(r.failed.map(\.name), ["broken.yaml"])
    }

    /// **與 Python 版的刻意差異**：parser 層現在是 libyaml 的 event 流（store 讀端 Yams 用的那個），不是 PyYAML。
    /// 兩者對 anchor 與 tag 同義；對「什麼算 parse 失敗」偶有不同——`a:\t1`（冒號後接 tab）PyYAML 是 ScannerError，
    /// libyaml 接受。ground truth 以讀端為準，所以這裡釘住讀端的行為。
    func testParserLayerFollowsLibyamlNotPyYAML() throws {
        let r = try scan(["tab.yaml": "a:\t1\n"])
        XCTAssertEqual(r.failed.map(\.name), [])
        let vt = try scan(["vt.yaml": "a: 1\u{0B}b: 2\n"])
        XCTAssertEqual(vt.failed.map(\.name), ["vt.yaml"], "控制字元兩個 parser 都拒絕")
    }

    // MARK: 呈現

    func testRenderShowsEveryFeatureRowAndTheThreeParserColumns() throws {
        let r = try scan(["a.yaml": "a: &x 1\nb: *x\n"])
        let text = YAMLProfileScan.render(r, inspect: false).joined(separator: "\n")
        for f in YAMLProfileScan.features { XCTAssertTrue(text.contains(f), f) }
        XCTAssertTrue(text.contains("total files  : 1"))
        XCTAssertTrue(text.contains("真 anchor      : 1  ['a.yaml']"), text)
        XCTAssertTrue(text.contains("顯式 core tag  : 0  []"))
        XCTAssertFalse(text.contains("--- regex 命中的實際文字"), "--inspect 才印")
    }

    func testInspectPrintsTheMatchingLines() throws {
        try write(["a.yaml": Data("journal: \"Stats &amp; Prob.\"\nplain: 1\n".utf8)])
        let r = try YAMLProfileScan.scan(root: root.path, inspect: true)
        let text = YAMLProfileScan.render(r, inspect: true).joined(separator: "\n")
        XCTAssertTrue(text.contains("a.yaml: journal: \"Stats &amp; Prob.\""), text)
        XCTAssertFalse(text.contains("a.yaml: plain: 1"))
    }

    /// 檔名是 store 衍生字串：控制字元不得原樣進輸出。
    func testRenderEscapesControlCharactersInFileNames() throws {
        try write(["e\u{1B}sc.yaml": Data("a: &x 1\nb: *x\n".utf8)])
        let r = try YAMLProfileScan.scan(root: root.path)
        let text = YAMLProfileScan.render(r, inspect: false).joined(separator: "\n")
        XCTAssertFalse(text.contains("\u{1B}"))
    }
}
