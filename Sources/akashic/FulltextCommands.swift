import ArgumentParser
import Foundation
import AkashicCore
import AkashicSkillTools

/// `akashic-fetch-fulltext` skill 的決定論中間運算與抓取編排（#629 由 `scripts/*.py`、`fetch-fulltext.sh` 移植）。
///
/// 全部**不寫 store、不連網**：`fetch` 只在使用者自己的 Safari 裡導航、把 PDF 交給人（本身沒有 HTTP client，也不在頁內取檔，
/// `.claude/rules/web-access-via-safari-browser.md`、#613 的「跟真人一樣」），`take` 收人存下來的本機檔；其餘是「取得之後怎麼判斷」。
/// MCP 沒有對應面：輸入是本機檔案或使用者的瀏覽器，不是 store 狀態（`mcp-cli-parity` 的 CLI-only 表一列）。
struct FulltextCmd: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "fulltext",
        abstract: "取全文 skill 的中間運算：驗證下載檔、起疑訊號、抖動、導航到 PDF 並交給人、收人存的檔、標題規則校準、契約版本",
        subcommands: [FulltextVerifyCmd.self, FulltextBotSignalsCmd.self, FulltextJitterCmd.self,
                      FulltextFetchCmd.self, FulltextTakeCmd.self, FulltextCalibrateCmd.self, FulltextContractCmd.self])
}

/// `fetch`／`take` 對 skill 的契約版本（`FulltextFetch.contractVersion`）。SKILL.md 第 0 步用它分辨比這份 SKILL 舊的 CLI（#613 R3，b31 W4 第 1 則：
/// 先前以 `take` 的行為探測，R1、R2 的 CLI 兩條都過）。唯讀：不碰瀏覽器、不連網、不讀不寫任何檔。
struct FulltextContractCmd: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "contract",
        abstract: "印 fetch／take 對 skill 的契約版本（fulltext-contract <N>）；唯讀，不碰瀏覽器、不連網、不寫任何檔",
        discussion: """
        SKILL.md 第 0 步要求至少某個版本；比它舊的 CLI（含沒有這個子命令的，ArgumentParser 回 64）一律當成要先更新。\
        結束碼、交給人的原因、或哪些頁面整批暫停改變時版本往上調。
        """)

    func run() throws {
        print("fulltext-contract \(FulltextFetch.contractVersion)")
    }
}

/// 下載下來的檔案是不是記錄所描述的那篇正式論文？印一個 JSON 物件；判定為「是這篇」時結束碼 0，否則（含讀不到）1。
/// `flags` 帶 `author-manuscript` 之類不單獨讓判定失敗：檔案仍可能是對的作品，但它不是正式版，呼叫端必須照實說，不能默默存成正式版。
struct FulltextVerifyCmd: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "verify",
        abstract: "比對 PDF 與記錄（標題、頁數、DOI），判定是不是那篇的正式版；印 JSON，是＝0、不是＝1")

    @Argument(help: "要驗證的 PDF 檔")
    var pdf: String

    // `.unconditional`：標題可以以連字號開頭（`-Omics of things`、`-1 to 1`）；預設的 `.next` 策略把它當成另一個旗標而拒收
    // （舊 shell 的 `TITLE=$2` 什麼值都收，R1 verify 第 24／57 則）。代價：`--title --pages` 會把 `--pages` 當標題——那是使用者給的值。
    @Option(name: .long, parsing: .unconditional, help: "記錄的標題（必填）")
    var title: String

    @Option(name: .long, parsing: .unconditional, help: "記錄的頁碼範圍，如 71--98（選填；有才比頁數）")
    var pages: String?

    @Option(name: .long, parsing: .unconditional, help: "記錄的 DOI（選填；沒有就沒有 DOI 可比，永不自動收）")
    var doi: String?

    func run() throws {
        let (json, ok) = FulltextTake.verdictJSON(path: pdf, title: title, pages: pages, doi: doi ?? "")
        print(json)   // display-safe-exempt: json：判定物件由 `Assessment.json` 組成，DOI 欄位已過 displaySafeInvisible，其餘是數字、布林與固定標籤；錯誤文字已過 displaySafeErrorText
        if !ok { throw ExitCode(1) }
    }
}

