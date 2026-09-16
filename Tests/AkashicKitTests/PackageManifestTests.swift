import Foundation
import XCTest

/// R19 verify regression 第 9 列、DA 第 14 列（#554 R20）：Xcode 27 的預設建置系統 swiftbuild 只連結**宣告依賴的閉包**內的模組
/// （native 靠 SwiftPM 的傳遞連結，所以 `AkashicKitTests` 少宣告 `AkashicMCPKit` 六個月都沒事）。pre-push 暫釘 native（#577），
/// 於是這一類缺陷沒有任何在跑的閘會抓到；CI 又帳務擱置。這條用純文字把 `Package.swift` 的依賴圖與每個 test target 的
/// `import` 對照，不需要 swiftbuild 也不需要建置——不變式是「模組要在宣告依賴的閉包內」，不是「要直接宣告」
/// （DA 第 14 列：另外三個 test target 有九個 import 沒直接宣告而在閉包內，建得起來；`AkashicMCPKit` 是唯一不在閉包的）。
final class PackageManifestTests: XCTestCase {
    private func repoRoot() -> URL {
        var dir = URL(fileURLWithPath: #filePath)
        for _ in 0..<10 {
            dir.deleteLastPathComponent()
            if FileManager.default.fileExists(atPath: dir.appendingPathComponent("Package.swift").path) { return dir }
        }
        return dir
    }

    /// `Package.swift` 的 target → 直接宣告的依賴（只認裸字串名，`.product(...)` 是外部套件、不在本檢查的母體）。
    private func declaredDependencies(_ manifest: String) -> [String: Set<String>] {
        var graph: [String: Set<String>] = [:]
        let pattern = #"\.(?:executableTarget|testTarget|target)\(\s*name:\s*"([A-Za-z0-9_-]+)"(?:,\s*dependencies:\s*\[((?:[^\[\]]|\[[^\]]*\])*)\])?"#
        let re = try! NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators])
        let ns = manifest as NSString
        for m in re.matches(in: manifest, range: NSRange(location: 0, length: ns.length)) {
            let name = ns.substring(with: m.range(at: 1))
            var deps = Set<String>()
            if m.range(at: 2).location != NSNotFound {
                let body = ns.substring(with: m.range(at: 2))
                let depRe = try! NSRegularExpression(pattern: #"(?<![\w.])"([A-Za-z0-9_-]+)""#)
                let nb = body as NSString
                for d in depRe.matches(in: body, range: NSRange(location: 0, length: nb.length)) {
                    let token = nb.substring(with: d.range(at: 1))
                    if !body.contains(".product(name: \"\(token)\"") { deps.insert(token) }
                }
            }
            graph[name] = deps
        }
        return graph
    }

    /// target 名 → 模組名（SwiftPM 把 `-` 換成 `_`；R20 verify DA 第 17 列）。value 是原 target 名。
    private func moduleUniverse(_ graph: [String: Set<String>]) -> [String: String] {
        Dictionary(uniqueKeysWithValues: graph.keys.map { ($0.replacingOccurrences(of: "-", with: "_"), $0) })
    }

    private func closure(of target: String, in graph: [String: Set<String>]) -> Set<String> {
        var seen: Set<String> = []
        var stack = Array(graph[target] ?? [])
        while let next = stack.popLast() {
            guard seen.insert(next).inserted else { continue }
            stack.append(contentsOf: graph[next] ?? [])
        }
        return seen
    }

    /// R20 verify DA 第 17 列：SwiftPM 把 target 名的連字號換成底線當模組名（`akashic-mcp` → `import akashic_mcp`），而 R20 的
    /// 母體是 target 名——三個帶連字號的 target 對本守衛結構上不可見。R21：兩側都正規化。
    func testHyphenatedTargetsAreInTheModuleUniverse() throws {
        let manifest = try String(contentsOf: repoRoot().appendingPathComponent("Package.swift"), encoding: .utf8)
        let modules = moduleUniverse(declaredDependencies(manifest))
        for name in ["akashic_mcp", "akashic_guards", "tractatus_doc", "AkashicMCPKit"] {
            XCTAssertTrue(modules.keys.contains(name), "模組母體少了 \(name)：\(modules.keys.sorted())")
        }
    }

    /// R20 verify logic 第 12 列、regression 第 16 列：R20 的走訪是非遞迴、目錄讀不到就 `continue`、且只認名字以 Tests 結尾的 target
    /// ——一支抓「沉默缺口」的守衛自己留了三個沉默缺口。R21：遞迴走訪、讀不到即紅、母體取自 `.testTarget(` 宣告；並把掃過的檔數與
    /// `Tests/` 底下實際的 `.swift` 檔數對帳（多一個沒被掃到的檔就紅）。
    func testEveryTestTargetImportIsInsideItsDeclaredDependencyClosure() throws {
        let root = repoRoot()
        let manifest = try String(contentsOf: root.appendingPathComponent("Package.swift"), encoding: .utf8)
        let graph = declaredDependencies(manifest)
        XCTAssertTrue(graph.keys.contains("AkashicKitTests"), "manifest 解析不到 test target：\(graph.keys.sorted())")
        let modules = moduleUniverse(graph)
        // 母體＝manifest 裡宣告為 `.testTarget(` 的 target（不靠名字後綴）
        let testTargetRe = try NSRegularExpression(pattern: #"\.testTarget\(\s*name:\s*"([A-Za-z0-9_-]+)""#)
        let mns = manifest as NSString
        let testTargets = testTargetRe.matches(in: manifest, range: NSRange(location: 0, length: mns.length)).map { mns.substring(with: $0.range(at: 1)) }
        XCTAssertGreaterThanOrEqual(testTargets.count, 5, "\(testTargets)")
        let importRe = try NSRegularExpression(pattern: #"^\s*(?:@testable\s+)?import\s+([A-Za-z0-9_]+)"#, options: [.anchorsMatchLines])
        var violations: [String] = []
        var scanned = 0
        for target in testTargets {
            let dir = root.appendingPathComponent("Tests/\(target)")
            guard let walker = FileManager.default.enumerator(at: dir, includingPropertiesForKeys: nil) else {
                XCTFail("讀不到 Tests/\(target)——「沒被掃」不得與「掃過且乾淨」同輸出（zero-instance-guards 第 3 列）"); continue
            }
            let reach = closure(of: target, in: graph)
            for case let url as URL in walker where url.pathExtension == "swift" {
                scanned += 1
                let src = try String(contentsOf: url, encoding: .utf8)
                let ns = src as NSString
                for m in importRe.matches(in: src, range: NSRange(location: 0, length: ns.length)) {
                    let mod = ns.substring(with: m.range(at: 1))
                    guard let targetName = modules[mod], targetName != target else { continue }   // 只看本 package 的 target；系統框架不在母體
                    if !reach.contains(targetName) { violations.append("\(target)/\(url.lastPathComponent) import \(mod)（不在 \(target) 宣告依賴的閉包內）") }
                }
            }
        }
        // 對帳：Tests/ 底下每個 .swift 都要被掃到（用另一條走訪算，不是同一個迴圈自己數自己）
        let all = try FileManager.default.subpathsOfDirectory(atPath: root.appendingPathComponent("Tests").path).filter { $0.hasSuffix(".swift") }.count
        XCTAssertEqual(scanned, all, "Tests/ 底下有 \(all) 個 .swift，本守衛只掃到 \(scanned) 個——沒被掃到的那些在母體之外")
        XCTAssertEqual(violations, [], "swiftbuild 只連結閉包內的模組，這些 import 在預設建置系統下會 Undefined symbols：\n" + violations.joined(separator: "\n"))
    }
}
