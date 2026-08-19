import XCTest
@testable import AkashicCore

/// 「被收錄於」這條邊**暫不新增**的裁決，以及它的觸發條件（#339）。
///
/// `entity-backlink-completeness` 的「考慮過但暫不新增的邊」一節記著這個裁決。那一節
/// 要求**每一列都附一個可檢查的觸發條件**——否則「暫時」會變成「永遠」而沒有人知道。
///
/// 本組把那個要求變成機械的：裁決的**前提**若不再成立，測試會紅。
///
/// ## 為什麼守的是前提而不是結論
///
/// 結論（「不新增這條邊」）沒有東西可斷言——不存在的邊測不出來。可斷言的是**當初據以
/// 裁決的事實**：`fields.booktitle` 沒有升格成 ref、而 `booktitle` 仍是自由字串。
///
/// 這與 `#315` 的 `testStoreDirectoryForMembershipIsStillNamedLibraries` 同形：那條也是
/// 釘住一個**分析的前提**（store 的目錄叫 `libraries/`），而不是分析的結論。
final class ContainerRelationDeferralTests: XCTestCase {

    /// **前提一**：`booktitle` 仍是 `fields` 裡的自由字串，不是 ref。
    ///
    /// 若哪天它升格成二態 ref，`Entry` 會長出一個對應的具型別成員，而這條會紅
    /// ——那時該做的是**把那條邊寫進封閉列舉表**並刪掉「暫不新增」的那一列。
    func testBooktitleIsStillAScalarFieldNotARef() {
        var e = Entry(id: UUID(), citekey: "x2020", type: .bookChapter, title: "T")
        e.fields["booktitle"] = "Handbook of modern item response theory"
        XCTAssertEqual(e.fields["booktitle"], "Handbook of modern item response theory",
                       "booktitle 目前是自由字串。升格成 ref 時本測試該被刪掉，"
                       + "而不是改成通過——同時要更新 entity-backlink-completeness 的封閉列舉")
    }

    /// **前提二**：`Entry` 沒有容器 ref 成員。
    ///
    /// 用反射列出 `Entry` 的儲存屬性名，斷言其中沒有容器語意的欄位。這比「檢查某個具名
    /// 欄位不存在」強：它抓得到**任何名字**的容器欄位被加進來。
    func testEntryHasNoContainerRefMember() {
        let e = Entry(id: UUID(), citekey: "x2020", type: .bookChapter, title: "T")
        let names = Mirror(reflecting: e).children.compactMap(\.label)
        let containerish = names.filter {
            let n = $0.lowercased()
            return n.contains("container") || n.contains("collection")
                || n.contains("parentwork") || n.contains("containedin")
        }
        XCTAssertTrue(containerish.isEmpty,
                      "Entry 長出了容器語意的成員：\(containerish)。"
                      + "若那是刻意新增的邊，請更新 entity-backlink-completeness 的封閉列舉"
                      + "並刪掉「考慮過但暫不新增」那一節的 #339 列")
    }

    /// **前提三**：`VenueType` 沒有 edited book 之類的值。
    ///
    /// #324 明確裁定不得把 edited book 塞進 `VenueType`（那會製造一個結構上無法持有
    /// APA7 要求欄位的 venue）。#339 的裁決建立在那條路已被關掉之上——若它被打開，
    /// 本裁決的第三個理由就失效了。
    func testVenueTypeHasNoEditedBookValue() {
        let forbidden = ["editedbook", "book", "collection", "anthology"]
        for type in VenueType.allCases {
            XCTAssertFalse(forbidden.contains(type.rawValue.lowercased()),
                           "VenueType 長出了 \(type.rawValue)——#324 裁定 edited book 不得"
                           + "進入這個值域，而 #339 的裁決建立在那條路已被關掉之上")
        }
    }
}
