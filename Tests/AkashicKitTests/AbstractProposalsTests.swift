import XCTest
import CryptoKit
@testable import AkashicSkillTools
import AkashicStoreIO

/// `AbstractProposals`（#629，由 `plugin/tests/ndjson-abstracts-to-proposals.py` 移植）。
///
/// 階段 B 的摘要存檔（NDJSON）要餵進 `akashic enrich --from` 得先變成 `[Proposal]`。釘住轉換的幾件事：
///
/// 1. **只收 `status == got` 且摘要非空且 DOI 在場的列**；其餘每一列都在 skip 報告裡逐筆具名（`lossless-intake` 執行細節 3）。
/// 2. **`doi` 原樣透傳、不正規化**——URL 前綴與大小寫由 core 的 `DOI` 吸收；「重複」只認**逐位元相同**的 DOI 字串：近重複
///    （大小寫／前綴不同）**兩筆都輸出**，交給 core 判（#516 verify）。
/// 3. **同 DOI 而摘要不同不是「重複」是「衝突」**：`conflicting-duplicate`，與 `duplicate-doi` 分開具名。
/// 4. **skip 報告不可被資料偽造**：`doi`／`status` 裡的控制字元要跳脫、長度要有上限——`doi` 含 `\n` 不得憑空多出一列。
/// 5. **決定論**：同一輸入兩次輸出逐位元相同；digest 給定時驗內容定址，大寫 hex 仍是 digest 形。
/// 6. 錯誤要具名：非 UTF-8、壞的 `--out` 目錄。
/// 7. **`--out` 拒絕寫到非普通檔**（#519 Expected 1）：symlink／目錄／FIFO 一律零寫入並具名。
/// 8. **Crossref「這個 DOI 沒有 metadata」的錯誤頁不是摘要**（#544）。
private extension Error {
    /// `SkillToolError` 的 `errorDescription`（`"\(error)"` 給的是 enum case 的 dump，開頭是 `failure(`）。
    var skillMessage: String { (self as? SkillToolError)?.errorDescription ?? "\(self)" }
}

final class AbstractProposalsTests: XCTestCase {
    static let doi1 = "https://doi.org/10.1037/1082-989x.3.2.231"
    static let doi1Upper = "https://doi.org/10.1037/1082-989X.3.2.231"   // 近重複：只差大小寫
    static let forgingDOI = "10.1/x\nskip\tno-doi\tFORGED\tline 999\u{1B}[2J" + String(repeating: "z", count: 300)

    /// 10 列（含 BOM 與一個空行）。`nil` 是空行。
    static let rows: [PyJSON?] = [
        .object([("doi", .string(doi1)), ("status", .string("got")), ("abstract", .string("Abstract one.")), ("title", .string("T1")), ("year", .int(1998))]),
        .object([("doi", .string(doi1)), ("status", .string("got")), ("abstract", .string("Abstract DIFFERENT.")), ("title", .string("T1")), ("year", .int(1998))]),   // 衝突
        .object([("doi", .string(doi1)), ("status", .string("got")), ("abstract", .string("Abstract one.")), ("title", .string("T1")), ("year", .int(1998))]),   // 冗餘
        .object([("doi", .string("https://doi.org/10.1037/1082-989x.1.4.354")), ("status", .string("landing-failed")), ("abstract", .string("")), ("title", .string("T3")), ("year", .int(1996))]),
        nil,   // 空行
        .object([("doi", .string("https://doi.org/10.1037//1082-989x.6.4.430-450")), ("status", .string("none-verified")), ("abstract", .string("")), ("title", .string("T4")), ("year", .int(2001))]),
        .object([("doi", .null), ("status", .string("landing-failed")), ("abstract", .string("")), ("title", .string("T5")), ("year", .int(1997))]),
        .object([("doi", .string("https://doi.org/10.1037/1082-989x.2.2.173")), ("status", .string("got")), ("abstract", .string("   ")), ("title", .string("T6")), ("year", .int(1997))]),
        .object([("doi", .string(doi1Upper)), ("status", .string("got")), ("abstract", .string("Abstract one.")), ("title", .string("T1")), ("year", .int(1998))]),   // 近重複穿透
        .object([("doi", .string(forgingDOI)), ("status", .string("landing-failed")), ("abstract", .string("")), ("title", .string("T9")), ("year", .int(1999))]),   // 偽造嘗試
        .object([("doi", .string("https://doi.org/10.1037/1082-989x.9.9.999")), ("status", .string("got")), ("title", .string("T10")), ("year", .int(2004)),
                 ("abstract", .string("This DOI is not currently attached to any metadata records. DOIs can’t actually ever be deleted"))]),   // #544：錯誤頁
    ]

