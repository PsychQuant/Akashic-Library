import XCTest
@testable import AkashicCore
@testable import AkashicEntity

/// venue 名字內容的不變式住在 **store 邊界**（#554 R4 verify，使用者裁決 D8）。
///
/// R2→R4 三輪把名字內容的閘（空白／控制字元／不是名字／存 canonical）裝在 `updateVenue` 的
/// 三個迴圈裡，R4 verify 指出同一個 `names` 欄位還有兩個寫入者沒經過它——`addVenue` 原樣
/// 存入（連空字串都收）、`VenueBootstrap` 只 trim。`Venue.swift` 自己的 doc 早就寫著答案：
/// 「守衛住在 validate → writeVenue 的交會處才擋得住所有路徑」。所以：
///
/// - `NameIdentity.wellFormednessIssue` 是**一份**謂詞，與輸出閘 `UnsafeToEmitScalar` 共用
///   危險 scalar 的定義（R4 的 `forbiddenScalar` 是 19 個例子的列舉、170 個 Cf 漏 149，且與
///   `UnsafeToEmitScalar` 分岔——ALM 輸入放行、輸出逃脫）
/// - `Venue.validate()` 對 names／authorized／variant 逐條驗（error 級）、names 內無 canonical-相等對
/// - 所有寫入者存 `NameIdentity.canonical`
///
/// live store 2026-09-12 實測 485 筆 venue：無字母 0、含 Cf／Cc 0、非 canonical 拼法 0、
/// NBSP／U+3000 0——提級不拒絕任何既有記錄。
final class VenueNameInvariantTests: XCTestCase {

    private func venue(names: [String], authorized: [String] = [], variant: [String] = []) -> Venue {
        var v = Venue(key: "j", type: .periodical,
                      names: Timeline(names.map { TemporalValue(value: $0) }), authorized: authorized)
        v.variant = variant
        return v
    }
    private func errors(_ v: Venue) -> [String] {
        v.validate().filter { $0.severity == .error }.map(\.message)
    }

    // MARK: - 謂詞本身

    func testCanonicalWellFormedNamesPass() {
        for ok in ["Psychometrika", "1843", "2600", "心理計量學", "Zeitschrift für Psychologie",
                   "Психометрика", "サイコメトリカ", "نشریه\u{200C}روان\u{200D}سنجی", "J. B."] {
            XCTAssertNil(NameIdentity.wellFormednessIssue(ok), ok)
        }
    }

    /// 純數字刊名是真的（*1843*、*2600*）——判準是「至少一個字母**或數字**」，`×`／`—`／`…` 仍擋。
    func testSymbolOnlyIsNotANameButDigitsAre() {
        XCTAssertNil(NameIdentity.wellFormednessIssue("1843"))
        for bad in ["×", "÷", "—", "…", "× ÷"] { XCTAssertNotNil(NameIdentity.wellFormednessIssue(bad), bad) }
    }

    /// 非 canonical 形（前後／連續空白、tab、NFD）不是合法的儲存形——寫入者要先 canonical。
    func testNonCanonicalSpellingIsRejected() {
        for bad in ["Psychometrika ", " Psychometrika", "Journal  of  X", "New\tJournal",
                    "Psychome\u{301}trika", "心理　計量"] {
            XCTAssertNotNil(NameIdentity.wellFormednessIssue(bad), bad.debugDescription)
        }
        XCTAssertNil(NameIdentity.wellFormednessIssue(NameIdentity.canonical("Journal  of  X")))
    }

    /// 危險 scalar 是**性質**不是列舉（R4 verify 第 2 列：TAG 字元、ALM 漏過），且與 `UnsafeToEmitScalar` 同一份。
    func testFormatAndControlScalarsAreRejectedAsAClass() {
        let cases: [(String, String)] = [
            ("Psychometrika\u{202E}", "RLO"), ("Psycho\u{200B}metrika", "ZWSP"), ("Psycho\u{00AD}metrika", "SHY"),
            ("Psycho\u{061C}metrika", "ARABIC LETTER MARK"), ("Tag\u{E0041}\u{E007F}Name", "TAG"),
            ("Iss\u{206A}Name", "U+206A"), ("Iaa\u{FFF9}Name", "U+FFF9"), ("Mvs\u{180E}Name", "U+180E"),
            ("Bom\u{FEFF}Name", "BOM"), ("Line\u{2028}Name", "LS"),
        ]
        for (s, label) in cases { XCTAssertNotNil(NameIdentity.wellFormednessIssue(s), label) }
        // 與輸出閘同一份定義：UnsafeToEmitScalar 收的，這裡也收
        for v: UInt32 in [0x202E, 0x2066, 0x200E, 0x061C, 0xFEFF, 0x2028] {
            XCTAssertTrue(UnsafeToEmitScalar.contains(v))
            XCTAssertNotNil(NameIdentity.wellFormednessIssue("A" + String(Unicode.Scalar(v)!) + "B"), String(v, radix: 16))
        }
    }

