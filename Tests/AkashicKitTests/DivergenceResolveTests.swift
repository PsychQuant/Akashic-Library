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
/// 前提。測試造出**真實**的兩種情境——#73 之後前提是「要刪的檔案 tracked 且 clean」，
/// 所以 fixture 得真的 `git init` + commit（見 `GitFixture`），假 `.git` 目錄不再夠用。
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
            // #73：**真的** git repo。假 `.git` 目錄在 #73 之後不再夠用——版控前提
            // 已升級成「本次要刪的檔案 tracked 且 clean」，而那正是被測的性質。
            GitFixture.initRepo(dir)
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

        var work = Entry(id: UUID(), citekey: "shen2015model", type: .periodicalArticle,
                         title: "Model selection")
        work.authors = [.literal("Shen, Tzu-Jung"), .key("fann-cathy-s-j-2")]
        try s.writeEntry(work)

        let d = Divergence(
            id: UUID(),
            question: "是否為同一人",
            candidates: [DivergenceCandidate(key: "fann-cathy-s-j", shape: .person),
                         DivergenceCandidate(key: "fann-cathy-s-j-2", shape: .person)])
        try s.writeDivergence(d)
        // #73：seed 完就 commit——被測的是「消歧」，不是「未 commit 會被擋」。
        // 後者由 testRefusesWhenDoomedFilesAreUncommitted 專門覆蓋。
        GitFixture.commitAll(s.root, message: "seed")
        return d
    }

    // MARK: - #73 版控前提：tracked + clean

    /// 最常見的失效情況：歧異記錄建立後**尚未 commit** 就被消歧。
    /// 舊檢查（往上找得到 `.git`）完全不觸發，於是 question / judgement / rests-on
    /// 三者隨檔案一起永久消失——#71 要解決的「判斷留不下來」原封不動地回來。
    func testRefusesWhenDoomedFilesAreUncommitted() throws {
        var survivor = Person(key: "fann-cathy-s-j"); survivor.names = ["A"]
        var merged = Person(key: "fann-cathy-s-j-2"); merged.names = ["B"]
        try store.writePerson(survivor)
        try store.writePerson(merged)
        GitFixture.commitAll(root, message: "people only")
        // 歧異記錄建立後**不** commit
        let d = Divergence(id: UUID(), question: "是否為同一人",
                           candidates: [DivergenceCandidate(key: "fann-cathy-s-j", shape: .person),
                                        DivergenceCandidate(key: "fann-cathy-s-j-2", shape: .person)])
        try store.writeDivergence(d)

        XCTAssertThrowsError(try store.resolveDivergence(id: d.id, survivor: "fann-cathy-s-j"),
                             "未 commit 的歧異記錄消歧後永久消失，必須拒絕") { err in
            guard case DivergenceResolveError.deletionNotRecoverable(let files) = err else {
                return XCTFail("應為 deletionNotRecoverable，實得 \(err)")
            }
            XCTAssertTrue(files.contains { $0.path.contains(d.id.uuidString) },
                          "訊息必須指名是哪個檔：\(files)")
        }
        // 拒絕發生在**任何寫入之前**——被併記錄與歧異記錄都必須完好
        let after = try store.load()
        XCTAssertEqual(after.people.count, 2, "拒絕後不得動到任何檔案")
        XCTAssertEqual(after.divergences.count, 1)
    }

    /// 被併實體有**未提交的修改**：git 裡有的是舊版本，當下這版刪掉不可回復。
    func testRefusesWhenDoomedEntityHasUncommittedEdits() throws {
        let d = try seed(into: store)           // seed 內已 commit
        var merged = try XCTUnwrap(try store.load().people.first { $0.key == "fann-cathy-s-j-2" })
        merged.names = ["Fann, Cathy S. J.", "後來補的別名（未 commit）"]
        try store.writePerson(merged)

        XCTAssertThrowsError(try store.resolveDivergence(id: d.id, survivor: "fann-cathy-s-j")) { err in
            guard case DivergenceResolveError.deletionNotRecoverable(let files) = err else {
                return XCTFail("應為 deletionNotRecoverable，實得 \(err)")
            }
            XCTAssertTrue(files.contains { $0.why.contains("未提交") }, "\(files)")
        }
    }

    /// **entities/ 被 .gitignore 擋**——最隱蔽的一種：`git status --porcelain` 裡
    /// 連 `??` 都不會出現，舊檢查也照樣放行。
    func testRefusesWhenEntitiesDirectoryIsGitIgnored() throws {
        try "entities/\n".write(to: root.appendingPathComponent(".gitignore"),
                                atomically: true, encoding: .utf8)
        var survivor = Person(key: "fann-cathy-s-j"); survivor.names = ["A"]
        var merged = Person(key: "fann-cathy-s-j-2"); merged.names = ["B"]
        try store.writePerson(survivor)
        try store.writePerson(merged)
        let d = Divergence(id: UUID(), question: "是否為同一人",
                           candidates: [DivergenceCandidate(key: "fann-cathy-s-j", shape: .person),
                                        DivergenceCandidate(key: "fann-cathy-s-j-2", shape: .person)])
        try store.writeDivergence(d)
        GitFixture.commitAll(root, message: "commit — 但 entities/ 被 ignore，什麼都沒進去")

        XCTAssertThrowsError(try store.resolveDivergence(id: d.id, survivor: "fann-cathy-s-j"),
                             "被 ignore 的檔案從未進 git object，刪掉就沒了") { err in
            guard case DivergenceResolveError.deletionNotRecoverable(let files) = err else {
                return XCTFail("應為 deletionNotRecoverable，實得 \(err)")
            }
            XCTAssertTrue(files.allSatisfy { $0.why.contains("未被 git 追蹤") }, "\(files)")
        }
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
        var other = Entry(id: UUID(), citekey: "chen2020assoc", type: .periodicalArticle, title: "Assoc")
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

    // MARK: - #78-2 塌縮可見性與 dry-run

    /// 第二筆歧異記錄的兩個候選都指向本次消歧的鍵——遷移後塌縮、被連帶刪除。
    /// 使用者沒有指名它，所以回報必須帶 question，不能只有裸 UUID。
    private func seedCollapsible(into s: LibraryStore) throws -> (main: Divergence, other: Divergence) {
        let main = try seed(into: s)
        let other = Divergence(
            id: UUID(),
            question: "兩個寫法是否同屬機構 X",
            candidates: [DivergenceCandidate(key: "fann-cathy-s-j", shape: .person),
                         DivergenceCandidate(key: "fann-cathy-s-j-2", shape: .person)])
        try s.writeDivergence(other)
        GitFixture.commitAll(s.root, message: "seed collapsible")
        return (main, other)
    }

    func testCollapsedDetailsCarryQuestion() throws {
        let (main, other) = try seedCollapsible(into: store)
        let report = try store.resolveDivergence(id: main.id, survivor: "fann-cathy-s-j")
        XCTAssertEqual(report.failures, [])
        // 兩筆歧異記錄都被刪（main 是使用者指名的、other 是塌縮連帶）……
        XCTAssertEqual(report.removedDivergences.sorted(),
                       [main.id.uuidString, other.id.uuidString].sorted())
        // ……但只有 other 進 collapsedDetails——main 是使用者自己要求的，不算連帶。
        XCTAssertEqual(report.collapsedDetails.count, 1)
        XCTAssertEqual(report.collapsedDetails.first?.id, other.id.uuidString)
        XCTAssertEqual(report.collapsedDetails.first?.question, "兩個寫法是否同屬機構 X")
    }

    /// preview 的三個承諾：(1) 一個檔案都不動；(2) merged / collapsedDetails 與實跑
    /// 一致（判準共用 `migrateOtherDivergences`，這個測試釘住共用沒被拆散）；
    /// (3) rewritten 的預測 = 實跑正常路徑的 rewritten。
    func testPreviewMatchesActualAndTouchesNothing() throws {
        let (main, _) = try seedCollapsible(into: store)
        let before = try snapshot(root)
        let preview = try store.previewResolveDivergence(id: main.id, survivor: "fann-cathy-s-j", overrideReason: nil)
        XCTAssertEqual(try snapshot(root), before, "preview 不得動任何檔案")
        XCTAssertFalse(preview.survivorUpdated, "preview 沒有既成事實可報")
        XCTAssertEqual(preview.removedDivergences, [], "同上——removed 是事實欄位")

        let actual = try store.resolveDivergence(id: main.id, survivor: "fann-cathy-s-j")
        XCTAssertEqual(actual.failures, [])
        XCTAssertEqual(preview.merged, actual.merged)
        XCTAssertEqual(preview.rewritten, actual.rewritten)
        XCTAssertEqual(preview.collapsedDetails.map(\.id), actual.collapsedDetails.map(\.id))
        XCTAssertEqual(preview.collapsedDetails.map(\.question),
                       actual.collapsedDetails.map(\.question))
    }

    /// #78-1：可預期的刪除失敗前移——一個檔案不可刪就**一個都不刪**。
    /// 三候選：兩筆被併，其中一筆設 immutable。沒有前移檢查時，可刪的那筆會先被
    /// 刪掉、immutable 那筆留下——「部分成功」正是最難描述的狀態。
    func testUndeletableDoomedFileDeletesNothing() throws {
        var survivor = Person(key: "wang-a")
        survivor.names = ["Wang, A"]
        var m1 = Person(key: "wang-a-2")
        m1.names = ["Wang, A."]
        var m2 = Person(key: "wang-a-3")
        m2.names = ["Wang, A.-B."]
        for p in [survivor, m1, m2] { try store.writePerson(p) }
        let d = Divergence(
            id: UUID(), question: "三個寫法是否同一人",
            candidates: [DivergenceCandidate(key: "wang-a", shape: .person),
                         DivergenceCandidate(key: "wang-a-2", shape: .person),
                         DivergenceCandidate(key: "wang-a-3", shape: .person)])
        try store.writeDivergence(d)
        GitFixture.commitAll(store.root, message: "seed three-way")

        let blocked = store.entityURL(id: m2.id)
        try FileManager.default.setAttributes([.immutable: true], ofItemAtPath: blocked.path)
        defer {
            try? FileManager.default.setAttributes([.immutable: false], ofItemAtPath: blocked.path)
        }

        let report = try store.resolveDivergence(id: d.id, survivor: "wang-a")
        XCTAssertTrue(report.hasFailures)
        XCTAssertTrue(report.failures.contains { $0.contains(blocked.lastPathComponent) },
                      "失敗訊息須指名不可刪的檔案：\(report.failures)")
        let load = try store.load()
        XCTAssertTrue(load.people.contains { $0.key == "wang-a-2" },
                      "**可刪的那筆也不得刪**——全刪或全不刪")
        XCTAssertTrue(load.people.contains { $0.key == "wang-a-3" })
        XCTAssertEqual(load.divergences.count, 1, "歧異記錄保留，修好後可重跑")
    }

    /// #139 verify F1 的 regression：shape 專屬拒絕（wouldLoseFields）preview 也要擲
    /// ——它是最高頻的拒絕（兩筆各帶一半識別碼），dry-run 對它沉默等於在最需要
    /// 預告的場景上失效。
    func testPreviewRejectsWouldLoseFieldsSameAsActual() throws {
        let d = try seed(into: store)
        // 被併者帶 keeper 沒有的 orcid → 實跑會拒
        var merged = try XCTUnwrap(try store.load().people.first { $0.key == "fann-cathy-s-j-2" })
        merged.orcid = ORCID("0000-0002-1825-0097")
        try store.writePerson(merged)
        GitFixture.commitAll(store.root, message: "orcid on doomed")

        for run in [{ try self.store.previewResolveDivergence(id: d.id, survivor: "fann-cathy-s-j", overrideReason: nil) },
                    { try self.store.resolveDivergence(id: d.id, survivor: "fann-cathy-s-j") }] {
            XCTAssertThrowsError(try run(), "preview 與實跑必須擲同樣的拒絕") { error in
                guard case DivergenceResolveError.wouldLoseFields = error else {
                    return XCTFail("預期 wouldLoseFields，實得 \(error)")
                }
            }
        }
    }

    /// #139 R2 複驗的 R1：work 側 preview 驗證的 regression——person 側有測試守著、
    /// work 側沒有＝留著 F1（兩條路徑分開維護）的復發面。
    func testWorkPreviewRejectsCandidateMissingSameAsActual() throws {
        let e1 = Entry(id: UUID(), citekey: "w2020a", type: .periodicalArticle, title: "A")
        let e2 = Entry(id: UUID(), citekey: "w2021b", type: .periodicalArticle, title: "B")
        try store.writeEntry(e1)
        try store.writeEntry(e2)
        let d = Divergence(
            id: UUID(), question: "是否同一篇",
            candidates: [DivergenceCandidate(key: "w2020a", shape: .work),
                         DivergenceCandidate(key: "w2021b", shape: .work)])
        try store.writeDivergence(d)
        GitFixture.commitAll(store.root, message: "seed work pair")
        // 候選的 entity 檔被外力刪掉
        try FileManager.default.removeItem(at: store.entityURL(id: e2.id))
        GitFixture.commitAll(store.root, message: "remove candidate file")

        for run in [{ try self.store.previewResolveDivergence(id: d.id, survivor: "w2020a", overrideReason: nil) },
                    { try self.store.resolveDivergence(id: d.id, survivor: "w2020a") }] {
            XCTAssertThrowsError(try run(), "work 側 preview 與實跑必須擲同樣的拒絕") { error in
                guard case DivergenceResolveError.candidateMissing(let key, let shape) = error else {
                    return XCTFail("預期 candidateMissing，實得 \(error)")
                }
                XCTAssertEqual(key, "w2021b")
                XCTAssertEqual(shape, "work")
            }
        }
    }

    /// preview 與實跑擲**同樣的**拒絕——dry-run 放行而實跑被擋是在騙人。
    func testPreviewRejectsSameAsActual() throws {
        let d = try seed(into: store)
        XCTAssertThrowsError(try store.previewResolveDivergence(
            id: d.id, survivor: "not-a-candidate", overrideReason: nil)) { error in
            guard case DivergenceResolveError.survivorNotACandidate = error else {
                return XCTFail("預期 survivorNotACandidate，實得 \(error)")
            }
        }
        // 版控前提也要在 preview 就擋（#73 的 gate 屬於共用驗證段）
        try "dirty".write(to: root.appendingPathComponent("entities/extra.txt"),
                          atomically: true, encoding: .utf8)
        var uncommitted = Person(key: "ghost-person")
        uncommitted.names = ["Ghost"]
        try store.writePerson(uncommitted)   // 未 commit
        let d2 = Divergence(
            id: UUID(), question: "未提交者",
            candidates: [DivergenceCandidate(key: "fann-cathy-s-j", shape: .person),
                         DivergenceCandidate(key: "ghost-person", shape: .person)])
        try store.writeDivergence(d2)
        XCTAssertThrowsError(try store.previewResolveDivergence(
            id: d2.id, survivor: "fann-cathy-s-j", overrideReason: nil)) { error in
            guard case DivergenceResolveError.deletionNotRecoverable = error else {
                return XCTFail("預期 deletionNotRecoverable，實得 \(error)")
            }
        }
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
