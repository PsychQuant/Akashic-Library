import ArgumentParser
import Foundation
import AkashicCore
import AkashicSkillTools

/// `web-access.md` 讀頁面的三個檢查（#692 R4 verify：文件裡的 `check-read.py` 移植成 Swift，見 `WebRead`）。
///
/// 全部**不寫 store、不連網、不碰瀏覽器**：輸入是 skill 寫進暫存目錄的檔與 `safari-browser documents --json` 的輸出，
/// 輸出是一行判定與（`landing`、`check` 通過時）一個暫存檔。MCP 沒有對應面：這是 skill 讀頁面時的內部步驟
/// （`mcp-cli-parity` 的 CLI-only 表一列）。
struct WebReadCmd: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "web-read",
        abstract: "web-access.md 讀頁面的檢查（skill 用）：鎖到的分頁的主機、驗落地主機、檢查讀回的文字並剔除",
        discussion: """
        結束碼（三個子命令共用）：0 通過；1 讀不到、形狀不對、鎖到的分頁不是恰好一個；2 主機換到已知的驗證服務——照中止條款整批暫停；\
        4 主機不合（文字不寫出）。命令列本身打錯是 64。不寫 store、不連網、不碰瀏覽器。
        """,
        subcommands: [WebReadOriginCmd.self, WebReadLandingCmd.self, WebReadCheckCmd.self])
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
        abstract: "驗落地主機：先刪掉 --out，形狀合格（--expect 是網址檔時還要與那條網址的主機相同）才寫回；OK＝0、REJECT＝4",
        discussion: """
        形狀：https、主機至少兩段、最後一段是字母或 xn-- 形、不帶埠號、不是私有或本機用的名稱、不像 IP 位址。\
        主機不合而落地主機是已知的驗證服務時結束碼是 2（整批暫停），不是 4。
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
        abstract: "檢查讀回的 JSON 並寫出剔除後的文字：先刪 --out、不論結果都刪 --raw；READ-OK＝0、READ-FAIL＝1、READ-REJECT＝4",
        discussion: """
        讀取前後 Safari 回報的主機（--before、--after）要相同；--landing 是落地主機檔時還要等於它，是 - 時主機要形狀合格。\
        讀回的 JSON 超過 6 × 上限 + 4096 bytes、欄位型別不對、rawLength 不在 0–1,000,000,000 之間都是 READ-FAIL。\
        通過才截到 --limit 個 UTF-16 單位、剔除不可見與控制字元（與 repo 輸出端同一份定義）、寫出。主機換到已知的驗證服務時結束碼是 2。
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