/// 網站是不是開始懷疑是自動化？從 stdin 讀頁面或回應文字；命中時印訊號標籤、結束碼 0，沒命中不印、結束碼 1。
/// 樣式只是**下限**：沒命中不代表乾淨。`--kind` 另印處置（#613）：`verify`＝等人驗證、`pause`＝整批暫停。
/// **命中的結束碼一律是 0**（不因處置不同而變）：舊的呼叫端以「0＝有訊號、停」寫成，改碼會讓它把等人驗證讀成「沒有訊號」。
struct FulltextBotSignalsCmd: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "bot-signals",
        abstract: "從 stdin 讀頁面文字，比對網站起疑的訊號（中止條款的下限）；命中＝印標籤、0，沒命中＝1")

    @Option(name: .long, help: "HTTP 狀態碼；403、429 本身就是起疑")
    var status: Int?

    @Flag(name: .long, help: "標籤後面以 tab 分隔再印處置：verify（等人驗證）或 pause（整批暫停）")
    var kind = false

    func run() throws {
        let text = String(decoding: FileHandle.standardInput.readDataToEndOfFile(), as: UTF8.self)
        if let hit = BotSignals.classify(text, status: status) {
            print(kind ? "\(hit.label)\t\(hit.response.rawValue)" : hit.label)
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

/// 在使用者自己的 Safari 裡從 DOI 走到頁面自己的 PDF 連結，交給人（#613）。**不取位元組、不寫任何輸出檔**；結束碼是它對 agent 的契約
/// （見 `FulltextFetch`）。**鎖分頁的方式沒有改**（`--window` 加分頁位置；規則檔〈例外〉第二種形狀）。
struct FulltextFetchCmd: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "fetch",
        abstract: "在使用者自己的 Safari 裡導航到頁面自己的 PDF 連結、交給人存檔；不取位元組、不寫檔；結束碼 6＝整批暫停",
        discussion: """
        只用瀏覽器導航（不在頁內取檔、不拼出版商網址）。結束碼：7 交給人，批次繼續（PDF 已顯示——含在別的主機上顯示、頁面的下載按鈕要人按、\
        分頁到了別的主機、頁面載完而沒有命中驗證／封鎖／登入的封閉清單（不代表不是登入頁）、讀不到的分頁（可能是 Safari 的 PDF 檢視器，什麼都沒檢查過；文章站上與別的主機上同一套）、DOI 解不開（doi.org 自己的查無頁）；原因在 stdout 的 `handover:` 一行；人存檔之後用 `fulltext take`）；\
        8 等人驗證（CAPTCHA 等，只在文章站本身或已知的驗證服務上成立；使用者驗證完加 stdout `resume:` 一行印出的 \
        --resume-tab／--resume-origin（導航之後的驗證另有 --resume-stage followed）在同一個分頁接著走）；\
        9 這個站今天（Asia/Taipei）已經 10 次嘗試，停這個站；6 整批暫停：其他起疑訊號（含其他主機上的驗證字樣、HTTP 403／429、登入頁、登入頁長相的 DOI 落地頁、讀不到而停在登入主機上的分頁、停在 doi.org 卻沒有查無證據、頁面約 60 秒沒載完），\
        分頁留著給使用者看；3 頁面上找不到 PDF 連結；1 自動化失敗（看 stderr）。沒有結束碼 0。命令列本身打錯是 64。\
        每次準備導航到 PDF 就在帳本（預設 $HOME/Library/Application Support/akashic/fulltext-attempts.jsonl，在 store 之外）記一次；\
        查數與記錄是一步（跨行程的鎖）。--ledger 只給測試：換帳本等於重算上限，不要為了繞過每站 10 次而用它。
        """)

    @Option(name: .long, help: "Safari 視窗編號（從 1 起）")
    var window: Int

    @Option(name: .long, help: "落地頁網址（一律是 https://doi.org/<DOI>，見 SKILL.md 第 2 步）")
    var landing: String

    @Option(name: .customLong("expect-profile"), help: "這個視窗必須屬於的 Safari profile（使用者自己的；必填）；不符就在開任何分頁之前拒絕")
    var expectProfile: String

    @Option(name: .long, help: "每日嘗試帳本的路徑（只給測試；預設 $HOME/Library/Application Support/akashic/fulltext-attempts.jsonl）")
    var ledger: String?

    @Option(name: .customLong("resume-tab"), help: "等人驗證（結束碼 8）之後在同一個分頁接著走：那個分頁在 --window 裡的位置")
    var resumeTab: Int?

    @Option(name: .customLong("resume-origin"), help: "與 --resume-tab 一起給：文章站的 https://<主機>（結束碼 8 印出的值）；article 階段分頁此刻必須顯示它")
    var resumeOrigin: String?

    @Option(name: .customLong("resume-stage"), help: "與 --resume-tab 一起給：驗證發生在哪一步，article（導航到 PDF 連結之前，預設）或 followed（之後；結束碼 8 有印就照抄；那個分頁要顯示文章站、已知驗證服務或 PDF，否則拒絕）")
    var resumeStage: String = "article"

    @Option(name: .long, help: "safari-browser 的路徑")
    var bin: String = "safari-browser"

    func validate() throws {
        guard window >= 1 else { throw ValidationError("--window 必須是 1 以上的整數") }
        // 視窗屬於誰是唯一防止「動到別人的 Safari session」的檢查：文件一直寫「一律帶」，程式現在也強制（R1 verify 第 31 則）
        guard !expectProfile.isEmpty else { throw ValidationError("--expect-profile 不可為空：它是唯一防止動到別人的 Safari session 的檢查") }
        guard (resumeTab == nil) == (resumeOrigin == nil) else { throw ValidationError("--resume-tab 與 --resume-origin 要一起給") }
        if let t = resumeTab, t < 1 { throw ValidationError("--resume-tab 必須是 1 以上的整數") }
        guard FulltextFetch.ResumeStage(rawValue: resumeStage) != nil else { throw ValidationError("--resume-stage 只能是 article 或 followed") }
        if resumeTab == nil, resumeStage != "article" { throw ValidationError("--resume-stage 要和 --resume-tab 一起給") }
        if let origin = resumeOrigin, let problem = FulltextFetch.resumeOriginProblem(origin) {
            throw ValidationError("--resume-origin 必須恰好是 https://<主機>（\(displaySafeInvisible(problem, max: 200))）")
        }
    }

    func run() throws {
        guard ProcessSafariBrowser.isAvailable(bin) else {
            FileHandle.standardError.write(Data("✗ safari-browser not found: \(displaySafeInvisible(bin, max: 300))\n".utf8))
            throw ExitCode(1)
        }
        if let ledger, ledger != FulltextAttemptLedger.defaultPath() {
            FileHandle.standardError.write(Data("⚠ using a ledger other than the default (\(displaySafeInvisible(ledger, max: 300))): --ledger is for tests — a different ledger recounts the per-site daily cap from zero\n".utf8))
        }
        let runner = FulltextFetch(
            browser: ProcessSafariBrowser(executable: bin),
            out: { line in print(line); fflush(stdout) },
            err: { line in FileHandle.standardError.write(Data((line + "\n").utf8)) })
        let code = runner.run(.init(window: window, landing: landing, ledger: ledger ?? FulltextAttemptLedger.defaultPath(),
                                    expectProfile: expectProfile, resumeTab: resumeTab, resumeOrigin: resumeOrigin,
                                    resumeStage: FulltextFetch.ResumeStage(rawValue: resumeStage) ?? .article))
        throw ExitCode(code)
    }
}

