import XCTest
@testable import AkashicCore

/// #695：`enrich` 的來源欄位（`sourceURL`／`sourceRetrieved`／`sourceStatus`）寫的是 retrieval reference，與 person／venue 的
/// `references`（#674）走**同一份**形狀檢查——url 只收 http／https、主機非空、不含帳密；retrieved 是 ISO 8601；status 在 100–599，
/// 而且給了 url／retrieved／media type 就必填（不預設 200）。形狀不合的提案**整批拒絕、具名**（`InputError.invalidProposal`），零寫入。
///
/// 使用者 2026-09-30 裁決：「要，共用同一個解析函式」。先前這三欄只驗長度：`ftp:`、帶帳密的 url、`2026/09/09`、`status: 0` 都照寫進 store。
final class EnrichRetrievalShapeTests: XCTestCase {

    private let digest = "sha256:" + String(repeating: "b", count: 64)
    private func entry() -> Entry { Entry(id: UUID(), citekey: "a2020x", type: .periodicalArticle, title: "T") }

    /// 基底提案：四欄齊備、形狀合法。
    private func proposal(_ mutate: (inout AddOnlyEnrichment.Proposal) -> Void = { _ in }) -> AddOnlyEnrichment.Proposal {
        var p = AddOnlyEnrichment.Proposal(
            citekey: "a2020x", fields: ["abstract": "一段摘要"], sourceDigest: digest,
            sourceURL: "https://api.crossref.org/works/10.1037/x", sourceRetrieved: "2026-09-09",
            sourceMediaType: "application/json", sourceStatus: 200)
        mutate(&p)
        return p
    }

    /// 整批拒絕的理由（`InputError.invalidProposal` 的 reason）；沒丟或丟了別的就失敗。
    private func refusal(_ proposals: [AddOnlyEnrichment.Proposal], file: StaticString = #filePath, line: UInt = #line) -> (index: Int, reason: String)? {
        do {
            _ = try AddOnlyEnrichment.plan(entries: [entry()], proposals: proposals)
            XCTFail("應整批拒絕，卻產生了計畫", file: file, line: line)
            return nil
        } catch AddOnlyEnrichment.InputError.invalidProposal(let index, let reason) {
            return (index, reason)
        } catch {
            XCTFail("應是 invalidProposal，得 \(error)", file: file, line: line)
            return nil
        }
    }

    private struct Case {
        let label: String
        let needles: [String]
        let mutate: (inout AddOnlyEnrichment.Proposal) -> Void
        init(_ label: String, _ needles: [String], _ mutate: @escaping (inout AddOnlyEnrichment.Proposal) -> Void) {
            self.label = label; self.needles = needles; self.mutate = mutate
        }
    }

    /// 每一格都整批拒絕，理由指名是哪個來源鍵、說出哪一種錯。
    func testMalformedSourceFieldsRefuseTheWholeBatch() {
        let cases: [Case] = [
            Case("url 是 ftp", ["sourceURL", "http／https", "scheme 是「ftp」"]) { $0.sourceURL = "ftp://example.org/x" },
            Case("url 是 file（離線來源）", ["sourceURL", "http／https", "只給 sourceDigest"]) { $0.sourceURL = "file:///tmp/scan.pdf" },
            Case("url 沒有 scheme", ["sourceURL", "http／https"]) { $0.sourceURL = "example.org/x" },
            Case("url 是 javascript:", ["sourceURL", "http／https"]) { $0.sourceURL = "javascript:alert(1)" },
            Case("url 前面有空白", ["sourceURL", "http／https"]) { $0.sourceURL = " https://example.org/x" },
            Case("url 只有空白", ["sourceURL", "http／https"]) { $0.sourceURL = "  " },
            Case("url 缺主機", ["sourceURL", "主機"]) { $0.sourceURL = "https:///path" },
            Case("url 帶帳密", ["sourceURL", "帳密"]) { $0.sourceURL = "https://user:s3cret@example.org/x" },
            Case("url 帶只有 user 的 userinfo", ["sourceURL", "帳密"]) { $0.sourceURL = "https://token@example.org/x" },
            Case("retrieved 斜線日期", ["sourceRetrieved", "ISO 8601"]) { $0.sourceRetrieved = "2026/09/09" },
            Case("retrieved 月份 13", ["sourceRetrieved", "ISO 8601"]) { $0.sourceRetrieved = "2026-13-01" },
            Case("retrieved 只有年月", ["sourceRetrieved", "ISO 8601"]) { $0.sourceRetrieved = "2026-09" },
            Case("retrieved 時間後接垃圾", ["sourceRetrieved", "ISO 8601"]) { $0.sourceRetrieved = "2026-09-09T10:00:00 UTC" },
            Case("status 低於 100", ["sourceStatus", "100–599"]) { $0.sourceStatus = 99 },
            Case("status 高於 599", ["sourceStatus", "100–599"]) { $0.sourceStatus = 600 },
            Case("status 是 0", ["sourceStatus", "100–599"]) { $0.sourceStatus = 0 },
            Case("缺 status（url、retrieved、digest 都給了）", ["沒有 status", "sourceStatus", "不預設 200"]) { $0.sourceStatus = nil },
            Case("缺 status（只給 url）", ["沒有 status"]) {
                $0.sourceStatus = nil; $0.sourceDigest = nil; $0.sourceRetrieved = nil; $0.sourceMediaType = nil
            },
            Case("缺 status（只給 retrieved）", ["沒有 status"]) {
                $0.sourceStatus = nil; $0.sourceDigest = nil; $0.sourceURL = nil; $0.sourceMediaType = nil
            },
            Case("缺 status（digest 加 media type）", ["沒有 status"]) {
                $0.sourceStatus = nil; $0.sourceURL = nil; $0.sourceRetrieved = nil
            },
        ]
        for c in cases {
            guard let r = refusal([proposal(c.mutate)]) else { XCTFail(c.label); continue }
            XCTAssertEqual(r.index, 1, c.label)
            for n in c.needles { XCTAssertTrue(r.reason.contains(n), "\(c.label)：要說出「\(n)」，實得 \(r.reason)") }
        }
    }

