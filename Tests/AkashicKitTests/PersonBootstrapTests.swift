import XCTest
import Foundation
@testable import AkashicCore
@testable import AkashicEntity

/// #34：從 literal 作者 bootstrap person 記錄。
final class PersonBootstrapTests: XCTestCase {

    private func entry(_ ck: String, _ authors: [String]) -> Entry {
        Entry(id: UUID(), citekey: ck, type: .periodicalArticle, title: "T",
              authors: authors.map { .literal($0) }, date: "2020")
    }

    // MARK: - 安全方向：寧可分割，絕不合併

    /// **機械可判的重排才合併。** `Last, First` ↔ `First Last` 是字串操作，不是猜測。
    // MARK: - R1-fix B4（DA-2）：寬鬆鍵命中的 literal 不建新 person——路由 pendingResolution

    func testInitialsHitAgainstExistingPersonRoutesToPendingResolution() {
        let existing = [Person(key: "chen-yi-hau",
                               names: PersonNames(variant: ["Chen, Yi-Hau"]))]
        var e = Entry(id: UUID(), citekey: "x2025", type: .periodicalArticle, title: "T")
        e.authors = [.literal("Chen, Y.-H.")]
        let r = PersonBootstrap.resolve(entries: [e], existing: existing, rejected: [], confirmed: [:])
        XCTAssertTrue(r.candidates.isEmpty,
                      "initials 命中既有 person 的 literal 不得被提案成新 person：\(r.candidates)")
        XCTAssertEqual(r.pendingResolution.count, 1)
        XCTAssertEqual(r.pendingResolution.first?.matchedKeys, ["chen-yi-hau"])
    }

    /// R3-fix R4-6a：鍵空間逐 tier 查找——literal 的 reorder 鍵撞上某名字的
    /// initials 鍵**不是**命中（resolver 不會提名），不得產生幽靈 pending。
    func testCrossSpaceKeyCollisionDoesNotCreatePhantomPending() {
        // R5 換上可鑑別 fixture（R4 抓到原 fixture 兩邊皆假、斷言退化 false==false）：
        // literal「Yh Chen」的 **reorder 鍵**（"chen yh"）恰等於 person
        // 「Chen, Yi-Hau」的 **initials 鍵**——合併空間實作會幽靈命中（bootstrap
        // pending 而 resolver 靜默），分空間實作兩面同構（皆無命中 → 建檔候選）。
        let existing = [Person(key: "chen-yi-hau",
                               names: PersonNames(variant: ["Chen, Yi-Hau"]))]
        var e = Entry(id: UUID(), citekey: "x2025", type: .periodicalArticle, title: "T")
        e.authors = [.literal("Yh Chen")]
        let r = PersonBootstrap.resolve(entries: [e], existing: existing,
                                        rejected: [], confirmed: [:])
        let rr = PersonResolver.resolve(entries: [e], people: existing,
                                        rejected: [], confirmed: [:])
        let resolverNominates = !rr.candidates.isEmpty || !rr.ambiguities.isEmpty
        XCTAssertEqual(!r.pendingResolution.isEmpty, resolverNominates,
                       "bootstrap pending ⟺ resolver 有提名——兩份空間不得分岔：" +
                       "pending=\(r.pendingResolution)，resolver=\(rr)")
        XCTAssertFalse(resolverNominates, "本 fixture 的預期：兩面皆無命中")
        XCTAssertEqual(r.candidates.count, 1, "無命中 → 建檔候選：\(r)")
    }

    /// R3-fix R4-6b：resolver 正以 confirmed-elsewhere 提名的 literal，bootstrap
    /// 不得鑄成新 person。
    func testConfirmedElsewhereLiteralIsNotMintedAsNewPerson() {
        let existing = [Person(key: "hsu-yung-fong",
                               names: PersonNames(variant: ["徐永豐"]))]
        var e = Entry(id: UUID(), citekey: "y2024", type: .periodicalArticle, title: "T")
        e.authors = [.literal("Yung-Fong Hsu")]
        let confirmed: [ResolutionPairing: String] = [
            ResolutionPairing(holderKind: .work, holder: "x2020",
                              literal: "Yung-Fong Hsu",
                              judgedKey: "hsu-yung-fong"): ResolutionLedger.personRule]
        let r = PersonBootstrap.resolve(entries: [e], existing: existing,
                                        rejected: [], confirmed: confirmed)
        XCTAssertTrue(r.candidates.isEmpty,
                      "confirmed-elsewhere 提名中的 literal 不得建檔：\(r.candidates)")
        XCTAssertEqual(r.pendingResolution.first?.matchedKeys, ["hsu-yung-fong"])
    }

