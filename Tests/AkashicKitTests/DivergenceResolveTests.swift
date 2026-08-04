import XCTest
import Foundation
@testable import AkashicCore
@testable import AkashicStoreIO

/// 消歧：合併 → 全庫參照重寫 → 刪檔，三者是一個操作（#71）。
///
/// 「刪一個檔」不是消歧。被併掉的候選很可能已被其他記錄引用；直接刪檔會留下指向
/// 不存在鍵的參照，佈局檢查的孤兒計數會跳，但那時已經壞了。
///
/// **沒有 `requireVersionControl:` 這種參數**：版控前提若可由呼叫端關掉，那它就不是
/// 前提。測試改以「root 底下有沒有 `.git`」造出兩種真實情境——這正是實作檢查的事實。
final class DivergenceResolveTests: XCTestCase {
    var root: URL!
    var store: LibraryStore!

    override func setUpWithError() throws {
        root = try makeStore(versioned: true)
        store = LibraryStore(root: root)
    }
    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: root) }

    private func makeStore(versioned: Bool) throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("akashic-div-\(UUID().uuidString)")
        try FileManager.default.createDirectory(
            at: dir.appendingPathComponent("entities"), withIntermediateDirectories: true)
        try StoreVersion.write(root: dir, format: StoreVersion.supported)
        if versioned {
            // 工作樹的事實就是這個目錄的存在——實作走檔案系統，不呼叫 git 執行檔。
            try FileManager.default.createDirectory(
                at: dir.appendingPathComponent(".git"), withIntermediateDirectories: true)
        }
        return dir
    }

    /// 兩筆 person（同一人的兩種寫法）＋ 一筆引用其中之一的 work ＋ 一筆歧異記錄。
    @discardableResult
    private func seed(into s: LibraryStore) throws -> Divergence {
        var survivor = Person(key: "fann-cathy-s-j")
        survivor.names = ["Fann, Cathy S-J"]
        var merged = Person(key: "fann-cathy-s-j-2")
        merged.names = ["Fann, Cathy S. J."]
        try s.writePerson(survivor)
        try s.writePerson(merged)

        var work = Entry(id: UUID(), citekey: "shen2015model", type: "article",
                         title: "Model selection")
        work.authors = [.literal("Shen, Tzu-Jung"), .key("fann-cathy-s-j-2")]
        try s.writeEntry(work)

        let d = Divergence(
            id: UUID(),
            question: "是否為同一人",
            candidates: [DivergenceCandidate(key: "fann-cathy-s-j", shape: .person),
                         DivergenceCandidate(key: "fann-cathy-s-j-2", shape: .person)])
        try s.writeDivergence(d)
        return d
    }

    /// 引用跟著合併走——spec 的 `Example: A work's author list follows the merge`。
    func testReferencesFollowMerge() throws {
        let d = try seed(into: store)
        let report = try store.resolveDivergence(id: d.id, survivor: "fann-cathy-s-j")
        XCTAssertEqual(report.rewritten, ["shen2015model"])
        XCTAssertFalse(report.hasFailures, "\(report.failures)")

        let load = try store.load()
        let work = try XCTUnwrap(load.entries.first { $0.citekey == "shen2015model" })
        XCTAssertEqual(work.authors, [.literal("Shen, Tzu-Jung"), .key("fann-cathy-s-j")],
                       "作者應改為倖存鍵，且順序不變")
    }

    /// 被併實體與歧異記錄的檔案都不存在。
    func testMergedFilesRemoved() throws {
        let d = try seed(into: store)
        let report = try store.resolveDivergence(id: d.id, survivor: "fann-cathy-s-j")
        XCTAssertEqual(report.merged, ["fann-cathy-s-j-2"])
        XCTAssertEqual(report.removedDivergences, [d.id.uuidString])

        let load = try store.load()
        XCTAssertEqual(load.people.map(\.key), ["fann-cathy-s-j"], "被併的 person 應消失")
        XCTAssertTrue(load.divergences.isEmpty, "歧異記錄應消失")
        XCTAssertTrue(load.quarantined.isEmpty, "\(load.quarantined)")
    }

    /// 被併者的別名併入倖存者——否則之後遇到那個寫法又會重新分割一次。
    func testAliasesMergedIntoSurvivor() throws {
        let d = try seed(into: store)
        _ = try store.resolveDivergence(id: d.id, survivor: "fann-cathy-s-j")
        let p = try XCTUnwrap(try store.load().people.first { $0.key == "fann-cathy-s-j" })
        XCTAssertEqual(p.names, ["Fann, Cathy S-J", "Fann, Cathy S. J."],
                       "被併者的寫法應併入且不重複：\(p.names)")
    }

    /// 倖存者不在候選清單內 → 拒絕，且錯誤列出實際候選。
    func testSurvivorOutsideCandidatesRefused() throws {
        let d = try seed(into: store)
        let before = try snapshot(root)
        XCTAssertThrowsError(
            try store.resolveDivergence(id: d.id, survivor: "someone-else")
        ) { error in
            let msg = (error as? LocalizedError)?.errorDescription ?? "\(error)"
            XCTAssertTrue(msg.contains("fann-cathy-s-j") && msg.contains("fann-cathy-s-j-2"),
                          "錯誤須列出實際候選：\(msg)")
        }
        XCTAssertEqual(try snapshot(root), before, "拒絕後任何檔案都不得被改動或刪除")
    }

    /// 單筆參照寫入失敗 → 其餘照寫、失敗被列出、且**不刪任何東西**。
    ///
    /// 「部分改寫且索引過期」正是要避免的撕裂狀態：若此時仍刪掉被併記錄，
    /// 那些沒改寫成功的參照就永久懸空了。
    func testPartialWriteFailureReportsAndExitsNonZero() throws {
        let d = try seed(into: store)
        // 第二筆引用被併鍵的 work，把它的檔案設成 immutable：**讀得到、寫不進去**。
        // 這正是要模擬的情境——記錄照常載入並進入改寫清單，落地時才失敗。
        // （用「把檔案換成目錄」會連 load() 都讀不到它，那模擬的是別的故障。）
        var other = Entry(id: UUID(), citekey: "chen2020assoc", type: "article", title: "Assoc")
        other.authors = [.key("fann-cathy-s-j-2")]
        try store.writeEntry(other)
        let blocked = store.entityURL(id: other.id)
        try FileManager.default.setAttributes([.immutable: true], ofItemAtPath: blocked.path)
        defer {
            // 不解除的話 tearDown 刪不掉整個暫存目錄。
            try? FileManager.default.setAttributes([.immutable: false], ofItemAtPath: blocked.path)
        }

        let report = try store.resolveDivergence(id: d.id, survivor: "fann-cathy-s-j")
        XCTAssertTrue(report.hasFailures, "應回報失敗")
        XCTAssertTrue(report.failures.contains { $0.contains("chen2020assoc") },
                      "失敗清單須指名那一筆：\(report.failures)")
        XCTAssertEqual(report.rewritten, ["shen2015model"], "其餘記錄仍應被改寫")

        let load = try store.load()
        XCTAssertTrue(load.people.contains { $0.key == "fann-cathy-s-j-2" },
                      "有失敗時不得刪除被併記錄")
        XCTAssertEqual(load.divergences.count, 1, "有失敗時不得刪除歧異記錄")
    }

    /// store 不在版控工作樹內 → 拒絕，且檔案全數保留。
    ///
    /// 「git 有紀錄所以可以刪」是部署假設而非 store 保證——store 可以建在任何位置。
    /// 這條把假設變成被驗證的前提（與 encode canary、版本過新拒讀同一個 fail-closed 風格）。
    func testRefusesOutsideVersionControl() throws {
        let bare = try makeStore(versioned: false)
        defer { try? FileManager.default.removeItem(at: bare) }
        let s = LibraryStore(root: bare)
        let d = try seed(into: s)
        let before = try snapshot(bare)

        XCTAssertThrowsError(try s.resolveDivergence(id: d.id, survivor: "fann-cathy-s-j")) { error in
            let msg = (error as? LocalizedError)?.errorDescription ?? "\(error)"
            XCTAssertTrue(msg.contains("版本控制"), "錯誤須說明版控是刪除的前提：\(msg)")
        }
        XCTAssertEqual(try snapshot(bare), before, "拒絕後任何檔案都不得被改動或刪除")
    }

    /// 版控偵測的往上走一定會停。
    ///
    /// 這條是回歸測試：第一版用 `URL.deletingLastPathComponent()` 走，而它在根目錄
    /// **不是不動點**——回傳 `/..`，下一輪 `/../..`，字串永遠變長。守衛（parent == self）
    /// 因此永遠不成立，測試跑成 88% CPU、29 GB RSS 的失控迴圈。**它的表徵是「測試很慢」
    /// 而不是 crash**，所以值得一條直接打在函式上的測試，而不是只信呼叫端跑得完。
    func testWorkTreeWalkTerminatesAtRoot() throws {
        XCTAssertFalse(LibraryStore.isInsideVersionedWorkTree(URL(fileURLWithPath: "/")),
                       "根目錄本身不該被當成工作樹（除非真的有 /.git）")
        // 不存在的深路徑：往上走每一層都不該卡住。
        let deep = URL(fileURLWithPath: "/nonexistent-\(UUID().uuidString)/a/b/c/d/e")
        XCTAssertFalse(LibraryStore.isInsideVersionedWorkTree(deep))
        // 本 repo 自己在版控內——正向那一半也要走過。
        XCTAssertTrue(LibraryStore.isInsideVersionedWorkTree(
            URL(fileURLWithPath: #filePath).deletingLastPathComponent()))
    }

    /// 逐檔雜湊，用來斷言「什麼都沒動」。
    private func snapshot(_ dir: URL) throws -> [String: Int] {
        let entities = dir.appendingPathComponent("entities")
        var out: [String: Int] = [:]
        for u in try FileManager.default.contentsOfDirectory(
            at: entities, includingPropertiesForKeys: nil) where u.pathExtension == "yaml" {
            out[u.lastPathComponent] = try Data(contentsOf: u).hashValue
        }
        return out
    }
}
