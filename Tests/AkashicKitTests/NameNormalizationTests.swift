import XCTest
@testable import AkashicCore
@testable import AkashicEntity

/// #81 Expected 四：正規化候選生成器。
///
/// **用於配對，永不用於判定**——`matchingKey` 的輸出是比對鍵，不是資料。同 key
/// 只代表「值得提名給人看」，不代表同一人；任何寫回 store 的路徑都必須用原字串。
/// 這條界線是 #81 的哲學段（正規化／身分／正規形是三層）在程式層的投影。
final class NameNormalizationTests: XCTestCase {

    // MARK: - 連字號家族（NFKC 不覆蓋——en/em dash 在 NFKC 下保持原樣）

    func testHyphenFamilyUnifies() {
        // U+2010 HYPHEN / U+2011 NON-BREAKING / U+2013 EN DASH / U+2014 EM DASH
        // / U+2212 MINUS —— WoS 與出版商匯出裡全部實際出現過
        for variant in ["Chang, Y\u{2010}H.", "Chang, Y\u{2011}H.",
                        "Chang, Y\u{2013}H.", "Chang, Y\u{2014}H.",
                        "Chang, Y\u{2212}H."] {
            XCTAssertEqual(NameNormalization.matchingKey(variant),
                           NameNormalization.matchingKey("Chang, Y-H."),
                           "連字號家族必須映到同一鍵：\(variant.unicodeScalars.map { String(format: "U+%04X", $0.value) })")
        }
    }

    // MARK: - NFKC（全形、相容字元）

    func testFullwidthCompatibilityFoldsViaNFKC() {
        XCTAssertEqual(NameNormalization.matchingKey("Ｆｕｓｈｉｎｇ　Ｈｓｉｅｈ"),
                       NameNormalization.matchingKey("Fushing Hsieh"),
                       "全形拉丁與 ideographic space 經 NFKC 收斂")
    }

    func testCJKIsNotMangled() {
        // NFKC 對 CJK 統一表意文字是恆等——本名不得被改寫
        XCTAssertEqual(NameNormalization.matchingKey("謝復興"), "謝復興")
    }

    // MARK: - 空白收斂與 casefold

    func testWhitespaceCollapsesAndCaseFolds() {
        XCTAssertEqual(NameNormalization.matchingKey("  Guan,\u{00A0}\u{00A0}Yongtao  "),
                       NameNormalization.matchingKey("guan, yongtao"),
                       "NBSP、多空白、前後空白收斂；大小寫摺疊")
    }

    // MARK: - 配對面接線：resolver 比對吃正規化、輸出仍是原字串

    func testResolverMatchesAcrossHyphenVariantsButPreservesOriginals() {
        // person 的 alias 用 ASCII 連字號；entry 的 literal 用 U+2010——
        // 正規化前不命中（#81 的病），正規化後提名
        var p = Person(key: "chang-y-h")
        p.names = ["Chang, Y-H."]
        let entry = Entry(id: UUID(), citekey: "chang2020x", type: "article",
                          title: "X", authors: [.literal("Chang, Y\u{2010}H.")], date: "2020")
        let found = PersonResolver.candidates(entries: [entry], people: [p])
        XCTAssertEqual(found.count, 1, "連字號變體必須經正規化命中")
        // **輸出是原字串**：literal 保持 U+2010 原樣——正規化永不外洩成資料
        XCTAssertEqual(found.first?.literal, "Chang, Y\u{2010}H.")
        XCTAssertEqual(found.first?.personKey, "chang-y-h")
    }

    func testAmbiguityStillExcludesAfterNormalization() {
        // 正規化讓兩個人的不同寫法塌縮到同鍵 → 歧義，整組排除（絕不自動合併）
        var a = Person(key: "lee-a"); a.names = ["Lee, J-H."]
        var b = Person(key: "lee-b"); b.names = ["Lee, J\u{2010}H."]
        let entry = Entry(id: UUID(), citekey: "lee2021y", type: "article",
                          title: "Y", authors: [.literal("Lee, J-H.")], date: "2021")
        let found = PersonResolver.candidates(entries: [entry], people: [a, b])
        XCTAssertTrue(found.isEmpty,
                      "正規化製造的塌縮是歧義訊號，不是合併授權：\(found)")
    }
}

/// #140 verify F1 的 regression：bootstrap 與 resolver 的正規化必須是同一份——
/// 分裂的後果是文件化主流程（bootstrap-people → resolve-people）對連字號變體
/// 從 2 候選掉到 0，完全靜默。
extension NameNormalizationTests {
    func testBootstrapAndResolverShareNormalization() {
        let ascii = Entry(id: UUID(), citekey: "a2020x", type: "article",
                          title: "X", authors: [.literal("Chang, Y-H.")], date: "2020")
        let u2010 = Entry(id: UUID(), citekey: "b2021y", type: "article",
                          title: "Y", authors: [.literal("Chang, Y\u{2010}H.")], date: "2021")
        // bootstrap 對兩種寫法必須聚成**一組**（同一人的兩個寫法），不是兩個 person
        let groups = PersonBootstrap.candidates(entries: [ascii, u2010], existing: [])
        XCTAssertEqual(groups.count, 1,
                       "連字號變體必須聚成一組——兩組＝bootstrap 還有自己的舊正規化：\(groups)")
        // 端到端：建出的 person 讓 resolver 對兩筆 entry 都提名
        var p = Person(key: "chang-y-h")
        p.names = groups.first?.names ?? []
        let found = PersonResolver.candidates(entries: [ascii, u2010], people: [p])
        XCTAssertEqual(found.count, 2,
                       "主流程端到端：兩筆 entry 都應提名（曾掉到 0——塌縮歧義誤判）")
    }

    /// #140 verify F2：U+2015 HORIZONTAL BAR 與 dash 家族同鍵。
    func testHorizontalBarUnifies() {
        XCTAssertEqual(NameNormalization.matchingKey("Chang, Y\u{2015}H."),
                       NameNormalization.matchingKey("Chang, Y-H."))
    }
}

/// #140 verify F3：不可見格式字元（Cf）刪除——顯示相同的字串必須同鍵。
extension NameNormalizationTests {
    func testInvisibleFormatCharactersAreStripped() {
        for (label, dirty) in [("ZWSP", "Fushing\u{200B} Hsieh"),
                               ("BOM", "\u{FEFF}Fushing Hsieh"),
                               ("SOFT HYPHEN", "Fushing Hsi\u{00AD}eh"),
                               ("WORD JOINER", "Fushing\u{2060} Hsieh"),
                               ("LRM", "Fushing Hsieh\u{200E}")] {
            XCTAssertEqual(NameNormalization.matchingKey(dirty),
                           NameNormalization.matchingKey("Fushing Hsieh"),
                           "\(label) 必須被剝除——畫面相同的字串永遠配不起來且無診斷")
        }
    }
}
