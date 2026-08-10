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
    /// 側條件是**述詞**（兩段正規化後皆非空），不是列舉的定義域。
    ///
    /// ## 但性質只看得到 `parts` 生成的輸入——這裡的列舉沒有消失，只是換了位置
    ///
    /// 第一版的 `parts` **16 個全是單 token**，於是 272 個受測輸入全都只有 1–2 token，
    /// 而 M7／M8 的觸發條件（多 token family ＋ 逗號／漢字 family ＋ 逗號）在那個
    /// 輸入空間裡**一次都踩不到**。實跑：M6 killed，**M7／M8 存活全套**（#222 R3）。
    /// 三格只關上一格，而 doc 當時寫的是「任何重排都會讓它紅」——**那句是假的**。
    ///
    /// 所以真正要釘的不是「有效對數夠多」（那是劇場），而是**輸入空間裡真的含有
    /// 每個已知突變需要的形狀**。下面的覆蓋自檢就是這件事：它會在有人把 `parts`
    /// 縮回全單 token 時變紅。
    func testMatchingKeyActsSegmentwise() {
        // 後四個是 R3 補上的：多 token family、多 token given、漢字 family——
        // 少了它們，M7／M8／M9 在這個測試裡不可觸發。
        let parts = ["Liang", "Yu-Jen", "Chang,", "Y-H.", "Guan,", "Yongtao",
                     "梁佑任", "謝復興", "Ｆｕｓｈｉｎｇ", "\u{FEFF}Chen",
                     "Yu\u{2010}Jen", "van", "der", "Waals,", "O'Brien", "MCELROY",
                     "van der Waals,", "Grace S.", "Fu Shing", "梁,"]

        /// 把正規化後的鍵拆成 `(family, given)`——與 `NameForm.isCitationForm` 同判準
        /// （逗號兩側都有內容），語序塌陷的突變都是掛在這個形狀上的。
        func citationParts(_ key: String) -> (family: String, given: String)? {
            guard let c = key.firstIndex(of: ",") else { return nil }
            let f = key[key.startIndex..<c].trimmingCharacters(in: .whitespaces)
            let g = key[key.index(after: c)...].trimmingCharacters(in: .whitespaces)
            return (f.isEmpty || g.isEmpty) ? nil : (f, g)
        }

        var reach = (multiTokenFamily: false, hanFamily: false,
                     multiTokenGiven: false, hyphenlessGiven: false)
        for a in parts {
            let ka = NameNormalization.matchingKey(a)
            guard !ka.isEmpty else { continue }
            for b in parts {
                let kb = NameNormalization.matchingKey(b)
                guard !kb.isEmpty else { continue }

                let joined = ka + " " + kb
                XCTAssertEqual(NameNormalization.matchingKey(a + " " + b), joined,
                               "matchingKey 必須逐段作用——重排或跨段合併等於讓身分判斷"
                               + "偷渡進配對層，違反「用於配對，永不用於判定」：\(a) | \(b)")

                guard let p = citationParts(joined) else { continue }
                if p.family.contains(" ")           { reach.multiTokenFamily = true }
                if WritingSystem.of(p.family) == .han { reach.hanFamily = true }
                if p.given.contains(" ")            { reach.multiTokenGiven = true }
                if !p.given.contains("-")           { reach.hyphenlessGiven = true }
            }
        }
        // 覆蓋自檢——每一項對應一個實測存活過的突變。全部為真才代表這條性質
        // 「看得到」那些突變；否則它只是在一個太小的輸入空間上恆真。
        XCTAssertTrue(reach.hyphenlessGiven,  "M6（given 段無連字號）在此輸入空間不可觸發")
        XCTAssertTrue(reach.multiTokenFamily, "M7（family 段多 token）在此輸入空間不可觸發")
        XCTAssertTrue(reach.hanFamily,        "M8（漢字 family）在此輸入空間不可觸發")
        XCTAssertTrue(reach.multiTokenGiven,  "M9（given 段多 token）在此輸入空間不可觸發")
    }

    /// **`authorized = names.map(matchingKey)` 被不變式 1 擋下的那一半**（非主論據）。
    ///
    /// 禁令的主論據是**不變式 2**（`openspec/specs/authorized-name/spec.md`：同書寫
    /// 系統兩個 authorized 是 "an undecided question, not a designation"，SHALL be
    /// rejected），因為 `matchingKey` 從不轉寫書寫系統——見 `Person.authorized` 的
    /// doc。本條只釘住
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

    /// **主論據**：不變式 1 漏掉的那一半，由不變式 2 接住。
    ///
    /// 殺死前一版論證的反例是「`names` 每筆都是 `matchingKey` 不動點」的記錄——純漢字
    /// 即是，`map` 之後產出**逐字等於** `names`，不變式 1 完全靜默。這條釘住：**那類
    /// 記錄照樣存不進去**，因為 `matchingKey` 從不轉寫書寫系統，兩個漢字名 `map` 完
    /// 仍是兩個漢字名 → 不變式 2 報 `.error`。
    ///
    /// 這才是 `Person.authorized` 禁令的機械根據，也是 `openspec/specs/authorized-name/
    /// spec.md` 的 SHALL（同書寫系統兩個 authorized 是 "an undecided question, not a
    /// designation"）。**不經過正規化那一層，所以不動點反例對它無效。**
    func testFixedPointNamesStillBlockedByTheOnePerScriptInvariant() {
        let names = ["梁佑任", "梁佑仁"]                  // 兩個漢字名，同一人的兩種寫法
        let normalized = names.map(NameNormalization.matchingKey)
        // 前提一：不動點——不變式 1 在這裡沒有東西可抓
        XCTAssertEqual(normalized, names, "前提：純漢字是 matchingKey 的不動點")
        // 前提二：書寫系統沒有被轉寫（這是不變式 2 必然觸發的理由）
        XCTAssertEqual(normalized.map(WritingSystem.of), [.han, .han],
                       "前提：matchingKey 不轉寫書寫系統")

        let issues = AuthorizedNames.validate(authorized: normalized, names: names,
                                              ownerKey: "probe")
        XCTAssertFalse(issues.contains { $0.message.contains("不在 names 內") },
                       "不變式 1 不該觸發——若觸發，本測試就在錯的理由上通過")
        XCTAssertTrue(
            issues.contains { $0.severity == .error && $0.message.contains("han") },
            "不變式 2 必須報 error：兩個漢字 authorized 是「未決」不是「指定」。"
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
