import Foundation
import ArgumentParser
import AkashicCore

/// `akashic references extract` 的切分邏輯（#617）：吃 `pdftotext` 的輸出，找參考文獻段、
/// 逐筆切分、抽欄位。**不寫 store、不打網路**——這是 skill 流程裡的決定論中間運算
/// （`.claude/rules/swift-is-the-implementation-language.md` 的放置表第 3 列）。
///
/// 只支援作者—年份格式（APA 系，#617 D7）。數字編號格式明確拒絕，不硬切出一份錯的清單。
/// 切分是啟發式的：誤差由 skill 的兩源交叉（PDF × OpenAlex）與模型逐筆判定吸收，
/// 本檔只負責把「看得出來的」切對，並把看不出來的寫進 `warnings`。
enum ReferenceListExtractor {

    struct Reference: Codable, Equatable {
        var index: Int
        var raw: String
        var firstAuthor: String?
        var authors: [String]
        var groupAuthor: Bool
        var year: Int?
        var yearSuffix: String?
        var yearNote: String?
        var title: String?
        var doi: String?
    }

    struct Result: Codable {
        var count: Int
        var entries: [Reference]
        var warnings: [String]
        /// 輸出契約版本（#617 verify R2 G5）：skill 以它分辨 CLI 是否夠新——舊版沒有這個鍵，
        /// 而舊版上新的檢查會空洞地成立。optional：讀舊輸出時不因缺鍵失敗，交給 skill 判斷。
        var contract: Int?
    }

    /// 目前的輸出契約版本。輸出欄位或 warning 的語意改了就加一。3（R4 A4）：R3 改了 warning 的語意
    /// ——多段 warning 列各段條目數、頁首與接續 warning、位置帶 PDF 頁碼、nominate 不再發「同分」。
    /// 4（R6）：新增「過長」與「最後一筆還沒結束」兩則 warning，多段 warning 改列條目最多的 5 段；
    /// nominate 只接同版的 refs。5（R7）：「最後一筆看起來還沒結束」擴及停在另一個參考文獻標題、一路到文字
    /// 結尾，並新增「下一行以小寫開頭、這個標題可能是換行換出來的字」；措辭改為「被切斷或吸進了文字」。
    static let contractVersion = 5

    // MARK: - 樣式

    /// 參考文獻段的標題：整行只有這幾個字（可帶章節編號與冒號）。標題候選怎麼組成一份清單見
    /// `groups`：清單從一個候選開始，遇到斷點時看「之後是不是同一份清單接下去」。演變（都是踩過的）：
    /// - R1 取最後一個候選 → 清單**之後**的表格欄名 `Reference` 奪走標題
    /// - R2 取條目最多、段落在下一個候選截止 → 書的每一頁都印著 `References` 頁首時，清單被切成
    ///   一頁一段、只留最大段（本機真實書籍實測只剩 1–4%）
    /// - R3 以字母順序與完整條目判定斷點後是否接續；多段都有條目時 warning 列出每一段的條目數
    static let headingPattern =
        "^(?:\\d+(?:\\.\\d+)*\\.?\\s+)?(?:references?|reference list|bibliography|literature cited|works cited|參考文獻|参考文献|引用文獻)\\s*:?$"

    /// 段落的結束：參考文獻之後的附錄、註、致謝、索引、表與圖（索引是 R3 H1 加的：書末索引行
    /// `姓, 名縮寫., 頁碼` 長得像條目開頭，不擋就整段被算成條目）。只認**整行**標題；附錄標題
    /// 不含括號（條目一定有年份括號，所以 `Appendix, J. (2001)` 不會被當成標題）。
    static let endPattern =
        "^(?:\\d+\\.?\\s+)?(?:(?:appendix|appendices)\\b[^()]{0,80}|supplementa(?:l|ry)(?: materials?| information)?|supporting information|notes|footnotes|endnotes|acknowledge?ments?|author note|(?:subject |author |name )?index(?:es)?|(?:table|figure)\\s+\\d+\\.?)\\s*:?$"

    /// 數字編號格式（`[1] …`、`1. …`）
    static let numberedPattern = "^(?:\\[\\d{1,3}\\]|\\d{1,3}\\.\\s)"

    /// 姓前的小寫姓氏前綴（`van der Berg`、`de Haan`）
    static let particles = "(?:(?:van|von|de|der|den|du|la|le|di|da|del|dos|ten|ter)\\s+)*"

    /// 個人作者開頭的一筆：`姓, 名縮寫.`
    ///
    /// 連字號**只當分隔符**、不在字元類裡（#617 verify F8）：原本兩處都允許連字號，`Aa-Aa-…Aa!`
    /// 這種失敗行會被試遍所有切法，每多一段慢約 2.8 倍（20 段 16 秒）。名縮寫後接冒號的
    /// （`Cambridge, U.K.:`、`Washington, D.C.:`）是出版地續行，不是條目開頭。
    ///
    /// 分號不在前瞻裡（R3 L1）：R2 為了 `Oxford, U.K.; New York` 加上 `;`，結果以分號分隔的作者
    /// 清單（`Baker, L.; Cole, M.;`）也不再是條目開頭。出版地改由 `isEntryStart` 的「括號前就有
    /// 冒號」擋掉——出版地行一定帶 `City, ST: Publisher`，條目的冒號在年份括號之後（副標）。
    static let personStartPattern =
        "^" + particles + "\\p{Lu}[\\p{L}'’]+(?:\\s\\p{Lu}[\\p{L}'’]+|-\\p{L}[\\p{L}'’]+)*,\\s+\\p{Lu}\\.(?!(?:\\s?\\p{Lu}\\.)*\\s*:)"

    /// 個人姓名的開頭（`姓, 名縮寫.`，不帶前瞻）——`isLocationLine` 用來分辨分號後面是不是下一位作者
    static let personNamePattern =
        "^" + particles + "\\p{Lu}[\\p{L}'’]+(?:\\s\\p{Lu}[\\p{L}'’]+|-\\p{L}[\\p{L}'’]+)*,\\s+\\p{Lu}\\."

    /// 出版地行（`Oxford, U.K.; New York, NY: Press.`、`Oxford, U.K.; New York.`）：第一個括號之前
    /// 就有「冒號＋空白」，或第一個括號之前有分號、而分號後面不是下一位作者（`Baker, L.; Cole, M.;`
    /// 的分號後面是 `Cole, M.`）
    static func isLocationLine(_ line: String) -> Bool {
        if matches(line, "^[^()]*:\\s") { return true }
        guard let semi = line.firstIndex(of: ";"), !line[..<semi].contains("(") else { return false }
        let after = line[line.index(after: semi)...].trimmingCharacters(in: .whitespaces)
        return !after.isEmpty && !matches(after, personNamePattern)
    }

    /// 機構作者開頭的一筆：`機構名. (年份`。機構名可以含句點（`U.S. Department …`，#617 verify）；
    /// 但以 `et al.` 結尾的是正文的引用句（`Quinn et al. (2011) argued …`），不是條目（R2 G1）。
    static let groupStartPattern =
        "^\\p{Lu}[^()]{2,120}?(?<!\\bet al)\\.\\s\\((?:\\d{4}|n\\.\\s?d\\.|in press|in preparation|submitted|forthcoming)"

    /// 年份括號：`(2015)`、`(2015a)`、`(2015, March 3)`、區間 `(1998–2012)`／`(1998–99)`／`(2015–)`、
    /// 重印 `(1890/1950)`（都取第一年）、`(n.d.)`、`(in press)`／`(in preparation)`／`(submitted)`／
    /// `(forthcoming)`。認不得的寫法會讓下一筆被當成續行併進來——區間是 #617 校準加的，其餘是
    /// verify F1 加的；括號排成大括號的排版錯字（`(1996}.` 是 R3、鏡像的 `{1996)` 是 R4 B1，都出自
    /// 本機同一本真實書籍）；仍認不得的
    /// 由 `split` 的併筆 warning 揭露。
    static let yearParenPattern =
        "[({](?:(\\d{4})([a-z])?(?=\\s*[),/}]|\\s*[–—-])|(n\\.\\s?d\\.)|(in press|in preparation|submitted|forthcoming))"