    static var ndjson: Data {
        Data([0xEF, 0xBB, 0xBF]) + Data(rows.map { ($0?.dumps() ?? "") + "\n" }.joined().utf8)
    }
    static var hex: String { SHA256.hash(data: ndjson).map { String(format: "%02x", $0) }.joined() }
    static var digest: String { "sha256:\(hex)" }

    private var tmp: URL!

    override func setUpWithError() throws {
        tmp = FileManager.default.temporaryDirectory.appendingPathComponent("abs-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: tmp) }

    /// 有 sources/ 的假 store：把 NDJSON 放在它的 digest 位置。
    private func store(blob: Data = AbstractProposalsTests.ndjson, at hex: String = AbstractProposalsTests.hex) throws -> LibraryStore {
        let root = tmp.appendingPathComponent("lib")
        let s = LibraryStore(root: root)
        let url = s.sourceBlobURL(digest: "sha256:\(hex)")!
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try blob.write(to: url)
        return s
    }

    private func convert(_ source: String, store: LibraryStore? = nil) throws -> (Conversion, String) {
        let resolved = try AbstractProposals.resolveSource(source) { d in store?.sourceBlobURL(digest: d) }
        let c = try AbstractProposals.convert(resolved.data, digest: resolved.digest)
        return (c, AbstractProposals.render(c.proposals))
    }

    typealias Conversion = AbstractProposals.Conversion

    static var expectedText: String {
        AbstractProposals.render([
            .object([("doi", .string(doi1)), ("fields", .object([("abstract", .string("Abstract one."))])), ("sourceDigest", .string(digest))]),
            .object([("doi", .string(doi1Upper)), ("fields", .object([("abstract", .string("Abstract one."))])), ("sourceDigest", .string(digest))]),
        ])
    }

    /// 輸出的形狀取自 Python 的 `json.dumps(…, ensure_ascii=False, indent=2, sort_keys=True) + "\n"`。
    func testOutputShapeMatchesPythonsSortedIndentedDump() {
        let text = AbstractProposals.render([.object([("doi", .string("10.1/é")), ("fields", .object([("abstract", .string("a\"b"))])), ("sourceDigest", .string("sha256:x"))])])
        XCTAssertEqual(text, "[\n  {\n    \"doi\": \"10.1/é\",\n    \"fields\": {\n      \"abstract\": \"a\\\"b\"\n    },\n    \"sourceDigest\": \"sha256:x\"\n  }\n]\n")
        XCTAssertEqual(AbstractProposals.render([]), "[]\n")
    }

    /// 1. digest 形：BOM 可讀；2 筆提案（近重複穿透）；8 列 skip 逐筆具名（含 Crossref 錯誤頁）；rows 不算空行。
    func testDigestFormReadsBOMAndReportsEverySkipByName() throws {
        let (c, text) = try convert(Self.digest, store: try store())
        XCTAssertEqual(text, Self.expectedText)
        XCTAssertEqual(c.skips.map(\.cause).sorted(),
                       ["conflicting-duplicate", "crossref-no-metadata", "duplicate-doi", "empty-abstract", "no-doi",
                        "status:landing-failed", "status:landing-failed", "status:none-verified"])
        XCTAssertEqual(c.skips.first { $0.cause == "no-doi" }, .init(cause: "no-doi", doi: "(no doi)", line: 7))
        XCTAssertEqual(c.rows, 10)
        let lines = AbstractProposals.reportLines(c)
        XCTAssertEqual(lines.last, "rows=10 proposals=2 skipped=8 (conflicting-duplicate=1, crossref-no-metadata=1, duplicate-doi=1, "
                       + "empty-abstract=1, no-doi=1, status:landing-failed=2, status:none-verified=1)")
    }

    /// 2. skip 報告不可偽造：換行／ESC 跳脫、長度截斷；FORGED 不得成為獨立一行。
    func testSkipReportCannotBeForged() throws {
        let (c, _) = try convert(Self.digest, store: try store())
        let lines = AbstractProposals.reportLines(c)
        let forged = lines.filter { $0.contains("FORGED") }
        XCTAssertEqual(forged.count, 1, lines.joined(separator: "\n"))
        XCTAssertTrue(forged[0].hasPrefix("skip\tstatus:landing-failed\t"), forged[0])
        XCTAssertFalse(lines.joined().contains("\u{1B}"))
        XCTAssertLessThan(forged[0].count, 400)
        XCTAssertFalse(lines.contains { $0.hasPrefix("skip\tno-doi\tFORGED") }, "偽造的 skip 行不得獨立成行")
    }

    /// 3. 路徑形：`sourceDigest` 由位元組算出，輸出與 digest 形逐位元相同。
    func testPathFormComputesTheDigestAndMatchesTheDigestForm() throws {
        let path = tmp.appendingPathComponent("blob.ndjson")
        try Self.ndjson.write(to: path)
        let (_, text) = try convert(path.path)
        XCTAssertEqual(text, Self.expectedText)
    }

    /// #703 R2 verify 第 12、23 則：整份讀進來的讀取面**有界**——超過上限的檔以 fstat 判、不讀、具名失敗（先前是無上限的 `Data(contentsOf:)`）。
    /// 大檔是 sparse 檔（真的常數，不佔磁碟）；注入的小上限驗「讀的時候長過上限」那一支之外的邊界。
    func testReadingIsBoundedByTheSourcesCap() throws {
        let huge = tmp.appendingPathComponent("huge.ndjson")
        XCTAssertTrue(FileManager.default.createFile(atPath: huge.path, contents: nil))
        let h = try FileHandle(forWritingTo: huge)
        try h.truncate(atOffset: UInt64(LibraryStore.maxSourceBytes + 1))
        try h.close()
        XCTAssertThrowsError(try AbstractProposals.resolveSource(huge.path, blobURL: { _ in nil })) { e in
            XCTAssertTrue(e.skillMessage.contains("超過上限") && e.skillMessage.contains("256 MiB"), e.skillMessage)
        }
        let small = tmp.appendingPathComponent("small.ndjson")
        try Data(repeating: 0x41, count: 10).write(to: small)
        XCTAssertEqual(try AbstractProposals.readFile(small, limit: 10).count, 10, "上限本身可以讀")
        XCTAssertThrowsError(try AbstractProposals.readFile(small, limit: 9))
    }

    /// 4. 大寫 hex 仍是 digest 形：解析成功，`sourceDigest` 以小寫輸出。
    func testUppercaseHexIsStillADigestForm() throws {
        let (_, text) = try convert("sha256:" + Self.hex.uppercased(), store: try store())
        XCTAssertEqual(text, Self.expectedText)
    }

    /// 6. 內容定址：digest 對不上內容 → 拒絕、零輸出。
    func testContentAddressMismatchIsRefused() throws {
        let bad = String(repeating: "0", count: 64)
        let s = try store(blob: Self.ndjson, at: bad)
        XCTAssertThrowsError(try convert("sha256:\(bad)", store: s)) { XCTAssertTrue("\($0)".contains("內容定址不符"), "\($0)") }
    }

    /// 7. 找不到存檔 → 訊息含路徑；格式錯的 digest → 具名拒絕（不落到路徑形）。
    func testMissingBlobAndMalformedDigestAreNamed() throws {
        let s = try store()
        XCTAssertThrowsError(try convert("sha256:" + String(repeating: "f", count: 64), store: s)) {
            XCTAssertTrue("\($0)".contains("sources/ff/"), "\($0)")
        }
        XCTAssertThrowsError(try convert("sha256:notahash", store: s)) {
            XCTAssertTrue("\($0)".contains("digest"), "\($0)")
            XCTAssertFalse("\($0)".contains("檔案不存在"), "\($0)")
        }
        XCTAssertThrowsError(try convert("SHA256:" + Self.hex, store: s)) { XCTAssertTrue("\($0)".contains("不是合法的 digest"), "\($0)") }
    }

    /// 8. 非 UTF-8、壞的一行：具名訊息。
    func testInvalidInputIsNamedNotCrashed() throws {
        XCTAssertThrowsError(try AbstractProposals.convert(Data([0xFF, 0xFE, 0x00] + Array("garbage\n".utf8)), digest: "sha256:x")) {
            XCTAssertTrue($0.skillMessage.hasPrefix("✗ 存檔不是 UTF-8"), $0.skillMessage)
        }
        // Python 的 `utf-8-sig` 報的壞位元組位置是**去掉 BOM 之後**的（有沒有 BOM 都是 3）
        for bom in [Data(), Data([0xEF, 0xBB, 0xBF])] {
            XCTAssertThrowsError(try AbstractProposals.convert(bom + Data("abc".utf8) + Data([0xFF]), digest: "sha256:x")) {
                XCTAssertTrue($0.skillMessage.contains("byte 3"), $0.skillMessage)
            }
        }
        XCTAssertThrowsError(try AbstractProposals.convert(Data("{\"doi\": \"a\"}\nnot json\n".utf8), digest: "sha256:x")) {
            XCTAssertTrue($0.skillMessage.hasPrefix("✗ 第 2 行不是合法 JSON"), $0.skillMessage)
        }
        XCTAssertThrowsError(try AbstractProposals.convert(Data("[1,2]\n".utf8), digest: "sha256:x")) {
            XCTAssertTrue($0.skillMessage.hasPrefix("✗ 第 1 行不是 JSON 物件"), $0.skillMessage)
        }
    }

    /// 「重複」只認逐位元相同：NFC 與 NFD 的同一個 DOI 是兩筆（Swift 的 `String ==` 會把它們當成同一個，Python 不會）。
    func testDuplicatesAreByteExactNotCanonicallyEquivalent() throws {
        let nfc = "10.1/caf\u{E9}", nfd = "10.1/cafe\u{301}"
        let lines = [nfc, nfd, nfc].map { "{\"doi\": \(PyJSON.string($0).dumps()), \"status\": \"got\", \"abstract\": \"A\"}\n" }.joined()
        let c = try AbstractProposals.convert(Data(lines.utf8), digest: "sha256:x")
        XCTAssertEqual(c.proposals.count, 2)
        XCTAssertEqual(c.skips.map(\.cause), ["duplicate-doi"])
        XCTAssertEqual(c.skips.first?.line, 3)
    }

    /// 摘要相同與否也按位元組判：只差 NFC／NFD 的摘要是「衝突」，不是「冗餘」。
    func testAbstractComparisonIsByteExact() throws {
        let doi = "10.1/x"
        let lines = ["caf\u{E9}", "cafe\u{301}"].map { "{\"doi\": \"\(doi)\", \"status\": \"got\", \"abstract\": \(PyJSON.string($0).dumps())}\n" }.joined()
        XCTAssertEqual(try AbstractProposals.convert(Data(lines.utf8), digest: "sha256:x").skips.map(\.cause), ["conflicting-duplicate"])
    }

    /// `status` 不是字串時，理由是 Python 的 `str(x)`（`None`、`True`、`3`）。
    func testNonStringStatusReasonsUsePythonStr() throws {
        let lines = ["{\"doi\": \"a\", \"abstract\": \"A\"}", "{\"doi\": \"b\", \"status\": true, \"abstract\": \"A\"}",
                     "{\"doi\": \"c\", \"status\": 3, \"abstract\": \"A\"}", "{\"doi\": \"d\", \"status\": null, \"abstract\": \"A\"}"].joined(separator: "\n")
        XCTAssertEqual(try AbstractProposals.convert(Data(lines.utf8), digest: "sha256:x").skips.map(\.cause),
                       ["status:None", "status:True", "status:3", "status:None"])
    }

    /// Python 的 `splitlines()` 把 U+2028 當行界，所以一列裡含裸 U+2028 的合法 JSON 會被切成兩半而具名拒絕——與舊腳本同（誠實邊界，不修）。
    func testLineSplittingFollowsPythonSplitlines() {
        let raw = "{\"doi\": \"a\", \"status\": \"got\", \"abstract\": \"x\u{2028}y\"}\n"
        XCTAssertThrowsError(try AbstractProposals.convert(Data(raw.utf8), digest: "sha256:x")) { XCTAssertTrue("\($0)".contains("第 1 行不是合法 JSON"), "\($0)") }
    }

    // MARK: `--out`

    private func write(_ path: String, _ text: String = "NEW\n") throws -> [String] {
        var announced: [String] = []
        try AbstractProposals.writeOut(path: path, text: text) { announced.append($0) }
        return announced
    }

    /// 5. 覆寫既有普通檔仍是常態路徑（沒有 `--force`）；解析後的絕對路徑一律印出；無 temp 殘骸；權限變 0600（刻意）。
    func testOverwritingARegularFileIsTheNormalPathAndPrintsTheAbsolutePath() throws {
        let plain = tmp.appendingPathComponent("again.json")
        try Data("OLD\n".utf8).write(to: plain)
        try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: plain.path)
        let announced = try write(plain.path)
        XCTAssertEqual(try String(contentsOf: plain, encoding: .utf8), "NEW\n")
        XCTAssertTrue(announced.first?.contains(plain.path) == true, "\(announced)")   // 比對未解析的絕對路徑（$TMPDIR 是 /var → /private/var）
        XCTAssertFalse(try FileManager.default.contentsOfDirectory(atPath: tmp.path).contains { $0.hasSuffix(".tmp") })
        XCTAssertEqual((try FileManager.default.attributesOfItem(atPath: plain.path)[.posixPermissions] as? NSNumber)?.intValue, 0o600)
    }

    /// 9. symlink 目標不得被改動、symlink 本身留著；目錄拒絕。
    func testSymlinkAndDirectoryTargetsAreRefusedWithZeroWrites() throws {
        let victim = tmp.appendingPathComponent("victim.txt")
        try Data("SACRED\n".utf8).write(to: victim)
        let link = tmp.appendingPathComponent("outlink.json")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: victim)
        XCTAssertThrowsError(try write(link.path)) {
            XCTAssertTrue("\($0)".contains("symlink"), "\($0)")
            XCTAssertTrue("\($0)".contains("跟隨它會改到另一條路徑上的檔"), "括號裡那句只對 symlink 為真：\($0)")
        }
        XCTAssertEqual(try String(contentsOf: victim, encoding: .utf8), "SACRED\n", "symlink 的目標被改動了——這正是 #516 verify 實測到的逃逸")
        XCTAssertEqual((try? FileManager.default.destinationOfSymbolicLink(atPath: link.path)), victim.path, "symlink 本身被取代了")

        let dir = tmp.appendingPathComponent("adir")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        XCTAssertThrowsError(try write(dir.path)) {
            XCTAssertTrue("\($0)".contains("目錄"), "\($0)")
            XCTAssertFalse("\($0)".contains("跟隨它"), "對目錄講「跟隨它」是假的：\($0)")
        }
    }

    func testMissingOutDirectoryIsNamedNotCrashed() {
        XCTAssertThrowsError(try write(tmp.appendingPathComponent("no-such-dir/p.json").path)) {
            XCTAssertTrue($0.skillMessage.hasPrefix("✗ 無法寫入 --out"), $0.skillMessage)
        }
    }

    func testAbsolutePathIsLexicalAndDoesNotFollowSymlinks() throws {
        XCTAssertEqual(AbstractProposals.absolutePath("/a/b/../c/./d//e"), "/a/c/d/e")
        XCTAssertEqual(AbstractProposals.absolutePath("/../x"), "/x")
        let cwd = FileManager.default.currentDirectoryPath
        XCTAssertEqual(AbstractProposals.absolutePath("rel/x.json"), cwd + "/rel/x.json")
        XCTAssertEqual(AbstractProposals.absolutePath("~/x.json"), (("~/x.json" as NSString).expandingTildeInPath))
    }
}
