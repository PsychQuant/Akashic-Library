import XCTest
@testable import AkashicCore
@testable import AkashicStoreIO
@testable import AkashicMCPKit

/// #695 R2 verify 的 LOW（2026-10-01）：擷取型 reference 的形狀函式（`RetrievalWriteShape`）在兩個面——`enrich` 的來源欄位與
/// person／venue 的 `references`——同一個函式、同一句話。每一格都兩面各驗一次：一個面收緊、另一個沒跟上，就在這裡紅。
final class RetrievalWriteShapeR2Tests: XCTestCase {
    var root: URL!
    var fakeHome: URL!
    var env: [String: String] { ["AKASHIC_HOME": fakeHome.path] }
    let digest = "sha256:" + String(repeating: "c", count: 64)
    let alpha = UUID()

    override func setUpWithError() throws {
        fakeHome = FileManager.default.temporaryDirectory.appendingPathComponent("akashic-home-\(UUID().uuidString)")
        root = FileManager.default.temporaryDirectory.appendingPathComponent("akashic-695r2-\(UUID().uuidString)")
        let store = LibraryStore(root: root)
        try store.ensureLayout()
        try store.writeEntry(Entry(id: alpha, citekey: "anon2020x", type: .periodicalArticle, title: "Anon"))
        try store.writePerson(Person(key: "p-one", names: PersonNames(authorized: ["Che Cheng"])))
    }
    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
        try? FileManager.default.removeItem(at: fakeHome)
    }

    private var service: AkashicService { AkashicService(root: root, environment: env) }

    private func message(_ error: Error) -> String {
        if case ServiceError.invalid(let why) = error { return why }
        return "\(error)"
    }

    private struct Shape {
        var url: String? = "https://example.org/x"
        var retrieved: String? = "2026-09-30"
        var status: Int? = 200
        var mediaType: String? = nil
    }

    private func enrichProposal(_ s: Shape, digest d: String? = nil) -> AddOnlyEnrichment.Proposal {
        .init(citekey: "anon2020x", fields: ["abstract": "摘要"], sourceDigest: d ?? digest,
              sourceURL: s.url, sourceRetrieved: s.retrieved, sourceMediaType: s.mediaType, sourceStatus: s.status)
    }
    private func personReference(_ s: Shape) -> [String: Any] {
        var d: [String: Any] = ["field": "openalex", "kind": "retrieval", "content": digest]
        if let u = s.url { d["url"] = u }
        if let r = s.retrieved { d["retrieved"] = r }
        if let st = s.status { d["status"] = st }
        if let m = s.mediaType { d["media_type"] = m }
        return d
    }

    /// 兩面都拒絕；回兩面的訊息（enrich 以 dry-run 驗——拒絕在任何寫入之前）。
    private func refusals(_ s: Shape, file: StaticString = #filePath, line: UInt = #line) -> (enrich: String, person: String) {
        var e = "", p = ""
        XCTAssertThrowsError(try service.enrich(proposals: [enrichProposal(s)], dryRun: true, includeAbsentAuthors: false),
                             "enrich 應拒絕", file: file, line: line) { e = message($0) }
        XCTAssertThrowsError(try service.updatePerson(key: "p-one", fields: ["references": [personReference(s)]], dryRun: true),
                             "person references 應拒絕", file: file, line: line) { p = message($0) }
        return (e, p)
    }

    /// 第 15 列：帳密掃描只認 ASCII 定界符——全形／小寫形的 `＠`／`：`、`℀`（a/c）與非數字的 port 都把帳密帶進過 store。
    /// 主機部分任何相容分解含 `@ : / ? # \` 的非 ASCII scalar 拒絕；port 只收 ASCII 數字。都不回顯原值。
    func testCompatibilityDelimitersAndNonNumericPortsAreRefusedOnBothFaces() {
        let cases: [(String, String, String)] = [
            ("全形 ＠", "https://user:secret\u{FF20}example.org/a", "相容形的定界符"),
            ("全形 ： 與 ＠", "https://user\u{FF1A}secret\u{FF20}example.org/", "相容形的定界符"),
            ("小寫形 ﹫", "https://secret\u{FE6B}example.org/", "相容形的定界符"),
            ("℀（相容分解是 a/c）", "https://secret\u{2100}example.org/", "相容形的定界符"),
            ("全形 ／ 在主機裡", "https://example.org\u{FF0F}secret/", "相容形的定界符"),
            ("非數字 port", "https://example.org:secret/a", "port 不是數字"),
            ("百分比編碼的 @ 落在 port", "https://user:secret%40example.org/a", "port 不是數字"),
            ("全形數字的 port", "https://example.org:\u{FF18}\u{FF10}/", "port 不是數字"),
            ("IPv6 之後接垃圾", "https://[2001:db8::1]secret/", "port 不是數字"),
        ]
        for (label, url, needle) in cases {
            let r = refusals(Shape(url: url))
            for (face, why) in [("enrich", r.enrich), ("person", r.person)] {
                XCTAssertTrue(why.contains(needle), "\(face)：\(label)：要說出「\(needle)」，實得 \(why)")
                XCTAssertFalse(why.contains("secret"), "\(face)：\(label)：不回顯原值：\(why)")
            }
        }
        // 合法形不受影響：IDN 主機、全形句點（相容分解是 `.`，不是定界符）、空 port（RFC 3986 收）、IPv6 加 port
        for ok in ["https://例え.jp/パス", "https://example\u{FF0E}org/x", "https://example.org:/x", "https://[2001:db8::1]:8443/x"] {
            XCTAssertNoThrow(try service.enrich(proposals: [enrichProposal(Shape(url: ok))], dryRun: true, includeAbsentAuthors: false), ok)
        }
    }

    /// 第 7／11 列：scheme 前綴在 scalar 上比。`https://` 後面緊跟組合符號時第二個 `/` 與它合成一個 `Character`，
    /// 先前落到「只收 http／https」；前面多了空白或隱形字元的 http(s) 網址錯的是那些字元，不是 scheme。
    func testTheSchemePrefixIsComparedOnScalars() {
        let cases: [(String, String, String)] = [
            ("https:// 後接 U+0301 再接帳密", "https://\u{0301}user:pw@example.org/", "含帳密"),
            ("https:// 後接 ZWNJ", "https://\u{200C}example.org/", "含控制字元、格式字元"),
            ("前導空白", " https://example.org/", "含控制字元、格式字元（方向控制、零寬字元等）或空白"),
            ("前導 ZWSP", "\u{200B}https://example.org/", "含控制字元、格式字元"),
        ]
        for (label, url, needle) in cases {
            let r = refusals(Shape(url: url))
            for (face, why) in [("enrich", r.enrich), ("person", r.person)] {
                XCTAssertTrue(why.contains(needle), "\(face)：\(label)：要說出「\(needle)」，實得 \(why)")
                XCTAssertFalse(why.contains("只收 http／https"), "\(face)：\(label)：它的 scheme 是 https：\(why)")
            }
        }
    }

    /// 第 1／6／14 列：控制／格式字元的拒絕涵蓋整條網址（路徑、query 也是，fail-closed），而補救是編碼、不是刪除——
    /// 波斯文「心理學」詞中的 ZWNJ 拿掉就是另一個頁面。百分比編碼形照收。
    func testTheRemedyForInvisibleCharactersIsEncodingNotRemoval() throws {
        let raw = "https://fa.wikipedia.org/wiki/\u{0631}\u{0648}\u{0627}\u{0646}\u{200C}\u{0634}\u{0646}\u{0627}\u{0633}\u{06CC}"
        let r = refusals(Shape(url: raw))
        for (face, why) in [("enrich", r.enrich), ("person", r.person)] {
            XCTAssertTrue(why.contains("%E2%80%8C") && why.contains("punycode") && why.contains("百分比編碼"), "\(face)：\(why)")
            XCTAssertFalse(why.contains("拿掉再送"), "\(face)：拿掉會改成另一個網址：\(why)")
        }
        let encoded = "https://fa.wikipedia.org/wiki/%D8%B1%D9%88%D8%A7%D9%86%E2%80%8C%D8%B4%D9%86%D8%A7%D8%B3%DB%8C"
        XCTAssertNoThrow(try service.enrich(proposals: [enrichProposal(Shape(url: encoded))], dryRun: true, includeAbsentAuthors: false))
    }

    /// 第 10／18 列：回顯的原值排在理由之後、以逃脫後的長度截——兩百個 TAG 字元（每個逃脫成 `\u{E0041}`）時，
    /// 理由（「不是 ISO 8601」）與 enrich 的「整批拒絕」仍在，錯誤出口截掉的只會是原值的尾巴。
    func testTheReasonSurvivesAnEchoMadeOfInvisibleScalars() {
        for (label, value) in [("TAG ×200", String(repeating: "\u{E0041}", count: 200)),
                               ("ZWSP ×120", String(repeating: "\u{200B}", count: 120))] {
            let r = refusals(Shape(retrieved: value))
            XCTAssertTrue(r.enrich.contains("不是 ISO 8601") && r.enrich.contains("整批拒絕"), "enrich：\(label)：\(r.enrich)")
            XCTAssertTrue(r.person.contains("不是 ISO 8601"), "person：\(label)：\(r.person)")
            for (face, why) in [("enrich", r.enrich), ("person", r.person)] {
                XCTAssertLessThanOrEqual(why.count, 400, "\(face)：\(label)：整句要放得進 CLI 每行 400：\(why.count)")
                XCTAssertTrue(why.contains("收到的值：「") && why.contains("…」"), "\(face)：\(label)：原值截了、有標記：\(why)")
            }
        }
        // 可見的原值照全文回顯（常見錯形 24 字，在 48 的預算之內）
        let r = refusals(Shape(retrieved: "2026-09-30T12:00:00+0800"))
        XCTAssertTrue(r.enrich.contains("收到的值：「2026-09-30T12:00:00+0800」"), r.enrich)
        XCTAssertTrue(r.person.contains("收到的值：「2026-09-30T12:00:00+0800」"), r.person)
    }

    /// 第 8 列：空的（或只有空白的）media type——references 面先前存成 `media-type: ''`；enrich 面的空字串視同沒給，
    /// 先前卻原樣寫進 reference。現在 references 面拒絕，enrich 面寫出的 reference 沒有 media type。
    func testAnEmptyMediaTypeIsNeverStored() throws {
        for m in ["", "   "] {
            XCTAssertThrowsError(try service.updatePerson(key: "p-one", fields: ["references": [personReference(Shape(mediaType: m))]], dryRun: true)) {
                XCTAssertTrue(message($0).contains("references[0].media_type 是空的"), message($0))
            }
        }
        XCTAssertThrowsError(try service.enrich(proposals: [enrichProposal(Shape(mediaType: "   "))], dryRun: true, includeAbsentAuthors: false)) {
            XCTAssertTrue(message($0).contains("sourceMediaType 是空的"), message($0))
        }
        _ = try service.enrich(proposals: [enrichProposal(Shape(mediaType: ""))], dryRun: false, includeAbsentAuthors: false)
        let e = try XCTUnwrap(try LibraryStore(root: root).load().entries.first { $0.citekey == "anon2020x" })
        let ref = try XCTUnwrap(e.references.first { $0.field == "fields.abstract" })
        guard case .retrieval(_, _, _, let mediaType, _) = ref.kind else { return XCTFail("\(ref)") }
        XCTAssertNil(mediaType, "空字串視同沒給，不寫成 media-type: ''")
    }

    /// 第 12 列：`sourceDigest` 驗的是寫進去的那個值——先前以 trim 過的值驗、以原值寫，乾跑說會寫、apply 被寫入閘拒絕。
    func testASourceDigestWithSurroundingWhitespaceIsRefusedAtPlanTime() {
        for d in [" \(digest)", "\(digest)\n"] {
            XCTAssertThrowsError(try service.enrich(proposals: [enrichProposal(Shape(), digest: d)], dryRun: true, includeAbsentAuthors: false)) {
                XCTAssertTrue(message($0).contains("sourceDigest 前後有空白或換行"), message($0))
            }
        }
    }

    /// 第 3 列：只給 digest 是離線來源的做法，報告不說「不齊」；第 17 列：帳密的拒絕只宣稱 retrieval reference 的 url。
    func testWordingOfTheDigestOnlyEchoAndTheCredentialsRefusal() throws {
        let p = AddOnlyEnrichment.Proposal(citekey: "anon2020x", fields: ["abstract": "摘要"], sourceDigest: digest)
        let item = try XCTUnwrap(try AddOnlyEnrichment.plan(entries: [Entry(id: alpha, citekey: "anon2020x", type: .periodicalArticle, title: "A")],
                                                            proposals: [p]).items.first)
        let why = try XCTUnwrap(item.outcome.provenanceSkipped)
        XCTAssertTrue(why.hasPrefix("只給了 sourceDigest：回顯、不寫 reference（離線來源的做法）"), why)
        XCTAssertFalse(why.contains("不齊"), why)
        XCTAssertTrue(why.contains("sourceStatus"), "要記網路取得就四欄一起給，含 status：\(why)")

        let r = refusals(Shape(url: "https://u:p@example.org/x"))
        for (face, m) in [("enrich", r.enrich), ("person", r.person)] {
            XCTAssertTrue(m.contains("不得寫進 retrieval reference 的 url"), "\(face)：\(m)")
        }
    }
}
