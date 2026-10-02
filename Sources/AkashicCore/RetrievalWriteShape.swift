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
/// 驗五件事，先後固定：
/// 1. `status` 給了就要在 100–599（RFC 9110 §15：三位數、1xx–5xx）；
/// 2. 呼叫端判定這是擷取型（`statusRequired`）而 `status` 沒給 → 拒絕，**不預設 200**（預設會把離線掃描檔記成 HTTP 200——
///    store 就斷言了來源沒說過的事實；#542 R2 對 `enrich` 裁掉過同一個預設）；
/// 3. `url` 給了就只收 http／https、主機非空、不含帳密（帳密與帶 token 的 userinfo 會落進 git 追蹤的 YAML）、主機不含反斜線，
///    整串不含危險 scalar 與空白（#695 R1 verify）；主機部分不含相容形的定界符、port 只含 ASCII 數字（#695 R2 verify）；
/// 4. `retrieved` 給了就要是 ISO 8601（日期，或日期加時間與可選的時區）——文法逐位元組比到結尾，控制字元、空白本來就過不了；
/// 5. `mediaType` 給了就不是空的、不含危險 scalar、前後沒有空白（#695 R1／R2 verify；內部的空白照收——`text/html; charset=utf-8`）。
///
/// **定界符一律在 scalar 上找**（#695 R1 verify 第 6／10 列，兩席以真 binary 寫進 store）：Swift 的 `Character` 是 grapheme cluster，
/// `@` 後面緊跟組合符號（U+0301）、ZWJ（U+200D）或 VS16（U+FE0F）時兩者合成一個 `Character`，`contains("@")` 為 false——
/// `https://user:secret@\u{0301}example.org/` 的帳密整段進了 git 追蹤的 YAML。`/`、`?`、`#`、`@`、`\`、`:`、`[`、`]` 都是 ASCII，
/// 在 `unicodeScalars` 上找就不會被後面的 Extend 字元吃掉。scheme 前綴（`https://`）同樣在 scalar 上比（#695 R2 verify 第 7／11 列：
/// `https://` 後面緊跟組合符號時，第二個 `/` 與它合成一個 `Character`，`hasPrefix` 為 false，訊息誤說「只收 http／https」）。
///
/// **相容形的定界符**（#695 R2 verify 第 15 列）：全形 `＠`／`：`／`／`、小寫形 `﹫`、`℀`（a/c）這類 scalar 的相容分解（NFKD）含
/// `@ : / ? # \`。它們不是定界符——`https://user:secret＠example.org/` 在 scalar 上沒有 `@`，帳密檢查放行——而 WHATWG 的主機處理
/// （UTS 46）會把它們正規化成 ASCII 再拒絕，Python 的 `urlsplit` 對 `＠` 直接報錯（CVE-2019-9636 那一類）。裁決：主機部分（第一個 ASCII
/// `/`、`?`、`#` 之前）**任何相容分解含這六個 ASCII 定界符的非 ASCII scalar 都拒絕**，其餘非 ASCII 照收——IDN 主機（`例え.jp`、全形句點
/// `．`）不受影響。沒有選「主機部分不收任何非 ASCII」：那會拒掉合法的 IDN 主機，而 live store 的 33 筆沒有一筆用得到它（都是 ASCII https），
/// 不需要為一個零實例的形狀多拒一整類合法網址。port 只收 ASCII 數字（RFC 3986 `port = *DIGIT`）：`https://example.org:hunter2/` 的
/// 「port」可能是少了 `@` 的密碼。
///
/// **危險 scalar 與輸出閘同一份性質**（`UnsafeToEmitScalar.contains`：Cc／Cf／Zl／Zp、非 U+0020 的 Zs、Default_Ignorable、私用區、
/// 渲染成空白的碼位）——NUL、換行、方向控制（U+202E）、零寬字元都在裡面。它們進 store 之後會在報告與合併描述裡回顯，輸出端的逃脫是
/// 縱深防禦，不是寫入的理由。
///
/// 「缺 status」排在 url／retrieved 之前：一筆什麼都沒給對的 retrieval，先被告知的應該是 #674 點名的那一項（#674 R1 verify 第 28 列）。
///
/// **「給了」與「status 必填」由呼叫端決定**——兩個面的輸入形狀不同：`references` 的物件有判斷型的鍵（statement／rests_on）要排除；
/// `enrich` 的 `sourceDigest` 單獨給是回顯、不是在寫 reference（#517；摘要提案就是這個形），不觸發 status 必填。那是面的差異，不是契約的分岔。
///
/// **回顯**：`retrieved` 的原值排在理由**之後**、以逃脫後的長度截（`boundedForEcho`）——#695 R2 verify 第 10／18 列：先前原值排在理由之前、
/// 以輸入 scalar 數截，120 個 ZWSP 逃脫成 960 個字元，錯誤出口的上限（CLI 每行 400、MCP 512）把「不是 ISO 8601」與「整批拒絕，零寫入」都截掉了。
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
        public let mediaType: String
        /// 離線來源（沒有 HTTP 狀態、url 不是 http／https）的出路——兩個面不同：references 改用判斷型，enrich 只給 digest。
        public let offlineRemedy: String

        public init(record: String, url: String, retrieved: String, status: String, mediaType: String, offlineRemedy: String) {
            self.record = record; self.url = url; self.retrieved = retrieved; self.status = status; self.mediaType = mediaType
            self.offlineRemedy = offlineRemedy
        }
    }

    /// 第一個不合的理由；nil＝合法。只驗給了的欄位（nil 不驗）。
    ///
    /// `echo`：回顯呼叫端送來的值（`retrieved` 的原字串、url 的 scheme）之前怎麼處理。訊息直接進自帶消毒的錯誤型別（`ServiceError`）時
    /// 在這裡逃脫；由消費端統一逃脫時（`AddOnlyEnrichment.InputError` 在 service／CLI／MCP 的擲出站點逃一次）原樣——否則逃兩次
    /// （`displaySafe` 不冪等）。帳密不回顯：url 只回顯 `://` 之前那一段，且只在它真的是 scheme 形時。**截在這裡、不在 `echo`**：
    /// 兩個面送進 `echo` 的都已經是 `boundedForEcho` 截過的值（#695 R2 verify 第 10／18 列）。
    public static func firstIssue(url: String?, retrieved: String?, status: Int?, mediaType: String?, statusRequired: Bool,
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
            // 理由在前、原值在後且先截（見型別 doc 的〈回顯〉）：錯誤出口截的是尾巴，截掉的只會是原值
            return "\(names.retrieved) 不是 ISO 8601——日期 YYYY-MM-DD，"
                + "或再接 THH:MM[:SS[.fff]] 與 Z／±HH:MM（偏移要帶冒號：+08:00，不收 +0800；帶時區才是確切的一刻；"
                + "store 的既有記錄多是裸日期，所以裸日期照收）；收到的值：「\(echo(boundedForEcho(retrieved)))」"
        }
        if let mediaType, let why = mediaTypeIssue(mediaType, names: names) { return why }
        return nil
    }

    // MARK: - 回顯的上限

    /// 回顯原值的上限，以**逃脫後**的字元數計（#695 R2 verify 第 10／18 列）。48 放得下常見的錯形（`2026-09-30T12:00:00+0800` 是 24 字）；
    /// 一個被逃脫的 scalar 算 10（`\u{E0041}` 的長度），所以最壞是 4 個隱形字元加「…」——理由加前後綴仍在 CLI 每行 400 之內。
    static let echoOutputBudget = 48

    /// 截到 `echoOutputBudget`，截了就接「…」。在交給 `echo` 逃脫**之前**截：計價照輸出端的逃脫（危險 scalar 與反斜線都寫成 `\u{…}`）。
    static func boundedForEcho(_ s: String) -> String {
        var out = String.UnicodeScalarView()
        var used = 0
        for u in s.unicodeScalars {
            let cost = (UnsafeToEmitScalar.contains(u) || u == "\\") ? 10 : 1
            guard used + cost <= echoOutputBudget else { return String(out) + "…" }
            out.append(u)
            used += cost
        }
        return String(out)
    }

    // MARK: - 危險 scalar

    /// 與輸出閘同一份性質（`UnsafeToEmitScalar.contains`）——不另寫一份清單。
    static func hasUnsafeScalar<S: Sequence>(_ scalars: S) -> Bool where S.Element == Unicode.Scalar {
        scalars.contains { UnsafeToEmitScalar.contains($0) }
    }

    /// `mediaType`：不含危險 scalar、前後沒有空白。**不驗 `type/subtype` 文法**——裁決沒有點名它，而 live store 的 media type
    /// 由 `store-source` 的收據帶來；這裡只擋會在輸出端回顯成隱形或多行的字元。不回顯原值。
    ///
    /// **空的或只有空白也拒絕**（#695 R2 verify 第 8 列）：先前 `""` 通過（`first`／`last` 都是 nil），references 面把它存成 `media-type: ''`。
    /// enrich 面的空字串視同沒給、不會走到這裡（`retrievalKind` 也不把它寫進 reference）——兩個面對「空字串」的既有差異，見 changelog。
    static func mediaTypeIssue(_ mediaType: String, names: Names) -> String? {
        let s = mediaType.unicodeScalars
        guard s.contains(where: { !$0.properties.isWhitespace }) else {
            return "\(names.mediaType) 是空的（或只有空白）——沒有 media type 就不要給這個鍵"
        }
        let edgeSpace = (s.first?.properties.isWhitespace ?? false) || (s.last?.properties.isWhitespace ?? false)
        guard !edgeSpace, !hasUnsafeScalar(s) else {
            return "\(names.mediaType) 含控制字元、格式字元（方向控制、零寬字元等）或前後空白——media type 是 type/subtype 形"
                + "（例如 text/html）；拿掉再送（不回顯原值）"
        }
        return nil
    }

    // MARK: - url

    /// `url` 只收 http／https 網址，主機非空，不含帳密（userinfo）、主機不含反斜線與相容形的定界符、port 只含數字、整串不含危險 scalar 與空白。
    /// **不回顯原值**：帳密若在 url 裡，把它印進錯誤訊息就是把它送進 log 與 MCP 的對話紀錄；只說是哪一種錯，scheme 只在 `://` 之前那一段
    /// 符合 `^[A-Za-z][A-Za-z0-9+.-]*$` 時回顯（至多 20 字）。
    ///
    /// 誠實邊界：query 裡的 token（`?token=…`）與路徑裡的機密看不出來，這裡不猜；帳密檢查只管 **retrieval reference 的 url 這一格**——
    /// 同一份 enrich 提案的 `fields.url`、`create-entry` 的欄位照 `lossless-intake` 原樣收下，不經這個函式（#695 R2 verify 第 17 列）。
    static func urlIssue(_ url: String, names: Names, echo: (String) -> String) -> String? {
        let scalars = Array(url.unicodeScalars)
        let afterScheme: ArraySlice<Unicode.Scalar>
        if hasASCIIPrefixIgnoringCase(scalars[...], "https://") {
            afterScheme = scalars.dropFirst(8)
        } else if hasASCIIPrefixIgnoringCase(scalars[...], "http://") {
            afterScheme = scalars.dropFirst(7)
        } else {
            // 前面多了空白或隱形字元的 http(s) 網址：錯的是那些字元，不是 scheme（#695 R2 verify 第 7 列）
            let stripped = scalars.drop(while: { $0.properties.isWhitespace || UnsafeToEmitScalar.contains($0) })
            if stripped.count < scalars.count,
               hasASCIIPrefixIgnoringCase(stripped, "https://") || hasASCIIPrefixIgnoringCase(stripped, "http://") {
                return unsafeScalarIssue(names)
            }
            // `://` 之前那一段要真的是 scheme 形（RFC 3986：字母開頭，其後字母、數字、`+`、`-`、`.`）才回顯——否則它可能就是帳密
            // （`alice:hunter2@example.org/?next=https://x`，#674 R1 verify 第 26 列）
            var shape = ""
            if let r = url.range(of: "://"), looksLikeURLScheme(url[..<r.lowerBound]) {
                shape = "（scheme 是「\(echo(String(url[..<r.lowerBound].prefix(20))))」）"
            }
            return "\(names.url) 只收 http／https 網址\(shape)——\(names.offlineRemedy)"
        }
        // 定界符在 scalar 上找（見型別 doc）。`\` 刻意**不是**定界符：WHATWG 對 http／https 把它當成 `/`、RFC 3986 不認它——
        // 不把它當定界符，任何在第一個 `/`、`?`、`#` 之前的 `@` 都算帳密，是兩種解析的聯集（嚴的那一邊）；主機部分出現它則直接拒絕，
        // 不讓 store 留一個兩種解析器讀出不同主機的網址。
        let authority = afterScheme.prefix(while: { $0 != "/" && $0 != "?" && $0 != "#" })
        guard !authority.contains("@") else {
            return "\(names.url) 含帳密（userinfo，`user:password@` 或 `token@`）——帳密與 token 不得寫進 retrieval reference 的 url"
                + "（store 的 YAML 進 git 追蹤）；拿掉它再送（不回顯原值）"
        }
        guard !authority.contains(where: isCompatibilityDelimiter) else {
            return "\(names.url) 的主機部分含全形或相容形的定界符（＠：／？＃＼ 這類，相容分解後是 @ : / ? # 或反斜線）——可能藏著帳密"
                + "（user：pw＠host），不同的網址解析器也會讀出不同的主機，store 不收；主機用 ASCII 或 punycode（xn--）寫（不回顯原值）"
        }
        guard !authority.contains("\\") else {
            return "\(names.url) 的主機部分含反斜線——網址解析器對它的解讀不同（瀏覽器當成 /），store 不收；改成 / 再送（不回顯原值）"
        }
        // 整串：危險 scalar 與任何空白（RFC 3986 不收空白）。排在帳密之後：兩者都在時先說帳密。
        guard !hasUnsafeScalar(scalars), !scalars.contains(where: { $0.properties.isWhitespace }) else {
            return unsafeScalarIssue(names)
        }
        // 主機與其後的 port：`[IPv6]` 取到 `]` 為止，其餘取到第一個 `:`。
        let host: ArraySlice<Unicode.Scalar>
        let rest: ArraySlice<Unicode.Scalar>
        if authority.first == "[" {
            let body = authority.dropFirst()
            // #695 R3 verify（security）：沒有結尾 `]` 時 host 曾是整段 authority、rest 是空的，port 檢查整個不走——`https://[user:hunter2/x`
            // 過了；括號內也沒限定內容（`https://[hunter2]/x`）。`host:密碼` 少了 `@` 的形狀換成方括號就繞過 port 檢查
            guard body.contains("]") else {
                return "\(names.url) 的 IPv6 位址缺結尾的 ]（`[` 之後要有 `]`）——store 不收（不回顯原值）"
            }
            host = body.prefix(while: { $0 != "]" })
            rest = body.dropFirst(host.count + 1)   // `]` 之後
            // 括號內只收 IPv6 字面值（十六進位、冒號、點；RFC 3986 `IPv6address`）加可選的 zone id（`%25` 之後，RFC 6874：unreserved）
            let literal = host.prefix(while: { $0 != "%" })
            let zone = host.dropFirst(literal.count)
            func hexOrIPv6Punct(_ u: Unicode.Scalar) -> Bool {
                ("0"..."9").contains(u) || ("a"..."f").contains(u) || ("A"..."F").contains(u) || u == ":" || u == "."
            }
            func zoneChar(_ u: Unicode.Scalar) -> Bool {
                ("0"..."9").contains(u) || ("a"..."z").contains(u) || ("A"..."Z").contains(u) || "-._~%".unicodeScalars.contains(u)
            }
            guard literal.allSatisfy(hexOrIPv6Punct), zone.allSatisfy(zoneChar) else {
                return "\(names.url) 的 IPv6 位址不合法——方括號內只收十六進位、冒號與點（可接 %25 加 zone id）"
                    + "（`host:密碼` 少了 @ 時密碼可能落在這裡），store 不收（不回顯原值）"
            }
        } else {
            host = authority.prefix(while: { $0 != ":" })
            rest = authority.dropFirst(host.count)
        }
        guard !host.isEmpty else {
            return "\(names.url) 缺主機（https:// 之後要有網域或位址）"
        }
        guard rest.isEmpty || (rest.first == ":" && rest.dropFirst().allSatisfy({ ("0"..."9").contains($0) })) else {
            return "\(names.url) 的 port 不是數字——冒號之後只收 ASCII 數字（`host:密碼` 少了 @ 時密碼會落在這裡），store 不收（不回顯原值）"
        }
        return nil
    }

    /// 危險 scalar 或空白：網址要以**編碼形**送（#695 R2 verify 第 1／6／14 列）。整條網址都拒絕（含路徑與 query）——fail-closed、
    /// 使用者沒有裁過範圍；但「拿掉」會把網址改成另一個（波斯文、印度系文字詞中的 ZWNJ 是拼寫的一部分），所以補救寫的是編碼，不是刪除。
    static func unsafeScalarIssue(_ names: Names) -> String {
        "\(names.url) 含控制字元、格式字元（方向控制、零寬字元等）或空白——網址要以編碼形送：路徑與 query 裡的這些字元用百分比編碼"
            + "（空白是 %20、ZWNJ 是 %E2%80%8C），主機用 punycode（xn--）；直接拿掉會變成另一個網址（不回顯原值）"
    }

    /// `prefix` 是 ASCII；逐 scalar 比、只把 ASCII 大寫字母轉小寫（不經 `lowercased()`——那是 `Character` 語意）。
    static func hasASCIIPrefixIgnoringCase(_ scalars: ArraySlice<Unicode.Scalar>, _ prefix: String) -> Bool {
        let p = Array(prefix.unicodeScalars)
        guard scalars.count >= p.count else { return false }
        return zip(scalars, p).allSatisfy { u, q in
            let lower = ("A"..."Z").contains(u) ? Unicode.Scalar(u.value + 32)! : u
            return lower == q
        }
    }

    /// 非 ASCII、且相容分解（NFKD）含 `@ : / ? # \` 之一的 scalar（`＠`、`：`、`﹫`、`℀`……）。
    static func isCompatibilityDelimiter(_ u: Unicode.Scalar) -> Bool {
        guard !u.isASCII else { return false }
        return String(u).decomposedStringWithCompatibilityMapping.unicodeScalars.contains {
            $0 == "@" || $0 == ":" || $0 == "/" || $0 == "?" || $0 == "#" || $0 == "\\"
        }
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