    /// 接合字元的**非法位置**（R4 verify 第 9 列的原案例：尾隨 ZWJ、前導 ZWNJ、鄰接空白）。合法脈絡
    /// 的定義自 D9 起在 `joinerIsLegal`（virama 之後、或兩側都是使用 join control 的文字的字母／標記／
    /// 數字），本測試只釘非法位置；合法案例見 `testJoinControlScriptsKeepTheirJoiners`。
    func testJoinersOnlyBetweenLetters() {
        XCTAssertNil(NameIdentity.wellFormednessIssue("نشریه\u{200C}روان"), "ZWNJ between Arabic letters")
        XCTAssertNil(NameIdentity.wellFormednessIssue("क्\u{200D}ष"), "ZWJ after virama (Devanagari)")
        XCTAssertNotNil(NameIdentity.wellFormednessIssue("Zwj\u{200D}"), "trailing")
        XCTAssertNotNil(NameIdentity.wellFormednessIssue("\u{200C}Zwnj"), "leading")
        XCTAssertNotNil(NameIdentity.wellFormednessIssue("Zw \u{200D}j"), "next to space")
    }

    /// **拉丁字母夾 joiner 是通道，不是名字**（R5 verify 第 1 列，五路命中；Claude 代裁 D9）：
    /// R4 的 `joinable` 只查兩側是字母，拉丁字母就是字母，於是 doc 宣稱關掉的通道從未關過——
    /// 而 R4 的測試 doc 逐字寫「拉丁字母間的 ZWNJ」、五個斷言裡沒有一個放它。這條就是那個斷言。
    func testLatinAndCJKJoinersAreRejected() {
        for bad in ["Psycho\u{200C}metrika", "Psycho\u{200D}metrika", "心理\u{200C}計量學", "心理\u{200D}計量學",
                    "Психо\u{200D}метрика"] {
            XCTAssertNotNil(NameIdentity.wellFormednessIssue(bad), bad.debugDescription)
        }
    }

    /// 反方向也是真的（同一列）：合法脈絡見 `joinerIsLegal`（R8：掛在同一文字字母上的 virama 之後、
    /// 或左鄰居是 join-control 文字的字母／標記／數字且右鄰居是同一文字的字母／數字）。legacy Malayalam chillu 是 consonant＋virama＋ZWJ **詞尾**、波斯文
    /// `۱۴۰۰\u{200C}ها` 是**數字**＋ZWNJ——R4 的「兩側都是字母」對這兩個真實形狀 fail-closed。
    func testJoinControlScriptsKeepTheirJoiners() {
        for ok in ["\u{0D28}\u{0D4D}\u{200D}", "കല\u{0D4D}\u{200D}", "۱۴۰۰\u{200C}ها", "نشریه\u{200C}روان",
                   "क्\u{200D}ष", "ک\u{200C}تاب"] {
            XCTAssertNil(NameIdentity.wellFormednessIssue(ok), ok.debugDescription)
        }
        // 詞尾 ZWJ 只在 virama 之後合法——拉丁／西里爾字母後的詞尾 joiner 仍擋（R4 第 9 列的原案例）
        XCTAssertNotNil(NameIdentity.wellFormednessIssue("Zwj\u{200D}"))
        XCTAssertNotNil(NameIdentity.wellFormednessIssue("ржа\u{200C}"))
    }

