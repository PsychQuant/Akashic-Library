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
        /// 第二次讀（實跑）用：資料目錄與 `locate` 的結果——`ZoteroStorageFile.openVerified` 從 descriptor 重新判斷，不以路徑直讀。
        let dataDir: URL
        let located: ZoteroStorageFile.Located
    }

    /// 略過一個附件的原因。封閉列舉。
    public enum SkipReason: Equatable {
        /// 定位不到（`ZoteroStorageFile.Refusal`：路徑形狀不對、檔案不在、跑出 `storage/`、不是普通檔、0 byte、超過 256 MiB 的上限——#703）。
        case file(ZoteroStorageFile.Refusal)
        /// 檔案在，但讀不出來。
        case unreadable
        /// 計畫算完之後、複製之前，檔案的內容變了（digest 對不上）——不存、不連。
        case changedDuringRun
        /// 本機 `sources/` 裡這個 digest 的那一份判不出在不在、是不是這份內容（shard 目錄讀不到、位置上是目錄或 symlink、打不開、index 有壞行
        /// 而判不出條目）——不存、不動連結。兩種情形共用這一格：digest 已連在 work 上（不重存），或這一趟本來要新連而位址上已有東西（不新連；
        /// #703 R1 verify 第 1、4、6、19、24 則——先前新連結只擋 `.mismatch`，位址上是目錄時照樣連上並報「已複製」）。值是原因（已消毒，
        /// 開頭說是哪一種、帶位址）。位址上不是普通檔、或大小與 index 不同時，`akashic doctor` 的 sources 一致性也會列出（#703 R2）；
        /// 打不開、讀不完的要自己查權限。
        case localCopyUnverifiable(String)
        /// 同一筆 work 裡內容相同的另一個附件（值是它的 `path`，未消毒）這一趟沒有做完——補存或新連結失敗、work 寫不進去——這一個跟著它，
        /// 不算已連過（#703 R2 verify 第 2、17 則：先前在實跑開始之前就把這一個報成「已連過」，第一個之後失敗時同一份報告同時說完成與沒完成）。
        case followsUnfinished(String)
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

    /// `sources/` 已有這個 digest 的存檔，內容卻不是 Zotero 原檔（#703）：被截短、被換掉。**不覆寫**那一份、不補記取得記錄、不新連——
    /// 內容定址的位址上放的不是那份內容，要人處理（移走那份存檔後重跑，會以 Zotero 原檔補存）。比對逐塊算 digest；大小不同時不必讀。
    public struct StoredBlobMismatch: Equatable {
        /// Zotero 原檔（digest、大小取自它）。
        public let item: Item
        /// `sources/` 那一份的實際大小。
        public let storedBytes: Int
        /// `sources/` 那一份內容的 digest；大小與原檔不同時沒有讀它，是 nil。
        public let storedDigest: String?
        /// digest 已連在這筆 work 上（true），或這一趟本來要新連（false）。
        public let alreadyLinkedOnWork: Bool
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
    /// `sources/` 已有這個 digest、內容卻與 Zotero 原檔不符的檔（#703）。乾跑與實跑都在計畫時比對；不覆寫、不補記、不新連。
    public var storedBlobMismatch: [StoredBlobMismatch] = []
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
///   位元組在而 index 沒有條目的（孤兒 blob）只補記取得記錄（`recordRestored`，#606 R2 verify）；位元組在的（已連過、要補記、或新連結遇到
///   同一份已存過）**逐塊重算既有 blob 的 digest** 與 Zotero 原檔比對（#703），不符就列在 `storedBlobMismatch`、不覆寫、不補記、不新連；
///   blob 早就在 `sources/`（前一次跑到一半）的不重寫、不重複記取得記錄（`storeSource` 的冪等語意），這次沒寫進 index 的 Zotero 來源逐檔列在
///   `provenanceNotRecorded`（附 index 保留的 origin）。
/// - **不以舊快照覆寫**：寫 work 之前，讀可回溯閘回傳的那個檔、與計畫時 load 的快照比相等；不同（閘的時間窗裡被別的寫入者改過並 commit）就不寫、
///   記進 `writeFailed`，其餘照跑（App #609 移除面的 `changedDuringCheck` 同一條，#606 R1 verify）。
/// - **整批拒絕、零寫入的閘**（任何一個檔落地之前）：每一筆要改寫的 work 過 `writeEntry` 的全部前置（`preflightWrite`）；每個要存的 digest 過
///   `storeSource` 的前置（`preflightStoreSource`：`sources/` 沒被版控排除——blob、index 與實跑要用的那條暫存檔路徑都問，#703 R1——、git 不可用、
///   index 有壞行）；被改寫的 work 檔要已在 git 裡 commit、乾淨
///   （`assertRecordsRecoverable`——舊版只剩 git 那一份；只覆蓋**真的要被改寫**的記錄）。
/// - **逐筆略過（具名，其餘照跑）**：附件路徑不是 `storage/<KEY>/<檔名>`、檔案不在、不是普通檔、0 byte、超過 256 MiB（#703，印出大小）、
///   讀不出來、計畫之後內容變了、`sources/` 裡同一個 digest 的位置上有東西而判不出它是不是這份內容（#703 R1）；
///   無法唯一定位的 work（`unlocatableCitekeys`）。
/// - **只複製附件記錄的那一個檔**：HTML snapshot 同目錄的資源檔不複製。
/// - 不動 `attachments`、不動 `provenance`、不動書目欄位；`akashic.sources` 只追加。
///
/// **誠實邊界**：`sources/` 不進 git，別台 clone 讀到這條連結時位元組不在（§2.4.1：載入成功、可報缺席）——那台機器上重跑本命令會補回（`restoredLocally`），
/// 前提是它的 Zotero 資料目錄裡還有那個檔；單檔上限 256 MiB（`LibraryStore.maxSourceBytes`，#703——與 `store-source` 同一個常數），
/// 超過的以 stat 判斷、不讀、具名略過；內容**逐塊**讀（算 digest、複製、比對既有 blob 都是，每塊經 `LibraryStore.pump` 讀完即釋放——
/// #703 R1 之前每塊都留到行程結束、跨檔累積；不 mmap，檔案被截短時
/// mmap 會讓行程收到 SIGBUS）；計畫階段讀一遍、複製階段讀兩遍（`storeSource(contentsOf:)`：先驗 digest 與計畫相同、再逐塊複製並再算一次），
/// 三遍都從 `ZoteroStorageFile.openVerified` 交回的同一種 descriptor 讀（`O_NOFOLLOW` 開一次、判斷種類與真實位置），之間內容被換掉時以
/// digest 對不上偵測（`changedDuringRun`）；既有 blob 的比對在計畫時做，計畫到實跑之間那一份再被換掉看不到，閘之後的重讀與寫入之間也仍有一個很短的窗
/// （兩者都因為沒有 store 層的鎖）；Zotero 端的檔案之後再變（重新下載、編輯註記）不會回頭更新
/// 已複製的副本——那是另一份內容、另一個 digest，下一次跑會再連一份。**逆操作**：連錯的宣告用 `update-entry --remove-source`（#677）收回；blob 與取得記錄留在
/// `sources/`（可能被別筆引用）。
extension AkashicService {

    public func copyZoteroAttachments(zoteroDb: String?, citekeys: [String]?, apply: Bool,
                                      now: Date = Date()) throws -> ZoteroAttachmentCopyReport {
        try copyZoteroAttachments(zoteroDb: zoteroDb, citekeys: citekeys, apply: apply, now: now, afterPlanning: nil)
    }

    /// 測試接縫：`afterPlanning` 在計畫算完、第一次寫入之前呼叫（模擬「計畫之後檔案內容被換掉」）；`beforeStore` 在每一次 `storeSource` 之前呼叫，
    /// 擲錯即當成那一次存檔擲錯（模擬 I/O 失敗）。對外的入口沒有這兩個參數。
    /// `sourceLimit`（#703）是大小上限的測試接縫，預設就是唯一一份常數 `LibraryStore.maxSourceBytes`。
    func copyZoteroAttachments(zoteroDb: String?, citekeys: [String]?, apply: Bool, now: Date,
                               afterPlanning: (() throws -> Void)?,
                               beforeStore: ((ZoteroAttachmentCopyReport.Item) throws -> Void)? = nil,
                               sourceLimit: Int = LibraryStore.maxSourceBytes) throws -> ZoteroAttachmentCopyReport {
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

        // 計畫：每筆 work 算出「要新連的檔」。讀檔只為算 digest（逐塊讀，#703；不 mmap，理由見 `ZoteroStorageFile.openVerified`）。
        struct Target { var entry: Entry; var items: [ZoteroAttachmentCopyReport.Item] }
        var targets: [Target] = []
        var linkedOnWork: [ZoteroAttachmentCopyReport.Item] = []
        // 同一筆 work 內內容相同的第二個（以後）附件：跟著第一個（`lead`）的**最終**結果走——乾跑是計畫、實跑是做完之後（`resolveFollowers`）。
        // #703 R1 verify 第 11、16 則修了計畫階段的不符；R2 verify 第 2、17 則：實跑階段的失敗（補存 I/O 錯、計畫之後內容變了、work 寫不進去）
        // 先前沒有涵蓋，第二個在實跑開始之前就進了「已連過」
        var followers: [(item: ZoteroAttachmentCopyReport.Item, lead: ZoteroAttachmentCopyReport.Item)] = []
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
            var linkedLead: [String: ZoteroAttachmentCopyReport.Item] = [:]    // 已連的 digest 在這筆 work 裡只查一次、只補一次（#606 R2 verify：與新連結那一條路同形）
            var newLinkLead: [String: ZoteroAttachmentCopyReport.Item] = [:]   // 要新連的 digest：這筆 work 裡第一個

            for att in attachments where seenPaths.insert(att.path).inserted {
                switch ZoteroStorageFile.locate(dataDir: dataDir, attachmentPath: att.path, limit: sourceLimit) {
                case .refused(let why):
                    report.skipped.append(.init(citekey: entry.citekey, path: att.path, reason: .file(why)))
                case .found(let f):
                    let digest: String
                    let bytes: Int
                    switch Self.zoteroDigest(dataDir: dataDir, located: f, limit: sourceLimit) {
                    case .digest(let d, let n): (digest, bytes) = (d, n)
                    case .skip(let why):
                        report.skipped.append(.init(citekey: entry.citekey, path: att.path, reason: why))
                        continue
                    }
                    let item = ZoteroAttachmentCopyReport.Item(
                        citekey: entry.citekey, path: att.path, digest: digest, bytes: bytes,
                        mediaType: ZoteroStorageFile.mediaType(forFilename: f.url.lastPathComponent), modified: f.modified, url: f.url,
                        dataDir: dataDir, located: f)
                    if linked.insert(item.digest).inserted {
                        // #703：同一個 digest 在 sources/ 已有一份（別筆 work、store-source 存過）——比對它。只有「位址上沒東西」與
                        // 「內容就是這一份」往下走；不符、不是普通檔、讀不到都不新連、不覆寫（R1 verify 第 1、4、6、19、24 則：先前只擋
                        // `.mismatch`，位址上是目錄時 `writeBlob` 當成「已有」、照樣補記取得記錄並連上，報「已複製」）。
                        // 被擋下的從 `linked` 拿掉：同一筆裡內容相同的另一個附件照樣自己比、自己列，不被當成「這一份會存」
                        switch storedBlobCheck(item) {
                        case .absent, .matches:
                            items.append(item)
                            newLinkLead[item.digest] = item
                        case .mismatch(let stored, let storedDigest):
                            report.storedBlobMismatch.append(.init(item: item, storedBytes: stored, storedDigest: storedDigest,
                                                                   alreadyLinkedOnWork: false))
                            linked.remove(item.digest)
                        case .notRegularFile(let kind):
                            report.skipped.append(.init(citekey: item.citekey, path: item.path, reason: .localCopyUnverifiable(
                                "要新連；本機 \(LibraryStore.sourceRelativePath(digest: item.digest)) 的位置上是\(displaySafeInvisible(kind, max: 40))、不是普通檔")))
                            linked.remove(item.digest)
                        case .unreadable:
                            report.skipped.append(.init(citekey: item.citekey, path: item.path, reason: .localCopyUnverifiable(
                                "要新連；本機 \(LibraryStore.sourceRelativePath(digest: item.digest)) 讀不到（分片目錄列不出來、打不開或讀不完）")))
                            linked.remove(item.digest)
                        }
                    } else if alreadyOnWork.contains(item.digest), linkedLead[item.digest] == nil {
                        linkedOnWork.append(item)   // 連結在——位元組在不在本機，下面一次查完
                        linkedLead[item.digest] = item
                    } else if let lead = linkedLead[item.digest] ?? newLinkLead[item.digest] {
                        followers.append((item, lead))   // 同一筆內另一個附件內容相同：結果跟著它（補存、新連結都只做一次）
                    } else {
                        // 不可達（digest 在 `linked` 裡就一定有一個 lead）；萬一走到，不宣稱已連過
                        report.skipped.append(.init(citekey: item.citekey, path: item.path, reason: .followsUnfinished(item.path)))
                    }
                }
            }
            if !items.isEmpty { targets.append(Target(entry: entry, items: items)) }
        }
        // 已連過的：位元組在本機才算做完（`sources/` 不進 git，別台 clone 的連結在、位元組不在）。一次查完所有 digest（#614 的 `sourcePresence`）。
        // 同一筆內內容相同的其他附件由 `resolveFollowers` 照這一個的最終結果走。
        func skipLinked(_ item: ZoteroAttachmentCopyReport.Item, _ why: String) {
            report.skipped.append(.init(citekey: item.citekey, path: item.path, reason: .localCopyUnverifiable(why)))
        }
        if !linkedOnWork.isEmpty {
            do {
                let presence = try store.sourcePresence(digests: Array(Set(linkedOnWork.map(\.digest))))
                for item in linkedOnWork {
                    let address = LibraryStore.sourceRelativePath(digest: item.digest)
                    switch presence[item.digest] {
                    case .stored?, .unindexed?, .sizeMismatch?:
                        // #703：「已連過」不再只看在不在——逐塊比對那一份與 Zotero 原檔。不符不覆寫、不補記；判不出來具名略過。
                        // index 記的大小不同（`.sizeMismatch`，R2）也在這裡以 Zotero 原檔為準比一次：那一份若就是原檔，錯的是 index 那一列（doctor 報它）
                        switch storedBlobCheck(item) {
                        case .matches:
                            if case .unindexed? = presence[item.digest] {
                                report.recordRestored.append(item)   // 位元組在、index 沒有條目：補記取得記錄（#606 R2 verify）
                            } else {
                                report.alreadyLinked.append(item)
                            }
                        case .mismatch(let stored, let storedDigest):
                            report.storedBlobMismatch.append(.init(item: item, storedBytes: stored, storedDigest: storedDigest,
                                                                   alreadyLinkedOnWork: true))
                        case .notRegularFile(let kind):
                            skipLinked(item, "已連過；本機 \(address) 的位置上是\(displaySafeInvisible(kind, max: 40))、不是普通檔")
                        case .absent, .unreadable:
                            skipLinked(item, "已連過；本機 \(address) 讀不到（分片目錄列不出來、打不開或讀不完）")
                        }
                    case .absent?:
                        report.restoredLocally.append(item)
                    case .notRegularFile(let kind)?:
                        skipLinked(item, "已連過；本機 \(address) 的位置上是\(displaySafeInvisible(kind, max: 40))、不是普通檔")
                    case .unreadable?, nil:
                        skipLinked(item, "已連過；本機 \(address) 所在的分片目錄讀不到")
                    }
                }
            } catch {
                let why = "已連過；" + displaySafeError(error, max: 600)
                for item in linkedOnWork { skipLinked(item, why) }
            }
        }
        report.planned = targets.flatMap(\.items)
        try afterPlanning?()

        // 閘：任何檔落地之前。乾跑把拒絕當預告放進報告，實跑擲錯。
        var gatePaths: [UUID: String] = [:]
        // 每個要存的 digest 一個暫存檔 token：預演問排除的就是實跑會建立的那條暫存路徑（#703 R1 verify 第 3、17、21 則）
        var temporaryTokens: [String: String] = [:]
        for digest in Set(targets.flatMap { $0.items.map(\.digest) } + (report.restoredLocally + report.recordRestored).map(\.digest)) {
            temporaryTokens[digest] = UUID().uuidString
        }
        do {
            gatePaths = try assertZoteroCopyWritable(targets.map { ($0.entry, $0.items) },
                                                     restoreDigests: (report.restoredLocally + report.recordRestored).map(\.digest),
                                                     temporaryTokens: temporaryTokens)
        } catch {
            if apply { throw error }
            report.applyRefusal = displaySafeError(error, max: 4_096)
        }
        guard apply, !targets.isEmpty || !report.restoredLocally.isEmpty || !report.recordRestored.isEmpty else {
            Self.resolveFollowers(followers, in: &report)   // 乾跑：跟著第一個的**計畫**
            return report
        }
        report.applied = true

        // 實跑：逐筆——先存這一筆的檔、再寫這一筆的連結。單筆失敗收容（`import-zotero` 的形），其餘照跑；重跑會補上沒做完的。
        var plannedAfter: [ZoteroAttachmentCopyReport.Item] = []
        let stamp = ISO8601DateFormatter().string(from: now)
        var notRecorded: [(item: ZoteroAttachmentCopyReport.Item, bytesWereAlreadyStored: Bool)] = []
        func fail(_ citekey: String, _ why: String) {
            report.writeFailed[citekey] = report.writeFailed[citekey].map { $0 + "；" + why } ?? why
        }
        /// 再開一次、逐塊存（#703）：`storeSource(contentsOf:)` 先驗 digest 要與計畫相同（不同就是被換掉了，略過、不存、不連），
        /// 再逐塊複製並再算一次。回傳存檔的收據；略過回 nil。
        func storeOne(_ item: ZoteroAttachmentCopyReport.Item) throws -> LibraryStore.SourceReceipt? {
            func skip(_ reason: ZoteroAttachmentCopyReport.SkipReason) -> LibraryStore.SourceReceipt? {
                report.skipped.append(.init(citekey: item.citekey, path: item.path, reason: reason))
                return nil
            }
            let handle: FileHandle
            switch ZoteroStorageFile.openVerified(dataDir: item.dataDir, located: item.located, limit: sourceLimit) {
            case .file(let h, _): handle = h
            case .refused(let why): return skip(.file(why))
            case .unreadable: return skip(.unreadable)
            }
            defer { try? handle.close() }
            try beforeStore?(item)
            let outcome = try store.storeSource(contentsOf: handle, provenance: LibraryStore.SourceProvenance(
                mediaType: item.mediaType, retrieved: stamp,
                origin: "zotero:\(item.path)", acquisition: "zotero-storage-copy",
                note: Self.zoteroCopyNote(citekey: item.citekey, modified: item.modified)),
                expectedDigest: item.digest, limit: sourceLimit, temporaryToken: temporaryTokens[item.digest])
            let receipt: LibraryStore.SourceReceipt
            switch outcome {
            case .stored(let r): receipt = r
            case .refused(.changed): return skip(.changedDuringRun)
            case .refused(.tooLarge(let bytes)): return skip(.file(.tooLarge(bytes)))
            case .refused(.empty): return skip(.file(.empty))
            }
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
        Self.resolveFollowers(followers, in: &report)   // 實跑：跟著第一個**做完之後**的結果
        if !report.written.isEmpty {
            do { try LibraryIndex(store: store).rebuild() } catch {
                report.indexRebuildFailure = displaySafeError(error, max: 1_024)
            }
        }
        return report
    }

    /// 同一筆 work 內內容相同的其他附件跟著第一個（`lead`）的結果走（#703 R1 verify 第 11、16 則；R2 verify 第 2、17 則）。
    /// 呼叫時機：乾跑在計畫之後（跟著計畫）、實跑在全部做完之後（跟著最終結果）——所以實跑時第一個補存失敗、內容變了、work 寫不進去，
    /// 這一個不會留在「已連過」。第一個以 (citekey, path) 找：
    ///
    /// - 做完或計畫要做（`alreadyLinked`、`planned`、`restoredLocally`、`recordRestored`、`provenanceNotRecorded`——後者是位元組存了、
    ///   來源沒記）→ 已連過；
    /// - 內容不符（`storedBlobMismatch`）→ 同樣列不符；因為位址上那一份判不出來而略過（`localCopyUnverifiable`）→ 同一個原因；
    ///   補存失敗（`restoreFailed`）→ 同一則訊息——這三種說的是**同一個 digest 的位址**，對這一個一樣成立；
    /// - 因為第一個**自己的檔**而略過（計畫之後內容變了、檔案不在、讀不出來……）或都不在（新連結的 work 寫不進去，那一筆在 `writeFailed`）
    ///   → `followsUnfinished(第一個的 path)`：那個原因不是這一個的，照抄會說錯話；只說它跟著第一個、不算已連過。
    static func resolveFollowers(_ followers: [(item: ZoteroAttachmentCopyReport.Item, lead: ZoteroAttachmentCopyReport.Item)],
                                 in report: inout ZoteroAttachmentCopyReport) {
        guard !followers.isEmpty else { return }
        func key(_ citekey: String, _ path: String) -> String { citekey + "\u{0}" + path }
        var done = Set<String>()
        for i in report.alreadyLinked + report.planned + report.restoredLocally + report.recordRestored { done.insert(key(i.citekey, i.path)) }
        for n in report.provenanceNotRecorded { done.insert(key(n.item.citekey, n.item.path)) }
        var mismatch: [String: ZoteroAttachmentCopyReport.StoredBlobMismatch] = [:]
        for m in report.storedBlobMismatch { mismatch[key(m.item.citekey, m.item.path)] = m }
        var skippedBy: [String: ZoteroAttachmentCopyReport.SkipReason] = [:]
        for s in report.skipped where skippedBy[key(s.citekey, s.path)] == nil { skippedBy[key(s.citekey, s.path)] = s.reason }
        var restoreFailed: [String: String] = [:]
        for f in report.restoreFailed { restoreFailed[key(f.item.citekey, f.item.path)] = f.message }
        for (item, lead) in followers {
            let k = key(lead.citekey, lead.path)
            if done.contains(k) {
                report.alreadyLinked.append(item)
            } else if let m = mismatch[k] {
                report.storedBlobMismatch.append(.init(item: item, storedBytes: m.storedBytes, storedDigest: m.storedDigest,
                                                       alreadyLinkedOnWork: m.alreadyLinkedOnWork))
            } else if let reason = skippedBy[k], case .localCopyUnverifiable = reason {
                report.skipped.append(.init(citekey: item.citekey, path: item.path, reason: reason))
            } else if let message = restoreFailed[k] {
                report.restoreFailed.append(.init(item: item, message: message))
            } else {
                report.skipped.append(.init(citekey: item.citekey, path: item.path, reason: .followsUnfinished(lead.path)))
            }
        }
    }

    /// 計畫時算一個 Zotero 附件的 digest 的結果（#703）。
    enum ZoteroDigest {
        case digest(String, bytes: Int)
        case skip(ZoteroAttachmentCopyReport.SkipReason)
    }

    /// 從 `openVerified` 交回的 descriptor **逐塊**算 digest（#703：不整份讀進記憶體——乾跑也一樣）。讀的時候長大超過上限、被清空、
    /// 讀失敗，各自是具名的略過原因。
    static func zoteroDigest(dataDir: URL, located: ZoteroStorageFile.Located, limit: Int) -> ZoteroDigest {
        switch ZoteroStorageFile.openVerified(dataDir: dataDir, located: located, limit: limit) {
        case .refused(let why): return .skip(.file(why))
        case .unreadable: return .skip(.unreadable)
        case .file(let handle, _):
            defer { try? handle.close() }
            switch try? LibraryStore.contentDigest(reading: handle, limit: limit) {
            case .digest(_, let n)? where n == 0: return .skip(.file(.empty))
            case .digest(let d, let n)?: return .digest(d, bytes: n)
            case .overLimit(let n)?: return .skip(.file(.tooLarge(n)))
            case nil: return .skip(.unreadable)
            }
        }
    }

    /// 本機 `sources/` 裡同一個 digest 的那一份與 Zotero 原檔的比對（#703）。判不出來（digest 形狀不合——計畫算的不會）當成讀不到。
    func storedBlobCheck(_ item: ZoteroAttachmentCopyReport.Item) -> LibraryStore.StoredBlobCheck {
        (try? store.checkStoredBlob(digest: item.digest, expectedBytes: item.bytes)) ?? .unreadable
    }

    /// `sources/index.jsonl` 的 note：哪個命令、哪一筆 work、Zotero 端檔案的修改時間（不是取得時間——`retrieved` 是複製當下）。
    static func zoteroCopyNote(citekey: String, modified: Date?) -> String {
        var s = "自 Zotero 資料目錄複製（akashic copy-zotero-attachments，#606）；work \(citekey)"
        if let modified { s += "；檔案修改時間 \(ISO8601DateFormatter().string(from: modified))" }
        return s
    }

    /// 寫入前的三道閘，乾跑與實跑共用（見型別 doc 的「整批拒絕、零寫入的閘」）。回傳可回溯閘解析出的記錄檔路徑（寫入前重讀用）。
    /// `restoreDigests`（已連過、本機缺位元組的）只過存檔前置——它們不改寫 work，不過可回溯閘。
    /// `temporaryTokens`：每個 digest 實跑要用的暫存檔 token，存檔前置問的是那條暫存路徑（#703 R1）。
    private func assertZoteroCopyWritable(_ targets: [(entry: Entry, items: [ZoteroAttachmentCopyReport.Item])],
                                          restoreDigests: [String],
                                          temporaryTokens: [String: String]) throws -> [UUID: String] {
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
                if let token = temporaryTokens[digest] {
                    try store.preflightStoreSource(digest: digest, temporaryToken: token)
                } else {
                    try store.preflightStoreSource(digest: digest)
                }
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
