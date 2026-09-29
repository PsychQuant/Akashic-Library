import Foundation
import AkashicCore
import AkashicStoreIO
import AkashicIndex
import AkashicZoteroImport

/// `copy-zotero-attachments` 的報告（#606）。
public struct ZoteroAttachmentCopyReport {
    /// 一個附件檔（已定位、算過 digest）。字串欄位取自 store 與檔案系統，輸出面要消毒。
    public struct Item: Equatable {
        public let citekey: String
        /// 附件記錄裡的 path（`storage/<KEY>/<檔名>`）。
        public let path: String
        public let digest: String
        public let bytes: Int
        public let mediaType: String
        /// 檔案在 Zotero 資料目錄裡的修改時間（進 `sources/index.jsonl` 的 note；不是取得時間）。
        let modified: Date?
        let url: URL
    }

    /// 略過一個附件的原因。封閉列舉。
    public enum SkipReason: Equatable {
        /// 定位不到（`ZoteroStorageFile.Refusal`：路徑形狀不對、檔案不在、跑出 `storage/`、不是普通檔、0 byte）。
        case file(ZoteroStorageFile.Refusal)
        /// 檔案在，但讀不出來。
        case unreadable
        /// 計畫算完之後、複製之前，檔案的內容變了（digest 對不上）——不存、不連。
        case changedDuringRun
    }

    public struct Skipped: Equatable {
        public let citekey: String
        public let path: String
        public let reason: SkipReason
    }

    /// 帶 zotero 附件記錄的 work 數（被點名的範圍內）。
    public var considered = 0
    /// 要複製並連結的檔（實跑時＝已複製、已連結的檔，除了 `skipped`／`writeFailed` 那幾筆）。
    public var planned: [Item] = []
    /// digest 已在該筆 work 的 `akashic.sources` 上（前一次跑過，或同一筆內另一個附件內容相同）。
    public var alreadyLinked: [Item] = []
    public var skipped: [Skipped] = []
    /// 無法唯一定位的 work（#627／#641）——本趟不碰。
    public var unlocatable: [String] = []
    /// `--citekeys` 點名、store 裡沒有的。
    public var notInStore: [String] = []
    /// `--citekeys` 點名、存在、但沒有 zotero 附件記錄的。
    public var noZoteroAttachments: [String] = []
    /// 實跑：`akashic.sources` 被改寫的 work。
    public var written: [String] = []
    /// 實跑：單筆寫入失敗（citekey → 已消毒的錯誤描述），其餘照跑。
    public var writeFailed: [String: String] = [:]
    /// 實跑：這次遇到 blob 早就在 `sources/` 裡（前一次跑到一半、或同一份內容先前經別的路徑存過）的檔數——不重複寫、不重複記取得記錄。
    public var blobsAlreadyStored = 0
    /// 實跑：`sources/` 的版控排除驗證是否真的跑了（store 不在 git 裡時是 false）。沒有存過任何東西時是 nil。
    public var exclusionVerified: Bool?
    public var applied = false
    /// 乾跑時：`--apply` 會以什麼理由整批拒絕（nil＝不會）。已消毒。`--apply` 本身遇到同樣的理由是直接擲錯、不寫任何一筆。
    public var applyRefusal: String?
    /// 實跑：index rebuild 失敗（已消毒）——記錄與存檔都已落地，報告不因此遺失。
    public var indexRebuildFailure: String?
}