    /// **「不可見」是 Unicode 自己的性質 `Default_Ignorable_Code_Point`**（R5 verify 第 2 列，Claude 代裁 D9）
    /// ——不是 generalCategory 四類：VS16（U+FE0F，網頁貼上常見）、CGJ（U+034F）是 Mn，Hangul filler
    /// （U+3164）是 **Lo**，三者都通過 R5 的分類檢查；`心\u{FE0F}理學報`／`心\u{034F}理學報`／`心理學報` 存成三筆
    /// 「不同」名字，`add-venue --names $'\u{3164}'` 建出一筆 displayName 空白的 venue（真 binary 實測）。
    func testDefaultIgnorableScalarsAreInvisibleEvenWhenTheyAreLettersOrMarks() {
        let cases: [(String, String)] = [
            ("心\u{FE0F}理學報", "VS16"), ("心\u{034F}理學報", "CGJ"), ("Journal\u{FE0F}", "trailing VS16"),
            ("\u{3164}", "Hangul filler alone"), ("저널\u{3164}", "Hangul filler inside"),
            ("ᠮᠣᠩ\u{180B}ᠭᠣᠯ", "Mongolian FVS1"), ("A\u{E0100}B", "variation selector supplement"),
            ("\u{115F}\u{1160}", "Hangul choseong+jungseong filler"),
        ]
        for (s, label) in cases { XCTAssertNotNil(NameIdentity.wellFormednessIssue(s), label) }
        // 「至少一個字母或數字」對 DI scalar 不計——Hangul filler 是 Lo，單獨一個不是名字
        XCTAssertNotNil(NameIdentity.wellFormednessIssue("\u{3164}\u{3164}"))
    }

    /// **區塊成員資格不是充分條件**（R6 verify 第 1 列，Codex）：Unicode 區塊含標點，`A\u{200C}،B`
    /// 因逗號落在 Arabic 區塊而通過——這個 ZWNJ 沒有接合用途，只是通道。R7 起兩側都要是該區塊裡的
    /// 字母／標記／數字；標點、拉丁鄰居都不算。
    func testJoinerBesidePunctuationOrAForeignLetterIsRejected() {
        for bad in ["A\u{200C}\u{060C}B", "ک\u{200C}\u{060C}", "\u{060C}\u{200C}ک", "क\u{200D}\u{0964}",
                    "ک\u{200C}A", "A\u{200C}ک"] {
            XCTAssertNotNil(NameIdentity.wellFormednessIssue(bad), bad.debugDescription)
        }
        XCTAssertNil(NameIdentity.wellFormednessIssue("ک\u{200C}تاب"), "兩側都是阿拉伯字母仍合法")
        XCTAssertNil(NameIdentity.wellFormednessIssue("۱۴۰۰\u{200C}ها"), "數字＋字母仍合法")
    }

    /// **連續 joiner 沒有正字法意義**（R6 verify 第 19 列）：第二個 joiner 的鄰居是 joiner，字型忽略重複，
    /// 純粹是「看起來一樣、canonical 不相等」的殘餘通道。virama 分支也要求 virama 掛在印度系基底上
    /// （`Psychometrika\u{094D}\u{200D}` 是弱通道）。
    func testConsecutiveJoinersAndFloatingViramaAreRejected() {
        for bad in ["ا\u{200C}\u{200C}ب", "ا\u{200C}\u{200D}ب", "क्\u{200D}\u{200D}क", "Psychometrika\u{094D}\u{200D}"] {
            XCTAssertNotNil(NameIdentity.wellFormednessIssue(bad), bad.debugDescription)
        }
        XCTAssertNil(NameIdentity.wellFormednessIssue("\u{0D28}\u{0D4D}\u{200D}"), "chillu 仍合法")
    }

    /// **同一個文字的補充區塊、以及其他草書文字**（R6 verify 第 14／22 列）：Mandaic 與 Syriac Supplement
    /// 就夾在 Syriac 與 Arabic Extended-B 之間，漏掉是疏忽不是裁決；Adlam／Hanifi Rohingya／Tifinagh／
    /// Sogdian／Old Uyghur／Manichaean／Arabic Extended-C 同為使用 join control 的文字。
    func testCursiveScriptsOutsideTheOriginalListKeepTheirJoiners() {
        for ok in ["\u{0840}\u{200D}\u{0841}", "\u{0860}\u{200C}\u{0861}", "\u{1E900}\u{200C}\u{1E901}",
                   "\u{10D00}\u{200D}\u{10D01}", "\u{2D30}\u{200D}\u{2D31}", "\u{10F30}\u{200D}\u{10F31}"] {
            XCTAssertNil(NameIdentity.wellFormednessIssue(ok), ok.debugDescription)
        }
    }