/// 把人存下來的全文檔（本機檔）驗證後存到 `--out`（#613）。不碰瀏覽器、不連網、不寫 store；`--from` 只讀不動。
struct FulltextTakeCmd: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "take",
        abstract: "收人存下來的全文檔：驗證、git 閘、存到 --out；不碰瀏覽器、不連網、不寫 store",
        discussion: """
        結束碼：0 存好了，而且驗證是這篇；2 --from 不是 PDF，什麼都沒寫；\
        5 是 PDF 但驗證不是這篇（存成 FILE.unverified.pdf）；1 其他失敗（--from 不是普通檔或太大、輸出目的地不合、git 閘拒絕、\
        驗證本身跑不起來——截斷的下載或缺 poppler，什麼都沒寫）。命令列本身打錯是 64，含沒給 --title 或 --title 是空的\
        （沒有標題就沒有驗證，不能讓「沒驗證」長得像「驗證過」）。--from 只讀，不移動、不刪除。
        """)

    @Option(name: .long, help: "人存下來的 PDF（本機的普通檔；只讀）")
    var from: String

    @Option(name: .long, help: "輸出的 PDF 路徑；必須在 git 工作樹之外，或被該樹 ignore（全文是第三方內容）")
    var out: String

    // `.unconditional`：標題可以以連字號開頭（見 FulltextVerifyCmd）
    @Option(name: .long, parsing: .unconditional, help: "記錄的標題（驗證用，必填、不得是空的）；可以以連字號開頭")
    var title: String

    @Option(name: .long, parsing: .unconditional, help: "記錄的頁碼範圍（驗證用），如 71--98")
    var pages: String?

    @Option(name: .long, parsing: .unconditional, help: "記錄的 DOI（驗證用；沒有就沒有 DOI 可比，永不自動收）")
    var doi: String?

    func validate() throws {
        guard !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ValidationError("--title 不得是空的：沒有記錄標題就沒有驗證（標題檔是空的？記錄沒有標題的作品不走 take）")
        }
    }

    func run() throws {
        let taker = FulltextTake(
            out: { line in print(line); fflush(stdout) },
            err: { line in FileHandle.standardError.write(Data((line + "\n").utf8)) })
        let code = taker.run(.init(from: from, out: out, title: title, pages: pages, doi: doi))
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
        會逐個列出（DOI 與完整網址）並以結束碼 3 結束，由 skill 經 safari-browser 取回、存進那個目錄後重跑；\
        首頁讀出的 DOI 形狀不合格的（含引號、`$`、`#`、`?`、`%`、`..` 等）不列網址、不取，同樣算「沒量到」。\
        數字只涵蓋有記錄的檔案時不宣稱是全部（--partial 才照量）。\
        結束碼：0 量完且沒有別篇標題被收；1 有「別篇標題被收」；3 缺記錄（沒有 --partial）；4 一個檔案都沒量到\
        （資料夾裡沒有首頁帶 DOI 的 PDF，或它們的記錄都沒有）——全零的數字不是校準結果。資料夾不存在或 --crossref 不是目錄是一般失敗（1）。
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
        if !loaded.missing.isEmpty || !loaded.unsafeDOIs.isEmpty {
            if !loaded.missing.isEmpty {
                print("缺 \(loaded.missing.count) 個 DOI 的 Crossref 回應（經 safari-browser 取下面的網址，存進 --crossref 目錄後重跑）：")
                for doi in loaded.missing {
                    print("  \(displaySafeInvisible(doi, max: 200))\t\(displaySafeInvisible(TitleCalibration.crossrefURL(forDOI: doi) ?? "", max: 400))")
                }
            }
            if !loaded.unsafeDOIs.isEmpty {
                print("另有 \(loaded.unsafeDOIs.count) 個 DOI 形狀不合格（含引號、`$`、`#`、`?`、`%` 或 `..` 路徑段），不列網址、不取，那些檔量不到：")
                for doi in loaded.unsafeDOIs { print("  \(displaySafeInvisible(doi, max: 200))") }
            }
            if !partial { throw ExitCode(3) }
            print("--partial：以下數字只涵蓋有 Crossref 記錄的 \(loaded.rows.count) 個檔案")
        }
        let report = TitleCalibration.evaluate(rows: loaded.rows)
        for line in report.lines { print(line) }   // display-safe-exempt: line：整行由 evaluate 組成，檔名與標題逐項過 displaySafeInvisible，其餘是計數
        if loaded.rows.isEmpty {
            FileHandle.standardError.write(Data("✗ 沒有量到任何檔案：資料夾裡沒有「首頁帶 DOI、而且 --crossref 目錄有那個 DOI 的記錄」的 PDF。上面的 0／0 不是校準結果。\n".utf8))
            throw ExitCode(4)
        }
        if report.wrongAccepts > 0 { throw ExitCode(1) }
    }
}
