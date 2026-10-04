import Foundation
import AkashicCore

/// `web-access.md` 讀頁面的三個檢查——`akashic web-read origin｜landing｜check`（#692 R4 verify 把文件裡的 `check-read.py` 移植過來）。
///
/// **為什麼不留在文件裡**：那支約 175 行的 Python 是安全閘，卻要模型每次照抄寫進暫存目錄再跑——跑的是抄本，測試釘的是文件；
/// 它還重寫了一份 `UnsafeToEmitScalar`，而 macOS 的 `/usr/bin/python3`（Unicode 13）判不出之後才指派的格式字元（R4 verify 實測
/// U+0890–0891、U+13439–1343F 九個）。`.claude/rules/swift-is-the-implementation-language.md` 放置表第 3 列：skill 需要的確定性計算
/// 做成 `akashic` 子命令。剔除集合在這裡**就是** `UnsafeToEmitScalar`，沒有第二份。
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

    /// 結束碼（封閉列舉）：0 通過；1 讀不到、形狀不對、鎖的個數不是 1；2 主機換到已知的驗證服務——照中止條款整批暫停；4 主機不合。
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

    /// 本機與內網用的頂層名稱（`.local`、`.lan`、`.internal`…）：形狀上不是公開網站。
    static let privateSuffixes: Set<String> = ["local", "localhost", "localdomain", "internal", "lan", "home", "box", "intranet", "corp", "private", "arpa"]

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
    /// 剔除集合**就是** `UnsafeToEmitScalar.contains`（`Default_Ignorable_Code_Point`、Cc／Cf／Zl／Zp、非 U+0020 的 Zs、Co、
    /// `rendersBlank`），只在之前多三條映射：LF 與 TAB 保留；CR（CRLF 算一個）、VT、FF、NEL、Zl、Zp 換成換行；非 U+0020 的 Zs 換成空白
    /// （刪掉會把相鄰的字黏在一起）。截在代理對中間留下的孤立代理字元刪掉。
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
            } else if !UnsafeToEmitScalar.contains(u) {
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

    /// `landing`：**先刪掉落地主機檔**，形狀合格（給了開的網址檔時還要與它的主機相同）才寫回去（先寫暫存檔再改名）——`REJECT` 之後
    /// 沒有一個「驗過的」檔留著。主機不合但落地主機是已知的驗證服務時不是 4，是 2（整批暫停，R4 verify 第 10 列）。
    public static func landingMode(originFile: String, landingFile: String, expectFile: String?) -> Outcome {
        remove(landingFile)
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
                                                         + "）- STOP THE WHOLE RUN：照中止條款整批暫停，不是不可達"])
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

    /// `check`：**先刪掉輸出檔**（`READ-REJECT` 或 `READ-FAIL` 之後不留上一次的文字），**不論結果都刪掉讀回的 JSON**（第三方文字；
    /// 通過檢查的文字另寫在輸出檔）。讀取前後 Safari 回報的主機不同、或與驗過的落地主機不同 → 4；沒有比對落地主機時，主機還要形狀合格
    /// （R4 verify 第 15 列：預設不再 fail-open）→ 否則 4；換到已知的驗證服務 → 2。讀回的 JSON 太大、欄位型別不對、`rawLength` 超出範圍
    /// → `READ-FAIL`（1）。通過才截、剔除、寫出。
    public static func checkMode(_ input: CheckInput) -> Outcome {
        remove(input.outFile)
        defer { remove(input.rawFile) }
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
                return Outcome(code: 1, stdout: ["READ-FAIL 找不到驗過的落地主機檔 " + displaySafeInvisible(landingFile, max: 300) + "：這個分頁要先跑落地主機區塊"])
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
        let (kept, cut) = clean(text, limit: input.limit)
        do {
            try writeAtomically(kept, to: input.outFile)
        } catch {
            return Outcome(code: 1, stdout: ["READ-FAIL 寫不進輸出檔：" + displaySafeError(error, max: 200)])
        }
        return Outcome(code: 0, stdout: ["READ-OK host=" + shown(before) + " truncated=" + (truncated || cut ? "yes" : "no")
                                         + " raw_length=\(rawLength) kept=\(kept.utf16.count)"])
    }

    /// 主機不合的分流：其中一個 Safari 回報的主機是已知的驗證服務時，不是「不可達」——頁面把分頁送去驗證了，照中止條款整批暫停。
    static func pauseIfVerificationService(_ origins: [String]) -> Outcome? {
        guard let hit = origins.first(where: isVerificationServiceHost) else { return nil }
        return Outcome(code: pauseCode, stdout: ["READ-REJECT 分頁換到已知的驗證服務 " + shown(hit)
                                                 + "（文字不寫出）- STOP THE WHOLE RUN：照中止條款整批暫停，不是不可達"])
    }

    // MARK: - 小工具

    static func isASCIILetter(_ u: Unicode.Scalar) -> Bool { ("a"..."z").contains(u) || ("A"..."Z").contains(u) }
    static func isASCIIDigit(_ u: Unicode.Scalar) -> Bool { ("0"..."9").contains(u) }

    static func readTrimmed(_ path: String) throws -> String {
        try String(contentsOfFile: path, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func remove(_ path: String) { try? FileManager.default.removeItem(atPath: path) }

    static func writeAtomically(_ text: String, to path: String) throws {
        try Data(text.utf8).write(to: URL(fileURLWithPath: path), options: .atomic)
    }
}