    /// **U+2800 BRAILLE PATTERN BLANK 渲染成一格空白**（R6 verify 第 20 列）：不是 White_Space、不是四類、
    /// 不是 DI、不在 `UnsafeToEmitScalar`——與 Hangul filler 同形而三份性質都沒收它，顯式加進謂詞。
    func testBrailleBlankIsNotPartOfAName() {
        for bad in ["Psychometrika\u{2800}", "Psycho\u{2800}metrika", "\u{2800}"] {
            XCTAssertNotNil(NameIdentity.wellFormednessIssue(bad), bad.debugDescription)
        }
    }

    /// 碼位補零到四位（R6 verify 第 32 列）：`U+034F` 不是 `U+34F`，搜 `U+001C` 才搜得到。
    func testCodePointsInMessagesArePaddedToFourHexDigits() {
        XCTAssertTrue(NameIdentity.wellFormednessIssue("A\u{034F}B")?.contains("U+034F") == true)
        XCTAssertTrue(NameIdentity.wellFormednessIssue("A\u{001C}B")?.contains("U+001C") == true)
        XCTAssertTrue(NameIdentity.wellFormednessIssue("Tag\u{E0041}Name")?.contains("U+E0041") == true)
    }

    /// **virama 要掛在同一文字的字母上、joiner 兩側要是同一文字、joiner 之後要是基底**（R7 verify 第 1／33／26 列，
    /// Codex＋DA＋security）：R7 的 virama 分支只驗 `scalars[i-2]` 是 member——數字（U+0967）與 nukta（Mn）都是 member，
    /// `Journal \u{0967}\u{094D}\u{200D}` 通過；virama 分支不看右鄰居（`क्\u{200C}A` 通過）；(b) 支不要求同一文字
    /// （`ک\u{200C}क` 通過）；joiner 夾在基底與自己的 virama 之間（`क\u{200D}\u{094D}ष`）與 joiner 後直接接標記
    /// （`ا\u{200C}\u{064E}ب`）都通過。R8：從 virama 往前跳過標記找基底、基底要是字母；joiner 之後只能是基底
    /// （字母／數字）；兩側同一文字。合法的 conjunct 形（ka＋nukta＋virama＋ZWJ＋ssa）要保留。
    func testViramaBaseAndJoinerNeighboursAreLettersOfOneScript() {
        for bad in ["Journal \u{0967}\u{094D}\u{200D}", "Journal \u{093C}\u{094D}\u{200D}", "क्\u{200C}A",
                    "ک\u{200C}क", "क\u{200D}\u{094D}ष", "ا\u{200C}\u{064E}ب", "क\u{200D}\u{093C}"] {
            XCTAssertNotNil(NameIdentity.wellFormednessIssue(bad), bad.debugDescription)
        }
        for ok in ["क़्\u{200D}ष", "क्\u{200D}ष", "\u{0D28}\u{0D4D}\u{200D}", "بَ\u{200C}ب", "۱۴۰۰\u{200C}ها",
                   "ស្\u{200D}ត"] {
            XCTAssertNil(NameIdentity.wellFormednessIssue(ok), ok.debugDescription)
        }
    }

    /// **「至少一個字母或數字」的字母是 L 類，不是 Alphabetic**（R7 verify 第 15 列，security）：`Character.isLetter`
    /// 是 `isAlphabetic`，而 Unicode `Alphabetic` 含 Other_Alphabetic 的 Mn／Mc（Arabic fatha、Devanagari vowel sign）
    /// ——一筆只有一個孤立變音符號的 venue 寫得進去，displayName 是一個懸空的記號（R5 Hangul filler 的同形）。
    func testLoneCombiningMarkIsNotAName() {
        for bad in ["\u{064E}", "\u{093E}", "\u{0345}", "\u{0650}\u{0651}"] {
            XCTAssertNotNil(NameIdentity.wellFormednessIssue(bad), bad.debugDescription)
        }
        XCTAssertNil(NameIdentity.wellFormednessIssue("\u{0640}"), "tatweel 是 Lm，照 doc 放行")
        XCTAssertNil(NameIdentity.wellFormednessIssue("۱۴۰۰"), "Nd 是數字")
    }