    static let doiPattern =
        "(?:https?://(?:dx\\.)?doi\\.org/|doi:\\s*)(10\\.\\d{4,9}/\\S+)"
    static let bareDOIPattern = "\\b(10\\.\\d{4,9}/\\S+)"

    // MARK: - 入口

    static func extract(_ input: String) throws -> Result {
        let (lines, pages) = normalizedLines(input)
        let paged = input.contains("\u{0C}")
        func place(_ i: Int) -> String {
            paged ? "第 \(i + 1) 行（PDF 第 \(pages[i]) 頁）" : "第 \(i + 1) 行"
        }

        let candidates = lines.indices.filter { matches(lines[$0], headingPattern, caseInsensitive: true) }
        guard !candidates.isEmpty else {
            throw ValidationError(
                "找不到參考文獻段的標題（References／Bibliography／參考文獻 等獨立成行的標題）——"
                + "輸入可能不含參考文獻段，或標題與其他文字擠在同一行")
        }
        let sections = groups(candidates, in: lines, pages: pages, place: place)
        let starts = sections.map { $0.lines.filter(isEntryStart).count }
        // 條目開頭最多者；同數取後者（沿用原本「參考文獻段在正文之後」的偏好）
        let best = starts.indices.max { (starts[$0], $0) < (starts[$1], $1) } ?? 0
        let chosen = sections[best]
        var warnings: [String] = []
        let withEntries = starts.indices.filter { starts[$0] > 0 }
        if withEntries.count > 1 {
            // 只列 5 段（R5 E4：候選很多時會超過 warning 的長度上限）——列條目開頭最多的 5 段，不是文件裡
            // 最前面的 5 段（R6 E4：大段可能被藏在「等 N 段」裡）
            let others = withEntries.filter { $0 != best }
                .sorted { (starts[$0], -$0) > (starts[$1], -$1) }
                .map { "\(place(sections[$0].heading))：\(starts[$0]) 個" }
            warnings.append("有 \(withEntries.count) 個參考文獻標題候選都帶著條目；取條目開頭最多的那個"
                            + "（\(place(chosen.heading))，\(starts[best]) 個條目開頭）。其餘（由多到少）："
                            + others.prefix(5).joined(separator: "、")
                            + (others.count > 5 ? " 等 \(others.count) 段（未列的每段都不多於列出的）" : "")
                            + "——可能是目錄、附錄或表格；若其中有這份清單的一部分，清單被截斷了")
        }
        // 沒被選中、而且自己一筆都沒有的段：它在斷點處停下、之後其實有條目開頭——主清單可能就是它
        // （R5 D7：這則 note 原本跟著沒被選中的段一起丟掉，工具改選別段而完全沒有 warning）
        // 只在停下處是圖表或結束標題時（停在另一個標題候選的，那些條目歸下一段），而且不在選中的清單裡
        // 的條目開頭至少 3 個——一兩行是正文裡長得像條目的句子（本機語料：目錄後的一行、真清單本身）；
        // 或者比選中的清單還多——短清單的主清單只有一兩筆，選中的那段更少（R6 D7）
        for (n, g) in sections.enumerated() where n != best && starts[n] == 0 {
            guard let o = g.orphan else { continue }
            let outside = o.starts.filter { !chosen.range.contains($0) }
            if outside.count >= 3 || outside.count > starts[best] {
                warnings.append("\(place(o.heading))的參考文獻標題之後，清單在\(place(o.stop))的圖表或結束標題處停下，"
                                + "之後的 \(outside.count) 個條目開頭沒有被認成清單（第一筆不是完整條目，或離斷點太遠）"
                                + "——若那才是參考文獻，這份清單選錯了")
            }
        }
        // 標題之前、同一頁就有完整條目：雙欄版面把清單的一部分讀到標題之前了（R4 A7）。沒有換頁資訊
        // 時無從判斷「同一頁」，不報
        if paged {
            let before = (0..<chosen.heading).filter { i in
                pages[i] == pages[chosen.heading] && isEntryStart(lines[i])
                    && (i == 0 || !continuesAuthorList(lines[i - 1])) && isFullEntry(at: i, in: lines)
            }
            if before.count >= 2 {
                warnings.append("標題之前、同一頁（PDF 第 \(pages[chosen.heading]) 頁）有 \(before.count) 個完整條目沒有計入"
                                + "——可能是雙欄版面把清單的一部分讀到標題之前了，這份清單可能缺了一段")
            }
        }

        let nonEmpty = chosen.lines.filter { !$0.isEmpty }
        if nonEmpty.prefix(10).filter({ matches($0, numberedPattern) }).count >= 3 {
            throw ValidationError(
                "參考文獻段是數字編號格式（[1] …）——目前不支援，只處理作者—年份格式（#617 D7）")
        }

        let (noise, fallback) = noiseIndices(nonEmpty, documentLines: lines, section: chosen.range)
        guard nonEmpty.indices.contains(where: { !noise.contains($0) && isEntryStart(nonEmpty[$0]) }) else {
            throw ValidationError(
                "找到參考文獻標題，但段落裡沒有辨識出任何條目——段落可能是空的、被截斷，或不是作者—年份格式")
        }

        // 斷點 note 的「第 k 筆」由最後的切分決定（R5 D6：`groups` 與 `split` 的算法不同，會差一）
        let markIndex = chosen.notes.map { note in
            note.mark.map { m in chosen.lines[..<min(m, chosen.lines.count)].filter { !$0.isEmpty }.count }
        }
        let (texts, absorbed, skippedIn, markedEntries) = split(nonEmpty, skip: noise, marks: markIndex.compactMap { $0 })
        var markCursor = 0
        for (n, note) in chosen.notes.enumerated() {
            if markIndex[n] != nil {
                warnings.append(note.text.replacingOccurrences(of: "〔k〕", with: String(markedEntries[markCursor])))
                markCursor += 1
            } else {
                warnings.append(note.text)
            }
        }
        if !noise.isEmpty {
            let pageNumbers = noise.filter { matches(nonEmpty[$0], "^\\d{1,4}$") }.count
            // 不引 PDF 原文（R2 G10：warnings 會進模型的行動清單），只報落在哪幾筆
            let repeated = fallback
                ? "段內重複出現的行 \(noise.count - pageNumbers) 行（沒有正文可對照，以段內重複判定：頁首頁尾、"
                    + "版權聲明，也可能是正當重複的續行）"
                : "在參考文獻段以外也出現的行 \(noise.count - pageNumbers) 行（頁首頁尾、版權聲明）"
            // 完整列出每一筆，分段寫才不會被 warning 的長度上限截掉（R5 D9：R4 只列前 15 筆）
            let chunks = stride(from: 0, to: skippedIn.count, by: 40).map {
                skippedIn[$0..<min($0 + 40, skippedIn.count)].map(String.init).joined(separator: "、")
            }
            for (c, chunk) in chunks.enumerated() {
                warnings.append(c == 0
                    ? "略過 \(noise.count) 行：頁碼 \(pageNumbers) 行、\(repeated)，落在第 \(chunk) 筆"
                        + (chunks.count > 1 ? "（續見下一則）" : "") + "——這幾筆的標題或出處若看起來缺了一段，判為「判不了」"
                    : "（續）略過的行也落在第 \(chunk) 筆")
            }
        }
        let entries = texts.enumerated().map { offset, text in
            fields(of: text, index: offset + 1)
        }
        for n in absorbed {
            warnings.append("第 \(n) 筆吸收了一行看起來像新條目開頭的內容——可能兩筆併成一筆"
                            + "（前一筆的年份寫法沒認出來），作者與標題可能分屬兩筆")
        }
        // 過長的條目：清單之後（或欄間）的文字被併了進來，最常見的是最後一筆一路吸到檔尾（作者簡介、
        // 「引用本文」的 DOI）。作者、年份、標題取自開頭，不受影響；DOI 取第一個出現的，這一筆自己沒有
        // DOI 時會拿到別人的（R6：原本只在 SKILL 裡點名一份語料，機制沒有揭露）
        let overlong = entries.filter { $0.raw.count > overlongEntry }.map(\.index)
        for c in stride(from: 0, to: overlong.count, by: 40) {
            let chunk = overlong[c..<min(c + 40, overlong.count)].map(String.init).joined(separator: "、")
            warnings.append((c == 0 ? "" : "（續）") + "第 \(chunk) 筆的原文超過 \(overlongEntry) 字"
                            + "——可能併進了清單之後或欄間的文字；這幾筆的 DOI 可能不是它自己的")
        }
        // 清單在斷點或文字結尾停下，而最後一筆在那之前還沒結束：它在斷點之後的那一段不會回來（R6：跨過
        // 圖表的最後一筆，後半原本無聲丟掉）。看切分之後的那一筆本身——斷點前一行常是頁尾之類的雜訊
        // （本機語料 3 份）；過長的已由上一則說出來（本機語料 11 份是吸進了文字才停在圖表處）。長度檢查
        // 先做：`closesEntry` 只看結尾，但不先擋，一長串吸進來的數字仍要整段複製（R7 #1）。
        // R7 #2：原本只看停在結束標題或圖表標題的，停在另一個參考文獻標題、或一路到文字結尾的都不看
        if let stop = chosen.stop, let last = entries.last, last.raw.count <= overlongEntry {
            if stop.wrapSuspect, let line = stop.line {
                // 大寫、單獨一行的 Index／Appendix 照終點處理（`isHardEnd`）；下一行以小寫開頭時，它可能是
                // 最後一筆換行換出來的字——最後一筆恰好在句點處換行時，下面那一則看不出來（R7 #5）
                warnings.append("清單停在\(place(line))的結束標題，而它的下一行以小寫開頭——這個標題可能是最後一筆"
                                + "（第 \(last.index) 筆）換行換出來的一個字；若是，這一筆缺了後半")
            } else if !closesEntry(last.raw) {
                if let line = stop.line {
                    warnings.append("清單停在\(place(line))的\(stop.kind)，而最後一筆（第 \(last.index) 筆）看起來還沒結束"
                                    + "（不是以句點、括號、頁碼或 DOI 結尾）——它可能在那裡被切斷（之後那一段不會回來），也可能"
                                    + "吸進了清單之後的文字；這一筆的標題可能不完整、DOI 可能不是它自己的")
                } else {
                    // 本機語料 18 份觸發，看得出來的都是吸進了頁尾、收稿日期這類文字，不是缺頁——兩種都說
                    warnings.append("清單一直到文字結尾，而最後一筆（第 \(last.index) 筆）看起來還沒結束（不是以句點、括號、"
                                    + "頁碼或 DOI 結尾）——可能吸進了清單之後的文字（頁尾、收稿日期），或 PDF 缺了最後幾頁；"
                                    + "這一筆的標題可能不完整、DOI 可能不是它自己的")
                }
            }
        }
        for e in entries where e.year == nil && e.yearNote == nil {
            warnings.append("第 \(e.index) 筆沒有辨識出年份——可能兩筆併成一筆，或不是作者—年份格式")
        }
        for e in entries where e.title == nil {
            warnings.append("第 \(e.index) 筆沒有辨識出標題")
        }
        return Result(count: entries.count, entries: entries, warnings: warnings, contract: contractVersion)
    }

