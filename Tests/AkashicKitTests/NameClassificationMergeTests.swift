import XCTest
import Foundation
@testable import AkashicCore
@testable import AkashicStoreIO

/// #564（Spectra change `name-classification-judgement`）：venue 合併分得出人判定過的 authorized——
/// spec `divergence-record`「A venue merge SHALL NOT demote an authorized name that carries a name-classification record」。
///
/// - 被併者帶名字分類記錄的 authorized 會被降級：preview 與實跑都拒絕（`wouldDemoteJudgedAuthorized`），零寫入。
/// - 機械值（沒有記錄）：照舊合併、提醒。
/// - 其餘名字分類記錄：名字在合併後的倖存者上分類與被併者相同才逐位元組搬（`referencesCarried`），不同就以 `wouldLoseFields` 拒絕。
final class NameClassificationMergeTests: XCTestCase {
    var root: URL!
    var store: LibraryStore!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("akashic-ncm-\(UUID().uuidString)")
        try FileManager.default.createDirectory(
            at: root.appendingPathComponent("entities"), withIntermediateDirectories: true)
        try StoreVersion.write(root: root, format: StoreVersion.supported)
        GitFixture.initRepo(root)
        store = LibraryStore(root: root)
    }
    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: root) }

    private func record(_ field: String, _ name: String, _ action: NameClassificationRecord.Action, _ reason: String) -> ProvenanceReference {
        NameClassificationRecord.make(field: field, name: name, action: action, reason: reason, restsOn: [])
    }
    private func venue(_ key: String, names: [String], authorized: [String] = [], variant: [String] = [],
                       refs: [ProvenanceReference] = []) -> Venue {
        var v = Venue(key: key, type: .periodical, names: Timeline(names.map { TemporalValue(value: $0) }), authorized: authorized)
        v.variant = variant
        v.references = refs
        return v
    }
    @discardableResult
    private func seed(keeper: Venue, doomed: [Venue]) throws -> Divergence {
        try store.writeVenue(keeper)
        for d in doomed { try store.writeVenue(d) }
        let d = Divergence(id: UUID(), question: "同一本刊嗎",
                           candidates: ([keeper] + doomed).map { DivergenceCandidate(key: $0.key, shape: .venue) })
        try store.writeDivergence(d)
        GitFixture.commitAll(root, message: "seed")
        return d
    }
    private func message(_ e: Error) -> String { (e as? LocalizedError)?.errorDescription ?? "\(e)" }

    /// spec「A judged authorized name would be demoted」：preview 拒絕並說出名字與最後一筆記錄；實跑同樣拒絕、零寫入。
    func testJudgedAuthorizedDemotionIsRefusedInPreviewAndApply() throws {
        let keeper = venue("k", names: ["Keeper Journal"], authorized: ["Keeper Journal"])
        let doomed = venue("d", names: ["Doomed Journal"], authorized: ["Doomed Journal"],
                           refs: [record("authorized", "Doomed Journal", .designate, "官網刊頭")])
        let d = try seed(keeper: keeper, doomed: [doomed])
        XCTAssertThrowsError(try store.previewResolveDivergence(id: d.id, survivor: "k", overrideReason: nil)) { e in
            guard case DivergenceResolveError.wouldDemoteJudgedAuthorized = e else { return XCTFail("\(e)") }
            let m = message(e)
            XCTAssertTrue(m.contains("Doomed Journal") && m.contains("指定：官網刊頭"), m)
            XCTAssertTrue(m.contains("--unauthorize") && m.contains("--authorize") && m.contains("--judgement"), "出路要寫出來：\(m)")
        }
        XCTAssertThrowsError(try store.resolveDivergence(id: d.id, survivor: "k"))
        XCTAssertEqual(Set(try store.load().venues.map(\.key)), ["k", "d"], "零寫入")
    }

    /// 判準是「有任何記錄」：最後一筆是撤回卻仍在 authorized（只可能是手改）也拒。
    func testAnyRecordOnTheDemotedNameRefuses() throws {
        let keeper = venue("k", names: ["Keeper Journal"], authorized: ["Keeper Journal"])
        let doomed = venue("d", names: ["Doomed Journal"], authorized: ["Doomed Journal"],
                           refs: [record("authorized", "Doomed Journal", .withdraw, "手改")])
        let d = try seed(keeper: keeper, doomed: [doomed])
        XCTAssertThrowsError(try store.previewResolveDivergence(id: d.id, survivor: "k", overrideReason: nil)) { e in
            guard case DivergenceResolveError.wouldDemoteJudgedAuthorized = e else { return XCTFail("\(e)") }
        }
    }

    /// spec「A mechanical authorized name would be demoted」：沒有記錄的降級照舊合併、提醒。
    func testMechanicalDemotionStillMergesWithAWarning() throws {
        let keeper = venue("k", names: ["Keeper Journal"], authorized: ["Keeper Journal"])
        let doomed = venue("d", names: ["Doomed Journal"], authorized: ["Doomed Journal"])
        let d = try seed(keeper: keeper, doomed: [doomed])
        let report = try store.resolveDivergence(id: d.id, survivor: "k")
        XCTAssertFalse(report.hasFailures, report.failures.joined(separator: "\n"))
        XCTAssertTrue(report.warnings.contains { $0.contains("Doomed Journal") && $0.contains("authorized") }, "\(report.warnings)")
        XCTAssertEqual(Set(try store.load().venues.map(\.key)), ["k"])
    }

    /// 兩邊都指定同一個名字：沒有降級，記錄隨合併逐位元組搬到倖存者。
    func testRecordOnANameBothSidesAuthorizeIsCarried() throws {
        let rec = record("authorized", "Psychometrika", .designate, "官網刊頭")
        let keeper = venue("k", names: ["Psychometrika"], authorized: ["Psychometrika"])
        let doomed = venue("d", names: ["Psychometrika", "PSYCHOMETRIKA"], authorized: ["Psychometrika"], refs: [rec])
        let d = try seed(keeper: keeper, doomed: [doomed])
        let preview = try store.previewResolveDivergence(id: d.id, survivor: "k", overrideReason: nil)
        XCTAssertEqual(preview.referencesCarried.count, 1, "\(preview.referencesCarried)")
        let report = try store.resolveDivergence(id: d.id, survivor: "k")
        XCTAssertFalse(report.hasFailures, report.failures.joined(separator: "\n"))
        XCTAssertEqual(report.referencesCarried, preview.referencesCarried)
        let k = try XCTUnwrap(store.load().venues.first { $0.key == "k" })
        XCTAssertEqual(k.references.map(\.byteExactKey), [rec.byteExactKey])
    }

    /// spec「A withdrawal record whose classification agrees is carried」：被併者上已撤回（未標）的名字，合併後在倖存者上也是未標——搬。
    func testWithdrawalRecordWithAgreeingClassificationIsCarried() throws {
        let designated = record("authorized", "Old Title", .designate, "舊刊頭")
        let withdrawn = record("authorized", "Old Title", .withdraw, "刊名已改")
        let keeper = venue("k", names: ["Keeper Journal"], authorized: ["Keeper Journal"])
        let doomed = venue("d", names: ["Doomed Journal", "Old Title"], refs: [designated, withdrawn])
        let d = try seed(keeper: keeper, doomed: [doomed])
        let report = try store.resolveDivergence(id: d.id, survivor: "k")
        XCTAssertFalse(report.hasFailures, report.failures.joined(separator: "\n"))
        let k = try XCTUnwrap(store.load().venues.first { $0.key == "k" })
        XCTAssertEqual(k.references.map(\.byteExactKey), [designated.byteExactKey, withdrawn.byteExactKey], "逐位元組、順序不變")
        XCTAssertFalse(k.authorized.contains("Old Title"))
        XCTAssertTrue(k.names.entries.contains { $0.value == "Old Title" })
        XCTAssertNoThrow(try k.validateReferenceAttachment())
    }

    /// variant 的記錄：名字隨合併被標 variant（被併者原本就在 variant）——分類一致，搬。
    func testVariantRecordFollowsTheVariantIntoTheKeeper() throws {
        let rec = record("variant", "DOOMED J", .designate, "縮寫")
        let keeper = venue("k", names: ["Keeper Journal"], authorized: ["Keeper Journal"])
        let doomed = venue("d", names: ["Doomed Journal", "DOOMED J"], variant: ["DOOMED J"], refs: [rec])
        let d = try seed(keeper: keeper, doomed: [doomed])
        let report = try store.resolveDivergence(id: d.id, survivor: "k")
        XCTAssertFalse(report.hasFailures, report.failures.joined(separator: "\n"))
        let k = try XCTUnwrap(store.load().venues.first { $0.key == "k" })
        XCTAssertTrue(k.variant.contains("DOOMED J"))
        XCTAssertEqual(k.references.map(\.byteExactKey), [rec.byteExactKey])
    }

    /// 分類不一致：被併者說「它是異寫」，倖存者已有這個名字而且未標——搬過去會說一句倖存者的分類不承認的話，以 wouldLoseFields 拒絕，
    /// 訊息說出名字與兩邊的分類。
    func testDisagreeingClassificationRefusesTheMerge() throws {
        let rec = record("variant", "Shared Name", .designate, "被併者認為是異寫")
        let keeper = venue("k", names: ["Keeper Journal", "Shared Name"], authorized: ["Keeper Journal"])
        let doomed = venue("d", names: ["Doomed Journal", "Shared Name"], variant: ["Shared Name"], refs: [rec])
        let d = try seed(keeper: keeper, doomed: [doomed])
        XCTAssertThrowsError(try store.previewResolveDivergence(id: d.id, survivor: "k", overrideReason: nil)) { e in
            guard case DivergenceResolveError.wouldLoseFields = e else { return XCTFail("\(e)") }
            let m = message(e)
            XCTAssertTrue(m.contains("名字分類的判定記錄") && m.contains("Shared Name") && m.contains("variant") && m.contains("未標"), m)
            XCTAssertFalse(m.contains("references（"), "不要再被當成一般 reference 說一次：\(m)")
        }
        XCTAssertEqual(Set(try store.load().venues.map(\.key)), ["k", "d"], "零寫入")
    }

    /// #564 R1 verify（Codex，b26 F2 第 1 列）：兩邊各持一筆位元組相同的「variant 指定：R」，倖存者之後把那個名字抬進 authorized 再撤回
    /// （現在是未標）——被併者仍說它是異寫。分類不一致要拒絕；先前位元組去重排在分類檢查之前，倖存者「已經有」那一筆就放行，
    /// 被併者的 variant 分類被合併安靜地拿掉。
    func testByteIdenticalRecordWithDisagreeingClassificationStillRefuses() throws {
        let shared = record("variant", "Shared Name", .designate, "R")
        let keeper = venue("k", names: ["Keeper Journal", "Shared Name"], authorized: ["Keeper Journal"], refs: [
            shared,
            record("variant", "Shared Name", .withdraw, "改指定為 authorized——R2"),
            record("authorized", "Shared Name", .designate, "R2"),
            record("authorized", "Shared Name", .withdraw, "R3"),
        ])
        let doomed = venue("d", names: ["Doomed Journal", "Shared Name"], variant: ["Shared Name"], refs: [shared])
        let d = try seed(keeper: keeper, doomed: [doomed])
        XCTAssertThrowsError(try store.previewResolveDivergence(id: d.id, survivor: "k", overrideReason: nil)) { e in
            guard case DivergenceResolveError.wouldLoseFields = e else { return XCTFail("\(e)") }
            let m = message(e)
            XCTAssertTrue(m.contains("名字分類的判定記錄") && m.contains("Shared Name") && m.contains("variant") && m.contains("未標"), m)
        }
        XCTAssertThrowsError(try store.resolveDivergence(id: d.id, survivor: "k"))
        XCTAssertEqual(Set(try store.load().venues.map(\.key)), ["k", "d"], "零寫入")
    }

    /// person 合併：被併者有、倖存者沒有的 authorized 仍拒絕（#81）；名字分類記錄在分類不一致時另說一行、指出口。
    func testPersonMergeKeepsItsOwnRefusals() {
        let rec = record("authorized", "Doomed, Person", .designate, "本人署名")
        var doomed = Person(key: "d-person", names: PersonNames(authorized: ["Doomed, Person"], variant: []))
        doomed.references = [rec]
        let keeper = Person(key: "k-person", names: PersonNames(authorized: ["Keeper, Person"], variant: []))
        let losses = LibraryStore.fieldsLostByMerging(doomed, into: keeper)
        XCTAssertTrue(losses.contains { $0.hasPrefix("authorized:") && $0.contains("Doomed, Person") }, "\(losses)")
        XCTAssertTrue(losses.contains { $0.hasPrefix("名字分類的判定記錄") && $0.contains("update-person") }, "\(losses)")

        var sameKeeper = Person(key: "k2-person", names: PersonNames(authorized: ["Doomed, Person"], variant: []))
        sameKeeper.references = [rec]
        XCTAssertTrue(LibraryStore.fieldsLostByMerging(doomed, into: sameKeeper).isEmpty,
                      "倖存者有位元組相同的記錄、也指定同一個名字：沒有東西會失去")
    }

    private func person(_ key: String, authorized: [String], variant: [String] = [], refs: [ProvenanceReference] = []) -> Person {
        var p = Person(key: key, names: PersonNames(authorized: authorized, variant: variant))
        p.references = refs
        return p
    }
    @discardableResult
    private func seedPeople(keeper: Person, doomed: [Person]) throws -> Divergence {
        _ = try store.writePerson(keeper)
        for p in doomed { _ = try store.writePerson(p) }
        let d = Divergence(id: UUID(), question: "同一個人嗎",
                           candidates: ([keeper] + doomed).map { DivergenceCandidate(key: $0.key, shape: .person) })
        try store.writeDivergence(d)
        GitFixture.commitAll(root, message: "seed")
        return d
    }

    /// #564 修正輪（使用者 2026-10-02 裁決第 3 點；b26 F2 第 8 列）：兩筆攣生在不同批次各跑一次 authorize-names（理由不同）——
    /// 同一個名字兩邊都是對外形，分類一致：被併者的記錄逐位元組搬到倖存者，合併照做；preview 與實跑說同一份 `referencesCarried`。
    func testPersonTwinRecordsWithAgreeingClassificationAreCarried() throws {
        let theirs = record("authorized", "Twin, Name", .designate, "第二批")
        let keeper = person("twin-a", authorized: ["Twin, Name"], refs: [record("authorized", "Twin, Name", .designate, "第一批")])
        let doomed = person("twin-b", authorized: ["Twin, Name"], refs: [theirs])
        let d = try seedPeople(keeper: keeper, doomed: [doomed])
        let preview = try store.previewResolveDivergence(id: d.id, survivor: "twin-a", overrideReason: nil)
        XCTAssertEqual(preview.referencesCarried.count, 1, "\(preview.referencesCarried)")
        let report = try store.resolveDivergence(id: d.id, survivor: "twin-a")
        XCTAssertFalse(report.hasFailures, report.failures.joined(separator: "\n"))
        XCTAssertEqual(report.referencesCarried, preview.referencesCarried)
        let kept = try XCTUnwrap(store.load().people.first { $0.key == "twin-a" })
        XCTAssertTrue(kept.references.contains { $0.byteExactKey == theirs.byteExactKey }, "逐位元組搬到倖存者")
        XCTAssertEqual(Set(try store.load().people.map(\.key)), ["twin-a"])
    }

    /// 分類不一致（被併者撤回了、倖存者仍以它對外）：拒絕，訊息說出名字、兩邊的分類與出口。
    func testPersonTwinRecordsWithDisagreeingClassificationRefuse() throws {
        let keeper = person("twin-a", authorized: ["Twin, Name"])
        let doomed = person("twin-b", authorized: [], variant: ["Twin, Name"], refs: [
            record("authorized", "Twin, Name", .designate, "批次"), record("authorized", "Twin, Name", .withdraw, "不是他"),
        ])
        let d = try seedPeople(keeper: keeper, doomed: [doomed])
        XCTAssertThrowsError(try store.previewResolveDivergence(id: d.id, survivor: "twin-a", overrideReason: nil)) { e in
            guard case DivergenceResolveError.wouldLoseFields = e else { return XCTFail("\(e)") }
            let m = message(e)
            XCTAssertTrue(m.contains("Twin, Name") && m.contains("不是對外形") && m.contains("authorized") && m.contains("--judgement"), m)
        }
        XCTAssertEqual(Set(try store.load().people.map(\.key)), ["twin-a", "twin-b"], "零寫入")
    }

    // MARK: - #564 R2 verify（b29 V1 第 0／2／3／6／12／26 列）：搬記錄按位置接、尾端與分類一致、錨定、預覽說出動作

    private func classificationRecords(_ refs: [ProvenanceReference], name: String) -> [String] {
        refs.filter { NameClassificationRecord.isRecord($0) && $0.value == name }.compactMap { r in
            guard case .judgement(let statement, _) = r.kind else { return nil }
            return r.field + " " + statement
        }
    }

    /// 被併者「指定 R → 撤回 S → 指定 R」併進已有「指定 R」的倖存者：第三筆不能因為與倖存者的第一筆位元組相同而被丟——
    /// 先前（整份歷史位元組去重）只搬「撤回 S」，倖存者的名字仍是對外形、最後一筆卻是撤回。預覽與實跑同一份，且預覽說出動作。
    func testPersonCarryKeepsTheFinalDesignationThatRepeatsAnEarlierOne() throws {
        let r = record("authorized", "Zhang, Wei", .designate, "R")
        let keeper = person("zw-keep", authorized: ["Zhang, Wei"], refs: [r])
        let doomed = person("zw-doom", authorized: ["Zhang, Wei"],
                            refs: [r, record("authorized", "Zhang, Wei", .withdraw, "S"), record("authorized", "Zhang, Wei", .designate, "R")])
        let d = try seedPeople(keeper: keeper, doomed: [doomed])
        let preview = try store.previewResolveDivergence(id: d.id, survivor: "zw-keep", overrideReason: nil)
        XCTAssertEqual(preview.referencesCarried.count, 2, "\(preview.referencesCarried)")
        XCTAssertTrue(preview.referencesCarried[0].contains("撤回：S") && preview.referencesCarried[1].contains("指定：R"),
                      "預覽要說出動作與順序：\(preview.referencesCarried)")
        let report = try store.resolveDivergence(id: d.id, survivor: "zw-keep")
        XCTAssertFalse(report.hasFailures, report.failures.joined(separator: "\n"))
        XCTAssertEqual(report.referencesCarried, preview.referencesCarried)
        let kept = try XCTUnwrap(store.load().people.first { $0.key == "zw-keep" })
        XCTAssertEqual(classificationRecords(kept.references, name: "Zhang, Wei"),
                       ["authorized 指定：R", "authorized 撤回：S", "authorized 指定：R"])
        XCTAssertEqual(NameClassificationRecord.latestAction(in: kept.references, name: "Zhang, Wei"), .designate)
        XCTAssertTrue(LibraryStore.personTailConflicts(kept).isEmpty)
    }

    /// Codex 的情境：兩邊都是「指定 R → 撤回（理由不同）→ 指定 R」——合併後最後一筆仍是指定。
    func testPersonCarryOfTwoRedesignationHistoriesEndsInDesignation() throws {
        let r = record("authorized", "Zhang, Wei", .designate, "R")
        let keeper = person("zw-keep", authorized: ["Zhang, Wei"], refs: [r, record("authorized", "Zhang, Wei", .withdraw, "S"), r])
        let doomed = person("zw-doom", authorized: ["Zhang, Wei"], refs: [r, record("authorized", "Zhang, Wei", .withdraw, "T"), r])
        let d = try seedPeople(keeper: keeper, doomed: [doomed])
        _ = try store.previewResolveDivergence(id: d.id, survivor: "zw-keep", overrideReason: nil)
        let report = try store.resolveDivergence(id: d.id, survivor: "zw-keep")
        XCTAssertFalse(report.hasFailures, report.failures.joined(separator: "\n"))
        let kept = try XCTUnwrap(store.load().people.first { $0.key == "zw-keep" })
        XCTAssertEqual(classificationRecords(kept.references, name: "Zhang, Wei"),
                       ["authorized 指定：R", "authorized 撤回：S", "authorized 指定：R", "authorized 撤回：T", "authorized 指定：R"])
        XCTAssertEqual(NameClassificationRecord.latestAction(in: kept.references, name: "Zhang, Wei"), .designate)
    }

    /// 兩邊都已撤回（現在是 variant）、被併者的撤回與倖存者較早的撤回位元組相同：先前被去重丟掉、只搬「指定 Q」，最後一筆變成指定，
    /// 之後 `--remove-name` 以「最後一筆不是撤回」拒絕而出口做不到（名字根本不在 authorized）。現在最後一筆是撤回。
    func testPersonCarryKeepsTheFinalWithdrawalThatRepeatsAnEarlierOne() throws {
        let keeper = person("ac-keep", authorized: ["Chen, A."], variant: ["Chen, Alice"], refs: [
            record("authorized", "Chen, Alice", .designate, "R"), record("authorized", "Chen, Alice", .withdraw, "S")])
        let doomed = person("ac-doom", authorized: [], variant: ["Chen, Alice"], refs: [
            record("authorized", "Chen, Alice", .designate, "Q"), record("authorized", "Chen, Alice", .withdraw, "S")])
        let d = try seedPeople(keeper: keeper, doomed: [doomed])
        let preview = try store.previewResolveDivergence(id: d.id, survivor: "ac-keep", overrideReason: nil)
        XCTAssertEqual(preview.referencesCarried.count, 2, "\(preview.referencesCarried)")
        _ = try store.resolveDivergence(id: d.id, survivor: "ac-keep")
        let kept = try XCTUnwrap(store.load().people.first { $0.key == "ac-keep" })
        XCTAssertEqual(classificationRecords(kept.references, name: "Chen, Alice"),
                       ["authorized 指定：R", "authorized 撤回：S", "authorized 指定：Q", "authorized 撤回：S"])
        XCTAssertEqual(NameClassificationRecord.latestAction(in: kept.references, name: "Chen, Alice"), .withdraw)
    }

    /// venue 同形：倖存者「指定 R」← 被併者「指定 R → 撤回 S → 指定 R」——倖存者以指定結尾。
    func testVenueCarryKeepsTheFinalDesignationThatRepeatsAnEarlierOne() throws {
        let r = record("authorized", "Journal A", .designate, "R")
        let keeper = venue("k", names: ["Journal A"], authorized: ["Journal A"], refs: [r])
        let doomed = venue("d", names: ["Journal A"], authorized: ["Journal A"],
                           refs: [r, record("authorized", "Journal A", .withdraw, "S"), record("authorized", "Journal A", .designate, "R")])
        let d = try seed(keeper: keeper, doomed: [doomed])
        let preview = try store.previewResolveDivergence(id: d.id, survivor: "k", overrideReason: nil)
        let report = try store.resolveDivergence(id: d.id, survivor: "k")
        XCTAssertFalse(report.hasFailures, report.failures.joined(separator: "\n"))
        XCTAssertEqual(report.referencesCarried, preview.referencesCarried)
        let k = try XCTUnwrap(store.load().venues.first { $0.key == "k" })
        XCTAssertEqual(classificationRecords(k.references, name: "Journal A"),
                       ["authorized 指定：R", "authorized 撤回：S", "authorized 指定：R"])
        XCTAssertTrue(LibraryStore.venueTailConflicts(k).isEmpty)
    }

    /// 被併者自己的記錄就與分類不一致（手改，或修正輪之前的 binary：「指定 R → 撤回 S → 指定 R」的第三筆被當時的去重丟掉）——合併接過去
    /// 會讓倖存者以撤回結尾而名字仍是對外形。preview 與實跑都拒絕、零寫入，訊息說出名字、分割、最後一筆與出口。
    func testCarryThatWouldLeaveAContradictoryTailIsRefused() throws {
        let r = record("authorized", "Zhang, Wei", .designate, "R")
        let keeper = person("zw-keep", authorized: ["Zhang, Wei"], refs: [r])
        let doomed = person("zw-doom", authorized: ["Zhang, Wei"], refs: [r, record("authorized", "Zhang, Wei", .withdraw, "S")])
        let d = try seedPeople(keeper: keeper, doomed: [doomed])
        let attempts: [() throws -> Void] = [{ _ = try self.store.previewResolveDivergence(id: d.id, survivor: "zw-keep", overrideReason: nil) },
                                             { _ = try self.store.resolveDivergence(id: d.id, survivor: "zw-keep") }]
        for attempt in attempts {
            XCTAssertThrowsError(try attempt()) { e in
                guard case DivergenceResolveError.wouldContradictClassificationTail = e else { return XCTFail("\(e)") }
                let m = message(e)
                XCTAssertTrue(m.contains("Zhang, Wei") && m.contains("撤回") && m.contains("仍在 authorized") && m.contains("--judgement"), m)
            }
        }
        XCTAssertEqual(Set(try store.load().people.map(\.key)), ["zw-keep", "zw-doom"], "零寫入")

        let vk = venue("vk", names: ["Journal A"], authorized: ["Journal A"])
        let vd = venue("vd", names: ["Journal A"], authorized: ["Journal A"],
                       refs: [record("authorized", "Journal A", .designate, "R"), record("authorized", "Journal A", .withdraw, "S")])
        let vdiv = try seed(keeper: vk, doomed: [vd])
        XCTAssertThrowsError(try store.previewResolveDivergence(id: vdiv.id, survivor: "vk", overrideReason: nil)) { e in
            guard case DivergenceResolveError.wouldContradictClassificationTail = e else { return XCTFail("\(e)") }
        }
        XCTAssertThrowsError(try store.resolveDivergence(id: vdiv.id, survivor: "vk"))
        XCTAssertEqual(Set(try store.load().venues.map(\.key)), ["vk", "vd"], "零寫入")
    }

    /// 倖存者自己原本就以撤回結尾而名字仍是對外形（合併前的既有狀態）：不歸咎這次合併（delta），照舊合併。
    func testExistingContradictoryTailOnTheSurvivorDoesNotBlock() throws {
        let keeper = person("zw-keep", authorized: ["Zhang, Wei"], refs: [
            record("authorized", "Zhang, Wei", .designate, "R"), record("authorized", "Zhang, Wei", .withdraw, "S")])
        let doomed = person("zw-doom", authorized: ["Zhang, Wei"])
        let d = try seedPeople(keeper: keeper, doomed: [doomed])
        let report = try store.resolveDivergence(id: d.id, survivor: "zw-keep")
        XCTAssertFalse(report.hasFailures, report.failures.joined(separator: "\n"))
    }

    /// 被併者的名字與倖存者的只差空白（canonical 相等、拼法不同）：合併不併入這個拼法，它的記錄搬過去是孤兒。先前 dry-run 說「搬 2 筆」、
    /// 實跑在寫入閘以「value 不是這筆記錄的名字」拒絕——乾跑與實跑不一致。現在兩者都以 wouldLoseFields 拒絕並指出口、零寫入。
    func testPersonRecordOnAWhitespaceTwinSpellingRefusesInPreviewAndApply() throws {
        let keeper = person("fb-keep", authorized: ["Foo Bar"], refs: [record("authorized", "Foo Bar", .designate, "R")])
        let doomed = person("fb-doom", authorized: [], variant: ["Foo  Bar"], refs: [
            record("authorized", "Foo  Bar", .designate, "R"), record("authorized", "Foo  Bar", .withdraw, "S")])
        let d = try seedPeople(keeper: keeper, doomed: [doomed])
        let attempts: [() throws -> Void] = [{ _ = try self.store.previewResolveDivergence(id: d.id, survivor: "fb-keep", overrideReason: nil) },
                                             { _ = try self.store.resolveDivergence(id: d.id, survivor: "fb-keep") }]
        for attempt in attempts {
            XCTAssertThrowsError(try attempt()) { e in
                guard case DivergenceResolveError.wouldLoseFields = e else { return XCTFail("\(e)") }
                let m = message(e)
                XCTAssertTrue(m.contains("只差空白") && m.contains("--remove-name") && m.contains("孤兒"), m)
                XCTAssertFalse(m.contains("分類不同"), "分類並沒有不同：\(m)")
            }
        }
        XCTAssertEqual(Set(try store.load().people.map(\.key)), ["fb-keep", "fb-doom"], "零寫入")
    }

    /// 兩邊的對外形只差空白：分類的相等看 canonical——記錄的拒絕理由不是「被併者 authorized→倖存者不是對外形」。
    func testPersonClassificationComparesAuthorizedCanonically() {
        let doomed = person("lm-doom", authorized: ["Li  Ming"], refs: [record("authorized", "Li  Ming", .designate, "R")])
        let keeper = person("lm-keep", authorized: ["Li Ming"])
        let losses = LibraryStore.fieldsLostByMerging(doomed, into: keeper)
        XCTAssertFalse(losses.contains { $0.contains("不是對外形") }, "\(losses)")
        XCTAssertTrue(losses.contains { $0.contains("只差空白") }, "\(losses)")
    }
}
