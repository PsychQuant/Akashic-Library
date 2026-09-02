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
        // **斷言兩支訊息都有的那部分**。先前這裡寫 `contains("venue")`（小寫），而
        // #414 R1 把訊息分成有／無 booktitle 兩支之後，無 booktitle 那支只有
        // 大寫的 `Venue`——測試因此在一個**與它要測的性質無關**的字上紅。
        // 要測的性質是「有沒有出聲」，所以錨在兩支共有的抬頭。
        XCTAssertTrue(msgs.contains { $0.contains("editor") && $0.contains("booktitle 載體列舉") },
                      "booktitle 載體型別帶 editor 必須出聲：\(msgs)")
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
    /// **訊息不得斷言一個對該筆為假的後果**（自審抓到，#414 R1）。
    ///
    /// 守衛的前件是**型別層**的（#324 的 §11 判準問的是「這個型別決定哪些欄位存在」），
    /// 所以它對一筆**沒有 `booktitle`** 的成員記錄照樣出聲——那是對的，因為型別成員資格
    /// 本身就是被問的東西。
    ///
    /// 但原本的訊息一律說「venue 持不住編者」，而那句話描述的是 `booktitle → venue`
    /// **推導的後果**——對一筆沒有 booktitle 的記錄，那個推導**沒有發生**，於是訊息
    /// 斷言了一件對該筆為假的事。
    ///
    /// 實測（2026-08-23）這不是假想：37 筆 `conference-session` **零筆帶 booktitle**，
    /// 而 17 筆 `reference-work-entry` **全部帶**。也就是說本表的兩個成員在這一點上
    /// 剛好落在光譜兩端，而先前的訊息只對其中一端為真。
    func testMessageDoesNotClaimADerivationThatDidNotHappen() {
        var withBT = Entry(id: UUID(), citekey: "a2025", type: .conferenceSession, title: "T")
        withBT.fields["editor"] = "Someone"
        withBT.fields["booktitle"] = "Proceedings of X"
        let m1 = try! XCTUnwrap(withBT.validate().first { $0.message.contains("editor") }).message
        XCTAssertTrue(m1.contains("持不住"),
                      "有 booktitle 時推導確實發生，訊息該說出後果：\(m1)")

        var noBT = Entry(id: UUID(), citekey: "b2025", type: .conferenceSession, title: "T")
        noBT.fields["editor"] = "Someone"
        let m2 = try! XCTUnwrap(noBT.validate().first { $0.message.contains("editor") }).message
        XCTAssertFalse(m2.contains("持不住"),
                       "沒有 booktitle 時那個推導沒發生——訊息不得斷言它的後果：\(m2)")
        XCTAssertTrue(m2.contains("型別"),
                      "沒有 booktitle 時要說出這是型別層的問題：\(m2)")
    }

    func testNonCarrierTypeWithEditorIsNotFlagged() {
        var e = Entry(id: UUID(), citekey: "x2025", type: .bookChapter, title: "T")
        e.fields["editor"] = "Someone"
        XCTAssertFalse(e.validate().map(\.message).contains { $0.contains("venue 持不住") },
                       "bookChapter 不在 booktitleCarrierTypes 內，帶編者是正常的")
    }
}

// MARK: - #422／#406：variant 分割與 paginated 判定

extension VenueTests {

    /// `variant` round-trip，且**不與 `authorized` 混淆**。
    func testVariantRoundTrips() throws {
        var v = Venue(key: "plos-one", type: .periodical,
                      names: TimelineOf([TemporalValue(value: "PLOS ONE"),
                                         TemporalValue(value: "PLoS One")]))
        v.authorized = ["PLOS ONE"]
        v.variant = ["PLoS One"]
        let back = try VenueYAML.decode(try VenueYAML.encode(v))
        XCTAssertEqual(back.authorized, ["PLOS ONE"])
        XCTAssertEqual(back.variant, ["PLoS One"])
    }

    /// **交集是 error**——一個名字不能既權威又是它自己的異寫。
    ///
    /// 這不是「資料不完整」是**自相矛盾**：讀取面對同一個字串會得到兩個相反的答案。
    func testAuthorizedAndVariantMustNotOverlap() {
        var v = Venue(key: "x", type: .periodical,
                      names: TimelineOf([TemporalValue(value: "A")]))
        v.authorized = ["A"]
        v.variant = ["A"]
        let errs = v.validate().filter { $0.severity == .error }
        XCTAssertTrue(errs.contains { $0.message.contains("兩個分割") },
                      "應該報交集：\(v.validate().map(\.message))")
    }

    /// 分割互斥與 person 共用同一份守衛（`AuthorizedNames.validateDisjointPartitions`，
    /// `NameIdentity`）：只差前後空白的近重複**不得**穿透（#296；#422 verify R1 指出
    /// 第一版在 venue 上用精確 `String ==` 重造了較弱的副本）。
    func testNearDuplicateAcrossPartitionsIsCaught() {
        var v = Venue(key: "x", type: .periodical,
                      names: TimelineOf([TemporalValue(value: "A"), TemporalValue(value: "A ")]))
        v.authorized = ["A"]
        v.variant = ["A "]
        XCTAssertTrue(v.validate().contains { $0.severity == .error && $0.message.contains("兩個分割") },
                      "只差空白的名字分居兩個分割要被抓：\(v.validate().map(\.message))")
    }