    // MARK: - 步驟

    /// pdftotext 輸出的正規化，逐行，連同每行所在的 PDF 頁碼（R3 L3）。
    ///
    /// - 換頁符：pdftotext 把它放在每頁第一行的**行首**（`…\n\fNext`），空白頁是連續兩個
    ///   （`\f\f`）。行首的換頁符只換頁、**不多算一行**，所以行號等於檔案的行號；行中的
    ///   換頁符（其他工具）才換頁並斷行。R2 只收掉 `\n\f` 一次，空白頁仍每頁多算一行。
    /// - 行尾軟連字號：去掉、在那一行尾端加 `softHyphenMark`、**保留換行**（R2 直接接合，後面的行號全部少一）。接合
    ///   交給 `join`：去掉記號、不加空白。R3 換成一般連字號，標題與 DOI 因此多出一個 `-`（R4 B5）。
    /// - NFKC（連字 ﬁ → fi、不換行空白 → 空白），其餘格式字元與控制字元移除，頭尾空白去掉。
    static func normalizedLines(_ s: String) -> (lines: [String], pages: [Int]) {
        let t = s.replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .replacingOccurrences(of: "\t", with: " ")

        var lines: [String] = []
        var pages: [Int] = []
        var page = 1
        for raw in t.components(separatedBy: "\n") {
            var rest = Substring(raw)
            while rest.first == "\u{0C}" { page += 1; rest = rest.dropFirst() }
            let parts = rest.split(separator: "\u{0C}", omittingEmptySubsequences: false)
            for (k, part) in parts.enumerated() {
                if k > 0 { page += 1 }
                let soft = k == parts.count - 1 && part.hasSuffix("\u{AD}")
                lines.append(clean(String(part)) + (soft ? softHyphenMark : ""))
                pages.append(page)
            }
        }
        return (lines, pages)
    }

    /// 行尾軟連字號的記號：控制字元 U+001F。`clean` 會刪掉輸入裡所有控制字元，所以清理之後出現的
    /// U+001F 只可能是這裡加的（R5 E2：R4 用私用區 U+E000，會撞上 pdftotext 本來就會輸出的私用區字元）
    static let softHyphenMark = "\u{1F}"

    static func clean(_ s: String) -> String {
        var out = String.UnicodeScalarView()
        for u in s.precomposedStringWithCompatibilityMapping.unicodeScalars {
            switch u.properties.generalCategory {
            case .format, .control: continue
            default: out.append(u)
            }
        }
        return String(out).trimmingCharacters(in: .whitespaces)
    }

    /// 雜訊行在 `lines` 裡的位置：頁碼（只有數字的行），以及**在參考文獻段以外也出現**的行
    /// （頁首、頁尾、版權聲明——它們印在每一頁上，正文頁也有）。
    ///
    /// 判準的演變，都是量出來的：
    /// - 段內計數 → 參考文獻段只跨兩頁時，頁首在段內只出現一次，併進了條目（#617 校準）
    /// - 全文計數 ≥ 2 → 同一家出版社的兩章各以 `New York, NY: Guilford Press.` 單獨成行
    ///   結尾，兩行都被當成頁首刪掉（R2 G10）
    /// - 段外出現 ≥ 1（現行）→ 只在清單裡重複的是條目的一部分
    ///
    /// 位置（每頁開頭或結尾幾行）不能當判準：同一條版權聲明在一篇 APA 論文的三頁裡分別落在
    /// 第 0、8、16 行。條目開頭的行永不算雜訊——兩筆開頭逐字相同就是重複條目，要留給人看。
    ///
    /// 段外**沒有任何文字**時（只有清單的輸入：貼上的參考文獻頁、節錄），沒有正文頁可以觀察，
    /// 退回「段內重複 ≥ 2」（R3 L2：R2 改判準時把這種輸入的頁首併進了條目）。標題候選行不算
    /// 段外文字。
    static func noiseIndices(_ lines: [String], documentLines: [String], section: Range<Int>) -> (Set<Int>, fallback: Bool) {
        var outside: [String: Int] = [:]
        for (i, l) in documentLines.enumerated()
        where !l.isEmpty && !section.contains(i) && !matches(l, headingPattern, caseInsensitive: true) {
            outside[l, default: 0] += 1
        }
        var inside: [String: Int] = [:]
        if outside.isEmpty { for l in lines { inside[l, default: 0] += 1 } }
        let set = Set(lines.indices.filter { i in
            if matches(lines[i], "^\\d{1,4}$") { return true }
            if isEntryStart(lines[i]) { return false }
            return outside.isEmpty ? inside[lines[i], default: 0] >= 2 : outside[lines[i], default: 0] >= 1
        })
        return (set, outside.isEmpty)
    }

