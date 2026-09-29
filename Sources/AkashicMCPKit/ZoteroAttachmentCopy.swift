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
        /// 第二次讀（實跑）用：資料目錄與 `locate` 的結果——`ZoteroStorageFile.read` 從 descriptor 重新判斷，不以路徑直讀。
        let dataDir: URL
        let located: ZoteroStorageFile.Located
    }

    /// 略過一個附件的原因。封閉列舉。
    public enum SkipReason: Equatable {
        /// 定位不到（`ZoteroStorageFile.Refusal`：路徑形狀不對、檔案不在、跑出 `storage/`、不是普通檔、0 byte）。
        case file(ZoteroStorageFile.Refusal)
        /// 檔案在，但讀不出來。
        case unreadable
        /// 計畫算完之後、複製之前，檔案的內容變了（digest 對不上）——不存、不連。
        case changedDuringRun
        /// digest 已連在 work 上，但本機 `sources/` 的那一份判不出在不在（shard 目錄讀不到、位置上是目錄或 symlink、index 有壞行而判不出條目）——
        /// 不重存、不動連結；值是原因（已消毒）。`akashic doctor` 會列出 `sources/` 的問題。
        case localCopyUnverifiable(String)
    }

    /// `storeSource` 冪等早退、丟棄了這次交來的取得記錄（`discardedProvenance`）的一個檔：index 已有這份內容的條目、以先到的為準，
    /// 這次的 Zotero 來源（`origin: zotero:<path>` 與 note）**沒有**寫進 index（`lossless-intake`：丟棄必須可見）。
    /// 位元組可能早就在，也可能是這一次才存的（index 的條目還在、blob 被清過）——#606 R2 verify 之前一律說成「早就在」，
    /// 而同一份報告剛說過「已補存」。
    public struct ProvenanceNotRecorded: Equatable {
        public let item: Item
        /// index 裡保留的那一條的 `origin`（已消毒）；讀不到是 nil。
        public let keptOrigin: String?
        /// 存之前 blob 就在 `sources/`（`SourceReceipt.bytesWritten` 的反面）。false＝位元組是這一次才存進去的。
        public let bytesWereAlreadyStored: Bool
    }

    /// 已連過的 digest 補存（位元組或取得記錄）時 `storeSource` 擲錯（I/O、磁碟滿）。與 `writeFailed` 分開：
    /// 補存不改寫 work，同一筆 work 的新連結可能已經寫進去了——混在一起會讓同一個 citekey 同時在 `written` 與 `writeFailed`（#606 R2 verify）。
    public struct RestoreFailure: Equatable {
        public let item: Item
        /// 已消毒。
        public let message: String
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
    /// digest 已在該筆 work 的 `akashic.sources` 上，**而且位元組在本機 `sources/`**（前一次跑過，或同一筆內另一個附件內容相同）。
    public var alreadyLinked: [Item] = []
    /// digest 已連在 work 上、本機 `sources/` 卻**沒有**這份位元組（別台 clone——`sources/` 不進 git——或 `sources/` 被清過）：
    /// 乾跑是要補存的、實跑是已補存的。只存位元組與取得記錄，**不改連結**、不動 work 檔（所以不過可回溯閘）。#606 R1 verify。
    public var restoredLocally: [Item] = []
    /// digest 已連在 work 上、位元組在本機，但 `sources/index.jsonl` 沒有它的條目（孤兒 blob：`akashic doctor` 報的 `orphanBlobs`）：
    /// 乾跑是要補記的、實跑是已補記的——走同一個 `storeSource`，位元組不重寫、補上這一次的取得記錄；不改連結、不動 work 檔。
    /// #606 R2 verify 之前這一格算進 `alreadyLinked`，每次重跑都說已連過，而工具手上就有補記需要的資料。
    public var recordRestored: [Item] = []
    /// 實跑：補存（`restoredLocally`／`recordRestored`）時 `storeSource` 擲錯的檔。連結沒動，重跑會再補。
    public var restoreFailed: [RestoreFailure] = []
    public var skipped: [Skipped] = []
    /// 無法唯一定位的 work（#627／#641）——本趟不碰。
    public var unlocatable: [String] = []
    /// `--citekeys` 點名、store 裡沒有的。
    public var notInStore: [String] = []
    /// `--citekeys` 點名、存在、但沒有 zotero 附件記錄的。
    public var noZoteroAttachments: [String] = []
    /// 實跑：`akashic.sources` 被改寫的 work。
    public var written: [String] = []
    /// 實跑：單筆寫入失敗（citekey → 已消毒的錯誤描述），其餘照跑。含「計畫之後這筆 work 被改過」（閘之後重讀、與計畫的快照不同——
    /// 不以舊快照覆寫，#606 R1 verify）。
    public var writeFailed: [String: String] = [:]
    /// 實跑：index 已有這份內容的條目、這次的取得記錄沒有寫進 index 的檔（前一次跑到一半、這一趟稍早另一筆 work 存過同一份、同一份內容
    /// 先前經別的路徑存過、或 index 的條目還在而 blob 被清過）。不重複記；逐檔列出並附 index 保留的那一條的 origin。
    public var provenanceNotRecorded: [ProvenanceNotRecorded] = []
    /// `provenanceNotRecorded` 裡位元組早就在的個數（這一次才存位元組的不算）。
    public var blobsAlreadyStored: Int { provenanceNotRecorded.filter(\.bytesWereAlreadyStored).count }
    /// 實跑：有沒有真的改寫 work 檔或補存任何檔。`applied` 只說「走到了寫入那一段」——全部略過時它也是 true（#606 R2 verify）。
    public var changedAnything: Bool { !written.isEmpty || !restoredLocally.isEmpty || !recordRestored.isEmpty }
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
/// - **可重跑**：digest 已在該筆 work 的 `akashic.sources` 上、**位元組在本機 `sources/` 且 index 有它的取得記錄**的不重複複製（`alreadyLinked`）；
///   已連過而本機沒有位元組的（別台 clone、`sources/` 被清過）只補存位元組、不改連結（`restoredLocally`）——「已複製」看的是本機存檔，不是連結（#606 R1 verify）；
///   位元組在而 index 沒有條目的（孤兒 blob）只補記取得記錄（`recordRestored`，#606 R2 verify）——只看存在與條目，**不重算既有 blob 的 digest**；
///   blob 早就在 `sources/`（前一次跑到一半）的不重寫、不重複記取得記錄（`storeSource` 的冪等語意），這次沒寫進 index 的 Zotero 來源逐檔列在
///   `provenanceNotRecorded`（附 index 保留的 origin）。
/// - **不以舊快照覆寫**：寫 work 之前，讀可回溯閘回傳的那個檔、與計畫時 load 的快照比相等；不同（閘的時間窗裡被別的寫入者改過並 commit）就不寫、
///   記進 `writeFailed`，其餘照跑（App #609 移除面的 `changedDuringCheck` 同一條，#606 R1 verify）。
/// - **整批拒絕、零寫入的閘**（任何一個檔落地之前）：每一筆要改寫的 work 過 `writeEntry` 的全部前置（`preflightWrite`）；每個要存的 digest 過
///   `storeSource` 的前置（`preflightStoreSource`：`sources/` 沒被版控排除、git 不可用、index 有壞行）；被改寫的 work 檔要已在 git 裡 commit、乾淨
///   （`assertRecordsRecoverable`——舊版只剩 git 那一份；只覆蓋**真的要被改寫**的記錄）。
/// - **逐筆略過（具名，其餘照跑）**：附件路徑不是 `storage/<KEY>/<檔名>`、檔案不在、不是普通檔、0 byte、讀不出來、計畫之後內容變了；
///   無法唯一定位的 work（`unlocatableCitekeys`）。
/// - **只複製附件記錄的那一個檔**：HTML snapshot 同目錄的資源檔不複製。
/// - 不動 `attachments`、不動 `provenance`、不動書目欄位；`akashic.sources` 只追加。
///
/// **誠實邊界**：`sources/` 不進 git，別台 clone 讀到這條連結時位元組不在（§2.4.1：載入成功、可報缺席）——那台機器上重跑本命令會補回（`restoredLocally`），
/// 前提是它的 Zotero 資料目錄裡還有那個檔；沒有大小上限（每個檔整份讀進記憶體、存完即釋放——**乾跑也一樣**，要讀完整份才算得出 digest；
/// 不 mmap，檔案被截短時 mmap 會讓行程收到 SIGBUS；`store-source` 與 `SourceStore` 本來就沒有大小上限，這裡不另立一個）；
/// 計畫階段與複製階段各讀一次檔案（`ZoteroStorageFile.read`：`O_NOFOLLOW` 開一次、從同一個 descriptor 判斷種類與真實位置再讀完），之間內容被換掉時以
/// digest 對不上偵測（`changedDuringRun`）；閘之後的重讀與寫入之間仍有一個很短的窗（沒有 store 層的鎖）；Zotero 端的檔案之後再變（重新下載、編輯註記）不會回頭更新
/// 已複製的副本——那是另一份內容、另一個 digest，下一次跑會再連一份。**逆操作**：連錯的宣告用 `update-entry --remove-source`（#677）收回；blob 與取得記錄留在
/// `sources/`（可能被別筆引用）。
extension AkashicService {

    public func copyZoteroAttachments(zoteroDb: String?, citekeys: [String]?, apply: Bool,
                                      now: Date = Date()) throws -> ZoteroAttachmentCopyReport {
        try copyZoteroAttachments(zoteroDb: zoteroDb, citekeys: citekeys, apply: apply, now: now, afterPlanning: nil)
    }

    /// 測試接縫：`afterPlanning` 在計畫算完、第一次寫入之前呼叫（模擬「計畫之後檔案內容被換掉」）；`beforeStore` 在每一次 `storeSource` 之前呼叫，
    /// 擲錯即當成那一次存檔擲錯（模擬 I/O 失敗）。對外的入口沒有這兩個參數。
    func copyZoteroAttachments(zoteroDb: String?, citekeys: [String]?, apply: Bool, now: Date,
                               afterPlanning: (() throws -> Void)?,
                               beforeStore: ((ZoteroAttachmentCopyReport.Item) throws -> Void)? = nil) throws -> ZoteroAttachmentCopyReport {
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

        // 計畫：每筆 work 算出「要新連的檔」。讀檔只為算 digest（整份讀進記憶體、算完即釋放；不 mmap，理由見 `ZoteroStorageFile.read`）。
        struct Target { var entry: Entry; var items: [ZoteroAttachmentCopyReport.Item] }
        var targets: [Target] = []
        var linkedOnWork: [ZoteroAttachmentCopyReport.Item] = []
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
            let alreadyOnWork = Set(entry.akashic.sources)
            var linked = alreadyOnWork
            var items: [ZoteroAttachmentCopyReport.Item] = []
            var seenPaths = Set<String>()
            var linkedSeen = Set<String>()   // 已連的 digest 在這筆 work 裡只查一次、只補一次（#606 R2 verify：與新連結那一條路同形）
            for att in attachments where seenPaths.insert(att.path).inserted {
                switch ZoteroStorageFile.locate(dataDir: dataDir, attachmentPath: att.path) {
                case .refused(let why):
                    report.skipped.append(.init(citekey: entry.citekey, path: att.path, reason: .file(why)))
                case .found(let f):
                    let data: Data
                    switch ZoteroStorageFile.read(dataDir: dataDir, located: f) {
                    case .data(let d): data = d
                    case .refused(let why):
                        report.skipped.append(.init(citekey: entry.citekey, path: att.path, reason: .file(why)))
                        continue
                    case .unreadable:
                        report.skipped.append(.init(citekey: entry.citekey, path: att.path, reason: .unreadable))
                        continue
                    }
                    let item = ZoteroAttachmentCopyReport.Item(
                        citekey: entry.citekey, path: att.path, digest: LibraryStore.contentDigest(of: data), bytes: data.count,
                        mediaType: ZoteroStorageFile.mediaType(forFilename: f.url.lastPathComponent), modified: f.modified, url: f.url,
                        dataDir: dataDir, located: f)
                    if linked.insert(item.digest).inserted {
                        items.append(item)
                    } else if alreadyOnWork.contains(item.digest), linkedSeen.insert(item.digest).inserted {
                        linkedOnWork.append(item)   // 連結在——位元組在不在本機，下面一次查完
                    } else if alreadyOnWork.contains(item.digest) {
                        report.alreadyLinked.append(item)   // 同一筆內另一個附件內容相同、已在上面那一格：補存（若要）只做一次
                    } else {
                        report.alreadyLinked.append(item)   // 同一筆內另一個附件剛計畫的同一份內容：它那一份會存
                    }
                }
            }
            if !items.isEmpty { targets.append(Target(entry: entry, items: items)) }
        }
        // 已連過的：位元組在本機才算做完（`sources/` 不進 git，別台 clone 的連結在、位元組不在）。一次查完所有 digest（#614 的 `sourcePresence`）。
        if !linkedOnWork.isEmpty {
            do {
                let presence = try store.sourcePresence(digests: Array(Set(linkedOnWork.map(\.digest))))
                for item in linkedOnWork {
                    switch presence[item.digest] {
                    case .stored?:
                        report.alreadyLinked.append(item)
                    case .unindexed?:   // 位元組在、index 沒有條目：補記取得記錄（#606 R2 verify）
                        report.recordRestored.append(item)
                    case .absent?:
                        report.restoredLocally.append(item)
                    case .notRegularFile(let kind)?:
                        report.skipped.append(.init(citekey: item.citekey, path: item.path, reason: .localCopyUnverifiable(
                            "本機 sources/ 裡這份存檔的位置上是\(displaySafeInvisible(kind, max: 40))、不是普通檔")))
                    case .unreadable?, nil:
                        report.skipped.append(.init(citekey: item.citekey, path: item.path, reason: .localCopyUnverifiable(
                            "本機 sources/ 的分片目錄讀不到")))
                    }
                }
            } catch {
                let why = displaySafeError(error, max: 600)
                for item in linkedOnWork {
                    report.skipped.append(.init(citekey: item.citekey, path: item.path, reason: .localCopyUnverifiable(why)))
                }
            }
        }
        report.planned = targets.flatMap(\.items)
        try afterPlanning?()

        // 閘：任何檔落地之前。乾跑把拒絕當預告放進報告，實跑擲錯。
        var gatePaths: [UUID: String] = [:]
        do {
            gatePaths = try assertZoteroCopyWritable(targets.map { ($0.entry, $0.items) },
                                                     restoreDigests: (report.restoredLocally + report.recordRestored).map(\.digest))
        } catch {
            if apply { throw error }
            report.applyRefusal = displaySafeError(error, max: 4_096)
        }
        guard apply, !targets.isEmpty || !report.restoredLocally.isEmpty || !report.recordRestored.isEmpty else { return report }
        report.applied = true

        // 實跑：逐筆——先存這一筆的檔、再寫這一筆的連結。單筆失敗收容（`import-zotero` 的形），其餘照跑；重跑會補上沒做完的。
        var plannedAfter: [ZoteroAttachmentCopyReport.Item] = []
        let stamp = ISO8601DateFormatter().string(from: now)
        var notRecorded: [(item: ZoteroAttachmentCopyReport.Item, bytesWereAlreadyStored: Bool)] = []
        func fail(_ citekey: String, _ why: String) {
            report.writeFailed[citekey] = report.writeFailed[citekey].map { $0 + "；" + why } ?? why
        }
        /// 讀第二次、digest 要與計畫相同才存（不同就是被換掉了，略過、不存、不連）。回傳存檔的收據；略過回 nil。
        func storeOne(_ item: ZoteroAttachmentCopyReport.Item) throws -> LibraryStore.SourceReceipt? {
            let data: Data
            switch ZoteroStorageFile.read(dataDir: item.dataDir, located: item.located) {
            case .data(let d): data = d
            case .refused(let why):
                report.skipped.append(.init(citekey: item.citekey, path: item.path, reason: .file(why)))
                return nil
            case .unreadable:
                report.skipped.append(.init(citekey: item.citekey, path: item.path, reason: .unreadable))
                return nil
            }
            guard LibraryStore.contentDigest(of: data) == item.digest else {
                report.skipped.append(.init(citekey: item.citekey, path: item.path, reason: .changedDuringRun))
                return nil
            }
            try beforeStore?(item)
            let receipt = try store.storeSource(data, provenance: LibraryStore.SourceProvenance(
                mediaType: item.mediaType, retrieved: stamp,
                origin: "zotero:\(item.path)", acquisition: "zotero-storage-copy",
                note: Self.zoteroCopyNote(citekey: item.citekey, modified: item.modified)))
            if receipt.discardedProvenance != nil { notRecorded.append((item, !receipt.bytesWritten)) }
            report.exclusionVerified = (report.exclusionVerified ?? true) && receipt.exclusionVerified
            return receipt
        }
        for t in targets {
            var entry = t.entry
            var linkedNow: [String] = []
            do {
                for item in t.items {
                    guard let receipt = try storeOne(item) else { continue }
                    linkedNow.append(receipt.digest)
                    plannedAfter.append(item)
                }
                guard !linkedNow.isEmpty else { continue }
                // 閘證的是「此刻磁碟上的檔已 commit、乾淨」，不是「它還等於計畫時的快照」：重讀閘回傳的那個檔，不同就不寫（#606 R1 verify）
                guard let path = gatePaths[entry.id], try store.rereadEntry(atRelativePath: path) == t.entry else {
                    plannedAfter.removeAll { $0.citekey == entry.citekey }
                    fail(entry.citekey, "計畫之後這筆 work 的記錄檔被改過（與計畫時讀到的不同）——不以計畫時的快照覆寫它；"
                        + "位元組已存進 sources/，重跑會以新的內容重新計畫並補上連結（#606）")
                    continue
                }
                entry.akashic.sources.append(contentsOf: linkedNow)
                try store.writeEntry(entry)
                report.written.append(entry.citekey)
            } catch {
                fail(entry.citekey, displaySafeError(error, max: 4_096))
                plannedAfter.removeAll { $0.citekey == entry.citekey }
            }
        }
        // 已連過、本機缺位元組或缺取得記錄的：只存，不改連結、不寫 work。失敗另列（不是 work 的寫入失敗，#606 R2 verify）
        var restoredAfter: [ZoteroAttachmentCopyReport.Item] = []
        var recordedAfter: [ZoteroAttachmentCopyReport.Item] = []
        for (item, isRecordOnly) in report.restoredLocally.map({ ($0, false) }) + report.recordRestored.map({ ($0, true) }) {
            do {
                guard let receipt = try storeOne(item) else { continue }
                // 補記那一格只收真的寫進 index 的：這一趟稍早另一個檔已記了同一份內容時，這一次的來源被丟棄、列在 provenanceNotRecorded
                if !isRecordOnly { restoredAfter.append(item) } else if receipt.indexEntryCreated { recordedAfter.append(item) }
            } catch {
                report.restoreFailed.append(.init(item: item, message: displaySafeError(error, max: 4_096)))
            }
        }
        report.restoredLocally = restoredAfter
        report.recordRestored = recordedAfter
        report.planned = plannedAfter
        if !notRecorded.isEmpty {
            let kept = (try? store.sourcePresence(digests: Array(Set(notRecorded.map(\.item.digest))))) ?? [:]
            report.provenanceNotRecorded = notRecorded.map { n in
                var origin: String?
                if case .stored(let row)? = kept[n.item.digest], let o = row["origin"] { origin = displaySafeInvisible(o, max: 300) }
                return .init(item: n.item, keptOrigin: origin, bytesWereAlreadyStored: n.bytesWereAlreadyStored)
            }
        }
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

    /// 寫入前的三道閘，乾跑與實跑共用（見型別 doc 的「整批拒絕、零寫入的閘」）。回傳可回溯閘解析出的記錄檔路徑（寫入前重讀用）。
    /// `restoreDigests`（已連過、本機缺位元組的）只過存檔前置——它們不改寫 work，不過可回溯閘。
    private func assertZoteroCopyWritable(_ targets: [(entry: Entry, items: [ZoteroAttachmentCopyReport.Item])],
                                          restoreDigests: [String]) throws -> [UUID: String] {
        guard !targets.isEmpty || !restoreDigests.isEmpty else { return [:] }
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
        for digest in Set(targets.flatMap { $0.items.map(\.digest) } + restoreDigests).sorted() {
            do {
                try store.preflightStoreSource(digest: digest)
            } catch {
                throw ServiceError.invalid("存檔前置過不了：\(displaySafeError(error, max: 2_000))——整批拒絕、零寫入（#606）")
            }
        }
        guard !targets.isEmpty else { return [:] }
        return try assertRecordsRecoverable(targets.map { ($0.entry.id, "work「\(displaySafeInvisible($0.entry.citekey, max: 200))」") },
                                            action: "這次會改寫 \(targets.count) 筆 work 的 akashic.sources",   // display-safe-exempt: targets.count 是 Int
                                            issue: "#606")
    }
}