    /// 訊息是對**操作者**說的（R5 verify 第 17 列）：修法是人改 YAML，訊息不得叫他呼叫一個 Swift 函式。
    func testInvariantMessagesSpeakToTheOperator() {
        for bad in ["Psychometrika ", "Psycho\u{200B}metrika", "×", "", "Psycho\u{200C}metrika", "\u{3164}"] {
            let why = NameIdentity.wellFormednessIssue(bad) ?? ""
            XCTAssertFalse(why.isEmpty, bad.debugDescription)
            XCTAssertFalse(why.contains("NameIdentity"), why)
            XCTAssertTrue(why.contains("YAML") || why.contains("刪") || why.contains("留"), "要說怎麼修：\(why)")
        }
    }

    // MARK: - validate 是所有路徑的交會處

    func testValidateRejectsMalformedNamesInAllThreeLists() {
        XCTAssertFalse(errors(venue(names: ["Psychometrika "])).isEmpty, "names 非 canonical")
        XCTAssertFalse(errors(venue(names: ["Psycho\u{200B}metrika"])).isEmpty, "names 零寬")
        XCTAssertFalse(errors(venue(names: ["×"])).isEmpty, "names 不是名字")
        XCTAssertFalse(errors(venue(names: [""])).isEmpty, "空名")
        XCTAssertFalse(errors(venue(names: ["Psychometrika", "Psychometrika "], authorized: ["Psychometrika "])).isEmpty,
                       "authorized 非 canonical（且 names 有近重複對）")
        XCTAssertTrue(errors(venue(names: ["Psychometrika", "1843"], authorized: ["Psychometrika"], variant: ["1843"])).isEmpty)
    }

    /// names 內不得有兩筆 canonical-相等的條目（venue 沒有 `validateNearDuplicates`——person 有）。
    func testValidateRejectsCanonicalEqualPairInNames() {
        let msgs = errors(venue(names: ["Psychometrika", "Psychometrika"]))
        XCTAssertFalse(msgs.isEmpty, "完全重複也是近重複對")
        XCTAssertTrue(msgs.contains { $0.contains("近重複") }, "\(msgs)")
    }

    /// **同名的不相交沿革段不是近重複對**（R5 verify 第 4 列）：`TimelineOf` 明寫同一 value 可在
    /// 多段，row 22 保留沿革正是為了「改回舊名」（Sankhyā 1933–1960 → 分刊 → 2002–2007 合回同名
    /// → 再分）。R5 的檢查對 value 去重、不看時間，那筆記錄寫不進去、「人改 YAML」沒有合法結果。
    /// 判準：兩段**都**作時間宣稱且**不重疊**才豁免；任一段無時間宣稱、或兩段重疊，仍是近重複對。
    func testValidateExemptsDisjointDatedSegmentsWithTheSameTitle() {
        func v(_ segs: [TemporalValue<String>]) -> Venue {
            Venue(key: "sankhya", type: .periodical, names: Timeline(segs), authorized: [])
        }
        let disjoint = v([TemporalValue(value: "Sankhyā", range: DateRange(start: "1933", end: "1960")),
                          TemporalValue(value: "Sankhyā Series A", range: DateRange(start: "1961", end: "2001")),
                          TemporalValue(value: "Sankhyā", range: DateRange(start: "2002", end: "2007"))])
        XCTAssertTrue(errors(disjoint).isEmpty, "\(errors(disjoint))")
        let overlapping = v([TemporalValue(value: "Sankhyā", range: DateRange(start: "1933", end: "1960")),
                             TemporalValue(value: "Sankhyā", range: DateRange(start: "1950"))])
        XCTAssertTrue(errors(overlapping).contains { $0.contains("近重複") }, "\(errors(overlapping))")
        let oneUndated = v([TemporalValue(value: "Sankhyā", range: DateRange(start: "1933", end: "1960")),
                            TemporalValue(value: "Sankhyā")])
        XCTAssertTrue(errors(oneUndated).contains { $0.contains("近重複") }, "\(errors(oneUndated))")
    }

