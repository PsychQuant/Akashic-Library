import XCTest
import Foundation
import ArgumentParser
@testable import AkashicStoreIO
@testable import akashic

/// #705 R2 verify 第 4 列：**直接印 service JSON 的寫入命令都經 `LegacyCopyReport.payload`**。不經的話，寫進 `entities/`、搬移後的
/// legacy 拷貝沒刪掉的那一筆由 CLI 進入點以人可讀文字接在 JSON 後面——stdout 不再是一份 JSON，而且只在那種狀態下才壞（安靜）。
///
/// **怎麼機械地列舉**（不靠手寫清單）：
/// 1. 寫入命令＝執行期命令樹（`AkashicCLI.configuration.subcommands` 遞迴）的每個葉命令中，`DestructiveTargetGate.commandRulings`
///    裁決不是 `.readOnly` 的（#658 的裁決表本來就逐格列出每一個葉命令，`WriteGateRulingsTests` 雙向比對它與命令樹）；
/// 2. 找到那個型別在 `Sources/akashic/` 的 `struct` 宣告，取到同一縮排的 `}` 為止；
/// 3. 在裡面找 `print(`：引數以 `try service.` 開頭，或是一個名字而那個名字被 `= … service.…` 賦值——那是直接印 service JSON；
///    引數以 `try LegacyCopyReport.payload` 開頭、或那個名字的賦值含 `LegacyCopyReport.payload`——那是接好了的。
///
/// 直接印 service JSON 而沒接的寫入命令只有下面具名的豁免（封閉列舉，逐格理由）。
///
/// **誠實邊界**：只看命令自己 `struct` 裡的 `print(`；經 helper 印的（`ResolvePeople.printUndecidedResult` 這類——目前都是解析 JSON
/// 再印文字）看不到；引數的判斷是文字形狀，多行拆開的 `print(\n try service…` 或別名的 service 變數也看不到。
final class LegacyCopyPayloadScanTests: XCTestCase {

    /// 直接印 service JSON、而寫不到既有 work／person 記錄的寫入命令——#631 的搬移只發生在寫一筆**既有**的 work／person 時，
    /// 所以它們碰不到 legacy 拷貝的那一格，不必經 `payload`（不經也不會讓 stdout 多出文字）。新增一格要寫它自己的理由。
    static let exempt: [String: String] = [
        "add-person": "只新增一筆 person；key 已在庫就拒絕——legacy 殘留一定已經是一筆載入得到的記錄，所以碰不到搬移",
        "add-venue": "只寫 venue 記錄；#631 的 legacy 搬移只對 work／person",
        "update-venue": "只寫 venue 記錄（名字、ISSN、references）；同上",
        "dismiss-divergence": "只刪一筆歧異記錄，不寫 work／person",
        "store-source": "只把內容存進 sources/ 並記 index，不寫任何記錄",
    ]

    /// 已知接好了的——掃描自己的下限：這幾個的寫法（直接、經變數、經 `json ? … : …`）都要被認出來，否則是掃描壞了。
    static let knownWired: Set<String> = ["update-person", "update-entry", "tag", "link", "set-status", "resolve-venues", "enrich"]

