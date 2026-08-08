import XCTest
import Foundation
@testable import AkashicCore
@testable import AkashicStoreIO

/// #168：候選遷移保留舊 id，讓「同一組候選＝同一筆記錄」失效。
///
/// ## 為什麼這不是潔癖
///
/// #75 的三道守衛**全部 key 在那個不變式上**：
///
/// | 守衛 | 它怎麼找到要保護的判斷 |
/// |---|---|
/// | `contradictsJudgement`（#75 對一）| 讀 target 記錄的 `judgement` |
/// | #133 F1「無判斷的重呼叫不得抹掉判斷」| 「同組候選⇒同一筆記錄」查既有 |
/// | 159-4「重錄不得抹掉 prefers」| 同上 |
///
/// id drift 讓同一組候選有**兩筆**記錄，於是三道守衛全部去問了沒有判斷的那筆。
/// 席位實測：帶判斷與 `prefers` 的那筆被連帶刪除、判斷指名為正確的實體被合併掉，
/// **dry-run 與實跑兩次都沒有一個字提到有判斷存在**，exit 0。
///
/// 觸發路徑全部是正常操作：record → resolve → 再 record → resolve。
final class DivergenceIDDriftTests: XCTestCase {
    private var root: URL!
    private var store: LibraryStore!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("akashic-168-\(UUID().uuidString)")
        try FileManager.default.createDirectory(
            at: root.appendingPathComponent("entities"), withIntermediateDirectories: true)
        try StoreVersion.write(root: root, format: StoreVersion.supported)
        GitFixture.initRepo(root)
        store = LibraryStore(root: root)
    }
    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: root) }

    /// **刻意不給 `authorized`／`orcid` 等內容**：`fieldsLostByMerging` 會擋下
    /// 「被併者帶有倖存者沒有的資料」，而本組測試要驗的是 id 與候選集的關係，
    /// 不是欄位遺失。給了內容就永遠走不到被測的那段路。
    private func person(_ key: String) throws {
        try store.writePerson(Person(key: key, names: [key]))
    }
    private func idFor(_ keys: [String]) -> UUID {
        DeterministicUUID.forDivergence(candidateKeys: keys)
    }
    private func record(_ keys: [String], question: String = "同一人？",
                        judgement: String? = nil, prefers: String? = nil) throws -> Divergence {
        try store.recordDivergence(
            question: question,
            candidates: keys.map { (key: $0, shape: EntityKind.person) },
            // judgement 與 rests-on 必須成對（既有守衛）——沒有依據的斷言不是判斷
            judgement: judgement,
            restsOn: judgement == nil ? [] : ["sha256:" + String(repeating: "ab", count: 32)],
            prefers: prefers)
    }

    // MARK: - 不變式本身

    /// **遷移後 id 必須重算。** 這是整條鏈的根。
    func testMigratedRecordGetsRecomputedID() throws {
        for k in ["chen-a", "fann-a", "fann-b"] { try person(k) }
        let side = try record(["chen-a", "fann-a"])
        let main = try record(["fann-a", "fann-b"])
        GitFixture.commitAll(root, message: "seed")

        _ = try store.resolveDivergence(id: main.id, survivor: "fann-b")

        let after = try store.load().divergences
        XCTAssertEqual(after.count, 1, "主記錄刪除、side 遷移後留下：\(after.map(\.id))")
        let migrated = try XCTUnwrap(after.first)
        XCTAssertEqual(Set(migrated.candidates.map(\.key)), ["chen-a", "fann-b"], "候選要遷移")
        XCTAssertEqual(migrated.id, idFor(["chen-a", "fann-b"]),
                       "id 必須由**遷移後**的候選集推出——保留舊 id 就是 #168")
        XCTAssertNotEqual(migrated.id, side.id, "舊 id 不該還在")
        // 舊檔要刪掉，否則兩個檔案描述同一件事
        XCTAssertFalse(FileManager.default.fileExists(
            atPath: root.appendingPathComponent("entities/\(side.id.uuidString).yaml").path),
                       "改名 = 刪舊建新，舊檔留著就是兩筆記錄")
    }

    /// **原始的五步鏈**：修好之後，第三步的 `record-divergence` 會落在同一筆記錄上，
    /// 於是 #133 F1 / 159-4 / `contradictsJudgement` 全部重新生效。
    func testTheFiveStepChainNoLongerBypassesJudgementGuards() throws {
        for k in ["chen-a", "fann-a", "fann-b"] { try person(k) }
        _ = try record(["chen-a", "fann-a"])
        let main = try record(["fann-a", "fann-b"])
        GitFixture.commitAll(root, message: "seed")

        // 步驟 2：遷移發生，side 的候選變成 {chen-a, fann-b}，id 跟著改
        _ = try store.resolveDivergence(id: main.id, survivor: "fann-b")
        let migratedID = idFor(["chen-a", "fann-b"])

        // 步驟 3：對同一組候選補上判斷。**#168 之前這裡會產生第二筆記錄。**
        let judged = try record(["chen-a", "fann-b"],
                                judgement: "名冊確認 chen-a 才是正式寫法", prefers: "chen-a")
        XCTAssertEqual(judged.id, migratedID, "同一組候選必須落在同一筆記錄上")
        XCTAssertEqual(try store.load().divergences.count, 1,
                       "同一組候選只能有一筆記錄——兩筆正是 #168 的病灶")
        GitFixture.commitAll(root, message: "judged")

        // 步驟 4：選判斷反對的方向 → **必須被擋**
        XCTAssertThrowsError(
            try store.resolveDivergence(id: migratedID, survivor: "fann-b")
        ) { err in
            guard case DivergenceResolveError.contradictsJudgement = err else {
                return XCTFail("要由 #75 的對一守衛擋下，實得：\(err)")
            }
        }
        // 判斷指名為正確的那個實體必須還在
        XCTAssertTrue(try store.load().people.contains { $0.key == "chen-a" },
                      "判斷說 chen-a 才是正式寫法——它不得被靜默合併掉")
    }

    /// 遷移**不改變**候選時 id 不動——不要把「重算」變成無條件改名。
    func testUnaffectedRecordsKeepTheirID() throws {
        for k in ["x", "y", "fann-a", "fann-b"] { try person(k) }
        let untouched = try record(["x", "y"])
        let main = try record(["fann-a", "fann-b"])
        GitFixture.commitAll(root, message: "seed")
        _ = try store.resolveDivergence(id: main.id, survivor: "fann-b")
        XCTAssertEqual(try store.load().divergences.map(\.id), [untouched.id],
                       "沒被遷移到的記錄不得改名")
    }

    // MARK: - 重算引入的三種碰撞

    /// **碰撞 1：遷移後撞上既有記錄，而內容不同 → 拒絕整個消歧。**
    ///
    /// 自動挑一邊的判斷活下來，正是本 issue 要修的靜默毀損。
    func testCollisionWithExistingRecordIsRefused() throws {
        for k in ["chen-a", "fann-a", "fann-b"] { try person(k) }
        _ = try record(["chen-a", "fann-a"], question: "A 問法")
        _ = try record(["chen-a", "fann-b"], question: "B 問法",
                       judgement: "名冊確認 chen-a", prefers: "chen-a")
        let main = try record(["fann-a", "fann-b"])
        GitFixture.commitAll(root, message: "seed")

        XCTAssertThrowsError(try store.resolveDivergence(id: main.id, survivor: "fann-b")) { err in
            guard case let DivergenceResolveError.migrationCollision(details) = err else {
                return XCTFail("要拒絕而不是靜默挑一邊：\(err)")
            }
            XCTAssertTrue(details.joined().contains("名冊確認 chen-a"),
                          "訊息要指名將被犧牲的判斷，否則不可執行：\(details)")
        }
        XCTAssertEqual(try store.load().divergences.count, 3, "拒絕就不得動任何檔案")
        XCTAssertTrue(try store.load().people.contains { $0.key == "fann-a" }, "被併實體也不得動")
    }

    /// **dry-run 必須看得到同一個拒絕**——它是唯一還能反悔的時點。
    func testPreviewSurfacesTheSameCollision() throws {
        for k in ["chen-a", "fann-a", "fann-b"] { try person(k) }
        _ = try record(["chen-a", "fann-a"], question: "A 問法")
        _ = try record(["chen-a", "fann-b"], question: "B 問法", judgement: "j", prefers: "chen-a")
        let main = try record(["fann-a", "fann-b"])
        GitFixture.commitAll(root, message: "seed")
        XCTAssertThrowsError(try store.previewResolveDivergence(
            id: main.id, survivor: "fann-b", overrideReason: nil)) { err in
            guard case DivergenceResolveError.migrationCollision = err else {
                return XCTFail("dry-run 與實跑的拒絕條件必須相同：\(err)")
            }
        }
    }

    /// **零損失的碰撞可以靜默合併**——內容完全相同時沒有東西可失去。
    func testIdenticalContentCollisionMergesSilently() throws {
        for k in ["chen-a", "fann-a", "fann-b"] { try person(k) }
        _ = try record(["chen-a", "fann-a"], question: "同一人？")
        _ = try record(["chen-a", "fann-b"], question: "同一人？")
        let main = try record(["fann-a", "fann-b"])
        GitFixture.commitAll(root, message: "seed")

        let report = try store.resolveDivergence(id: main.id, survivor: "fann-b")
        XCTAssertEqual(report.failures, [], "零損失不該擋：\(report.failures)")
        let after = try store.load().divergences
        XCTAssertEqual(after.count, 1, "兩筆合成一筆：\(after.map(\.id))")
        XCTAssertEqual(after.first?.id, idFor(["chen-a", "fann-b"]))
    }

    /// **碰撞 2：兩筆遷移記錄互撞。** 只比對既有記錄會漏掉這一種。
    ///
    /// `{chen-a, fann-a}` 與 `{chen-a, fann-b}` 在 fann-a 併入 fann-b 之後同為
    /// `{chen-a, fann-b}`——兩邊都在遷移，都不在「既有記錄」的對照組裡。
    func testTwoMigratingRecordsCollidingWithEachOtherIsRefused() throws {
        for k in ["chen-a", "fann-a", "fann-b", "fann-c"] { try person(k) }
        // 兩筆都會被遷移（都含 fann-a 或 fann-c，兩者都併入 fann-b）
        _ = try record(["chen-a", "fann-a"], question: "A 問法", judgement: "ja", prefers: "chen-a")
        _ = try record(["chen-a", "fann-c"], question: "C 問法")
        let main = try store.recordDivergence(
            question: "三者同一人？",
            candidates: ["fann-a", "fann-b", "fann-c"].map { (key: $0, shape: EntityKind.person) },
            judgement: nil, restsOn: [], prefers: nil)
        GitFixture.commitAll(root, message: "seed")

        XCTAssertThrowsError(try store.resolveDivergence(id: main.id, survivor: "fann-b")) { err in
            guard case let DivergenceResolveError.migrationCollision(details) = err else {
                return XCTFail("兩筆遷移記錄互撞也要擋：\(err)")
            }
            XCTAssertTrue(details.joined().contains("ja"), "要指名將被犧牲的判斷：\(details)")
        }
    }

    /// 多筆同時改名時，每一筆都要以**新 id** 落地、舊檔全清。
    ///
    /// **歸因（重要）**：這條**不**驗「改名刪除不會刪到剛寫好的檔」那個排除
    /// （`!writtenIDs.contains(old)`）。mutation 實測拿掉它九條全綠——因為那個
    /// 危害**現行不可達**：B 的舊 id 等於 A 的新 id ⇒ B 的原候選集等於 A 的遷移後
    /// 候選集 ⇒ B 不含被併鍵 ⇒ B 不遷移 ⇒ B 走碰撞路徑而非改名路徑。
    ///
    /// 那個排除是 defence-in-depth，釘的是「不遷移的記錄一定走碰撞路徑」這個
    /// 前提。歸因寫錯會讓日後改動路徑分派的人以為這條還罩得住。
    func testMultipleRenamesAllLandAtNewIDs() throws {
        for k in ["a", "b", "fann-a", "fann-b"] { try person(k) }
        // {a, fann-a} → {a, fann-b}；{b, fann-a} → {b, fann-b}。兩者互不撞，
        // 但驗證重點是：所有遷移後的記錄都必須真的存在於磁碟上。
        _ = try record(["a", "fann-a"])
        _ = try record(["b", "fann-a"])
        let main = try record(["fann-a", "fann-b"])
        GitFixture.commitAll(root, message: "seed")

        let report = try store.resolveDivergence(id: main.id, survivor: "fann-b")
        XCTAssertEqual(report.failures, [])
        let after = try store.load().divergences
        XCTAssertEqual(Set(after.map(\.id)), [idFor(["a", "fann-b"]), idFor(["b", "fann-b"])],
                       "兩筆都要以新 id 存在：\(after.map(\.id))")
        // 舊檔全清
        for old in [idFor(["a", "fann-a"]), idFor(["b", "fann-a"]), main.id] {
            XCTAssertFalse(FileManager.default.fileExists(
                atPath: root.appendingPathComponent("entities/\(old.uuidString).yaml").path),
                           "舊檔 \(old) 未清除")
        }
    }

    /// 塌縮（候選 <2）的路徑不受影響——它本來就刪，不走改名。
    func testCollapsedRecordsStillDeleted() throws {
        for k in ["fann-a", "fann-b"] { try person(k) }
        let collapsing = try record(["fann-a", "fann-b"], question: "會塌縮的")
        // 另建一筆主記錄（同候選集會撞 id，所以用第三個 key）
        try person("fann-c")
        let main = try store.recordDivergence(
            question: "主記錄",
            candidates: ["fann-a", "fann-b", "fann-c"].map { (key: $0, shape: EntityKind.person) },
            judgement: nil, restsOn: [], prefers: nil)
        GitFixture.commitAll(root, message: "seed")

        let report = try store.resolveDivergence(id: main.id, survivor: "fann-b")
        XCTAssertEqual(report.failures, [])
        XCTAssertTrue(report.collapsedDetails.contains { $0.id == collapsing.id.uuidString },
                      "塌縮要照舊回報：\(report.collapsedDetails)")
        XCTAssertEqual(try store.load().divergences, [], "兩筆都該不在了")
    }
}