    /// R5（R4L-2）：identity 命中但非 normalize 相等（重排形）→ pending 而非隱形；
    /// 否決後回歸建檔（先前是兩面皆不可行動的死路）。
    func testReorderEquivalentLiteralRoutesToPendingNotInvisible() {
        let existing = [Person(key: "cheng-che",
                               names: PersonNames(variant: ["Che Cheng"]))]
        var e = Entry(id: UUID(), citekey: "x2025", type: .periodicalArticle, title: "T")
        e.authors = [.literal("Cheng Che")]   // 重排形：identity 相等、normalize 不等
        let r = PersonBootstrap.resolve(entries: [e], existing: existing,
                                        rejected: [], confirmed: [:])
        XCTAssertTrue(r.candidates.isEmpty)
        XCTAssertEqual(r.pendingResolution.first?.matchedKeys, ["cheng-che"],
                       "重排等價要以 pending 可見，不得隱形：\(r)")
        // 否決該配對後回歸建檔候選（死路解除）
        let rejected: Set<ResolutionPairing> = [
            ResolutionPairing(holderKind: .work, holder: "x2025",
                              literal: "Cheng Che", judgedKey: "cheng-che")]
        let r2 = PersonBootstrap.resolve(entries: [e], existing: existing,
                                         rejected: rejected, confirmed: [:])
        XCTAssertEqual(r2.candidates.count, 1, "全否決後回歸建檔：\(r2)")
    }

    /// R2-fix R3-4：部分否決**不**讓同一 literal 分裂成「建檔候選＋pending 並排」。
    func testPartialRejectionKeepsWholeGroupPending() {
        let existing = [Person(key: "chen-yi-hau",
                               names: PersonNames(variant: ["Chen, Yi-Hau"]))]
        var e1 = Entry(id: UUID(), citekey: "x2025", type: .periodicalArticle, title: "T")
        e1.authors = [.literal("Chen, Y.-H.")]
        var e2 = Entry(id: UUID(), citekey: "y2024", type: .periodicalArticle, title: "U")
        e2.authors = [.literal("Chen, Y.-H.")]
        // 只否決 x2025 那筆配對——y2024 的配對仍未出清
        let rejected: Set<ResolutionPairing> = [
            ResolutionPairing(holderKind: .work, holder: "x2025",
                              literal: "Chen, Y.-H.", judgedKey: "chen-yi-hau")]
        let r = PersonBootstrap.resolve(entries: [e1, e2], existing: existing,
                                        rejected: rejected, confirmed: [:])
        XCTAssertTrue(r.candidates.isEmpty,
                      "部分否決不得產生建檔候選：\(r.candidates)")
        XCTAssertEqual(r.pendingResolution.count, 1)
        XCTAssertEqual(r.pendingResolution.first?.occurrences, 2, "整組扣住")
    }

    func testRejectedLoosePairingReturnsLiteralToBootstrap() {
        // 全部寬鬆配對都被否決後，literal 回到可建檔——生命週期閉環
        let existing = [Person(key: "chen-yi-hau",
                               names: PersonNames(variant: ["Chen, Yi-Hau"]))]
        var e = Entry(id: UUID(), citekey: "x2025", type: .periodicalArticle, title: "T")
        e.authors = [.literal("Chen, Y.-H.")]
        let rejected: Set<ResolutionPairing> = [
            ResolutionPairing(holderKind: .work, holder: "x2025",
                              literal: "Chen, Y.-H.", judgedKey: "chen-yi-hau")]
        let r = PersonBootstrap.resolve(entries: [e], existing: existing, rejected: rejected, confirmed: [:])
        XCTAssertTrue(r.pendingResolution.isEmpty)
        XCTAssertEqual(r.candidates.count, 1, "\(r)")
    }

    func testReorderedFormsMergeIntoOneCandidate() throws {
        let cs = PersonBootstrap.candidates(
            entries: [entry("a", ["Che Cheng"]), entry("b", ["Cheng, Che"])], existing: [], rejected: [], confirmed: [:])
        XCTAssertEqual(cs.count, 1)
        let c = try XCTUnwrap(cs.first)
        XCTAssertEqual(c.names.sorted(), ["Che Cheng", "Cheng, Che"])
        XCTAssertEqual(c.occurrences, 2)
    }

    /// **縮寫不與全名合併。** `Cheng, C` 看起來像 `Cheng, Che`，但也可能是 `Cheng, Chao`。
    /// 過度合併不可回復——兩個人被併成一個，區別就此消失且沒有任何訊號。
    ///
    /// **#547 改了這條測試的斷言，但沒有削弱它守的東西。** 原本斷言
    /// `candidates.count == 2`（「分開，讓人決定」）；現在兩者一起被扣進
    /// `pendingMutual`。守的性質仍是**不得自動合併**——變的是「讓人決定」怎麼實現：
    /// 從「各自建檔、之後用 resolve-divergence 合併」（事後、不可逆）換成
    /// 「建檔前先問」（事前、additive）。理由見
    /// `.claude/rules/disambiguate-before-irreversible-writes.md`：安全預設是
    /// 「你**無法**消歧時該往哪邊倒」，不是「你**可以**消歧卻不做」的許可。
    func testAbbreviationDoesNotMergeWithFullName() {
        let r = PersonBootstrap.resolve(
            entries: [entry("a", ["Cheng, Che"]), entry("b", ["Cheng, C"])],
            existing: [], rejected: [], confirmed: [:])
        XCTAssertTrue(r.candidates.isEmpty,
                      "已識別的歧義不得在建檔前被略過：\(r.candidates.map(\.key))")
        XCTAssertEqual(r.pendingMutual.count, 1, "兩者要被收在同一組待判：\(r.pendingMutual)")
        XCTAssertEqual(Set(r.pendingMutual.first?.names ?? []), ["Cheng, Che", "Cheng, C"],
                       "**兩個寫法都要看得見**——合併成一個名字就是本測試要防的那件事")
    }

