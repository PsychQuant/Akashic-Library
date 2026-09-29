import ArgumentParser
import Foundation
import AkashicCore
import AkashicSkillTools

/// `akashic-fetch-fulltext` skill 的決定論中間運算與抓取編排（#629 由 `scripts/*.py`、`fetch-fulltext.sh` 移植）。
///
/// 全部**不寫 store、不連網**：PDF 由 skill 經使用者自己的 Safari 取得（`fetch` 替 safari-browser 編排，本身沒有 HTTP client，
/// `.claude/rules/web-access-via-safari-browser.md`），這裡只做「取得之後怎麼判斷」與「取得的步驟怎麼排」。MCP 沒有對應面：
/// 輸入是本機檔案或使用者的瀏覽器，不是 store 狀態（`mcp-cli-parity` 的 CLI-only 表一列）。
struct FulltextCmd: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "fulltext",
        abstract: "取全文 skill 的中間運算：驗證下載檔、出版商網址規則、起疑訊號、抖動、抓取編排、標題規則校準",
        subcommands: [FulltextVerifyCmd.self, FulltextURLRuleCmd.self, FulltextBotSignalsCmd.self, FulltextJitterCmd.self,
                      FulltextFetchCmd.self, FulltextCalibrateCmd.self])
}

/// 下載下來的檔案是不是記錄所描述的那篇正式論文？印一個 JSON 物件；判定為「是這篇」時結束碼 0，否則（含讀不到）1。
/// `flags` 帶 `author-manuscript` 之類不單獨讓判定失敗：檔案仍可能是對的作品，但它不是正式版，呼叫端必須照實說，不能默默存成正式版。
struct FulltextVerifyCmd: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "verify",
        abstract: "比對 PDF 與記錄（標題、頁數、DOI），判定是不是那篇的正式版；印 JSON，是＝0、不是＝1")

    @Argument(help: "要驗證的 PDF 檔")
    var pdf: String

    @Option(name: .long, help: "記錄的標題（必填）")
    var title: String

    @Option(name: .long, help: "記錄的頁碼範圍，如 71--98（選填；有才比頁數）")
    var pages: String?

    @Option(name: .long, help: "記錄的 DOI（選填；沒有就沒有 DOI 可比，永不自動收）")
    var doi: String?

    func run() throws {
        let (json, ok) = FulltextFetch.verdictJSON(path: pdf, title: title, pages: pages, doi: doi ?? "")
        print(json)   // display-safe-exempt: json：判定物件由 `Assessment.json` 組成，DOI 欄位已過 displaySafeInvisible，其餘是數字、布林與固定標籤；錯誤文字已過 displaySafeErrorText
        if !ok { throw ExitCode(1) }
    }
}

/// 從落地頁最後停在的網址，推出出版商 PDF 的網址；沒有規則適用時什麼都不印（呼叫端改用頁面自己的連結）。
struct FulltextURLRuleCmd: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "url-rule",
        abstract: "從落地頁網址推出出版商的 PDF 網址（SAGE、Wiley、PsycNet）；沒有規則適用時不印")

    @Argument(help: "落地頁最後停在的網址")
    var finalURL: String

    @Argument(help: "頁面自己的 PDF 連結（PsycNet 停在 doiLanding 時 id 從這裡取）")
    var pageLink: String?

    func run() throws {
        if let url = PdfUrlRules.pdfURL(finalURL: finalURL, pageLink: pageLink) {
            print(displaySafeInvisible(url, max: 1_000))
        }
    }
}

/// 網站是不是開始懷疑是自動化？從 stdin 讀頁面或回應文字；命中時印訊號標籤、結束碼 0，沒命中不印、結束碼 1。
/// 樣式只是**下限**：沒命中不代表乾淨。
struct FulltextBotSignalsCmd: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "bot-signals",
        abstract: "從 stdin 讀頁面文字，比對網站起疑的訊號（中止條款的下限）；命中＝印標籤、0，沒命中＝1")

    @Option(name: .long, help: "HTTP 狀態碼；403、429 本身就是起疑")
    var status: Int?

    func run() throws {
        let text = String(decoding: FileHandle.standardInput.readDataToEndOfFile(), as: UTF8.self)
        if let hit = BotSignals.detect(text, status: status) {
            print(hit)
        } else {
            throw ExitCode(1)
        }
    }
}