    /// 一份清單：從 `heading` 開始，`lines` 是清單內的行（略過的斷點區不在內），`range` 是它在
    /// 全文的行號範圍（0 起算），`notes` 是只在選中這份時才輸出的 warning。
    struct Group {
        var heading: Int
        var lines: [String]
        var range: Range<Int>
        /// `mark` 是 note 所指的斷點位置（`lines` 的索引）；帶 mark 的 note 裡的「〔k〕」在切分後換成
        /// 真正的條目序號
        var notes: [(text: String, mark: Int?)]
        /// 這一段一筆都沒有、卻在圖表或結束標題處停下時，停下處之後的條目開頭位置——即使這段沒被
        /// 選中，只要那些不在選中的清單裡，就要說出來（`extract` 決定）
        var orphan: (heading: Int, stop: Int, starts: [Int])?
        /// 清單停在哪裡（`line` 為 nil＝一路到文字結尾）。最後一筆在那裡還沒結束的話，要說出來——但雜訊行
        /// 在這裡還沒去掉，要等切分之後看那一筆本身（`extract` 決定）。`wrapSuspect`：停在大寫、單獨一行
        /// 的 Index／Appendix，而下一行以小寫開頭
        var stop: (line: Int?, kind: String, wrapSuspect: Bool)? = nil
    }

    /// 圖表之後找接續時的窗口：表格一格一行，本機一份真實論文要隔 1,095 行（R5 D7）
    static let floatContinuationWindow = 1500

    /// 「過長」的條目字數。本機 124 份可切的真實論文、5,519 筆：中位數 168 字、第 99 百分位 893 字；
    /// 超過 1,000 字的 51 筆有 32 筆是清單的最後一筆（R6）
    static let overlongEntry = 1000

    /// 一定是清單之後的結束標題：附錄、索引。這兩種不做接續判定——附錄裡的文獻清單可能剛好
    /// 按字母順序接得上（T3、T18b），而它們從不穿插在清單中間。
    static let hardEndPattern =
        "^(?:\\d+\\.?\\s+)?(?:(?:appendix|appendices)\\b[^()]{0,80}|(?:subject |author |name )?index(?:es)?)\\s*:?$"

    /// 第 `j` 行是附錄或索引的終點——不是某一筆換行換出來的一行。
    ///
    /// 以小寫開頭的不是（R6 E5）：標題不會以小寫開頭，`appendix in children. Journal …` 是標題的
    /// 續行；原本清單在那裡結束，最後一筆的後半與 DOI 無聲丟掉。
    ///
    /// 大寫開頭、單獨一行的 `Index` 分不出來：本機語料裡「前一行還沒結束」的附錄／索引行 118 個，
    /// 大寫開頭的 114 個幾乎都是真標題（書末索引每頁的頁首、前一行是不帶 `https://` 的網址），只憑
    /// 前一行判會把整份索引吸進最後一筆。這種照終點處理，由 `extract` 的「最後一筆還沒結束」說出來。
    static func isHardEnd(at j: Int, in lines: [String]) -> Bool {
        guard matches(lines[j], hardEndPattern, caseInsensitive: true) else { return false }
        return lines[j].first(where: \.isLetter)?.isLowercase != true
    }

    /// 單獨一行的 Index／Appendix（不帶編號或標題）——分不出是標題還是最後一筆換行換出來的字
    static let bareHardEndPattern =
        "^(?:\\d+\\.?\\s+)?(?:appendix|appendices|(?:subject |author |name )?index(?:es)?)\\s*:?$"

    /// 一筆像是結束了：句點、右括號或右方括號，或以 DOI／網址（不一定帶 `https://`）、頁碼區間結尾
    static func closesEntry(_ s: String) -> Bool {
        // 只看結尾：每一支都錨在 `$`。整段丟給正則時，一長串吸進來的數字讓 `\\d+…$` 變成二次方（R7 #1：
        // 20 萬字元跑了 7 分鐘）。`suffix` 以字元叢集計：一個字元後接大量組合字元時仍要走完那一串，成本
        // 線性（R8 L3：200 萬個約 3 秒 CPU，與前面 `clean` 的正規化同一量級）
        let t = String(s.suffix(200)).replacingOccurrences(of: softHyphenMark, with: "").trimmingCharacters(in: .whitespaces)
        guard let last = t.last else { return true }
        if ".)]".contains(last) { return true }
        // 頁碼區間結尾（`12, 345–367`）：不以句點結尾的書目格式
        return matches(t, "(?:https?://|doi:\\s*|\\b10\\.\\d{4,9}/|\\bwww\\.)\\S+$|\\.(?:com|org|net|edu|gov)(?:/\\S*)?$|\\d+\\s?[-–]\\s?\\d+$",
                       caseInsensitive: true)
    }

    /// 圖表標題（`Table 3`、`Figure 2.`）——雙欄期刊的浮動圖表會落在清單中間
    static let floatPattern = "^(?:table|figure)\\s+\\d+\\.?\\s*:?$"

    /// 斷點之後找接續的條目時，最多往後看幾行非空行
    static let continuationWindow = 60

