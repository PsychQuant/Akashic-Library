import CryptoKit
import Foundation
import XCTest

/// plugin 殼送出的內容改了，`plugin/.claude-plugin/plugin.json` 的 `version` 就要升（#729；#613 b39＝b38 Z2 第 0 則）。
///
/// Claude Code 以 `version` 決定要不要換掉使用者機器上的 plugin 快取：內容改了而版號沒升，`claude plugin update` 回報「已是最新」，
/// 使用者載入的仍是舊的 skill。#729（2026-10-08，0.13.2 → 0.13.3）修過一次；之後 #613 b37（`1e42ed5d`：SKILL 第 0 步改成要求契約版本 6、
/// 中止條款的路徑規則改寫）與 #692／#700（`f2a321e4`：web-access.md〈開始前〉的探測）又改了 skill 而沒升，`plugin/CHANGELOG.md` 還把
/// 「skill 文字的改動」寫成不升版的理由。後果不只是文字沒送到：快取裡的 SKILL 仍要求契約版本 5，b34 的 CLI 照過第 0 步，而它把
/// safari-browser 的整段錯誤（含其他 profile 的分頁網址）印出來——b37 的隱私修正對仍用舊 CLI 的人沒有閘。
///
/// 這支把「這個版號送出的是哪一份內容」記成一個摘要（`recorded`）：內容改了而這一行沒改，就紅。
///
/// **送出的內容**＝`plugin/` 底下 git 認得的檔（已追蹤，加上未追蹤而沒被忽略的——還沒 `git add` 的新 skill 檔也算），除了
/// `plugin/CHANGELOG.md`（版本史，不是 Claude Code 載入的東西）；`plugin.json` 去掉 `version` 本身再算（其餘欄位——`binary_version`、
/// `description`——改了同樣要升：wrapper 讀的是快取裡那一份）。
///
/// **誠實邊界**：它分不出「這個版號已經推上 main、同步到 marketplace 了沒」。紅了之後該升版還是只重記摘要，看的是那件事（見 `recorded`）。
final class PluginShellVersionTests: XCTestCase {
    /// 目前的版號，與它送出的殼內容的摘要。這支紅的時候：
    /// - 殼的內容改了 → 升 `plugin.json` 的 `version`，把這兩個值改成新的版號與失敗訊息印出的摘要；
    /// - 這個版號還沒推上 main（還沒同步到 marketplace）→ 版號不動，只改摘要。
    static let recorded = (version: "0.13.4", digest: "23daeceed371a9c4fd5e176de9c0ba67f0c16658e228e0199d99804af6971190")

