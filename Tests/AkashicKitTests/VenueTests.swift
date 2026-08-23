import XCTest
import Foundation
@testable import AkashicCore

/// venue 作為第五種記錄形狀（#304 裁決：期刊＋會議＋出版社一次到位）。
///
/// 沿革（裁決五b）直接重用 `TimelineOf<String>`——org 的 names 已是時間軸，
/// venue 跟隨同一模式，刊名改名史免費獲得。
final class VenueTests: XCTestCase {

    // MARK: - 型別與 validate（task 1.1）

    /// 值域細分 APA7 §9.23–9.33 的 source 類型學（#324）。
    ///
    /// **六值，不是七值**：APA7 的第七類「edited book / reference work」（§9.28）
    /// 不在此——一本編著有編者、書名、版次，`Venue` 一個欄位都裝不下，它是 **work**
    /// 而非 venue（其 publisher 才是 venue）。詳見 #324 的更正 comment。
    func testVenueTypeRefinesAPA7SourceTaxonomy() {
        XCTAssertEqual(VenueType.allCases.map(\.rawValue).sorted(),
                       ["conference", "database", "periodical",
                        "publisher", "socialMedia", "website"])
    }

    /// `journal` 已更名為 `periodical`——APA7 的 periodical 涵蓋 journal／magazine／
    /// newspaper／newsletter／blog，它們索取同一組欄位，是同一類。舊名不得復活。
    func testJournalRawValueIsGone() {
        XCTAssertNil(VenueType(rawValue: "journal"),
                     "`journal` 是 #324 更名前的舊值，不該再被接受")
    }

    func testNewVenueGetsRandomV4ID() {
        // #241 doctrine：id 是單一來源事件的 v4，不由名字推導。
        // 同 key 兩次建構必須得到不同 id——決定性推導正是被廢除的行為。
        let a = Venue(key: "jcgs", type: .periodical)
        let b = Venue(key: "jcgs", type: .periodical)
        XCTAssertNotEqual(a.id, b.id)
    }

    func testValidateRejectsBadKey() {
        let v = Venue(key: "Bad Key!", type: .periodical)
        XCTAssertTrue(v.validate().contains { $0.severity == .error })
    }

    func testNameTimelineSegments() throws {
        // 改名史：舊刊名帶 end、現刊名帶 start——兩者並存，現行名可推導。
        var v = Venue(key: "jcgs", type: .periodical)
        v.names = Timeline([
            TemporalValue(value: "Old Journal Title", range: DateRange(end: "2003")),
            TemporalValue(value: "Journal of Computational and Graphical Statistics",
                          range: DateRange(start: "2003")),
        ])
        XCTAssertEqual(v.names.current?.value,
                       "Journal of Computational and Graphical Statistics")
        XCTAssertEqual(v.names.entries.count, 2)
    }

    func testDisplayNamePrefersAuthorized() {
        var v = Venue(key: "jcgs", type: .periodical)
        v.names = Timeline([TemporalValue(value: "JCGS")])
        v.authorized = ["Journal of Computational and Graphical Statistics"]
        XCTAssertEqual(v.displayName,
                       "Journal of Computational and Graphical Statistics")
    }

    // MARK: - YAML round-trip（task 1.2）

    func testVenueRoundTripsCanonically() throws {
        var v = Venue(key: "journal-of-computational-and-graphical-statistics",
                      type: .periodical)
        v.names = Timeline([
            TemporalValue(value: "Journal of Computational and Graphical Statistics"),
            TemporalValue(value: "JCGS"),
        ])
        v.authorized = ["Journal of Computational and Graphical Statistics"]
        v.note = "測試"
        let text = try VenueYAML.encode(v)
        XCTAssertTrue(text.hasPrefix("venue:"), "形狀裸標籤必須最前")
        let back = try VenueYAML.decode(text)
        XCTAssertEqual(back, v)
        // canonical：encode(decode(x)) == x
        XCTAssertEqual(try VenueYAML.encode(back), text)
    }

    func testUnknownTypeRejected() throws {
        let yaml = """
        venue:
        id: \(UUID().uuidString)
        key: some-series
        type: series
        """
        XCTAssertThrowsError(try VenueYAML.decode(yaml)) { err in
            // 斷言訊息**含當前值域**，而非寫死某個值——#324 改值域時發現三處訊息
            // 各自寫死舊值域，值域改了訊息還在報舊值。現在訊息從 `allCases` 生成，
            // 測試也跟著從 `allCases` 取期望值，兩者不會再分岔。
            let msg = String(describing: err)
            XCTAssertTrue(msg.contains(VenueType.domainDescription),
                          "錯誤訊息必須點名當前封閉列舉，實得：\(err)")
            for c in VenueType.allCases {
                XCTAssertTrue(msg.contains(c.rawValue),
                              "訊息漏了值 \(c.rawValue)：\(err)")
            }
        }
    }

    func testMissingTypeRejected() throws {
        let yaml = """
        venue:
        id: \(UUID().uuidString)
        key: no-type
        """
        XCTAssertThrowsError(try VenueYAML.decode(yaml))
    }

    func testEntityKindPeeksVenue() throws {
        let yaml = """
        venue:
        id: \(UUID().uuidString)
        key: jcgs
        type: journal
        """
        XCTAssertEqual(try EntityKind.peek(yaml), .venue)
    }

