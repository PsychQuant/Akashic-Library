import Foundation

/// 把 work 的附件記錄（`attachments: [{zotero: storage/<KEY>/<檔名>}]`）解成 Zotero 資料目錄裡的一個普通檔（#606）。
///
/// 路徑取自 store 的 YAML——`attachments` 的 path 在載入時只驗是字串，手改或舊 binary 可以寫成任何東西。所以這一層是**未信任輸入**的邊界：
/// 複製它的位元組進 `sources/` 之前，先確認它是資料目錄的 `storage/` 底下的一個非空普通檔；不是就**具名拒絕**，不猜、不跟 symlink。
public enum ZoteroStorageFile {

    /// 定位成功：檔案的位置、大小與修改時間。
    public struct Located: Equatable {
        public let url: URL
        public let bytes: Int
        public let modified: Date?
    }

    /// 定位不到的原因。封閉列舉，每個都是「這一筆略過、其餘照跑」，不是整批拒絕。
    public enum Refusal: Equatable {
        /// 路徑不是恰好 `storage/<KEY>/<檔名>` 三段（含 `..`、`.`、空段、絕對路徑、NUL）。**不進檔案系統**。
        case badPath
        /// 檔案不存在——Zotero 資料目錄沒同步、檔案被刪、或這個 KEY 的儲存目錄不在這台機器上。
        case missing
        /// 真實位置在 `storage/` 之外（KEY 目錄是指出去的 symlink）。
        case outsideStorage
        /// 位置上有東西、但不是普通檔（值是給人看的種類名：目錄、symlink、特殊檔案）。
        case notRegularFile(String)
        /// 0 byte——空內容的 digest 不指認任何一份存檔（#546）。
        case empty
    }

    /// 定位的結果。刻意不用 `Result`／`Error`：拒絕是這一層的**正常輸出**（每一筆各自略過），不是擲出的錯誤。
    public enum Location: Equatable {
        case found(Located)
        case refused(Refusal)
    }

    /// `attachmentPath` 相對 `dataDir`（`zotero.sqlite` 所在的目錄）。
    public static func locate(dataDir: URL, attachmentPath: String) -> Location {
        let parts = attachmentPath.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
        guard parts.count == 3, parts[0] == "storage",
              parts.allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." && !$0.contains("\u{0}") }) else {
            return .refused(.badPath)
        }
        let storage = dataDir.appendingPathComponent("storage")
        let url = storage.appendingPathComponent(parts[1]).appendingPathComponent(parts[2])
        let fm = FileManager.default
        // lstat 語意（`attributesOfItem` 不跟隨最後一段的 symlink）：拿得到屬性就是「那個位置上有東西」，種類要是普通檔
        guard let attrs = try? fm.attributesOfItem(atPath: url.path) else { return .refused(.missing) }
        if let type = attrs[.type] as? FileAttributeType, type != .typeRegular {
            let name = type == .typeDirectory ? "目錄" : type == .typeSymbolicLink ? "symlink" : "特殊檔案"
            return .refused(.notRegularFile(name))
        }
        // 檔案本身是普通檔之後，還要它的**真實位置**在 storage/ 之內：`storage/` 自己可以是 symlink（把儲存區放別的磁碟是常見用法），
        // 所以比的是兩邊各自解開之後的路徑；KEY 目錄若是指出去的 symlink，這裡會不等。
        let realStorage = storage.resolvingSymlinksInPath().standardizedFileURL.path
        let realFile = url.resolvingSymlinksInPath().standardizedFileURL.path
        guard realFile.hasPrefix(realStorage + "/") else { return .refused(.outsideStorage) }
        let size = (attrs[.size] as? NSNumber)?.intValue ?? 0
        guard size > 0 else { return .refused(.empty) }
        return .found(Located(url: url, bytes: size, modified: attrs[.modificationDate] as? Date))
    }

    /// 由副檔名推 media type；認不得的是 `application/octet-stream`。Zotero 的 `itemAttachments.contentType` 不在附件記錄裡
    /// （`attachments` 只存 path），所以這裡只能看檔名——它只進 `sources/index.jsonl` 的 `media-type` 欄位，不影響 digest 與身分。
    public static func mediaType(forFilename name: String) -> String {
        switch (name as NSString).pathExtension.lowercased() {
        case "pdf": return "application/pdf"
        case "html", "htm": return "text/html"
        case "txt": return "text/plain"
        case "md": return "text/markdown"
        case "csv": return "text/csv"
        case "xml": return "application/xml"
        case "json": return "application/json"
        case "epub": return "application/epub+zip"
        case "doc": return "application/msword"
        case "docx": return "application/vnd.openxmlformats-officedocument.wordprocessingml.document"
        case "xls": return "application/vnd.ms-excel"
        case "xlsx": return "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet"
        case "ppt": return "application/vnd.ms-powerpoint"
        case "pptx": return "application/vnd.openxmlformats-officedocument.presentationml.presentation"
        case "png": return "image/png"
        case "jpg", "jpeg": return "image/jpeg"
        case "gif": return "image/gif"
        case "svg": return "image/svg+xml"
        case "zip": return "application/zip"
        default: return "application/octet-stream"
        }
    }
}