    /// 把標題候選分成一份一份的清單。
    ///
    /// 清單會被三種**斷點**打斷：又出現一次的**同一個**參考文獻標題（頁首）、圖表標題、其他結束
    /// 標題（補充資料、致謝、註——雙欄版面會把它們穿插進清單）。附錄與索引不是斷點，是終點
    /// （`hardEndPattern`）；文字不同的標題候選（表格欄名 `Reference`）也不是頁首。每遇到一個
    /// 斷點，只問一件事——**斷點之後，是不是同一份清單接下去？**（R3：R1 取最後一個標題、R2 取
    /// 條目最多且在下一個候選截止，兩次都各修一種版面、弄壞另一種，因為都沒問這件事。）
    ///
    /// 判準：斷點之後第一個條目開頭（往後至多 `continuationWindow` 行，不越過另一個標題候選或
    /// 非圖表的結束標題）
    /// 1. 是**完整條目**——帶 `(年份).`（表格列、索引行沒有）；而且
    /// 2. 作者**按字母順序接得上**斷點前的最後一筆（作者—年份清單依第一作者排序；目錄沒有條目、
    ///    表格欄名之後的表格列不是完整條目）；或者斷點是結束標題、而它排在這份清單的第一筆之前
    ///    ——雙欄版面被讀反（`continues`）。
    ///
    /// 兩項都成立 → 同一份清單：斷點區略過，說出來。否則清單在斷點處結束；斷點之後若還有完整
    /// 條目，說出數目。
    static func groups(_ candidates: [Int], in lines: [String], pages: [Int], place: (Int) -> String) -> [Group] {
        var result: [Group] = []
        let candidateSet = Set(candidates)
        var k = 0
        while k < candidates.count {
            let heading = candidates[k]
            var out: [String] = []
            var notes: [(text: String, mark: Int?)] = []
            var orphan: (heading: Int, stop: Int, starts: [Int])?
            var stop: (line: Int?, kind: String, wrapSuspect: Bool)?
            var runningHeads: [Int] = []
            var order = Order()
            var entries = 0
            var previous = ""
            var i = heading + 1
            while i < lines.count {
                let line = lines[i]
                let isHeading = candidateSet.contains(i)
                // 以小寫開頭的是某一筆換行換出來的一行，不是標題，照一般的行收（R6 E5：`appendix in
                // children. Journal …` 原本讓清單在那裡結束）
                let isEnd = !isHeading && matches(line, endPattern, caseInsensitive: true)
                    && line.first(where: \.isLetter)?.isLowercase != true
                if isHeading || isEnd {
                    let isFloat = isEnd && matches(line, floatPattern, caseInsensitive: true)
                    let sameHeading = isHeading && line.caseInsensitiveCompare(lines[heading]) == .orderedSame
                    let canContinue = isHeading
                        // 頁首：同文字，而且清單到這裡為止，每跨兩頁至少有一筆完整條目——目錄裡同文字的
                        // 標題與真正的清單隔著整份正文，過不了這一關（R4 B3）
                        ? sameHeading && order.full * 2 >= max(1, pages[i] - pages[heading])
                        : !matches(line, hardEndPattern, caseInsensitive: true)
                    let window = isFloat ? floatContinuationWindow : continuationWindow
                    if canContinue, let j = continuation(after: i, in: lines, candidates: candidateSet, window: window) {
                        let how: String?
                        if endsInAuthorList(previous) {
                            // 斷點前一行正在列作者：斷點之後那一行是同一筆的共同作者，不比字母順序（R5 D5）。
                            // 只看作者清單的形狀，不看「以逗號結尾」——期刊名後面也是逗號，那樣會跳過
                            // 字母順序、把停下並說出來的情形變成無聲併入（R6 D5）
                            how = "斷點前正在列作者，是同一筆"
                        } else if order.last == nil {
                            // 第一筆之前的圖表或結束標題（R4 A3-4）：沒有可比的，之後是完整條目就是清單的開頭
                            how = isHeading ? nil : "清單第一筆在它之後"
                        } else {
                            // 雙欄讀反只用在非圖表的結束標題（R4 A3-2）
                            how = order.accept(sortKey(lines[j]), columnSwapAllowed: isEnd && !isFloat)
                        }
                        if let how {
                            if isHeading {
                                // 只略過標題這一行：之後的行照常收，跨頁條目的後半才留得住（R4 A1）
                                runningHeads.append(i)
                                i += 1
                                continue
                            }
                            let kind = isFloat ? "圖表標題" : "結束標題"
                            let skipped = lines[(i + 1)..<j].filter { !$0.isEmpty }.count
                            if entries == 0 {
                                notes.append(("\(place(i))的\(kind)夾在清單中間（清單第一筆之前）：清單在\(place(j))開始"
                                              + "（\(how)）——中間 \(skipped) 行略過", nil))
                            } else {
                                notes.append(("\(place(i))的\(kind)夾在清單中間（第 〔k〕 筆之後）：清單在\(place(j))接續"
                                              + "（\(how)）——中間 \(skipped) 行略過；第 〔k〕 筆若有一段落在其中，會缺那一段", out.count))
                            }
                            i = j
                            continue
                        }
                    }
                    // 最後一筆跨頁：頁首之後沒有下一筆可接，但到清單結束前也沒有別的條目開頭——那是最後
                    // 一筆的後半，照頁首處理（R5 D8）
                    if sameHeading && order.last != nil && order.full * 2 >= max(1, pages[i] - pages[heading])
                        && entryStartLines(after: i, in: lines, candidates: candidateSet).isEmpty
                        && lines[(i + 1)...].contains(where: { !$0.isEmpty }) {
                        runningHeads.append(i)
                        i += 1
                        continue
                    }
                    if isEnd {
                        let kind = isFloat ? "圖表標題" : "結束標題"
                        let following = fullEntries(after: i, in: lines, candidates: candidateSet)
                        if following > 0 {
                            notes.append(("清單停在\(place(i))的\(kind)，但它之後還有 \(following) 個條目開頭沒有計入"
                                          + "（字母順序接不上，或不在接續範圍內）——若那些也是參考文獻，這份清單被截斷了", nil))
                        }
                    }
                    // 停在附錄或索引的不算：那之後的條目開頭屬於附錄或索引（它們不穿插在清單中間）。目錄裡
                    // `References` 下一行就是 `Index`，本機一本書因此誤報（R6）
                    if entries == 0 && isEnd && !matches(line, hardEndPattern, caseInsensitive: true) {
                        orphan = (heading, i, entryStartLines(after: i, in: lines, candidates: candidateSet))
                    }
                    if entries > 0 {
                        let kind = isHeading ? "參考文獻標題" : isFloat ? "圖表標題" : "結束標題"
                        // 往後至多看 `continuationWindow` 行，與其他往後看的地方一致（R8 #6）
                        let next = lines[(i + 1)..<min(lines.count, i + 1 + continuationWindow)]
                            .first { !$0.isEmpty && !matches($0, "^\\d{1,4}$") }
                        let suspect = matches(line, bareHardEndPattern, caseInsensitive: true)
                            && next?.first(where: \.isLetter)?.isLowercase == true
                        stop = (i, kind, suspect)
                    }
                    break
                }
                out.append(line)
                if !line.isEmpty && !matches(line, "^\\d{1,4}$") {
                    // 只有真正的新一筆才更新排序鍵：作者清單換行的那一行不算（R4 A2）；頁碼行不算「前一行」
                    // ——作者清單跨頁時，中間夾著頁碼（R5 D5）
                    if isEntryStart(line) && !continuesAuthorList(previous) {
                        entries += 1
                        order.see(sortKey(line), full: isFullEntry(at: i, in: lines))
                    }
                    previous = line
                }
                i += 1
            }
            if i >= lines.count && entries > 0 { stop = (nil, "文字結尾", false) }
            if !runningHeads.isEmpty {
                // 位置只列前 5 個——長書的頁首出現幾十次，全列會被 warning 的長度上限截掉（R4 B10）
                let shown = runningHeads.prefix(5).map(place).joined(separator: "、")
                notes.append(("參考文獻標題在清單中又出現 \(runningHeads.count) 次（\(shown)\(runningHeads.count > 5 ? " 等" : "")），"
                              + "其後接得上同一份清單——視為頁首，只略過標題那一行、併入同一份清單", nil))
            }
            result.append(Group(heading: heading, lines: out, range: (heading + 1)..<i, notes: notes, orphan: orphan, stop: stop))
            k = candidates.firstIndex(where: { $0 >= i && !runningHeads.contains($0) }) ?? candidates.count
        }
        return result
    }

    /// 一份清單到目前為止的排序狀態。
    ///
    /// 接續的判準（`accept`）：
    /// - 之後的第一筆不排在斷點前最後一筆之前 → 字母順序接得上
    /// - 排在這份清單第一筆之前、而且允許雙欄讀反（非圖表的結束標題）→ pdftotext 先讀了後半所在
    ///   的那一欄。R3 用本機真實論文量到的兩例都是這樣：結束標題前是 B–P，之後從 A 開始
    /// - 讀反**只會發生一次**：之後只照第一條接續（R4 A3-1：沒有這一條，`[≥ last] ∪ [< first]`
    ///   從此涵蓋整個字母表）。R4 另設的上界（只接受讀反那一欄）被語料否定：兩份真實讀反之後都一路
    ///   排過了那個上界，上界會在下一個斷點截斷真實清單（R5 D4）
    struct Order {
        private(set) var first: String?
        private(set) var last: String?
        private(set) var swapped = false
        private(set) var full = 0