    func testUnknownFieldsTolerantPreserved() throws {
        var v = Venue(key: "jcgs", type: .periodical)
        v.names = Timeline([TemporalValue(value: "JCGS")])
        var text = try VenueYAML.encode(v)
        text += "future_field: hello\n"
        let back = try VenueYAML.decode(text)
        XCTAssertEqual(back.unknownFields.map(\.key), ["future_field"])
        // 寫回時原樣保留
        XCTAssertTrue(try VenueYAML.encode(back).contains("future_field: hello"))
    }

    // MARK: - Entry.venues 二態 ref（task 1.3）

    func testEntryVenuesRoundTrip() throws {
        var e = Entry(id: UUID(), citekey: "cheng2025universal", type: .periodicalArticle, title: "T")
        e.venues = [.literal("JOURNAL OF STATISTICS"), .key("jcgs")]
        let text = try EntryYAML.encode(e)
        let back = try EntryYAML.decode(text)
        XCTAssertEqual(back.venues, e.venues)
        // 順序帶語意——不得重排
        XCTAssertEqual(back.venues.first, .literal("JOURNAL OF STATISTICS"))
    }

    func testEntryVenuesRejectsUnknownElementKey() throws {
        var e = Entry(id: UUID(), citekey: "x2025", type: .periodicalArticle, title: "T")
        e.venues = [.key("jcgs")]
        var text = try EntryYAML.encode(e)
        text = text.replacingOccurrences(of: "- key: jcgs", with: "- name: jcgs")
        XCTAssertThrowsError(try EntryYAML.decode(text))
    }

    func testEntryWithoutVenuesUnchanged() throws {
        // 既有 entry（無 venues 鍵）round-trip 零 diff——additive 契約。
        let e = Entry(id: UUID(), citekey: "old2020", type: .periodicalArticle, title: "Old")
        let text = try EntryYAML.encode(e)
        XCTAssertFalse(text.contains("venues"))
        XCTAssertEqual(try EntryYAML.decode(text).venues, [])
    }

    // MARK: - booktitleCarrierTypes 的成員資格有沒有程式層對應物（#414）

    /// `booktitleCarrierTypes` 的判準（#324 的 §11：「它決定了哪些欄位存在」）先前
    /// **只存在於 doc comment**：集合是人工列舉，成員資格只看 `entry.type`，既不檢查
    /// 記錄實際擁有的欄位，也沒有任何東西會在判準被違反時出聲。
    ///
    /// 跨模型審查（2026-08-23）指出的正是這個：「不得依性質相似類推第三個」這條禁令
    /// **沒有可機械執行的判準程序**——下一個線上百科／辭典型別仍只能靠人判斷「像不像」。
    ///
    /// 本條把 #324 排除編著的那個**結構性**理由變成對成員的可執行約束：`Venue` 沒有
    /// 編者欄位（實測其欄位是 id/key/type/names/authorized/note/references/unknownFields），
    /// 所以一個帶 `editor` 的型別進了這張表，它的編者資訊在 venue 側**無處可放**。
    ///
    /// **這是必要條件不是充分條件**（同 `apa7-is-the-work-floor` 對 113 例的立場）：
    /// 一個新型別即使不帶 `editor` 也未必該進表。守衛擋掉的是**已知會錯**的那一類，
    /// 不保證通過的都對。
    func testCarrierTypeCarryingAnEditorIsFlagged() {
        var e = Entry(id: UUID(), citekey: "x2025", type: .conferenceSession, title: "T")
        e.fields["editor"] = "Someone"
        let msgs = e.validate().map(\.message)
        XCTAssertTrue(msgs.contains { $0.contains("editor") && $0.contains("venue") },
                      "booktitle 載體型別帶 editor 必須出聲——venue 持不住編者：\(msgs)")
    }

    /// **前件不得寫成「editor 或 publisher」**——那會誤傷一個有正當路徑的欄位。
    ///
    /// 實測（2026-08-23，全 corpus）：帶 `publisher` 的有 82 筆、跨 4 個型別，而
    /// `VenueType` 本身就有 `.publisher` 這個值，`VenueDerivation.literals` 的第三個
    /// 分支**無條件**把 publisher 變成另一個 venue literal。所以出版社不是「持不住」，
    /// 是「它自己就是一個 venue」。
    ///
    /// doc comment 先前把「沒有同義的出版社」列為納入 `.referenceWorkEntry` 的理由之一
    /// ——那句話被本量測否掉，已一併改寫（#414）。
    func testCarrierTypeCarryingAPublisherIsNotFlagged() {
        var e = Entry(id: UUID(), citekey: "x2025", type: .conferenceSession, title: "T")
        e.fields["publisher"] = "Springer"
        XCTAssertFalse(e.validate().map(\.message).contains { $0.contains("venue 持不住") },
                       "publisher 有自己的 venue 路徑（VenueType.publisher），不得當成違規")
    }

    /// **不在表裡的型別不受此約束**。編著章節本來就該有編者——#324 排除它的理由正是
    /// 「它有編者而 venue 持不住」，所以對它報警等於把排除的結論倒過來用。
    func testNonCarrierTypeWithEditorIsNotFlagged() {
        var e = Entry(id: UUID(), citekey: "x2025", type: .bookChapter, title: "T")
        e.fields["editor"] = "Someone"
        XCTAssertFalse(e.validate().map(\.message).contains { $0.contains("venue 持不住") },
                       "bookChapter 不在 booktitleCarrierTypes 內，帶編者是正常的")
    }
}
