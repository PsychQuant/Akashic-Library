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
        XCTAssertTrue(line.contains("其中 citekey「j2020alpha」不只一筆記錄") && line.hasSuffix("先修好那個重複"), line)
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
        XCTAssertTrue(line.contains("其中 citekey「j2020alpha」不只一筆記錄") && line.hasSuffix("先修好那個重複"), line)
        XCTAssertFalse(line.contains("處置同上"), "「同上」是 record-divergence：\(line)")
    }

    func testAZoteroSourceClaimedBySameCitekeyDuplicatesSaysFixTheDuplicateFirst() throws {
        try write("j2020alpha", title: "Alpha", doi: nil, zotero: "KEYART01")
        try write("j2020alpha", title: "Alpha (other)", doi: nil, zotero: "KEYART01")
        let line = try warning("Zotero 來源「1:KEYART01」被 2 筆 entry 宣稱")
        XCTAssertTrue(line.contains("其中 citekey「j2020alpha」不只一筆記錄") && line.contains("先修好那個重複"), line)
        XCTAssertFalse(line.contains("record-divergence 記下"), line)
        XCTAssertTrue(line.contains("update-entry --remove-zotero-source 也以 citekey 定位"), "移除面同樣拒絕它：\(line)")
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
