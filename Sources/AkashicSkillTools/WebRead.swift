import Foundation
import AkashicCore

/// `web-access.md` 讀頁面的三個檢查——`akashic web-read origin｜landing｜check`（#692 R4 verify 把文件裡的 `check-read.py` 移植過來）。
///
/// **為什麼不留在文件裡**：那支約 175 行的 Python 是安全閘，卻要模型每次照抄寫進暫存目錄再跑——跑的是抄本，測試釘的是文件；
/// 它還重寫了一份 `UnsafeToEmitScalar`，而 macOS 的 `/usr/bin/python3`（Unicode 13）判不出之後才指派的格式字元（R4 verify 實測
/// U+0890–0891、U+13439–1343F 九個）。`.claude/rules/swift-is-the-implementation-language.md` 放置表第 3 列：skill 需要的確定性計算
/// 做成 `akashic` 子命令。剔除集合在這裡是 `UnsafeToEmitScalar` 加 noncharacter（`clean` 的 doc），不另寫一份。
///
/// **信任的界線**不變（R3）：`safari-browser js` 在頁面自己的 JS 環境裡求值，頁面能偽造回傳的每一個欄位；主機從 Safari 那一側取
/// （`documents --json` 的網址，讀取前後各一次），剔除與上限在這裡做。全部**不連網、不碰瀏覽器、不寫 store**：輸入是 skill 寫下的暫存檔。
public enum WebRead {
    /// 一次執行的結果：結束碼與要印的行（stdout、stderr 分開，與 Python 版同一個分工）。
    public struct Outcome: Equatable {
        public var code: Int32
        public var stdout: [String] = []
        public var stderr: [String] = []
    }

    /// 結束碼（封閉列舉）：0 通過；1 讀不到、形狀不對、鎖的個數不是 1；2 主機換到已知的驗證服務——整批暫停；4 主機不合。
    ///
    /// **2 是比中止條款保守的一邊，刻意的**（b33 verify X2 第 5／21 列）：中止條款（使用者 2026-10-02）把**已知驗證服務上的驗證頁**
    /// 分到「等人驗證」（區塊二的 3），而這裡只看主機、不看頁面文字，判不出那一頁是不是驗證頁，所以一律整批暫停。同一個終態（分頁停在
    /// 驗證服務的主機上）因此依「有沒有觀察到換主機」走兩種處置：沒有預期主機時（`--expect -`、`--landing -` 而讀取前後同一個主機）
    /// 這裡放行，由區塊二的文字比對分 3／2。要不要改成一種，待使用者裁決（#692 Blocking）。
    /// 不用 3：區塊二以 3 表示等人驗證。命令列本身打錯是 ArgumentParser 的 64。
    public static let rejectCode: Int32 = 4
    public static let pauseCode: Int32 = 2

    /// `rawLength` 的上限（R4 verify 第 7／13 列）：頁面自報的原文長度原樣印進 `READ-OK` 行，而那一行會進模型的 context——
    /// 不設界的話頁面可以塞一個四千多位數的整數。十億個 UTF-16 單位遠超任何誠實的頁面；超過就是 `READ-FAIL`，與「讀回的 JSON 太大」同一類。
    public static let maxRawLength = 1_000_000_000

    // MARK: - 主機

