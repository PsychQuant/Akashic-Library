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
/// `Given Family`）它**看不出來是同一個名字**——注意這句只對 `matchingKey` 成立，
/// 不對「機械層」整體成立（`PersonBootstrap.identity` 有做重排等價；見 #226）。
///
/// 這組測試釘住的是 **`matchingKey` 的行為邊界**，不是 `authorized` 禁令的論據——
/// 那條禁令的根據是 `AuthorizedNameMigration` 的明文政策，與正規化無關（見
/// `Person.authorized` 的 doc）。哪天有人「順手」讓 matchingKey 也吃語序，這裡會紅。
extension NameNormalizationTests {

    /// `matchingKey` **逐段作用**——這才是「不重排語序」的正確編碼。
    ///
    /// ## 為什麼是同態，不是一張 pair 表
    ///
    /// 前兩版都用「釘住幾組 `(inverted, direct)` 不得同鍵」。**列舉關不上這個空間**：
    /// verify 席對釘了兩組（全寫形 + 縮寫形）的版本仍找到**三個**保留語序塌陷卻讓
    /// 全檔 1249 測試皆綠的 mutation——un-invert 只在 (M6) given 段不含 `-`、
    /// (M7) family 段多 token、(M8) family 是漢字時發生。M6 讓 `Guan, Yongtao` ↔
    /// `Yongtao Guan` 塌縮，而那是本 codebase 自己的常用範例。補一格，開三格。
    ///
    /// 而第三版一度寫成「輸出等於 `s.lowercased()` 的切分」——**那條是紅的**，因為
    /// 它斷言的是「除了小寫與切分之外什麼都不做」，而 `matchingKey` 存在的理由正是
    /// 連字號家族統一、NFKC、剝 Cf 這三件事（各自都有綠燈測試）。**那不是「性質這種
    /// 形式不管用」，是那條性質寫錯了。**
    ///
    /// 同態說的才是要說的事：把兩段用空白接起來再正規化，等於各自正規化再接起來。
    /// 任何重排或跨段合併都會讓它紅，而三種髒輸入全部通過——因為 `matchingKey`
    /// 對它們的處理本來就是逐段的。側條件是**述詞**（兩段正規化後皆非空），不是列舉。
    func testMatchingKeyActsSegmentwise() {
        let parts = ["Liang", "Yu-Jen", "Chang,", "Y-H.", "Guan,", "Yongtao",
                     "梁佑任", "謝復興", "Ｆｕｓｈｉｎｇ", "\u{FEFF}Chen",
                     "Yu\u{2010}Jen", "van", "der", "Waals,", "O'Brien", "MCELROY"]
        var killable = 0
        for a in parts {
            let ka = NameNormalization.matchingKey(a)
            guard !ka.isEmpty else { continue }
            for b in parts {
                let kb = NameNormalization.matchingKey(b)
                guard !kb.isEmpty else { continue }
                XCTAssertEqual(NameNormalization.matchingKey(a + " " + b), ka + " " + kb,
                               "matchingKey 必須逐段作用——重排或跨段合併等於讓身分判斷"
                               + "偷渡進配對層，違反「用於配對，永不用於判定」：\(a) | \(b)")
                if ka != kb { killable += 1 }
            }
        }
        // 語序塌陷的 mutant 只有在兩段的鍵不同時才可能被抓到；記錄有效對數，
        // 避免哪天 parts 被改成全同而讓斷言變成恆真。
        XCTAssertGreaterThan(killable, 100, "有效判別對太少，這條已退化成恆真")
    }

    /// **`authorized = names.map(matchingKey)` 的一個機械後果**（非主論據）。
    ///
    /// 禁令的根據是 `AuthorizedNameMigration` 的明文政策（「仍然多於一個 → 留空並
    /// 報告」），與 `matchingKey` 無關——見 `Person.authorized` 的 doc。本條只釘住
    /// 「連 schema 都擋得住」的那一小塊，**不足以獨立支撐禁令**：對 `names` 每筆都是
    /// `matchingKey` 不動點的記錄（純漢字——`testCJKIsNotMangled` 就是），不變式 1
    /// 根本不觸發。
    func testNormalizedFormsWouldViolateTheAuthorizedSubsetInvariant() {
        // **單一名字**，所以不變式 2（同書寫系統至多一個）不可能觸發——若用多個
        // 拉丁形，`contains { .error }` 會因為不變式 2 而為真，測試就在**錯的理由**
        // 上通過。第一版正是如此：拿掉不變式 1 的檢查它照樣綠（自測突變抓到）。
        let names = ["Liang, Yu-Jen"]
        let normalized = names.map(NameNormalization.matchingKey)   // ["liang, yu-jen"]
        XCTAssertEqual(normalized, ["liang, yu-jen"], "前提：casefold 確實改變了字串")
        XCTAssertFalse(Set(names).contains(normalized[0]), "前提：產出不在 names 內")

        let issues = AuthorizedNames.validate(authorized: normalized, names: names,
                                              ownerKey: "probe")
        // 具名比對訊息，不是只看 severity——確保紅的是**子集**那條
        XCTAssertTrue(
            issues.contains { $0.severity == .error && $0.message.contains("不在 names 內") },
            "casefold 後的字串不在 names 內，不變式 1 必須報 error——"
            + "這就是 `authorized = names.map(normalize)` 不可行的機械證明。"
            + "實際 issues：\(issues.map(\.message))")
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
