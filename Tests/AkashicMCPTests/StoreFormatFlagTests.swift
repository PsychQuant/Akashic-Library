import XCTest
@testable import AkashicStoreIO

/// `akashic-mcp --store-format`：印出編譯進去的 `StoreVersion.supported` 後結束（#630）。
///
/// 發布腳本用它做冒煙檢查：剛建好的產物回報的 format 必須等於原始碼的值。v0.12.0 出貨的是
/// 兩週前的舊產物（腳本從舊的建置路徑拿檔、只檢查存在），而它唯一被發現的方式是使用者的
/// store 被拒——這個旗標讓同一個錯位在發布當下就紅。
final class StoreFormatFlagTests: XCTestCase {
    private var productsDirectory: URL {
        for bundle in Bundle.allBundles where bundle.bundlePath.hasSuffix(".xctest") {
            return bundle.bundleURL.deletingLastPathComponent()
        }
        fatalError("找不到 products directory")
    }

    func testStoreFormatFlagPrintsCompiledSupportedFormatAndExits() throws {
        let p = Process()
        p.executableURL = productsDirectory.appendingPathComponent("akashic-mcp")
        p.arguments = ["--store-format"]
        // stdin 為空：若旗標沒被處理，server 會讀到 EOF 後結束、stdout 為空——測試照樣紅，不會卡住
        p.standardInput = FileHandle.nullDevice
        let out = Pipe()
        p.standardOutput = out
        p.standardError = Pipe()
        try p.run()
        let deadline = Date().addingTimeInterval(10)
        while p.isRunning && Date() < deadline { usleep(50_000) }
        if p.isRunning { p.terminate(); XCTFail("akashic-mcp --store-format 10 秒內沒有結束"); return }
        let text = String(data: out.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        XCTAssertEqual(p.terminationStatus, 0)
        XCTAssertEqual(text, String(StoreVersion.supported))
    }
}
