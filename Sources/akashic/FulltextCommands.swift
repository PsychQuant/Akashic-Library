import ArgumentParser
import Foundation
import AkashicCore
import AkashicSkillTools
import AkashicMCPKit

/// `akashic-fetch-fulltext` skill 的決定論中間運算與抓取編排（#629 由 `scripts/*.py`、`fetch-fulltext.sh` 移植）。
///
/// 全部**不寫 store、不連網**：`fetch` 只在使用者自己的 Safari 裡導航、把 PDF 交給人（本身沒有 HTTP client，也不在頁內取檔，
/// `.claude/rules/web-access-via-safari-browser.md`、#613 的「跟真人一樣」），`take` 收人存下來的本機檔；其餘是「取得之後怎麼判斷」。
/// MCP 沒有對應面：輸入是本機檔案或使用者的瀏覽器，不是 store 狀態（`mcp-cli-parity` 的 CLI-only 表一列）。
struct FulltextCmd: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "fulltext",
        abstract: "取全文與依全文核對的中間運算：驗證下載檔、起疑訊號、抖動、導航到 PDF 並交給人、收人存的檔、標題規則校準、契約版本、逐頁文字（text）",
        subcommands: [FulltextVerifyCmd.self, FulltextBotSignalsCmd.self, FulltextJitterCmd.self,
                      FulltextFetchCmd.self, FulltextTakeCmd.self, FulltextCalibrateCmd.self, FulltextContractCmd.self,
                      FulltextTextCmd.self, FulltextCompareCmd.self])
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

/// 一筆 work 連著的全文 PDF 的**全部頁**文字（#742，`akashic-verify-work` skill 的第 1 步）。讀 store、不寫 store、不連網、不做 OCR。
/// MCP 沒有對應面：輸出是第三方全文、要落在 git 之外的檔（`mcp-cli-parity` 的 CLI-only 表一列，理由同 `references`：skill 的內部步驟）。
struct FulltextTextCmd: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "text",
        abstract: "一筆 work 連著的全文 PDF 的逐頁文字與有沒有文字層，寫成 JSON 到 --out（git 工作樹之外）；不寫 store、不做 OCR",
        discussion: """
        輸出：{"citekey", "source", "sourcePath", "pageCount", "hasTextLayer", "pages": [{"page", "hasLetters", "text"}]}。page 是 PDF 的\
        實體頁序（1 起算），不是印刷頁碼。hasLetters 是那一頁有沒有任何 Unicode 字母（只有數字、標點的頁不算）；hasTextLayer 是 false \
        恰在沒有任何一頁有字母時。akashic-verify-work 對需要讀、卻沒有字母的頁改走 bestOCR，本命令不做 OCR。sourcePath 是那份全文在 \
        本機 sources/ 的實體路徑。全文從 akashic.sources 裡 index 記為 application/pdf 的那一份取；連著不只一份時要 --source 指定。\
        --out 必須是還不存在的檔（不覆寫、不跟隨 symlink），以 0600 寫出。拒絕（結束碼 1、不寫檔）：--out 在 git 工作樹內或已經存在、\
        --source 沒連在這筆、這筆沒連任何 PDF、本機 sources/ 沒有那份存檔、pdftotext 切出的頁數與 pdfinfo 不符。需要 poppler（pdfinfo、pdftotext）。
        """)

    @OptionGroup var options: LibraryOptions

    @Option(name: .long, help: "work 的 citekey")
    var citekey: String

    @Option(name: .long, help: "要讀的那一份全文的 digest（這筆連著不只一份 PDF 時必填）")
    var source: String?

    @Option(name: .long, help: "輸出的 JSON 檔；必須在任何 git 工作樹之外（全文是第三方內容），而且還不存在")
    var out: String

    func run() throws {
        let store = try options.openStore()
        do {
            let target = try FulltextReconcile.checkOutput(out)
            let entries = try store.load().entries
            if entries.unlocatableCitekeys.contains(citekey) {
                throw SkillToolError.failure("work「\(displaySafeInvisible(citekey, max: 200))」無法唯一定位——先修好（#628／#641）")
            }
            guard let entry = entries.first(where: { $0.citekey == citekey }) else {
                throw SkillToolError.failure("找不到 citekey「\(displaySafeInvisible(citekey, max: 200))」")
            }
            let chosen = try FulltextReconcile.chooseSource(entry: entry, requested: source, store: store)
            let read = try PDFReader.readAllPages(path: chosen.url.path)
            let data = try FulltextReconcile.textJSON(citekey: entry.citekey, digest: chosen.digest, sourcePath: chosen.url.path,
                                                      pageCount: read.pageCount, pages: read.pages)
            try FulltextReconcile.write(data, to: target)
            FileHandle.standardError.write(Data("✓ \(read.pageCount) 頁 → \(displaySafeInvisible(target, max: 300))\n".utf8))   // display-safe-exempt: pageCount 是 Int
        } catch let e as SkillToolError {
            throw RuntimeFailure.state(displaySafeErrorText(e))
        }
    }
}

