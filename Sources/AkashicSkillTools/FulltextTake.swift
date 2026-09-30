import Foundation
import AkashicCore
import AkashicStoreIO

/// 把**人存下來的**全文檔收進來：驗證、git 閘、存到 `--out`（#613，使用者 2026-10-01 裁決「拆成導航與收檔兩步，位元組先由人提供」）。
///
/// `fulltext fetch` 只負責把分頁導到頁面自己的 PDF 連結、交給人；PDF 的位元組由使用者自己存（Safari 的 PDF 檢視器、下載鈕或 ⌘S——
/// 哪一個是標準流程由 PsychQuant/safari-browser#210 的實驗決定，這裡不挑）。這個命令**不碰瀏覽器、不連網、不寫 store**：它只讀
/// `--from` 那個本機檔（不移動、不刪除、不改它），寫 `--out`（或 `*.unverified.pdf`）。之後存進 store 仍是 `store-source`。
///
/// # 結束碼
///
///     0 存好了，而且（有 --title 時）驗證是這篇         2 --from 不是 PDF（沒有 %PDF- 檔頭）；什麼都沒寫
///     1 其他失敗（--from 不是普通檔、太大、讀不了；      5 是 PDF，但驗證不是這篇（存成 FILE.unverified.pdf）
///       輸出目的地不合；git 閘拒絕）                    64 命令列打錯
///
/// 驗證與 git 閘是 #629 為 `fetch` 寫的那一份，搬到這裡：
///
/// - **驗的就是存的**：`--from` 只讀一次進記憶體，同一份位元組寫進 0700 的暫存目錄給 `verify` 讀、再寫到 `--out`。`--from` 在兩步之間
///   被換掉也不會存成別的東西。
/// - **輸出目的地**（`--out`、`*.unverified.pdf`）先 `lstat`：只有「不存在」或「普通檔」放行；覆寫是同目錄暫存＋`rename` 的原子替換
///   （`OutputFile`）。
/// - **git 閘 fail-closed**：輸出目錄的祖先有 `.git` 時，git 執行不起來、`rev-parse` 非零、`check-ignore` 不是 0／1，一律拒絕；
///   原子替換的暫存檔名一併問。git 一律走 `LibraryStore.hardenedGit`（#585）。
/// - `--from` 必須是普通檔（`lstat`：symlink、目錄、FIFO 都拒絕），大小不得超過 `store-source` 的上限（`LibraryStore.maxSourceBytes`，
///   #703——存不進 store 的檔收進來也沒有用）。
public final class FulltextTake {
    public struct Options {
        public var from: String
        public var out: String
        public var title: String?
        public var pages: String?
        public var doi: String?
        public init(from: String, out: String, title: String? = nil, pages: String? = nil, doi: String? = nil) {
            self.from = from; self.out = out; self.title = title; self.pages = pages; self.doi = doi
        }
    }

    /// 在目錄裡跑一次 git；nil＝執行不起來。預設是 repo 既有的加固 helper（#585）；測試注入「起不來」的版本。
    public typealias GitRunner = ([String], URL) -> (status: Int32, out: String)?

    struct Stop: Error { let code: Int32 }

    private let out: (String) -> Void
    private let err: (String) -> Void
    private let git: GitRunner
    private let sizeLimit: Int
    /// 暫存目錄建好之後被叫一次（測試接縫：量它的權限）。
    var onScratch: ((URL) -> Void)?

    public init(out: @escaping (String) -> Void, err: @escaping (String) -> Void, git: GitRunner? = nil,
                sizeLimit: Int = LibraryStore.maxSourceBytes) {
        self.out = out; self.err = err; self.sizeLimit = sizeLimit
        self.git = git ?? { LibraryStore.hardenedGit($0, in: $1) }
    }

    public func run(_ o: Options) -> Int32 {
        do {
            try execute(o)
            return 0
        } catch let stop as Stop {
            return stop.code
        } catch {
            err("✗ \(displaySafeErrorText(error))")
            return 1
        }
    }

    private func fail(_ message: String) -> Stop {
        err("✗ \(displaySafeInvisible(message, max: 600))")
        return Stop(code: 1)
    }

