import AkashicCore
import AkashicS2
import ArgumentParser
import Foundation

/// #664：Semantic Scholar 共用接口的 CLI 面。與 MCP 的 `akashic_s2` 共用 `AkashicS2`，
/// 不經 `AkashicService`、不開 store。結束碼：3 金鑰不可用、4 限流用盡、5 S2 或網路錯誤；
/// 依 #549 的判準，只看 argv 判得出的錯誤在 `validate()` 回 64，要讀 argv 以外（環境變數、
/// 輸入檔、節流狀態檔）才判得出的回 1（`RuntimeFailure`）。
struct S2Cmd: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "s2",
        abstract: "查詢 Semantic Scholar（金鑰從 keychain 讀取；全機每秒至多 1 個請求）",
        discussion: """
        金鑰存在 keychain：service「semantic-scholar」、account「default」。設定方法見 \(S2Settings.setupDocument)；只裝 plugin 的話見 \(S2Settings.setupDocumentInPlugin)。
        結束碼：0 成功、1 環境覆寫或輸入檔有誤、3 金鑰不可用、4 限流用盡、5 S2 或網路錯誤、64 參數錯誤。
        """,
        subcommands: [S2PaperCmd.self, S2MatchCmd.self, S2BatchCmd.self, S2ReferencesCmd.self,
                      S2CitationsCmd.self, S2RecommendCmd.self, S2AuthorSearchCmd.self,
                      S2AuthorPapersCmd.self, S2StatusCmd.self])
}

struct S2Options: ParsableArguments {
    @Flag(name: .long, help: "輸出 JSON（source、endpoint、request、fetchedAt、total、data）")
    var json = false

    @Option(name: .long, help: "逗號分隔的 S2 欄位名，照原樣轉給 S2；省略時論文類預設 title,year,authors、作者類預設 name,paperCount")
    var fields: String?

    func fieldList(default fallback: [String]) -> [String] {
        guard let fields else { return fallback }
        return fields.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    }
}

struct S2PageOptions: ParsableArguments {
    @Option(name: .long, help: "至多取幾筆（省略＝全部）")
    var limit: Int?

    @Option(name: .long, help: "從第幾筆開始（0 起算）")
    var offset: Int = 0

    /// 只看 argv 的檢查（#549）。
    func validate() throws {
        if let limit, limit < 1 {
            throw ValidationError(displaySafeErrorText(S2ArgumentError.limitOutOfRange(endpoint: "s2", limit: limit, min: 1, max: nil)))
        }
        if offset < 0 { throw ValidationError(displaySafeErrorText(S2ArgumentError.negativeOffset(offset))) }
    }
}

enum S2CLI {
    static let paperFields = S2Endpoints.defaultPaperFields
    static let authorFields = S2Endpoints.defaultAuthorFields

    /// 解析設定 → 組 client → 跑查詢 → 清理 → 印出。錯誤依類型對應結束碼。
    static func run(_ options: S2Options,
                    _ op: @escaping @Sendable (S2Endpoints) async throws -> S2Result) throws {
        let settings = try resolveSettings()
        let client = S2Client(settings: settings,
                              keyProvider: S2KeychainKeyProvider(settings: settings),
                              throttle: S2FileThrottle(stateDirectory: settings.stateDirectory))
        let endpoints = S2Endpoints(client: client)
        let result: S2Result
        do {
            result = try runBlocking { try await op(endpoints) }
        } catch let e as S2Error {
            try fail(e, code: exitCode(for: e))
        } catch let e as S2ArgumentError {
            // 走到這裡的是要讀輸入檔才判得出的（batch 的筆數）；argv 的檢查在 validate()。
            throw RuntimeFailure.state(displaySafeErrorText(e))
        } catch let e as S2ThrottleError {
            throw RuntimeFailure.state(displaySafeErrorText(e))
        }
        // JSON 面無損（`cliJSON` 自己清理）；人可讀的面是終端機，走 `sanitized`。
        print(options.json ? S2Output.cliJSON(result, fetchedAt: Date()) : S2Output.humanReadable(S2Output.sanitized(result)))
    }

