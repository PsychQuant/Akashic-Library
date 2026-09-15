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
        // `क\u{200D}\u{094D}ष`（joiner 在 virama **之前**）R8 曾在這裡當反例——R9 改收（D21，見下一條測試）
        for bad in ["Journal \u{0967}\u{094D}\u{200D}", "Journal \u{093C}\u{094D}\u{200D}", "क्\u{200C}A",
                    "ک\u{200C}क", "ا\u{200C}\u{064E}ب", "क\u{200D}\u{093C}"] {
            XCTAssertNotNil(NameIdentity.wellFormednessIssue(bad), bad.debugDescription)
        }
        for ok in ["क़्\u{200D}ष", "क्\u{200D}ष", "\u{0D28}\u{0D4D}\u{200D}", "بَ\u{200C}ب", "۱۴۰۰\u{200C}ها",
                   "ស្\u{200D}ត"] {
            XCTAssertNil(NameIdentity.wellFormednessIssue(ok), ok.debugDescription)
        }
    }

    /// **virama 與它前面被跳過的標記都要與基底同一文字**（R8 verify 第 6／18／19／23／26 列，Codex＋四席）：
    /// R8 的 (a) 支只驗基底與右鄰居的文字，virama 本身只驗 ccc 9，走訪過的標記只驗 Mn／Mc——
    /// `ک\u{094D}\u{200D}`（Arabic 字母＋Devanagari virama＋ZWJ）、`क\u{09CD}\u{200D}ष`（Devanagari 基底＋Bengali virama）、
    /// `क\u{09BC}\u{094D}\u{200D}ष`（Bengali nukta 夾在中間）都通過，而 doc 寫的是「掛在**同一文字**字母上的 virama」。
    /// 合法的同文字 conjunct（ka＋nukta＋virama＋ZWJ＋ssa）仍收。Claude 代裁 D22。
    func testViramaAndItsMarksMustShareTheBaseScript() {
        for bad in ["ک\u{094D}\u{200D}", "क\u{09CD}\u{200D}ष", "क\u{09BC}\u{094D}\u{200D}ष", "ک\u{094D}\u{200D}ب"] {
            XCTAssertNotNil(NameIdentity.wellFormednessIssue(bad), bad.debugDescription)
        }
        for ok in ["क़्\u{200D}ष", "क\u{093C}\u{094D}\u{200D}ष", "\u{0D28}\u{0D4D}\u{200D}"] {
            XCTAssertNil(NameIdentity.wellFormednessIssue(ok), ok.debugDescription)
        }
    }

    /// **詞尾 chillu 之後接空白視同沒有右鄰居**（R8 verify 第 11 列，logic）：R8 的 (a) 支「右鄰居若在要是同一文字的
    /// 字母／數字」只對整個字串的最後一個詞成立——多字刊名裡的 legacy Malayalam chillu／Bengali khanda ta 右邊是
    /// U+0020，既不同文字也不是字母，`add-venue --names $'അവന്\u{200D} വന്നു'` 被拒、單詞版通過。canonical 形保證
    /// 內部空白只會是單一 U+0020，所以「空白視同沒有」不會放行任何別的東西。D22 的第二半。
    func testWordFinalChilluBeforeASpaceIsStillWordFinal() {
        for ok in ["അവന്\u{200D} വന്നു", "ত্\u{200D} ব", "\u{0D28}\u{0D4D}\u{200D} Journal"] {
            XCTAssertNil(NameIdentity.wellFormednessIssue(ok), ok.debugDescription)
        }
        // 空白**之前**的 (b) 支 joiner 仍拒：`ب\u{200C} ب` 的 ZWNJ 兩側不是同一個詞
        XCTAssertNotNil(NameIdentity.wellFormednessIssue("ب\u{200C} ب"))
        XCTAssertNotNil(NameIdentity.wellFormednessIssue("അവന്\u{200D}\u{00A0}വന്നു"), "NBSP 不是 canonical 形，先被第 1 條擋")
    }

    /// **joiner 在同一 Indic 文字的 virama 之前是正字法**（R8 verify 第 10 列，logic；Claude 代裁 D21）：R8 把
    /// `क\u{200D}\u{094D}ष` 當「沒有正字法意義」的 confusable 通道，對 Bengali 為假——Unicode 核心規範 ch. 12.2 明寫
    /// ya-phalaa 用 `<RA, ZWJ, VIRAMA, YA>`（`র\u{200D}\u{09CD}যাব`＝RAB，常見外來語），Microsoft 的 Devanagari／Bengali
    /// OpenType 音節文法都有 `<ZWNJ|ZWJ>+H` 這一支（2026-09-13 實取兩頁確認）。收的範圍是 (b) 支的右鄰居可以是
    /// **同一 Indic 文字**（joinScript 100–109）的 virama（ccc 9）；非 Indic 的 virama（Myanmar asat、Khmer coeng）
    /// 與非 virama 的標記（Arabic fatha）仍拒。
    func testJoinerBeforeASameScriptViramaIsIndicOrthography() {
        for ok in ["র\u{200D}\u{09CD}যাব", "क\u{200D}\u{094D}ष", "ক\u{200C}\u{09CD}ষ", "র\u{200D}\u{09CD}য"] {
            XCTAssertNil(NameIdentity.wellFormednessIssue(ok), ok.debugDescription)
        }
        for bad in ["ا\u{200C}\u{064E}ب", "\u{1000}\u{200D}\u{1039}\u{1000}", "ក\u{200D}\u{17D2}ត", "क\u{200D}\u{09CD}ष",
                    "A\u{200D}\u{094D}ष"] {
            XCTAssertNotNil(NameIdentity.wellFormednessIssue(bad), bad.debugDescription)
        }
    }

    /// **virama 之前的 joiner 要有右脈絡，且只在有引用的文字裡**（R9 verify DA 第 10 列；Claude 代裁 D26）：R9 的 (b) 支
    /// 收 virama 時不看 virama 之後有沒有東西——`क\u{200D}\u{094D}`（詞尾）、`क\u{200C}\u{094D}Journal`（接拉丁）、Tamil
    /// `ல\u{200D}\u{0BCD}ல` 全部通過、validate 綠，而 R8 是拒的：ya-phalaa／half-form 的每一個引用實例都是 `<C, ZWJ, H, C>`，
    /// halant 後面那個輔音才是 joiner 有作用的原因，沒有它 joiner 就是純隱形位元組差（confusable 通道——`क‍्` 與 `क्`
    /// 渲染完全相同，能各自進 names 再被 `--authorize` 升成 displayName）。所以：virama 之後要接**同一文字的字母**，
    /// 且只收有引用依據的 Devanagari／Bengali（Unicode ch. 12.2、Microsoft 兩份音節文法都只涵蓋這兩個），其餘 Indic 文字
    /// 依 `zero-instance-guards` 的紀律一列一列加。
    func testJoinerBeforeAViramaNeedsAFollowingLetterAndACitedScript() {
        for ok in ["র\u{200D}\u{09CD}যাব", "क\u{200D}\u{094D}ष", "ক\u{200C}\u{09CD}ষ", "Journal क\u{200D}\u{094D}ष"] {
            XCTAssertNil(NameIdentity.wellFormednessIssue(ok), ok.debugDescription)
        }
        for bad in ["क\u{200D}\u{094D}", "क\u{200C}\u{094D}", "क\u{200C}\u{094D}Journal", "Journal क\u{200D}\u{094D}",
                    "র\u{200D}\u{09CD}", "क\u{200D}\u{094D}\u{0967}", "क\u{200D}\u{094D}\u{093E}", "क\u{200D}\u{094D} ष",
                    "ல\u{200D}\u{0BCD}ல", "ക\u{200D}\u{0D4D}ക"] {
            XCTAssertNotNil(NameIdentity.wellFormednessIssue(bad), bad.debugDescription)
        }
    }

    /// **近重複訊息每組有上限**（R9 verify security 第 3 列）：同鍵組內 O(k²) 對、每對一則 `ValidationIssue`——由讀取路徑
    /// （`StoreHealth` → doctor／App）對未信任的 store 內容觸發，60,000 筆同名段就是 1.8×10⁹ 則訊息。每組最多逐一列 3 對，
    /// 其餘一句「另 M 對」；找到足夠的違反後就停止比對（結論已定，剩下的對不改變 verdict）。
    func testNearDuplicateIssuesPerGroupAreBounded() {
        let v = venue(names: Array(repeating: "Psychometrika", count: 40))
        let msgs = errors(v).filter { $0.contains("近重複") }
        XCTAssertLessThanOrEqual(msgs.count, 4, "\(msgs.count) 則")
        XCTAssertTrue(msgs.contains { $0.contains("另") && $0.contains("對") }, "要說還有幾對沒列：\(msgs)")
        // 只有一對時照舊逐一列，不多印摘要
        XCTAssertEqual(errors(venue(names: ["Psychometrika", "Psychometrika"])).filter { $0.contains("近重複") }.count, 1)
    }

    /// **上限也要綁住求值，不只訊息**（R10 verify 五席同指：Codex 第 4、logic 第 8、requirements 第 13、security 第 15、regression
    /// 第 17 列）：R10 的 `listed == 3` 只在非豁免對上遞增，一組全部成對豁免的同名沿革段（合法、零 issue）仍跑滿 k(k−1)/2 次
    /// `segmentsAreDisjoint`——真 binary 4,500 段 20 秒、全綠。求值也設上限（`pairsToEvaluate`，對應約 100 筆同名段）：超過即
    /// error（fail-closed——`add_names` 不帶時間欄位、造不出全豁免組，手改或匯入的 store 才造得出），上限內求值與 R10 逐位相同。
    func testNearDuplicateEvaluationIsBoundedEvenWhenEveryPairIsExempt() {
        func dated(_ n: Int) -> Venue {
            var segs: [TemporalValue<String>] = []
            for i in 0..<n {
                let start = String(1000 + 2 * i), end = String(1001 + 2 * i)
                segs.append(TemporalValue(value: "Sankhyā", range: DateRange(start: start, end: end)))
            }
            return Venue(key: "j", type: .periodical, names: Timeline(segs), authorized: [])
        }
        XCTAssertTrue(errors(dated(100)).isEmpty, "上限內：全豁免組零 issue，verdict 不變")
        // 求值上限的訊息用自己的開頭詞（R11 verify regression 第 31 列）：這一組沒有任何一對被判定違反，
        // `grep -c '近重複'`（第 25 列的量測）不該把它算成近重複
        let over = errors(dated(120)).filter { $0.contains("同名段過多") }
        XCTAssertEqual(over.count, 1, "\(errors(dated(120)))")
        XCTAssertTrue(over.first?.contains("未評估") == true && over.first?.contains("上限") == true, "\(over)")
        XCTAssertFalse(over[0].contains("近重複"), over[0])
    }

    /// **豁免前要驗段本身的區間**（R11 verify Codex 第 3 列）：`{start: 2000, end: 1900}` 與 `{1950–1960}`——只驗參與比較的
    /// `a.end`／`b.start` 是 ISO，`"1900" < "1950"` 就放行了一個倒置的無效區間。豁免要求兩段**每個在場的端點**都是 ISO 前綴、
    /// 且各自 start ≤ end（以較粗粒度截斷比）；證明不了區間有效就不授予豁免（放行條件 fail-closed，R7 的同一方向）。
    func testInvertedOrPartlyInvalidRangesDoNotUnlockTheExemption() {
        func v(_ a: DateRange, _ b: DateRange) -> Venue {
            Venue(key: "j", type: .periodical, names: Timeline([TemporalValue(value: "Sankhyā", range: a), TemporalValue(value: "Sankhyā", range: b)]), authorized: [])
        }
        XCTAssertTrue(errors(v(DateRange(start: "2000", end: "1900"), DateRange(start: "1950", end: "1960"))).contains { $0.contains("近重複") }, "倒置區間")
        XCTAssertTrue(errors(v(DateRange(start: "民國49", end: "1960"), DateRange(start: "1961", end: "1970"))).contains { $0.contains("近重複") }, "未參與比較的端點不合法")
        XCTAssertTrue(errors(v(DateRange(start: "1933", end: "1960"), DateRange(start: "1961", end: "1970"))).isEmpty, "合法沿革仍豁免")
        XCTAssertTrue(errors(v(DateRange(start: "1960", end: "1960-06"), DateRange(start: "1961"))).isEmpty, "同年內的細粒度 end 合法")
    }

    /// **「另至多 M 對」量的是未評估的對數，訊息要這麼說**（R10 verify regression 第 18 列）：R10 寫「未逐一列出」，但已評估而豁免的對
    /// 同樣沒被列出，M 少算它們——2 對豁免、3 對違反、第 6 對觸發上限時，未列出的是 7 對、未評估的是 6 對。
    func testNearDuplicateSummaryCountsUnevaluatedPairs() {
        func d(_ s: String, _ e: String) -> TemporalValue<String> {
            TemporalValue(value: "Sankhyā", range: DateRange(start: s, end: e))
        }
        let v = Venue(key: "j", type: .periodical, names: Timeline([
            d("1900", "1901"), d("1902", "1903"),
            TemporalValue(value: "Sankhyā"), TemporalValue(value: "Sankhyā"), TemporalValue(value: "Sankhyā")]), authorized: [])
        let msgs = errors(v).filter { $0.contains("近重複") }
        XCTAssertEqual(msgs.count, 4, "\(msgs)")
        XCTAssertTrue(msgs.contains { $0.contains("另至多 6 對未評估") }, "\(msgs)")
    }

    /// **同一 work 兩條邊指同一 venue 要看得見**（R10 verify requirements 第 5 列：`StoreHealth` 沒有這條掃描，`validate`／`doctor`／
    /// App 對它一律綠燈，使用者直到想 demote 才知道；D28）：warning 級——記錄合法，失效的是 repoint／demote 的前提（D25），
    /// 而修法只有手改 YAML（移除面：#572）。`zero-instance-guards` 第 26 列。
    func testTwoKeyEdgesToOneVenueAreAWarningOnTheWork() {
        var e = Entry(id: UUID(), citekey: "x2025", type: .periodicalArticle, title: "T")
        e.venues = [.key("a"), .key("b"), .key("a")]
        let w = e.validate().filter { $0.severity == .warning && $0.message.contains("同一 venue") }
        XCTAssertEqual(w.count, 1, "\(w)")
        let m = w.first?.message ?? ""
        XCTAssertTrue(m.contains("「a」") && m.contains("index 0、2") && m.contains("#572"), m)
        XCTAssertTrue(m.hasPrefix(Entry.duplicateVenueEdgePrefix), "家族前綴（StoreHealth 用它篩）：\(m)")
        e.venues = [.key("a"), .key("b"), .literal("a")]
        XCTAssertTrue(e.validate().filter { $0.message.contains("同一 venue") }.isEmpty, "literal 邊不算——那是尚未判定的誠實狀態")
    }

    /// **同一文字的補充區塊要在區塊表裡**（R8 verify 第 21／28／38 列）：Devanagari Extended（A8E0–A8FF，含 Lo 字母
    /// U+A8FB HEADSTROKE）、Devanagari Extended-A（11B00–11B5F）、Myanmar Extended-A／B（AA60–AA7F Khamti、
    /// A9E0–A9FF Shan／Tai Laing）回 nil，鄰接它們的 joiner 被拒，而 R7 的 doc 說「同一個文字的補充區塊本來就該在」。
    /// Vedic Extensions（1CD0–1CFF）刻意不加：多數是標記（走訪時本來就跳過），少數 Lo 字母沒有 joiner 用途，§5.7 記為邊界。
    func testExtensionBlocksJoinTheirScript() {
        XCTAssertEqual(NameIdentity.joinScript("\u{A8FB}"), NameIdentity.joinScript("क"))
        XCTAssertEqual(NameIdentity.joinScript("\u{11B00}"), NameIdentity.joinScript("क"))
        XCTAssertEqual(NameIdentity.joinScript("\u{AA60}"), NameIdentity.joinScript("\u{1000}"))
        XCTAssertEqual(NameIdentity.joinScript("\u{A9E0}"), NameIdentity.joinScript("\u{1000}"))
        XCTAssertNil(NameIdentity.joinScript("\u{1CE9}"), "Vedic Extensions 刻意不在表")
        for ok in ["क्\u{200D}\u{A8FB}", "\u{AA60}\u{200D}\u{AA61}", "\u{A9E0}\u{200C}\u{A9E1}"] {
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

    /// **不變式的訊息不得原樣迴送它剛拒掉的不可見字元**（R12 verify security 第 14 列：訊息在結構上保證帶著那個 scalar，
    /// 而 `displaySafe` 的列舉不逃 TAG／ZWSP／VS16／U+2800——R12 造的性質式逃脫只掛在 `verdictsRetired` 上）。
    func testInvariantMessagesEscapeTheOffendingScalar() {
        let msgs = errors(venue(names: ["Psycho\u{E0001}metrika", "Psycho\u{200B}metrika"]))
        XCTAssertEqual(msgs.count, 2, "\(msgs)")
        for m in msgs {
            XCTAssertFalse(m.unicodeScalars.contains { $0.value == 0xE0001 || $0.value == 0x200B }, "原樣迴送：\(m)")
        }
        XCTAssertTrue(msgs.contains { $0.contains("\\u{E0001}") } && msgs.contains { $0.contains("\\u{200B}") }, "\(msgs)")
    }

    /// 近重複訊息也要以性質逃脫（R13 verify security 第 12 列、requirements 第 18 列）：近重複對的兩筆只差空白類或 NFC 形，
    /// 而 `displaySafe` 不逃脫 NBSP——兩個字串印成逐像素相同，訊息卻叫人「留一筆」。
    func testNearDuplicateMessagesEscapeTheOffendingScalar() {
        let v = venue(names: ["Psychometrika", "Psychometrika\u{00A0}"], authorized: ["Psychometrika", "Psychometrika\u{00A0}"])
        let msgs = errors(v).filter { $0.contains("近重複") }
        XCTAssertFalse(msgs.isEmpty, "\(errors(v))")
        for m in msgs {
            XCTAssertFalse(m.unicodeScalars.contains { $0.value == 0x00A0 }, "原樣迴送 NBSP：\(m)")
            XCTAssertTrue(m.contains("\\u{00A0}"), m)
        }
    }

    /// **配對唯一性的第二半有掃描面了**（R13 verify DA 第 16 列；Claude 代裁 D36，`zero-instance-guards` 第 27 列）：同一 work 上
    /// ≥2 個正規化後不同的 confirmed literal 是 warning——真正造出它的路徑（work 合併）結構上不會點亮第一半（`Entry.validate()`
    /// 的重複 key 邊）的燈，R13 之前全庫零掃描面、只有 demote／repoint 撞 D23 時才知道。
    func testTwoConfirmedLiteralsForOneWorkIsAWarning() throws {
        func ref(_ work: String, _ literal: String) -> ProvenanceReference {
            ProvenanceReference(field: "resolution-confirmed",
                                value: ProvenanceReference.VerdictPairingValue(holderKind: .work, holder: work, literal: literal).encoded,
                                kind: .judgement(statement: "測試", restsOn: []))
        }
        var v = venue(names: ["Psychometrika"])
        v.references = [ref("w1", "Psychometrika"), ref("w1", "Psychometrika (Journal)"), ref("w2", "Psychometrika"), ref("w2", "PSYCHOMETRIKA")]
        let ws = v.validate().filter { $0.severity == .warning }.map(\.message)
        // D39（R14 verify Codex 第 3 列、requirements 第 5 列）：D23 的拒絕比**位元組**，所以 w2 那種只差位元組的兩筆也要有掃描面——
        // 第二類 warning，與第一類共用家族前綴、措辭分開（正規化後不同＝不變式的違反；只差位元組＝重複記錄，工具面寫不出）
        XCTAssertEqual(ws.count, 2, "w1 兩個不同、w2 只差位元組：\(ws)")
        let w = try XCTUnwrap(ws.first { $0.contains("「w1」") }, "\(ws)")
        XCTAssertTrue(w.contains("個正規化後不同的 confirmed literal") && w.contains("D23") && w.contains("YAML"), w)
        let w2b = try XCTUnwrap(ws.first { $0.contains("「w2」") }, "\(ws)")
        XCTAssertTrue(w2b.contains("只差位元組") && w2b.contains("D23") && w2b.contains("「Psychometrika」") && w2b.contains("「PSYCHOMETRIKA」"), w2b)
        XCTAssertTrue(ws.allSatisfy { $0.hasPrefix(Venue.confirmedLiteralAmbiguityPrefix) }, "兩類共用家族前綴（StoreHealth 用它篩）：\(ws)")
        XCTAssertTrue(errors(v).isEmpty, "是 warning 不是 error：\(errors(v))")
        // 逃脫以性質（`matchingKey` 會剝掉 Cf，所以兩個 literal 要在鍵上真的不同）
        v.references = [ref("w1", "Alpha\u{200B}Journal"), ref("w1", "Beta Journal")]
        let w2 = v.validate().filter { $0.severity == .warning }.map(\.message)
        XCTAssertEqual(w2.count, 1, "\(w2)")
        XCTAssertTrue(w2.first?.contains("\\u{200B}") == true && w2.first?.unicodeScalars.contains { $0.value == 0x200B } == false, "以性質逃脫：\(w2)")
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


    /// **兩族 per-record warning 的則數要有上限**（R14 verify logic 第 16 列、security 第 18 列：同一個 `validate()` 裡的近重複檢查
    /// 為了同一條理由——讀取路徑上對未信任的 store 內容跑——剛加了兩道上限，緊鄰的 D36 迴圈與 `Entry.validate()` 的重複邊迴圈
    /// 卻逐筆無上限）。每筆記錄最多列 20 則，其餘收成一句「另 N 筆未列出」（帶同一家族前綴，計數仍看得見）。
    func testPairingUniquenessWarningsAreCappedPerRecord() {
        func ref(_ work: String, _ literal: String) -> ProvenanceReference {
            ProvenanceReference(field: "resolution-confirmed",
                                value: ProvenanceReference.VerdictPairingValue(holderKind: .work, holder: work, literal: literal).encoded,
                                kind: .judgement(statement: "測試", restsOn: []))
        }
        var v = venue(names: ["Psychometrika"])
        v.references = (0..<25).flatMap { [ref("w\($0)", "Alpha \($0)"), ref("w\($0)", "Beta \($0)")] }
        let ws = v.validate().filter { $0.severity == .warning && $0.message.hasPrefix(Venue.confirmedLiteralAmbiguityPrefix) }.map(\.message)
        XCTAssertEqual(ws.count, 21, "20 則 ＋ 1 句概括：\(ws.count)")
        XCTAssertEqual(ws.filter { $0.contains("個正規化後不同的 confirmed literal") }.count, 20)
        XCTAssertTrue(ws.last?.contains("另有 5 筆 work 未列出") == true, ws.last ?? "")
        var e = Entry(id: UUID(), citekey: "x2025", type: .periodicalArticle, title: "T")
        e.venues = (0..<25).flatMap { [VenueRef.key("v\($0)"), VenueRef.key("v\($0)")] }
        let es = e.validate().filter { $0.severity == .warning && $0.message.hasPrefix(Entry.duplicateVenueEdgePrefix) }.map(\.message)
        XCTAssertEqual(es.count, 21, "\(es.count)")
        XCTAssertEqual(es.filter { $0.contains("條邊指向同一 venue") }.count, 20)
        XCTAssertTrue(es.last?.contains("另有 5 個 venue 未列出") == true, es.last ?? "")
    }
}