/// `copy-zotero-attachments`（#606，為日後切斷 Zotero 鋪路，#605 的 sibling concern）：把 work 的 `zotero: storage/<KEY>/<檔名>` 附件的
/// **位元組**複製進 `sources/`（經 `SourceStore.storeSource`：內容定址、取得記錄同落、版控排除 fail-closed），再把 digest 連到那筆 work 的
/// `akashic.sources`（既有形狀，store-format §2.4.1）。只有 CLI 面——批次、操作者規模、讀本機 Zotero 資料目錄（`mcp-cli-parity` 的 CLI-only 表）。
///
/// ## 為什麼不「改寫附件記錄指向新位置」
///
/// 附件記錄（`Entry.attachments`，第 6 條邊）的鍵域是封閉的一（#223）：只有 `zotero:`，「不得因形狀相似而新增第二種路徑型引用」；可 ingest 的內容
/// 一律以 digest 引用、住在**記錄側**的 `akashic.sources`——那個形狀本來就存在，本命令只是它的第二個寫入者（第一個是 `update-entry --add-source`，#614）。
/// 而 `zotero:` 附件是 **Zotero 擁有的區塊**（namespace 契約，§2.5）：每次 pull 整批以 Zotero 為準，改寫或刪掉它下一次 `import-zotero` 就被還原。
/// 所以它原樣保留——同時就是這份副本的**來源記錄**（provenance）：`sources/index.jsonl` 的 `origin` 寫 `zotero:storage/<KEY>/<檔名>`，
/// 與 `attachments` 的那一格對得起來。
///
/// ## 契約
///
/// - **乾跑是預設**；`--apply` 才寫。乾跑與實跑算**同一份**計畫、跑**同一組**閘；乾跑把閘的拒絕當預告放進報告，實跑遇到就擲錯、零寫入。
/// - **可重跑**：digest 已在該筆 work 的 `akashic.sources` 上的不重複複製（`alreadyLinked`）；blob 早就在 `sources/`（前一次跑到一半）的不重寫、
///   不重複記取得記錄（`storeSource` 的冪等語意，報告 `blobsAlreadyStored`）。
/// - **整批拒絕、零寫入的閘**（任何一個檔落地之前）：每一筆要改寫的 work 過 `writeEntry` 的全部前置（`preflightWrite`）；每個要存的 digest 過
///   `storeSource` 的前置（`preflightStoreSource`：`sources/` 沒被版控排除、git 不可用、index 有壞行）；被改寫的 work 檔要已在 git 裡 commit、乾淨
///   （`assertRecordsRecoverable`——舊版只剩 git 那一份；只覆蓋**真的要被改寫**的記錄）。
/// - **逐筆略過（具名，其餘照跑）**：附件路徑不是 `storage/<KEY>/<檔名>`、檔案不在、不是普通檔、0 byte、讀不出來、計畫之後內容變了；
///   無法唯一定位的 work（`unlocatableCitekeys`）。
/// - **只複製附件記錄的那一個檔**：HTML snapshot 同目錄的資源檔不複製。
/// - 不動 `attachments`、不動 `provenance`、不動書目欄位；`akashic.sources` 只追加。
///
/// **誠實邊界**：`sources/` 不進 git，別台 clone 讀到這條連結時位元組不在（§2.4.1：載入成功、可報缺席）；沒有大小上限（檔案以 mmap 讀入，不常駐記憶體）；
/// 計畫階段與複製階段各讀一次檔案，之間內容被換掉時以 digest 對不上偵測（`changedDuringRun`）；Zotero 端的檔案之後再變（重新下載、編輯註記）不會回頭更新
/// 已複製的副本——那是另一份內容、另一個 digest，下一次跑會再連一份。**逆操作**：連錯的宣告用 `update-entry --remove-source`（#677）收回；blob 與取得記錄留在
/// `sources/`（可能被別筆引用）。
extension AkashicService {

    public func copyZoteroAttachments(zoteroDb: String?, citekeys: [String]?, apply: Bool,
                                      now: Date = Date()) throws -> ZoteroAttachmentCopyReport {
        try copyZoteroAttachments(zoteroDb: zoteroDb, citekeys: citekeys, apply: apply, now: now, afterPlanning: nil)
    }