        mutating func see(_ key: String, full isFull: Bool) {
            if first == nil { first = key }
            last = key
            if isFull { full += 1 }
        }

        mutating func accept(_ next: String, columnSwapAllowed: Bool) -> String? {
            guard let first, let last else { return nil }
            let o: String.CompareOptions = [.caseInsensitive, .diacriticInsensitive]
            if next.compare(last, options: o) != .orderedAscending { return "字母順序接得上" }
            if columnSwapAllowed && !swapped && next.compare(first, options: o) == .orderedAscending {
                swapped = true
                return "之後的條目排在清單開頭之前——雙欄版面的另一欄"
            }
            return nil
        }
    }

    /// 斷點 `i` 之後第一個條目開頭的位置——若它是完整條目。越過圖表標題與會穿插的結束標題（補充
    /// 資料、致謝、註——R4 A3-3：原本在它們那裡就停，圖表之後緊接著補充資料時清單在圖表處截斷），
    /// 不越過另一個標題候選、附錄或索引；窗口內沒有條目開頭、或第一個條目開頭不完整，回 nil。
    static func continuation(after i: Int, in lines: [String], candidates: Set<Int>,
                             window: Int = continuationWindow) -> Int? {
        var seen = 0
        var j = i + 1
        while j < lines.count && seen < window {
            let l = lines[j]
            if !l.isEmpty {
                if candidates.contains(j) { return nil }
                if isHardEnd(at: j, in: lines) { return nil }
                if isEntryStart(l) { return isFullEntry(at: j, in: lines) ? j : nil }
                seen += 1
            }
            j += 1
        }
        return nil
    }

    /// 斷點之後、到下一個標題候選、附錄或索引之前，完整條目的數目（只用來寫 warning）
    static func fullEntries(after i: Int, in lines: [String], candidates: Set<Int>) -> Int {
        var n = 0
        var j = i + 1
        while j < lines.count {
            let l = lines[j]
            if candidates.contains(j) { break }
            // 緊接在斷點之後的附錄或索引也是終點（R5 E4：原本從第二行才開始算）
            if isHardEnd(at: j, in: lines) { break }
            if isEntryStart(l) && isFullEntry(at: j, in: lines) { n += 1 }
            j += 1
        }
        return n
    }

    /// 斷點之後、到下一個標題候選、附錄或索引之前，條目開頭（不論完不完整）的位置
    static func entryStartLines(after i: Int, in lines: [String], candidates: Set<Int>) -> [Int] {
        var out: [Int] = []
        var j = i + 1
        while j < lines.count {
            let l = lines[j]
            if candidates.contains(j) || isHardEnd(at: j, in: lines) { break }
            if isEntryStart(l) { out.append(j) }
            j += 1
        }
        return out
    }

    /// 從 `j` 起，年份括號後面接著標題：`(2001). Title`、`(2001). 25 years`、`(1995): Title`、
    /// `(1995) Two words`、`(2003) ‘Quoted’`、`(2003) Oneword.`（R5 D3：R4 只認兩個字，Harvard 的
    /// 引號標題與單字標題被當成不完整，斷點之後會被無聲截斷）。
    /// 表格列後面是數字（`(2003) 120 .35`）或一個字再接數字（`(2003) RCT 120`，R4 B2），索引行
    /// （`姓, 名., 288`）沒有年份括號。只認 `(年份).` 太窄——非 APA 的作者—年份書目寫 `(1995):`，
    /// 本機真實書籍實測因此在頁首處斷開
    ///
    /// 往下看至多 6 行（長的作者清單會把年份推到第 4 行以後），但不越過下一筆條目——否則一筆沒有
    /// 年份的短條目會借到下一筆的年份。作者清單換行的那一行也長得像條目開頭，要照 `split` 的規則
    /// 認：前一行以 `,`／`;`／`&`／`and`／刪節號結尾的，是作者清單的延續，不是下一筆。
    static func isFullEntry(at j: Int, in lines: [String]) -> Bool {
        var end = j + 1
        while end < min(j + 6, lines.count),
              !(isEntryStart(lines[end]) && !continuesAuthorList(lines[end - 1])) { end += 1 }
        let text = lines[j..<end].joined(separator: " ")
        guard let m = firstMatch(text, "([({](?:\\d{4}[a-z]?|n\\.\\s?d\\.|in press|in preparation|submitted|forthcoming)[^(){}]{0,40}[)}])"
                                     + "(?:[.:,]\\s*[\\p{L}\\d\"“‘'\\[]|\\s+[\"“‘'\\[]|\\s+\\p{L}[\\p{L}'’\\-]*(?:[.:,]|\\s+[\\p{L}\"“‘'\\[]))",
                                 caseInsensitive: true) else { return false }
        // 表格列：姓名**緊接**年份、年份之後**完全沒有實在的字**——四個字母以上、不是縮寫，或是漢字、
        // 假名、韓文。真條目的標題或期刊名幾乎一定有這種字；`(2003) USA, 120, .35`、`(2003). 150 .40`、
        // `(2003). Vol. 12, 45-67, .35`、`(2005) U.S.A. 120 .35` 沒有。年份放在最後的書目（`Adams, J.
        // Title. Journal, 1, 1–2 (2001).` ＋ 下一筆的標籤）實在的字在姓名與年份之間——R9 修正輪只看年份之後，
        // 本機一本這種書從 86 筆掉到 33 筆，清單在每一頁的頁首斷開。
        //
        // 為什麼不數「數字是否多於字詞」：R6–R8 三輪都用它，每一輪都在界定「標題段在哪裡結束」時往一邊
        // 壞——R6 把短標題、多頁碼的真條目當成表格列，R7 讓縮寫開頭的表格列過關，R8 又讓以 `U.K.` 結尾
        // 的真標題數進卷期頁（R7 #0、R8 #0、R9 #0）。兩種錯的代價不對稱：多收一列表格只多一筆「只在 PDF」
        // 的條目；把真條目判成表格列，斷點之後的清單會無聲消失。所以這一條寧可多收：只擋一個實在的字
        // 都沒有的列，字詞多的表格列（`(2003) Total 120 .35`）寫進 SKILL 的〈已知限制〉
        let ns = text as NSString
        let bracket = m.range(at: 1)
        if ns.substring(from: bracket.location + bracket.length).split(separator: " ").contains(where: isSubstantiveWord) {
            return true
        }
        // 姓名（`姓, 名縮寫.`）之後、年份之前：共同作者的姓也算——多作者的表格列因此會被收進來，寧可多收
        let nameEnd = firstMatch(text, personNamePattern).map { $0.range.location + $0.range.length } ?? bracket.location
        guard nameEnd < bracket.location else { return false }
        return ns.substring(with: NSRange(location: nameEnd, length: bracket.location - nameEnd))
            .split(separator: " ").contains(where: isSubstantiveWord)
    }

    /// 實在的字（`isFullEntry` 用）：四個字母以上、不是冊期頁版這類縮寫；或含漢字、假名、韓文
    static func isSubstantiveWord(_ token: Substring) -> Bool {
        if token.unicodeScalars.contains(where: { $0.properties.isAlphabetic && $0.value >= 0x3040 }) { return true }
        let letters = token.filter(\.isLetter).lowercased()
        return letters.count >= 4 && !notWords.contains(letters)
    }

    /// 四個字母以上、但不算實在的字的縮寫
    static let notWords: Set<String> = ["vols", "suppl", "supp", "sect", "chap"]

    /// 排序鍵：第一作者（個人作者取第一個逗號之前，機構作者取 `. (` 之前），去掉大小寫與重音
    static func sortKey(_ line: String) -> String {
        let head = line.components(separatedBy: matches(line, personStartPattern) ? "," : ". (").first ?? line
        return head.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
    }

