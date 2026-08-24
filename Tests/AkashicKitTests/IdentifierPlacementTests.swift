import XCTest
@testable import AkashicCore

/// 交付 spec requirement「An identifier SHALL live on the entity it identifies」（#394 task 3.1）。
///
/// ISSN 識別的是**期刊**不是文章，ROR 識別的是**機構**——它們必須住在被它識別的那個
/// 記錄的頂層具名欄位上。實測動機：64 筆 work 帶著 `issn`，只因為 venue 沒有地方放它。
///
/// **為什麼放記錄頂層**：`docs/store-format.md` 的 tolerant-preserve 開放演化層只涵蓋
/// 記錄頂層與 `akashic` namespace；時間軸段內與 `references` 元素內是 strict 層，舊
/// binary 讀到未知鍵是整檔 quarantine。放頂層因此是 additive、不需要 format bump
/// （本 change 的 bump 觸發點是 §6 的 provenance 白名單，不是這裡）。
final class IdentifierPlacementTests: XCTestCase {

    private var repoRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // AkashicKitTests
            .deletingLastPathComponent()   // Tests
            .deletingLastPathComponent()   // repo root
    }

    /// 反射取一個型別的儲存屬性名集合。
    private func fieldNames<T>(of value: T) -> Set<String> {
        Set(Mirror(reflecting: value).children.compactMap(\.label))
    }

    // MARK: - 欄位存在

    func testVenueCarriesITSOwnISSN() {
        let venue = Venue(key: "psychometrika", type: .periodical)
        XCTAssertTrue(fieldNames(of: venue).contains("issn"),
                      "ISSN 識別期刊，必須是 Venue 的頂層欄位——它現在住在 work 的 fields 裡是放錯實體")
    }

    func testVenueISSNIsAListBecausePrintAndElectronicAreTwoRealNumbers() {
        // 基數逐種決定：實測 Behavior Research Methods 的 1554-351X（print）與
        // 1554-3528（electronic）是**兩個真的號**，一律純量會丟掉一個（違反 lossless-intake）。
        var venue = Venue(key: "behavior-research-methods", type: .periodical)
        guard let print = ISSN("1554-351X"), let electronic = ISSN("1554-3528") else {
            return XCTFail("兩個都是合法 ISSN")
        }
        venue.issn = [print, electronic]
        XCTAssertEqual(venue.issn.count, 2, "print 與 electronic 都要留住，不得擇一")
    }

    func testOrganizationCarriesROR() {
        let org = Organization(key: "academia-sinica")
        XCTAssertTrue(fieldNames(of: org).contains("ror"),
                      "ROR 識別機構，必須是 Organization 的頂層欄位")
    }

    func testOrganizationRORIsScalarBecauseOneRecordPerOrganization() {
        // ROR 在定義上每機構一個。基數不是風格選擇：它決定 provenance 走哪條驗證分支
        // ——純量欄位的 reference 不得帶 value，清單欄位必須帶。宣告錯邊會落到錯的分支。
        // 值取自 IdentifierTests 已驗證的那個（check digit 對），不另行發明——
        // 發明的識別碼多半 check digit 不合法，而那會讓測試在與本 task 無關的地方變紅。
        var org = Organization(key: "academia-sinica")
        org.ror = ROR("https://ror.org/05bqach95")
        XCTAssertEqual(org.ror?.normalized, "05bqach95")
        XCTAssertTrue(fieldNames(of: org).contains("ror"))
    }

    // MARK: - doc 列舉不得與實際欄位分岔

    /// `Venue` 的型別 doc 用**逐一列舉全部欄位**來論證「編著裝不下」（§9.28 為什麼不入
    /// `VenueType`）。那個列舉是規格的第二份副本——加一個欄位而不同步改它，論證就在
    /// 讀者看不出來的地方變成假的。本測試讓那次分岔擋在 CI 而不是擋在某個人重讀它時。
    ///
    /// 它查的是**一致性**，不是**論證仍然成立**：加一個裝不下編者的欄位不會推翻結論，
    /// 但加一個裝得下的會——而那一步永遠是人工裁決，本測試不提供任何證據。
    func testVenueDocFieldEnumerationMatchesTheActualFields() throws {
        let source = try String(contentsOf: repoRoot
            .appendingPathComponent("Sources/AkashicCore/Venue.swift"), encoding: .utf8)

        // doc 裡的列舉形如 `id / key / type / …`（反引號包住、斜線分隔）。
        let pattern = #"`([a-zA-Z]+(?:\s*/\s*[a-zA-Z]+)+)`"#
        let regex = try NSRegularExpression(pattern: pattern)
        let matches = regex.matches(in: source, range: NSRange(source.startIndex..., in: source))

        let enumerations: [Set<String>] = matches.compactMap { m in
            guard let r = Range(m.range(at: 1), in: source) else { return nil }
            let parts = source[r].components(separatedBy: "/")
                .map { $0.trimmingCharacters(in: .whitespaces) }
            return parts.contains("id") ? Set(parts) : nil
        }

        let documented = try XCTUnwrap(enumerations.first,
            "在 Venue.swift 找不到以 `id` 開頭的反引號欄位列舉——doc 的形狀改了，請一併更新本測試的 locator")

        let actual = fieldNames(of: Venue(key: "x", type: .periodical))

        XCTAssertEqual(documented, actual,
            """
            Venue 的 doc 欄位列舉與實際欄位分岔了。
              doc 有而型別沒有: \(documented.subtracting(actual).sorted())
              型別有而 doc 沒有: \(actual.subtracting(documented).sorted())
            那段列舉在論證「一本編著的編者／書名／版次／出版社一個都裝不下」，
            列錯就是拿一份過期的欄位表去支撐一個現在的結論。
            """)
    }
}