    /// 環境變數不是 argv（#549）：覆寫被拒回 1，不是 64。
    static func resolveSettings() throws -> S2Settings {
        do { return try S2Settings.resolve() } catch let e as S2SettingsError {
            throw RuntimeFailure.state(displaySafeErrorText(e))
        }
    }

    /// 識別碼的 argv 檢查（空值、`.`／`..` 路徑片段）——與 `S2Endpoints` 送出前的是同一個函式。
    static func checkIdentifier(_ raw: String, endpoint: String) throws {
        do { _ = try S2Endpoints.segment(S2Endpoints.normalizePaperID(raw), endpoint: endpoint) } catch let e as S2ArgumentError {
            throw ValidationError(displaySafeErrorText(e))
        }
    }

    static func exitCode(for error: S2Error) -> Int32 {
        switch error {
        case .keyUnavailable: return 3
        case .rateLimited: return 4
        case .notFound, .http, .network, .invalidResponse, .invalidRequest, .unsafeSession: return 5
        }
    }

    /// 與 MCP 的錯誤出口同一個函式（`displaySafeErrorMultiline(_:prefix: "Error: ")`），兩面逐字相同。
    /// 印到 stderr 後以指定的碼結束；`main()` 對 `ExitCode` 不再印字。
    static func fail(_ error: S2Error, code: Int32) throws -> Never {
        let text = displaySafeErrorMultiline(error, prefix: "Error: ")
        try? FileHandle.standardError.write(contentsOf: Data((text + "\n").utf8))
        throw ExitCode(code)
    }

    /// 同步的 `run()` 裡跑 async 查詢。根命令刻意維持同步（見 `AkashicCLI.main()` 的註解），
    /// 所以在這裡橋接；查詢跑在 detached task 上，不依賴主執行緒。
    static func runBlocking<T: Sendable>(_ op: @escaping @Sendable () async throws -> T) throws -> T {
        let done = DispatchSemaphore(value: 0)
        let box = ResultBox<T>()
        Task.detached {
            do { box.set(.success(try await op())) } catch { box.set(.failure(error)) }
            done.signal()
        }
        done.wait()
        return try box.get()
    }

    final class ResultBox<T: Sendable>: @unchecked Sendable {
        private let lock = NSLock()
        private var result: Result<T, Error>?
        func set(_ r: Result<T, Error>) { lock.lock(); result = r; lock.unlock() }
        func get() throws -> T {
            lock.lock(); defer { lock.unlock() }
            guard let result else { throw ExitCode.failure }
            return try result.get()
        }
    }
}

struct S2PaperCmd: ParsableCommand {
    static let configuration = CommandConfiguration(commandName: "paper", abstract: "查一篇論文（DOI:…、CorpusId:…、S2 paperId；以 10. 開頭的裸 DOI 自動加 DOI:）")
    @Argument(help: "論文識別碼") var paperID: String
    @OptionGroup var options: S2Options
    func validate() throws {
        try S2CLI.checkIdentifier(paperID, endpoint: "paper")
    }
    func run() throws {
        let id = paperID, fields = options.fieldList(default: S2CLI.paperFields)
        try S2CLI.run(options) { try await $0.paper(id: id, fields: fields) }
    }
}

struct S2MatchCmd: ParsableCommand {
    static let configuration = CommandConfiguration(commandName: "match", abstract: "以標題比對一篇論文")
    @Option(name: .long, help: "論文標題") var title: String
    @Option(name: .long, help: "出版年（可省略）") var year: String?
    @OptionGroup var options: S2Options
    /// 只看 argv（#549）：空白標題在這裡回 64，不是等到查詢時才失敗。
    func validate() throws {
        if title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            throw ValidationError(displaySafeErrorText(S2ArgumentError.emptyIdentifier(endpoint: "match")))
        }
    }
    func run() throws {
        let t = title, y = year, fields = options.fieldList(default: S2CLI.paperFields)
        try S2CLI.run(options) { try await $0.match(title: t, year: y, fields: fields) }
    }
}

