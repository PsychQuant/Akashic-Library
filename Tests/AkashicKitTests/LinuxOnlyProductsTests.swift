import Foundation
import XCTest

/// #794：swift-crypto 與 swift-toolchain-sqlite 對每個平台宣告、product 只在 Linux 掛上（`Package.swift` 檔頭）。
/// 這支測試在 macOS 驗「只在 Linux 掛上」的那一半：建置目錄裡沒有這兩個套件編出來的任何東西，
/// macOS 連的仍是系統的 SQLite3 與 CryptoKit。
///
/// needle 不只 spec 寫的 `CCryptoBoringSSL`：swift-crypto 的 manifest 在 Apple 平台本來就不編 BoringSSL
/// （它的依賴以 `.when(platforms: [.linux, .android, .windows, .wasi, .openbsd])` 掛上），所以
/// 只找 `CCryptoBoringSSL` 時，把 `Crypto` 的條件拿掉、讓 macOS 編出 `Crypto` 模組，這支測試照樣綠。
/// 因此另找 swift-crypto 自己的模組（`Crypto`、`_CryptoExtras`、`CryptoBoringWrapper`）。
///
/// 空掃描不算通過：同一次掃描要先找到一個已知一定在的產物（`AkashicSQLite` 的物件檔），找不到就紅。
final class LinuxOnlyProductsTests: XCTestCase {
    /// 檔名（不含路徑）含這些字串的，是 Linux 專用套件的產物。
    private static let containsNeedles = ["SwiftToolchainCSQLite", "CCryptoBoringSSL", "CryptoBoringWrapper"]
    /// 模組名剛好是這些的（`Crypto.o`、`Crypto.swiftmodule`、`Crypto.build`、`Crypto-t.build`…）。
    private static let moduleNeedles: Set<String> = ["Crypto", "_CryptoExtras"]

    private func moduleStem(_ name: String) -> String {
        if let r = name.range(of: "-t.build") { return String(name[..<r.lowerBound]) }
        return name.split(separator: ".", maxSplits: 1).first.map(String.init) ?? name
    }

    /// 測試 bundle 所在的目錄就是這次建置的 products 目錄（native：`.build/<triple>/debug`；swiftbuild：
    /// `.build/out/Products/Debug`）。swiftbuild 另把中間產物放在 `out/Intermediates.noindex`，一併掃。
    private func scanRoots() throws -> [URL] {
        let bundle = Bundle(for: Self.self).bundleURL
        XCTAssertEqual(bundle.pathExtension, "xctest", "找不到測試 bundle：\(bundle.path)")
        let products = bundle.deletingLastPathComponent()
        var roots = [products]
        let intermediates = products.deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Intermediates.noindex")
        if FileManager.default.fileExists(atPath: intermediates.path) { roots.append(intermediates) }
        return roots
    }

    // spec-example: linux-platform-support / macOS build contains no Linux-only product
    func testTheMacOSBuildContainsNoLinuxOnlyProduct() throws {
        #if os(Linux)
        throw XCTSkip("macOS 專屬：Linux 的建置本來就該有 swift-crypto 與 swift-toolchain-sqlite 的產物")
        #else
        var found: [String] = []
        var sawKnownProduct = false
        let roots = try scanRoots()
        for root in roots {
            guard let walker = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil) else {
                XCTFail("讀不到建置目錄 \(root.path)"); continue
            }
            for case let url as URL in walker {
                let name = url.lastPathComponent
                if name == "AkashicSQLite.o" || name == "AkashicSQLite.swiftmodule" || name == "AkashicSQLite.build" { sawKnownProduct = true }
                if Self.containsNeedles.contains(where: { name.contains($0) }) || Self.moduleNeedles.contains(moduleStem(name)) {
                    found.append(url.path)
                }
            }
        }
        XCTAssertTrue(sawKnownProduct, "掃描沒有找到 AkashicSQLite 的產物——掃的不是這次的建置目錄，空掃描不算通過：\(roots.map(\.path))")
        XCTAssertEqual(found, [], "macOS 的建置目錄出現 Linux 專用套件的產物（product 的 `.when(platforms: [.linux])` 失效？）：\n"
                       + found.prefix(20).joined(separator: "\n"))
        #endif
    }
}
