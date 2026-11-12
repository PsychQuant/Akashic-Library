import Foundation
#if os(Linux)
import Glibc
#else
import Darwin
#endif

/// Linux 的排他改名 `renameat2(AT_FDCWD, from, AT_FDCWD, to, RENAME_NOREPLACE)`（#794）：`sources/` 放置閘在 Linux 的第一步，
/// 對應 macOS 的 `renamex_np(RENAME_EXCL)`——原子、目的地在就 `EEXIST`、從不取代目的地。
///
/// Swift 的 Glibc 模組不露出 `renameat2`（Swift 6.4.2 量：`cannot find 'renameat2' in scope`），所以執行期以 `dlopen(nil, RTLD_NOW)` 加
/// `dlsym("renameat2")` 取得、轉成 C 函式型別呼叫。本 repo 因此不加任何 C 程式碼（design「本 repo 不新增任何 C 程式碼」）。
/// **找不到符號回 `ENOSYS`**（glibc 2.28 以前沒有這個包裝），與 kernel 3.15 以前回的 `ENOSYS` 走同一條退路（`link(2)`）。
///
/// `call` 在兩個平台都編譯，讓「找不到符號」那一條在 macOS 的測試裡也走得到（`call(nil)`）；真正查找符號的 `symbol` 只在 Linux。
internal enum LinuxRenameNoReplace {
    /// `RENAME_NOREPLACE`：Linux uapi `include/uapi/linux/fs.h` 的 `#define RENAME_NOREPLACE (1 << 0)`。
    static let renameNoReplace: UInt32 = 1
    /// `AT_FDCWD`：Linux uapi `include/uapi/linux/fcntl.h` 的 `#define AT_FDCWD -100`。
    static let atFDCWD: Int32 = -100

    typealias Renameat2 = @convention(c) (Int32, UnsafePointer<CChar>?, Int32, UnsafePointer<CChar>?, UInt32) -> Int32

    /// 由查到的符號做出放置閘要的呼叫：回 0 或 errno。符號是 nil（找不到）時一律回 `ENOSYS`。
    static func call(_ symbol: UnsafeMutableRawPointer?) -> @Sendable (_ from: String, _ to: String) -> Int32 {
        guard let symbol else { return { _, _ in ENOSYS } }
        let renameat2 = unsafeBitCast(symbol, to: Renameat2.self)
        return { from, to in renameat2(atFDCWD, from, atFDCWD, to, renameNoReplace) == 0 ? 0 : errno }
    }

    #if os(Linux)
    /// 行程裡已載入的 `renameat2`（glibc 2.28 起有）。`dlopen(nil)` 的 handle 不關：它指的是主程式本身。
    static let symbol: UnsafeMutableRawPointer? = dlopen(nil, RTLD_NOW).flatMap { dlsym($0, "renameat2") }
    #endif
}