struct S2BatchCmd: ParsableCommand {
    static let configuration = CommandConfiguration(commandName: "batch", abstract: "批次查詢（檔案一行一個 id，至多 500 個）")
    @Option(name: .long, help: "id 清單檔") var idsFile: String
    @OptionGroup var options: S2Options
    static let maxIdsFileBytes = 256 * 1024
    func run() throws {
        // 上限量的是**讀進來的位元組**：至多 500 個 id、每個至多 512 字元，遠小於 256 KiB；超過的不是 id 清單，
        // 不整份讀進來、也不 POST 給第三方。不量檔案屬性——裝置檔與 FIFO 的大小是 0，`/dev/zero` 會讀不完。
        // 迴圈讀到 EOF 或上限，不押在單次 `read(upToCount:)` 的行為上。實測（R3）：Foundation 目前對分段寫入的 FIFO 一次就讀到 EOF——
        // 驗證時 Codex 席說它只回第一段，那個說法在這個平台上不成立；迴圈沒有改變行為，只是不依賴那個實作細節（`<(…)` 就是這個形狀）。
        // 指向一個永遠不關閉的 FIFO 會一直等，與任何讀 stdin 的 CLI 相同，不另外處理。
        let text: String
        do {
            guard let handle = FileHandle(forReadingAtPath: idsFile) else { throw CocoaError(.fileReadNoSuchFile) }
            defer { try? handle.close() }
            var data = Data()
            while true {
                let chunk = try handle.read(upToCount: Swift.min(65_536, Self.maxIdsFileBytes + 1 - data.count)) ?? Data()
                if chunk.isEmpty { break }
                data.append(chunk)
                if data.count > Self.maxIdsFileBytes {
                    throw RuntimeFailure.state("--ids-file 超過 256 KiB（至多 500 個 id，不需要這麼大）：\(displaySafeInvisible(idsFile, max: 300))")
                }
            }
            guard let decoded = String(data: data, encoding: .utf8) else { throw CocoaError(.fileReadInapplicableStringEncoding) }
            text = decoded
        } catch let failure as RuntimeFailure {
            throw failure
        } catch {
            throw RuntimeFailure.state("讀不到 --ids-file：\(displaySafeInvisible(idsFile, max: 300))")
        }
        let ids = text.split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        let fields = options.fieldList(default: S2CLI.paperFields)
        try S2CLI.run(options) { try await $0.batch(ids: ids, fields: fields) }
    }
}

struct S2ReferencesCmd: ParsableCommand {
    static let configuration = CommandConfiguration(commandName: "references", abstract: "一篇論文的參考文獻（預設全部）")
    @Argument(help: "論文識別碼") var paperID: String
    @OptionGroup var page: S2PageOptions
    @OptionGroup var options: S2Options
    func validate() throws {
        try S2CLI.checkIdentifier(paperID, endpoint: "references")
    }
    func run() throws {
        let id = paperID, limit = page.limit, offset = page.offset, fields = options.fieldList(default: S2CLI.paperFields)
        try S2CLI.run(options) { try await $0.references(id: id, fields: fields, limit: limit, offset: offset) }
    }
}

struct S2CitationsCmd: ParsableCommand {
    static let configuration = CommandConfiguration(commandName: "citations", abstract: "引用一篇論文的論文（預設全部）")
    @Argument(help: "論文識別碼") var paperID: String
    @OptionGroup var page: S2PageOptions
    @OptionGroup var options: S2Options
    func validate() throws {
        try S2CLI.checkIdentifier(paperID, endpoint: "citations")
    }
    func run() throws {
        let id = paperID, limit = page.limit, offset = page.offset, fields = options.fieldList(default: S2CLI.paperFields)
        try S2CLI.run(options) { try await $0.citations(id: id, fields: fields, limit: limit, offset: offset) }
    }
}

