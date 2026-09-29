import ArgumentParser
import Foundation
import AkashicCore
import AkashicSkillTools

/// 用標題＋期刊＋年份比對 Crossref 記錄取得 DOI，並做反向驗證（#629 由 `akashic-bootstrap/scripts/crossref_match.py` 移植）。
///
/// **本命令不連網。** 舊腳本自己以 `urllib` 直連 Crossref；現在取得是 skill 的事（經 safari-browser，
/// `akashic-bootstrap/references/web-access.md`），本命令只做比對與計分。它是一個**重播式**的狀態機：給它作品清單與一個放回應的
/// 目錄（`--responses`），它算出每一筆作品下一步需要哪個 URL 的回應——都齊了就寫結果檔；還缺就把缺的請求印成 JSON 並以結束碼 3
/// 結束，skill 取回、存成 `<responses>/<id>.json`（404 存成 `<responses>/<id>.404`）、重跑。細節見 `CrossrefMatch`。
///
/// exit code：0 全部判定完成、結果檔已寫；3 還有請求要取（stdout 是 JSON：`{"pending": [{"id", "url"}…], …}`）；1 輸入或回應檔壞了。
struct CrossrefMatchCmd: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "crossref-match",
        abstract: "標題＋期刊＋年份比對 Crossref 取得 DOI、反向驗證（重播式：缺的請求由 skill 經 safari-browser 取回；不連網）",
        discussion: """
        輸入 works.json：[{"citekey", "title", "journal", "year"}, …]（journal 與 year 可缺，但缺了會削弱判定）。輸出每筆的 status \
        （confident／probable／needs_review／no_result）、選定的 DOI 與書目欄位、各訊號的分數。needs_review 的請人工核對；\
        一筆錯的 DOI 比一個缺的 DOI 糟得多。
        """)

    @Option(name: .long, help: "輸入 JSON：[{citekey, title, journal, year}, …]")
    var works: String

    @Option(name: .long, help: "放回應的目錄（skill 取回的 API 回應：<id>.json 是 200 的本文，<id>.404 是查無此筆）")
    var responses: String

    @Option(name: [.short, .long], help: "結果檔（全部完成時寫入）")
    var out: String = "crossref_result.json"

    @Option(name: .long, help: "Crossref 禮貌流量用的聯絡信箱（放進請求網址的 mailto 參數）")
    var mailto: String?

    @Flag(name: .customLong("no-verify"), help: "跳過反向驗證（不建議）")
    var noVerify = false

    func validate() throws {
        if let mailto, !Self.isPlausibleEmail(mailto) { throw ValidationError("--mailto 不是信箱的形狀") }
    }

    static func isPlausibleEmail(_ s: String) -> Bool {
        s.range(of: "^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\\.[A-Za-z]{2,}$", options: .regularExpression) != nil
    }

    func run() throws {
        let outcome: CrossrefMatch.Outcome
        let parsed: [CrossrefMatch.Work]
        do {
            guard let data = FileManager.default.contents(atPath: works) else {
                throw SkillToolError.failure("讀不到 --works 指定的檔：\(displaySafeInvisible(works, max: 300))")
            }
            parsed = try CrossrefMatch.parseWorks(data)
            outcome = try CrossrefMatch.run(works: parsed, source: DirectoryResponseSource(directory: responses),
                                            verify: !noVerify, mailto: mailto)
        } catch {
            throw RuntimeFailure.state(displaySafeErrorText(error))
        }
        switch outcome {
        case .pending(let requests, let resolved):
            let payload = PyJSON.object([
                ("pending", .array(requests.map { .object([("id", .string($0.id)), ("url", .string($0.url))]) })),
                ("resolved", .int(resolved)),
                ("total", .int(parsed.count)),
            ])
            print(payload.dumps())   // display-safe-exempt: payload：id 是 URL 的雜湊、url 是本命令自己組的（標題與信箱已百分比編碼，DOI 過形狀檢查），計數是整數
            FileHandle.standardError.write(Data("已判定 \(resolved)/\(parsed.count) 筆；還有 \(requests.count) 個請求要取（存成 \(displaySafeInvisible(responses, max: 200))/<id>.json，404 存成 <id>.404），取回後重跑\n".utf8))
            throw ExitCode(3)
        case .complete(let records):
            let text = PyJSON.array(records.map(\.json)).dumps(indent: 1)
            do {
                try AbstractProposals.writeOut(path: out, text: text, announce: { _ in })
            } catch {
                throw RuntimeFailure.state(displaySafeErrorText(error))
            }
            var log = Data()
            for (i, r) in records.enumerated() {
                let status = r.status.padding(toLength: 13, withPad: " ", startingAt: 0)
                let key = "\(r.citekey.plainText)".prefix(30).padding(toLength: 30, withPad: " ", startingAt: 0)
                log.append(Data("\(String(format: "%4d", i + 1))/\(records.count)  \(status) \(displaySafeInvisible(String(key), max: 60)) \(displaySafeInvisible(r.best?.doi ?? "-", max: 200))\n".utf8))
            }
            var tally: [String: Int] = [:]
            for r in records { tally[r.status, default: 0] += 1 }
            log.append(Data("\n=== 判定 ===\n".utf8))
            for k in ["confident", "probable", "needs_review", "no_result"] where tally[k] != nil { log.append(Data("  \(k): \(tally[k]!)\n".utf8)) }
            log.append(Data("\n寫入 \(displaySafeInvisible(out, max: 300))\nneeds_review 的請人工核對；一筆錯的 DOI 比一個缺的 DOI 糟得多。\n".utf8))
            FileHandle.standardError.write(log)
        }
    }
}

private extension PyJSON {
    /// 進度行裡的 citekey：字串原樣、null 是 `None`（舊腳本的 `str(w.get("citekey"))`）。
    var plainText: String {
        switch self {
        case .string(let s): return s
        case .null: return "None"
        default: return dumps()
        }
    }
}
