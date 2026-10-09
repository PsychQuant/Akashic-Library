import ArgumentParser
import Foundation
import AkashicCore
import AkashicSkillTools

/// `web-access.md` 讀頁面的四個檢查（#692 R4 verify：文件裡的 `check-read.py` 移植成 Swift，見 `WebRead`；b34 加開分頁之前的 `url`）。
///
/// 全部**不寫 store、不連網、不碰瀏覽器**：輸入是 skill 寫進暫存目錄的檔與 `safari-browser documents --json` 的輸出，
/// 輸出是一行判定與（`landing`、`check` 通過時）一個暫存檔。`landing` 與 `check` 會**刪** `--out`／`--raw` 指的檔——只刪一般檔或 symlink，
/// 目錄與其他型態在刪任何東西之前具名拒絕（b33 verify X2 第 0／1 列）。MCP 沒有對應面：這是 skill 讀頁面時的內部步驟
/// （`mcp-cli-parity` 的 CLI-only 表一列）。
struct WebReadCmd: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "web-read",
        abstract: "web-access.md 讀頁面的檢查（skill 用）：開之前的網址、鎖到的分頁的主機、驗落地主機、檢查讀回的文字並剔除",
        discussion: """
        結束碼（四個子命令共用）：0 通過；1 讀不到、形狀不對、鎖到的分頁不是恰好一個、--out／--raw 是目錄；2 整批暫停；3 等人驗證；\
        4 主機不合（文字不寫出、網址不開）。命令列本身打錯是 64。2 與 3 只出自 check：分頁在已知的驗證服務上（Cloudflare 挑戰、hCaptcha、\
        reCAPTCHA 的主機；只看主機，所以 www.google.com 也算），不論是換到還是直接落在那裡，都以頁面文字分——等人驗證的標籤 3，其他 2。\
        不寫 store、不連網、不碰瀏覽器；landing 與 check 刪 --out／--raw 指的檔（只刪一般檔或 symlink）。
        """,
        subcommands: [WebReadURLCmd.self, WebReadOriginCmd.self, WebReadLandingCmd.self, WebReadCheckCmd.self])
}

/// 一次性碼的形狀（web-access.md 區塊一以 `od -An -N4 -tx1 /dev/urandom` 產生）。
private func validateTag(_ tag: String) throws {
    guard tag.range(of: "^[0-9a-f]{8}$", options: .regularExpression) != nil else {
        throw ValidationError("--tag 要是 8 個小寫十六進位字元（區塊一印出的 T）")
    }
}

private func emit(_ outcome: WebRead.Outcome) throws {
    for line in outcome.stdout { print(line) }   // display-safe-exempt: line：WebRead 組成的固定文字，主機只印 `shown` 驗過形狀的字串、錯誤文字已過 displaySafeInvisible
    for line in outcome.stderr { FileHandle.standardError.write(Data((line + "\n").utf8)) }
    if outcome.code != 0 { throw ExitCode(outcome.code) }
}

struct WebReadURLCmd: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "url",
        abstract: "開分頁之前檢查要開的網址：URL-OK＝0 才開；主機形狀不合＝4；其餘形狀不合或讀不到＝1",
        discussion: """
        網址整串：https、ASCII 主機（國際化網域名稱寫成 xn-- 形，頂層名稱也可以是 xn-- 形）、不帶埠號；路徑與查詢只收 A–Z a–z 0–9 與 \
        ._~%!*+,;=:@/()-（查詢另收 ?&）；不含 #、引號、反斜線、反引號、$、空白；路徑段百分比解碼後不得是 . 或 ..。網址檔不修剪：只去掉結尾的\
        換行（與 "$(cat …)" 相同），前後的空白、CR 都算形狀不合——檢查的要就是 shell 開出去的那一份。主機另過與 landing 同一個形狀檢查（私有、\
        本機或特殊用途的頂層名稱如 .local .home .test .example .onion，IP 位址的形狀如 127.0.0.1.nip.io、app-127-0-0-1.nip.io，都不收）。\
        只印主機。這是形狀檢查：擋不了解析到私有位址的公開名稱（foo.nip.io 這類萬用 DNS、7f000001.nip.io 的十六進位形都過得了），\
        也擋不了轉址之後的主機（那由 landing 驗）。
        """)

    @Option(name: .long, help: "要開的網址檔（一行；web-access.md 的 <W>/url-<序號>.txt）")
    var file: String

    func run() throws {
        try emit(WebRead.urlMode(urlFile: file))
    }
}

struct WebReadOriginCmd: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "origin",
        abstract: "從 stdin 讀 safari-browser documents --json，網址結尾是 #akashic-<tag> 的分頁要恰好一個，印它的 <協定>://<主機>[:<埠>]",
        discussion: """
        只印這一段，網址的路徑與查詢字串不印。主機段有帳密（@）、百分比編碼、IPv6 字面值，或 fragment 之前有反斜線、空白、\
        控制或不可見字元時印 invalid://（不同的網址解析器會讀出不同的主機，不猜）。國際化網域名稱一律轉成 punycode。
        """)

    @Option(name: .long, help: "這個分頁的一次性碼（8 個小寫十六進位字元）")
    var tag: String

    func validate() throws { try validateTag(tag) }

    func run() throws {
        try emit(WebRead.originMode(documents: FileHandle.standardInput.readDataToEndOfFile(), tag: tag))
    }
}