    private func execute(_ o: Options) throws {
        // --- 輸出落在哪裡：在讀 --from 之前先檢查 ---
        let outURL = URL(fileURLWithPath: o.out)
        let outDirURL = outURL.deletingLastPathComponent()
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: outDirURL.path, isDirectory: &isDir), isDir.boolValue else {
            throw fail("--out directory does not exist: \(outDirURL.path)")
        }
        let outDir = Self.physicalPath(outDirURL.path)   // `pwd -P`：`resolvingSymlinksInPath` 會把 `/private/var` 縮成 `/var`
        let outPath = outDir + "/" + outURL.lastPathComponent
        let stem = outPath.hasSuffix(".pdf") ? String(outPath.dropLast(4)) : outPath
        let unverified = stem + ".unverified.pdf"
        for f in [outPath, unverified] {
            if case .other(let kind) = try OutputFile.inspect(f) {
                err("✗ refusing: \(displaySafeInvisible(f, max: 400)) already exists and is a \(displaySafeInvisible(kind, max: 40)), not a regular file — this command only writes regular files and never deletes a directory or follows a symlink.")
                throw Stop(code: 1)
            }
        }
        let token = UUID().uuidString
        let finals = [outPath, unverified]
        try outputGitGate(outDir: outDir, files: finals, temps: finals.map { OutputFile.tempPath(for: $0, token: token) })

        // --- 讀 --from：普通檔、不超過上限，只讀一次 ---
        let body = try readSource(o.from)
        guard body.starts(with: Data("%PDF-".utf8)) else {
            let head = String(String(decoding: body.prefix(80), as: UTF8.self).unicodeScalars.filter { (0x20...0x7E).contains($0.value) })
            err("not a PDF (\(body.count) bytes, no %PDF- header): \(displaySafeInvisible(head, max: 120)) — nothing was written")
            throw Stop(code: 2)
        }