/// 把模型從全文讀出的提議與 store 現值逐欄比對（#742，`akashic-verify-work` 的第 3 步）。讀 store、不寫 store、不連網。
/// 提議裡的作者項、`release`、`groupMembers` 由**替換腿的同一個解碼器與規則**驗：這裡直接跑一次替換腿的乾跑，被拒的原因寫進 `refusal`
/// （結束碼仍 0）——會被拒的提議在乾跑階段就說出來，不另寫一份驗證器。**不論要不要替換都跑**（#742 verify：作者列相同、`release`
/// 卻指到 literal 位的提議，先前以 `refusal: null` 過關）。MCP 沒有對應面（CLI-only 表一列，理由同 `fulltext text`）。
struct FulltextCompareCmd: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "compare",
        abstract: "全文讀出的提議與 store 現值逐欄比對，輸出比對表與可直接交給 update-entry --replace-authors 的物件；不寫 store",
        discussion: """
        提議：{"source", "authors": {"page", "items", "reason"?}, "release"?, "groupMembers"?, "title"?, "volume"?, "issue"?, "pages"?, \
        "articleNumber"?, "date"?}；純量欄位是 {"value", "page"}。items、release、groupMembers 與 update-entry --replace-authors 同形。\
        reason 省略時填「PDF 第 N 頁 byline」。任何一層的未知鍵都拒絕（結束碼 1）。\
        輸出：{"citekey", "rows": [{"field", "store", "proposed", "page", "status"}], "replaceAuthors", "refusal", "applyRefusal"}，status 是 same、differs、\
        absentInStore、notProposed 之一，比較逐位元組；成員名單列的每組帶 restsOn（提議那一側是提議的 source）。作者列或成員名單不同時 \
        replaceAuthors 是替換腿的物件，否則 null；提議一律經替換腿乾跑驗一次（不論 replaceAuthors 是不是 null），會被拒時原因在 refusal、\
        結束碼 0。頁序對照提議 source 那份 PDF 的頁數，超出或讀不出頁數都寫進 refusal。乾跑接受、但 store 會拒絕寫入（例如 format 低於 23）時\
        原因在 applyRefusal；只有提議與 store 不同、給得出替換物件時才有 applyRefusal，與 store 一致的提議沒有東西要寫、三欄皆 null。\
        讀不出替換腿乾跑的報告時寫進 refusal。refusal 或 applyRefusal 不是 null 時 replaceAuthors 一律 null：被拒的提議沒有寫入命令。作者列與成員名單以外的欄位只列出，不產生寫入命令。\
        卷、期、頁碼、article number 對的是 fields 的 volume、number、pages、eid。--out 省略時印到 stdout；給了就必須在 git 工作樹之外、\
        而且還不存在（不覆寫、不跟隨 symlink），以 0600 寫出。
        """)

    @OptionGroup var options: LibraryOptions

    @Option(name: .long, help: "work 的 citekey")
    var citekey: String

    @Option(name: .long, help: "提議的 JSON 檔")
    var proposal: String

    @Option(name: .long, help: "輸出的 JSON 檔（省略印到 stdout）；必須在 git 工作樹之外，而且還不存在")
    var out: String?

    func run() throws {
        let store = try options.openStore()
        do {
            let target = try out.map { try FulltextReconcile.checkOutput($0) }
            let p: FulltextReconcile.Proposal
            do { p = try FulltextReconcile.decodeProposal(try Data(contentsOf: URL(fileURLWithPath: proposal))) } catch let e as SkillToolError {
                throw e
            } catch {
                throw SkillToolError.failure("讀不到 --proposal：\(displaySafeErrorText(error))")
            }
            let entries = try store.load().entries
            if entries.unlocatableCitekeys.contains(citekey) {
                throw SkillToolError.failure("work「\(displaySafeInvisible(citekey, max: 200))」無法唯一定位——先修好（#628／#641）")
            }
            guard let entry = entries.first(where: { $0.citekey == citekey }) else {
                throw SkillToolError.failure("找不到 citekey「\(displaySafeInvisible(citekey, max: 200))」")
            }
            let result = FulltextReconcile.compare(entry: entry, proposal: p)
            var refusal: Any = NSNull()
            // 替換腿的乾跑：同一個解碼器、同一套規則；乾跑不寫 store。不論要不要替換都跑
            let service = AkashicService(root: store.root, key: store.key, environment: ProcessInfo.processInfo.environment)
            var applyRefusal: Any = NSNull()
            do {
                let dry = try service.updateEntry(citekey: citekey, removeFields: nil,
                                                  replaceAuthors: try JSONSerialization.data(withJSONObject: result.validation),
                                                  dryRun: true, verdictsLimit: nil)
                // 乾跑接受提議、但 store 會拒絕寫入（format 不足、寫入前置的上限）時，替換腿只把原因放在 applyRefusal、不擲錯——
                // 另列出來，不給寫入命令（#742 verify 第四輪：先前只接 thrown error，這一類被丟掉）
                // 只在有東西要寫（給得出替換物件）時才採用：一致的提議沒有東西要寫，乾跑卻會因為要補一筆依據記錄而撞上 format 閘
                //（#742 verify 第五輪）。報告讀不出來時寫進 refusal，不當成沒有拒絕（同輪：try? 讓解析失敗變成放行）
                if result.replaceAuthors != nil {
                    if let obj = (try? JSONSerialization.jsonObject(with: Data(dry.utf8))) as? [String: Any] {
                        if let reason = obj["applyRefusal"] as? String, !reason.isEmpty {
                            applyRefusal = reason   // display-safe-exempt: reason 是替換腿已 displaySafeError 過的訊息
                        }
                    } else {
                        refusal = "讀不出替換腿乾跑的報告，無法確認寫不寫得進去"
                    }
                }
            } catch {
                refusal = displaySafeErrorText(error)
            }
            // 頁序上限：替換腿不讀 PDF，所以在這裡對照提議 source 那一份的頁數。source 本身不合（沒連在這筆、沒存、不是 PDF）時
            // 替換腿已經拒絕並說出原因，這裡不重報（#742 verify 第二輪）
            // 讀不出頁數（含 chooseSource 失敗）時寫進 refusal，不略過這道閘：替換腿本身不查頁序上限，這裡是唯一的一道
            //（#742 verify 第四輪：`try?` 吞掉錯誤時整道閘不跑、refusal 為 null）
            if refusal is NSNull {
                do {
                    let chosen = try FulltextReconcile.chooseSource(entry: entry, requested: p.source, store: store)
                    let count = try PDFReader.pageCount(path: chosen.url.path)
                    if let problem = FulltextReconcile.pageProblem(p, pageCount: count) { refusal = problem }
                } catch {
                    refusal = "讀不出提議 source 的頁數，無法核對提議的頁序：\(displaySafeErrorText(error))"
                }
            }
            // 被拒的提議不產生寫入命令：`refusal` 不是 null 時 `replaceAuthors` 一律 null（#742 verify 第三輪——頁序那一種原本只有這裡擋，
            // 取出 replaceAuthors 交給替換腿就過關）
            let replaceOut: Any = (refusal is NSNull && applyRefusal is NSNull) ? (result.replaceAuthors ?? NSNull()) : NSNull()
            let object: [String: Any] = ["citekey": entry.citekey, "rows": result.rows,   // display-safe-exempt: entry.citekey 受 StoreKey 約束；這份 JSON 是給 skill 讀的機器格式（值是作品與 store 的原文）
                                         "replaceAuthors": replaceOut, "refusal": refusal, "applyRefusal": applyRefusal]
            let data = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys, .prettyPrinted, .withoutEscapingSlashes])
            if let target {
                try FulltextReconcile.write(data, to: target)
            } else {
                FileHandle.standardOutput.write(data)   // display-safe-exempt: 未消毒——給 skill 讀的機器格式，值是作品與 store 的原文
                FileHandle.standardOutput.write(Data("\n".utf8))
            }
        } catch let e as SkillToolError {
            throw RuntimeFailure.state(displaySafeErrorText(e))
        }
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