    /// 測試接縫：`afterPlanning` 在計畫算完、第一次寫入之前呼叫（模擬「計畫之後檔案內容被換掉」）。對外的入口沒有這個參數。
    func copyZoteroAttachments(zoteroDb: String?, citekeys: [String]?, apply: Bool, now: Date,
                               afterPlanning: (() throws -> Void)?) throws -> ZoteroAttachmentCopyReport {
        let dbPath = ((zoteroDb ?? "~/Zotero/zotero.sqlite") as NSString).expandingTildeInPath
        guard FileManager.default.fileExists(atPath: dbPath) else {
            throw ServiceError.notFound("zotero.sqlite：\(displaySafeInvisible(dbPath, max: 300))")
        }
        let dataDir = URL(fileURLWithPath: dbPath).deletingLastPathComponent()
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: dataDir.appendingPathComponent("storage").path, isDirectory: &isDir), isDir.boolValue else {
            throw ServiceError.notFound("Zotero 資料目錄的 storage/：\(displaySafeInvisible(dataDir.appendingPathComponent("storage").path, max: 300))"
                                        + "——zotero.sqlite 所在的目錄要是 Zotero 的資料目錄")
        }

        let load = try store.load()
        let unlocatable = load.entries.unlocatableCitekeys
        let wanted = citekeys.map { Set($0) }
        var report = ZoteroAttachmentCopyReport()
        if let wanted {
            report.notInStore = wanted.subtracting(load.entries.map(\.citekey)).sorted()
        }

        // 計畫：每筆 work 算出「要新連的檔」。讀檔只為算 digest（mmap，不常駐）。
        struct Target { var entry: Entry; var items: [ZoteroAttachmentCopyReport.Item] }
        var targets: [Target] = []
        for entry in load.entries.sorted(by: { $0.citekey < $1.citekey }) {
            if let wanted, !wanted.contains(entry.citekey) { continue }
            let attachments = entry.attachments.filter { $0.kind == .zotero }
            guard !attachments.isEmpty else {
                if wanted != nil { report.noZoteroAttachments.append(entry.citekey) }
                continue
            }
            report.considered += 1
            if unlocatable.contains(entry.citekey) {
                if !report.unlocatable.contains(entry.citekey) { report.unlocatable.append(entry.citekey) }
                continue
            }
            var linked = Set(entry.akashic.sources)
            var items: [ZoteroAttachmentCopyReport.Item] = []
            var seenPaths = Set<String>()
            for att in attachments where seenPaths.insert(att.path).inserted {
                switch ZoteroStorageFile.locate(dataDir: dataDir, attachmentPath: att.path) {
                case .refused(let why):
                    report.skipped.append(.init(citekey: entry.citekey, path: att.path, reason: .file(why)))
                case .found(let f):
                    guard let data = try? Data(contentsOf: f.url, options: .mappedIfSafe), !data.isEmpty else {
                        report.skipped.append(.init(citekey: entry.citekey, path: att.path, reason: .unreadable))
                        continue
                    }
                    let item = ZoteroAttachmentCopyReport.Item(
                        citekey: entry.citekey, path: att.path, digest: LibraryStore.contentDigest(of: data), bytes: data.count,
                        mediaType: ZoteroStorageFile.mediaType(forFilename: f.url.lastPathComponent), modified: f.modified, url: f.url)
                    if linked.insert(item.digest).inserted { items.append(item) } else { report.alreadyLinked.append(item) }
                }
            }
            if !items.isEmpty { targets.append(Target(entry: entry, items: items)) }
        }
        report.planned = targets.flatMap(\.items)
        try afterPlanning?()

        // 閘：任何檔落地之前。乾跑把拒絕當預告放進報告，實跑擲錯。
        do {
            try assertZoteroCopyWritable(targets.map { ($0.entry, $0.items) })
        } catch {
            if apply { throw error }
            report.applyRefusal = displaySafeError(error, max: 4_096)
        }
        guard apply, !targets.isEmpty else { return report }
        report.applied = true

