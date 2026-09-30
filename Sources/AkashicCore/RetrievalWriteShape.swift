import Foundation

/// 擷取型（retrieval）reference 的**寫入面形狀**——一份，兩個寫入面共用：
///
/// - person／venue 的通用 `references`（`AkashicService.parseReferenceObjects`，#674）；
/// - `enrich` 的來源欄位（`AddOnlyEnrichment` 的提案驗證，#695）——`sourceURL`／`sourceRetrieved`／`sourceStatus` 寫的是同一種記錄。
///
/// 使用者 2026-09-30 裁決（#695）：「要，共用同一個解析函式」——同一種記錄只剩一份寫入契約。#674 時這些檢查住在
/// `ReferenceWriteParsing.swift`（AkashicMCPKit），而 `AddOnlyEnrichment` 住在 Core、看不到它；搬到 Core，兩邊呼叫同一個函式，
/// 不留第二份（`no-compat-fallback`「同一件事只能有一份描述」）。
///
/// 驗四件事，先後固定：
/// 1. `status` 給了就要在 100–599（RFC 9110 §15：三位數、1xx–5xx）；
/// 2. 呼叫端判定這是擷取型（`statusRequired`）而 `status` 沒給 → 拒絕，**不預設 200**（預設會把離線掃描檔記成 HTTP 200——
///    store 就斷言了來源沒說過的事實；#542 R2 對 `enrich` 裁掉過同一個預設）；
/// 3. `url` 給了就只收 http／https、主機非空、不含帳密（帳密與帶 token 的 userinfo 會落進 git 追蹤的 YAML）；
/// 4. `retrieved` 給了就要是 ISO 8601（日期，或日期加時間與可選的時區）。
///
/// 「缺 status」排在 url／retrieved 之前：一筆什麼都沒給對的 retrieval，先被告知的應該是 #674 點名的那一項（#674 R1 verify 第 28 列）。
///
/// **「給了」與「status 必填」由呼叫端決定**——兩個面的輸入形狀不同：`references` 的物件有判斷型的鍵（statement／rests_on）要排除；
/// `enrich` 的 `sourceDigest` 單獨給是回顯、不是在寫 reference（#517；摘要提案就是這個形），不觸發 status 必填。那是面的差異，不是契約的分岔。
///
/// **只在寫入面**：載入既有記錄走 `ProvenanceReference.init`，不驗這些——收緊寫入不能讓既有記錄讀不進來。
/// 2026-09-30 唯讀量測：live store 7,649 筆記錄的擷取型 reference 共 33 筆，全在 work 上（`enrich` 寫的 `fields.<鍵>`），
/// 全是 `https`、裸日期、status 200——這四項全數通過。
public enum RetrievalWriteShape {

    /// HTTP 狀態碼的值域（RFC 9110 §15：三位數、1xx–5xx）。
    public static let statusRange = 100...599

    /// 呼叫端怎麼稱呼這筆記錄與它的三個鍵——訊息指名呼叫端送來的那個鍵（`references[0].url` 對 `sourceURL`），不是 store 的欄位名。
    public struct Names {
        /// 這筆擷取型記錄（`references[0]`、`來源欄位`）。
        public let record: String
        public let url: String
        public let retrieved: String
        public let status: String
        /// 離線來源（沒有 HTTP 狀態、url 不是 http／https）的出路——兩個面不同：references 改用判斷型，enrich 只給 digest。
        public let offlineRemedy: String

        public init(record: String, url: String, retrieved: String, status: String, offlineRemedy: String) {
            self.record = record; self.url = url; self.retrieved = retrieved; self.status = status
            self.offlineRemedy = offlineRemedy
        }
    }

    /// 第一個不合的理由；nil＝合法。只驗給了的欄位（nil 不驗）。
    ///
    /// `echo`：回顯呼叫端送來的值（`retrieved` 的原字串、url 的 scheme）之前怎麼處理。訊息直接進自帶消毒的錯誤型別（`ServiceError`）時
    /// 在這裡逃脫；由消費端統一逃脫時（`AddOnlyEnrichment.InputError` 在 service／CLI／MCP 的擲出站點逃一次）原樣——否則逃兩次
    /// （`displaySafe` 不冪等）。帳密不回顯：url 只回顯 `://` 之前那一段，且只在它真的是 scheme 形時。
    public static func firstIssue(url: String?, retrieved: String?, status: Int?, statusRequired: Bool,
                                  names: Names, echo: (String) -> String) -> String? {
        if let status, !statusRange.contains(status) {
            return "\(names.status)「\(status)」不是 HTTP 狀態碼（\(statusRange.lowerBound)–\(statusRange.upperBound)）"
        }
        if status == nil, statusRequired {
            return "\(names.record) 是擷取型卻沒有 status——HTTP 狀態碼必填、不預設 200（預設會把離線掃描檔記成 HTTP 200，"
                + "store 就斷言了來源沒說過的事實）；\(names.offlineRemedy)"
        }
        if let url, let why = urlIssue(url, names: names, echo: echo) { return why }
        if let retrieved, !isValidRetrievedInstant(retrieved) {
            return "\(names.retrieved)「\(echo(retrieved))」不是 ISO 8601——日期 YYYY-MM-DD，"
                + "或再接 THH:MM[:SS[.fff]] 與 Z／±HH:MM（帶時區才是確切的一刻；store 的既有記錄多是裸日期，所以裸日期照收）"
        }
        return nil
    }