    /// 連字號差異不合併——`Jeng-Min` 與 `Jeng Min` 可能是同一人也可能不是，
    /// 去掉連字號就等於替人決定了。
    ///
    /// #547：同上，改為「扣住並列出兩個寫法」而非「各自建檔」。
    func testHyphenVariantsDoNotMerge() {
        let r = PersonBootstrap.resolve(
            entries: [entry("a", ["Jeng-Min Chiou"]), entry("b", ["Jeng Min Chiou"])],
            existing: [], rejected: [], confirmed: [:])
        XCTAssertTrue(r.candidates.isEmpty, "\(r.candidates.map(\.key))")
        XCTAssertEqual(r.pendingMutual.count, 1)
        XCTAssertEqual(Set(r.pendingMutual.first?.names ?? []),
                       ["Jeng-Min Chiou", "Jeng Min Chiou"],
                       "連字號差異不得被摺掉——兩個寫法都要原樣留著給人看")
    }

    /// 大小寫與空白差異**是**機械可判的，合併。
    func testCaseAndWhitespaceVariantsMerge() throws {
        let cs = PersonBootstrap.candidates(
            entries: [entry("a", ["Chun-Houh Chen"]), entry("b", ["chun-houh  chen"])],
            existing: [], rejected: [], confirmed: [:])
        XCTAssertEqual(cs.count, 1)
        XCTAssertEqual(try XCTUnwrap(cs.first).occurrences, 2)
    }

    // MARK: - 不重複建立

    /// 已存在的 person 不再產出候選——它們的 alias 已在 `PersonResolver` 的比對範圍內，
    /// 再造一個就是在製造重複。
    func testExistingPersonIsNotProposedAgain() {
        let cs = PersonBootstrap.candidates(
            entries: [entry("a", ["Che Cheng"])],
            existing: [Person(key: "cheng-che", names: ["Che Cheng", "鄭澈"])], rejected: [], confirmed: [:])
        XCTAssertTrue(cs.isEmpty, "\(cs)")
    }

    /// 既有 person 的**任一** alias 命中就算數（不只第一個）。
    func testAnyExistingAliasSuppresses() {
        let cs = PersonBootstrap.candidates(
            entries: [entry("a", ["Cheng, Che"])],
            existing: [Person(key: "cheng-che", names: ["鄭澈", "Che Cheng"])], rejected: [], confirmed: [:])
        XCTAssertTrue(cs.isEmpty, "重排形式也要被既有 alias 吸收：\(cs)")
    }

    /// 機構名（#6 的 `{...}` 標記）不是人——不建 person。
    func testCorporateNamesAreNotPeople() {
        let cs = PersonBootstrap.candidates(
            entries: [entry("a", [CorporateName.mark("World Health Organization")])],
            existing: [], rejected: [], confirmed: [:])
        XCTAssertTrue(cs.isEmpty, "\(cs)")
    }

    // MARK: - key 生成

    func testSuggestedKeyIsSurnameFirst() throws {
        let cs = PersonBootstrap.candidates(entries: [entry("a", ["Yi-Hau Chen"])], existing: [], rejected: [], confirmed: [:])
        XCTAssertEqual(try XCTUnwrap(cs.first).key, "chen-yi-hau")
    }

    /// **這條測試的名字說的不是它現在守的東西——留著是因為它守的那個更重要。**
    ///
    /// #547 verify（DA 跑 `MUT-C` mutation）證實：把 `LooseNameKey` 的兩個鍵空間
    /// 合成一張表時（＝`PersonBootstrap.resolve` 的註解自己點名要防的「幽靈命中」，
    /// 也是本檔 `R3-fix R4-6` 記過的真實 bug），**全 repo 只有這一條測試會紅**，
    /// 而且靠的正是這組 fixture：`Chen, Y-H` 的 **initials** 鍵 `chen yh` 恰等於
    /// `Chen, YH` 的 **reorder** 鍵。合表後兩者共鍵 → `pendingMutual` 非空 → 紅。
    ///
    /// **所以不要換掉這組 fixture。** #547 verify 的 regression／requirements 兩個 lens
    /// 都建議換成 `Jörg Müller` ／ `Jorg Muller`（那兩個確實會撞 slug），但實測它們
    /// 在合表後**零共鍵、不會紅**——換過去等於補一個洞、同時安靜開另一個。
    ///
    /// **它不再守「撞號加序號」，那一半由
    /// `testSuggestedKeyAccumulatesSuffixWithinOneRun` 接手**（`chen-y-h` ≠ `chen-yh`，
    /// 本 fixture 從不進入 `taken.contains(base)` 分支，那三個斷言對 suffix 恆真）。
    func testKeyCollisionGetsSuffixNotMerge() {
        let r = PersonBootstrap.resolve(
            entries: [entry("a", ["Chen, Y-H"]), entry("b", ["Chen, YH"])],
            existing: [], rejected: [], confirmed: [:])
        XCTAssertTrue(r.pendingMutual.isEmpty,
                      "本 fixture 的前提是兩者**不**共鍵：\(r.pendingMutual)")
        XCTAssertEqual(r.candidates.count, 2)
        XCTAssertEqual(Set(r.candidates.map(\.key)).count, 2,
                       "key 必須唯一：\(r.candidates.map(\.key))")
    }