struct S2RecommendCmd: ParsableCommand {
    static let configuration = CommandConfiguration(commandName: "recommend", abstract: "與一篇論文相似的論文")
    @Argument(help: "論文識別碼") var paperID: String
    @Option(name: .long, help: "筆數（1–500）") var limit: Int = 100
    @OptionGroup var options: S2Options
    func validate() throws {
        try S2CLI.checkIdentifier(paperID, endpoint: "recommend")
        if !(1...500).contains(limit) {
            throw ValidationError(displaySafeErrorText(S2ArgumentError.limitOutOfRange(endpoint: "recommend", limit: limit, min: 1, max: 500)))
        }
    }
    func run() throws {
        let id = paperID, l = limit, fields = options.fieldList(default: S2CLI.paperFields)
        try S2CLI.run(options) { try await $0.recommend(id: id, limit: l, fields: fields) }
    }
}

struct S2AuthorSearchCmd: ParsableCommand {
    static let configuration = CommandConfiguration(commandName: "author-search", abstract: "以姓名搜尋作者（預設 100 筆）")
    @Option(name: .long, help: "姓名") var name: String
    @OptionGroup var page: S2PageOptions
    @OptionGroup var options: S2Options
    func validate() throws {
        if name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            throw ValidationError(displaySafeErrorText(S2ArgumentError.emptyIdentifier(endpoint: "author-search")))
        }
    }
    func run() throws {
        let n = name, limit = page.limit, offset = page.offset, fields = options.fieldList(default: S2CLI.authorFields)
        try S2CLI.run(options) { try await $0.authorSearch(name: n, fields: fields, limit: limit, offset: offset) }
    }
}

struct S2AuthorPapersCmd: ParsableCommand {
    static let configuration = CommandConfiguration(commandName: "author-papers", abstract: "一位作者的著作（預設全部）")
    @Argument(help: "S2 authorId") var authorID: String
    @OptionGroup var page: S2PageOptions
    @OptionGroup var options: S2Options
    func validate() throws {
        try S2CLI.checkIdentifier(authorID, endpoint: "author-papers")
    }
    func run() throws {
        let id = authorID, limit = page.limit, offset = page.offset, fields = options.fieldList(default: S2CLI.paperFields)
        try S2CLI.run(options) { try await $0.authorPapers(id: id, fields: fields, limit: limit, offset: offset) }
    }
}

/// 不連網。回報 keychain 項目存在與否、可否讀取、節流狀態；**不印金鑰，也不印它的長度**。
/// 結束碼：金鑰存在且可讀為 0，否則 3。skill 選路要再看 `--json` 的 `keychain.present`（false＝keychain 說找不到；true＝項目在、現在讀不到，不是沒有金鑰）。
struct S2StatusCmd: ParsableCommand {
    static let configuration = CommandConfiguration(commandName: "status", abstract: "檢查金鑰與節流狀態（不連網、不印金鑰）")
    @Flag(name: .long, help: "輸出 JSON") var json = false

    func run() throws {
        let settings = try S2CLI.resolveSettings()
        let probe: S2KeyProbe? = settings.readsKeychain ? S2KeychainKeyProvider(settings: settings).probe() : nil
        let throttle = S2FileThrottle(stateDirectory: settings.stateDirectory)
        let next = throttle.peekNextAllowedAt().map(S2Output.timestamp)
        let host = settings.baseURL.host ?? ""

        if json {
            print(S2Output.statusJSON(settings: settings, probe: probe))
        } else {
            let yn: (Bool?) -> String = { $0.map { $0 ? "是" : "否" } ?? "未檢查（AKASHIC_S2_BASE_URL 已設定，不讀 keychain）" }
            print(displaySafeAssembled("keychain：service「\(settings.keychainService)」account「\(settings.keychainAccount)」存在：\(yn(probe?.present)) 可讀：\(yn(probe?.readable))"))   // display-safe-exempt: settings 的 keychainService／keychainAccount 是常量或已驗證的 akashic-test- 名稱
            print(displaySafeAssembled("節流狀態檔：\(throttle.stateFile.path) 下次可送：\(next ?? "無紀錄")"))
            print(displaySafeAssembled("主機：\(host)"))
        }
        if let probe, !(probe.present && probe.readable) { throw ExitCode(3) }
    }
}