    /// **豁免的「不相交」是保守的**（R6 verify 第 9／47 列）：`DateRange.overlaps` 用字串比較，
    /// `end: "1960"` 對 `start: "1960-06"` 會判「在前」（fail-open）；沿革豁免是本 repo 第一次拿它當**放行**
    /// 條件。R7 起豁免用自己的判準：以較粗的粒度比、端點相等算重疊、且兩段都要有可比的端點。
    func testNearDupExemptionIsConservativeAboutGranularityAndTouchingEndpoints() {
        func v(_ segs: [TemporalValue<String>]) -> Venue {
            Venue(key: "sankhya", type: .periodical, names: Timeline(segs), authorized: [])
        }
        let mixed = v([TemporalValue(value: "Sankhyā", range: DateRange(start: "1933", end: "1960")),
                       TemporalValue(value: "Sankhyā", range: DateRange(start: "1960-06", end: "2007"))])
        XCTAssertTrue(errors(mixed).contains { $0.contains("近重複") }, "1960 涵蓋 1960-06：\(errors(mixed))")
        let touching = v([TemporalValue(value: "Sankhyā", range: DateRange(start: "1933", end: "1960")),
                          TemporalValue(value: "Sankhyā", range: DateRange(start: "1960", end: "2007"))])
        XCTAssertTrue(errors(touching).contains { $0.contains("近重複") }, "端點相等算重疊：\(errors(touching))")
        let attestedOnly = v([TemporalValue(value: "Sankhyā", range: DateRange(attested: ["1950"])),
                              TemporalValue(value: "Sankhyā", range: DateRange(attested: ["2005"]))])
        XCTAssertTrue(errors(attestedOnly).contains { $0.contains("近重複") }, "attested-only 沒有可比端點：\(errors(attestedOnly))")
        let fine = v([TemporalValue(value: "Sankhyā", range: DateRange(start: "1933", end: "1960-12")),
                      TemporalValue(value: "Sankhyā", range: DateRange(start: "1961"))])
        XCTAssertTrue(errors(fine).isEmpty, "\(errors(fine))")
    }

    /// **豁免的端點要是 ISO 8601 前綴**（R7 verify 第 2／3／7 列，三席）：R7 的 `before` 對任意字串做字典序比較，
    /// `end: 2003-01`／`start: 2003-1`（手誤少一位）、`民國49`／`民國50`、`1960-10`／`1960-9` 全判「不相交」而豁免；
    /// venue `names` 的日期 decode 不驗、`dateFieldAnomalies` 不掃 venue，三處都沉默。`ISO8601Prefix.isValid` 早就
    /// 存在（`ISO8601Prefix.compatible` 的 doc 明寫非 ISO 一律當不相容），R8 在 `before` 裡對兩端各 guard 一次。
    func testNearDupExemptionRequiresISOEndpoints() {
        func v(_ segs: [TemporalValue<String>]) -> Venue {
            Venue(key: "sankhya", type: .periodical, names: Timeline(segs), authorized: [])
        }
        for (e, s) in [("2003-01", "2003-1"), ("民國49", "民國50"), ("1960-10", "1960-9"), ("2503", "abc"), ("1960 ", "1961")] {
            let vv = v([TemporalValue(value: "Sankhyā", range: DateRange(start: "1933", end: e)),
                        TemporalValue(value: "Sankhyā", range: DateRange(start: s))])
            XCTAssertTrue(errors(vv).contains { $0.contains("近重複") }, "\(e) / \(s)：\(errors(vv))")
        }
    }

    /// **三張清單都掃近重複對**（R5 verify 第 11 列）：`variant` 內兩筆完全相同、`authorized` 內兩筆
    /// 完全相同——工具不會造出，手改會；R5 只掃 names。
    func testValidateRejectsCanonicalEqualPairInVariantAndAuthorized() {
        let vv = venue(names: ["Psychometrika", "1843"], authorized: ["Psychometrika"], variant: ["1843", "1843"])
        XCTAssertTrue(errors(vv).contains { $0.contains("variant") && $0.contains("近重複") }, "\(errors(vv))")
        let va = venue(names: ["Psychometrika", "1843"], authorized: ["1843", "1843"])
        XCTAssertTrue(errors(va).contains { $0.contains("authorized") && $0.contains("近重複") }, "\(errors(va))")
    }

    // MARK: - 第五個寫入者：bootstrap 存 canonical

