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

    /// 目前的輸出契約版本。輸出欄位或 warning 的語意改了就加一。
    static let contractVersion = 2

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
    /// verify F1 加的；右括號排成 `}` 的排版錯字（`(1996}.`，本機真實書籍實測）是 R3 加的；仍認不得的
    /// 由 `split` 的併筆 warning 揭露。
    static let yearParenPattern =
        "\\((?:(\\d{4})([a-z])?(?=\\s*[),/}]|\\s*[–—-])|(n\\.\\s?d\\.)|(in press|in preparation|submitted|forthcoming))"

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
        let sections = groups(candidates, in: lines, place: place)
        let starts = sections.map { $0.lines.filter(isEntryStart).count }
        // 條目開頭最多者；同數取後者（沿用原本「參考文獻段在正文之後」的偏好）
        let best = starts.indices.max { (starts[$0], $0) < (starts[$1], $1) } ?? 0
        let chosen = sections[best]
        var warnings: [String] = []
        let withEntries = starts.indices.filter { starts[$0] > 0 }
        if withEntries.count > 1 {
            let others = withEntries.filter { $0 != best }.map { "\(place(sections[$0].heading))：\(starts[$0]) 個" }
            warnings.append("有 \(withEntries.count) 個參考文獻標題候選都帶著條目；取條目開頭最多的那個"
                            + "（\(place(chosen.heading))，\(starts[best]) 個條目開頭）。其餘："
                            + others.joined(separator: "、")
                            + "——可能是目錄、附錄或表格；若其中有這份清單的一部分，清單被截斷了")
        }
        warnings += chosen.notes

        let nonEmpty = chosen.lines.filter { !$0.isEmpty }
        if nonEmpty.prefix(10).filter({ matches($0, numberedPattern) }).count >= 3 {
            throw ValidationError(
                "參考文獻段是數字編號格式（[1] …）——目前不支援，只處理作者—年份格式（#617 D7）")
        }

        let noise = noiseIndices(nonEmpty, documentLines: lines, section: chosen.range)
        guard nonEmpty.indices.contains(where: { !noise.contains($0) && isEntryStart(nonEmpty[$0]) }) else {
            throw ValidationError(
                "找到參考文獻標題，但段落裡沒有辨識出任何條目——段落可能是空的、被截斷，或不是作者—年份格式")
        }

        let (texts, absorbed, skippedIn) = split(nonEmpty, skip: noise)
        if !noise.isEmpty {
            let pageNumbers = noise.filter { matches(nonEmpty[$0], "^\\d{1,4}$") }.count
            // 不引 PDF 原文（R2 G10：warnings 會進模型的行動清單），只報落在哪幾筆
            warnings.append("略過 \(noise.count) 行：頁碼 \(pageNumbers) 行、在參考文獻段以外也出現的行"
                            + " \(noise.count - pageNumbers) 行（頁首頁尾、版權聲明），落在第 "
                            + skippedIn.map(String.init).joined(separator: "、")
                            + " 筆——這幾筆的標題或出處若看起來缺了一段，判為「判不了」")
        }
        let entries = texts.enumerated().map { offset, text in
            fields(of: text, index: offset + 1)
        }
        for n in absorbed {
            warnings.append("第 \(n) 筆吸收了一行看起來像新條目開頭的內容——可能兩筆併成一筆"
                            + "（前一筆的年份寫法沒認出來），作者與標題可能分屬兩筆")
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
    /// - 行尾軟連字號：換成一般連字號、**保留換行**（R2 直接接合，後面的行號全部少一）。接合交給
    ///   `join`（行尾是連字號時不加空白）；比對端的 `titleTokens` 會去掉連字號。
    /// - NFKC（連字 ﬁ → fi、不換行空白 → 空白），其餘格式字元與控制字元移除，頭尾空白去掉。
    static func normalizedLines(_ s: String) -> (lines: [String], pages: [Int]) {
        let t = s.replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .replacingOccurrences(of: "\t", with: " ")
            .replacingOccurrences(of: "\u{AD}\n", with: "-\n")
        var lines: [String] = []
        var pages: [Int] = []
        var page = 1
        for raw in t.components(separatedBy: "\n") {
            var rest = Substring(raw)
            while rest.first == "\u{0C}" { page += 1; rest = rest.dropFirst() }
            for (k, part) in rest.split(separator: "\u{0C}", omittingEmptySubsequences: false).enumerated() {
                if k > 0 { page += 1 }
                lines.append(clean(String(part)))
                pages.append(page)
            }
        }
        return (lines, pages)
    }

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
    static func noiseIndices(_ lines: [String], documentLines: [String], section: Range<Int>) -> Set<Int> {
        var outside: [String: Int] = [:]
        for (i, l) in documentLines.enumerated()
        where !l.isEmpty && !section.contains(i) && !matches(l, headingPattern, caseInsensitive: true) {
            outside[l, default: 0] += 1
        }
        var inside: [String: Int] = [:]
        if outside.isEmpty { for l in lines { inside[l, default: 0] += 1 } }
        return Set(lines.indices.filter { i in
            if matches(lines[i], "^\\d{1,4}$") { return true }
            if isEntryStart(lines[i]) { return false }
            return outside.isEmpty ? inside[lines[i], default: 0] >= 2 : outside[lines[i], default: 0] >= 1
        })
    }

    /// 一份清單：從 `heading` 開始，`lines` 是清單內的行（略過的斷點區不在內），`range` 是它在
    /// 全文的行號範圍（0 起算），`notes` 是只在選中這份時才輸出的 warning。
    struct Group {
        var heading: Int
        var lines: [String]
        var range: Range<Int>
        var notes: [String]
    }

    /// 一定是清單之後的結束標題：附錄、索引。這兩種不做接續判定——附錄裡的文獻清單可能剛好
    /// 按字母順序接得上（T3、T18b），而它們從不穿插在清單中間。
    static let hardEndPattern =
        "^(?:\\d+\\.?\\s+)?(?:(?:appendix|appendices)\\b[^()]{0,80}|(?:subject |author |name )?index(?:es)?)\\s*:?$"

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
    static func groups(_ candidates: [Int], in lines: [String], place: (Int) -> String) -> [Group] {
        var result: [Group] = []
        let candidateSet = Set(candidates)
        var k = 0
        while k < candidates.count {
            let heading = candidates[k]
            var out: [String] = []
            var notes: [String] = []
            var runningHeads: [Int] = []
            var first: String?
            var last: String?
            var i = heading + 1
            while i < lines.count {
                let line = lines[i]
                let isHeading = candidateSet.contains(i)
                let isEnd = !isHeading && matches(line, endPattern, caseInsensitive: true)
                if isHeading || isEnd {
                    let canContinue = isHeading
                        ? line.caseInsensitiveCompare(lines[heading]) == .orderedSame
                        : !matches(line, hardEndPattern, caseInsensitive: true)
                    if canContinue, let first, let last, let j = continuation(after: i, in: lines, candidates: candidateSet),
                       let how = continues(sortKey(lines[j]), first: first, last: last, columnSwapAllowed: !isHeading) {
                        if isHeading {
                            runningHeads.append(i)
                        } else {
                            let kind = matches(line, floatPattern, caseInsensitive: true) ? "圖表標題" : "結束標題"
                            let skipped = lines[(i + 1)..<j].filter { !$0.isEmpty }.count
                            notes.append("\(place(i))的\(kind)夾在清單中間：清單在\(place(j))接續（\(how)）"
                                         + "——中間 \(skipped) 行略過；那之前的最後一筆若有一段落在其中，會缺那一段")
                        }
                        i = j
                        continue
                    }
                    if isEnd {
                        let following = fullEntries(after: i, in: lines, candidates: candidateSet)
                        if following > 0 {
                            notes.append("清單停在\(place(i))的結束標題，但它之後還有 \(following) 個條目開頭沒有計入"
                                         + "（字母順序接不上，或不在接續範圍內）——若那些也是參考文獻，這份清單被截斷了")
                        }
                    }
                    break
                }
                out.append(line)
                if isEntryStart(line) {
                    let key = sortKey(line)
                    if first == nil { first = key }
                    last = key
                }
                i += 1
            }
            if !runningHeads.isEmpty {
                notes.append("參考文獻標題在清單中又出現 \(runningHeads.count) 次（\(runningHeads.map(place).joined(separator: "、"))），"
                             + "其後的條目按字母順序接得上——視為頁首，併入同一份清單")
            }
            result.append(Group(heading: heading, lines: out, range: (heading + 1)..<i, notes: notes))
            k = candidates.firstIndex(where: { $0 >= i && !runningHeads.contains($0) }) ?? candidates.count
        }
        return result
    }

    /// 斷點之後的第一個完整條目（排序鍵 `next`）是不是同一份清單的接續；是的話回傳怎麼接上的：
    /// - `next` 不排在斷點前最後一筆之前 → 字母順序接得上
    /// - `next` 排在這份清單的第一筆之前、而斷點不是標題候選 → 雙欄版面被讀反（pdftotext 先讀了
    ///   後半所在的那一欄）。R3 用本機真實論文量到的兩例都是這樣：結束標題前是 B–P，之後從 A 開始
    static func continues(_ next: String, first: String, last: String, columnSwapAllowed: Bool) -> String? {
        let opts: String.CompareOptions = [.caseInsensitive, .diacriticInsensitive]
        if next.compare(last, options: opts) != .orderedAscending { return "字母順序接得上" }
        if columnSwapAllowed && next.compare(first, options: opts) == .orderedAscending {
            return "之後的條目排在清單開頭之前——雙欄版面的另一欄"
        }
        return nil
    }

    /// 斷點 `i` 之後第一個條目開頭的位置——若它是完整條目。越過圖表標題，不越過另一個標題候選
    /// 或非圖表的結束標題；窗口內沒有條目開頭、或第一個條目開頭不完整，回 nil。
    static func continuation(after i: Int, in lines: [String], candidates: Set<Int>) -> Int? {
        var seen = 0
        var j = i + 1
        while j < lines.count && seen < continuationWindow {
            let l = lines[j]
            if !l.isEmpty {
                if candidates.contains(j) { return nil }
                if matches(l, endPattern, caseInsensitive: true) && !matches(l, floatPattern, caseInsensitive: true) { return nil }
                if isEntryStart(l) { return isFullEntry(at: j, in: lines) ? j : nil }
                seen += 1
            }
            j += 1
        }
        return nil
    }

    /// 斷點之後、到下一個標題候選或非圖表結束標題之前，完整條目的數目（只用來寫 warning）
    static func fullEntries(after i: Int, in lines: [String], candidates: Set<Int>) -> Int {
        var n = 0
        var j = i + 1
        while j < lines.count {
            let l = lines[j]
            if candidates.contains(j) { break }
            if j > i + 1 && matches(l, endPattern, caseInsensitive: true) && !matches(l, floatPattern, caseInsensitive: true) { break }
            if isEntryStart(l) && isFullEntry(at: j, in: lines) { n += 1 }
            j += 1
        }
        return n
    }

    /// 從 `j` 起，年份括號後面接著標題：`(2001). Title`、`(1995): Title`、`(1995) Title`。
    /// 表格列（`(2003) 120 .35`）後面是數字，索引行（`姓, 名., 288`）沒有年份括號。只認 `(年份).`
    /// 太窄——非 APA 的作者—年份書目寫 `(1995):`，本機真實書籍實測因此在頁首處斷開
    ///
    /// 往下看至多 6 行（長的作者清單會把年份推到第 4 行以後），但不越過下一筆條目——否則一筆沒有
    /// 年份的短條目會借到下一筆的年份。作者清單換行的那一行也長得像條目開頭，要照 `split` 的規則
    /// 認：前一行以 `,`／`;`／`&`／`and`／刪節號結尾的，是作者清單的延續，不是下一筆。
    static func isFullEntry(at j: Int, in lines: [String]) -> Bool {
        var end = j + 1
        while end < min(j + 6, lines.count),
              !(isEntryStart(lines[end]) && !continuesAuthorList(lines[end - 1])) { end += 1 }
        let text = lines[j..<end].joined(separator: " ")
        return matches(text, "\\((?:\\d{4}[a-z]?|n\\.\\s?d\\.|in press|in preparation|submitted|forthcoming)[^(){}]{0,40}[)}][.:,]?\\s*[\\p{L}\"“‘'\\[]",
                       caseInsensitive: true)
    }

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
    static func split(_ lines: [String], skip: Set<Int> = [])
        -> (entries: [String], absorbed: [Int], skippedIn: [Int]) {
        var entries: [String] = []
        var absorbed: [Int] = []
        var skippedIn: [Int] = []
        var current = ""
        for (i, line) in lines.enumerated() {
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
        if !current.isEmpty { entries.append(current) }
        return (entries, absorbed, skippedIn)
    }

    /// 作者清單換到下一行的樣子：以逗號、`&` 或 `and` 結尾
    static func continuesAuthorList(_ s: String) -> Bool {
        let t = s.trimmingCharacters(in: .whitespaces)
        // APA 7 以刪節號省略第 20 位之後的作者（`…, . . .` 換行接最後一位，R2 G10）
        return t.hasSuffix(",") || t.hasSuffix(";") || t.hasSuffix("&") || t.lowercased().hasSuffix(" and")
            || t.hasSuffix("...") || t.hasSuffix("…") || t.hasSuffix(". . .")
    }

    /// 續行接合：行尾是連字號、破折號或斜線（URL）時不加空白，其餘加一個空白。
    /// 連字號保留——分不出是斷字還是複合字（`Within-person`）；比對端正規化時會去掉它。
    static func join(_ a: String, _ b: String) -> String {
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
        let rest = afterParen.drop(while: { $0 != ")" }).dropFirst()

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
        for (i, ch) in body.enumerated() {
            if ch == "." {
                let isInitial = previousWord.count == 1 && previousWord.first?.isLetter == true
                // 小數點（`2.5`）不是句末（#617 verify F14）
                let isDecimal = i > 0 && body[i - 1].isNumber && i + 1 < body.count && body[i + 1].isNumber
                // 常見縮寫不是句末（R2 G4：截斷的標題會讓 store 比對漏網）——但要看上下文（R3 M9：
                // `Learning to say no.` 的 `no.` 就是句末，不看上下文會把期刊名吞進標題）
                let isAbbreviation = isTitleAbbreviation(previousWord.lowercased(),
                                                          next: body[(i + 1)...].first(where: { $0 != " " }),
                                                          insideParens: out.filter({ $0 == "(" }).count
                                                              > out.filter({ $0 == ")" }).count)
                if !isInitial && !isDecimal && !isAbbreviation { break }
            }
            out.append(ch)
            if ch == "?" || ch == "!" { break }
            previousWord = ch.isLetter ? previousWord + String(ch) : ""
        }
        var t = out.trimmingCharacters(in: .whitespaces)
        t = replacing(t, "\\s*\\[[^\\]]*\\]$", with: "")
        // 尾端的版次、冊次、編者括號（`(3rd ed.)`、`(6th ed., Vol. 3)`、`(Vol. 2)`、
        // `(J. Smith, Ed.; 3rd ed.)`）不屬於標題本身（R3 M8：G4 只去掉純版次的括號）
        t = replacing(t, "\\s*\\((?=[^()]*\\b(?:ed|eds|vol|vols|trans|rev)\\.)[^()]*\\)$", with: "",
                      caseInsensitive: true)
        return t.isEmpty ? nil : t
    }

    /// 標題裡的句點前一個詞是不是縮寫（R3 M9：看上下文，封閉的四類）：
    /// - `vs` → 一律是縮寫
    /// - `no`、`vol`、`vols` → 後面接數字才是（`No. 2`）；`Learning to say no.` 是句末
    /// - `ed`、`eds`、`trans`、`rev` → 在括號內才是（`(3rd ed.)`）
    /// - `st` → 後面接大寫字母才是（`St. Louis`）
    static func isTitleAbbreviation(_ word: String, next: Character?, insideParens: Bool) -> Bool {
        switch word {
        case "vs": return true
        case "no", "vol", "vols": return next?.isNumber == true
        case "ed", "eds", "trans", "rev": return insideParens
        case "st": return next?.isUppercase == true
        default: return false
        }
    }

    static func doi(in text: String) -> String? {
        let ns = text as NSString
        guard let m = firstMatch(text, doiPattern, caseInsensitive: true)
                ?? firstMatch(text, bareDOIPattern),
              var d = group(m, 1, in: ns) else { return nil }
        while let last = d.last, ".,;".contains(last) { d.removeLast() }
        while d.hasSuffix(")"),
              d.filter({ $0 == ")" }).count > d.filter({ $0 == "(" }).count {
            d.removeLast()
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