    /// #695 R1 verify 第 6／10 列：`@` 後面緊跟 Extend 字元（組合符號 U+0301、ZWJ U+200D、VS16 U+FE0F）時，Swift 的 `Character`
    /// 把兩者合成一個 grapheme，`contains("@")` 為 false——兩席以真 binary 把帳密寫進了 store。定界符在 scalar 上找，三種都說帳密。
    /// 帳密排在危險 scalar 之前，所以 ZWJ（Cf）那一格說的也是帳密——恢復 `Character` 掃描的反向編輯會讓三格都紅。
    func testAnAtSignFollowedByAnExtendScalarIsStillCredentials() {
        for (label, url) in [("@ 後接 U+0301", "https://user:secret@\u{0301}example.org/x"),
                             ("@ 後接 U+200D", "https://user:secret@\u{200D}example.org/x"),
                             ("@ 後接 U+FE0F", "https://user:secret@\u{FE0F}example.org/x"),
                             ("token@ 後接 U+0301", "https://token@\u{0301}example.org/x")] {
            guard let r = refusal([proposal { $0.sourceURL = url }]) else { XCTFail(label); continue }
            XCTAssertTrue(r.reason.contains("sourceURL") && r.reason.contains("帳密"), "\(label)：\(r.reason)")
            XCTAssertFalse(r.reason.contains("secret") || r.reason.contains("example.org"), "\(label)：不回顯：\(r.reason)")
        }
    }

    /// #695 R1 verify 第 19 列：控制字元、格式字元（方向控制）、NUL、換行、空白——url、retrieved、media type 三欄都拒絕。
    /// url 整串不收空白（RFC 3986：要編成 %20）；media type 內部的空白照收（`text/html; charset=utf-8`），前後的不收；
    /// retrieved 的文法逐位元組比到結尾，這幾種本來就過不了——這裡釘住它們繼續過不了。
    func testUnsafeScalarsAndStrayWhitespaceAreRefused() {
        let cases: [Case] = [
            Case("url 主機裡有換行", ["sourceURL", "控制字元"]) { $0.sourceURL = "https://exa\nmple.org/x" },
            Case("url 路徑裡有換行", ["sourceURL", "控制字元"]) { $0.sourceURL = "https://example.org/x\nsecret" },
            Case("url 是 NUL 主機", ["sourceURL", "控制字元"]) { $0.sourceURL = "https://\u{0}" },
            Case("url 主機內嵌空白", ["sourceURL", "空白"]) { $0.sourceURL = "https://exa mple.org" },
            Case("url 尾端空白", ["sourceURL", "空白"]) { $0.sourceURL = "https://example.org " },
            Case("url 路徑有 RLO", ["sourceURL", "格式字元"]) { $0.sourceURL = "https://example.org/\u{202E}gnp.exe" },
            Case("url 路徑有 ZWSP", ["sourceURL", "格式字元"]) { $0.sourceURL = "https://example.org/a\u{200B}b" },
            Case("url 主機有反斜線", ["sourceURL", "反斜線"]) { $0.sourceURL = "https://example.org\\x/y" },
            Case("retrieved 尾端空白", ["sourceRetrieved", "ISO 8601"]) { $0.sourceRetrieved = "2026-09-09 " },
            Case("retrieved 尾端換行", ["sourceRetrieved", "ISO 8601"]) { $0.sourceRetrieved = "2026-09-09\n" },
            Case("retrieved 帶 NUL", ["sourceRetrieved", "ISO 8601"]) { $0.sourceRetrieved = "2026-09-09\u{0}" },
            Case("retrieved 偏移沒有冒號", ["sourceRetrieved", "偏移要帶冒號"]) { $0.sourceRetrieved = "2026-09-30T12:00:00+0800" },
            Case("media type 帶 RLO", ["sourceMediaType", "格式字元"]) { $0.sourceMediaType = "text/html\u{202E}" },
            Case("media type 前導空白", ["sourceMediaType", "前後空白"]) { $0.sourceMediaType = " text/html" },
            Case("media type 尾端空白", ["sourceMediaType", "前後空白"]) { $0.sourceMediaType = "text/html " },
            Case("media type 帶換行", ["sourceMediaType", "控制字元"]) { $0.sourceMediaType = "text/\nhtml" },
            Case("media type 帶 NUL", ["sourceMediaType", "控制字元"]) { $0.sourceMediaType = "text/html\u{0}" },
        ]
        for c in cases {
            guard let r = refusal([proposal(c.mutate)]) else { XCTFail(c.label); continue }
            for n in c.needles { XCTAssertTrue(r.reason.contains(n), "\(c.label)：要說出「\(n)」，實得 \(r.reason)") }
        }
        // 內部空白的 media type 照收
        XCTAssertNoThrow(try AddOnlyEnrichment.plan(entries: [entry()], proposals: [proposal { $0.sourceMediaType = "text/html; charset=utf-8" }]))
    }

