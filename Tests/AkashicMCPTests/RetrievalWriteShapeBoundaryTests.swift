import XCTest
@testable import AkashicCore
@testable import AkashicStoreIO
@testable import AkashicMCPKit

/// #695 第三次 verify（LOW 9、11、12、14、16、20）：本輪只修文字、說明與測試，**不改行為**。這裡把寫進誠實邊界的幾格釘成「現在照收」——
/// 日後收窄時這支會紅，提醒回來改 `RetrievalWriteShape.isBracketedIPv6` 的 doc 與 docs/store-format.md 的那一段（同 `APA7GoldenTests` 斷言現況的形）。
///
/// - 方括號是語法檢查：位址形狀的內容擋不住——合法位址本身裝得下 32 位十六進位，zone 裡 15 個位元組以內的英數字或 `%HH` 照收，zone 不限連結本地位址；
/// - Darwin 的 `inet_pton` 接受每群多於四位的前導零與 IPv4 八位元組的前導零（glibc 不收：拒絕集合依平台而異）；
/// - port 只驗 ASCII 數字、不驗位數與範圍；
/// - digest 的空白檢查是「四個來源欄位齊備」，不是「reference 會寫」：目標欄位已在、什麼都不會寫時照樣整批拒絕。
final class RetrievalWriteShapeBoundaryTests: XCTestCase {
    var root: URL!
    var fakeHome: URL!
    var env: [String: String] { ["AKASHIC_HOME": fakeHome.path] }
    let digest = "sha256:" + String(repeating: "c", count: 64)

    override func setUpWithError() throws {
        fakeHome = FileManager.default.temporaryDirectory.appendingPathComponent("akashic-home-\(UUID().uuidString)")
        root = FileManager.default.temporaryDirectory.appendingPathComponent("akashic-695b-\(UUID().uuidString)")
        let store = LibraryStore(root: root)
        try store.ensureLayout()
        var e = Entry(id: UUID(), citekey: "anon2020x", type: .periodicalArticle, title: "Anon")
        e.fields["abstract"] = "已有的摘要"
        try store.writeEntry(e)
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

    private func withSource(url: String) -> AddOnlyEnrichment.Proposal {
        .init(citekey: "anon2020x", fields: ["note": "n"], sourceDigest: digest,
              sourceURL: url, sourceRetrieved: "2026-09-30", sourceMediaType: nil, sourceStatus: 200)
    }

    func testAddressShapedContentIsStillAcceptedToday() {
        var urls = ["https://[::1%25hunter2]/x",                                // zone 裡的英數字
                    "https://[2001:db8::1%25hunter2]/x",                        // zone 不限連結本地位址
                    "https://[::1%25%68%75%6e%74%65%72%32]/x",                  // zone 裡的 %HH
                    "https://[dead:beef:cafe:babe:1234:5678:9abc:def0]/x",      // 位址本身就是 32 位十六進位
                    "https://example.org:123456/x"]                             // port 不驗位數與範圍
        #if os(macOS)
        urls += ["https://[00000dead::1]/x", "https://[::ffff:1.2.3.04]/x"]     // Darwin 的 inet_pton 收前導零（glibc 不收）
        #endif
        for url in urls {
            XCTAssertNoThrow(try service.enrich(proposals: [withSource(url: url)], dryRun: true, includeAbsentAuthors: false),
                             "現在照收（誠實邊界）：\(url)")
        }
    }

    /// 目標欄位已在、什麼都不會寫——四欄齊備，帶換行的 digest 照樣整批拒絕；訊息只說四欄齊備時 reference 記原值。
    func testAPaddedDigestIsRefusedWhenAllFourFieldsAreGivenEvenIfNothingWouldBeWritten() {
        let p = AddOnlyEnrichment.Proposal(citekey: "anon2020x", fields: ["abstract": "已有的摘要"], sourceDigest: "\(digest)\n",
                                           sourceURL: "https://example.org/a", sourceRetrieved: "2026-09-30", sourceStatus: 200)
        XCTAssertThrowsError(try service.enrich(proposals: [p], dryRun: true, includeAbsentAuthors: false)) {
            let why = message($0)
            XCTAssertTrue(why.contains("四個來源欄位齊備時"), why)
            XCTAssertFalse(why.contains("reference 記的是送來的原值"), "不宣稱這一筆會寫 reference：\(why)")
        }
    }
}
