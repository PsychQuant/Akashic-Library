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

/// #221：**正規化的邊界**——`authorized` 為什麼不能改名叫 `normalized`。
///
/// `matchingKey` 只做可機械的那一層。同一個人的兩種語序（`Family, Given` vs
/// `Given Family`）它**看不出來是同一個名字**——所以「哪一個對外」這件事在正規化層
/// 根本不可表達，只能由 `authorized` 權威指定。
///
/// 這組測試釘住 `Person.authorized` 的 doc 主張。doc 說了什麼、這裡就驗什麼；
/// 哪天有人「順手」讓 matchingKey 也吃語序，這裡會紅並逼他重讀那段 doc。
extension NameNormalizationTests {

    /// 語序差異**不塌縮**——正規化不做身分判斷。
    func testNameOrderVariantsDoNotCollapse() {
        let inverted = NameNormalization.matchingKey("Liang, Yu-Jen")
        let direct   = NameNormalization.matchingKey("Yu-Jen Liang")
        XCTAssertNotEqual(inverted, direct,
                          "語序若塌縮，等於機械層做了身分判斷——違反「用於配對，永不用於判定」")
        // 逐字釘住，避免哪天改成「塌縮成同一個新鍵」仍讓上面那條通過
        XCTAssertEqual(inverted, "liang, yu-jen")
        XCTAssertEqual(direct, "yu-jen liang")
    }

    /// 跨書寫系統更不塌縮——`梁佑任` 與任何羅馬化都是不同鍵。
    ///
    /// 這是 `authorized` 「每個書寫系統至多一個」那條規則存在的前提：若正規化能跨
    /// 書寫系統配對，那條規則就該由機械執行而不是由人指定。
    func testCrossScriptVariantsDoNotCollapse() {
        let han = NameNormalization.matchingKey("梁佑任")
        XCTAssertEqual(han, "梁佑任", "CJK 不受 lowercase／連字號映射影響")
        for latin in ["Liang, Yu-Jen", "Yu-Jen Liang"] {
            XCTAssertNotEqual(han, NameNormalization.matchingKey(latin))
        }
    }

    /// 對照組：**該塌縮的仍然塌縮**——否則上面兩條可能只是因為正規化整個壞掉才通過。
    func testMechanicalVariantsStillCollapse() {
        let target = NameNormalization.matchingKey("Yu-Jen Liang")
        for dirty in ["YU-JEN LIANG",            // 大小寫
                      "Yu\u{2010}Jen Liang",     // U+2010 HYPHEN
                      "Yu\u{2013}Jen Liang",     // U+2013 EN DASH
                      "  Yu-Jen   Liang  "] {    // 空白收斂 + trim
            XCTAssertEqual(NameNormalization.matchingKey(dirty), target,
                           "\(dirty.debugDescription) 屬可機械的那一層，必須塌縮")
        }
    }
}
