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
    private func seed(into s: LibraryStore, commit: Bool = true) throws -> Divergence {
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
        // 後者由 testRefusesWhenDoomedFilesAreUncommitted 專門覆蓋。`commit: false` 給沒有 repo 的 store 用
        // （`testRefusesOutsideVersionControl`）——`commitAll` 自 R3 起對失敗出聲，對非 repo 呼叫它是 fixture 的錯。
        if commit { GitFixture.commitAll(s.root, message: "seed") }
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

    /// #558 R2（D86）：**倖存者**從未 commit——person 合併把別名併進去、把 verdict 遷進去並收攏（#554 R17／R18），改寫前的內容 git 取不回。
    /// 閘先前只看被併的檔與 holder 檔，倖存者不在任何一張名單上（R1 verify 第 2 列對 person 側的要求）。
    func testRefusesWhenSurvivorPersonIsUntracked() throws {
        var merged = Person(key: "fann-cathy-s-j-2"); merged.names = ["B"]
        try store.writePerson(merged)
        let d = Divergence(id: UUID(), question: "是否為同一人",
                           candidates: [DivergenceCandidate(key: "fann-cathy-s-j", shape: .person),
                                        DivergenceCandidate(key: "fann-cathy-s-j-2", shape: .person)])
        try store.writeDivergence(d)
        GitFixture.commitAll(root, message: "everything but the survivor")
        var survivor = Person(key: "fann-cathy-s-j"); survivor.names = ["A"]
        try store.writePerson(survivor)                    // untracked
        for (desc, op) in [("實跑", { _ = try self.store.resolveDivergence(id: d.id, survivor: "fann-cathy-s-j") }),
                           ("dry-run", { _ = try self.store.previewResolveDivergence(id: d.id, survivor: "fann-cathy-s-j", overrideReason: nil) })] {   // R3：兩面（R2 verify 第 18 列）
            XCTAssertThrowsError(try op(), desc) { err in
                guard case DivergenceResolveError.deletionNotRecoverable(let files) = err else { return XCTFail("\(desc)：應為 deletionNotRecoverable，實得 \(err)") }
                XCTAssertTrue(files.contains { $0.path.contains(survivor.id.uuidString) }, "\(desc)：訊息必須指名倖存者的檔：\(files)")
                XCTAssertFalse(files.contains { $0.path.contains(merged.id.uuidString) }, "\(desc)：被併者已 commit，不該進清單：\(files)")
            }
        }
        let after = try store.load()
        XCTAssertEqual(after.people.count, 2); XCTAssertEqual(after.divergences.count, 1)
        XCTAssertEqual(after.people.first { $0.key == "fann-cathy-s-j" }?.names, ["A"], "拒絕後倖存者未被改寫")
    }

    /// #558 R3（R2 verify 五席同指的 HIGH——DA 席那一輪缺席）：store 是 repo 的**子目錄**時，`git diff --name-only` 的輸出相對 repo root、`ls-files` 相對 cwd
    /// ——R2 的批次比對對 dirty 那一半永遠不命中，dirty 的被併檔被直接刪掉、閘沉默（五席真 binary 重現）。`--relative` 讓兩個基準一致。
    /// 三種狀態各測一格、每格實跑與 dry-run 兩腿：dirty 的被併實體、dirty 的倖存者（D86 的改寫閘）、untracked 的第三方 holder
    /// （釘住「`ls-files` 是 cwd 相對」在巢狀佈局下那句話——R4；R3 verify 第 5／15 列：R3 的 doc 宣稱三格，實際只有兩格、倖存者只跑實跑）。
    func testRefusesDirtyFilesWhenStoreIsARepoSubdirectory() throws {
        let repoRoot = FileManager.default.temporaryDirectory.appendingPathComponent("akashic-nested-\(UUID().uuidString)")
        let nested = repoRoot.appendingPathComponent("library")
        try FileManager.default.createDirectory(at: nested.appendingPathComponent("entities"), withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: repoRoot) }
        try StoreVersion.write(root: nested, format: StoreVersion.supported)
        GitFixture.initRepo(repoRoot)
        let s = LibraryStore(root: nested)
        let d = try seed(into: s)                                   // seed 內 commitAll(s.root)——對巢狀 store 也是整個 repo
        XCTAssertEqual(GitFixture.capture(["rev-parse", "--show-prefix"], in: nested)?.trimmingCharacters(in: .whitespacesAndNewlines), "library/", "fixture 真的是巢狀的")
        func dirty(_ id: UUID) throws {
            let url = s.entityURL(id: id)
            try (String(contentsOf: url, encoding: .utf8) + "# HUMAN NOTE ONLY ON DISK\n").write(to: url, atomically: true, encoding: .utf8)
        }
        let people = try s.load().people
        try dirty(try XCTUnwrap(people.first { $0.key == "fann-cathy-s-j-2" }).id)   // 被併實體 dirty
        for (desc, op) in [("實跑", { _ = try s.resolveDivergence(id: d.id, survivor: "fann-cathy-s-j") }),
                           ("dry-run", { _ = try s.previewResolveDivergence(id: d.id, survivor: "fann-cathy-s-j", overrideReason: nil) })] {
            XCTAssertThrowsError(try op(), "\(desc)：巢狀 store 的 dirty 被併檔要拒") { err in
                guard case DivergenceResolveError.deletionNotRecoverable(let files) = err else { return XCTFail("\(desc)：\(err)") }
                XCTAssertEqual(files.count, 1, "\(desc)：\(files)")
                XCTAssertTrue(files.contains { $0.why.contains("未提交的修改") }, "\(desc)：要說是 dirty 不是 untracked：\(files)")
            }
        }
        XCTAssertEqual(try s.load().people.count, 2, "拒絕後不得動到任何檔案")
        GitFixture.commitAll(repoRoot, message: "note")
        try dirty(try XCTUnwrap(people.first { $0.key == "fann-cathy-s-j" }).id)     // 倖存者 dirty（D86）
        for (desc, op) in [("實跑", { _ = try s.resolveDivergence(id: d.id, survivor: "fann-cathy-s-j") }),
                           ("dry-run", { _ = try s.previewResolveDivergence(id: d.id, survivor: "fann-cathy-s-j", overrideReason: nil) })] {
            XCTAssertThrowsError(try op(), "\(desc)：巢狀 store 的 dirty 倖存者要拒") { err in
                guard case DivergenceResolveError.deletionNotRecoverable(let files) = err else { return XCTFail("\(desc)：\(err)") }
                XCTAssertTrue(files.contains { $0.why.contains("未提交的修改") } && files.count == 1, "\(desc)：\(files)")
            }
        }
        GitFixture.commitAll(repoRoot, message: "note 2")
        XCTAssertNoThrow(try s.previewResolveDivergence(id: d.id, survivor: "fann-cathy-s-j", overrideReason: nil), "全部 commit 後巢狀 store 照常通過")
        // 第三格：一筆持有指向被併鍵 verdict 的 organization 記錄，寫了沒 commit——holder 檔進閘，理由要是 untracked 不是 dirty
        var holder = Organization(key: "iss", names: TimelineOf([TemporalValue(value: "ISS")]))
        holder.references = [ProvenanceReference(
            field: "resolution-confirmed",
            value: ProvenanceReference.VerdictPairingValue(holderKind: .person, holder: "fann-cathy-s-j-2", literal: "Fann").encoded,
            kind: .judgement(statement: "測試用判定", restsOn: []))]
        _ = try s.writeOrganization(holder)                                          // untracked
        for (desc, op) in [("實跑", { _ = try s.resolveDivergence(id: d.id, survivor: "fann-cathy-s-j") }),
                           ("dry-run", { _ = try s.previewResolveDivergence(id: d.id, survivor: "fann-cathy-s-j", overrideReason: nil) })] {
            XCTAssertThrowsError(try op(), "\(desc)：巢狀 store 的 untracked holder 要拒") { err in
                guard case DivergenceResolveError.deletionNotRecoverable(let files) = err else { return XCTFail("\(desc)：\(err)") }
                XCTAssertEqual(files.count, 1, "\(desc)：\(files)")
                XCTAssertTrue(files.contains { $0.path.contains(holder.id.uuidString) && $0.why.contains("未被 git 追蹤") }, "\(desc)：要說是 untracked 不是 dirty：\(files)")
            }
        }
        GitFixture.commitAll(repoRoot, message: "holder")
        XCTAssertNoThrow(try s.previewResolveDivergence(id: d.id, survivor: "fann-cathy-s-j", overrideReason: nil))
    }

    /// #558 R3（R2 verify 第 13／19 列）：拒絕清單自 D86 起由 store 內容決定體積——截 `unrecoverableFilesCap` 並揭露總數，
    /// 否則 96 KB 的 sink 會無聲截掉尾巴、使用者看不出還有幾筆。R4（R3 verify 第 9／14／16／17 列）：常數是這個錯誤**自己的**（不借
    /// `Entry.perRecordWarningCap`——它的母體是 per-record warning），超限時補救句不再說「這些檔案」，typed payload 不截。
    func testRefusalListIsCappedAndDisclosesTheTotal() {
        let cap = DivergenceResolveError.unrecoverableFilesCap
        let files = (0..<(cap + 5)).map { (path: "entities/F\($0).yaml", why: "未被 git 追蹤") }
        let msg = DivergenceResolveError.deletionNotRecoverable(files: files).errorDescription ?? ""
        XCTAssertEqual(msg.components(separatedBy: "\n  - ").count - 1, cap, msg)
        XCTAssertTrue(msg.contains("另有 5 個檔未列出（共 \(cap + 5) 個）") && msg.contains("（共 \(cap + 5) 個）："), msg)
        XCTAssertTrue(msg.contains("先把 store 內未提交的變更全部 commit") && !msg.contains("這些檔案（或確認"), "超限時補救句不得只指被列出的那幾個：\(msg)")
        let short = DivergenceResolveError.deletionNotRecoverable(files: Array(files.prefix(3))).errorDescription!
        XCTAssertFalse(short.contains("另有"), "未超過上限不加概括句")
        XCTAssertTrue(short.contains("這些檔案（或確認"), "未超限時補救句照舊指這幾個檔：\(short)")
        if case DivergenceResolveError.deletionNotRecoverable(let payload) = DivergenceResolveError.deletionNotRecoverable(files: files) {
            XCTAssertEqual(payload.count, cap + 5, "typed payload 不截——截的只有 errorDescription")
        }
    }

    /// #558 R3（R2 verify 第 11／22 列）：fresh `git init`、零 commit 的 store——tracked 的檔要說「還沒有任何版本」，不是「無法執行 git」。
    func testUnbornHeadGivesItsOwnReason() throws {
        let bare = try makeStore(versioned: true)                    // initRepo 只 init，不 commit
        defer { try? FileManager.default.removeItem(at: bare) }
        let s = LibraryStore(root: bare)
        var p = Person(key: "a-b"); p.names = ["A"]; try s.writePerson(p)
        var q = Person(key: "c-d"); q.names = ["C"]; try s.writePerson(q)
        _ = GitFixture.run(["add", "--", "entities/\(p.id.uuidString).yaml"], in: bare)   // staged、未 commit
        let out = LibraryStore.filesNotSafelyRecoverable(root: bare, relativePaths: ["entities/\(p.id.uuidString).yaml", "entities/\(q.id.uuidString).yaml"])
        XCTAssertEqual(out.count, 2, "\(out)")
        XCTAssertTrue(out.contains { $0.path.contains(p.id.uuidString) && $0.why.contains("尚無任何 commit") }, "\(out)")
        XCTAssertTrue(out.contains { $0.path.contains(q.id.uuidString) && $0.why.contains("未被 git 追蹤") }, "\(out)")
        XCTAssertFalse(out.contains { $0.why.contains("無法執行 git") }, "git 明明跑得起來：\(out)")
    }

    /// #558 R4（R3 verify 第 1／4／10／19／21／25 列，D87）：`rev-parse --verify --quiet HEAD` 非零**不只**在 unborn——orphan 分支
    /// （`checkout --orphan`）與 HEAD 指向不存在的 ref 時同樣非零，而 repo 裡**有** commit。R3 對它們一律說「repo 尚無任何 commit」——
    /// 假話、且叫人在 orphan 分支上 commit。分辨器是 `rev-list -n1 --all`：空才是真 unborn。兩者都仍拒（HEAD 指不到 commit 就沒有可比對
    /// 的版本——過度拒絕是有記錄的誠實邊界），但訊息要說真話、指向「切回有 commit 的分支」。
    func testOrphanBranchAndBrokenHeadAreNotCalledAnEmptyRepo() throws {
        let d = try seed(into: store)                                // seed 已 commit（master 上有版本）
        let people = try store.load().people
        let paths = people.map { "entities/\($0.id.uuidString).yaml" }
        XCTAssertEqual(GitFixture.run(["checkout", "-q", "--orphan", "wip"], in: root), 0)
        let orphan = LibraryStore.filesNotSafelyRecoverable(root: root, relativePaths: paths)
        XCTAssertEqual(orphan.count, 2, "\(orphan)")
        XCTAssertTrue(orphan.allSatisfy { $0.why.contains("HEAD 沒有指向任何 commit") }, "\(orphan)")
        XCTAssertFalse(orphan.contains { $0.why.contains("尚無任何 commit") || $0.why.contains("無法執行 git") }, "repo 有 commit，不得說沒有：\(orphan)")
        XCTAssertThrowsError(try store.resolveDivergence(id: d.id, survivor: "fann-cathy-s-j")) { err in
            guard case DivergenceResolveError.deletionNotRecoverable(let files) = err else { return XCTFail("\(err)") }
            XCTAssertTrue(files.allSatisfy { $0.why.contains("切回") }, "訊息要指向切回有 commit 的分支：\(files)")
        }
        // HEAD 指向不存在的 ref（手改／損壞的 `.git/HEAD`）——同一句話；`ls-files` 仍讀得到 index
        try "ref: refs/heads/does-not-exist\n".write(to: root.appendingPathComponent(".git/HEAD"), atomically: true, encoding: .utf8)
        let broken = LibraryStore.filesNotSafelyRecoverable(root: root, relativePaths: paths)
        XCTAssertEqual(broken.count, 2, "\(broken)")
        XCTAssertTrue(broken.allSatisfy { $0.why.contains("HEAD 沒有指向任何 commit") }, "\(broken)")
    }

    /// #558 R4（R3 verify 第 7／24 列，D88）：`assume-unchanged`／`skip-worktree` 位元讓 `git diff HEAD` **不報**那個檔，而 `ls-files`
    /// 仍列它——R1／R2／R3 三代都判成 tracked+clean、真 binary 刪檔、磁碟版永久消失。`ls-files -v` 的 tag 小寫（assume-unchanged）
    /// 或 `S`（skip-worktree）即拒：git 的工作樹比對對它不作數，閘無從確認可回溯性。
    func testIndexBitsThatHideEditsAreRefused() throws {
        let d = try seed(into: store)
        let people = try store.load().people
        let doomed = try XCTUnwrap(people.first { $0.key == "fann-cathy-s-j-2" })
        let survivor = try XCTUnwrap(people.first { $0.key == "fann-cathy-s-j" })
        func edit(_ id: UUID) throws {
            let url = store.entityURL(id: id)
            try (String(contentsOf: url, encoding: .utf8) + "# ONLY ON DISK\n").write(to: url, atomically: true, encoding: .utf8)
        }
        for (flag, id, label) in [("--assume-unchanged", doomed.id, "assume-unchanged"), ("--skip-worktree", survivor.id, "skip-worktree")] {
            XCTAssertEqual(GitFixture.run(["update-index", flag, "--", "entities/\(id.uuidString).yaml"], in: root), 0)
            try edit(id)
            XCTAssertEqual(GitFixture.capture(["diff", "--name-only", "HEAD", "--", "entities/\(id.uuidString).yaml"], in: root), "", "前提：git 自己對這個檔閉嘴")
            for (desc, op) in [("實跑", { _ = try self.store.resolveDivergence(id: d.id, survivor: "fann-cathy-s-j") }),
                               ("dry-run", { _ = try self.store.previewResolveDivergence(id: d.id, survivor: "fann-cathy-s-j", overrideReason: nil) })] {
                XCTAssertThrowsError(try op(), "\(desc)／\(label)") { err in
                    guard case DivergenceResolveError.deletionNotRecoverable(let files) = err else { return XCTFail("\(desc)／\(label)：\(err)") }
                    XCTAssertEqual(files.count, 1, "\(desc)／\(label)：\(files)")
                    XCTAssertTrue(files.contains { $0.path.contains(id.uuidString) && $0.why.contains(label) }, "\(desc)／\(label)：\(files)")
                }
            }
            XCTAssertEqual(GitFixture.run(["update-index", "--no" + flag.dropFirst(), "--", "entities/\(id.uuidString).yaml"], in: root), 0)
            XCTAssertThrowsError(try store.previewResolveDivergence(id: d.id, survivor: "fann-cathy-s-j", overrideReason: nil)) { err in
                guard case DivergenceResolveError.deletionNotRecoverable(let files) = err else { return XCTFail("\(err)") }
                XCTAssertTrue(files.contains { $0.why.contains("未提交的修改") }, "拿掉位元後它就是一個普通的 dirty 檔：\(files)")
            }
            GitFixture.commitAll(root, message: label)
        }
        XCTAssertEqual(try store.load().people.count, 2, "全程零寫入")
        XCTAssertNoThrow(try store.previewResolveDivergence(id: d.id, survivor: "fann-cathy-s-j", overrideReason: nil))
    }

    /// #558 R4（R3 verify 第 14／17 列）：`deletionNotRecoverable` 的 typed payload 在 **throw 點**也不截——只有 `errorDescription` 截。
    /// 用一次真的合併：被併 person 被 25 筆 untracked 的 work 引用，閘的清單是 25 筆、payload 要 25 筆、描述只列 `unrecoverableFilesCap` 筆。
    func testThrownPayloadIsNotCapped() throws {
        let d = try seed(into: store)
        let n = DivergenceResolveError.unrecoverableFilesCap + 5
        for i in 0..<n {
            var w = Entry(id: UUID(), citekey: "cite\(i)", type: .periodicalArticle, title: "T\(i)")
            w.authors = [.key("fann-cathy-s-j-2")]
            try store.writeEntry(w)                                  // untracked：被改指的 entry 進閘
        }
        XCTAssertThrowsError(try store.previewResolveDivergence(id: d.id, survivor: "fann-cathy-s-j", overrideReason: nil)) { err in
            guard case DivergenceResolveError.deletionNotRecoverable(let files) = err else { return XCTFail("\(err)") }
            XCTAssertEqual(files.count, n, "payload 不截：\(files.count)")
            let msg = err.localizedDescription
            XCTAssertEqual(msg.components(separatedBy: "\n  - ").count - 1, DivergenceResolveError.unrecoverableFilesCap, msg)
            XCTAssertTrue(msg.contains("（共 \(n) 個）"), msg)
        }
    }

    /// #558 R4（R3 verify 第 22／26 列）：pathspec 分批的迴圈在整套測試裡從沒跨過第二批（沒有 fixture 超過 `gitPathspecChunk`）。
    /// 直呼 static API 餵超過一批的路徑：tracked 集合要跨批 union（尾批的 dirty／untracked 全部指名、頭批的 clean 不被誤報）、零 `cannotRun`、
    /// 重複的輸入只算一筆（第 18 列：去重是函式自己的事）。
    func testPathspecChunkingSpansBatches() throws {
        let n = LibraryStore.gitPathspecChunk + 100
        var paths: [String] = []
        for i in 0..<n {
            var p = Person(key: "p-\(i)"); p.names = ["P \(i)"]
            try store.writePerson(p)
            paths.append("entities/\(p.id.uuidString).yaml")
        }
        GitFixture.commitAll(root, message: "many")
        for rel in paths.suffix(3) {                                 // 尾批 dirty
            let url = root.appendingPathComponent(rel)
            try (String(contentsOf: url, encoding: .utf8) + "# dirty\n").write(to: url, atomically: true, encoding: .utf8)
        }
        var extra = Person(key: "p-extra"); extra.names = ["X"]; try store.writePerson(extra)   // 尾批 untracked
        let extraPath = "entities/\(extra.id.uuidString).yaml"
        let input = paths + [extraPath] + Array(paths.suffix(2))     // 重複兩筆 dirty 的——不去重會變 6 筆
        let out = LibraryStore.filesNotSafelyRecoverable(root: root, relativePaths: input)
        XCTAssertEqual(out.count, 4, "\(out)")
        XCTAssertEqual(Set(out.map(\.path)), Set(paths.suffix(3) + [extraPath]))
        XCTAssertTrue(out.filter { $0.why.contains("未提交的修改") }.count == 3 && out.filter { $0.why.contains("未被 git 追蹤") }.count == 1, "\(out)")
        XCTAssertFalse(out.contains { $0.why.contains("無法執行 git") }, "\(out)")
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
        // #558 R2（D86）：會被改指的 entry 也要 tracked+clean，否則閘在寫入前就拒——本測試要的是「載入得到、落地才失敗」，
        // 所以先 commit 再設 immutable（R2 之前這裡改寫的是一個 untracked 的檔，正是 D86 要擋的形狀）。
        GitFixture.commitAll(root, message: "other work")
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
        let d = try seed(into: s, commit: false)
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
