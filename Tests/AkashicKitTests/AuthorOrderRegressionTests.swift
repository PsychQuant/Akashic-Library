import XCTest
import Foundation
@testable import AkashicCore

/// #69 的哨兵：**作者順序不得被正規化碰到**。
///
/// 作者的位置即語意——第一作者、通訊作者、貢獻排序都靠它。任何排序都是資料破壞，
/// 而不是「整理」。這個測試不驗證新功能，它守著一條**不該被跨過的線**：任何把排序
/// 誤加到 `authors` 的改動都會讓它變紅。
///
/// 同樣的紀律適用於 `attachments`（順序也帶語意），但那層目前沒有排序的誘因，
/// 所以先只釘 `authors`。
final class AuthorOrderRegressionTests: XCTestCase {

    /// requirement **Order-bearing sequences SHALL be excluded from reordering**。
    ///
    /// 作者名刻意**非字母序**且**非時間序**——若有人加了任何排序，這個順序必然改變。
    func testAuthorOrderSurvivesNormalization() throws {
        let authored: [Author] = [
            .literal("Zelterman, Daniel"),
            .literal("Chen, Chan-Fu"),
            .key("aaa-first-alphabetically"),
            .literal("Møller, Jesper"),
        ]
        var e = Entry(id: UUID(), citekey: "zelterman1988homogeneity", type: "article",
                      title: "Homogeneity Tests against Central-Mixture Alternatives",
                      authors: authored, date: "1988")
        e.fields["journaltitle"] = "JASA"

        let yaml = try EntryYAML.encode(e)

        // **斷言檔案裡的順序**，不只是 round-trip。
        //
        // round-trip 相等這個性質已由 encode canary 守著（實測注入排序時，紅的是 canary
        // 而不是本測試）。但 canary 比的是 `decode(encode(x)) == x`——若有人讓 encode
        // 與 decode **一致地**排序，round-trip 仍然成立而檔案裡的順序已經錯了。
        // 作者順序的價值在檔案本身（別人 clone 下來讀到的東西），所以斷言要下在那裡。
        let inFile = yaml.components(separatedBy: "\n")
            .drop { $0.trimmingCharacters(in: .whitespaces) != "authors:" }
            .dropFirst()
            .prefix { $0.hasPrefix("- ") }
            .map { $0.replacingOccurrences(of: "- literal: ", with: "")
                     .replacingOccurrences(of: "- key: ", with: "")
                     .trimmingCharacters(in: CharacterSet(charactersIn: " '\"")) }
        XCTAssertEqual(Array(inFile),
                       ["Zelterman, Daniel", "Chen, Chan-Fu",
                        "aaa-first-alphabetically", "Møller, Jesper"],
                       "檔案裡的作者順序必須與寫入順序完全相同：\n\(yaml)")

        let once = try EntryYAML.decode(yaml)
        XCTAssertEqual(once.authors, authored, "一次正規化不得動作者順序")

        // 兩次——排序若被誤加，第二次才穩定下來的實作同樣要被抓到
        let twice = try EntryYAML.decode(try EntryYAML.encode(once))
        XCTAssertEqual(twice.authors, authored, "第二次正規化同樣不得動作者順序")
    }
}