    /// 帳密不回顯——拒絕訊息進 MCP 的對話紀錄與終端。
    func testCredentialsAreNeverEchoed() {
        let r = refusal([proposal { $0.sourceURL = "https://alice:hunter2@example.org/x?token=abc" }])
        let why = r?.reason ?? ""
        XCTAssertFalse(why.contains("hunter2") || why.contains("alice") || why.contains("token=abc"), why)
    }

    /// 一筆壞的讓**整批**零寫入：前面合法的那筆也不產生計畫；理由指名第幾筆。
    func testOneMalformedProposalRefusesTheWholeBatch() {
        let good = proposal()
        let bad = proposal { $0.citekey = "a2020x"; $0.sourceURL = "ftp://example.org/x" }
        let r = refusal([good, bad])
        XCTAssertEqual(r?.index, 2, "要指名第 2 筆")
    }

    /// 與 #674 同一個先後：一筆什麼都沒給對的來源，先被告知的是缺 status。
    func testMissingStatusIsReportedBeforeAMalformedURLOrRetrieved() {
        let r = refusal([proposal { $0.sourceStatus = nil; $0.sourceURL = "u"; $0.sourceRetrieved = "d" }])
        XCTAssertTrue(r?.reason.contains("沒有 status") == true, r?.reason ?? "")
    }

    /// 兩面同一個解碼器：蛇形別名（`source_url`／`source_retrieved`／`source_status`）落到同一個欄位、同一道檢查。
    func testSnakeCaseAliasesGoThroughTheSameCheck() throws {
        let json = #"[{"citekey":"a2020x","fields":{"abstract":"x"},"source_digest":"\#(digest)","source_url":"ftp://example.org/x","source_retrieved":"2026-09-09","source_status":200}]"#
        let proposals = try AddOnlyEnrichment.decodeProposals(from: Data(json.utf8))
        XCTAssertTrue(refusal(proposals)?.reason.contains("http／https") == true)
    }

    /// 形狀合法的照寫：url 帶 port／IPv6、scheme 大小寫不拘、retrieved 帶時區、404 也是內容——每個補進去的欄位一筆 retrieval。
    func testWellFormedSourcesStillWriteTheirReference() throws {
        let variants: [(String, String, Int)] = [
            ("https://example.org:8443/x", "2026-09-09", 200),
            ("HTTPS://Example.org/x", "2026-09-09T14:30:00+08:00", 200),
            ("http://[2001:db8::1]/x", "2026-09-09T06:30:00Z", 404),
        ]
        for (u, ret, st) in variants {
            let p = proposal { $0.sourceURL = u; $0.sourceRetrieved = ret; $0.sourceStatus = st }
            let item = try XCTUnwrap(try AddOnlyEnrichment.plan(entries: [entry()], proposals: [p]).items.first)
            XCTAssertEqual(item.outcome.addedReferences.map(\.field), ["fields.abstract"], u)
            guard case .retrieval(let url, let retrieved, let status, _, _) = try XCTUnwrap(item.outcome.addedReferences.first).kind else {
                return XCTFail(u)
            }
            XCTAssertEqual([url, retrieved, "\(status)"], [u, ret, "\(st)"])
        }
    }

    /// 只給 digest 不是在寫 reference——它是回顯（#517；階段 B 的摘要提案就是這個形）。不拒絕，理由照舊進 `provenanceSkipped`。
    /// digest 加 status、沒有 url 同樣不是：status 在了，缺的是 url／retrieved，照舊略過並具名。
    func testDigestOnlyAndIncompleteWithStatusAreStillSkippedNotRefused() throws {
        for p in [proposal { $0.sourceURL = nil; $0.sourceRetrieved = nil; $0.sourceMediaType = nil; $0.sourceStatus = nil },
                  proposal { $0.sourceURL = nil; $0.sourceRetrieved = nil; $0.sourceMediaType = nil }] {
            let item = try XCTUnwrap(try AddOnlyEnrichment.plan(entries: [entry()], proposals: [p]).items.first)
            XCTAssertTrue(item.outcome.addedReferences.isEmpty)
            XCTAssertTrue(try XCTUnwrap(item.outcome.provenanceSkipped).contains("sourceURL"))
            XCTAssertEqual(item.outcome.addedFields["abstract"], "一段摘要", "值照補")
        }
    }
}
