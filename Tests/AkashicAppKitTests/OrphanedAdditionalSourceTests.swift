import XCTest
@testable import AkashicCore
@testable import AkashicStoreIO
@testable import AkashicAppKit

/// #609：App 裁決台看得到附加來源已刪除的 entry，並能拿掉那些來源；「只有附加來源、全部已刪除」的 entry
/// 當成整筆 orphan，可以脫鉤或丟垃圾桶。
final class OrphanedAdditionalSourceTests: XCTestCase {
    var root: URL!
    var state: AppState!
    private let gone = Date(timeIntervalSince1970: 1_753_000_000)

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("akashic-orphadd-\(UUID().uuidString)")
        let store = LibraryStore(root: root)
        try store.ensureLayout()
        var partial = Entry(id: UUID(), citekey: "partial2020", type: .periodicalArticle, title: "Partial")
        partial.provenance = Provenance(zoteroKey: "K1", zoteroVersion: 1, libraryID: 1)
        partial.additionalProvenance = [
            Provenance(zoteroKey: "K2", zoteroVersion: 1, libraryID: 5, orphanedAt: gone),
            Provenance(zoteroKey: "K3", zoteroVersion: 1, libraryID: 7),
        ]
        try store.writeEntry(partial)
        var allGone = Entry(id: UUID(), citekey: "allgone2020", type: .periodicalArticle, title: "All gone")
        allGone.additionalProvenance = [Provenance(zoteroKey: "K4", zoteroVersion: 1, libraryID: 5, orphanedAt: gone)]
        try store.writeEntry(allGone)
        var alive = Entry(id: UUID(), citekey: "alive2020", type: .periodicalArticle, title: "Alive")
        alive.provenance = Provenance(zoteroKey: "K5", zoteroVersion: 1, libraryID: 1)
        try store.writeEntry(alive)
        state = AppState(root: root)
        try state.load()
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    private func entry(_ citekey: String) throws -> Entry? {
        try LibraryStore(root: root).load().entries.first { $0.citekey == citekey }
    }

    /// 使用者在清單上看到、並在對話框裡確認的那一組來源（`Entry.orphanedAdditionalSourceKeys`）。
    private func seen(_ citekey: String) throws -> [String] {
        try XCTUnwrap(try entry(citekey)).orphanedAdditionalSourceKeys
    }

    // MARK: - git fixture（移除前要求記錄檔已 commit——移除面一族的使用者裁決，2026-09-27）

    /// 剝除 GIT_*（#234）：從 git hook 裡跑測試時，hook 環境帶著 GIT_DIR，`-C` 擋不住它。
    private static var scrubbedGitEnvironment: [String: String] {
        ProcessInfo.processInfo.environment.filter { !$0.key.hasPrefix("GIT_") }
    }

