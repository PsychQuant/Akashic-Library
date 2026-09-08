import XCTest
@testable import AkashicCore
@testable import AkashicMCPKit
@testable import AkashicStoreIO

/// `paginated` 判定的撤回路與翻轉語意（#500，裁決＝候選 1）。
///
/// 兩個原本**寫不出來**的東西：
///
/// - **(b) 撤回**：舊規則要求「記錄的 paginated 非 nil」，所以「退回 nil 但保留判定史」
///   在驗證層就寫不出來——要嘛丟掉全部 reference（違反留史），要嘛改規則。
/// - **(c) 翻轉語意**：value 恆 nil 時資料層看不出哪句理由對應哪個值；同 statement 翻回時
///   `(field, value, kind)` 冪等會吞掉新翻轉。
final class PaginatedWithdrawalTests: XCTestCase {

    /// 封閉三值——`nil` 是**撤回**不是「沒有值」。
    func testOnlyTheThreeValuesAreAccepted() throws {
        for v in ["true", "false", "nil"] {
            var venue = Venue(key: "j", type: .periodical,
                              names: TimelineOf([TemporalValue(value: "J")]))
            venue.references = [try ProvenanceReference(
                field: "paginated", value: v, url: nil, retrieved: nil, status: nil,
                mediaType: nil, content: nil, judgement: "理由",
                restsOn: ["sha256:" + String(repeating: "a", count: 64)])]
            XCTAssertNoThrow(try venue.validateReferenceAttachment(), "value=\(v)")
        }
        var venue = Venue(key: "j", type: .periodical,
                          names: TimelineOf([TemporalValue(value: "J")]))
        venue.references = [try ProvenanceReference(
            field: "paginated", value: "maybe", url: nil, retrieved: nil, status: nil,
            mediaType: nil, content: nil, judgement: "理由",
            restsOn: ["sha256:" + String(repeating: "a", count: 64)])]
        XCTAssertThrowsError(try venue.validateReferenceAttachment())
    }

    /// **撤回之後記錄的欄位是 nil 而判定史留著**——舊規則正是這一格寫不出來的原因。
    func testWithdrawnRecordKeepsItsJudgementHistory() throws {
        var venue = Venue(key: "j", type: .periodical,
                          names: TimelineOf([TemporalValue(value: "J")]))
        XCTAssertNil(venue.paginated)
        venue.references = [try ProvenanceReference(
            field: "paginated", value: "nil", url: nil, retrieved: nil, status: nil,
            mediaType: nil, content: nil, judgement: "證據不足，撤回",
            restsOn: ["sha256:" + String(repeating: "b", count: 64)])]
        XCTAssertNoThrow(try venue.validateReferenceAttachment(),
                         "paginated=nil 且有判定 reference 必須合法——那正是撤回的形狀")
    }

    /// **舊筆（value 缺席）放行**——退場量測寫在 doc 裡；33 筆 live 記錄不得因此拒讀。
    func testLegacyReferencesWithoutValueStillLoad() throws {
        var venue = Venue(key: "j", type: .periodical,
                          names: TimelineOf([TemporalValue(value: "J")]))
        venue.paginated = true
        venue.references = [try ProvenanceReference(
            field: "paginated", value: nil, url: nil, retrieved: nil, status: nil,
            mediaType: nil, content: nil, judgement: "舊筆",
            restsOn: ["sha256:" + String(repeating: "c", count: 64)])]
        XCTAssertNoThrow(try venue.validateReferenceAttachment())
    }

    /// **翻轉的每一筆各自帶值，冪等比對因此分得開**——(c) 的核心。
    /// 同一句理由翻回去時，`(field, value, kind)` 不同，所以新翻轉不會被吞掉。
    func testFlipsWithTheSameStatementAreNotSwallowed() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("akashic-pg-\(UUID().uuidString)")
        try FileManager.default.createDirectory(
            at: root.appendingPathComponent("entities"), withIntermediateDirectories: true)
        try StoreVersion.write(root: root, format: StoreVersion.supported)
        defer { try? FileManager.default.removeItem(at: root) }
        let service = AkashicService(root: root)
        _ = try service.addVenue(key: "j", names: ["J"], type: "periodical", note: nil, issn: nil)
        let digest = "sha256:" + String(repeating: "d", count: 64)
        // 同一句 statement，值一來一回——三筆都要在
        for p in [true, false, true] {
            _ = try service.updateVenue(key: "j", addNames: nil, note: nil, type: nil,
                                        paginated: p, judgement: "同一句理由", restsOn: [digest])
        }
        let v = try XCTUnwrap(LibraryStore(root: root).load().venues.first { $0.key == "j" })
        let vals = v.references.filter { $0.field == "paginated" }.compactMap(\.value)
        XCTAssertEqual(vals, ["true", "false"],
                       "第三筆與第一筆完整相等（同 field／value／kind）所以冪等吞掉；"
                       + "第二筆的 value 不同所以留著——這正是 (c) 要的分得開：\(vals)")
    }

    /// `paginated` 與 `clear_paginated` 不得同時給——一次呼叫只能說一件事。
    func testSettingAndClearingAtOnceIsRefused() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("akashic-pg2-\(UUID().uuidString)")
        try FileManager.default.createDirectory(
            at: root.appendingPathComponent("entities"), withIntermediateDirectories: true)
        try StoreVersion.write(root: root, format: StoreVersion.supported)
        defer { try? FileManager.default.removeItem(at: root) }
        let service = AkashicService(root: root)
        _ = try service.addVenue(key: "j", names: ["J"], type: "periodical", note: nil, issn: nil)
        XCTAssertThrowsError(try service.updateVenue(
            key: "j", addNames: nil, note: nil, type: nil,
            paginated: true, clearPaginated: true, judgement: "x",
            restsOn: ["sha256:" + String(repeating: "e", count: 64)]))
    }

    /// 撤回也要理由——撤回本身是判定，沒有理由的撤回事後與「不知道為什麼撤回」無法區分。
    func testWithdrawalRequiresAJudgement() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("akashic-pg3-\(UUID().uuidString)")
        try FileManager.default.createDirectory(
            at: root.appendingPathComponent("entities"), withIntermediateDirectories: true)
        try StoreVersion.write(root: root, format: StoreVersion.supported)
        defer { try? FileManager.default.removeItem(at: root) }
        let service = AkashicService(root: root)
        _ = try service.addVenue(key: "j", names: ["J"], type: "periodical", note: nil, issn: nil)
        XCTAssertThrowsError(try service.updateVenue(
            key: "j", addNames: nil, note: nil, type: nil, clearPaginated: true))
    }
}