    func testBootstrapStoresCanonicalNames() {
        var e = Entry(id: UUID(), citekey: "a", type: .periodicalArticle, title: "T",
                      authors: [.literal("A, A.")], date: "2020")
        e.fields = ["journaltitle": "  Journal  of  X "]
        let r = VenueBootstrap.result(entries: [e], existing: [])
        let venues = VenueBootstrap.makeVenues(r.candidates)
        XCTAssertEqual(venues.first?.names.entries.map(\.value), ["Journal of X"])
        XCTAssertEqual(venues.first?.authorized, ["Journal of X"])
        XCTAssertTrue(venues.allSatisfy { errors($0).isEmpty })
    }

    /// **被謂詞拒的 literal 不得靜默消失**（R5 verify 第 5 列）：R5 的 `guard … else { continue }` 在
    /// 分組之前，連 occurrences 都不累計——不在 candidates／dropped／conflicts／pending，`bootstrap-venues`
    /// 零字。同檔 `Dropped` 的 doc 寫「不靜默丟」。路由到 `dropped`、帶理由、累計次數。
    func testBootstrapReportsRejectedLiteralsAsDroppedWithReason() {
        func entry(_ ck: String, _ jt: String) -> Entry {
            var e = Entry(id: UUID(), citekey: ck, type: .periodicalArticle, title: "T",
                          authors: [.literal("A, A.")], date: "2020")
            e.fields = ["journaltitle": jt]
            return e
        }
        let r = VenueBootstrap.result(entries: [entry("a", "×"), entry("b", "×"), entry("c", "   "),
                                                entry("d", "Psycho\u{200B}metrika")], existing: [])
        XCTAssertTrue(r.candidates.isEmpty, "\(r.candidates)")
        let byName = Dictionary(uniqueKeysWithValues: r.dropped.map { ($0.name, $0) })
        XCTAssertEqual(byName["×"]?.occurrences, 2)
        XCTAssertTrue(byName["×"]?.reason.contains("字母或數字") == true, "\(String(describing: byName["×"]))")
        XCTAssertEqual(byName["   "]?.occurrences, 1)
        XCTAssertTrue(byName["   "]?.reason.contains("空白") == true)
        XCTAssertEqual(byName["Psycho\u{200B}metrika"]?.occurrences, 1)
        XCTAssertTrue(byName["Psycho\u{200B}metrika"]?.reason.contains("U+200B") == true)
        // bootstrap 脈絡的出口是修 work 的來源欄位，理由要說（R6 verify 第 34 列）
        XCTAssertTrue(r.dropped.filter { $0.name != "心理學報" }.allSatisfy { $0.reason.contains("來源欄位") }, "\(r.dropped)")
        // 產不出 key 的既有路徑仍走同一個 `dropped`，理由分得開
        let cjk = VenueBootstrap.result(entries: [entry("e", "心理學報")], existing: [])
        XCTAssertEqual(cjk.dropped.map(\.name), ["心理學報"])
        XCTAssertTrue(cjk.dropped[0].reason.contains("key"), cjk.dropped[0].reason)
    }

    /// **已有 venue 的檢查在謂詞之前**（R6 verify 第 16 列）：`matchingKey` 會刪 Cf，所以只差一個
    /// soft hyphen 的既有刊名 literal（WoS／HTML 貼上常見）本來就能被 `resolve-venues` 歸戶——R6 把它
    /// 印成「不建檔…請修來源欄位」是不必要的動作，而且它的 occurrences 從乾淨群裡消失。
    func testBootstrapSkipsLiteralsThatMatchAnExistingVenueEvenWhenMalformed() {
        var e = Entry(id: UUID(), citekey: "a", type: .periodicalArticle, title: "T",
                      authors: [.literal("A, A.")], date: "2020")
        e.fields = ["journaltitle": "Psycho\u{00AD}metrika"]
        let existing = Venue(key: "psychometrika", type: .periodical,
                             names: Timeline([TemporalValue(value: "Psychometrika")]), authorized: ["Psychometrika"])
        let r = VenueBootstrap.result(entries: [e], existing: [existing])
        XCTAssertTrue(r.candidates.isEmpty && r.dropped.isEmpty && r.pendingResolution.isEmpty, "\(r)")
    }
}
