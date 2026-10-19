import XCTest
import Foundation
@testable import AkashicCore
@testable import AkashicStoreIO

/// #709 b40 verify LOW 1（requirements）、LOW 8（regression）：`validate` 的「DOI 被 N 筆 work 共用」對同 citekey、不同 id 的重複仍說「可用
/// record-divergence 記下未決的同一性」——而 record-divergence 對同一個 citekey 的兩個候選拒絕（「重複的候選不構成歧異」）。b38 修掉 enrich 理由裡的同一個
/// 矛盾，enrich 的新理由指去的下一站（validate）又說了一次舊指路。同一份輸出裡指向 record-divergence 的另兩則（標題與年份相同而 DOI 不同、
/// Zotero 來源被多筆 entry 宣稱）同形，一起改。全部走真 binary；每一則都有不同 citekey 的對照組（照舊指向 record-divergence）。
final class CrossRecordDuplicateCitekeyCLITests: XCTestCase {
    private var base: URL!
    private var root: URL!
    private var home: URL!
    private var store: LibraryStore!

    private var env: [String: String] { ["AKASHIC_HOME": home.path] }

    private func cli(_ args: [String]) throws -> (status: Int32, output: String) {
        try CLITestHarness.run(args + ["--library", root.path], env: env)
    }

    override func setUpWithError() throws {
        base = FileManager.default.temporaryDirectory.appendingPathComponent("akashic-709-b41-validate-\(UUID().uuidString)")
        root = base.appendingPathComponent("store")
        home = base.appendingPathComponent("home")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        store = LibraryStore(root: root)
        try store.ensureLayout()
        try StoreVersion.write(root: root, format: StoreVersion.supported)
    }

    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: base) }

    private func write(_ citekey: String, title: String = "Alpha", doi: String?, zotero: String? = nil) throws {
        var e = Entry(id: UUID(), citekey: citekey, type: .periodicalArticle, title: title, date: "2020")
        if let doi { e.doi = [DOI(doi)!] }
        if let zotero { e.provenance = Provenance(zoteroKey: zotero, zoteroVersion: 1, libraryID: 1) }
        try EntryYAML.encode(e).write(to: store.entityURL(id: e.id), atomically: true, encoding: .utf8)
    }

    /// validate 輸出裡含 `needle` 的那一則跨記錄 warning。
    private func warning(_ needle: String, file: StaticString = #filePath, line: UInt = #line) throws -> String {
        let v = try cli(["validate"])
        let found = v.output.split(separator: "\n").map(String.init).filter { $0.hasPrefix("⚠ [跨記錄]") && $0.contains(needle) }
        XCTAssertEqual(found.count, 1, v.output, file: file, line: line)
        return try XCTUnwrap(found.first, v.output, file: file, line: line)
    }

    func testADOISharedBySameCitekeyDuplicatesSaysFixTheDuplicateFirst() throws {
        let doi = "10.1234/alpha"
        try write("j2020alpha", title: "Alpha", doi: doi)
        try write("j2020alpha", title: "Alpha (other)", doi: doi)
        // 前提：record-divergence 拒收同一個 citekey 的兩個候選（舊指路叫人做的事）；validate 另報 citekey 重複的 error
        let rd = try cli(["record-divergence", "--question", "same work?",
                          "--candidate", "j2020alpha:work", "--candidate", "j2020alpha:work"])
        XCTAssertNotEqual(rd.status, 0, rd.output)
        XCTAssertTrue(rd.output.contains("重複的候選不構成歧異"), rd.output)
        XCTAssertTrue(try cli(["validate"]).output.contains("✗ [跨記錄] citekey「j2020alpha」重複"), "前提")

        let line = try warning("DOI「\(doi)」被 2 筆 work 共用")
        // b42 verify LOW 5、15：結論在前、名單在後（MCP doctor 每則截 300 個 scalar）
        XCTAssertTrue(line.contains("DOI「\(doi)」被 2 筆 work 共用——先修好那個重複：其中 citekey「j2020alpha」不只一筆記錄"), line)
        XCTAssertTrue(line.hasSuffix("（j2020alpha, j2020alpha）"), line)
        XCTAssertFalse(line.contains("record-divergence 記下"), "不叫人做 record-divergence 拒收的事：\(line)")

        // 再加一筆不同 citekey 的：先修好重複，修好之後其餘的才是編目判斷
        try write("b2020beta", title: "Beta", doi: doi)
        let mixed = try warning("DOI「\(doi)」被 3 筆 work 共用")
        let fix = try XCTUnwrap(mixed.range(of: "先修好那個重複"), mixed)
        let pipeline = try XCTUnwrap(mixed.range(of: "修好之後其餘的要不要視為同一筆是編目判斷，可用 record-divergence 記下未決的同一性"), mixed)
        XCTAssertLessThan(fix.lowerBound, pipeline.lowerBound, mixed)
    }

    func testATitleYearGroupOfSameCitekeyDuplicatesSaysFixTheDuplicateFirst() throws {
        try write("j2020alpha", doi: "10.1234/a1")
        try write("j2020alpha", doi: "10.1234/a2")
        let line = try warning("標題與年份相同但 DOI 不同的 2 筆 work")
        XCTAssertTrue(line.contains("標題與年份相同但 DOI 不同的 2 筆 work——先修好那個重複：其中 citekey「j2020alpha」不只一筆記錄"), line)
        XCTAssertTrue(line.hasSuffix("（j2020alpha, j2020alpha）：「alpha」"), line)
        XCTAssertFalse(line.contains("處置同上"), "「同上」是 record-divergence：\(line)")

        // 混合組（重複的 citekey 加一筆別的）：其餘的直接說處置，不指「同 DOI 共用那一則」——這一組的 DOI 彼此不同（b42 verify INFO 12、16）
        try write("k2020beta", doi: "10.1234/a3")
        let mixed = try warning("標題與年份相同但 DOI 不同的 3 筆 work")
        XCTAssertTrue(mixed.contains("；修好之後其餘的要不要視為同一筆是編目判斷，可用 record-divergence 記下未決的同一性（"), mixed)
        XCTAssertFalse(mixed.contains("同 DOI 共用那一則"), mixed)
        XCTAssertFalse(try cli(["validate"]).output.contains("筆 work 共用"), "前提：這一組沒有共用 DOI 的那一則")
    }

    func testAZoteroSourceClaimedBySameCitekeyDuplicatesSaysFixTheDuplicateFirst() throws {
        try write("j2020alpha", title: "Alpha", doi: nil, zotero: "KEYART01")
        try write("j2020alpha", title: "Alpha (other)", doi: nil, zotero: "KEYART01")
        let line = try warning("Zotero 來源「1:KEYART01」被 2 筆 entry 宣稱")
        XCTAssertTrue(line.contains("Zotero 來源「1:KEYART01」被 2 筆 entry 宣稱——先修好那個重複：其中 citekey「j2020alpha」不只一筆記錄"), line)
        XCTAssertTrue(line.hasSuffix("（j2020alpha, j2020alpha）"), line)
        XCTAssertFalse(line.contains("record-divergence 記下"), line)
        XCTAssertTrue(line.contains("update-entry --remove-zotero-source 也以 citekey 定位"), "移除面同樣拒絕它：\(line)")
    }

    /// b42 verify LOW 3：兩筆**不同**的記錄共用 citekey 時，error 先前沒有處置，而 enrich、validate 的另外三則、rename 都說「先修好」——一圈指回來。
    /// 照同一個函式裡 venue key 那則寫：手改 YAML 改掉其中一筆的 citekey。
    func testTheCitekeyDuplicateErrorSaysHowToFixIt() throws {
        try write("j2020alpha", doi: nil)
        try write("j2020alpha", title: "Alpha (other)", doi: nil)
        let out = try cli(["validate"]).output
        let line = try XCTUnwrap(out.split(separator: "\n").map(String.init).first { $0.hasPrefix("✗ [跨記錄] citekey「j2020alpha」重複") }, out)
        XCTAssertTrue(line.contains("——以 citekey 定位的讀取與寫入分不出是哪一筆；先在 YAML 改掉其中一筆的 citekey"), line)
        XCTAssertTrue(line.contains("rename 與合併都會先停下") && line.contains("record-divergence／resolve-divergence 合併"), line)
        XCTAssertFalse(line.contains("legacy 拷貝"), "兩筆都不是拷貝：\(line)")
        // rename 被這個 error 擋下（所以處置不能叫人用 rename）；它的拒絕訊息帶這則 error，處置跟著到那裡——先前那裡只剩「先跑 akashic doctor 看清楚並修好」
        let rename = try cli(["rename", "j2020alpha", "j2020gamma"])
        XCTAssertNotEqual(rename.status, 0, rename.output)
        XCTAssertTrue(rename.output.contains("rename 拒絕執行") && rename.output.contains("先在 YAML 改掉其中一筆的 citekey"), rename.output)
    }

    /// 組裡有一份是**另一筆記錄**改名留下的 legacy 拷貝、檔名正好是這個 citekey：那一份要刪、不是改名——以檔名指認 entities/ 那份。
    func testTheCitekeyDuplicateErrorNamesALegacyCopyInTheGroup() throws {
        try write("j2020alpha", doi: nil)
        let renamedID = UUID()
        var current = Entry(id: renamedID, citekey: "u2021renamed", type: .periodicalArticle, title: "U", date: "2021")
        try EntryYAML.encode(current).write(to: store.entityURL(id: renamedID), atomically: true, encoding: .utf8)
        current.citekey = "j2020alpha"
        try FileManager.default.createDirectory(at: store.entriesDir, withIntermediateDirectories: true)
        try EntryYAML.encode(current).write(to: store.entriesDir.appendingPathComponent("j2020alpha.yaml"), atomically: true, encoding: .utf8)
        XCTAssertEqual(try store.load().shadowedLegacyCopies.map(\.legacyFile), ["entries/j2020alpha.yaml"], "前提：load 標出拷貝")

        let out = try cli(["validate"]).output
        let line = try XCTUnwrap(out.split(separator: "\n").map(String.init).first { $0.hasPrefix("✗ [跨記錄] citekey「j2020alpha」重複") }, out)
        XCTAssertTrue(line.contains("其中 entries/j2020alpha.yaml（entities/ 那份是 entities/\(renamedID.uuidString).yaml） 是 legacy 拷貝："
                                    + "確認 entities/ 那份是新的之後刪掉 legacy 那份"), line)
        XCTAssertFalse(line.contains("改掉其中一筆"), "拷貝以外只有一筆記錄，不叫人改名：\(line)")
    }

    /// b42 verify LOW 5、6、9、15：「先修好那個重複」先前接在不設上限的 citekey 名單之後、自己也列出全部重複的 citekey——MCP `akashic_doctor` 對每則
    /// 截 300 個 scalar，八筆就截掉結論；Zotero 那則本來截在 10 個，這一句繞過了它。現在結論在前、重複的 citekey 至多 5 個、組的名單至多 10 個。
    func testRepeatedCitekeyGroupsAreBoundedAndLeadWithTheConclusion() throws {
        let doi = "10.1234/many"
        let keys = (0..<7).map { "smithjonesmillerwilliams2019dup\($0)" }
        for k in keys {
            try write(k, title: "Same", doi: doi, zotero: "KEYART09")
            try write(k, title: "Same", doi: doi, zotero: "KEYART09")
        }
        for needle in ["DOI「\(doi)」被 14 筆 work 共用——先修好那個重複", "Zotero 來源「1:KEYART09」被 14 筆 entry 宣稱——先修好那個重複"] {
            let line = try warning(needle)
            XCTAssertTrue(line.contains("「\(keys[4])」…共 7 個不只一筆記錄"), "重複的 citekey 至多列 5 個：\(line)")
            XCTAssertFalse(line.contains(keys[5]) || line.contains(keys[6]), "第 6、7 個不列：\(line)")
            XCTAssertTrue(line.contains("…共 14 筆）"), "組的名單至多 10 個：\(line)")
            XCTAssertLessThan(line.unicodeScalars.count, 1_200, "一行有上限：\(line.unicodeScalars.count)")
            let clipped = String(String.UnicodeScalarView(line.unicodeScalars.prefix(300)))
            XCTAssertTrue(clipped.contains("先修好那個重複"), "MCP doctor 截到 300 個 scalar 之後結論仍在：\(clipped)")
        }
    }

    /// 對照組：citekey 不同的三則照舊指向 record-divergence、不提重複。
    func testDistinctCitekeysKeepTheRecordDivergencePointer() throws {
        try write("a2020alpha", doi: "10.1234/same")
        try write("b2020alpha", doi: "10.1234/same")
        XCTAssertTrue(try warning("DOI「10.1234/same」被 2 筆 work 共用").hasSuffix("可用 record-divergence 記下未決的同一性"))
        try write("c2020alpha", title: "Gamma", doi: "10.1234/g1")
        try write("d2020alpha", title: "Gamma", doi: "10.1234/g2")
        XCTAssertTrue(try warning("標題與年份相同但 DOI 不同的 2 筆 work").hasSuffix("處置同上，留給編目判斷"))
        try write("e2020alpha", title: "Epsilon", doi: nil, zotero: "KEYART02")
        try write("f2020alpha", title: "Zeta", doi: nil, zotero: "KEYART02")
        let zotero = try warning("Zotero 來源「1:KEYART02」被 2 筆 entry 宣稱")
        XCTAssertTrue(zotero.contains("兩筆是同一篇就用 record-divergence 記下") && !zotero.contains("不只一筆記錄"), zotero)
    }
}