    static func isEntryStart(_ line: String) -> Bool {
        (matches(line, personStartPattern) && !isLocationLine(line)) || matches(line, groupStartPattern)
    }

    /// 逐行併成條目。新條目只在「目前這筆已經有年份括號」時才開始——作者清單換行時，
    /// 下一行（`Garcia, T. (2012). …`）看起來也像一筆的開頭。
    ///
    /// `absorbed` 回報「吸收了一行條目開頭、而上一行不是作者清單的延續（不以 `,`／`&`／`and`
    /// 結尾）」的條目序號（#617 verify F1）：那是前一筆年份沒認出來、兩筆被併成一筆的訊號。
    /// 原本唯一的併筆偵測是「沒有年份」，但併入後的條目帶著下一筆的年份，那條永遠不會觸發。
    ///
    /// `skip` 是雜訊行的位置：不併進任何一筆，但記下它落在第幾筆（`skippedIn`）——
    /// 夾在兩筆之間的算前一筆（那時前一筆還沒結束）。
    ///
    /// `marks` 是斷點的位置：回傳每個斷點**之前**那一筆的序號（斷點前還沒有任何一筆則是 0）。
    static func split(_ lines: [String], skip: Set<Int> = [], marks: [Int] = [])
        -> (entries: [String], absorbed: [Int], skippedIn: [Int], markedEntries: [Int]) {
        var entries: [String] = []
        var absorbed: [Int] = []
        var skippedIn: [Int] = []
        var markedAt: [Int: Int] = [:]
        var current = ""
        for (i, line) in lines.enumerated() {
            if marks.contains(i) && markedAt[i] == nil { markedAt[i] = current.isEmpty ? entries.count : entries.count + 1 }
            if skip.contains(i) {
                let n = entries.count + 1
                if skippedIn.last != n { skippedIn.append(n) }
                continue
            }
            if !current.isEmpty && isEntryStart(line) && yearParen(in: current) != nil {
                entries.append(current)
                current = line
            } else if current.isEmpty {
                // 段首若不是條目開頭（例如殘留的段落文字），仍從這行起算，交給 warnings 揭露
                current = line
            } else {
                if isEntryStart(line) && !continuesAuthorList(current),
                   absorbed.last != entries.count + 1 {
                    absorbed.append(entries.count + 1)
                }
                current = join(current, line)
            }
        }
        let final = current.isEmpty ? entries.count : entries.count + 1
        if !current.isEmpty { entries.append(current) }
        return (entries.map { $0.replacingOccurrences(of: softHyphenMark, with: "") }, absorbed, skippedIn,
                marks.map { markedAt[$0] ?? final })
    }

    /// 作者清單換到下一行的樣子：以逗號、`&` 或 `and` 結尾
    static func continuesAuthorList(_ s: String) -> Bool {
        let t = s.trimmingCharacters(in: .whitespaces)
        // APA 7 以刪節號省略第 20 位之後的作者（`…, . . .` 換行接最後一位，R2 G10）
        return t.hasSuffix(",") || t.hasSuffix(";") || t.hasSuffix("&") || t.lowercased().hasSuffix(" and")
            || t.hasSuffix("...") || t.hasSuffix("…") || t.hasSuffix(". . .")
    }

    /// 比 `continuesAuthorList` 窄：這一行**確實**在列作者——以 `&`、`and`、刪節號結尾，或以名縮寫
    /// 加逗號／分號結尾（`Cole, M.,`、`Chen, H.-Y.;`）。只以逗號結尾的不算：期刊名、書名後面也是
    /// 逗號（R6 D5）。斷點處用這一個，因為它會跳過字母順序的檢查
    static func endsInAuthorList(_ s: String) -> Bool {
        let t = s.trimmingCharacters(in: .whitespaces)
        if t.hasSuffix("&") || t.lowercased().hasSuffix(" and") || t.hasSuffix("...") || t.hasSuffix("…")
            || t.hasSuffix(". . .") { return true }
        return matches(t, "(?:^|[\\s,\\-])\\p{Lu}\\.[,;]$")
    }

    /// 續行接合：行尾是連字號、破折號或斜線（URL）時不加空白，其餘加一個空白。
    /// 連字號保留——分不出是斷字還是複合字（`Within-person`）；比對端正規化時會去掉它。
    static func join(_ a: String, _ b: String) -> String {
        if a.hasSuffix(softHyphenMark) { return String(a.dropLast()) + b }
        if let last = a.last, "-–—/".contains(last) { return a + b }
        // APA 在標點前斷行的 DOI／URL 接回、不留空白：`…/0022-3514` ＋ `.40.2.226`（#617 verify）、
        // SICI 的 `(199901)55:1<1::…>`、URL 的 `?id=`（R2 G10）。`(` 只在括號內沒有空白時才接
        // ——`(Original work published 1950)` 是附註，不是 DOI 的一段
        if let first = b.first, let token = a.split(separator: " ").last,
           token.contains("10.") || token.contains("http") {
            if "._-/)?=&#%~;:<>".contains(first) { return a + b }
            if first == "(", matches(b, "^\\([^\\s()]*\\)") { return a + b }
        }
        return a + " " + b
    }

    static func fields(of text: String, index: Int) -> Reference {
        var ref = Reference(index: index, raw: text, firstAuthor: nil, authors: [],
                            groupAuthor: false, year: nil, yearSuffix: nil, yearNote: nil,
                            title: nil, doi: nil)
        ref.doi = doi(in: text)

        guard let m = yearParen(in: text) else {
            // 沒有年份：作者段無從界定，只留原文與 DOI
            return ref
        }
        let ns = text as NSString
        if let y = group(m, 1, in: ns) { ref.year = Int(y) }
        ref.yearSuffix = group(m, 2, in: ns)
        if group(m, 3, in: ns) != nil { ref.yearNote = "n.d." }
        if let note = group(m, 4, in: ns) { ref.yearNote = note.lowercased() }

        let authorPart = ns.substring(to: m.range.location)
        let afterStart = m.range.location + m.range.length
        let afterParen = ns.substring(from: afterStart)
        let rest = afterParen.drop(while: { $0 != ")" && $0 != "}" }).dropFirst()

        if matches(text, personStartPattern) {
            ref.authors = surnames(in: authorPart)
        } else {
            let name = authorPart.trimmingCharacters(in: CharacterSet(charactersIn: ". ").union(.whitespaces))
            ref.groupAuthor = true
            ref.authors = name.isEmpty ? [] : [name]
        }
        ref.firstAuthor = ref.authors.first
        ref.title = title(in: String(rest))
        return ref
    }