    private func git(_ args: [String]) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        p.arguments = ["-C", root.path, "-c", "user.email=t@t", "-c", "user.name=t"] + args
        p.environment = Self.scrubbedGitEnvironment
        p.standardOutput = Pipe(); p.standardError = Pipe()
        try? p.run(); p.waitUntilExit()
    }

    private func commitAll() {
        if !FileManager.default.fileExists(atPath: root.appendingPathComponent(".git").path) { git(["init", "-q"]) }
        git(["add", "-A"])
        git(["commit", "-q", "--allow-empty", "-m", "fixture"])
    }

    // MARK: - 清單

    func testBothShapesAreListed() {
        let model = OrphanModel(state: state)
        XCTAssertEqual(model.orphans.map(\.citekey), ["allgone2020"], "只有附加來源、全部已刪除 → 整筆 orphan")
        XCTAssertEqual(model.orphanedAdditionalSourceEntries.map(\.citekey), ["partial2020"])
    }

    // MARK: - 整筆 orphan 的既有兩個動作，作用在「只有附加來源、全部已刪除」的 entry

    func testDetachWorksWhenEverySourceIsAdditionalAndGone() throws {
        try OrphanModel(state: state).resolve(citekey: "allgone2020", action: .detachFromZotero)
        let after = try XCTUnwrap(try entry("allgone2020"))
        XCTAssertNil(after.provenance)
        XCTAssertEqual(after.additionalProvenance, [], "已刪除的附加來源一併拿掉，轉純 Akashic entry")
    }

    func testTrashWorksWhenEverySourceIsAdditionalAndGone() throws {
        try OrphanModel(state: state).resolve(citekey: "allgone2020", action: .moveToTrash)
        XCTAssertNil(try entry("allgone2020"))
    }

    // MARK: - 拿掉已刪除的附加來源

    func testRemovalDropsOnlyTheOrphanedAdditionalSources() throws {
        commitAll()
        let before = try XCTUnwrap(try entry("partial2020"))
        let report = try OrphanModel(state: state)
            .removeOrphanedAdditionalSources(citekey: "partial2020", reason: "群組那份已刪、不再等", seen: try seen("partial2020"))
        let after = try XCTUnwrap(try entry("partial2020"))
        XCTAssertEqual(after.provenance, before.provenance, "主來源不動")
        XCTAssertEqual(after.additionalProvenance.map(\.zoteroKey), ["K3"], "活著的附加來源不動")
        XCTAssertEqual(after.title, before.title)
        XCTAssertTrue(report.contains("5:K2"), report)
        XCTAssertTrue(report.contains("群組那份已刪、不再等"), "理由只進報告，要全文：\(report)")
        XCTAssertTrue(state.entriesWithOrphanedAdditionalSource.isEmpty, "寫後 reload")
    }

    func testRemovalRefusesWithoutAGitCopy() throws {
        let before = try XCTUnwrap(try entry("partial2020"))
        // 不在 git 工作樹
        XCTAssertThrowsError(try OrphanModel(state: state)
            .removeOrphanedAdditionalSources(citekey: "partial2020", reason: "r", seen: ["5:K2"])) { err in
            XCTAssertTrue(err.localizedDescription.contains("git"), err.localizedDescription)
        }
        XCTAssertEqual(try entry("partial2020"), before, "零寫入")
        // 在 git 裡、但記錄檔有未提交修改
        commitAll()
        var dirty = before
        dirty.title = "Edited, not committed"
        try LibraryStore(root: root).writeEntry(dirty)
        try state.load()
        XCTAssertThrowsError(try OrphanModel(state: state)
            .removeOrphanedAdditionalSources(citekey: "partial2020", reason: "r", seen: ["5:K2"]))
        XCTAssertEqual(try entry("partial2020")?.additionalProvenance.count, 2, "零寫入")
    }

    /// #683：App 的閘與 `AkashicService.assertRecordsRecoverable` 是**同一份**（`LibraryStore.recordRecoverability`）——拒絕的整句逐字取自共用函式，
    /// 不是 App 自己組的一句。兩種原因（不在 git 裡、未 commit）各驗一次；「找不到記錄檔」在 `RecordRecoverabilityTests`（App 的路徑先重讀 entry，找不到會先報 entryNotFound）。
    func testRefusalSentenceIsTheSharedGateSentence() throws {
        let partial = try XCTUnwrap(try entry("partial2020"))
        func shared() -> String {
            LibraryStore.recordRecoverability(
                root: root, items: [(partial.id, "work「partial2020」")],
                action: "這次會從 work「partial2020」拿掉 1 個已在 Zotero 端刪除的附加來源", issue: "#609").refusal ?? "（共用函式說可以）"
        }
        func app() throws -> String {
            var caught = ""
            XCTAssertThrowsError(try OrphanModel(state: state)
                .removeOrphanedAdditionalSources(citekey: "partial2020", reason: "r", seen: ["5:K2"])) { err in
                guard case AdjudicationError.notRecoverable(let refusal) = err else { return XCTFail("\(err)") }
                XCTAssertEqual(err.localizedDescription, refusal, "描述端只截、不改寫")
                caught = refusal
            }
            return caught
        }
        // 不在 git 工作樹
        XCTAssertEqual(try app(), shared())
        XCTAssertTrue(shared().contains("不在 git 工作樹裡"), shared())
        // 在 git 裡、但記錄檔有未提交修改
        commitAll()
        var dirty = partial
        dirty.title = "Edited, not committed"
        try LibraryStore(root: root).writeEntry(dirty)
        try state.load()
        XCTAssertEqual(try app(), shared())
        XCTAssertTrue(shared().contains("不能確認可回溯"), shared())
    }

    /// #683：理由上限是 StoreIO 那一個常數（`LibraryStore.maxStatementBytes`）——剛好等於上限收、多一個位元組拒絕。以位元組計、不截斷。
    func testReasonLimitIsTheSharedConstant() throws {
        commitAll()
        let model = OrphanModel(state: state)
        let over = String(repeating: "a", count: LibraryStore.maxStatementBytes + 1)
        XCTAssertThrowsError(try model.removeOrphanedAdditionalSources(citekey: "partial2020", reason: over, seen: ["5:K2"])) { err in
            XCTAssertEqual(err as? AdjudicationError, .reasonTooLong(bytes: LibraryStore.maxStatementBytes + 1), "\(err)")
            XCTAssertTrue(err.localizedDescription.contains("\(LibraryStore.maxStatementBytes)"), "訊息的上限讀同一個常數：\(err.localizedDescription)")
        }
        // 三位元組的字元：以位元組計，不是字元數
        let cjkOver = String(repeating: "理", count: LibraryStore.maxStatementBytes / 3 + 1)
        XCTAssertThrowsError(try model.removeOrphanedAdditionalSources(citekey: "partial2020", reason: cjkOver, seen: ["5:K2"]))
        XCTAssertEqual(try entry("partial2020")?.additionalProvenance.count, 2, "零寫入")
        let exact = String(repeating: "a", count: LibraryStore.maxStatementBytes)
        let report = try model.removeOrphanedAdditionalSources(citekey: "partial2020", reason: exact, seen: ["5:K2"])
        XCTAssertTrue(report.contains(exact), "理由全文進報告、不截斷")
        XCTAssertEqual(try entry("partial2020")?.additionalProvenance.map(\.zoteroKey), ["K3"])
    }

    func testRemovalRequiresAReason() throws {
        commitAll()
        for r in ["", "   \n"] {
            XCTAssertThrowsError(try OrphanModel(state: state).removeOrphanedAdditionalSources(citekey: "partial2020", reason: r, seen: ["5:K2"]))
        }
        XCTAssertEqual(try entry("partial2020")?.additionalProvenance.count, 2, "零寫入")
    }

    /// 動作當下重新讀盤驗證（TOCTOU）：沒有已刪除附加來源的、整筆 orphan 的，都拒絕——後者要走脫鉤。
    func testRemovalRevalidatesTheShapeAtActionTime() throws {
        commitAll()
        let model = OrphanModel(state: state)
        XCTAssertThrowsError(try model.removeOrphanedAdditionalSources(citekey: "alive2020", reason: "r", seen: []))
        XCTAssertThrowsError(try model.removeOrphanedAdditionalSources(citekey: "allgone2020", reason: "r", seen: ["5:K4"]))
        XCTAssertThrowsError(try model.removeOrphanedAdditionalSources(citekey: "ghost2000x", reason: "r", seen: ["5:K2"]))
        // 清單開著的時候，外部把那個來源恢復了
        let store = LibraryStore(root: root)
        var restored = try XCTUnwrap(try entry("partial2020"))
        restored.additionalProvenance[0].orphanedAt = nil
        try store.writeEntry(restored)
        commitAll()
        XCTAssertThrowsError(try model.removeOrphanedAdditionalSources(citekey: "partial2020", reason: "r", seen: ["5:K2"]))
        XCTAssertEqual(try entry("partial2020")?.additionalProvenance.count, 2)
    }

    // MARK: - #609 R1 verify：拿掉的是使用者看到並確認的那一組

    /// 清單顯示之後、按下「拿掉」之前，一次匯入又把另一個附加來源標成已刪除。動作只能拿掉使用者看到的那一組——
    /// 先前 `removeAll { orphanedAt != nil }` 連沒看過的也拿掉，只在事後的報告裡才說。
    func testRemovalRefusesWhenTheOrphanedSetDiffersFromTheOneTheUserSaw() throws {
        commitAll()
        let saw = try seen("partial2020")
        XCTAssertEqual(saw, ["5:K2"])
        // 外部：K3（lib 7）也在 Zotero 端被刪了
        let store = LibraryStore(root: root)
        var changed = try XCTUnwrap(try entry("partial2020"))
        changed.additionalProvenance[1].orphanedAt = gone
        try store.writeEntry(changed)
        commitAll()
        let model = OrphanModel(state: state)
        XCTAssertThrowsError(try model.removeOrphanedAdditionalSources(citekey: "partial2020", reason: "r", seen: saw)) { err in
            XCTAssertEqual(err as? AdjudicationError,
                           .orphanedSourcesChanged(citekey: "partial2020", seen: "5:K2", now: "5:K2、7:K3"), "\(err)")
        }
        XCTAssertEqual(try entry("partial2020")?.additionalProvenance.count, 2, "零寫入：沒看過的 K3 不得被拿掉")
        // 看到目前這一組並確認之後才動手
        _ = try model.removeOrphanedAdditionalSources(citekey: "partial2020", reason: "r", seen: ["7:K3", "5:K2"])
        XCTAssertEqual(try entry("partial2020")?.additionalProvenance, [])
    }

    /// 反方向：使用者看到的來源之一已在 Zotero 端恢復——同樣不是他確認的那一組，拒絕。
    func testRemovalRefusesWhenASeenSourceIsNoLongerOrphaned() throws {
        commitAll()
        let model = OrphanModel(state: state)
        XCTAssertThrowsError(try model.removeOrphanedAdditionalSources(
            citekey: "partial2020", reason: "r", seen: ["5:K2", "7:K3"]))
        XCTAssertThrowsError(try model.removeOrphanedAdditionalSources(citekey: "partial2020", reason: "r", seen: []))
        XCTAssertEqual(try entry("partial2020")?.additionalProvenance.count, 2)
    }

    /// LOW（security）：形狀重驗發生在慢速 git 閘之前、寫入卻用閘之前的快照。閘通過之後那筆記錄被外部恢復了一個來源，
    /// 動作必須拒絕，而不是用舊快照整檔寫回、把剛恢復的來源拿掉。
    func testRemovalRefusesWhenTheRecordChangesAfterTheGitGate() throws {
        commitAll()
        let model = OrphanModel(state: state)
        let saw = try seen("partial2020")
        model.afterRecoverabilityGate = {
            var restored = try XCTUnwrap(try self.entry("partial2020"))
            restored.additionalProvenance[0].orphanedAt = nil
            try LibraryStore(root: self.root).writeEntry(restored)
        }
        XCTAssertThrowsError(try model.removeOrphanedAdditionalSources(citekey: "partial2020", reason: "r", seen: saw)) { err in
            XCTAssertEqual(err as? AdjudicationError, .changedDuringCheck("partial2020"), "\(err)")
        }
        let after = try XCTUnwrap(try entry("partial2020"))
        XCTAssertEqual(after.additionalProvenance.map(\.zoteroKey), ["K2", "K3"], "剛恢復的來源不得被拿掉")
        XCTAssertNil(after.additionalProvenance[0].orphanedAt)
    }

    // MARK: - #609 R1 verify（security）：三個 App 寫入動作的定位守衛一致

    /// 同一個 citekey 有兩份記錄檔：以 citekey 定位會猜是哪一筆。垃圾桶、脫鉤、拿掉來源三個動作都拒絕、零寫入。
    func testAllThreeOrphanActionsRefuseAnUnlocatableCitekey() throws {
        commitAll()
        let entities = root.appendingPathComponent("entities")
        var snapshots: [String: Data] = [:]
        for ck in ["allgone2020", "partial2020"] {
            let e = try XCTUnwrap(try entry(ck))
            let dir = root.appendingPathComponent("entries")
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            try EntryYAML.encode(e).write(to: dir.appendingPathComponent("\(ck).yaml"), atomically: true, encoding: .utf8)
            snapshots[ck] = try Data(contentsOf: entities.appendingPathComponent("\(e.id.uuidString).yaml"))
        }
        try state.load()
        // #709：App 的清單只列 entities/ 那一份；三個動作重讀磁碟、在完整的 load 上定位，照舊拒絕
        XCTAssertEqual(state.entries.filter { $0.citekey == "allgone2020" }.count, 1, "App 只列 entities/ 那一份")
        XCTAssertEqual(try state.store.load().entries.filter { $0.citekey == "allgone2020" }.count, 2, "前提：磁碟上兩份都在")
        let model = OrphanModel(state: state)
        for action in [OrphanModel.Action.moveToTrash, .detachFromZotero] {
            XCTAssertThrowsError(try model.resolve(citekey: "allgone2020", action: action)) { err in
                XCTAssertEqual(err as? AdjudicationError, .unlocatableCitekey("allgone2020"), "\(action)：\(err)")
            }
        }
        XCTAssertThrowsError(try model.removeOrphanedAdditionalSources(
            citekey: "partial2020", reason: "r", seen: ["5:K2"])) { err in
            XCTAssertEqual(err as? AdjudicationError, .unlocatableCitekey("partial2020"), "\(err)")
        }
        for (ck, bytes) in snapshots {
            let e = try XCTUnwrap(state.entries.first { $0.citekey == ck })
            XCTAssertEqual(try Data(contentsOf: entities.appendingPathComponent("\(e.id.uuidString).yaml")), bytes, "\(ck) 一個位元都不動")
        }
    }

    // MARK: - #609 R1 verify：失敗之後保留已打的理由；空理由不能按

    func testReasonDraftSurvivesAFailureAndIsClearedOnSuccess() {
        var draft = RemovalReasonDraft()
        XCTAssertFalse(draft.isSubmittable, "還沒打理由")
        draft.open(for: "partial2020")
        draft.text = "群組那份已刪、不再等"
        XCTAssertTrue(draft.isSubmittable)
        // 動作失敗（例如記錄檔還沒 commit）→ 使用者 commit 之後重開同一筆：理由還在
        draft.open(for: "partial2020")
        XCTAssertEqual(draft.text, "群組那份已刪、不再等")
        // 換另一筆：不帶著別筆的理由
        draft.open(for: "other2020")
        XCTAssertEqual(draft.text, "")
        draft.text = "  \n\t"
        XCTAssertFalse(draft.isSubmittable, "只有空白＝空理由")
        draft.text = "x"
        draft.clearAfterSuccess()
        XCTAssertEqual(draft.text, "")
        draft.open(for: "other2020")
        XCTAssertEqual(draft.text, "", "成功之後不留舊理由")
    }

    // MARK: - #684：確認提示按下「拿掉」之後的全部狀態轉換（單一 `.alert` 的狀態，`OrphanAlertState`）

    /// 使用者看著確認提示：狀態機裡確認提示在畫面上，`confirmRemoval` 的結果要排在它後面。
    private func confirming(_ citekey: String) throws -> (PendingRemoval, OrphanAlertState) {
        let pending = PendingRemoval(citekey: citekey, seen: try seen(citekey), sourcesLabel: "5:K2")
        var alert = OrphanAlertState()
        alert.show(.confirmRemoval(pending))
        return (pending, alert)
    }

    func testConfirmRemovalSuccessQueuesTheReportAndClearsTheDraft() throws {
        commitAll()
        let (pending, initial) = try confirming("partial2020")
        var alert = initial
        var draft = RemovalReasonDraft()
        draft.open(for: "partial2020")
        draft.text = "群組那份已刪、不再等"
        OrphanModel(state: state).confirmRemoval(pending, draft: &draft, alert: &alert)
        XCTAssertEqual(try entry("partial2020")?.additionalProvenance.map(\.zoteroKey), ["K3"], "真的拿掉了")
        XCTAssertEqual(alert.presented, .confirmRemoval(pending), "確認提示還在畫面上，結果不搶它")
        guard case .removed(let report)? = alert.queued else { return XCTFail("成功要排 .removed：\(String(describing: alert.queued))") }
        XCTAssertTrue(report.contains("5:K2") && report.contains("群組那份已刪、不再等"), "報告帶來源鍵與理由全文：\(report)")
        XCTAssertEqual(draft.text, "", "理由已進報告，草稿清掉")
        // 關掉確認提示之後結果提示才輪到
        alert.dismissed()
        alert.presentQueued()
        XCTAssertEqual(alert.presented?.title, "已拿掉")
    }

    func testConfirmRemovalFailureQueuesTheErrorAndKeepsTheDraft() throws {
        // 不在 git 裡：移除面一族要求記錄檔已 commit——最常見的失敗
        let (pending, initial) = try confirming("partial2020")
        var alert = initial
        var draft = RemovalReasonDraft()
        draft.open(for: "partial2020")
        draft.text = "群組那份已刪、不再等"
        OrphanModel(state: state).confirmRemoval(pending, draft: &draft, alert: &alert)
        XCTAssertEqual(try entry("partial2020")?.additionalProvenance.count, 2, "零寫入")
        guard case .failed(let message)? = alert.queued else { return XCTFail("失敗要排 .failed：\(String(describing: alert.queued))") }
        XCTAssertTrue(message.contains("git"), message)
        XCTAssertEqual(draft.text, "群組那份已刪、不再等", "失敗保留理由——commit 之後重開同一筆不必重打")
        XCTAssertTrue(draft.isSubmittable)
        alert.dismissed()
        alert.presentQueued()
        XCTAssertEqual(alert.presented?.title, "操作失敗")
    }

    /// 「轉純 Akashic」的按鈕在清單列上：失敗時畫面上沒有任何呈現，錯誤立刻顯示；成功時提示不動。
    /// （垃圾桶的按鈕在 `confirmationDialog` 裡——對話框正在關閉，見下一支。）
    func testAttemptShowsAFailureImmediatelyAndLeavesSuccessAlone() throws {
        var alert = OrphanAlertState()
        OrphanModel.attempt(alert: &alert) { try OrphanModel(state: self.state).resolve(citekey: "allgone2020", action: .detachFromZotero) }
        XCTAssertEqual(alert, OrphanAlertState(), "成功不彈任何提示")
        XCTAssertNil(try entry("allgone2020")?.provenance, "前提：動作真的成功了（不是沒跑）")
        OrphanModel.attempt(alert: &alert) { try OrphanModel(state: self.state).resolve(citekey: "ghost2000x", action: .moveToTrash) }
        guard case .failed(let message)? = alert.presented else { return XCTFail("失敗要立刻顯示：\(alert)") }
        XCTAssertFalse(message.isEmpty)
        XCTAssertNil(alert.queued)
    }

    /// #684 R1 verify 第 19／21 列：垃圾桶在 `confirmationDialog` 的按鈕裡跑，失敗時對話框正在關閉——錯誤要排隊，
    /// 等對話框關掉之後才顯示（直接顯示會被那次關閉抹掉，`OrphanAlertState` 檔頭的同一條理由）。
    func testAttemptFromADismissingDialogQueuesTheFailure() throws {
        var alert = OrphanAlertState()
        OrphanModel.attempt(alert: &alert, fromDismissingPresentation: true) {
            try OrphanModel(state: self.state).resolve(citekey: "ghost2000x", action: .moveToTrash)
        }
        XCTAssertNil(alert.presented, "對話框正在關閉：不立刻顯示")
        guard case .failed(let message)? = alert.queued else { return XCTFail("失敗要排隊：\(alert)") }
        XCTAssertFalse(message.isEmpty)
        alert.presentQueued()
        XCTAssertEqual(alert.presented?.title, "操作失敗")
    }
}