    /// Safari 回報的網址 → `<協定>://<主機>[:<埠>]`；認不出主機時回 `invalid://`（之後的形狀檢查一定拒絕它）。
    ///
    /// **不模擬任何一個解析器，在它們會分岔的地方拒絕**（R4 verify 第 11／14 列）：Python `urlsplit` 與 Foundation 的 `URL` 都把
    /// `https://evil.example\@trusted.example/` 的主機讀成 `trusted.example`，WHATWG（WebKit）把反斜線當 `/`、讀成 `evil.example`。
    /// 所以：fragment 之前有反斜線、空白、控制或不可見字元，主機段（`//` 之後到第一個 `/`、`?`）有 `@`（帳密）、`%`（百分比編碼）、
    /// `[`／`]`（IPv6 字面值），或埠號不是 0–65535 的數字，一律 `invalid://`。WebKit 回報的是正規化後的序列化網址，這些形狀對它
    /// 應該不會出現——出現了就不是我們能確定主機的字串。
    ///
    /// **國際化網域名稱**：Safari 回報 punycode（`xn--`）或 Unicode 都比得起來——非 ASCII 的主機經 Foundation 的 IDNA（UTS #46）
    /// 轉成 punycode；轉不出純 ASCII 的名稱就是 `invalid://`。ASCII 主機轉小寫。
    public static func origin(of url: String) -> String {
        let invalid = "invalid://"
        var s = Array(url.unicodeScalars)
        if let hash = s.firstIndex(of: "#") { s = Array(s[..<hash]) }
        if s.contains(where: { $0 == "\\" || $0.properties.isWhitespace || UnsafeToEmitScalar.contains($0) }) { return invalid }
        guard let colon = s.firstIndex(of: ":"), colon > 0, isASCIILetter(s[0]),
              s[..<colon].allSatisfy({ isASCIILetter($0) || isASCIIDigit($0) || $0 == "+" || $0 == "-" || $0 == "." }) else { return invalid }
        let scheme = String(String.UnicodeScalarView(s[..<colon])).lowercased()
        var rest = Array(s[(colon + 1)...])
        guard rest.count >= 2, rest[0] == "/", rest[1] == "/" else { return scheme + "://" }   // `about:blank` 之類：沒有主機
        rest.removeFirst(2)
        let authority = Array(rest.prefix { $0 != "/" && $0 != "?" })
        if authority.contains(where: { $0 == "@" || $0 == "%" || $0 == "[" || $0 == "]" }) { return invalid }
        var host = authority
        var port: Int?
        if let c = authority.lastIndex(of: ":") {
            host = Array(authority[..<c])
            let digits = authority[(c + 1)...]
            if !digits.isEmpty {
                guard digits.count <= 5, digits.allSatisfy(isASCIIDigit),
                      let n = Int(String(String.UnicodeScalarView(digits))), n <= 65_535 else { return invalid }
                port = n
            }
        }
        guard let ascii = asciiHost(String(String.UnicodeScalarView(host))) else { return invalid }
        return scheme + "://" + ascii + (port.map { ":\($0)" } ?? "")
    }

    /// 主機名 → 小寫的 ASCII（非 ASCII 先經 IDNA 轉 punycode）；轉不出只含字母、數字、`.`、`-` 的名稱回 nil。空的主機回空字串。
    static func asciiHost(_ host: String) -> String? {
        if host.isEmpty { return "" }
        // 埠號已在上面拆掉；主機裡還有 `:` 就是畸形的（`日本.jp:80:`）。ASCII 分支本來就拒，非 ASCII 分支交給 `URL(string:)` 會把它當埠號
        // 讀掉、回 `https://xn--wgv71a.jp`——同一個形狀兩個分支相反（b33 verify X2 第 9 列）
        if host.contains(":") { return nil }
        let converted: String
        if host.unicodeScalars.allSatisfy(\.isASCII) {
            converted = host
        } else {
            guard let h = URL(string: "https://" + host + "/")?.host(percentEncoded: false) else { return nil }   // `false` 才是 IDNA 轉出的 punycode；`true` 回百分比編碼的原字串
            converted = h
        }
        let lower = converted.lowercased()
        guard lower.unicodeScalars.allSatisfy({ isASCIILetter($0) || isASCIIDigit($0) || $0 == "." || $0 == "-" }) else { return nil }
        return lower
    }

    /// 本機與內網用的頂層名稱（`.local`、`.lan`、`.internal`…），以及不是公開網站的特殊用途名稱（RFC 6761 的 `test`、`example`、
    /// `invalid`，RFC 7686 的 `onion`，RFC 9476 的 `alt`；b33 verify X2 第 16 列：先前 `https://foo.test` 照樣 `OK`）：形狀上不是公開網站。
    /// 開分頁之前的檢查（`urlMode`）與落地主機的檢查用這同一份——R4 以前開分頁前的那一份寫在文件的正則裡，少了四個（第 39 列）。
    static let privateSuffixes: Set<String> = ["local", "localhost", "localdomain", "internal", "lan", "home", "box", "intranet", "corp", "private", "arpa",
                                               "test", "example", "invalid", "onion", "alt"]

