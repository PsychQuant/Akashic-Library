import Foundation
import Darwin

/// `sources/` 存檔的暫存檔與「放上位址」那一步（#703；R1 verify 之後從 `SourceStore.swift` 拆出——那個檔加上這一輪會超過 800 行）。
///
/// 暫存檔的檔名只有一個形狀（`temporaryBlobName`），預演（`preflightStoreSource`）、建立（`writeBlob`）、殘留的報告
/// （`auditSourceIndex` 的 `strayTemporaryFiles`）都讀它。
extension LibraryStore {

    /// 存檔暫存檔的檔名（#703）：`.<62 hex>.incoming-<token>`，住在 blob 同一個分片目錄裡。`preflightStoreSource` 問排除的、
    /// `writeBlob` 建立的、`auditSourceIndex` 認得的都是這一個形狀（R1 verify 第 3、17、21 則：預演先前沒問暫存路徑，
    /// 乾跑說可以、實跑才在暫存路徑被拒，而多筆操作已經寫了前面幾筆）。
    internal static func temporaryBlobName(digest: String, token: String) -> String {
        ".\(digest.dropFirst("sha256:".count).dropFirst(2)).incoming-\(token)"
    }

    /// 分片目錄裡的一個檔名是不是 `temporaryBlobName` 的形狀（token 是 UUID）。
    internal static func isTemporaryBlobName(_ name: String) -> Bool {
        guard name.hasPrefix("."), let r = name.range(of: ".incoming-") else { return false }
        let rest = name[name.index(after: name.startIndex)..<r.lowerBound]
        return rest.count == 62 && rest.allSatisfy { "0123456789abcdef".contains($0) }
            && UUID(uuidString: String(name[r.upperBound...])) != nil
    }

    /// 把暫存檔放到位址上的三個系統呼叫，各回 0 或 errno（#703 R1 verify 第 5、9、12、33 則）。測試接縫：換掉其中一個，模擬
    /// 不支援 `RENAME_EXCL` 的檔案系統（2026-09-30 在磁碟映像上實測：exFAT 與 FAT32 的 `renamex_np(RENAME_EXCL)` 與 `link(2)`
    /// 都回 `ENOTSUP`，一般的 `rename(2)` 可以）。
    internal struct BlobPlacement {
        var renameExclusive: @Sendable (_ from: String, _ to: String) -> Int32
        var hardLink: @Sendable (_ from: String, _ to: String) -> Int32
        var plainRename: @Sendable (_ from: String, _ to: String) -> Int32
        static let system = BlobPlacement(
            renameExclusive: { renamex_np($0, $1, UInt32(RENAME_EXCL)) == 0 ? 0 : errno },
            hardLink: { Darwin.link($0, $1) == 0 ? 0 : errno },
            plainRename: { Darwin.rename($0, $1) == 0 ? 0 : errno })
    }

    /// 放上位址的結果：放了，或位址上已經有東西（不覆寫）。
    internal enum Placed { case placed, alreadyThere }

    /// 檔案系統「不支援這個呼叫」的 errno（封閉列舉）：`ENOTSUP`／`EOPNOTSUPP`（實測 exFAT、FAT32）；`renamex_np` 另收 `EINVAL`
    /// （手冊：旗標值不被接受——SMB／NFS 掛載可能以它回應，沒有實測），`link` 另收 `EPERM`（Linux 與部分網路檔案系統以它表示不支援
    /// hard link；macOS 手冊的 `EPERM` 只指目錄，暫存檔不是目錄）。其餘 errno 不退，直接具名擲出。
    private static func placementUnsupported(_ code: Int32, orAlso extra: Int32) -> Bool {
        code == ENOTSUP || code == EOPNOTSUPP || code == extra
    }

    /// 系統給的錯誤說明（固定英文字串，不含使用者資料）。
    private static func errnoText(_ code: Int32) -> String { "errno \(code)，\(String(cString: strerror(code)))" }

    /// 暫存檔放上位址（#703 R1）。三條路依序，每一條都**不覆寫**位址上已有的東西：
    ///
    /// 1. `renamex_np(RENAME_EXCL)`——原子、排他。`EEXIST`＝有人先放了。
    /// 2. 檔案系統不支援 → `link(2)`＋刪掉暫存名——同樣排他（目的地在就 `EEXIST`）。
    /// 3. 也不支援 → `lstat` 確認位址上沒有東西，再 `rename(2)`。**這一條不是原子的**：`lstat` 與 `rename` 之間別的行程放進來的
    ///    同一個位址會被取代。兩邊都經過兩遍 digest 驗證、位址是內容的 digest，所以取代的是同一份內容；唯一的例外是那一瞬間有人
    ///    放進一份**錯的**內容——它會被這一份對的取代。exFAT／FAT32 上只有這一條可用（實測），殘留的競態寫在 changelog 的誠實邊界。
    ///
    /// 三條都走不通時具名擲出，說出三個 errno。
    internal func placeTemporaryBlob(_ tmp: String, at dest: String, digest: String,
                                    placement: BlobPlacement) throws -> Placed {
        func fail(_ why: String) -> StoreIOError {
            StoreIOError.invalidInput(what: "sources/ 存檔", why: "\(why)——digest \(digest) 沒有存")   // display-safe-exempt: why 是本函式組的固定句與 errno 說明；digest 是本函式的呼叫端算的 SHA-256 十六進位
        }
        let excl = placement.renameExclusive(tmp, dest)
        if excl == 0 { return .placed }
        if excl == EEXIST { return .alreadyThere }
        guard Self.placementUnsupported(excl, orAlso: EINVAL) else {
            throw fail("暫存檔無法放到位址上（renamex_np RENAME_EXCL：\(Self.errnoText(excl))）")
        }
        let ln = placement.hardLink(tmp, dest)
        if ln == 0 {
            unlink(tmp)   // 失敗的話暫存名留著：doctor 會把它報成殘留的暫存檔，位址上的那一份不受影響
            return .placed
        }
        if ln == EEXIST { return .alreadyThere }
        guard Self.placementUnsupported(ln, orAlso: EPERM) else {
            throw fail("這個檔案系統不支援排他改名（RENAME_EXCL：\(Self.errnoText(excl))），hard link 也失敗（\(Self.errnoText(ln))）")
        }
        var st = stat()
        if lstat(dest, &st) == 0 { return .alreadyThere }
        let gone = errno
        guard gone == ENOENT else {
            throw fail("這個檔案系統不支援排他改名與 hard link（\(Self.errnoText(excl))；\(Self.errnoText(ln))），"
                + "而位址上有沒有東西也判不出來（lstat：\(Self.errnoText(gone))）")
        }
        let rn = placement.plainRename(tmp, dest)
        guard rn == 0 else {
            throw fail("這個檔案系統不支援排他改名與 hard link（\(Self.errnoText(excl))；\(Self.errnoText(ln))），"
                + "一般改名也失敗（\(Self.errnoText(rn))）")
        }
        return .placed
    }
}