    private func repoRoot() throws -> URL {
        var dir = URL(fileURLWithPath: #filePath)
        for _ in 0..<10 {
            dir.deleteLastPathComponent()
            if FileManager.default.fileExists(atPath: dir.appendingPathComponent("Package.swift").path) { return dir }
        }
        throw XCTSkip("找不到 repo root")
    }

    /// 葉命令路徑（巢狀以空白串接）→ 型別。
    private func leaves() -> [(path: String, type: ParsableCommand.Type)] {
        var out: [(String, ParsableCommand.Type)] = []
        func walk(_ t: ParsableCommand.Type, _ prefix: [String]) {
            let subs = t.configuration.subcommands
            if subs.isEmpty {
                if !prefix.isEmpty { out.append((prefix.joined(separator: " "), t)) }
                return
            }
            for s in subs { walk(s, prefix + [s._commandName]) }
        }
        walk(AkashicCLI.self, [])
        return out
    }

    /// 型別名 → 它的 `struct` 本體（到同一縮排的 `}` 為止），行註解拿掉。找不到或不只一個就回錯誤訊息。
    private func body(of typeName: String, in files: [String]) -> Result<[String], Error> {
        struct Missing: Error, CustomStringConvertible { let description: String }
        var found: [[String]] = []
        for text in files {
            let lines = text.components(separatedBy: "\n")
            for (i, line) in lines.enumerated() {
                guard let r = line.range(of: #"^(\s*)struct "# + typeName + #"\b"#, options: .regularExpression) else { continue }
                let indent = String(line[r].prefix { $0 == " " })
                var j = i + 1
                var out: [String] = []
                while j < lines.count, lines[j] != indent + "}" { out.append(lines[j]); j += 1 }
                found.append(out.map { $0.replacingOccurrences(of: #"(^|\s)//.*$"#, with: "", options: .regularExpression) })
            }
        }
        guard found.count == 1 else { return .failure(Missing(description: "struct \(typeName) 找到 \(found.count) 個")) }
        return .success(found[0])
    }

    private enum JSONPrint { case wired, unwired }

    /// 一個命令本體裡每個印 service JSON 的 `print(`。
    private func jsonPrints(_ lines: [String]) -> [JSONPrint] {
        func bindings(_ name: String) -> [String] {
            let pattern = #"(\b(let|var)\s+"# + name + #"\b[^=]*=|^\s*"# + name + #"\s*=)\s*(.+)$"#
            return lines.compactMap { line -> String? in
                guard let r = line.range(of: pattern, options: .regularExpression) else { return nil }
                return String(line[r])
            }
        }
        var out: [JSONPrint] = []
        for line in lines {
            var rest = Substring(line)
            while let r = rest.range(of: "print(") {
                let arg = rest[r.upperBound...].trimmingCharacters(in: .whitespaces)
                rest = rest[r.upperBound...]
                if arg.hasPrefix("try LegacyCopyReport.payload") { out.append(.wired); continue }
                if arg.hasPrefix("try service.") { out.append(.unwired); continue }
                guard let m = arg.range(of: #"^[A-Za-z_][A-Za-z0-9_]*\)"#, options: .regularExpression) else { continue }
                let name = String(arg[m].dropLast())
                let rhs = bindings(name)
                if rhs.contains(where: { $0.contains("LegacyCopyReport.payload") }) { out.append(.wired) }
                else if rhs.contains(where: { $0.contains("service.") }) { out.append(.unwired) }
            }
        }
        return out
    }

    func testEveryJSONPrintingWriterGoesThroughThePayload() throws {
        let dir = try repoRoot().appendingPathComponent("Sources/akashic")
        let files = try FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "swift" }
            .map { try String(contentsOf: $0, encoding: .utf8) }
        XCTAssertFalse(files.isEmpty)

        var wired: Set<String> = [], unwired: Set<String> = [], writers = 0
        for (path, type) in leaves() {
            let ruling = try XCTUnwrap(DestructiveTargetGate.commandRulings[path], "\(path) 沒有裁決（WriteGateRulingsTests 應先紅）")
            if case .readOnly = ruling { continue }
            writers += 1
            let lines: [String]
            switch body(of: String(describing: type), in: files) {
            case .success(let b): lines = b
            case .failure(let e): XCTFail("\(path)：\(e)"); continue
            }
            let prints = jsonPrints(lines)
            if prints.contains(.wired) { wired.insert(path) }
            if prints.contains(.unwired) { unwired.insert(path) }
        }
        print("LegacyCopyPayloadScan：寫入命令 \(writers)｜接好 \(wired.sorted())｜豁免 \(unwired.sorted())")

        XCTAssertGreaterThan(writers, 20, "空掃描不是通過：只找到 \(writers) 個寫入命令")
        XCTAssertEqual(Self.knownWired.subtracting(wired), [], "掃描沒認出已知接好的命令——掃描壞了，不是命令壞了")
        for path in unwired.sorted() where Self.exempt[path] == nil {
            XCTFail("`\(path)` 直接印 service JSON 卻沒經 LegacyCopyReport.payload——legacy 拷貝刪不掉時進入點會把文字接在 JSON 後面；"
                    + "接上 payload，或（寫不到既有 work／person 時）在 exempt 加一格寫理由")
        }
        XCTAssertEqual(Set(Self.exempt.keys).subtracting(unwired), [], "豁免表過期：這幾格已經不直接印 service JSON（或已接好）")
    }
}
