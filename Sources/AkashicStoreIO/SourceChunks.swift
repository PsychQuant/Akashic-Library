import Foundation
import CryptoKit

/// 逐塊讀取（#703，使用者 2026-09-30 裁決「SHA-256 逐塊計算」）：`sources/` 的寫入與比對不再把整份內容讀進記憶體。
///
/// 所有讀內容的路徑都經 `LibraryStore.pump`——每次至多 `sourceChunkBytes`，而且每一塊在自己的 autorelease pool 裡讀、交出、釋放
/// （R1 verify：只逐塊不夠，見 `pump`）。上限（`maxSourceBytes`）與存檔的兩遍流程在 `SourceStore.swift`；這裡只有讀取與 digest。
public extension LibraryStore {

    /// 逐塊讀取的塊大小（#703）：算 digest、複製進 `sources/`、比對既有 blob，一次都只拿這麼多。記憶體的界要這個加上 `pump` 的
    /// 逐塊 autorelease pool 才成立——`SourceIntakeMemoryCLITests` 以真 binary 的尖峰 RSS 釘住。
    static let sourceChunkBytes = 1 << 20

    /// 逐塊算 digest 的結果（#703）。
    enum StreamedDigest: Equatable {
        /// 讀完了：digest 與實際讀到的大小（可能是 0——空內容由呼叫端判）。
        case digest(String, bytes: Int)
        /// 讀到超過 `limit` 就停了，沒有算完。值是停下時讀到的量與當下 `fstat` 的大小取大者（檔案在讀的時候長大）。
        case overLimit(bytes: Int)
    }

    /// 從 handle 的**開頭**逐塊讀到底算 digest（#703）：一次只拿 `sourceChunkBytes`（經 `pump`，每塊讀完即釋放）；讀到超過 `limit` 就停。
    /// 讀失敗擲出（呼叫端當成讀不到）。公式與 `contentDigest(of:)` 同一份。
    static func contentDigest(reading handle: FileHandle, limit: Int = LibraryStore.maxSourceBytes) throws -> StreamedDigest {
        var chunks = HandleChunks(handle: handle)
        try chunks.rewind()
        return try streamDigest(&chunks, limit: limit)
    }

    internal static func streamDigest<C: SourceChunks>(_ source: inout C, limit: Int) throws -> StreamedDigest {
        var hasher = SHA256()
        switch try pump(&source, limit: limit, { hasher.update(data: $0) }) {
        case .exceeded(let n): return .overLimit(bytes: max(n, source.currentSize() ?? n))
        case .complete(let n): return .digest(digestText(hasher.finalize()), bytes: n)
        }
    }

    /// 逐塊讀到底（#703 的唯一一個讀取迴圈）：每塊至多 `sourceChunkBytes`、交給 `body`；總量超過 `limit` 就停（那一塊不交出去）。
    ///
    /// **每一塊在自己的 autorelease pool 裡讀、交出、釋放**（#703 R1 verify 第 2、8 則）。`FileHandle.read(upToCount:)` 回的是
    /// autoreleased 的 NSData，而 CLI 與同步呼叫端沒有外層的 pool 會排水——不包的話每一塊都留到行程結束：實測改動前的
    /// `store-source` 存 128 MiB 的檔尖峰 RSS 284,557,312 bytes（約 2.1 倍，兩遍各留一份），`copy-zotero-attachments --apply`
    /// 跨檔累積（6 個 100 MB 的附件 1.92 GB）。只逐塊請求不夠：`testDigestAndCopyNeverAskForMoreThanOneChunk` 證的是每次只要一塊，
    /// 量不到留住了幾塊；記憶體由 `SourceIntakeMemoryCLITests` 以真 binary 的尖峰 RSS 釘住。`body`（寫暫存檔、更新 hasher）
    /// 也在同一個 pool 裡——它若經 Foundation 產生 autoreleased 物件，同樣每塊排掉。
    internal static func pump<C: SourceChunks>(_ source: inout C, limit: Int, _ body: (Data) throws -> Void) throws -> PumpResult {
        var total = 0
        while true {
            let step: PumpStep = try autoreleasepool {
                guard let chunk = try source.next(upTo: sourceChunkBytes), !chunk.isEmpty else { return .end }
                total += chunk.count
                if total > limit { return .exceeded }
                try body(chunk)
                return .more
            }
            switch step {
            case .more: continue
            case .end: return .complete(bytes: total)
            case .exceeded: return .exceeded(bytesRead: total)
            }
        }
    }

    /// `pump` 每一塊的結果（pool 裡算、pool 外分支——回傳值不能是 autoreleased 的東西）。
    private enum PumpStep { case more, end, exceeded }
}

/// 逐塊讀取的結果（#703）。
internal enum PumpResult: Equatable {
    case complete(bytes: Int)
    /// 讀到超過上限就停了；值是停下時讀到的量。
    case exceeded(bytesRead: Int)
}

/// 可以從頭讀兩遍的內容來源（#703）：一遍算 digest、一遍複製進 `sources/`。每次至多拿呼叫端要的量——`LibraryStore.pump` 只要一塊。
internal protocol SourceChunks {
    /// 目前的大小；判不出來回 nil（就不做讀取之前的大小判斷，只靠讀的時候數）。
    func currentSize() -> Int?
    /// 回到開頭。
    mutating func rewind() throws
    /// 下一塊，至多 `upTo` bytes；讀完回 nil 或空。
    mutating func next(upTo: Int) throws -> Data?
}

/// 已經在記憶體裡的內容。
internal struct DataChunks: SourceChunks {
    let data: Data
    private var offset: Data.Index
    init(data: Data) {
        self.data = data
        self.offset = data.startIndex
    }
    func currentSize() -> Int? { data.count }
    mutating func rewind() throws { offset = data.startIndex }
    mutating func next(upTo n: Int) throws -> Data? {
        guard offset < data.endIndex else { return nil }
        let end = data.index(offset, offsetBy: min(n, data.endIndex - offset))
        defer { offset = end }
        return data.subdata(in: offset..<end)
    }
}

/// 一個已開啟的普通檔。大小以 `fstat` 問 descriptor（不是路徑）；讀以 `read(upToCount:)`，一次至多一塊。
internal struct HandleChunks: SourceChunks {
    let handle: FileHandle
    func currentSize() -> Int? {
        var st = stat()
        guard fstat(handle.fileDescriptor, &st) == 0 else { return nil }
        return Int(st.st_size)
    }
    mutating func rewind() throws { try handle.seek(toOffset: 0) }
    mutating func next(upTo n: Int) throws -> Data? { try handle.read(upToCount: n) }
}