/// 請求之間的間隔：雙截斷柯西分布，區間 [2, 60] 秒、截斷後中位數 3 秒。印出這次的秒數再睡；`--dry-run` 只印不睡。
/// 只在安裝的 safari-browser 沒有 `wait --jitter cauchy` 時用（PsychQuant/safari-browser#182）。
struct FulltextJitterCmd: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "jitter",
        abstract: "睡一個雙截斷柯西分布的間隔（秒，印在 stdout）；safari-browser 沒有 wait --jitter 時用")

    @Option(name: .long, help: "下界（秒）") var min: Double = 2
    @Option(name: .long, help: "上界（秒）") var max: Double = 60
    @Option(name: .long, help: "截斷後的中位數（秒）") var median: Double = 3
    @Option(name: .long, help: "尺度（秒）") var scale: Double = 0.8
    @Flag(name: .customLong("dry-run"), help: "只印出間隔，不睡") var dryRun = false

    func validate() throws {
        let params = CauchyJitter.Parameters(min: min, max: max, median: median, scale: scale)
        if case .failure(let e) = CauchyJitter.calibrate(params) { throw ValidationError(displaySafeInvisible(e.message, max: 300)) }
    }

    func run() throws {
        let params = CauchyJitter.Parameters(min: min, max: max, median: median, scale: scale)
        guard case .success(let calibrated) = CauchyJitter.calibrate(params) else { return }   // validate() 已擋
        let x = CauchyJitter.draw(params, calibrated)
        print(String(format: "%.2f", x))
        if !dryRun { Thread.sleep(forTimeInterval: x) }
    }
}

/// 透過使用者自己的 Safari session 取一篇 work 的全文 PDF，驗證後存檔；結束碼是它對 agent 的契約（見 `FulltextFetch`）。
/// **鎖分頁的方式沒有改**（`--window` 加分頁位置，#613 的作法；規則檔〈例外〉第二種形狀）。
struct FulltextFetchCmd: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "fetch",
        abstract: "經使用者自己的 Safari 取一篇的全文 PDF、驗證、存檔；結束碼 6＝整批停止（中止條款）",
        discussion: """
        結束碼：0 取得且（有 --title 時）驗證通過；1 自動化失敗（看 stderr）；2 回應不是 PDF（本文存成 FILE.response.txt）；\
        3 頁面上找不到 PDF 連結；4 無權限（網站給了登入殼）；5 是 PDF 但驗證不是這篇（存成 FILE.unverified.pdf）；\
        6 整批停止：網站出現懷疑是自動化的跡象，分頁留著給使用者看。命令列本身打錯是 64。
        """)

    @Option(name: .long, help: "Safari 視窗編號（從 1 起）")
    var window: Int

    @Option(name: .long, help: "落地頁網址（一律是 https://doi.org/<DOI>，見 SKILL.md 第 2 步）")
    var landing: String

    @Option(name: .long, help: "輸出的 PDF 路徑；必須在 git 工作樹之外，或被該樹 ignore（全文是第三方內容）")
    var out: String

    @Option(name: .customLong("expect-profile"), help: "這個視窗必須屬於的 Safari profile（使用者自己的）；不符就在開任何分頁之前拒絕")
    var expectProfile: String?

    @Option(name: .long, help: "記錄的標題（驗證用；不給就不驗證）")
    var title: String?

    @Option(name: .long, help: "記錄的頁碼範圍（驗證用），如 71--98")
    var pages: String?

    @Option(name: .long, help: "記錄的 DOI（驗證用）；--landing 是 doi.org 網址時自動取")
    var doi: String?

    @Option(name: .long, help: "先在自己的分頁開這個網址、像讀者點 PDF 連結那樣，再關掉（PMC 用）")
    var prime: String?

    @Option(name: .long, help: "safari-browser 的路徑")
    var bin: String = "safari-browser"

    func validate() throws {
        guard window >= 1 else { throw ValidationError("--window 必須是 1 以上的整數") }
    }

    func run() throws {
        guard ProcessSafariBrowser.isAvailable(bin) else {
            FileHandle.standardError.write(Data("✗ safari-browser not found: \(displaySafeInvisible(bin, max: 300))\n".utf8))
            throw ExitCode(1)
        }
        let runner = FulltextFetch(
            browser: ProcessSafariBrowser(executable: bin),
            out: { line in print(line); fflush(stdout) },
            err: { line in FileHandle.standardError.write(Data((line + "\n").utf8)) })
        let code = runner.run(.init(window: window, landing: landing, out: out, title: title, pages: pages, doi: doi,
                                    prime: prime, expectProfile: expectProfile))
        if code != 0 { throw ExitCode(code) }
    }
}

