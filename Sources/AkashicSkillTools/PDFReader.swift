import Foundation
import AkashicCore

/// 從 PDF 讀出驗證要用的三樣東西（#629）：首兩頁文字、頁數、檔案自己的 XMP 中繼資料 DOI。
///
/// 全部走 poppler 的 `pdfinfo`／`pdftotext`（舊腳本同樣）——不在 Swift 裡解析 PDF：文字抽取的行為（行序、分頁符 `\f`、
/// 連字處理）是校準門檻時量出來的，換抽取器等於換掉輸入。
public enum PDFReader {
    public struct Content {
        public var firstPages: String
        public var pageCount: Int
    }

    /// 檔頭必須是 `%PDF-`；`pdfinfo` 報頁數；`pdftotext -l 2` 取前兩頁（頁間以 `\f` 分隔）。
    public static func read(path: String) throws -> Content {
        let head: Data
        do {
            let fh = try FileHandle(forReadingFrom: URL(fileURLWithPath: path))
            defer { try? fh.close() }
            head = try fh.read(upToCount: 5) ?? Data()
        } catch {
            throw SkillToolError.failure("讀不到 \(displaySafeInvisible(path, max: 300))：\(displaySafeErrorText(error))")
        }
        guard head == Data("%PDF-".utf8) else { throw SkillToolError.failure("not a PDF (no %PDF- header)") }
        let info = try ToolRunner.run(["pdfinfo", path], timeout: ToolRunner.popplerTimeout)
        guard info.status == 0 else { throw SkillToolError.failure("pdfinfo failed (exit \(info.status))") }   // display-safe-exempt: info：status 是 Int 結束碼
        guard let count = pageCount(fromPdfinfo: String(decoding: info.stdout, as: UTF8.self)) else {
            throw SkillToolError.failure("pdfinfo reported no page count")
        }
        let text = try ToolRunner.run(["pdftotext", "-l", "2", path, "-"], timeout: ToolRunner.popplerTimeout)
        guard text.status == 0 else { throw SkillToolError.failure("pdftotext failed (exit \(text.status))") }   // display-safe-exempt: text：status 是 Int 結束碼
        guard let firstPages = String(data: text.stdout, encoding: .utf8) else {
            throw SkillToolError.failure("pdftotext output is not valid UTF-8")
        }
        return Content(firstPages: firstPages, pageCount: count)
    }

    /// 只讀頁數（`pdfinfo`）：`fulltext compare` 對照提議的頁序用，不抽文字（#742 verify 第二輪）。
    public static func pageCount(path: String) throws -> Int {
        let info = try ToolRunner.run(["pdfinfo", path], timeout: ToolRunner.popplerTimeout)
        guard info.status == 0 else { throw SkillToolError.failure("pdfinfo failed (exit \(info.status))") }   // display-safe-exempt: info：status 是 Int 結束碼
        guard let count = pageCount(fromPdfinfo: String(decoding: info.stdout, as: UTF8.self)) else {
            throw SkillToolError.failure("pdfinfo reported no page count")
        }
        return count
    }

    /// **全部頁**的文字（#742 `fulltext text`）：`pdfinfo` 報頁數、`pdftotext` 一次抽全檔，以分頁符 `\f` 切成逐頁。
    /// 與 `read` 分開，`read` 的「只讀前兩頁」是 `fulltext verify`／`take` 校準過的輸入，不動它。
    /// 切出來的頁數與 `pdfinfo` 不符時拒絕——頁序對不上，替換記錄的頁碼就是假的。
    public static func readAllPages(path: String) throws -> (pageCount: Int, pages: [String]) {
        let head: Data
        do {
            let fh = try FileHandle(forReadingFrom: URL(fileURLWithPath: path))
            defer { try? fh.close() }
            head = try fh.read(upToCount: 5) ?? Data()
        } catch {
            throw SkillToolError.failure("讀不到 \(displaySafeInvisible(path, max: 300))：\(displaySafeErrorText(error))")
        }
        guard head == Data("%PDF-".utf8) else { throw SkillToolError.failure("not a PDF (no %PDF- header)") }
        let info = try ToolRunner.run(["pdfinfo", path], timeout: ToolRunner.popplerTimeout)
        guard info.status == 0 else { throw SkillToolError.failure("pdfinfo failed (exit \(info.status))") }   // display-safe-exempt: info：status 是 Int 結束碼
        guard let count = pageCount(fromPdfinfo: String(decoding: info.stdout, as: UTF8.self)) else {
            throw SkillToolError.failure("pdfinfo reported no page count")
        }
        let text = try ToolRunner.run(["pdftotext", path, "-"], timeout: ToolRunner.popplerTimeout)
        guard text.status == 0 else { throw SkillToolError.failure("pdftotext failed (exit \(text.status))") }   // display-safe-exempt: text：status 是 Int 結束碼
        guard let all = String(data: text.stdout, encoding: .utf8) else {
            throw SkillToolError.failure("pdftotext output is not valid UTF-8")
        }
        // pdftotext 在每一頁之後都寫一個 \f，所以 N 頁切出 N+1 段、最後一段是空的
        var pages = all.split(separator: "\u{0C}", omittingEmptySubsequences: false).map(String.init)
        if pages.last?.isEmpty == true { pages.removeLast() }
        guard pages.count == count else {
            throw SkillToolError.failure("pdftotext 切出 \(pages.count) 頁、pdfinfo 報 \(count) 頁——頁序對不上，不輸出")   // display-safe-exempt: pages.count 與 count 是 Int
        }
        return (count, pages)
    }

    /// `^Pages:\s+(\d+)`（多行）。
    static func pageCount(fromPdfinfo text: String) -> Int? {
        for line in PyText.splitLines(Scalars(text.unicodeScalars)) {
            let key = Scalars("Pages:".unicodeScalars)
            guard PyText.hasPrefix(line, key) else { continue }
            var i = key.count
            let ws = i
            while i < line.count, PyText.isSpace(line[i]) { i += 1 }
            guard i > ws else { continue }
            var v = 0, any = false
            while i < line.count, PyText.isDecimal(line[i]) {
                v = min(v * 10 + Int(line[i].properties.numericValue ?? 0), 1_000_000_000)
                any = true
                i += 1
            }
            if any { return v }
        }
        return nil
    }

    /// PDF 自己的 XMP 中繼資料裡的 DOI——檔案的身分，不是引用。`pdfinfo -meta` 沒有輸出或沒有 DOI 時回 nil。
    public static func metadataDOI(path: String) throws -> String? {
        let r = try ToolRunner.run(["pdfinfo", "-meta", path], timeout: ToolRunner.popplerTimeout)
        return FulltextVerify.doiFromXMP(String(decoding: r.stdout, as: UTF8.self))
    }
}
