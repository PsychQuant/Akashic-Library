import XCTest
@testable import AkashicCore
@testable import AkashicStoreIO
@testable import AkashicMCPKit

/// #669 的 service 面。
final class DuplicateKeyServiceTests: XCTestCase {
    var root: URL!
    var fakeHome: URL!
    var env: [String: String] { ["AKASHIC_HOME": fakeHome.path] }

    override func setUpWithError() throws {
        fakeHome = FileManager.default.temporaryDirectory.appendingPathComponent("akashic-home-\(UUID().uuidString)")
        root = FileManager.default.temporaryDirectory.appendingPathComponent("akashic-669-\(UUID().uuidString)")
        let store = LibraryStore(root: root)
        try store.ensureLayout()
        var e = Entry(id: UUID(), citekey: "anon2020x", type: .periodicalArticle, title: "Anon")
        e.authors = [.literal("Institute of Statistical Science")]
        try store.writeEntry(e)
    }
    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
        try? FileManager.default.removeItem(at: fakeHome)
    }

    /// attribute-org 要把 verdict 寫進那個 organization——key 重複時寫進哪一筆是猜，整批拒絕、零寫入（#627 對 citekey 的同一件事）。
    /// #669 之前這裡以 `uniqueKeysWithValues` 建表，重複的 key 直接讓 process trap。
    func testAttributeOrgRefusesADuplicatedOrganizationKey() throws {
        let store = LibraryStore(root: root)
        // 兩個不同 UUID、同一個 key（id 不給時由 key 推導，兩次會寫進同一個檔）
        try store.writeOrganization(Organization(key: "iss", id: UUID()))
        try store.writeOrganization(Organization(key: "iss", id: UUID()))
        XCTAssertEqual(try store.load().organizations.filter { $0.key == "iss" }.count, 2, "前提：兩筆同 key")
        let svc = AkashicService(root: root, environment: env)
        XCTAssertThrowsError(try svc.attributeToOrganizations(["anon2020x:0:iss=論文機構欄"])) { error in
            XCTAssertTrue("\(error)".contains("不只一筆記錄"), "\(error)")
        }
        let e = try XCTUnwrap(store.load().entries.first { $0.citekey == "anon2020x" })
        XCTAssertEqual(e.authors, [.literal("Institute of Statistical Science")], "零寫入")
    }

    /// `enrich` 的 payload 以消毒後的欄位名當鍵；截斷在 80 字元，不是單射。format 16 的 store 上兩個共用 80 字元前綴的
    /// 欄位名都進 `provenanceOmitted`（#668）——#669 之前這裡 `Fatal error: Duplicate values for key`（CLI rc=133）。
    func testEnrichPayloadSurvivesFieldNamesThatCollideAfterTruncation() throws {
        try StoreVersion.write(root: root, format: 16)
        let prefix = String(repeating: "a", count: 90)
        let p = AddOnlyEnrichment.Proposal(
            citekey: "anon2020x", fields: [prefix + "1": "v1", prefix + "2": "v2"],
            sourceDigest: "sha256:" + String(repeating: "c", count: 64),
            sourceURL: "https://x.org/y", sourceRetrieved: "2026-09-28", sourceStatus: 200)
        let svc = AkashicService(root: root, environment: env)
        let payload = try svc.enrich(proposals: [p], dryRun: true, includeAbsentAuthors: false)
        XCTAssertTrue(payload.contains("provenanceOmitted"), payload)
    }
}