    func testKeyAvoidsExistingPersonKeys() throws {
        let cs = PersonBootstrap.candidates(
            entries: [entry("a", ["Che Cheng"])],
            existing: [Person(key: "cheng-che", names: ["別人"])], rejected: [], confirmed: [:])
        XCTAssertEqual(cs.count, 1)
        XCTAssertNotEqual(try XCTUnwrap(cs.first).key, "cheng-che", "不得與既有 key 相同")
    }

    // MARK: - 排序

    /// 出現次數多的先——處理它們的投報率最高。
    func testCandidatesSortedByOccurrence() {
        let cs = PersonBootstrap.candidates(
            entries: [entry("a", ["Rare Person"]),
                      entry("b", ["Common Person"]), entry("c", ["Common Person"])],
            existing: [], rejected: [], confirmed: [:])
        XCTAssertEqual(cs.map(\.occurrences), [2, 1])
    }

    // MARK: - 產不出 ASCII key 的作者（#238）

    /// **變音符號的歐洲名是直接的 bug，不是限制。**
    ///
    /// `StoreKey.pattern` 是純 ASCII，而 `PersonBootstrap.slug` 保留任何 Unicode 字母，
    /// 於是 `Jörg` → `jörg` → `isValid` 失敗 → 整組候選被 `compactMap` **靜默丟棄**。
    ///
    /// 而解法**已經在 repo 裡**：`Citekey.slug` 做 `.diacriticInsensitive` 摺疊。
    /// 同一個 repo 有兩份 slug、行為不同，這是其中一份沒跟上。
    func testDiacriticNamesProduceASCIIKeys() {
        let cs = PersonBootstrap.candidates(
            entries: [entry("a", ["Jörg Müller"]),
                      entry("b", ["Hans Schneeweiß"]),
                      entry("c", ["Patricia É. Brosseau-Liard"])],
            existing: [], rejected: [], confirmed: [:])
        XCTAssertEqual(cs.count, 3, "三個歐洲名都該產得出 key，實際：\(cs.map(\.key))")
        for c in cs {
            XCTAssertTrue(StoreKey.isValid(c.key),
                          "key「\(c.key)」不符 StoreKey——摺疊沒做乾淨")
        }
    }

    /// **CJK 是機械上無解，所以正確處置是「回報」不是「丟棄」。**
    ///
    /// `陳君厚` 沒有唯一正確的羅馬化——機器不該猜。但**靜默消失**與「需要你指定 key」
    /// 是兩件完全不同的事：前者讓使用者以為那些作者不存在。
    ///
    /// 這與 #231 是同一個形狀：系統知道自己遇到了決定點，然後把那個知識丟掉。
    func testUnkeyableNamesAreReportedNotDropped() {
        let r = PersonBootstrap.resolve(
            entries: [entry("a", ["陳君厚"]), entry("b", ["Che Cheng"])],
            existing: [], rejected: [], confirmed: [:])
        XCTAssertEqual(r.candidates.map(\.key), ["cheng-che"],
                       "產得出 key 的照常出候選")
        XCTAssertEqual(r.unkeyable.map(\.names), [["陳君厚"]],
                       "產不出 key 的必須被回報，不是消失：\(r.unkeyable)")
        XCTAssertEqual(r.unkeyable.first?.occurrences, 1)
    }

    /// `candidates()` 是 `resolve()` 的 thin wrapper——**不寫第二支遍歷**。
    /// 兩支會分岔，而分岔的方式通常是其中一支忘了某個排除條件。
    func testCandidatesIsAThinWrapperOverResolve() {
        let es = [entry("a", ["陳君厚"]), entry("b", ["Che Cheng"]), entry("c", ["Jörg Müller"])]
        XCTAssertEqual(PersonBootstrap.candidates(entries: es, existing: [], rejected: [], confirmed: [:]),
                       PersonBootstrap.resolve(entries: es, existing: [], rejected: [], confirmed: [:]).candidates)
    }

    /// 產出的 Person 直接可寫——names 就是這一組的所有寫法。
    func testPersonsForProducesUsableRecords() throws {
        let cs = PersonBootstrap.candidates(
            entries: [entry("a", ["Che Cheng"]), entry("b", ["Cheng, Che"])], existing: [], rejected: [], confirmed: [:])
        let ps = PersonBootstrap.personsFor(cs)
        XCTAssertEqual(ps.count, 1)
        XCTAssertEqual(try XCTUnwrap(ps.first).names.all.count, 2, "兩種寫法都要成為 alias")
    }