    static var repo: URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    }

    /// 送出的檔：（`plugin/` 起算的路徑，內容；工作樹裡被刪掉的已追蹤檔是 nil）。
    static func shippedFiles(repo: URL) throws -> [(path: String, data: Data?)] {
        let listed = try XCTUnwrap(GitFixture.capture(["ls-files", "-z", "--cached", "--others", "--exclude-standard", "--", "plugin"], in: repo),
                                   "git ls-files 失敗——沒有清單就沒有摘要（空掃描不是通過）")
        let paths = Set(listed.split(separator: "\0").map(String.init)).subtracting(["plugin/CHANGELOG.md"]).sorted()
        return paths.map { ($0, FileManager.default.contents(atPath: repo.appendingPathComponent($0).path)) }
    }

    /// 摘要：依路徑排序，每個檔是「路徑、NUL、長度、NUL、內容」；`plugin.json` 去掉 `version` 之後以排序過的鍵重新序列化。
    static func digest(_ files: [(path: String, data: Data?)]) throws -> String {
        var hasher = SHA256()
        for (path, data) in files.sorted(by: { $0.path < $1.path }) {
            var content = data ?? Data("<missing>".utf8)
            if path == "plugin/.claude-plugin/plugin.json", let raw = data {
                var object = try XCTUnwrap(try JSONSerialization.jsonObject(with: raw) as? [String: Any], "plugin.json 不是 JSON object")
                object.removeValue(forKey: "version")
                content = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
            }
            hasher.update(data: Data(path.utf8) + Data([0]) + Data(String(content.count).utf8) + Data([0]))
            hasher.update(data: content)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    func testTheShippedShellMatchesWhatThisVersionRecorded() throws {
        let manifest = try XCTUnwrap(FileManager.default.contents(atPath: Self.repo.appendingPathComponent("plugin/.claude-plugin/plugin.json").path))
        let version = try XCTUnwrap((try JSONSerialization.jsonObject(with: manifest) as? [String: Any])?["version"] as? String)
        let files = try Self.shippedFiles(repo: Self.repo)
        XCTAssertTrue(files.contains { $0.path.hasPrefix("plugin/skills/") }, "清單裡沒有任何 skill——量錯了地方：\(files.map(\.path))")
        let now = try Self.digest(files)
        XCTAssertEqual(version, Self.recorded.version,
                       "plugin.json 的 version 是 \(version)，這支記的是 \(Self.recorded.version)：升版時把 `recorded` 改成 (version: \"\(version)\", digest: \"\(now)\")")
        XCTAssertEqual(now, Self.recorded.digest,
                       "plugin 殼的內容與 \(Self.recorded.version) 記下的不同：內容改了而版號沒升，`claude plugin update` 會說已是最新、使用者載入舊的 skill（#729）。"
                       + "升 plugin.json 的 version，並把 `recorded` 改成 (version: \"<新版號>\", digest: \"\(now)\")；"
                       + "\(Self.recorded.version) 還沒推上 main（還沒同步到 marketplace）的話，版號不動、只把 digest 改成 \"\(now)\"")
    }

    /// 摘要算的是什麼：skill 的一個位元組、`plugin.json` 的其他欄位、新加與被刪的檔都會改變它；`version` 不會（`CHANGELOG.md` 在
    /// `shippedFiles` 就排除了）。
    func testTheDigestCoversTheShippedContentButNotTheVersionItself() throws {
        let manifest = Data(#"{"name": "akashic-mcp", "version": "1.0.0", "binary_version": "0.12.1"}"#.utf8)
        let skill = Data("step 0: contract 6\n".utf8)
        let base = try Self.digest([("plugin/.claude-plugin/plugin.json", manifest), ("plugin/skills/a/SKILL.md", skill)])
        XCTAssertEqual(base, try Self.digest([("plugin/skills/a/SKILL.md", skill), ("plugin/.claude-plugin/plugin.json", manifest)]), "與順序無關")
        let bumped = Data(#"{"name": "akashic-mcp", "version": "1.0.1", "binary_version": "0.12.1"}"#.utf8)
        XCTAssertEqual(base, try Self.digest([("plugin/.claude-plugin/plugin.json", bumped), ("plugin/skills/a/SKILL.md", skill)]), "只升版不改內容")
        let binary = Data(#"{"name": "akashic-mcp", "version": "1.0.0", "binary_version": "0.12.2"}"#.utf8)
        XCTAssertNotEqual(base, try Self.digest([("plugin/.claude-plugin/plugin.json", binary), ("plugin/skills/a/SKILL.md", skill)]), "binary_version 也是送出的內容")
        XCTAssertNotEqual(base, try Self.digest([("plugin/.claude-plugin/plugin.json", manifest), ("plugin/skills/a/SKILL.md", Data("step 0: contract 7\n".utf8))]))
        XCTAssertNotEqual(base, try Self.digest([("plugin/.claude-plugin/plugin.json", manifest), ("plugin/skills/a/SKILL.md", skill),
                                                 ("plugin/skills/b/SKILL.md", Data())]), "新加的空檔也算")
        XCTAssertNotEqual(base, try Self.digest([("plugin/.claude-plugin/plugin.json", manifest), ("plugin/skills/a/SKILL.md", nil)]), "被刪掉的檔")
        // 路徑與內容的分界：同一串位元組切在不同地方不能得到同一個摘要
        XCTAssertNotEqual(try Self.digest([("plugin/a", Data("bc".utf8))]), try Self.digest([("plugin/ab", Data("c".utf8))]))
    }
}
