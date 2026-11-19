import Foundation
import AkashicCore

/// `akashic fulltext attempt`：在每站每日的嘗試帳本上記一次（#781、#780，使用者 2026-11-10 裁決：Claude 在出版商頁面上按的每一下都算進
/// 每站每天 10 次，與 `fetch` 共用同一本帳）。
///
/// `fetch` 只在自己準備導航到 PDF 連結時記帳；skill 以 safari-browser 按頁面上這篇自己的連結時，請求是 skill 送的，`fetch` 看不到。
/// 這個命令給那一下一個記帳的入口：**先記到，才按**。它不碰瀏覽器、不連網、不讀不寫 store，只動 store 之外的那本帳。
///
/// 結束碼（對 skill 的契約，`FulltextFetch.contractVersion` 11 起）：
/// - 0：記到了，stdout 一行 `attempt: <站> <n>/10 <日>`（與 `fetch` 記到時印的同一個形狀）；
/// - 9：這個站今天已經到上限，stdout 一行 `cap: <站> <n>/10 <日>`，帳本不變——意思與 `fetch` 的 9 相同：停這個站；
/// - 1：帳本讀不懂或寫不了（數不出今天的次數就不能保證沒超過上限），帳本不變；
/// - 64：`--site` 或 `--landing` 的形狀不對（由命令列層在碰帳本之前擋下，見 `siteProblem`、`landingProblem`）。
public struct FulltextAttempt {
    let out: (String) -> Void
    let err: (String) -> Void
    let now: () -> Date

    public init(out: @escaping (String) -> Void, err: @escaping (String) -> Void, now: @escaping () -> Date = Date.init) {
        self.out = out
        self.err = err
        self.now = now
    }

    /// `--site` 的形狀：乾淨的 DNS 主機名稱，就是 `fetch` 記帳時用的那個鍵（文章頁的主機，小寫）。不收 scheme、路徑、帳密、埠號、
    /// 百分比編碼與空白——那些寫法會在帳本裡開出另一個「站」，同一個出版商的次數就被拆開了。回 nil 表示可以用。
    public static func siteProblem(_ site: String) -> String? {
        guard BotSignals.isPlainDNSName(site) else {
            return "not a plain DNS host name (no scheme, path, user@, port, percent-encoding or whitespace)"
        }
        // 與 `--landing` 的主機同一道檢查：最後一段是字母、不是私有網路的名稱
        return FulltextFetch.landingShapeProblem("https://" + site)
    }

    /// `--landing` 的形狀：絕對的 https 網址（與 `fetch --landing` 同一道檢查）。它不參與計數，只是記錄。
    public static func landingProblem(_ landing: String) -> String? { FulltextFetch.landingShapeProblem(landing) }

    /// 記一次。回結束碼。
    public func run(site: String, landing: String, ledger path: String) -> Int32 {
        let host = site.lowercased()
        let at = now()
        let day = FulltextAttemptLedger.taipeiDay(at)
        let reservation: FulltextAttemptLedger.Reservation
        do {
            reservation = try FulltextAttemptLedger(path: path).reserve(site: host, landing: FulltextFetch.plainURL(landing), at: at)
        } catch {
            err("✗ \(displaySafeErrorText(error))")
            err("  nothing was recorded — do not click: today's count for this site is unknown.")
            return 1
        }
        switch reservation {
        case .capReached(let used):
            err("⏹ DAILY CAP: \(displaySafeInvisible(host, max: 300)) already has \(used) attempts on \(day) (Asia/Taipei) — stop this site for today; nothing was recorded, do not click.")
            out("cap: \(displaySafeInvisible(host, max: 300)) \(used)/\(FulltextAttemptLedger.dailyCap) \(day)")
            return FulltextFetch.Code.dailyCapReached
        case .granted(let used):
            out("attempt: \(displaySafeInvisible(host, max: 300)) \(used)/\(FulltextAttemptLedger.dailyCap) \(day)")
            return 0
        }
    }
}