    /// #226：**重排等價不得取決於姓名的字典序。**
    ///
    /// `identity` 宣稱做「重排這一種機械等價」，但舊版只在逗號形上呼叫 `reordered`，
    /// 於是兩種輸入產生**不同的候選集**：
    ///
    /// - 逗號形 `Liang, Yu-Jen` → `min("liang, yu-jen", "yu-jen liang")` = `"liang, yu-jen"`
    ///   ——**含逗號的那個**，而直式永遠產不出它
    /// - 直式 `Yu-Jen Liang` → 只有 `"yu-jen liang"`
    ///
    /// 兩者相等的條件是 `mk(直式) < mk(逗號形)`，也就是「名的字典序 < 姓的字典序」。
    /// 那是巧合不是不變式——真實 store 869 個 `Family, Given` 形有 **482 個（55.5%）**
    /// 落在失效側，`bootstrap-people` 為同一個人靜默建出兩個候選。
    ///
    /// 這些 fixture **不是隨手挑的**：`Cheng` / `Hsieh` 兩組在舊版就會過（名 < 姓），
    /// 其餘四組是 issue 從真實 store 量出來的失效側。同時放進來，才能讓「只修一半」
    /// 的實作被抓到。
    func testIdentityIsSymmetricRegardlessOfNameOrdering() {
        let pairs = [
            ("Cheng, Che", "Che Cheng"),          // 舊版已過（che… < cheng…）
            ("Hsieh, Fushing", "Fushing Hsieh"),  // 舊版已過
            ("Liang, Yu-Jen", "Yu-Jen Liang"),    // 舊版失敗
            ("Chang, Y-H.", "Y-H. Chang"),        // 舊版失敗
            ("Guan, Yongtao", "Yongtao Guan"),    // 舊版失敗
            ("Huang, Su-Yun", "Su-Yun Huang"),    // 舊版失敗
        ]
        for (inverted, direct) in pairs {
            XCTAssertEqual(PersonBootstrap.identity(inverted), PersonBootstrap.identity(direct),
                           "「\(inverted)」與「\(direct)」是同一個名字的兩種寫法，"
                           + "identity 必須相等——而不是取決於誰的字典序比較小")
        }
    }

    /// 對偶：**不同的人不得因為這個修法而被合併**。
    ///
    /// 放寬等價判準最容易的失敗方式是放寬過頭。姓名互換後恰好撞到另一個真人是
    /// 可能的（`Chen Wei` / `Wei Chen` 可以是兩個人），但那是**這條等價本來就有的
    /// 代價**（舊版在字典序有利時也會合併），不是本次新增的。這裡釘住的是：
    /// 完全無關的名字不得合併。
    func testIdentityStillSeparatesUnrelatedNames() {
        XCTAssertNotEqual(PersonBootstrap.identity("Che Cheng"),
                          PersonBootstrap.identity("Fushing Hsieh"))
        XCTAssertNotEqual(PersonBootstrap.identity("Guan, Yongtao"),
                          PersonBootstrap.identity("Huang, Su-Yun"))
        // 單一 token（無姓名可換）不得與任何雙 token 名字碰撞
        XCTAssertNotEqual(PersonBootstrap.identity("鄭澈"),
                          PersonBootstrap.identity("Che Cheng"))
    }

    /// 端到端：兩種寫法必須併成**一個**候選，而不是兩個。
    func testBootstrapDoesNotSplitOneAuthorIntoTwoCandidates() {
        let cs = PersonBootstrap.candidates(
            entries: [entry("a", ["Guan, Yongtao"]), entry("b", ["Yongtao Guan"])],
            existing: [], rejected: [], confirmed: [:])
        XCTAssertEqual(cs.count, 1,
                       "同一個人的兩種寫法裂成 \(cs.count) 個候選："
                       + "\(cs.map(\.names))")
        XCTAssertEqual(cs.first?.names.count, 2, "兩種寫法都要成為 alias")
    }

    // MARK: - record-identity（#241 task 7.1）：key 配發後永不重算

    /// spec「Re-running key assignment does not change existing keys」：對記錄已帶
    /// key 的 store 再跑一次指派——既有 key 一個都不變、已歸戶的名字不再產出候選。
    /// 指派只發生在**新**候選身上（key MAY 在配發當下由內容推導，此後沿用）。
    func testRerunningAssignmentDoesNotChangeExistingKeys() {
        // 帶後綴的 key 是前一輪指派順序的產物——重跑也不得動它
        let existing = [
            Person(key: "chen-wei", names: PersonNames(variant: ["Chen Wei"])),
            Person(key: "chen-wei-2", names: PersonNames(variant: ["Wei Chen"])),
        ]
        let es = [entry("a", ["Chen Wei"]), entry("b", ["Wei Chen"]),
                  entry("c", ["Brand New Author"])]
        let report = PersonBootstrap.resolve(entries: es, existing: existing, rejected: [], confirmed: [:])
        XCTAssertEqual(report.candidates.map(\.key), ["author-brand-new"],
                       "已歸戶的名字不得再產出候選——那等於對既有記錄重新指派")
        // 第二輪（模擬候選已建檔）：零新候選、既有 key 集合不變
        let applied = existing + PersonBootstrap.personsFor(report.candidates)
        let second = PersonBootstrap.resolve(entries: es, existing: applied, rejected: [], confirmed: [:])
        XCTAssertTrue(second.candidates.isEmpty, "\(second.candidates.map(\.key))")
        XCTAssertEqual(Set(applied.map(\.key)),
                       ["chen-wei", "chen-wei-2", "author-brand-new"],
                       "沒有任何既有 key 改變")
    }

    /// spec「A collision suffix is a fact about assignment order, not about the
    /// record」：後綴不得被任何判斷邏輯讀取——同一個 literal 對到 `chen-wei` 與
    /// `chen-wei-2` 時是**歧義**（交給人），不得因「無後綴看起來比較正宗」自動挑
    /// base key。
    func testCollisionSuffixCarriesNoJudgmentWeight() {
        let existing = [
            Person(key: "chen-wei", names: PersonNames(variant: ["Chen Wei"])),
            Person(key: "chen-wei-2", names: PersonNames(variant: ["Chen Wei"])),
        ]
        let r = PersonResolver.resolve(
            entries: [entry("x", ["Chen Wei"])], people: existing, rejected: [], confirmed: [:])
        XCTAssertTrue(r.candidates.isEmpty,
                      "兩個同名記錄不得自動歸戶到其中一個：\(r.candidates)")
        XCTAssertEqual(r.ambiguities.count, 1, "必須以歧義呈現、交給人判斷")
        XCTAssertEqual(Set(r.ambiguities.first?.personKeys ?? []),
                       ["chen-wei", "chen-wei-2"],
                       "兩個候選並列，後綴不構成任何排序或偏好")
    }

