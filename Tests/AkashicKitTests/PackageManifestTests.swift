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

    private func closure(of target: String, in graph: [String: Set<String>]) -> Set<String> {
        var seen: Set<String> = []
        var stack = Array(graph[target] ?? [])
        while let next = stack.popLast() {
            guard seen.insert(next).inserted else { continue }
            stack.append(contentsOf: graph[next] ?? [])
        }
        return seen
    }

    func testEveryTestTargetImportIsInsideItsDeclaredDependencyClosure() throws {
        let root = repoRoot()
        let manifest = try String(contentsOf: root.appendingPathComponent("Package.swift"), encoding: .utf8)
        let graph = declaredDependencies(manifest)
        XCTAssertTrue(graph.keys.contains("AkashicKitTests"), "manifest 解析不到 test target：\(graph.keys.sorted())")
        let modules = Set(graph.keys)
        let importRe = try NSRegularExpression(pattern: #"^\s*(?:@testable\s+)?import\s+([A-Za-z0-9_]+)"#, options: [.anchorsMatchLines])
        var violations: [String] = []
        for (target, _) in graph where target.hasSuffix("Tests") {
            let dir = root.appendingPathComponent("Tests/\(target)")
            guard let files = try? FileManager.default.contentsOfDirectory(atPath: dir.path) else { continue }
            let reach = closure(of: target, in: graph)
            for f in files where f.hasSuffix(".swift") {
                let src = try String(contentsOf: dir.appendingPathComponent(f), encoding: .utf8)
                let ns = src as NSString
                for m in importRe.matches(in: src, range: NSRange(location: 0, length: ns.length)) {
                    let mod = ns.substring(with: m.range(at: 1))
                    guard modules.contains(mod), mod != target else { continue }   // 只看本 package 的 target；系統框架不在母體
                    if !reach.contains(mod) { violations.append("\(target)/\(f) import \(mod)（不在 \(target) 宣告依賴的閉包內）") }
                }
            }
        }
        XCTAssertEqual(violations, [], "swiftbuild 只連結閉包內的模組，這些 import 在預設建置系統下會 Undefined symbols：\n" + violations.joined(separator: "\n"))
    }
}
