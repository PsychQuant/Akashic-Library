import Foundation
import XCTest
@testable import AkashicCore
@testable import AkashicStoreIO

/// #461：merge 側 verdict 收攏必須與 reference 排列無關（二階段修法），
/// 且**只**收攏本次遷移觸及的 (field, value)——鍵**不等於任一遷移輸出**的既有重複
/// 一筆不動（「消歧不是清理工具」，#71 的裁決由觸及集合守住）；落在觸及鍵上的
/// keeper 既有重複則**刻意**一併收攏，且每一列丟棄都進 `ResolveReport.verdictsCollapsed`。
/// venue 側的 doomed-first 案在 `VenueVerdictMigrationTests`；本檔補 person 側、
/// 「不同鍵的既有重複保留」負向案，以及 helper 層的純函數案（留存者、冪等、survivor 自保）。
final class OrderInsensitiveCollapseTests: XCTestCase {
    private var root: URL!
    private var store: LibraryStore!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("akashic-oic-\(UUID().uuidString)")
        try FileManager.default.createDirectory(
            at: root.appendingPathComponent("entities"), withIntermediateDirectories: true)
        GitFixture.initRepo(root)
        try StoreVersion.write(root: root, format: StoreVersion.supported)
        store = LibraryStore(root: root)
    }

    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: root) }

    private func entry(_ citekey: String) throws {
        try store.writeEntry(Entry(id: UUID(), citekey: citekey, type: .periodicalArticle,
                                   title: "T \(citekey)", authors: [.literal("A B")],
                                   date: "2020"))
    }

    private func verdict(_ field: String, holder: String, literal: String,
                         statement: String = "測試用判定") -> ProvenanceReference {
        ProvenanceReference(
            field: field,
            value: ProvenanceReference.VerdictPairingValue(
                holderKind: .work, holder: holder, literal: literal).encoded,
            kind: .judgement(statement: statement, restsOn: []))
    }

    private func statement(_ r: ProvenanceReference?) -> String? {
        if case .judgement(let s, _)? = r?.kind { return s }
        return nil
    }

    private func mergeDivergence(keeper: String, doomed: String) throws -> Divergence {
        let d = Divergence(
            id: UUID(), question: "\(keeper) 與 \(doomed) 是同一篇嗎",
            candidates: [DivergenceCandidate(key: keeper, shape: .work),
                         DivergenceCandidate(key: doomed, shape: .work)])
        _ = try store.writeDivergence(d)
        return d
    }

    /// person 側的 doomed-first 排列——#461 之前與 venue 同病（#271 起）。
    func testPersonMergeDoomedFirstAlsoCollapses() throws {
        try entry("pkeeper2020a")
        try entry("pdoomed2020a")
        var p = Person(key: "some-author", names: PersonNames(variant: ["Some Author"]))
        p.references = [verdict("resolution-confirmed", holder: "pdoomed2020a", literal: "Some Author"),
                        verdict("resolution-confirmed", holder: "pkeeper2020a", literal: "Some Author")]
        try store.writePerson(p)
        let d = try mergeDivergence(keeper: "pkeeper2020a", doomed: "pdoomed2020a")

        GitFixture.commitAll(store.root)
        let report = try store.resolveDivergence(id: d.id, survivor: "pkeeper2020a")

        let after = try store.load().people.first { $0.key == "some-author" }
        XCTAssertEqual(after?.references.count, 1,
                       "person 側 doomed-first 排列也必須收攏成一筆（#461）")
        XCTAssertTrue(after?.references.first?.value?.contains("work:pkeeper2020a") ?? false)
        // 丟掉的那一列（keeper 原版）要在報告裡說得出來——lossless-intake 執行細節 3
        XCTAssertEqual(report.verdictsCollapsed.count, 1, "\(report.verdictsCollapsed)")
        XCTAssertTrue(report.verdictsCollapsed.first?.hasPrefix("person「some-author」：") ?? false)
        XCTAssertTrue(report.verdictsCollapsed.first?.contains("work:pkeeper2020a :: Some Author") ?? false)
    }

    /// 與本次遷移**無關**（鍵不等於任一遷移輸出）的既有重複不得被收攏——觸及集合的
    /// 邊界（#461 Risks 釘住：觸及集合若過寬會退化成全量 dedup，重演被否決的方案 (a)）。
    /// 這支證的是「**不同鍵**」那一半；同鍵那一半見下方 helper 層的
    /// `testTouchedKeyCollapsesKeeperPreexistingDuplicatesDeliberately`。
    func testUnrelatedExistingDuplicatesAreUntouched() throws {
        try entry("ukeeper2020a")
        try entry("udoomed2020a")
        try entry("bystander2020a")
        var v = Venue(key: "untouched-journal", type: .periodical)
        v.names = TimelineOf([TemporalValue(value: "U", range: DateRange())])
        v.references = [
            // 與 merge 無關的既有重複 ×2（bystander 的 verdict）
            verdict("resolution-confirmed", holder: "bystander2020a", literal: "U Journal"),
            verdict("resolution-confirmed", holder: "bystander2020a", literal: "U Journal"),
            // 本次要遷移的
            verdict("resolution-confirmed", holder: "udoomed2020a", literal: "U Journal"),
        ]
        try store.writeVenue(v)
        let d = try mergeDivergence(keeper: "ukeeper2020a", doomed: "udoomed2020a")

        GitFixture.commitAll(store.root)
        _ = try store.resolveDivergence(id: d.id, survivor: "ukeeper2020a")

        let after = try store.load().venues.first { $0.key == "untouched-journal" }
        let vals = after?.references.compactMap(\.value) ?? []
        XCTAssertEqual(vals.filter { $0.contains("bystander2020a") }.count, 2,
                       "與遷移無關的既有重複必須原樣保留（消歧不是清理工具）：\(vals)")
        XCTAssertEqual(vals.filter { $0.contains("ukeeper2020a") }.count, 1,
                       "遷移目標正常改寫")
    }

    // MARK: - helper 層（純函數，直接餵 refs——不經 store）

    private func ref(_ holder: String, _ literal: String = "L",
                     field: String = "resolution-confirmed",
                     statement: String = "測試用判定") -> ProvenanceReference {
        verdict(field, holder: holder, literal: literal, statement: statement)
    }

    /// 落在**觸及鍵**上的 keeper 既有重複會一併收攏——這是刻意的（helper doc 有記
    /// 先例與理由），不是「無關重複一筆不動」的例外漏洞。#461 verify R1 六席都指出
    /// 舊措辭涵蓋不到這格；本測試把真正的語意釘住：`[K, K, D] → 1`，且兩筆丟棄
    /// 都進 `collapsed`。
    func testTouchedKeyCollapsesKeeperPreexistingDuplicatesDeliberately() {
        let out = LibraryStore.migrateWorkHolderVerdicts(
            [ref("keeper2020a", statement: "k1"), ref("keeper2020a", statement: "k2"),
             ref("doomed2020a", statement: "d")],
            merged: ["doomed2020a"], survivor: "keeper2020a")
        XCTAssertTrue(out.changed)
        XCTAssertEqual(out.refs.count, 1, "同鍵的 keeper 既有重複一併收攏（刻意）：\(out.refs)")
        XCTAssertEqual(statement(out.refs.first), "k1", "留首見")
        XCTAssertEqual(out.collapsed.count, 2)
        XCTAssertTrue(out.collapsed.allSatisfy { $0.contains("work:keeper2020a :: L") }, "\(out.collapsed)")
    }

    /// **政策在 #468 從「首見」換成三層裁決**，本測試跟著換（它的舊名字
    /// `testDoomedFirstKeepsDoomedStatementAndReportsTheDrop` 已不描述行為）。
    ///
    /// 這一組兩筆血統相同（都沒有 rule 尾註 ⇒ 依族補完全命中預設），所以由第 2 層決定：
    /// **原本就指向 survivor 的那一筆勝**，與 #271 的 keeper 恆勝一致。關鍵是**兩種排列
    /// 得到同一個結果**——舊政策下 doomed-first 與 keeper-first 會留下不同的判定原文，
    /// 而那正是 #468 說的「不該由陣列順序代勞」。
    func testKeeperSideWinsOnLineageTieRegardlessOfOrder() {
        for (desc, refs) in [
            ("doomed 在前", [ref("doomed2020a", statement: "doomed 側"),
                             ref("keeper2020a", statement: "keeper 側")]),
            ("keeper 在前", [ref("keeper2020a", statement: "keeper 側"),
                             ref("doomed2020a", statement: "doomed 側")]),
        ] {
            let out = LibraryStore.migrateWorkHolderVerdicts(
                refs, merged: ["doomed2020a"], survivor: "keeper2020a")
            XCTAssertEqual(out.refs.count, 1, desc)
            XCTAssertEqual(statement(out.refs.first), "keeper 側",
                           "\(desc)：血統平手 → 未被改寫的那一筆勝（#468 第 2 層）")
            XCTAssertEqual(out.collapsed,
                           ["resolution-confirmed work:keeper2020a :: L——丟棄 判定「doomed 側」"],
                           desc)
        }
    }

    /// 冪等：第二次跑同一組 merged／survivor 是 no-op——refs 逐字相同、`changed`
    /// 為 false、零丟棄（否則呼叫端會空寫檔並假報 `verdictValuesRewritten`）。
    func testSecondRunIsANoOp() {
        let first = LibraryStore.migrateWorkHolderVerdicts(
            [ref("doomed2020a"), ref("keeper2020a")], merged: ["doomed2020a"], survivor: "keeper2020a")
        XCTAssertTrue(first.changed)
        let second = LibraryStore.migrateWorkHolderVerdicts(
            first.refs, merged: ["doomed2020a"], survivor: "keeper2020a")
        XCTAssertFalse(second.changed)
        XCTAssertEqual(second.refs, first.refs)
        XCTAssertTrue(second.collapsed.isEmpty)
    }

    /// 指向 survivor 的 verdict 永不算「本次觸及」——即使呼叫端把 survivor 放進
    /// `merged`（生產呼叫端不會，#463 複用時也不必各自防）。否則觸及集合退化成
    /// 全量 dedup（被否決的方案 (a)）、`changed` 恆真造成空寫（Codex R1 H-1）。
    func testSurvivorHoldersAreNeverTreatedAsMigrated() {
        let out = LibraryStore.migrateWorkHolderVerdicts(
            [ref("keeper2020a", "A", statement: "a1"), ref("keeper2020a", "A", statement: "a2"),
             ref("doomed2020a", "B")],
            merged: ["keeper2020a", "doomed2020a"], survivor: "keeper2020a")
        XCTAssertTrue(out.changed)
        XCTAssertEqual(out.refs.filter { $0.value?.hasSuffix(" :: A") == true }.count, 2,
                       "survivor 自己的既有重複不在觸及集合內，原樣保留：\(out.refs)")
        XCTAssertEqual(out.refs.filter { $0.value == "work:keeper2020a :: B" }.count, 1)
        XCTAssertTrue(out.collapsed.isEmpty)

        let onlySurvivor = LibraryStore.migrateWorkHolderVerdicts(
            [ref("keeper2020a", "A"), ref("keeper2020a", "A")],
            merged: ["keeper2020a"], survivor: "keeper2020a")
        XCTAssertFalse(onlySurvivor.changed, "沒有真正的遷移對象＝不寫檔")
        XCTAssertEqual(onlySurvivor.refs.count, 2)
    }
}