    // MARK: - #547：彼此互為異寫、而兩邊都還沒有記錄

    /// 三種 Dweck 寫法**至少有一列同時涵蓋三者**，而不是三個各自獨立的提案。
    ///
    /// 行為 oracle（#547 diagnosis）：只替其中一種建檔之後，另外兩種立刻被
    /// `pendingResolution` 標示 —— 也就是 `LooseNameKey` 本來就認得三者是一組。
    /// 差別只在那張索引**只由既有 person 建成**，所以「兩邊都還沒有記錄」時
    /// 完全沉默。本組測試釘住補上的那一半。
    ///
    /// **斷言從「恰好一組」放寬成「有一列涵蓋三者」**（#547 批次二，逐鍵成組）：
    /// 一列＝一個共鍵理由，而這三個寫法有兩個不同的理由——`initials:dweck cs`
    /// 連起三者，`reorder:carol dweck s` ＋ `initials:carol sd` 連起兩個全名形。
    /// 兩列都是真的，且第二列是**更強的證據**（全名 token 集合相等）。逼它們合併回
    /// 一列就是把那個強弱差異丟掉——而判定要的正是證據強度。
    func testMutualAliasesAmongUnrecordedLiteralsLandInOneGroup() throws {
        let entries = [
            entry("a2020", ["Carol S Dweck"]),
            entry("b2021", ["Carol S. Dweck"]),
            entry("c2022", ["C. S. Dweck"]),
        ]
        let r = PersonBootstrap.resolve(entries: entries, existing: [],
                                        rejected: [], confirmed: [:])
        let all = try XCTUnwrap(
            r.pendingMutual.first { Set($0.names) == ["Carol S Dweck", "Carol S. Dweck", "C. S. Dweck"] },
            "必須有一列同時涵蓋三種寫法：\(r.pendingMutual)")
        XCTAssertEqual(all.occurrences, 3, "occurrences 是該列全部作者位的總和")
        XCTAssertEqual(all.sharedKeys, ["initials:dweck cs"],
                       "該列的鍵要**恰好**是連起這三者的那一個，不是「碰到本組的所有鍵」")

        // 每一列的成員都不只一個——單獨一個寫法不構成「彼此共鍵」
        for g in r.pendingMutual {
            XCTAssertGreaterThanOrEqual(g.names.count, 2, "一列至少兩個寫法：\(g)")
        }
    }

    /// **扣住不建檔**（#547 D1(b)）——只回報不解決傷害：`--apply` 照樣會鑄三個身分。
    func testMutualAliasGroupMembersAreWithheldFromCandidates() {
        let entries = [
            entry("a2020", ["Carol S Dweck"]),
            entry("b2021", ["Carol S. Dweck"]),
            entry("c2022", ["C. S. Dweck"]),
        ]
        let r = PersonBootstrap.resolve(entries: entries, existing: [],
                                        rejected: [], confirmed: [:])
        XCTAssertTrue(r.candidates.isEmpty,
                      "互為異寫的組不得同時出現在建檔候選裡：\(r.candidates.map(\.key))")
        XCTAssertTrue(PersonBootstrap.personsFor(r.candidates).isEmpty,
                      "型別層也要擋住——personsFor 只吃 candidates")
    }

    /// **既有 person 的碰撞優先，新桶不得接管。**
    ///
    /// 這一條保護的是使用者 2026-09-09 指名的方向（「建檔前要確認庫裡是不是已經
    /// 有這個人」）：新桶只**增加**一種提名，讓既有的 17 筆在沒人注意時變少是回歸。
    func testExistingPersonCollisionStillRoutesToPendingResolutionNotMutual() {
        let existing = [Person(key: "chen-yi-hau",
                               names: PersonNames(variant: ["Chen, Yi-Hau"]))]
        let entries = [
            entry("x2025", ["Chen, Y.-H."]),          // 與既有 person 共鍵
            entry("a2020", ["Carol S Dweck"]),        // 彼此共鍵
            entry("b2021", ["C. S. Dweck"]),
        ]
        let r = PersonBootstrap.resolve(entries: entries, existing: existing,
                                        rejected: [], confirmed: [:])
        XCTAssertEqual(r.pendingResolution.count, 1,
                       "與既有 person 共鍵者必須留在 pendingResolution：\(r)")
        XCTAssertEqual(r.pendingResolution.first?.matchedKeys, ["chen-yi-hau"])
        let mutualNames = Set(r.pendingMutual.flatMap(\.names))
        XCTAssertFalse(mutualNames.contains("Chen, Y.-H."),
                       "已由 pendingResolution 承接的成員不得同時出現在新桶：\(mutualNames)")
        XCTAssertEqual(r.pendingMutual.count, 1, "Dweck 那組仍要被收攏")
    }