    /// 作者段依逗號切開後，姓與名縮寫交替出現：取偶數位置。先拿掉 `(Ed.)`、`Jr.` 這類
    /// 會打亂交替的成分；`et al.` 與刪節號跳過。
    static func surnames(in authorPart: String) -> [String] {
        var s = replacing(authorPart, "\\((?:Eds?|Trans|Comp|Dir)\\.\\)\\.?", with: "")
        s = replacing(s, ",\\s*(?:Jr|Sr)\\.?(?=,|\\s|$)", with: "")
        s = replacing(s, ",\\s*(?:II|III|IV)(?=,|\\s|$)", with: "")
        let tokens = s.components(separatedBy: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        var out: [String] = []
        for (i, token) in tokens.enumerated() where i % 2 == 0 {
            var t = token
            for prefix in ["&", "and ", "…", "..."] where t.hasPrefix(prefix) {
                t = String(t.dropFirst(prefix.count)).trimmingCharacters(in: .whitespaces)
            }
            if t.isEmpty || t.lowercased().hasPrefix("et al") { continue }
            out.append(t)
        }
        return out
    }

    /// 年份括號之後、到第一個句末標點為止。前一個詞只有一個字母的句點（`U.S.`、名縮寫）
    /// 不算句末；問號與驚嘆號屬於標題本身。
    static func title(in rest: String) -> String? {
        let body = Array(rest.drop(while: { ".: ".contains($0) }))
        var out = ""
        var previousWord = ""
        var depth = 0
        for (i, ch) in body.enumerated() {
            if ch == "." {
                let isInitial = previousWord.count == 1 && previousWord.first?.isLetter == true
                // 小數點（`2.5`）不是句末（#617 verify F14）
                let isDecimal = i > 0 && body[i - 1].isNumber && i + 1 < body.count && body[i + 1].isNumber
                // 常見縮寫不是句末（R2 G4：截斷的標題會讓 store 比對漏網）——但要看上下文（R3 M9：
                // `Learning to say no.` 的 `no.` 就是句末，不看上下文會把期刊名吞進標題）
                // 括號深度逐字累計，不在每個句點重數（R4 B8：重數是二次方）
                let rest = body[(i + 1)...].drop(while: { $0 == " " })
                let isAbbreviation = isTitleAbbreviation(previousWord.lowercased(),
                                                          nextToken: String(rest.prefix(while: { $0.isLetter || $0.isNumber })),
                                                          insideParens: depth > 0)
                if !isInitial && !isDecimal && !isAbbreviation { break }
            }
            out.append(ch)
            if ch == "(" { depth += 1 } else if ch == ")" && depth > 0 { depth -= 1 }
            if ch == "?" || ch == "!" { break }
            previousWord = ch.isLetter ? previousWord + String(ch) : ""
        }
        var t = out.trimmingCharacters(in: .whitespaces)
        // 標題在括號裡就結束了（`Title (Vol. II. Part A)` 在 `II.` 結束）：未閉合的括號殘片不屬於標題
        // （R4 B4）
        // 只切冊次、版次這類殘片（R5 E1：標題停在括號內的 `?` 時，括號裡是正當的標題文字）
        if depth > 0, let open = t.lastIndex(of: "("),
           matches(String(t[t.index(after: open)...]), "^\\s*(?:vols?|no|eds?|pp|rev|trans)\\.", caseInsensitive: true) {
            t = String(t[..<open]).trimmingCharacters(in: .whitespaces)
        }
        // 正則不以 `\s*` 開頭，改成事後去空白——長空白串上的 `\s*…$` 是二次方（R4 B8）
        // 尾端的 `[…]`：直接找最後一個 `[`，不用正則——一長串 `[` 上的正則是二次方（R5 E3）
        if t.hasSuffix("]"), let open = t.lastIndex(of: "["), !t[t.index(after: open)...].dropLast().contains("]") {
            t = String(t[..<open]).trimmingCharacters(in: .whitespaces)
        }
        // 尾端的版次、冊次、編者括號（`(3rd ed.)`、`(6th ed., Vol. 3)`、`(Vol. 2)`、
        // `(J. Smith, Ed.; 3rd ed.)`）不屬於標題本身（R3 M8：G4 只去掉純版次的括號）
        // 報告編號（`(No. IV)`）同理（R6 INFO）
        t = replacing(t, "\\((?=[^()]*\\b(?:ed|eds|vol|vols|trans|rev|pp|no)\\.)[^()]*\\)$", with: "",
                      caseInsensitive: true).trimmingCharacters(in: .whitespaces)
        // 逗號式書目的冊次、頁碼在句點處被切下之後留下的殘片（`Collected papers, Vol`、`…, pp`，R6 INFO）
        t = replacing(t, ",\\s*(?:vols?|pp)$", with: "", caseInsensitive: true)
        return t.isEmpty ? nil : t
    }

    /// 標題裡的句點前一個詞是不是縮寫（R3 M9：看上下文，封閉的四類）：
    /// - `vs` → 一律是縮寫
    /// - `no`、`vol`、`vols` → 後面接數字才是（`No. 2`）；接**整個字都是**羅馬數字、而且在括號內才是
    ///   （`(Vol. II)`）——`say no. International Journal` 的 `I` 不是羅馬數字（R5 D2：R4 只看第一個字元）
    /// - `pp` → 在括號內、後面接數字才是（`(pp. 10–20)`）；逗號式書目的 `, pp. 1–20` 在括號外，是句末
    /// - `ed`、`eds`、`trans`、`rev` → 在括號內才是（`(3rd ed.)`）
    /// - `st` → 後面接大寫字母才是（`St. Louis`）
    static func isTitleAbbreviation(_ word: String, nextToken: String, insideParens: Bool) -> Bool {
        let digit = nextToken.first?.isNumber == true
        switch word {
        case "vs": return true
        case "no", "vol", "vols":
            return digit || (insideParens && !nextToken.isEmpty && nextToken.allSatisfy { "IVXLC".contains($0) })
        case "pp": return insideParens && digit
        case "ed", "eds", "trans", "rev": return insideParens
        case "st": return nextToken.first?.isUppercase == true
        default: return false
        }
    }

    static func doi(in text: String) -> String? {
        let ns = text as NSString
        guard let m = firstMatch(text, doiPattern, caseInsensitive: true)
                ?? firstMatch(text, bareDOIPattern),
              var d = group(m, 1, in: ns) else { return nil }
        while let last = d.last, ".,;".contains(last) { d.removeLast() }
        // 括號數只數一次，之後逐次遞減（R5 E3：每次都重數是二次方）
        var close = d.filter { $0 == ")" }.count
        let open = d.filter { $0 == "(" }.count
        while d.hasSuffix(")") && close > open {
            d.removeLast()
            close -= 1
        }
        return d.isEmpty ? nil : d
    }

    // MARK: - 正則工具

    /// 編譯過的樣式快取（R3 M2：每行都重新編譯，60 個圖表標題就要 11 秒）
    final class RegexCache: @unchecked Sendable {
        private var store: [String: NSRegularExpression] = [:]
        private let lock = NSLock()
        func get(_ key: String, _ make: () -> NSRegularExpression) -> NSRegularExpression {
            lock.lock(); defer { lock.unlock() }
            if let r = store[key] { return r }
            let r = make()
            store[key] = r
            return r
        }
    }
    static let regexCache = RegexCache()

    static func regex(_ pattern: String, caseInsensitive: Bool) -> NSRegularExpression {
        // 樣式全是本檔的常量；編譯失敗是程式錯誤，不是輸入錯誤
        regexCache.get((caseInsensitive ? "i:" : "s:") + pattern) {
            try! NSRegularExpression(pattern: pattern, options: caseInsensitive ? [.caseInsensitive] : [])
        }
    }

    static func firstMatch(_ s: String, _ pattern: String,
                           caseInsensitive: Bool = false) -> NSTextCheckingResult? {
        regex(pattern, caseInsensitive: caseInsensitive)
            .firstMatch(in: s, range: NSRange(location: 0, length: (s as NSString).length))
    }

    static func matches(_ s: String, _ pattern: String, caseInsensitive: Bool = false) -> Bool {
        firstMatch(s, pattern, caseInsensitive: caseInsensitive) != nil
    }

    /// 年份括號不分大小寫：`(In press)` 與 `(in press)` 都是
    static func yearParen(in s: String) -> NSTextCheckingResult? {
        firstMatch(s, yearParenPattern, caseInsensitive: true)
    }

    static func group(_ m: NSTextCheckingResult, _ i: Int, in ns: NSString) -> String? {
        let r = m.range(at: i)
        return r.location == NSNotFound ? nil : ns.substring(with: r)
    }

    static func replacing(_ s: String, _ pattern: String, with template: String,
                          caseInsensitive: Bool = false) -> String {
        regex(pattern, caseInsensitive: caseInsensitive).stringByReplacingMatches(
            in: s, range: NSRange(location: 0, length: (s as NSString).length),
            withTemplate: template)
    }
}
