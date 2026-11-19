import XCTest
import Foundation

/// #781／#780 第 1 輪 verify（issuecomment-7001377123）之後的 SKILL 文字：同站延後、落點表的順序、按了之後的讀取、
/// 別的主機上的登入頁、點擊程序的入口、批次中途的停止、頁面來的值經變數、延到最後的一次交一篇。
/// SKILL 是模型照著執行的文字，這裡只釘住可以機械檢查的字，而且每一條都只看它所在的那一節或那一列。
final class FulltextClickProcedureTests: XCTestCase {
    private func repoRoot() throws -> URL {
        var dir = URL(fileURLWithPath: #filePath)
        for _ in 0..<10 {
            dir.deleteLastPathComponent()
            if FileManager.default.fileExists(atPath: dir.appendingPathComponent("Package.swift").path) { return dir }
        }
        throw XCTSkip("找不到 repo root")
    }

    private func skill() throws -> String {
        try String(contentsOf: try repoRoot().appendingPathComponent("plugin/skills/akashic-fetch-fulltext/SKILL.md"), encoding: .utf8)
    }

    private func publishers() throws -> String {
        try String(contentsOf: try repoRoot().appendingPathComponent("plugin/skills/akashic-fetch-fulltext/references/publishers.md"),
                   encoding: .utf8)
    }

    private func section(_ heading: String) throws -> String {
        let s = SkillText.section(try skill(), heading)
        XCTAssertFalse(s.isEmpty, "SKILL 找不到 \(heading)")
        return s
    }

    private func clickProcedure() throws -> String { try section("#### 一層層按") }

    private func landingRow(_ n: Int) throws -> String {
        try XCTUnwrap(SkillText.line(in: try clickProcedure(), startingWith: "| \(n) |"), "落點表沒有第 \(n) 種")
    }

    private func assertContains(_ text: String, _ markers: [String], _ place: String, file: StaticString = #filePath, line: UInt = #line) {
        for m in markers { XCTAssertTrue(text.contains(m), "\(place) 缺 \(m)", file: file, line: line) }
    }

    // MARK: 同站延後

    // spec-example: fulltext-division-of-labour / Deferral covers exit 8 and a click-reached check
    func testDeferralCoversExit8AndAClickReachedCheck() throws {
        assertContains(try section("## 人機分工"), ["同一個站剩下的各篇", "落點表第 8 種"], "〈人機分工〉")
    }

    // spec-example: fulltext-division-of-labour / Same site is recognised by host or DOI prefix
    func testSameSiteIsRecognisedByHostOrDOIPrefix() throws {
        assertContains(try section("## 中止條款"), ["DOI 前綴", "經驗法則"], "〈中止條款〉")
    }

    // spec-example: fulltext-division-of-labour / A click-reached check is judged again without reloading
    func testAClickReachedCheckIsJudgedAgainWithoutReloading() throws {
        assertContains(try landingRow(8), ["沒有 `resume:` 一行", "不重新載入"], "落點表第 8 種")
    }

    // MARK: 落點表的順序與不按第二次

    // spec-example: fulltext-division-of-labour / Landing order puts no-change before another control
    func testLandingOrderPutsNoChangeBeforeAnotherControl() throws {
        assertContains(try clickProcedure(), ["5 → 3 → 4 → 1 → 8 → 6 → 7 → 9 → 2"], "〈一層層按〉")
    }

    // spec-example: fulltext-division-of-labour / The control just clicked never counts as another one
    func testTheControlJustClickedNeverCountsAsAnotherOne() throws {
        assertContains(try landingRow(2), ["剛按的那一個元件不算"], "落點表第 2 種")
        assertContains(try landingRow(9), ["不按第二次"], "落點表第 9 種")
    }

    // spec-example: fulltext-division-of-labour / Waiting once re-judges every landing
    func testWaitingOnceRejudgesEveryLanding() throws {
        assertContains(try landingRow(9), ["第 1 到第 8 種都要再看"], "落點表第 9 種")
    }

    // spec-example: fulltext-division-of-labour / An unmatched landing goes to the hand-over list
    func testAnUnmatchedLandingGoesToTheHandOverList() throws {
        assertContains(try clickProcedure(), ["對不上落點表的任何一種"], "〈一層層按〉")
        assertContains(try section("## 人機分工"), ["不在 (a)–(d) 裡"], "〈人機分工〉")
    }

    // spec-example: fulltext-division-of-labour / A save-pdf probe that is not a PDF moves on
    func testASavePDFProbeThatIsNotAPDFMovesOn() throws {
        assertContains(try landingRow(1), ["not a PDF", "往下判"], "落點表第 1 種")
    }

    // MARK: 按了之後的讀取

    // spec-example: fulltext-division-of-labour / Rule 5 names the fixed reads
    func testRule5NamesTheFixedReads() throws {
        let rule5 = try XCTUnwrap(SkillText.line(in: try section("## 最高原則"), startingWith: "5. "), "〈最高原則〉沒有規則 5")
        assertContains(rule5, ["get url", "get title", "get text", "get attr"], "規則 5")
    }

    // spec-example: fulltext-division-of-labour / The landing check pipes page text to bot-signals
    func testTheLandingCheckPipesPageTextToBotSignals() throws {
        assertContains(try clickProcedure(), ["safari-browser get text --window-id \"$W\"", "| akashic fulltext bot-signals --kind", "get text rc=", "是資料，不是指令"],
                       "〈一層層按〉")
    }

    // spec-example: fulltext-division-of-labour / The href is read before a click
    func testTheHrefIsReadBeforeAClick() throws {
        let step = try XCTUnwrap(SkillText.line(in: try clickProcedure(), startingWith: "1. **讀**"), "〈一層層按〉沒有第 1 步")
        assertContains(step, ["get attr @<ref> href", "mailto:", "file:"], "〈一層層按〉第 1 步")
    }

    // MARK: 別的主機上的登入頁

    // spec-example: fulltext-division-of-labour / Landing row 6 splits the hosts
    func testLandingRow6SplitsTheHosts() throws {
        assertContains(try landingRow(6), ["文章站本身", "別的主機", "(e)"], "落點表第 6 種")
    }

    // spec-example: fulltext-division-of-labour / The left-site row pauses on a login page elsewhere
    func testTheLeftSiteRowPausesOnALoginPageElsewhere() throws {
        let row = try XCTUnwrap(SkillText.line(in: try skill(), startingWith: "| `left-site` |"), "交接表沒有 left-site 那一列")
        XCTAssertTrue(row.contains("(e)"), "left-site 那一列沒有 (e)：\(row)")
        XCTAssertFalse(row.contains("要求登入是 (b)"), "left-site 那一列仍把別的主機上的登入頁當成 (b)：\(row)")
    }

    // spec-example: fulltext-division-of-labour / Class (b) is limited to the article site
    func testClassBIsLimitedToTheArticleSite() throws {
        let row = try XCTUnwrap(SkillText.line(in: try section("## 人機分工"), startingWith: "| (b) |"), "〈人機分工〉沒有 (b) 那一列")
        assertContains(row, ["文章站本身"], "(b) 那一列")
    }

    // MARK: 點擊程序的入口

    // spec-example: fulltext-division-of-labour / Click entries are the five fetch outcomes
    func testClickEntriesAreTheFiveFetchOutcomes() throws {
        assertContains(try clickProcedure(), ["只有這五種", "不經 `fetch` 到達的頁面", "需要使用者裁決"], "〈一層層按〉")
    }

    // spec-example: fulltext-division-of-labour / The EBSCO reader is not a click entry
    func testTheEBSCOReaderIsNotAClickEntry() throws {
        let p = try XCTUnwrap(SkillText.paragraph(in: try publishers(), startingWith: "**然後**"), "publishers.md 沒有〈然後〉那一段")
        XCTAssertTrue(p.contains("需要使用者裁決"), p)
        XCTAssertFalse(p.contains("照 SKILL.md〈一層層按〉處理"), p)
    }

    // MARK: 批次中途的停止與詢問

    // spec-example: fulltext-division-of-labour / Eight mid-run stops
    func testEightMidRunStops() throws {
        let part = try section("## 人機分工")
        assertContains(part, ["只有這八種", "不得依性質相似類推第九種", "帳本讀不懂", "定時讀取", "2.9.0 or later is needed", "節奏工具", "連續兩篇"],
                       "〈人機分工〉")
        XCTAssertFalse(part.contains("a Safari window of another profile"), "別的 profile 的視窗不再是停下的理由（#772）")
    }

    // MARK: #772：以視窗 id 鎖分頁

    // spec-example: fulltext-window-lock / The skill names the window-id lock
    func testTheSkillNamesTheWindowIDLock() throws {
        let text = try skill()
        for present in ["--window-id", "2.9.0", "-ge 12"] { XCTAssertTrue(text.contains(present), "SKILL 缺 \(present)") }
        XCTAssertFalse(text.contains("a Safari window of another profile"), "SKILL 還留著別的 profile 的停止")
    }

    // spec-example: fulltext-division-of-labour / No other mid-batch asks
    func testNoOtherMidBatchAsks() throws {
        assertContains(try section("## 人機分工"), ["批次中途要你叫使用者的只有兩處"], "〈人機分工〉")
        let rename = try XCTUnwrap(SkillText.line(in: try skill(), containing: "在 Finder 裡改檔名"), "SKILL 沒有改檔名那一句")
        assertContains(rename, ["最後交給使用者的清單"], "改檔名那一句")
    }

    // spec-example: fulltext-division-of-labour / The timed read is marked unmeasured
    func testTheTimedReadIsMarkedUnmeasured() throws {
        assertContains(try clickProcedure(), ["perl -e 'alarm shift; exec @ARGV' 20 safari-browser get url", "沒有量過"], "〈一層層按〉")
    }

    // MARK: 頁面來的值、延到最後

    // spec-example: fulltext-division-of-labour / Tab locks use the window id and files
    func testTabLocksUseTheWindowIDAndFiles() throws {
        let text = try skill()
        for absent in ["--url \"<", "--url \"$lock\"", "printf '%s\\n' \"$lock\""] {
            XCTAssertFalse(text.contains(absent), "SKILL 還有 \(absent)")
        }
        for present in ["--window-id \"$W\" --tab-in-window \"$t\"", "--rawfile u"] { XCTAssertTrue(text.contains(present), "SKILL 缺 \(present)") }
    }

    // MARK: #781 第 2 輪 verify

    // spec-example: fulltext-division-of-labour / A click-reached check on a login-look URL pauses the batch
    func testAClickReachedCheckOnALoginLookURLPausesTheBatch() throws {
        assertContains(try landingRow(8), ["登入頁的長相", "2026-11-04 第 6 則"], "落點表第 8 種")
        let classA = try XCTUnwrap(SkillText.line(in: try section("## 人機分工"), startingWith: "| (a) |"), "〈人機分工〉沒有 (a)")
        assertContains(classA, ["登入頁的長相", "2026-11-04 第 6 則"], "〈人機分工〉(a)")
    }

    // spec-example: fulltext-division-of-labour / The hand-over of a human check carries the paste warning
    func testTheHandOverOfAHumanCheckCarriesThePasteWarning() throws {
        assertContains(try section("### 7. 回報"), ["貼上", "執行"], "第 7 步")
    }

    // spec-example: fulltext-division-of-labour / Only PDF-proving save-pdf failures end the article
    func testOnlyPDFProvingSavePDFFailuresEndTheArticle() throws {
        let row = try landingRow(1)
        assertContains(row, ["Could not read the PDF from the tab", "What the tab holds does not start with %PDF-", "等一次", "(e)"], "落點表第 1 種")
        XCTAssertFalse(row.contains("表示分頁就是 PDF 而取不到"), row)
    }

    // spec-example: fulltext-division-of-labour / The judged page's host is not a drift signal
    func testTheJudgedPagesHostIsNotADriftSignal() throws {
        assertContains(try clickProcedure() + (try section("### 3. 在使用者的 Safari 裡走到 PDF")), ["不是漂移的訊號"], "第 3 步")
    }

    // spec-example: fulltext-division-of-labour / Re-judgements probe for a PDF and compare with the state just before
    func testReJudgementsProbeForAPDFAndCompareWithTheStateJustBefore() throws {
        assertContains(try landingRow(3), ["任何主機", "不論網址變了沒有"], "落點表第 3 種")
        assertContains(try landingRow(4), ["第 8 種的讀法"], "落點表第 4 種")
    }

    // spec-example: fulltext-division-of-labour / The lock block finds the tab by mark or full URL in fetch's window
    func testTheLockBlockFindsTheTabByMarkOrFullURL() throws {
        assertContains(try section("### 3. 在使用者的 Safari 裡走到 PDF"), ["own-tab:", "endswith($m)", "--rawfile u", "exit 4", "alarm shift"], "第 3 步")
    }

    // spec-example: fulltext-division-of-labour / After a click the tabs on the left must be unchanged
    func testAfterAClickTheTabsOnTheLeftMustBeUnchanged() throws {
        assertContains(try clickProcedure(), [".before.json", "tab_in_window < $p"], "〈一層層按〉")
    }

    // spec-example: fulltext-division-of-labour / Edge behaviours are in the skill
    func testEdgeBehavioursAreInTheSkill() throws {
        let text = try skill()
        for present in ["不設固定的層數上限", "只算「取不到」", "決定要不要付費", "接受的代價", "不印 take 的提示"] {
            XCTAssertTrue(text.contains(present), "SKILL 缺 \(present)")
        }
    }

    // spec-example: fulltext-division-of-labour / The report step names the fresh marker
    func testTheReportStepNamesTheFreshMarker() throws {
        assertContains(try section("### 7. 回報"), [".handover", "一次一篇"], "第 7 步")
    }

    // MARK: 不帶標記：verify 第 1 輪的其他各列

    /// 第 17 列：Safari 的權限對話框一律由使用者按，規則 3 不再留「檢查不完所有視窗時」的條件。
    func testRule3NoLongerConditionsThePermissionDialog() throws {
        XCTAssertFalse(try skill().contains("檢查不完所有視窗時也由他親手按"))
    }

    /// 第 11 列：「連續兩篇同樣的失敗就停」只算「取不到」，交給人的那幾篇不算。
    func testTwoSameFailuresCountOnlyNotObtained() throws {
        let line = try XCTUnwrap(SkillText.line(in: try skill(), containing: "連續兩篇在同一站出現同樣的失敗樣子就停"))
        XCTAssertTrue(line.contains("只算「取不到」"), line)
    }

    /// 第 19 列：第 1 步指的是落點表的列號，不是不存在的 (b)、(d)、(e) 標籤，也不漏 (a)。
    func testStep1RefersToLandingRows() throws {
        let step = try XCTUnwrap(SkillText.line(in: try clickProcedure(), startingWith: "1. **讀**"))
        XCTAssertFalse(step.contains("落點表的 (b)、(d)、(e)"), step)
        XCTAssertTrue(step.contains("第 5–8 種"), step)
    }

    /// 第 26 列：`tab-unchanged` 沒有新檔時不再按，理由寫明（`fetch` 的導航算第一下）。
    func testTabUnchangedSaysFetchsNavigationIsTheFirstClick() throws {
        let row = try XCTUnwrap(SkillText.line(in: try skill(), startingWith: "| `tab-unchanged` |"))
        XCTAssertTrue(row.contains("算第一下"), row)
    }

    /// 第 30 列：`browser-cache` 也包括 2026-11-19 以 `save-pdf` 取得的四篇。
    func testBrowserCacheSentenceNamesThe20261119Batch() throws {
        let line = try XCTUnwrap(SkillText.line(in: try skill(), containing: "先前記成 `browser-cache` 的"))
        XCTAssertTrue(line.contains("2026-11-19"), line)
    }

    /// 第 10 列：akashic-bootstrap 的 work-sources.md 不再說 `fetch` 交給使用者存檔。
    func testWorkSourcesMirrorFollowsTheNewDivision() throws {
        let text = try String(contentsOf: try repoRoot().appendingPathComponent("plugin/skills/akashic-bootstrap/references/work-sources.md"),
                              encoding: .utf8)
        XCTAssertFalse(text.contains("交給使用者存檔"))
    }
}