    /// 閉環①：判定**是同一人**，`add-person --name …` 補齊 alias 之後該組消失。
    /// 三個寫法全成 `exactAliases` → bootstrap 隱形，交給 `resolve-people` 以 exact 提名。
    func testAddingAliasesRetiresTheMutualGroup() {
        let existing = [Person(key: "dweck-carol-s",
                               names: PersonNames(variant: ["Carol S Dweck",
                                                            "Carol S. Dweck",
                                                            "C. S. Dweck"]))]
        let entries = [
            entry("a2020", ["Carol S Dweck"]),
            entry("b2021", ["Carol S. Dweck"]),
            entry("c2022", ["C. S. Dweck"]),
        ]
        let r = PersonBootstrap.resolve(entries: entries, existing: existing,
                                        rejected: [], confirmed: [:])
        XCTAssertTrue(r.pendingMutual.isEmpty, "補齊 alias 後不該再有待裁決組：\(r.pendingMutual)")
        XCTAssertTrue(r.candidates.isEmpty, "也不得回流成建檔候選：\(r.candidates.map(\.key))")
    }

    /// 閉環②：判定**是不同人**，各自建檔之後同樣消失。
    /// 兩種判定都要有出口 —— 少了這一條，「不同人」會被困在桶裡出不去。
    func testJudgingThemAsDifferentPeopleAlsoRetiresTheGroup() {
        let existing = [
            Person(key: "dweck-carol-s", names: PersonNames(variant: ["Carol S Dweck"])),
            Person(key: "dweck-c-s", names: PersonNames(variant: ["C. S. Dweck"])),
        ]
        let entries = [
            entry("a2020", ["Carol S Dweck"]),
            entry("c2022", ["C. S. Dweck"]),
        ]
        let r = PersonBootstrap.resolve(entries: entries, existing: existing,
                                        rejected: [], confirmed: [:])
        XCTAssertTrue(r.pendingMutual.isEmpty,
                      "各自建檔後兩者皆是 exact alias，不該再被提名：\(r.pendingMutual)")
        XCTAssertTrue(r.candidates.isEmpty)
    }

    // MARK: - #547 verify V4：撞號加序號的覆蓋（原本被 fixture 更換弄丟）

    /// **同一次執行內兩個候選撞 slug → 第二個拿 `-2`。**
    ///
    /// `resolve()` 的 `reduce` 迴圈**逐候選累積** `takenKeys`，所以這個性質不是
    /// 「與既有 person 撞」而是「與同一批的前一個候選撞」。#547 verify 掃過全樹，
    /// 那時**沒有任何測試守它**——另外三個看似相關的都不是：
    ///
    /// | 測試 | 走的是哪條 |
    /// |---|---|
    /// | `testKeyAvoidsExistingPersonKeys` | `taken` 由 **existing** 種下，且只斷言 `!=` |
    /// | `testRerunningAssignmentDoesNotChangeExistingKeys` | `chen-wei-2` 是**既有記錄** |
    /// | `testCollisionSuffixCarriesNoJudgmentWeight` | 走 `PersonResolver`，不是 bootstrap |
    ///
    /// 直接單元測 `suggestedKey(from:taken:)`——不繞過 `resolve()` 的其餘分流，
    /// 因為那正是上一次覆蓋消失的原因（fixture 被別的機制吃掉，測試卻還是綠的）。
    ///
    /// **用 `XCTUnwrap` 不用 `!`**：本測試自己的負控踩過——序號迴圈被拿掉時
    /// `suggestedKey` 回 `nil`，斷言正確地紅了，但下一行的 `second!` 讓**行程崩潰**
    /// （`Exited with unexpected signal code 5`），於是沒有 `Executed N tests` 摘要，
    /// 「守衛失效」與「harness 崩潰」在輸出上無法區分。同 `DropAuthorTests` 記過的形狀。
    func testSuggestedKeyAccumulatesSuffixWithinOneRun() throws {
        var taken = Set<String>()
        let first = try XCTUnwrap(PersonBootstrap.suggestedKey(from: "Jorg Muller", taken: taken))
        XCTAssertEqual(first, "muller-jorg")
        taken.insert(first)                        // 模擬 reduce 迴圈的逐候選累積

        // 變音符號摺疊後 slug 相同——這正是「兩個不同的名字產生同一個 slug」
        let second = try XCTUnwrap(PersonBootstrap.suggestedKey(from: "Jörg Müller", taken: taken),
                                   "撞 slug 時第二個要拿 -2，而不是回 nil")
        XCTAssertEqual(second, "muller-jorg-2", "撞 slug 時第二個要拿 -2，而不是覆寫")
        taken.insert(second)

        // 第三個也撞（只有名字帶變音符號，姓不帶）——序號要繼續往上，不是停在 -2
        let third = PersonBootstrap.suggestedKey(from: "Jörg Muller", taken: taken)
        XCTAssertEqual(third, "muller-jorg-3", "序號要逐個累積：\(third ?? "nil")")

        // 對照：**沒**撞的名字不該拿到序號。`Mueller` 摺疊後仍是 `mueller`（`ue` 不折成 `u`），
        // 所以它是另一個 base，不進 suffix 分支。
        XCTAssertEqual(PersonBootstrap.suggestedKey(from: "Jorg Mueller", taken: taken),
                       "mueller-jorg", "不撞號的名字不得被加序號")
    }