struct WebReadLandingCmd: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "landing",
        abstract: "驗落地主機：先刪掉 --out，形狀合格（--expect 是網址檔時還要與那條網址的主機相同；已知的驗證服務不比對、照樣寫回）才寫回；OK＝0、REJECT＝4",
        discussion: """
        形狀：https、主機至少兩段、最後一段是字母或 xn-- 形、不帶埠號、不是私有、本機或特殊用途的名稱、不像 IP 位址。\
        落地主機是已知的驗證服務（Cloudflare 挑戰、hCaptcha、reCAPTCHA 的主機；只看主機，所以 www.google.com 也算）時，不論與 --expect 的\
        主機同不同都寫下它、印 OK 並註明是驗證服務：之後的 check 對它不給 READ-OK，以頁面文字分等人驗證 3／整批暫停 2。\
        --out 是目錄或其他不是一般檔、symlink 的東西時結束碼 1、什麼都不刪。
        """)

    @Option(name: .long, help: "origin 子命令寫下的檔（Safari 回報的主機）")
    var origin: String

    @Option(name: .long, help: "落地主機檔：先刪，通過才寫")
    var out: String

    // `-` 而不是省略：區塊以 `--expect "$EXPECT"` 一律傳入。zsh 不對未加引號的展開分詞，`${EXPECT:+--expect "$EXPECT"}` 在 zsh 裡是一個引數
    @Option(name: .long, help: "開的網址檔（使用者給定或確認的網址：落地主機要與它的主機相同），或 - 表示不比對")
    var expect: String

    func validate() throws {
        guard !expect.isEmpty else { throw ValidationError("--expect 不可為空：給開的網址檔，或 - 表示不比對") }
    }

    func run() throws {
        try emit(WebRead.landingMode(originFile: origin, landingFile: out, expectFile: expect == "-" ? nil : expect))
    }
}

struct WebReadCheckCmd: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "check",
        abstract: "檢查讀回的 JSON 並寫出剔除後的文字：參數驗過之後先刪 --out、不論結果都刪 --raw；READ-OK＝0、READ-FAIL＝1、READ-PAUSE＝2、READ-VERIFY＝3、READ-REJECT＝4",
        discussion: """
        --out、--raw 要是不存在、一般檔或 symlink；是目錄或其他型態時 READ-FAIL、什麼都不刪（命令列本身打錯的 64 也不刪）。\
        讀取前後 Safari 回報的主機（--before、--after）要相同；--landing 是落地主機檔時還要等於它，是 - 時主機要形狀合格。\
        讀回的 JSON 超過 6 × 上限 + 4096 bytes、欄位型別不對、rawLength 不在 0–1,000,000,000 之間或比交回的文字還短、剔除之後沒有看得見的字，\
        都是 READ-FAIL。通過才截到 --limit 個 UTF-16 單位、剔除不可見與控制字元（repo 輸出端那一份加 noncharacter）、寫出；--raw 刪不掉時\
        改成 READ-FAIL、收回寫出的文字。truncated=yes：頁面說截了、這裡截了，或頁面回報的原文長度超過 --limit。\
        讀取之前或之後 Safari 回報的主機是已知的驗證服務時，不做上面的主機比對、沒有 READ-OK、文字不寫出：剔除後的文字有等人驗證的標籤\
        （CAPTCHA、人類檢查、Cloudflare「Just a moment」、按住驗證）而且讀完時分頁還在驗證服務上是 READ-VERIFY（3），其他——整批暫停的\
        標籤、沒有訊號、讀回的文字不能用、讀完時已經離開驗證服務——是 READ-PAUSE（2）。
        """)

    @Option(name: .long, help: "safari-browser js --output 寫下的 JSON（{text, truncated, rawLength}）；不論結果都刪")
    var raw: String

    @Option(name: .long, help: "剔除後的文字寫到這裡；先刪，READ-OK 才寫")
    var out: String

    @Option(name: .long, help: "長度上限（UTF-16 單位，1–1,000,000）")
    var limit: Int

    @Option(name: .long, help: "落地主機檔，或 - 表示不比對落地主機")
    var landing: String

    @Option(name: .long, help: "讀取之前 origin 子命令寫下的檔")
    var before: String

    @Option(name: .long, help: "讀取之後 origin 子命令寫下的檔")
    var after: String

    func validate() throws {
        guard (1...1_000_000).contains(limit) else { throw ValidationError("--limit 要在 1–1,000,000 之間") }
        guard !landing.isEmpty else { throw ValidationError("--landing 不可為空：給落地主機檔，或 - 表示不比對") }
    }

    func run() throws {
        try emit(WebRead.checkMode(.init(rawFile: raw, outFile: out, limit: limit, landingFile: landing == "-" ? nil : landing,
                                         beforeFile: before, afterFile: after)))
    }
}
