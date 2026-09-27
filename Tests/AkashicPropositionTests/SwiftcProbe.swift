import Foundation
import XCTest

/// External probe 用的 toolchain 解析——**單一定義**（#230）。
///
/// 本 target 有三個 access-control probe（`NegationTests` / `ExpressionConstructionTests`
/// / `ClassicalSemanticsTests`），各自生一個 `Probe.swift`、編譯它，藉「編譯失敗」
/// 驗證外部 client 構造不出內部型別。三者曾各寫一份 `/usr/bin/xcrun swiftc`——
/// **同一個決定的三份拷貝，而修法只補了其中一份**（#237 併入 main 時實測：
/// `ClassicalSemanticsTests` 修好了，另外兩個仍紅）。
///
/// ## 為什麼不能用 `/usr/bin/xcrun`
///
/// 它解析到 **Xcode 預設 toolchain**，而 SwiftPM 用的是 PATH 上的 swift。兩者版本
/// 不同時（本機實測 swiftly 6.2.4 vs Xcode 6.3.3）`.swiftmodule` 不相容，probe 連
/// `import` 都過不了：
///
/// ```
/// error: module compiled with Swift 6.2.4 cannot be imported by the Swift 6.3.3 compiler
/// ```
///
/// 於是**兩條 assertion 都因為錯的理由失敗**——而它們檢查的是 access control。
///
/// ## 解析順序
///
/// `SWIFT_EXEC`（顯式覆寫，SwiftPM 也讀它）旁邊的 swiftc；否則走 PATH
/// （`/usr/bin/env`）——`swift build` / `swift test` 本身就是從 PATH 解析的，
/// 所以 PATH 上的 swiftc 與建出 modules 的那個一致。
enum SwiftcProbe {

    /// SwiftPM 產物佈局（#577）。native 把 `.swiftmodule` 放在 `<products>/Modules`、`checkouts/` 在往上兩層；swiftbuild（Xcode 27
    /// 起的預設）直接放在 `<products>`（`.build/out/Products/Debug`）、`checkouts/` 在往上三層。**以存在與否判斷，不寫死層數**——
    /// 先前三個 probe 各自寫死 native 的佈局，預設建置系統一換就三個一起紅。
    static func layout(products: URL) -> (modules: URL, cyamlInclude: URL) {
        let fm = FileManager.default
        let nativeModules = products.appendingPathComponent("Modules")
        let modules = fm.fileExists(atPath: nativeModules.path) ? nativeModules : products
        let rel = "checkouts/Yams/Sources/CYaml/include"
        var dir = products
        for _ in 0..<5 {
            let candidate = dir.appendingPathComponent(rel)
            if fm.fileExists(atPath: candidate.appendingPathComponent("module.modulemap").path) { return (modules, candidate) }
            dir = dir.deletingLastPathComponent()
        }
        // 找不到時回 native 的位置，讓呼叫端的存在斷言印出一條具體路徑
        return (modules, products.deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent(rel))
    }

    /// 用建出 modules 的那個 toolchain 設定 `process`。
    static func configure(_ process: Process, arguments: [String]) {
        if let swiftExec = ProcessInfo.processInfo.environment["SWIFT_EXEC"],
           !swiftExec.isEmpty {
            process.executableURL = URL(fileURLWithPath: swiftExec)
                .deletingLastPathComponent()
                .appendingPathComponent("swiftc")
            process.arguments = arguments
        } else {
            process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
            process.arguments = ["swiftc"] + arguments
        }
        process.environment = ProcessInfo.processInfo.environment
    }

    /// **負向測試除了斷言失敗，還必須斷言失敗的理由**（#230 的教訓）。
    ///
    /// 三個 probe 的呼叫者都靠「編譯失敗」當成功訊號，所以任何**其他**原因造成的
    /// 失敗都會被吞進同一個判準。toolchain 不合是最容易發生的那一種——在這裡明確
    /// 攔下並說出原因，而不是讓它偽裝成 access-control 的結論。
    static func assertToolchainMatched(
        _ output: String,
        _ process: Process,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        guard output.contains("cannot be imported by the Swift") else { return }
        XCTFail("""
            external probe 的 toolchain 與建出 modules 的不一致（#230）——本次結果
            **不能**當成 access-control 的判定。
            probe 用的 swiftc：\(process.executableURL?.path ?? "?")
            編譯器訊息：\(output)
            對策：讓 `swift test` 與 probe 走同一個 toolchain（例如統一用 PATH 上的 swift）。
            """, file: file, line: line)
    }
}