/// 在一個資料夾的真實 PDF 上量標題規則（自己 22/28、別篇 0/808 那組數字）。Crossref 記錄從本機目錄讀，**不連網**。
struct FulltextCalibrateCmd: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "calibrate",
        abstract: "在一個資料夾的 PDF 上量驗證規則（自己的標題／主標題被收幾份、別篇標題被收幾份）；Crossref 記錄讀本機目錄",
        discussion: """
        --crossref 目錄裡每個檔是 https://api.crossref.org/works/<DOI> 的回應（{"message": {…}}），檔名不重要。缺哪些 DOI 的回應，\
        會列出來（含要取的網址）並以結束碼 3 結束，由 skill 經 safari-browser 取回、存進那個目錄後重跑；\
        數字只涵蓋有記錄的檔案時不宣稱是全部（--partial 才照量）。有任何「別篇標題被收」時結束碼 1。
        """)

    @Argument(help: "放 PDF 的資料夾（遞迴）")
    var folder: String

    @Option(name: .long, help: "Crossref 回應檔所在的目錄")
    var crossref: String

    @Flag(name: .long, help: "有缺記錄的 DOI 時仍量現有的（數字只涵蓋有記錄的檔案）")
    var partial = false

    func run() throws {
        let loaded: TitleCalibration.Loaded
        do { loaded = try TitleCalibration.load(folder: folder, crossrefDirectory: crossref) } catch {
            throw RuntimeFailure.state(displaySafeErrorText(error))
        }
        if loaded.unusableResponses > 0 {
            FileHandle.standardError.write(Data("⚠ --crossref 目錄裡有 \(loaded.unusableResponses) 個檔讀不了或不是 Crossref 回應（沒有 message.DOI），已略過\n".utf8))
        }
        if loaded.withoutDOI > 0 {
            FileHandle.standardError.write(Data("首頁沒有 DOI 而略過的 PDF：\(loaded.withoutDOI) 個\n".utf8))
        }
        if !loaded.missing.isEmpty {
            print("缺 \(loaded.missing.count) 個 DOI 的 Crossref 回應（經 safari-browser 取 https://api.crossref.org/works/<DOI>，存進 --crossref 目錄後重跑）：")
            for doi in loaded.missing { print("  \(displaySafeInvisible(doi, max: 200))") }
            if !partial { throw ExitCode(3) }
            print("--partial：以下數字只涵蓋有 Crossref 記錄的 \(loaded.rows.count) 個檔案")
        }
        let report = TitleCalibration.evaluate(rows: loaded.rows)
        for line in report.lines { print(line) }   // display-safe-exempt: line：整行由 evaluate 組成，檔名與標題逐項過 displaySafeInvisible，其餘是計數
        if report.wrongAccepts > 0 { throw ExitCode(1) }
    }
}