        // --- 驗證（有 --title 時）：驗的是暫存目錄裡同一份位元組 ---
        if let title = o.title, !title.isEmpty {
            let scratch = FileManager.default.temporaryDirectory.appendingPathComponent("fulltext-take-\(UUID().uuidString)")
            try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            defer { try? FileManager.default.removeItem(at: scratch) }
            onScratch?(scratch)
            let staged = scratch.appendingPathComponent("take.pdf")
            try body.write(to: staged)
            let (verdict, ok) = Self.verdictJSON(path: staged.path, title: title, pages: o.pages, doi: o.doi ?? "")
            out("verify: \(verdict)")
            if !ok {
                try OutputFile.replace(path: unverified, with: body, token: token)
                err("kept as \(displaySafeInvisible(unverified, max: 400))")
                throw Stop(code: 5)
            }
        }
        try OutputFile.replace(path: outPath, with: body, token: token)
        out("OK \(body.count) bytes -> \(displaySafeInvisible(outPath, max: 400))")
    }

    /// `--from`：`lstat` 是普通檔（不跟隨 symlink）、`O_NOFOLLOW` 開、`fstat` 再確認一次、大小不超過上限，讀一次。
    private func readSource(_ path: String) throws -> Data {
        switch try OutputFile.inspect(path) {
        case .absent:
            throw fail("--from does not exist: \(path)")
        case .other(let kind):
            throw fail("--from is a \(kind), not a regular file: \(path)")
        case .regular:
            break
        }
        let fd = open(path, O_RDONLY | O_NOFOLLOW)
        guard fd >= 0 else { throw fail("cannot read --from \(path): \(String(cString: strerror(errno)))") }
        let handle = FileHandle(fileDescriptor: fd, closeOnDealloc: true)
        var st = stat()
        guard fstat(fd, &st) == 0, (st.st_mode & S_IFMT) == S_IFREG else { throw fail("--from is not a regular file: \(path)") }
        guard Int(st.st_size) <= sizeLimit else {
            throw fail("--from is \(st.st_size) bytes, over the store-source limit of \(LibraryStore.sourceCapDescription(sizeLimit)): \(path)")
        }
        let data: Data
        do { data = try handle.readToEnd() ?? Data() } catch {
            throw fail("cannot read --from \(path): \(displaySafeErrorText(error))")
        }
        guard data.count <= sizeLimit else {
            throw fail("--from grew past the store-source limit of \(LibraryStore.sourceCapDescription(sizeLimit)) while it was read: \(path)")
        }
        return data
    }

    // MARK: 輸出路徑的 git 閘

    /// 全文是第三方內容，不得落進沒有忽略它的 git 工作樹（`.claude/rules` 的隱私邊界）。**fail-closed**（#629 R1 verify 第 8、10、28 則）：
    ///
    /// - 用檔案系統事實先問「輸出目錄的祖先有沒有 `.git`」（`LibraryStore.isInsideVersionedWorkTree`，不呼叫 git）。**沒有**＝不在任何
    ///   repo 裡，直接放行。
    /// - **有**——之後每一步 git 答不出來都拒絕、說原因：`git` 執行不起來、`rev-parse` 非零、`rev-parse` 不是 `true`、`check-ignore` 是 0
    ///   （已忽略）與 1（沒忽略）以外的碼。
    /// - 最終檔名之外，也問**寫入時的暫存檔名**（`temps`，與真的寫入同一個 token；R2 verify 第 2／33 則）。
    ///
    /// **範圍照實寫**：這道閘擋的是「輸出目錄的某個祖先有 `.git`、而那個 repo 沒有忽略這些檔（或它們的暫存檔名）」。repo 自己的
    /// `.gitattributes`、`info/attributes`、global config 裡被它點名的 filter driver 仍是 `hardenedGit` 記著的邊界。
    private func outputGitGate(outDir: String, files: [String], temps: [String]) throws {
        let dir = URL(fileURLWithPath: outDir)
        guard LibraryStore.isInsideVersionedWorkTree(dir) else { return }
        func refuse(_ why: String) -> Stop {
            err("✗ refusing: \(displaySafeInvisible(outDir, max: 400)) is inside a git working tree and \(why).")
            err("  Full text is third-party content. Write to a scratch directory outside git, then store it with akashic store-source.")
            return Stop(code: 1)
        }
        guard let inside = git(["rev-parse", "--is-inside-work-tree"], dir) else {
            throw refuse("git cannot be run, so it cannot be confirmed that the output files are ignored")
        }
        guard inside.status == 0, inside.out.trimmingCharacters(in: .whitespacesAndNewlines) == "true" else {
            throw refuse("git could not confirm the working tree (rev-parse exit \(inside.status))")   // display-safe-exempt: inside：status 是 Int32 結束碼
        }
        for f in files + temps {
            guard let r = git(["check-ignore", "-q", "--", f], dir) else {
                throw refuse("git cannot be run, so it cannot be confirmed that \(displaySafeInvisible(f, max: 400)) is ignored")
            }
            switch r.status {
            case 0: continue
            case 1:
                let top = git(["rev-parse", "--show-toplevel"], dir).map { $0.out.trimmingCharacters(in: .whitespacesAndNewlines) } ?? ""
                let what = temps.contains(f) ? "\(displaySafeInvisible(f, max: 400)) (the temporary name written before the atomic rename)" : displaySafeInvisible(f, max: 400)
                err("✗ refusing: \(what) would land in the git working tree \(displaySafeInvisible(top, max: 400)), which does not ignore it.")
                err("  Full text is third-party content. Write to a scratch directory outside git, then store it with akashic store-source.")
                throw Stop(code: 1)
            default:
                throw refuse("git could not answer whether \(displaySafeInvisible(f, max: 400)) is ignored (check-ignore exit \(r.status))")   // display-safe-exempt: r：status 是 Int32 結束碼
            }
        }
    }

    // MARK: 純函式

    /// `cd dir && pwd -P`：解開全部 symlink 的實體路徑（`realpath(3)`）。解不開時原樣回傳。
    static func physicalPath(_ path: String) -> String {
        var buffer = [CChar](repeating: 0, count: Int(PATH_MAX))
        return realpath(path, &buffer) != nil ? String(cString: buffer) : path
    }

    /// 驗證步驟：回（判定 JSON 一行，是否通過）。讀不到 PDF 或外部工具失敗時判定是 `{"error": …, "is_article": false}`。
    public static func verdictJSON(path: String, title: String, pages: String?, doi: String) -> (String, Bool) {
        do {
            let content = try PDFReader.read(path: path)
            let meta = try PDFReader.metadataDOI(path: path)
            let a = FulltextVerify.assess(firstPage: content.firstPages, pageCount: content.pageCount, title: title,
                                          pages: pages?.isEmpty == false ? pages : nil, doi: doi.isEmpty ? nil : doi, metaDOI: meta)
            return (a.json.dumps(), a.isArticle)
        } catch {
            return (PyJSON.object([("error", .string(displaySafeErrorText(error))), ("is_article", .bool(false))]).dumps(), false)
        }
    }
}
