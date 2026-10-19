import XCTest
import Foundation
@testable import AkashicCore
@testable import AkashicStoreIO
@testable import AkashicMCPKit

/// #709 b40 verify：`enrich` 的理由文字（`AddOnlyEnrichment.plan` 的 `reason`）——
///
/// 1. DOI 歧義的理由裡，拷貝那一句說得了哪些 citekey（MEDIUM 0、LOW 4）：先前只看命中，同一個 citekey 另有一筆不帶這個 DOI、id 不同的記錄時照樣說
///    「刪掉 legacy 那份……，再跑」，照做之後重跑被「無法唯一定位」擋下。
/// 2. 理由的兩個分支先前沒有測試（LOW 3）：明細至多列 5 個加「…另 N 個」、拷貝那一對的 citekey 在拷貝以外的命中裡也重複；以及第 3 類（只有一份、
///    寫入時會被拒的 legacy 殘留）在多筆命中裡排在 #459 之前。
/// 3. 結論在前、回顯的未信任字串以 scalar 截短（LOW 6、7、10、11）：`notFound` 的兩句把呼叫端的原字串放在結論之前、不截，出口 `displaySafe(max: 512)`
///    截掉的是結論。同一份計畫的其他句子一起改。
///
/// 走真的 load（拷貝的標記與第 3 類的理由都由 load 設定）；store 不是 git 工作樹，所以單一份 legacy 檔是第 3 類。
final class EnrichReasonExplanationTests: XCTestCase {
    private var root: URL!
    private var store: LibraryStore!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("akashic-709-b41-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        store = LibraryStore(root: root, key: nil, environment: [:])
        try store.ensureLayout()
        try StoreVersion.write(root: root, format: StoreVersion.supported)
    }

    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: root) }

    private func reset() throws {
        try? FileManager.default.removeItem(at: store.entitiesDir)
        try? FileManager.default.removeItem(at: store.entriesDir)
        try store.ensureLayout()
    }

    private func writeEntities(_ e: Entry) throws {
        try EntryYAML.encode(e).write(to: store.entityURL(id: e.id), atomically: true, encoding: .utf8)
    }

    private func writeLegacy(_ e: Entry) throws {
        try FileManager.default.createDirectory(at: store.entriesDir, withIntermediateDirectories: true)
        try EntryYAML.encode(e).write(to: legacyURL(e.citekey), atomically: true, encoding: .utf8)
    }

    private func legacyURL(_ citekey: String) -> URL { store.entriesDir.appendingPathComponent("\(citekey).yaml") }

    private func work(_ citekey: String, id: UUID = UUID(), doi: String?) -> Entry {
        var e = Entry(id: id, citekey: citekey, type: .periodicalArticle, title: "T \(citekey)", date: "2020")
        if let doi { e.doi = [DOI(doi)!] }
        return e
    }

    /// 以 DOI 定位一筆 enrich 提案的那一項（走真的 load）。
    private func item(doi: String) throws -> AddOnlyEnrichment.Item {
        let plan = try AddOnlyEnrichment.plan(entries: try store.load().entries,
                                              proposals: [.init(doi: doi, fields: ["abstract": "A"])])
        return try XCTUnwrap(plan.items.first)
    }

    private func ambiguousReason(doi: String, matches: [String], file: StaticString = #filePath, line: UInt = #line) throws -> String {
        let it = try item(doi: doi)
        XCTAssertEqual(it.category, .ambiguous, "\(it)", file: file, line: line)
        XCTAssertEqual(it.matches, matches, file: file, line: line)
        return try XCTUnwrap(it.reason, file: file, line: line)
    }

    /// 走 CLI 與 MCP 共用的 service 出口（`displaySafe(max: 512)`），回第一項的 reason。
    private func servedReason(_ proposal: AddOnlyEnrichment.Proposal) throws -> String {
        let service = AkashicService(root: root, key: nil, environment: [:])
        let out = try service.enrich(proposals: [proposal], dryRun: true, includeAbsentAuthors: false)
        let obj = try XCTUnwrap(try JSONSerialization.jsonObject(with: Data(out.utf8)) as? [String: Any], out)
        return try XCTUnwrap((obj["items"] as? [[String: Any]])?.first?["reason"] as? String, out)
    }

    // MARK: - 1. 拷貝那一句說得了的 citekey（MEDIUM 0、LOW 4）

    /// 兩種形狀（logic 席以真 binary 重現）：
    /// (a) entities/ 的 r1 不帶 DOI、它的 legacy 拷貝帶、entities/ 另一筆 id 不同的 r2 帶；
    /// (b) 拷貝那一對都帶 DOI、entities/ 另一筆 id 不同的 r9 不帶。
    /// 兩種都是刪掉拷貝之後 citekey 仍重複：說先修好、不說「再跑」。照做（刪掉 legacy 那份）之後重跑仍被「無法唯一定位」擋——那正是先前那句「再跑」的後果。
    func testACopyDoesNotExplainACitekeyThatStaysUnlocatableOnceTheCopyIsDeleted() throws {
        let doi = "10.1234/same"
        for (shape, pairCarries, otherCarries) in [("a", false, true), ("b", true, false)] {
            try reset()
            let id = UUID()
            try writeEntities(work("x2020same", id: id, doi: pairCarries ? doi : nil))
            try writeLegacy(work("x2020same", id: id, doi: doi))
            try writeEntities(work("x2020same", doi: otherCarries ? doi : nil))
            XCTAssertEqual(try store.load().shadowedLegacyCopies.map(\.legacyFile), ["entries/x2020same.yaml"], "前提（\(shape)）：load 標出拷貝")

            let reason = try ambiguousReason(doi: doi, matches: ["x2020same"])
            XCTAssertTrue(reason.hasPrefix("DOI「\(doi)」命中 2 筆（1 個 citekey），零寫入：命中裡有 1 個 citekey 無法唯一定位（\(UnlocatableReason.work)），先修好（#628／#641）"),
                          "（\(shape)）\(reason)")
            XCTAssertTrue(reason.contains("無法唯一定位：x2020same"), "（\(shape)）\(reason)")
            XCTAssertTrue(reason.contains("命中裡有 1 份是同一筆記錄的 legacy 拷貝：確認 entities/ 那份是新的之後刪掉 legacy 那份"), "（\(shape)）拷貝照樣說：\(reason)")
            // b42 verify LOW 10：entities/ 裡有兩筆 x2020same，那份以檔名指認、不以 citekey
            XCTAssertTrue(reason.contains("x2020same（legacy 檔 entries/x2020same.yaml；entities/ 那份是 entities/\(id.uuidString).yaml"),
                          "（\(shape)）\(reason)")
            XCTAssertFalse(reason.contains("再跑"), "（\(shape)）刪掉拷貝之後 citekey 仍重複，不說「再跑」：\(reason)")
            XCTAssertFalse(reason.contains("#459"), "（\(shape)）只有一個 citekey，不是孿生：\(reason)")

            // 照做：刪掉 legacy 那份，重跑——仍被擋（理由說無法唯一定位）
            try FileManager.default.removeItem(at: legacyURL("x2020same"))
            let rerun = try item(doi: doi)
            XCTAssertEqual(rerun.category, .ambiguous, "（\(shape)）\(rerun)")
            XCTAssertTrue((rerun.reason ?? "").contains("無法唯一定位"), "（\(shape)）\(rerun)")
        }
    }

    /// 對照組：只有那一對拷貝（同 citekey、都帶 DOI）——刪掉拷貝之後就能唯一定位，照舊只說拷貝那一句、以「再跑」收尾。
    /// 孿生（entities/ 那份）在完整的 load 上自己也帶第 3 類的理由（`entries/<它的 citekey>.yaml` 就是那份拷貝）；刪掉拷貝之後它不在，不算。
    func testAPlainCopyPairStillEndsWithRerun() throws {
        let doi = "10.1234/same"
        let id = UUID()
        try writeEntities(work("x2020same", id: id, doi: doi))
        try writeLegacy(work("x2020same", id: id, doi: doi))
        let load = try store.load()
        XCTAssertEqual(load.shadowedLegacyCopies.count, 1, "前提：一對拷貝")
        XCTAssertNotNil(load.entries.first { $0.fileSituation.shadowedLegacyFile == nil }?.fileSituation.unwritableReason,
                        "前提：孿生自己也帶第 3 類的理由（就是那份拷貝）")
        XCTAssertEqual(load.entries.unlocatableCitekeys(afterDeletingCopiesAt: ["entries/x2020same.yaml"]), [], "刪掉拷貝之後能唯一定位")

        let reason = try ambiguousReason(doi: doi, matches: ["x2020same"])
        XCTAssertTrue(reason.hasPrefix("DOI「\(doi)」命中 2 筆（1 個 citekey），零寫入：命中裡有 1 份是同一筆記錄的 legacy 拷貝"), reason)
        XCTAssertTrue(reason.contains("（akashic validate 列出），再跑"), reason)
        XCTAssertFalse(reason.contains("先修好") || reason.contains("無法唯一定位"), reason)

        // 照做之後重跑：寫得進去（added）
        try FileManager.default.removeItem(at: legacyURL("x2020same"))
        XCTAssertEqual(try item(doi: doi).category, .added)
    }

    // MARK: - 1b. 叫人刪的拷貝與判準算在同一個集合上（b42 verify MEDIUM 0、LOW 4、INFO 13）

    /// 讀理由裡點名的 legacy 檔（「legacy 檔 entries/….yaml」），逐一刪掉——照著理由做的那一步。
    private func deleteTheLegacyFilesNamed(in reason: String) throws -> [String] {
        let files = reason.components(separatedBy: "legacy 檔 ").dropFirst().compactMap { $0.components(separatedBy: "；").first }
        for f in files { try FileManager.default.removeItem(at: root.appendingPathComponent(f)) }
        return files
    }

    /// 同一個 id 有兩份 legacy 拷貝，一份帶 DOI（在命中裡）、一份不帶（不在命中裡）：E:x:A（帶）、legacy x:A（帶）、legacy y:A（不帶）。先前判準在
    /// **全部**拷貝都刪掉的集合上算、處置只列命中裡那一份，理由以「，再跑」收尾；照做之後 y 仍與 x 共用 id A，重跑被「無法唯一定位……先修好」擋下
    /// （devils-advocate、logic 以真 binary 重現）。現在兩份都點名、「共 2 份」，照著刪掉理由列出的檔之後重跑寫得進去。兩種形狀：孿生沒改名（x）、
    /// 孿生改名了（entities/ 那份是 z，legacy x 與 y 都是它的舊 citekey）。
    func testTheCopyInstructionNamesEverySameIDCopySoTheRerunHolds() throws {
        let doi = "10.1234/same"
        for (shape, twinKey, matches) in [("沒改名", "x2020new", ["x2020new"]), ("改名", "z2021renamed", ["x2020new", "z2021renamed"])] {
            try reset()
            let id = UUID()
            try writeEntities(work(twinKey, id: id, doi: doi))
            try writeLegacy(work("x2020new", id: id, doi: doi))
            try writeLegacy(work("y2019old", id: id, doi: nil))
            XCTAssertEqual(Set(try store.load().shadowedLegacyCopies.map(\.legacyFile)), ["entries/x2020new.yaml", "entries/y2019old.yaml"],
                           "前提（\(shape)）：兩份都是 load 標出的拷貝")

            let reason = try ambiguousReason(doi: doi, matches: matches)
            let tally = matches.count == 1 ? "命中 2 筆（1 個 citekey）" : "命中 2 筆"
            XCTAssertTrue(reason.hasPrefix("DOI「\(doi)」\(tally)，零寫入：命中裡有 1 份是同一筆記錄的 legacy 拷貝、同 id 另有 1 份不帶這個 DOI："
                                           + "確認 entities/ 那份是新的之後刪掉 legacy 那份（共 2 份，akashic validate 列出），再跑。"), "（\(shape)）\(reason)")
            // y 的 citekey 與 entities/ 那份不同（舊 citekey）：citekey 另外寫出來；x 只在孿生改名時才寫
            XCTAssertTrue(reason.contains("y2019old（legacy 檔 entries/y2019old.yaml；entities/ 那份是 entities/\(id.uuidString).yaml、citekey \(twinKey)；這份不帶這個 DOI）"),
                          "（\(shape)）不帶 DOI 的那份也點名：\(reason)")
            let renamed = twinKey == "x2020new" ? "" : "、citekey \(twinKey)"
            XCTAssertTrue(reason.contains("x2020new（legacy 檔 entries/x2020new.yaml；entities/ 那份是 entities/\(id.uuidString).yaml\(renamed)）"),
                          "（\(shape)）\(reason)")

            // 照做：刪掉理由列出的每一份，重跑——寫得進去
            XCTAssertEqual(Set(try deleteTheLegacyFilesNamed(in: reason)), ["entries/x2020new.yaml", "entries/y2019old.yaml"], "（\(shape)）")
            XCTAssertEqual(try item(doi: doi).category, .added, "（\(shape)）「再跑」要成立")
        }
    }

    /// 只刪命中裡那一份（先前理由只列這一份）就重跑：y 仍與孿生共用 id——判準要與處置算在同一個集合上，這正是不能只列命中那一份的原因。
    func testDeletingOnlyTheHitCopyLeavesTheTwinUnlocatable() throws {
        let doi = "10.1234/same"
        let id = UUID()
        try writeEntities(work("x2020new", id: id, doi: doi))
        try writeLegacy(work("x2020new", id: id, doi: doi))
        try writeLegacy(work("y2019old", id: id, doi: nil))
        let load = try store.load()
        XCTAssertEqual(load.entries.unlocatableCitekeys(afterDeletingCopiesAt: ["entries/x2020new.yaml"]), ["x2020new", "y2019old"],
                       "只刪命中那一份：x 與 y 仍共用 id")
        XCTAssertEqual(load.entries.unlocatableCitekeys(afterDeletingCopiesAt: ["entries/x2020new.yaml", "entries/y2019old.yaml"]), [],
                       "兩份都刪：能唯一定位")
        try FileManager.default.removeItem(at: legacyURL("x2020new"))
        let rerun = try item(doi: doi)
        XCTAssertEqual(rerun.category, .ambiguous, "\(rerun)")
        XCTAssertTrue((rerun.reason ?? "").contains("無法唯一定位"), "\(rerun)")
    }

    /// 對照組：store 裡另有一對與命中無關的拷貝（id、citekey 都不同）——不點名、不算進「共 N 份」，照舊以「再跑」收尾。
    func testAnUnrelatedCopyElsewhereIsNotNamed() throws {
        let doi = "10.1234/same"
        let id = UUID(), other = UUID()
        try writeEntities(work("x2020new", id: id, doi: doi))
        try writeLegacy(work("x2020new", id: id, doi: doi))
        try writeEntities(work("w2018else", id: other, doi: nil))
        try writeLegacy(work("w2018else", id: other, doi: nil))
        let reason = try ambiguousReason(doi: doi, matches: ["x2020new"])
        XCTAssertTrue(reason.contains("命中裡有 1 份是同一筆記錄的 legacy 拷貝：確認 entities/ 那份是新的之後刪掉 legacy 那份（akashic validate 列出），再跑"), reason)
        XCTAssertFalse(reason.contains("w2018else") || reason.contains("同 id 另有") || reason.contains("共 2 份"), reason)
    }

    /// 命中**全是**拷貝、entities/ 那份都不帶這個 DOI（E:x:A 不帶、legacy x:A 帶、E:y:B 不帶、legacy y:B 帶）：刪掉之後這個 DOI 對不到任何記錄。
    /// 先前照樣說「再跑」，重跑得 notFound（INFO 13）；現在說出來、不說「再跑」。
    func testWhenEveryHitIsACopyTheReasonSaysTheDOIWillMatchNothing() throws {
        let doi = "10.1234/copies"
        let a = UUID(), b = UUID()
        try writeEntities(work("x2020only", id: a, doi: nil))
        try writeLegacy(work("x2020only", id: a, doi: doi))
        try writeEntities(work("y2020only", id: b, doi: nil))
        try writeLegacy(work("y2020only", id: b, doi: doi))
        let reason = try ambiguousReason(doi: doi, matches: ["x2020only", "y2020only"])
        XCTAssertTrue(reason.contains("命中裡有 2 份是同一筆記錄的 legacy 拷貝：確認 entities/ 那份是新的之後刪掉 legacy 那份（akashic validate 列出）"
                                      + "；entities/ 那份都不帶這個 DOI，刪掉之後它對不到任何記錄。"), reason)
        XCTAssertFalse(reason.contains("再跑"), reason)
        _ = try deleteTheLegacyFilesNamed(in: reason)
        XCTAssertEqual(try item(doi: doi).category, .notFound, "照做之後重跑：這個 DOI 對不到任何記錄")
    }

    /// 命中裡沒有拷貝、但命中的記錄另有不帶這個 DOI 的同 id 拷貝（改名留下的），加一筆真孿生：先前只說「無法唯一定位，先修好」，要去 validate 才知道
    /// 那是一份拷貝；現在拷貝那一句點名它，#459 照舊、不說「再跑」。
    func testASameIDCopyOfAHitRecordIsNamedEvenWhenNoHitIsACopy() throws {
        let doi = "10.1234/twins"
        let id = UUID()
        try writeEntities(work("x2020new", id: id, doi: doi))
        try writeLegacy(work("v2019old", id: id, doi: nil))
        try writeEntities(work("w2020twin", doi: doi))
        let reason = try ambiguousReason(doi: doi, matches: ["w2020twin", "x2020new"])
        XCTAssertTrue(reason.contains("不判定哪一筆才對（#459）；命中的記錄另有 1 份同 id 的 legacy 拷貝（不帶這個 DOI）："
                                      + "確認 entities/ 那份是新的之後刪掉 legacy 那份（akashic validate 列出）"), reason)
        XCTAssertTrue(reason.contains("v2019old（legacy 檔 entries/v2019old.yaml；entities/ 那份是 entities/\(id.uuidString).yaml、citekey x2020new；這份不帶這個 DOI）"), reason)
        XCTAssertFalse(reason.contains("無法唯一定位") || reason.contains("再跑"), "x 的無法唯一定位由拷貝那一句說明：\(reason)")
    }

    // MARK: - 2. 先前沒有測試的分支（LOW 3）

    /// 明細至多列 5 個無法唯一定位的 citekey，其餘以「…另 N 個」概括。6 個 citekey 各有兩筆 id 不同、都帶這個 DOI 的記錄。
    func testTheUnlocatableDetailListsFiveAndSummarisesTheRest() throws {
        let doi = "10.1234/many"
        let keys = (0..<6).map { "c2020n\($0)" }
        for k in keys {
            try writeEntities(work(k, doi: doi))
            try writeEntities(work(k, doi: doi))
        }
        let reason = try ambiguousReason(doi: doi, matches: keys)
        XCTAssertTrue(reason.hasPrefix("DOI「\(doi)」命中 12 筆（6 個 citekey），零寫入：命中裡有 6 個 citekey 無法唯一定位"), reason)
        XCTAssertTrue(reason.contains("無法唯一定位：c2020n0、c2020n1、c2020n2、c2020n3、c2020n4…另 1 個"), reason)
        XCTAssertFalse(reason.contains("c2020n5"), "第 6 個在概括裡：\(reason)")
        let fix = try XCTUnwrap(reason.range(of: "先修好（#628／#641）"), reason)
        let pipeline = try XCTUnwrap(reason.range(of: "不判定哪一筆才對（#459）"), reason)
        XCTAssertLessThan(fix.lowerBound, pipeline.lowerBound, reason)
    }

    /// 拷貝那一對的 citekey 在拷貝以外的命中裡也重複（r1 與它的拷貝、加一筆 id 不同的 r3，三筆都帶 DOI）；以及共用 id 的一組裡，有一個 citekey 另有一筆
    /// id 不同的記錄（兩個 legacy 檔共用 id、其中一個的 citekey 與 entities/ 的另一筆相同）。兩種都是「已有一句說明，但那個 citekey 另有一件事要修」。
    func testACitekeyWithAnotherProblemBesidesItsCopyOrSharedIDIsStillListed() throws {
        let doi = "10.1234/dup"
        let id = UUID()
        try writeEntities(work("x2020same", id: id, doi: doi))
        try writeLegacy(work("x2020same", id: id, doi: doi))
        try writeEntities(work("x2020same", doi: doi))
        let withCopy = try ambiguousReason(doi: doi, matches: ["x2020same"])
        XCTAssertTrue(withCopy.hasPrefix("DOI「\(doi)」命中 3 筆（1 個 citekey），零寫入：命中裡有 1 個 citekey 無法唯一定位"), withCopy)
        XCTAssertTrue(withCopy.contains("無法唯一定位：x2020same") && withCopy.contains("命中裡有 1 份是同一筆記錄的 legacy 拷貝"), withCopy)
        XCTAssertFalse(withCopy.contains("再跑") || withCopy.contains("#459"), withCopy)

        try reset()
        let shared = UUID()
        try writeLegacy(work("p2020share", id: shared, doi: doi))
        try writeLegacy(work("q2020share", id: shared, doi: doi))
        try writeEntities(work("p2020share", doi: doi))
        XCTAssertEqual(try store.load().shadowedLegacyCopies, [], "前提：沒有拷貝（entities/ 沒有那個 id）")
        let withSharedID = try ambiguousReason(doi: doi, matches: ["p2020share", "q2020share"])
        XCTAssertTrue(withSharedID.contains("命中裡有 1 個 citekey 無法唯一定位") && withSharedID.contains("無法唯一定位：p2020share"), withSharedID)
        XCTAssertTrue(withSharedID.contains("命中裡有 1 組共用同一個 id") && withSharedID.contains("共用 id：p2020share、q2020share"), withSharedID)
        XCTAssertFalse(withSharedID.contains("無法唯一定位：p2020share、q2020share"), "q 只有共用 id 那一件事，已由那一句說明：\(withSharedID)")
    }

    /// 第 3 類（只有一份、寫入時會被拒的 legacy 殘留）在多筆命中裡：先修好那一句排在 #459 之前。它在 validate 只是 warning、不經
    /// `assertNoCrossRecordErrors`（LOW 5、INFO 12 指出排序理由對它不成立）——擋它的是寫入當下的 #631 前置。順序不變，這裡只把它釘住。
    func testACategoryThreeLeftoverAmongSeveralHitsIsFixedBeforeTheTwinPipeline() throws {
        let doi = "10.1234/cat3"
        try writeEntities(work("a2020ok", doi: doi))
        try writeLegacy(work("b2020legacy", doi: doi))
        let load = try store.load()
        XCTAssertNotNil(load.entries.first { $0.citekey == "b2020legacy" }?.fileSituation.unwritableReason, "前提：第 3 類")
        XCTAssertEqual(load.entries.unlocatableCitekeys, ["b2020legacy"], "前提：只有它無法唯一定位")
        XCTAssertFalse(load.crossRecordIssues().contains { $0.severity == .error }, "前提：validate 對它只報 warning")

        let reason = try ambiguousReason(doi: doi, matches: ["a2020ok", "b2020legacy"])
        XCTAssertTrue(reason.contains("無法唯一定位：b2020legacy"), reason)
        let fix = try XCTUnwrap(reason.range(of: "命中裡有 1 個 citekey 無法唯一定位"), reason)
        let pipeline = try XCTUnwrap(reason.range(of: "不判定哪一筆才對（#459）"), reason)
        XCTAssertLessThan(fix.lowerBound, pipeline.lowerBound, "先修好的在前：\(reason)")
    }

    // MARK: - 3. 結論在前、回顯截短（LOW 6、7、10、11）

    /// 三種呼叫端給的長字串（5,000 個字元的 citekey、5,000 個字元的不合法 DOI、誤貼進 doi 的一段摘要）與一個很長而合法、沒有記錄帶的 DOI：
    /// 理由以結論開頭，回顯的字串截到 `reasonEchoScalarLimit` 個 scalar；走 service 出口之後結論仍在。
    func testNotFoundReasonsLeadWithTheConclusionAndClipTheEcho() throws {
        try writeEntities(work("a2020ok", doi: "10.1234/ok"))
        let limit = AddOnlyEnrichment.reasonEchoScalarLimit
        let abstract = String(repeating: "We examine how the polychoric model behaves when categories are sparse. ", count: 22)
        let cases: [(AddOnlyEnrichment.Proposal, String, String)] = [
            (.init(citekey: String(repeating: "a", count: 5_000), fields: ["abstract": "A"]), "citekey 不在 store 裡：「", String(repeating: "a", count: limit)),
            (.init(doi: "not a doi " + String(repeating: "z", count: 5_000), fields: ["abstract": "A"]),
             "不是合法的 DOI 形狀（\(DOI.shapeDescription)）：「", "not a doi " + String(repeating: "z", count: limit - 10)),
            (.init(doi: abstract, fields: ["abstract": "A"]), "不是合法的 DOI 形狀（\(DOI.shapeDescription)）：「", String(abstract.prefix(limit))),
            (.init(doi: "10.1234/" + String(repeating: "x", count: 5_000), fields: ["abstract": "A"]), "沒有記錄帶 DOI「",
             "10.1234/" + String(repeating: "x", count: limit - 8)),
        ]
        for (proposal, conclusion, echoed) in cases {
            let plan = try AddOnlyEnrichment.plan(entries: try store.load().entries, proposals: [proposal])
            let it = try XCTUnwrap(plan.items.first)
            XCTAssertEqual(it.category, .notFound, "\(it)")
            let reason = try XCTUnwrap(it.reason)
            XCTAssertTrue(reason.hasPrefix(conclusion), reason.prefix(200) + "")
            XCTAssertTrue(reason.contains(echoed + "…」"), "回顯截到 \(limit) 個 scalar：\(reason.prefix(300))")
            XCTAssertLessThan(reason.unicodeScalars.count, 300, "整句在出口預算之內：\(reason.unicodeScalars.count)")

            let served = try servedReason(proposal)
            XCTAssertTrue(served.hasPrefix(conclusion), "service 出口之後結論仍在：\(served.prefix(200))")
            XCTAssertFalse(served.hasSuffix("（已截斷）"), "不必靠出口截斷：\(served.suffix(80))")
        }
    }

    /// 只命中一筆、而那個 citekey 無法唯一定位：結論在前，citekey 截短（store 的 citekey 長度沒有上限——手改的 YAML 寫得出 300 個字元的 key）。
    func testTheSingleHitUnlocatableReasonLeadsWithTheConclusion() throws {
        let long = String(repeating: "b", count: 300)
        try writeEntities(work(long, doi: "10.1234/long"))
        try writeEntities(work(long, doi: nil))
        let it = try item(doi: "10.1234/long")
        XCTAssertEqual(it.category, .ambiguous)
        XCTAssertEqual(it.matches, [long], "matches 照舊是完整的 citekey")
        let reason = try XCTUnwrap(it.reason)
        XCTAssertTrue(reason.hasPrefix("citekey 無法唯一定位（\(UnlocatableReason.work)）——零寫入；先修好（#628／#641）：「"), reason)
        XCTAssertTrue(reason.contains(String(repeating: "b", count: AddOnlyEnrichment.reasonEchoScalarLimit) + "…」"), reason)
    }

    /// 同一份計畫的其他句子：`refused`／`partial` 把呼叫端的值放在結論之前（出口 `displaySafe(max: 300)`），空值的附註把欄位鍵放在前面，
    /// 兩個欄位名的整批拒絕把欄位名放在前面（出口 `displaySafeError(max: 512)`）。都改成結論在前、回顯截短。
    func testTheOtherSentencesOfThePlanLeadWithTheConclusion() throws {
        try writeEntities(work("a2020ok", doi: nil))
        let long = String(repeating: "9", count: 5_000)
        let limit = AddOnlyEnrichment.reasonEchoScalarLimit
        let plan = try AddOnlyEnrichment.plan(entries: try store.load().entries, proposals: [
            .init(citekey: "a2020ok", fields: ["issn": long, "pmid": "x" + long, "isbn": "978-0-306-40615-7 " + long,
                                               String(repeating: "k", count: 5_000): "", "abstract": "A"]),
        ])
        let it = try XCTUnwrap(plan.items.first)
        let refusedISSN = try XCTUnwrap(it.outcome.refused.first { $0.hasPrefix("issn：") }, "\(it.outcome.refused)")
        XCTAssertTrue(refusedISSN.hasPrefix("issn：ISSN 識別的是期刊不是文章，work 不收；要補請補到它的 venue——「"), refusedISSN)
        XCTAssertTrue(refusedISSN.hasSuffix(String(repeating: "9", count: limit) + "…」"), refusedISSN.suffix(120) + "")
        let refusedPMID = try XCTUnwrap(it.outcome.refused.first { $0.hasPrefix("pmid：") }, "\(it.outcome.refused)")
        XCTAssertTrue(refusedPMID.hasPrefix("pmid：解析不出 PMID 的形狀，不猜——「"), refusedPMID.prefix(80) + "")
        let partial = try XCTUnwrap(it.outcome.partial.first, "\(it.outcome)")
        XCTAssertTrue(partial.hasPrefix("isbn：只解析出 1 個，其餘 token 的形狀不認得；原字串已一併加進 fields 供人裁——「"), partial.prefix(120) + "")
        XCTAssertLessThan(partial.unicodeScalars.count, 300, "\(partial.unicodeScalars.count)")
        let note = try XCTUnwrap(it.reason)
        XCTAssertTrue(note.hasPrefix("值為空，略過：「"), note.prefix(80) + "")
        XCTAssertLessThan(note.unicodeScalars.count, 300, "\(note.unicodeScalars.count)")

        for (fields, conclusion) in [([String(repeating: "!", count: 5_000): "v"], "欄位名無法表達成合法的 biblatex 欄位鍵：「"),
                                     (["Ab Stract": "v", "ab_stract": "w"], "欄位名正規化後與另一個欄位相撞：「")] {
            XCTAssertThrowsError(try AddOnlyEnrichment.plan(entries: [], proposals: [.init(citekey: "a2020ok", fields: fields)])) { error in
                guard case AddOnlyEnrichment.InputError.invalidProposal(_, let reason) = error else { return XCTFail("\(error)") }
                XCTAssertTrue(reason.hasPrefix(conclusion), reason.prefix(120) + "")
                XCTAssertLessThan(reason.unicodeScalars.count, 300, "\(reason.unicodeScalars.count)")
            }
        }
    }
}