    /// 大小寫**不**摺疊——WoS 全大寫 vs 正常大小寫正是 variant 要裝的東西（實測 32 筆），
    /// 摺疊會把整批遷移結果誤報成交集。
    func testCaseVariantsAreNotTreatedAsOverlap() {
        var v = Venue(key: "plos-one", type: .periodical,
                      names: TimelineOf([TemporalValue(value: "PLOS ONE"), TemporalValue(value: "PLoS One")]))
        v.authorized = ["PLOS ONE"]
        v.variant = ["PLoS One"]
        XCTAssertFalse(v.validate().contains { $0.severity == .error },
                       "大小寫異寫不是交集：\(v.validate().map(\.message))")
    }

    /// **未分類是合法狀態**（spec 第 13 行）：多筆不帶時間的名字、`authorized` 與 `variant`
    /// 都空——那是「還沒人判定」的誠實狀態，不是錯誤。#422 verify 把三筆記錄退回這個
    /// 狀態，本測試釘住它不會被任何守衛誤擋（Codex R2 建議）。
    func testUnclassifiedMultiNameVenueIsLegal() {
        let v = Venue(key: "wikipedia", type: .website,
                      names: TimelineOf([TemporalValue(value: "Wikipedia"), TemporalValue(value: "維基百科")]))
        XCTAssertTrue(v.authorized.isEmpty && v.variant.isEmpty)
        XCTAssertFalse(v.validate().contains { $0.severity == .error },
                       "未分類不是錯誤：\(v.validate().map(\.message))")
    }

    /// **variant 不得帶時間欄位**（spec Scenario「A variant carrying a date fails validation」）。
    /// #422 verify R1：第一版零實作——遷移的整筆跳過只保證遷移自己不造出這種記錄。
    func testVariantCarryingADateFailsValidation() {
        var v = Venue(key: "x", type: .periodical,
                      names: TimelineOf([TemporalValue(value: "A"),
                                         TemporalValue(value: "B", range: DateRange(start: "2003"))]))
        v.authorized = ["A"]
        v.variant = ["B"]
        let errs = v.validate().filter { $0.severity == .error }
        XCTAssertTrue(errs.contains { $0.message.contains("帶時間欄位") },
                      "帶 start 的 variant 必須 fail：\(v.validate().map(\.message))")
        // 同一筆不列 variant，就是合法的沿革——守衛只針對「既是異寫又有期間」的矛盾。
        v.variant = []
        XCTAssertFalse(v.validate().contains { $0.severity == .error },
                       "不列 variant 的帶時間名字是沿革，不該報錯：\(v.validate().map(\.message))")
    }

    /// `paginated` 的三態 round-trip——**`nil` 不得折成 `false`**。
    ///
    /// 「未判定」與「判定為不使用頁碼」是兩件事：前者是 APA7 下限**仍該報缺**的狀態，
    /// 後者才是「這筆沒有頁碼是正確的」。折成 `false` 會讓所有未查的刊靜默通過。
    func testPaginatedRoundTripsAllThreeStates() throws {
        for state: Bool? in [nil, true, false] {
            var v = Venue(key: "j", type: .periodical,
                          names: TimelineOf([TemporalValue(value: "J")]))
            v.paginated = state
            let back = try VenueYAML.decode(try VenueYAML.encode(v))
            XCTAssertEqual(back.paginated, state, "三態必須逐一區分，失敗於 \(String(describing: state))")
        }
    }

    /// **`nil` 不寫進 YAML**——缺席即未判定。
    func testUnjudgedPaginatedIsAbsentFromYAML() throws {
        let v = Venue(key: "j", type: .periodical,
                      names: TimelineOf([TemporalValue(value: "J")]))
        XCTAssertFalse(try VenueYAML.encode(v).contains("paginated"),
                       "未判定不該在 YAML 裡留痕跡——那會讓缺席與 false 難以區分")
    }

    /// `paginated` 只收 `true`／`false`，其餘**整檔拒讀**。
    func testPaginatedRejectsAnythingElse() throws {
        let yaml = """
        venue:
        id: 01945230-81CD-4144-8E31-5BE5B8C13328
        key: j
        type: periodical
        names:
        - value: J
        paginated: maybe
        """
        XCTAssertThrowsError(try VenueYAML.decode(yaml),
                             "只接受 true／false——`maybe` 必須整檔拒讀，不猜")
    }

    /// variant 的名字必須在 `names` 裡——分割是**對 names 的標記**，不是獨立清單。
    func testVariantMustReferToAKnownName() {
        var v = Venue(key: "x", type: .periodical,
                      names: TimelineOf([TemporalValue(value: "A")]))
        v.variant = ["B"]
        XCTAssertTrue(v.validate().contains { $0.message.contains("不在 names 裡") },
                      "孤兒 variant 要出聲：\(v.validate().map(\.message))")
    }
}
