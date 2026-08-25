import XCTest
@testable import AkashicCore
@testable import AkashicMCPKit

/// `Venue` 的每個序列化欄位都必須出現在讀取面，不得只存在型別與磁碟上（#394 verify）。
///
/// ## 這道守衛防的是什麼
///
/// §8 的遷移把 **39 個 venue** 的 ISSN 寫進磁碟，而 `akashic venue` 與它的 `--json`
/// 都沒有那一格——於是「庫裡有這個號」與「查不到這個號」在使用者眼中**完全一樣**。
/// 同一輪還漏了 `references`（第 13 條邊的 resolution verdict），而 person 那面早就有。
///
/// 兩個都不是有人寫錯，是**沒有任何東西在問「型別有的，讀取面給了嗎」**。
///
/// ## 為什麼用反射而非人工清單
///
/// 與 `StoreHealthSurfaceTests` 同一個理由：人工清單會與型別分岔，而那正是
/// `entity-backlink-completeness` 的封閉列舉錯過三次的形狀。反射問的是型別自己。
///
/// ## 誠實邊界
///
/// 它查的是**服務端有沒有讀那個欄位**，不是「渲染得對不對」。一個把 `issn` 讀出來
/// 卻印成空字串的實作仍會通過——那需要端到端斷言，而本檔上方的 CLI／JSON 實測
/// （#394 verify）扮演那個角色。這是必要條件不是充分條件，寫出來免得它被讀成後者。
final class VenueSurfaceTests: XCTestCase {

    static func serviceSource() throws -> String {
        try String(contentsOf: URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Sources/AkashicMCPKit/AkashicService.swift"),
            encoding: .utf8)
    }

    /// 取一個函式的**完整** body，用括號配對而非固定長度。
    ///
    /// **先前是 `.prefix(4500)`**，而那個魔術數字在同一輪內就失效了：加上 verdicts
    /// 投影之後 `record.unknownFields` 掉出視窗，守衛開始報一個不存在的缺口。
    /// 假紅比漏報更貴——維護者會學會「這支有時候會紅」，那個習慣會套用到所有守衛
    /// （`zero-instance-guards` 第 6 列）。
    static func functionBody(of signature: String, in source: String) -> String? {
        guard let sig = source.range(of: signature) else { return nil }
        var depth = 0
        var i = source.index(before: sig.upperBound)     // 指向簽章結尾的 `{`
        let start = i
        while i < source.endIndex {
            if source[i] == "{" { depth += 1 }
            else if source[i] == "}" {
                depth -= 1
                if depth == 0 { return String(source[start...i]) }
            }
            i = source.index(after: i)
        }
        return nil                                        // 括號不平衡
    }

    /// 用一個真實的 `Venue` 值取欄位名——不寫死清單。
    private func venueFieldNames() -> [String] {
        Mirror(reflecting: Venue(key: "k", type: .periodical)).children.compactMap(\.label)
    }

    /// **不得為零**：反射拿不到東西時，下面那條會 vacuous pass。
    func testReflectionActuallySeesFields() {
        XCTAssertGreaterThanOrEqual(venueFieldNames().count, 8,
                                    "反射應看到 Venue 的全部欄位，實得 \(venueFieldNames())")
    }

    /// **守衛的守衛**：括號配對必須真的停在該函式結尾，不是吃到檔尾。
    ///
    /// 吃過頭的話，別的函式偶然提到 `record.<field>` 就會讓本檔 vacuous pass——
    /// 而那正是它要防的失敗形狀，只是換到自己身上。
    func testExtractedBodyStopsAtTheFunctionEnd() throws {
        let source = try Self.serviceSource()
        guard let body = Self.functionBody(
            of: "public func venue(key rawKey: String) throws -> String {", in: source)
        else { return XCTFail("找不到 venue(key:)") }
        XCTAssertFalse(body.contains("public func venues()"),
                       "body 吃到了下一個函式——括號配對壞了")
        XCTAssertTrue(body.contains("record.issn"), "body 應涵蓋整個函式")
        XCTAssertLessThan(body.count, source.count / 2, "body 不該是大半個檔案")
    }

    /// 每個欄位都必須被 `venue(key:)` 讀到——或落在具名的豁免集合裡。
    func testEveryFieldReachesTheReadSurface() throws {
        // **封閉豁免，附理由**（`common-spec-prose-enumeration`：能列舉的就列舉）。
        // 加一項就是加一列理由，不得依性質相似類推。
        let exempt: [String: String] = [
            "id": "內部 UUID 身分，任何 entity 的讀取面都不輸出它（person／organization 同）",
        ]
        let source = try Self.serviceSource()
        guard let body = Self.functionBody(
            of: "public func venue(key rawKey: String) throws -> String {", in: source)
        else { return XCTFail("找不到 venue(key:) —— 本測試的前提不成立") }

        for field in venueFieldNames() {
            if let why = exempt[field] {
                XCTAssertFalse(why.isEmpty, "豁免必須附理由")
                continue
            }
            XCTAssertTrue(body.contains("record.\(field)"),
                          "Venue.\(field) 沒有被 venue(key:) 讀到——"
                          + "它會存在磁碟上而使用者兩個面都看不到，"
                          + "而那與『庫裡沒有這個值』在輸出上完全一樣")
        }
    }
}
