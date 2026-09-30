import Foundation
import CryptoKit

/// 逐塊讀取（#703，使用者 2026-09-30 裁決「SHA-256 逐塊計算」）：`sources/` 的寫入與比對不再把整份內容讀進記憶體。
///
/// 所有讀內容的路徑都經 `LibraryStore.pump`——每次至多 `sourceChunkBytes`。上限（`maxSourceBytes`）與存檔的兩遍流程在
/// `SourceStore.swift`；這裡只有讀取與 digest。
public extension LibraryStore {

    /// 逐塊讀取的塊大小（#703）：算 digest、複製進 `sources/`、比對既有 blob，一次都只拿這麼多——記憶體用量與檔案大小無關。
    static let sourceChunkBytes = 1 << 20

    /// 逐塊算 digest 的結果（#703）。
    enum StreamedDigest: Equatable {
        /// 讀完了：digest 與實際讀到的大小（可能是 0——空內容由呼叫端判）。
        case digest(String, bytes: Int)
        /// 讀到超過 `limit` 就停了，沒有算完。值是停下時讀到的量與當下 `fstat` 的大小取大者（檔案在讀的時候長大）。
        case overLimit(bytes: Int)
    }

    /// 從 handle 的**開頭**逐塊讀到底算 digest（#703）：一次只拿 `sourceChunkBytes`，記憶體與檔案大小無關；讀到超過 `limit` 就停。
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
    internal static func pump<C: SourceChunks>(_ source: inout C, limit: Int, _ body: (Data) throws -> Void) throws -> PumpResult {
        var total = 0
        while let chunk = try source.next(upTo: sourceChunkBytes), !chunk.isEmpty {
            total += chunk.count
            if total > limit { return .exceeded(bytesRead: total) }
            try body(chunk)
        }
        return .complete(bytes: total)
    }
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