    /// 序號有上界，且**用完是回 `nil` 不是回一個撞號的 key**。
    func testSuggestedKeyGivesUpRatherThanCollide() {
        var taken: Set<String> = ["muller-jorg"]
        for i in 2...99 { taken.insert("muller-jorg-\(i)") }
        XCTAssertNil(PersonBootstrap.suggestedKey(from: "Jorg Muller", taken: taken),
                     "99 個都被占用時必須回 nil（由 resolve 記進 unkeyable），不得回撞號的 key")
    }

    // MARK: - #547 verify V16：門檻要在扣留之前生效

    /// **低於門檻的鄰居不得扣住高於門檻的候選。**
    ///
    /// 先前扣留發生在 `--min-occurrences` 過濾**之前**，於是使用者明講「只處理 ≥N 的」，
    /// 卻被一個他說了不要處理的寫法擋下。實測 live store 門檻 10 時仍有 16 組被扣住，
    /// 其中 `Daniel McNeish`（18 次）被 `Daniel Muise`（2 次）單獨拖住——而那兩個是
    /// 不同的人。那個否決權沒有來源。
    func testSubThresholdNeighbourDoesNotWithholdAnAboveThresholdCandidate() {
        // 三筆 `Carol S Dweck`（≥3）、一筆 `C. S. Dweck`（<3）
        let entries = [
            entry("a2020", ["Carol S Dweck"]), entry("b2021", ["Carol S Dweck"]),
            entry("c2022", ["Carol S Dweck"]), entry("d2023", ["C. S. Dweck"]),
        ]
        let r = PersonBootstrap.resolve(entries: entries, existing: [],
                                        rejected: [], confirmed: [:], minOccurrences: 3)
        XCTAssertTrue(r.pendingMutual.isEmpty,
                      "低於門檻的 `C. S. Dweck` 不該把 `Carol S Dweck` 扣住：\(r.pendingMutual)")
        // **`minOccurrences` 只閘互連索引，不過濾 `candidates`**——那一半由呼叫端做
        // （`Commands.swift` 的 `report.candidates.filter { $0.occurrences >= minOccurrences }`）。
        // 這條斷言把那個不對稱釘住：改成連 candidates 一起濾會靜默改變既有 34 個呼叫端。
        XCTAssertEqual(r.candidates.count, 2,
                       "resolve 回傳全部候選（含低於門檻者）：\(r.candidates.map(\.key))")
        let above = r.candidates.first { $0.occurrences >= 3 }
        XCTAssertEqual(above?.names, ["Carol S Dweck"])
        XCTAssertEqual(above?.occurrences, 3, "高於門檻的那個必須完好、未被扣住")
    }

    /// 門檻 1（預設）時行為不變——上一條的收窄不得順手改掉預設語意。
    func testAtTheDefaultThresholdTheGroupIsStillWithheld() {
        let entries = [
            entry("a2020", ["Carol S Dweck"]), entry("b2021", ["Carol S Dweck"]),
            entry("c2022", ["Carol S Dweck"]), entry("d2023", ["C. S. Dweck"]),
        ]
        let r = PersonBootstrap.resolve(entries: entries, existing: [],
                                        rejected: [], confirmed: [:])
        XCTAssertEqual(r.pendingMutual.count, 1, "\(r.pendingMutual)")
        XCTAssertTrue(r.candidates.isEmpty)
    }

    /// **被門檻排除的異寫不會就此消失**——它在下一輪由「與既有 person 共鍵」那一半接住。
    ///
    /// 這是門檻收窄之所以安全的理由，而且它是**實測**不是推論：live store 副本上以門檻 10
    /// 建檔後，`Y.-F. Hsu`（2 次）於下一輪落進 `pendingResolution` 並指回 `hsu-yung-fong`。
    /// 少了這一條，V16 的修法看起來就像「用漏掉換乾淨」。
    func testThresholdExcludedVariantIsCaughtByTheExistingPersonCheckLater() {
        // 模擬「高頻的那個已經建檔」之後的狀態
        let existing = [Person(key: "dweck-carol-s",
                               names: PersonNames(variant: ["Carol S Dweck"]))]
        let r = PersonBootstrap.resolve(entries: [entry("d2023", ["C. S. Dweck"])],
                                        existing: existing, rejected: [], confirmed: [:])
        XCTAssertTrue(r.candidates.isEmpty, "不得鑄造第二個身分：\(r.candidates.map(\.key))")
        XCTAssertEqual(r.pendingResolution.count, 1, "\(r)")
        XCTAssertEqual(r.pendingResolution.first?.matchedKeys, ["dweck-carol-s"])
    }

    /// 單一寫法不構成「彼此共鍵」——一組只有一個成員時不得進新桶（否則 3,822 筆
    /// 會全部被扣住，而那不是這個桶的意思）。
    func testASingleSpellingIsNotAMutualGroup() {
        let r = PersonBootstrap.resolve(entries: [entry("a2020", ["Carol S Dweck"])],
                                        existing: [], rejected: [], confirmed: [:])
        XCTAssertTrue(r.pendingMutual.isEmpty, "只有一種寫法時沒有可判定的對象：\(r.pendingMutual)")
        XCTAssertEqual(r.candidates.count, 1, "它應該照常是建檔候選")
    }
}
