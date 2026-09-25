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
    }

    // MARK: - 樣式

    /// 參考文獻段的標題：整行只有這幾個字（可帶章節編號與冒號）。有多個候選時取**段內條目開頭
    /// 最多**的那個（#617 verify F4：原本取最後一個，附錄或表格欄名的 `Reference` 會奪走標題、
    /// 前面整份清單被無聲丟棄）；目錄頁的同名字下面沒有條目開頭，自然落選。
    static let headingPattern =
        "^(?:\\d+(?:\\.\\d+)*\\.?\\s+)?(?:references?|reference list|bibliography|literature cited|works cited|參考文獻|参考文献|引用文獻)\\s*:?$"

    /// 段落的結束：參考文獻之後的附錄、註、致謝、表與圖。只認**整行**標題；附錄標題
    /// 不含括號（條目一定有年份括號，所以 `Appendix, J. (2001)` 不會被當成標題）。
    static let endPattern =
        "^(?:\\d+\\.?\\s+)?(?:(?:appendix|appendices)\\b[^()]{0,80}|supplementa(?:l|ry)(?: materials?| information)?|supporting information|notes|footnotes|endnotes|acknowledge?ments?|author note|(?:table|figure)\\s+\\d+\\.?)\\s*:?$"

    /// 數字編號格式（`[1] …`、`1. …`）
    static let numberedPattern = "^(?:\\[\\d{1,3}\\]|\\d{1,3}\\.\\s)"

    /// 姓前的小寫姓氏前綴（`van der Berg`、`de Haan`）
    static let particles = "(?:(?:van|von|de|der|den|du|la|le|di|da|del|dos|ten|ter)\\s+)*"

    /// 個人作者開頭的一筆：`姓, 名縮寫.`
    ///
    /// 連字號**只當分隔符**、不在字元類裡（#617 verify F8）：原本兩處都允許連字號，`Aa-Aa-…Aa!`
    /// 這種失敗行會被試遍所有切法，每多一段慢約 2.8 倍（20 段 16 秒）。名縮寫後接冒號的
    /// （`Cambridge, U.K.:`、`Washington, D.C.:`）是出版地續行，不是條目開頭。
    static let personStartPattern =
        "^" + particles + "\\p{Lu}[\\p{L}'’]+(?:[\\s\\-]\\p{Lu}[\\p{L}'’]+)*,\\s+\\p{Lu}\\.(?!(?:\\s?\\p{Lu}\\.)*\\s*:)"

    /// 機構作者開頭的一筆：`機構名. (年份`。機構名可以含句點（`U.S. Department …`，#617 verify）。
    static let groupStartPattern =
        "^\\p{Lu}[^()]{2,120}?\\.\\s\\((?:\\d{4}|n\\.\\s?d\\.|in press|in preparation|submitted|forthcoming)"

    /// 年份括號：`(2015)`、`(2015a)`、`(2015, March 3)`、區間 `(1998–2012)`／`(1998–99)`／`(2015–)`、
    /// 重印 `(1890/1950)`（都取第一年）、`(n.d.)`、`(in press)`／`(in preparation)`／`(submitted)`／
    /// `(forthcoming)`。認不得的寫法會讓下一筆被當成續行併進來——區間是 #617 校準加的，其餘是
    /// verify F1 加的；仍認不得的由 `split` 的併筆 warning 揭露。
    static let yearParenPattern =
        "\\((?:(\\d{4})([a-z])?(?=\\s*[),/]|\\s*[–—-])|(n\\.\\s?d\\.)|(in press|in preparation|submitted|forthcoming))"

    static let doiPattern =
        "(?:https?://(?:dx\\.)?doi\\.org/|doi:\\s*)(10\\.\\d{4,9}/\\S+)"
    static let bareDOIPattern = "\\b(10\\.\\d{4,9}/\\S+)"

    // MARK: - 入口

    static func extract(_ input: String) throws -> Result {
        let lines = normalize(input).components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }

        let candidates = lines.indices.filter { matches(lines[$0], headingPattern, caseInsensitive: true) }
        guard !candidates.isEmpty else {
            throw ValidationError(
                "找不到參考文獻段的標題（References／Bibliography／參考文獻 等獨立成行的標題）——"
                + "輸入可能不含參考文獻段，或標題與其他文字擠在同一行")
        }
        let sections = candidates.map { (index: $0, lines: section(after: $0, in: lines)) }
        let starts = sections.map { $0.lines.filter(isEntryStart).count }
        // 條目開頭最多者；同數取後者（沿用原本「參考文獻段在正文之後」的偏好）
        let best = starts.indices.max { (starts[$0], $0) < (starts[$1], $1) } ?? 0
        let chosen = sections[best].lines
        var warnings: [String] = []
        let withEntries = starts.filter { $0 > 0 }.count
        if withEntries > 1 {
            warnings.append("有 \(withEntries) 個參考文獻標題候選都帶著條目；取條目開頭最多的那個"
                            + "（第 \(sections[best].index + 1) 行，\(starts[best]) 個條目開頭）——其餘可能是附錄或表格")
        }

        let nonEmpty = chosen.filter { !$0.isEmpty }
        if nonEmpty.prefix(10).filter({ matches($0, numberedPattern) }).count >= 3 {
            throw ValidationError(
                "參考文獻段是數字編號格式（[1] …）——目前不支援，只處理作者—年份格式（#617 D7）")
        }

        let (kept, droppedLines) = dropNoise(nonEmpty, documentLines: lines)
        if !droppedLines.isEmpty {
            let pageNumbers = droppedLines.filter { matches($0, "^\\d{1,4}$") }.count
            let repeated = Array(Set(droppedLines.filter { !matches($0, "^\\d{1,4}$") })).sorted()
            var note = "略過 \(droppedLines.count) 行：頁碼 \(pageNumbers) 行、全文逐字重複的行 \(droppedLines.count - pageNumbers) 行"
            if !repeated.isEmpty {
                note += "（頁首頁尾、版權聲明；也可能是正當重複的續行）："
                    + repeated.prefix(3).map { "「\(String($0.prefix(60)))」" }.joined(separator: "")
            }
            warnings.append(note)
        }
        guard kept.contains(where: isEntryStart) else {
            throw ValidationError(
                "找到參考文獻標題，但段落裡沒有辨識出任何條目——段落可能是空的、被截斷，或不是作者—年份格式")
        }

        let (texts, absorbed) = split(kept)
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
        return Result(count: entries.count, entries: entries, warnings: warnings)
    }

    // MARK: - 步驟

    /// pdftotext 輸出的正規化：換頁符當換行、NFKC（連字 ﬁ → fi、不換行空白 → 空白）、
    /// 行尾軟連字號視為斷字接合、其餘格式字元與控制字元移除。
    static func normalize(_ s: String) -> String {
        var t = s.replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .replacingOccurrences(of: "\u{0C}", with: "\n")
            .replacingOccurrences(of: "\t", with: " ")
            .replacingOccurrences(of: "\u{AD}\n", with: "")
        t = t.precomposedStringWithCompatibilityMapping
        var out = String.UnicodeScalarView()
        for u in t.unicodeScalars {
            if u == "\n" { out.append(u); continue }
            switch u.properties.generalCategory {
            case .format, .control: continue
            default: out.append(u)
            }
        }
        return String(out)
    }

    /// 頁碼（只有數字的行）與逐字重複的行（頁首、頁尾、版權聲明）。重複次數在**全文**計
    /// ——參考文獻段只跨兩頁時，頁首在段內只出現一次（#617 校準）。條目開頭的行不算：
    /// 兩筆條目的開頭行不會逐字相同，除非真的是重複條目，那要保留給人看。
    static func dropNoise(_ lines: [String], documentLines: [String]) -> (kept: [String], dropped: [String]) {
        var counts: [String: Int] = [:]
        for l in documentLines where !l.isEmpty { counts[l, default: 0] += 1 }
        var kept: [String] = []
        var dropped: [String] = []
        for l in lines {
            if matches(l, "^\\d{1,4}$") || (counts[l, default: 0] >= 2 && !isEntryStart(l)) {
                dropped.append(l)
            } else {
                kept.append(l)
            }
        }
        return (kept, dropped)
    }

    /// 標題之後、到結束標題之前的行
    static func section(after heading: Int, in lines: [String]) -> [String] {
        var out: [String] = []
        for line in lines[(heading + 1)...] {
            if matches(line, endPattern, caseInsensitive: true) { break }
            out.append(line)
        }
        return out
    }

    static func isEntryStart(_ line: String) -> Bool {
        matches(line, personStartPattern) || matches(line, groupStartPattern)
    }

    /// 逐行併成條目。新條目只在「目前這筆已經有年份括號」時才開始——作者清單換行時，
    /// 下一行（`Garcia, T. (2012). …`）看起來也像一筆的開頭。
    ///
    /// `absorbed` 回報「吸收了一行條目開頭、而上一行不是作者清單的延續（不以 `,`／`&`／`and`
    /// 結尾）」的條目序號（#617 verify F1）：那是前一筆年份沒認出來、兩筆被併成一筆的訊號。
    /// 原本唯一的併筆偵測是「沒有年份」，但併入後的條目帶著下一筆的年份，那條永遠不會觸發。
    static func split(_ lines: [String]) -> (entries: [String], absorbed: [Int]) {
        var entries: [String] = []
        var absorbed: [Int] = []
        var current = ""
        for line in lines {
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
        return (entries, absorbed)
    }

    /// 作者清單換到下一行的樣子：以逗號、`&` 或 `and` 結尾
    static func continuesAuthorList(_ s: String) -> Bool {
        let t = s.trimmingCharacters(in: .whitespaces)
        return t.hasSuffix(",") || t.hasSuffix("&") || t.lowercased().hasSuffix(" and")
    }

    /// 續行接合：行尾是連字號、破折號或斜線（URL）時不加空白，其餘加一個空白。
    /// 連字號保留——分不出是斷字還是複合字（`Within-person`）；比對端正規化時會去掉它。
    static func join(_ a: String, _ b: String) -> String {
        if let last = a.last, "-–—/".contains(last) { return a + b }
        // APA 在標點前斷行的 DOI／URL（`…/0022-3514` ＋ `.40.2.226`）接回，不留空白（#617 verify）
        if let first = b.first, "._-/".contains(first),
           let token = a.split(separator: " ").last, token.contains("10.") || token.contains("http") {
            return a + b
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
                if !isInitial && !isDecimal { break }
            }
            out.append(ch)
            if ch == "?" || ch == "!" { break }
            previousWord = ch.isLetter ? previousWord + String(ch) : ""
        }
        var t = out.trimmingCharacters(in: .whitespaces)
        t = replacing(t, "\\s*\\[[^\\]]*\\]$", with: "")
        return t.isEmpty ? nil : t
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

    static func regex(_ pattern: String, caseInsensitive: Bool) -> NSRegularExpression {
        // 樣式全是本檔的常量；編譯失敗是程式錯誤，不是輸入錯誤
        try! NSRegularExpression(pattern: pattern,
                                 options: caseInsensitive ? [.caseInsensitive] : [])
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

    static func replacing(_ s: String, _ pattern: String, with template: String) -> String {
        regex(pattern, caseInsensitive: false).stringByReplacingMatches(
            in: s, range: NSRange(location: 0, length: (s as NSString).length),
            withTemplate: template)
    }
}