        // 實跑：逐筆——先存這一筆的檔、再寫這一筆的連結。單筆失敗收容（`import-zotero` 的形），其餘照跑；重跑會補上沒做完的。
        var plannedAfter: [ZoteroAttachmentCopyReport.Item] = []
        let stamp = ISO8601DateFormatter().string(from: now)
        for t in targets {
            var entry = t.entry
            var linkedNow: [String] = []
            do {
                for item in t.items {
                    // 計畫與複製各讀一次：這一次讀到的內容要與計畫的 digest 相同才存——不同就是被換掉了，略過、不存、不連。
                    guard let data = try? Data(contentsOf: item.url, options: .mappedIfSafe), !data.isEmpty else {
                        report.skipped.append(.init(citekey: item.citekey, path: item.path, reason: .unreadable))
                        continue
                    }
                    guard LibraryStore.contentDigest(of: data) == item.digest else {
                        report.skipped.append(.init(citekey: item.citekey, path: item.path, reason: .changedDuringRun))
                        continue
                    }
                    let receipt = try store.storeSource(data, provenance: LibraryStore.SourceProvenance(
                        mediaType: item.mediaType, retrieved: stamp,
                        origin: "zotero:\(item.path)", acquisition: "zotero-storage-copy",
                        note: Self.zoteroCopyNote(citekey: item.citekey, modified: item.modified)))
                    if !receipt.indexEntryCreated { report.blobsAlreadyStored += 1 }
                    report.exclusionVerified = (report.exclusionVerified ?? true) && receipt.exclusionVerified
                    linkedNow.append(receipt.digest)
                    plannedAfter.append(item)
                }
                guard !linkedNow.isEmpty else { continue }
                entry.akashic.sources.append(contentsOf: linkedNow)
                try store.writeEntry(entry)
                report.written.append(entry.citekey)
            } catch {
                report.writeFailed[entry.citekey] = displaySafeError(error, max: 4_096)
                plannedAfter.removeAll { $0.citekey == entry.citekey }
            }
        }
        report.planned = plannedAfter
        if !report.written.isEmpty {
            do { try LibraryIndex(store: store).rebuild() } catch {
                report.indexRebuildFailure = displaySafeError(error, max: 1_024)
            }
        }
        return report
    }

    /// `sources/index.jsonl` 的 note：哪個命令、哪一筆 work、Zotero 端檔案的修改時間（不是取得時間——`retrieved` 是複製當下）。
    static func zoteroCopyNote(citekey: String, modified: Date?) -> String {
        var s = "自 Zotero 資料目錄複製（akashic copy-zotero-attachments，#606）；work \(citekey)"
        if let modified { s += "；檔案修改時間 \(ISO8601DateFormatter().string(from: modified))" }
        return s
    }

    /// 寫入前的三道閘，乾跑與實跑共用（見型別 doc 的「整批拒絕、零寫入的閘」）。
    private func assertZoteroCopyWritable(_ targets: [(entry: Entry, items: [ZoteroAttachmentCopyReport.Item])]) throws {
        guard !targets.isEmpty else { return }
        for t in targets {
            var updated = t.entry
            updated.akashic.sources.append(contentsOf: t.items.map(\.digest))
            do {
                try store.preflightWrite(updated)
            } catch {
                throw ServiceError.invalid(
                    "work「\(displaySafeInvisible(t.entry.citekey, max: 200))」連上副本之後過不了寫入閘：\(displaySafeError(error, max: 2_000))"
                    + "——整批拒絕、零寫入（#606）")
            }
        }
        for digest in Set(targets.flatMap { $0.items.map(\.digest) }).sorted() {
            do {
                try store.preflightStoreSource(digest: digest)
            } catch {
                throw ServiceError.invalid("存檔前置過不了：\(displaySafeError(error, max: 2_000))——整批拒絕、零寫入（#606）")
            }
        }
        try assertRecordsRecoverable(targets.map { ($0.entry.id, "work「\(displaySafeInvisible($0.entry.citekey, max: 200))」") },
                                     action: "這次會改寫 \(targets.count) 筆 work 的 akashic.sources",   // display-safe-exempt: targets.count 是 Int
                                     issue: "#606")
    }
}