    /// 落地主機的形狀檢查：`https://` 加一個公開網站形狀的主機——至少兩段、每段只有字母數字與連字號、最後一段是字母（或 IDN 頂層名稱的
    /// `xn--` 形）、不是私有或本機用的後綴、不像 IP 位址（含把四段數字塞進名稱的 `127.0.0.1.nip.io`）、不帶埠號。
    /// **這是形狀檢查，不是信任判斷**：解析到私有位址的公開名稱擋不住。
    public static func hostIsAcceptable(_ origin: String) -> Bool {
        guard origin.hasPrefix("https://") else { return false }
        let host = String(origin.dropFirst("https://".count))
        guard !host.isEmpty, host.count <= 253 else { return false }
        let labels = host.split(separator: ".", omittingEmptySubsequences: false)
        guard labels.count >= 2, labels.allSatisfy({ label in
            !label.isEmpty && label.unicodeScalars.allSatisfy { isASCIILetter($0) || isASCIIDigit($0) || $0 == "-" }
        }) else { return false }
        let tld = labels[labels.count - 1].lowercased()
        let tldOK = (tld.count >= 2 && tld.unicodeScalars.allSatisfy(isASCIILetter))
            || (tld.hasPrefix("xn--") && tld.count > 4)
        guard tldOK, !privateSuffixes.contains(tld) else { return false }
        return host.range(of: #"(^|\.)[0-9]{1,3}([.-][0-9]{1,3}){3}(\.|$)"#, options: .regularExpression) == nil
    }

    /// 印給人看的主機：只印 `<協定>://<主機>[:<埠>]` 形狀的字串（加單引號，與 Python 版的 `ascii()` 同一個樣子），其餘印佔位字。
    /// 這裡的字串來自 Safari 與頁面能影響的網址，不像主機的不印——它可能夾帶任何東西。
    public static func shown(_ origin: String) -> String {
        let ok = origin.range(of: #"^[a-z][a-z0-9+.-]{0,20}://[A-Za-z0-9.-]{0,253}(:[0-9]{1,5})?$"#, options: .regularExpression) != nil
        return ok ? "'" + origin + "'" : "'<不像主機，未印>'"
    }

    /// 這個主機是不是已知的驗證服務（`BotSignals.knownVerificationHosts`，加上以路徑區分的 reCAPTCHA 主機）。
    /// 只看主機：origin 沒有路徑，所以 `www.google.com` 這類只在 `/recaptcha/` 才算驗證服務的主機在這裡**算進來**——
    /// 用到它的地方是「主機不合」的分流，算進來的結果是整批暫停（保守的一邊，中止條款「拿不準是哪一種就當整批暫停」）。
    public static func isVerificationServiceHost(_ origin: String) -> Bool {
        guard hostIsAcceptable(origin) else { return false }
        if BotSignals.isKnownVerificationService(url: origin + "/") { return true }
        let host = String(origin.dropFirst("https://".count))
        return BotSignals.knownVerificationPathPrefixes.contains { $0.host == host }
    }

    // MARK: - 文字

    /// 截到 `limit` 個 UTF-16 單位，再剔除不可見與控制字元。`cut` 是截之前的長度超過上限（不從截後的長度反推）。
    ///
    /// 剔除集合是 `UnsafeToEmitScalar.contains`（`Default_Ignorable_Code_Point`、Cc／Cf／Zl／Zp、非 U+0020 的 Zs、Co、`rendersBlank`）
    /// **加上 noncharacter**——與 repo 給 LLM 的出口 `escapesInLLMDocument` 同一個加項（b33 verify X2 第 15 列：這裡的輸出也進 LLM context，
    /// 先前 U+FFFF、U+FDD0、U+1FFFE 原樣留下）。與 `escapesInLLMDocument` 的差別只有 ZWJ／ZWNJ：那邊保留（正字法，逃脫可還原），這裡刪掉
    /// （剔除不可還原，而頁面文字只當證據引用）。只在之前多三條映射：LF 與 TAB 保留；CR（CRLF 算一個）、VT、FF、NEL、Zl、Zp 換成換行；
    /// 非 U+0020 的 Zs 換成空白（刪掉會把相鄰的字黏在一起）。截在代理對中間留下的孤立代理字元刪掉。**未指派的碼位（Cn）不刪**：判斷
    /// 一個碼位指派了沒有，用的是執行 `akashic` 那台 macOS 的 Swift runtime（`libswiftCore` 是動態連結的）的 Unicode 表，比它新的格式字元
    /// 在舊系統上會被當成未指派而留下。
    public static func clean(_ text: String, limit: Int) -> (text: String, cut: Bool) {
        let units = Array(text.utf16)
        let cut = units.count > limit
        var scalars: [Unicode.Scalar] = []
        var iterator = units.prefix(max(0, limit)).makeIterator()
        var decoder = UTF16()
        decode: while true {
            switch decoder.decode(&iterator) {
            case .scalarValue(let u): scalars.append(u)
            case .emptyInput: break decode
            case .error: continue   // 截斷造出的孤立代理字元
            }
        }
        var out = String.UnicodeScalarView()
        var i = 0
        while i < scalars.count {
            let u = scalars[i]
            let cat = u.properties.generalCategory
            if u == "\r", i + 1 < scalars.count, scalars[i + 1] == "\n" {
                out.append("\n"); i += 2; continue
            }
            if u == "\n" || u == "\t" {
                out.append(u)
            } else if u == "\r" || u.value == 0x0B || u.value == 0x0C || u.value == 0x85 || cat == .lineSeparator || cat == .paragraphSeparator {
                out.append("\n")
            } else if cat == .spaceSeparator {
                out.append(" ")
            } else if !UnsafeToEmitScalar.contains(u) && !u.properties.isNoncharacterCodePoint {
                out.append(u)
            }
            i += 1
        }
        return (String(out), cut)
    }

    // MARK: - 三種用法

    /// `origin`：從 `safari-browser documents --json` 的輸出找網址結尾是 `#akashic-<tag>` 的分頁，**恰好一個**才印它的 origin。
    /// 網址的路徑與查詢字串不印、不寫進任何檔。
    public static func originMode(documents: Data, tag: String) -> Outcome {
        let suffix = "#akashic-" + tag
        guard let docs = try? PyJSONParser.parse(documents, loneSurrogates: .replacementCharacter) as? [Any] else {
            return Outcome(code: 1, stderr: ["ORIGIN-FAIL documents 的輸出不是預期的 JSON - STOP"])
        }
        let urls = docs.compactMap { ($0 as? [String: Any])?["url"] as? String }.filter { $0.hasSuffix(suffix) }
        guard urls.count == 1 else {
            return Outcome(code: 1, stderr: ["tab lock: \(urls.count) tabs match (need exactly 1) - STOP"])
        }
        return Outcome(code: 0, stdout: [origin(of: urls[0])])
    }

    /// `url`：**開分頁之前**檢查要開的網址（b33 verify X2 第 16／39 列：先前這道檢查是文件裡的一條正則，由模型照著看，主機的部分比落地主機
    /// 的 `hostIsAcceptable` 寬——`https://192.168.1.1.nip.io/`、`.home`、`.box`、`.private` 都過得了，請求帶著 profile 的 cookie 送出去之後
    /// 才在落地主機那一步被擋）。網址整串要符合文件「完整網址」那一列的形狀（只收 https 與 ASCII 主機；路徑與查詢只收那幾個字元；不含 `#`、
    /// 引號、反斜線、反引號、`$`、空白），**主機再過 `hostIsAcceptable`**（與落地主機同一個檢查），路徑段百分比解碼後不得是 `.`／`..`。
    /// 結束碼：0 可以開；4 主機形狀不合；1 讀不到或其餘形狀不合。只印主機（`shown`），不印網址的路徑與查詢。
    public static func urlMode(urlFile: String) -> Outcome {
        let url: String
        do {
            url = try readTrimmed(urlFile)
        } catch {
            return Outcome(code: 1, stdout: ["URL-FAIL 讀不到網址檔：" + displaySafeError(error, max: 200)])
        }
        let shape = #"\Ahttps://([A-Za-z0-9-]+\.)+[A-Za-z]{2,}(/[A-Za-z0-9._~%!*+,;=:@/()-]*)?(\?[A-Za-z0-9._~%!*+,;=:@/?()&-]*)?\z"#
        guard url.range(of: shape, options: .regularExpression) != nil else {
            return Outcome(code: 1, stdout: ["URL-REJECT 網址形狀不合（只收 https 與 ASCII 主機；路徑與查詢只收 A–Z a–z 0–9 與 ._~%!*+,;=:@/()-、查詢另收 ?&；"
                                             + "不含 #、引號、反斜線、反引號、$、空白）：不開"])
        }
        let host = origin(of: url)
        guard hostIsAcceptable(host) else {
            return Outcome(code: rejectCode, stdout: ["URL-REJECT " + shown(host) + "（主機形狀不合：私有、本機或特殊用途的名稱，或 IP 位址的形狀）：不開"])
        }
        let afterHost = url.dropFirst("https://".count).drop { $0 != "/" && $0 != "?" }
        let path = afterHost.prefix { $0 != "?" }
        for segment in path.split(separator: "/", omittingEmptySubsequences: false) {
            let decoded = String(segment).removingPercentEncoding ?? String(segment)
            if decoded == "." || decoded == ".." {
                return Outcome(code: 1, stdout: ["URL-REJECT 路徑段（百分比解碼後）是 . 或 ..：網址解析會把它折成同一主機的別的路徑，不開"])
            }
        }
        return Outcome(code: 0, stdout: ["URL-OK " + shown(host)])
    }

    /// `landing`：**先刪掉落地主機檔**，形狀合格（給了開的網址檔時還要與它的主機相同）才寫回去（先寫暫存檔再改名）——`REJECT` 之後
    /// 沒有一個「驗過的」檔留著。主機不合但落地主機是已知的驗證服務時不是 4，是 2（整批暫停，R4 verify 第 10 列）。
    public static func landingMode(originFile: String, landingFile: String, expectFile: String?) -> Outcome {
        if let why = removalProblem(landingFile) {
            return Outcome(code: 1, stdout: ["LANDING-FAIL --out " + shownPath(landingFile) + " " + why + "：只刪一般檔或 symlink，什麼都沒刪"])
        }
        if let why = removeFile(landingFile) {
            return Outcome(code: 1, stdout: ["LANDING-FAIL --out " + shownPath(landingFile) + " " + why])
        }
        let got: String, want: String
        do {
            got = try readTrimmed(originFile)
            want = try expectFile.map { origin(of: try readTrimmed($0)) } ?? got
        } catch {
            return Outcome(code: 1, stdout: ["LANDING-FAIL 讀不到：" + displaySafeError(error, max: 200)])
        }
        if !hostIsAcceptable(got) || got != want {
            if got != want, isVerificationServiceHost(got) {
                return Outcome(code: pauseCode, stdout: ["REJECT " + shown(got) + "（已知的驗證服務；開的網址的主機是 " + shown(want)
                                                         + "）- STOP THE WHOLE RUN：整批暫停（只看主機、判不出是不是等人驗證，取保守的一邊），不是不可達"])
            }
            return Outcome(code: rejectCode, stdout: ["REJECT " + shown(got) + (got == want ? "" : "（開的網址的主機是 " + shown(want) + "）")])
        }
        do {
            try writeAtomically(got + "\n", to: landingFile)
        } catch {
            return Outcome(code: 1, stdout: ["LANDING-FAIL 寫不進落地主機檔：" + displaySafeError(error, max: 200)])
        }
        return Outcome(code: 0, stdout: ["OK " + shown(got)])
    }

    /// `check` 的輸入（全部是暫存目錄裡的檔；`landingFile` 是 nil 時不比對落地主機）。
    public struct CheckInput {
        public var rawFile: String
        public var outFile: String
        public var limit: Int
        public var landingFile: String?
        public var beforeFile: String
        public var afterFile: String

        public init(rawFile: String, outFile: String, limit: Int, landingFile: String?, beforeFile: String, afterFile: String) {
            self.rawFile = rawFile; self.outFile = outFile; self.limit = limit
            self.landingFile = landingFile; self.beforeFile = beforeFile; self.afterFile = afterFile
        }
    }

    /// `check`：**參數先驗**（`--out`、`--raw` 要是不存在、一般檔或 symlink；目錄與其他型態具名拒絕、**什麼都不刪**——b33 verify：
    /// 先前以 `FileManager.removeItem` 刪，`--raw <目錄>` 整棵遞迴刪除），然後**先刪掉輸出檔**（`READ-REJECT` 或 `READ-FAIL` 之後不留上一次的
    /// 文字），**不論結果都刪掉讀回的 JSON**（第三方文字；通過檢查的文字另寫在輸出檔）——刪不掉就報出來，原本是 `READ-OK` 時改成 `READ-FAIL`
    /// 並收回寫出的文字（第三方原文還在，這一次不算讀成）。讀取前後 Safari 回報的主機不同、或與驗過的落地主機不同 → 4；沒有比對落地主機時，
    /// 主機還要形狀合格（R4 verify 第 15 列：預設不再 fail-open）→ 否則 4；換到已知的驗證服務 → 2。讀回的 JSON 太大、欄位型別不對、
    /// `rawLength` 超出範圍或比頁面交回的文字還短、剔除之後沒有看得見的字 → `READ-FAIL`（1）。通過才截、剔除、寫出。
    public static func checkMode(_ input: CheckInput) -> Outcome {
        for (flag, path) in [("--out", input.outFile), ("--raw", input.rawFile)] {
            if let why = removalProblem(path) {
                return Outcome(code: 1, stdout: ["READ-FAIL \(flag) " + shownPath(path) + " " + why + "：只刪一般檔或 symlink，什麼都沒刪"])
            }
        }
        var outcome = checkBody(input)
        if let why = removeFile(input.rawFile) {
            outcome.stderr.append("RAW-NOT-REMOVED --raw " + shownPath(input.rawFile) + " " + why + "：讀回的 JSON（第三方原文）還在")
            if outcome.code == 0 {
                let outLeft = removeFile(input.outFile).map { "；輸出檔也刪不掉（\($0)）" } ?? ""
                outcome.code = 1
                outcome.stdout = ["READ-FAIL 讀回的 JSON 刪不掉（\(why)）：這一次不算讀成，文字收回" + outLeft]
            }
        }
        return outcome
    }

    /// `checkMode` 的本體：讀回的 JSON 由呼叫端（`checkMode`）在結束時刪。
    private static func checkBody(_ input: CheckInput) -> Outcome {
        if let why = removeFile(input.outFile) {
            return Outcome(code: 1, stdout: ["READ-FAIL --out " + shownPath(input.outFile) + " " + why])
        }
        guard input.limit >= 1 else { return Outcome(code: 1, stdout: ["READ-FAIL 上限要是正整數"]) }
        let before: String, after: String
        do {
            before = try readTrimmed(input.beforeFile)
            after = try readTrimmed(input.afterFile)
        } catch {
            return Outcome(code: 1, stdout: ["READ-FAIL " + displaySafeError(error, max: 200)])
        }
        if before != after {
            if let pause = pauseIfVerificationService([before, after]) { return pause }
            return Outcome(code: rejectCode, stdout: ["READ-REJECT 讀取前後分頁的主機不同：前 " + shown(before) + "、後 " + shown(after) + "（文字不寫出）"])
        }
        if let landingFile = input.landingFile {
            guard let want = try? readTrimmed(landingFile) else {
                return Outcome(code: 1, stdout: ["READ-FAIL 找不到驗過的落地主機檔 " + shownPath(landingFile) + "：這個分頁要先跑落地主機區塊"])
            }
            if !hostIsAcceptable(want) || before != want {
                if before != want, let pause = pauseIfVerificationService([before]) { return pause }
                return Outcome(code: rejectCode, stdout: ["READ-REJECT 落地主機不合：驗過的 " + shown(want) + "，Safari 這次回報的 " + shown(before) + "（文字不寫出）"])
            }
        } else if !hostIsAcceptable(before) {
            return Outcome(code: rejectCode, stdout: ["READ-REJECT 分頁的主機形狀不合（不是 https、帶埠號、私有或本機用的名稱、IP 位址的形狀）：" + shown(before) + "（文字不寫出）"])
        }
        let size: Int
        do {
            size = (try FileManager.default.attributesOfItem(atPath: input.rawFile)[.size] as? NSNumber)?.intValue ?? 0
        } catch {
            return Outcome(code: 1, stdout: ["READ-FAIL 讀不到讀回的檔：" + displaySafeError(error, max: 200)])
        }
        if size > 6 * input.limit + 4096 {
            return Outcome(code: 1, stdout: ["READ-FAIL 讀回的 JSON 有 \(size) bytes，超過 6 × 上限 + 4096：不是誠實頁面的輸出，整個不收"])
        }
        let text: String, truncated: Bool, rawLength: Int
        do {
            let data = try Data(contentsOf: URL(fileURLWithPath: input.rawFile))
            guard let d = try PyJSONParser.parse(data, loneSurrogates: .drop) as? [String: Any],
                  let t = d["text"] as? String, let tr = d["truncated"], tr is Bool, let b = tr as? Bool,
                  let rl = d["rawLength"], !(rl is Bool), let n = rl as? Int else {
                return Outcome(code: 1, stdout: ["READ-FAIL 讀回的不是預期的 JSON：欄位型別不對（text 字串、truncated 布林、rawLength 整數）"])
            }
            text = t; truncated = b; rawLength = n
        } catch {
            return Outcome(code: 1, stdout: ["READ-FAIL 讀回的不是預期的 JSON：" + displaySafeError(error, max: 200)])
        }
        guard (0...maxRawLength).contains(rawLength) else {
            return Outcome(code: 1, stdout: ["READ-FAIL 頁面回報的原文長度不在 0–\(maxRawLength) 之間：不是誠實頁面的輸出，整個不收"])
        }
        // 讀取的運算式交回的是原文的前段（`text` ≤ `rawLength`）。比交回的文字還短的原文長度不可能出自誠實的頁面（b33 verify 第 6 列：
        // 先前照印成 `raw_length=2 kept=5`，報告裡會寫出「已截（原文 2 單位）」這種自相矛盾的證據）。
        guard rawLength >= text.utf16.count else {
            return Outcome(code: 1, stdout: ["READ-FAIL 頁面回報的原文長度比它交回的文字還短：不是誠實頁面的輸出，整個不收"])
        }
        let (kept, cut) = clean(text, limit: input.limit)
        // 剔除之後沒有看得見的字（整段是不可見或控制字元、或頁面還沒渲染出來）：不當成「沒有訊號」往下走（b33 verify 第 17 列：
        // 區塊二把空的首屏交給 bot-signals，它回 1＝沒有訊號，而中止條款說拿不準就當作是）。
        guard kept.unicodeScalars.contains(where: { !$0.properties.isWhitespace }) else {
            return Outcome(code: 1, stdout: ["READ-FAIL 剔除之後沒有看得見的字（頁面回報原文 \(rawLength) 單位）：頁面還沒渲染，或內容整段是不可見字元——不當成沒有訊號"])
        }
        do {
            try writeAtomically(kept, to: input.outFile)
        } catch {
            return Outcome(code: 1, stdout: ["READ-FAIL 寫不進輸出檔：" + displaySafeError(error, max: 200)])
        }
        // 被截：頁面說截了、這裡截了，或頁面回報的原文長度超過上限（b33 verify 第 11 列：誠實的頁面不會在 `rawLength > 上限` 時說沒截）
        let wasCut = truncated || cut || rawLength > input.limit
        return Outcome(code: 0, stdout: ["READ-OK host=" + shown(before) + " truncated=" + (wasCut ? "yes" : "no")
                                         + " raw_length=\(rawLength) kept=\(kept.utf16.count)"])
    }

    /// 主機不合的分流：其中一個 Safari 回報的主機是已知的驗證服務時，不是「不可達」——頁面把分頁送去驗證了，整批暫停（保守的一邊，見 `pauseCode` 上面的說明）。
    static func pauseIfVerificationService(_ origins: [String]) -> Outcome? {
        guard let hit = origins.first(where: isVerificationServiceHost) else { return nil }
        return Outcome(code: pauseCode, stdout: ["READ-REJECT 分頁換到已知的驗證服務 " + shown(hit)
                                                 + "（文字不寫出）- STOP THE WHOLE RUN：整批暫停（只看主機、判不出是不是等人驗證，取保守的一邊），不是不可達"])
    }

    // MARK: - 小工具

    static func isASCIILetter(_ u: Unicode.Scalar) -> Bool { ("a"..."z").contains(u) || ("A"..."Z").contains(u) }
    static func isASCIIDigit(_ u: Unicode.Scalar) -> Bool { ("0"..."9").contains(u) }

    static func readTrimmed(_ path: String) throws -> String {
        try String(contentsOfFile: path, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - 刪檔（b33 verify X2 第 0／1 列）

    /// 這個路徑能不能交給 `removeFile`：不存在、一般檔、symlink（刪的是連結本身）才可以；目錄與其他型態回原因。
    ///
    /// **移植前的 Python 用 `os.remove`**，遇到目錄失敗、不刪；R4 改成 `FileManager.removeItem` 之後對目錄**整棵遞迴刪除**——
    /// `landing --out .` 把目前目錄整個刪掉、`check --raw <目錄>` 在 READ-FAIL 之後照樣刪（b33 verify 以真 binary 實測）。路徑由呼叫端給
    /// （skill 的區塊給的是暫存目錄裡的檔），程式不限制它在哪個目錄；只保證不刪目錄、刪失敗會說。
    static func removalProblem(_ path: String) -> String? {
        var st = stat()
        guard lstat(path, &st) == 0 else {
            let code = errno
            return code == ENOENT ? nil : "看不到它的狀態（\(errnoText(code))）"
        }
        switch st.st_mode & S_IFMT {
        case S_IFREG, S_IFLNK: return nil
        case S_IFDIR: return "是目錄"
        default: return "不是一般檔"
        }
    }

    /// 刪掉一般檔或 symlink：回 `nil`＝刪了或本來就不在（`ENOENT`），否則回原因。只呼叫 `unlink`——檢查之後被換成目錄時 `unlink` 失敗、
    /// 不會遞迴（不再 `try?` 吞掉失敗）。
    static func removeFile(_ path: String) -> String? {
        if let why = removalProblem(path) { return why }
        if unlink(path) == 0 { return nil }
        let code = errno
        return code == ENOENT ? nil : "刪不掉（\(errnoText(code))）"
    }

    /// 錯誤訊息裡的路徑：呼叫端給的字串，逃脫不可見字元、截長。
    static func shownPath(_ path: String) -> String { "「" + displaySafeInvisible(path, max: 300) + "」" }

    /// 系統給的錯誤說明（固定英文字串，不含使用者資料）。
    static func errnoText(_ code: Int32) -> String { "errno \(code)，\(String(cString: strerror(code)))" }

    static func writeAtomically(_ text: String, to path: String) throws {
        try Data(text.utf8).write(to: URL(fileURLWithPath: path), options: .atomic)
    }
}