    // MARK: - url

    /// `url` 只收 http／https 網址，主機非空，不含帳密（userinfo）。**不回顯原值**：帳密若在 url 裡，把它印進錯誤訊息就是把它送進 log
    /// 與 MCP 的對話紀錄；只說是哪一種錯，scheme 只在 `://` 之前那一段符合 `^[A-Za-z][A-Za-z0-9+.-]*$` 時回顯（至多 20 字）。
    /// 誠實邊界：query 裡的 token（`?token=…`）與路徑裡的機密看不出來，這裡不猜。
    static func urlIssue(_ url: String, names: Names, echo: (String) -> String) -> String? {
        let lower = url.lowercased()
        let afterScheme: Substring
        if lower.hasPrefix("https://") {
            afterScheme = url.dropFirst(8)
        } else if lower.hasPrefix("http://") {
            afterScheme = url.dropFirst(7)
        } else {
            // `://` 之前那一段要真的是 scheme 形（RFC 3986：字母開頭，其後字母、數字、`+`、`-`、`.`）才回顯——否則它可能就是帳密
            // （`alice:hunter2@example.org/?next=https://x`，#674 R1 verify 第 26 列）
            var shape = ""
            if let r = url.range(of: "://"), looksLikeURLScheme(url[..<r.lowerBound]) {
                shape = "（scheme 是「\(echo(String(url[..<r.lowerBound].prefix(20))))」）"
            }
            return "\(names.url) 只收 http／https 網址\(shape)——\(names.offlineRemedy)"
        }
        let authority = afterScheme.prefix(while: { $0 != "/" && $0 != "?" && $0 != "#" })
        guard !authority.contains("@") else {
            return "\(names.url) 含帳密（userinfo，`user:password@` 或 `token@`）——不得把帳密或 token 寫進 store（YAML 進 git 追蹤）；拿掉它再送（不回顯原值）"
        }
        let host = authority.hasPrefix("[") ? authority.dropFirst().prefix(while: { $0 != "]" }) : authority.prefix(while: { $0 != ":" })
        guard !host.isEmpty else {
            return "\(names.url) 缺主機（https:// 之後要有網域或位址）"
        }
        return nil
    }

    /// RFC 3986 的 scheme 形：ASCII 字母開頭，其後 ASCII 字母、數字、`+`、`-`、`.`。
    static func looksLikeURLScheme(_ s: Substring) -> Bool {
        func letter(_ u: Unicode.Scalar) -> Bool { ("a"..."z").contains(u) || ("A"..."Z").contains(u) }
        guard let first = s.unicodeScalars.first, letter(first) else { return false }
        return s.unicodeScalars.allSatisfy { letter($0) || ("0"..."9").contains($0) || $0 == "+" || $0 == "-" || $0 == "." }
    }

    // MARK: - retrieved

    /// `retrieved` 是 ISO 8601：`YYYY-MM-DD`（月 01–12、日 01–31，不驗日曆，同 `ISO8601Prefix`），可再接
    /// `THH:MM`（可選 `:SS`、可選 `.` 加至少一位小數；時 00–23、分 00–59、秒 00–60）與可選的 `Z` 或 `±HH:MM`。
    ///
    /// **裸日期照收**：store 既有的擷取型 reference 全是 `YYYY-MM-DD`（store-format §2.5.1 的範例也是）。#262 的
    /// 「帶 UTC offset」契約寫在 `sources/index.jsonl` 的 `retrieved`，尚未在任何一個寫入面強制——這裡不替它先行。
    public static func isValidRetrievedInstant(_ s: String) -> Bool {
        let b = Array(s.utf8)
        guard b.count >= 10, ISO8601Prefix.isValid(String(decoding: b[0..<10], as: UTF8.self)),
              b[0..<10].filter({ $0 == UInt8(ascii: "-") }).count == 2 else { return false }
        if b.count == 10 { return true }
        guard b[10] == UInt8(ascii: "T") else { return false }
        var i = 11
        func twoDigits(max: Int) -> Bool {
            guard i + 2 <= b.count, b[i...(i + 1)].allSatisfy({ (UInt8(ascii: "0")...UInt8(ascii: "9")).contains($0) }),
                  let n = Int(String(decoding: b[i...(i + 1)], as: UTF8.self)), n <= max else { return false }
            i += 2
            return true
        }
        func colon() -> Bool {
            guard i < b.count, b[i] == UInt8(ascii: ":") else { return false }
            i += 1
            return true
        }
        guard twoDigits(max: 23), colon(), twoDigits(max: 59) else { return false }
        if i < b.count, b[i] == UInt8(ascii: ":") {
            i += 1
            guard twoDigits(max: 60) else { return false }
            if i < b.count, b[i] == UInt8(ascii: ".") {
                i += 1
                let start = i
                while i < b.count, (UInt8(ascii: "0")...UInt8(ascii: "9")).contains(b[i]) { i += 1 }
                guard i > start else { return false }
            }
        }
        if i == b.count { return true }
        if b[i] == UInt8(ascii: "Z") { return i + 1 == b.count }
        guard b[i] == UInt8(ascii: "+") || b[i] == UInt8(ascii: "-") else { return false }
        i += 1
        guard twoDigits(max: 23), colon(), twoDigits(max: 59) else { return false }
        return i == b.count
    }
}
