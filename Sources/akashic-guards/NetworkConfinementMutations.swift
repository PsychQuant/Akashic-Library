// `network-confinement-mutations`：`network-confinement` 真的會開火嗎？（#664）
//
// **為什麼需要它**：一道只比對字樣的守衛，最可能的失效不是誤報，而是**永遠綠**——掃描
// 範圍算錯（少走一層目錄、只看程式碼不看註解、豁免寫成整個 `akashic-guards/`），而綠
// 看起來和「沒有人開第二條網路路徑」一模一樣。能排除這一種的方法只有一個：故意注入，
// 看它紅不紅。
//
// **三種格子，逐條對應 spec〈A mutation control proves the guard fires〉**：
//
//   1. **原樣副本**必須綠。它同時證明兩個豁免檔真的被豁免——守衛與本檔把九個字樣都寫成
//      了字面，豁免失效的話這一格就紅。
//   2. **九個字樣各注入一次**到 `Sources/AkashicS2/` 以外的檔，每一格都必須紅，而且
//      **恰好一條**違規、指名注入的檔、行號與字樣。「恰好一條」是鑑別力：紅的原因若不只
//      注入那一行，這一格證明不了守衛看得見它（`trigger-coverage-mutations` 的同一個紀律）。
//   3. **九個字樣一起放進 `Sources/AkashicS2/` 底下一個新檔**必須綠。spec 的情境要求
//      「一個」放置；九個字樣都在那個檔裡，所以每一個字樣在豁免目錄內不開火都驗到了。
//
// **注入格與守衛的清單逐項對帳**：注入格照 spec 獨立寫，再與守衛的
// `networkConfinementPatterns` 比對。守衛的清單多一項而這裡沒跟上，會紅，而不是少驗一格。
// 放置的目錄同樣照 spec 獨立寫，不取守衛的常數——取了的話，守衛把目錄寫錯時這裡會跟著錯、
// 照樣綠。
//
// **目標檔的選法**：兩格是 spec 情境的原文（`Sources/AkashicCore/` 的 `URLSession.shared`、
// `Sources/akashic/CLI.swift` 的 `SecItemCopyMatching` 註解）；兩格寫成註解，證明註解也
// 計入；一格落在 `Sources/akashic-guards/main.swift`——與兩個豁免檔同目錄，證明豁免是
// 逐檔的，不是整個目錄；一格**新建**在第三層的新目錄，證明守衛會遞迴走訪、也看得見新檔
// （`Sources/` 的 Swift 檔幾乎全在第二層，只走兩層的守衛會讓其餘八格照樣全過）。其餘目標
// 都是既有的受保護檔：被刪或改名時注入會套不上而紅，不會安靜地少一格。
//
// **只複製 `Sources/`**：守衛只讀那裡。注入全部發生在暫存副本；工作樹有沒有被寫入，
// 最後逐位元比對一次——spec 說 SHALL NOT modify the working tree，那是量得到的，就量。

import Foundation

private struct ConfinementInjection {
    let pattern: String
    /// 注入的檔（repo 相對路徑，在 `Sources/AkashicS2/` 以外）
    let target: String
    /// 加在檔尾的那一行
    let line: String
    /// true：目標是副本裡新建的檔（它必須還不存在）；false：加在既有檔的檔尾
    var createsFile = false
}

func networkConfinementMutations() -> Int32 {
    let fm = FileManager.default
    let BIN = "\(repoRoot)/.build/debug/akashic-guards"
    // spec 的字面，刻意不取守衛的常數（理由見檔頭）
    let home = "Sources/AkashicS2/"

    let injections: [ConfinementInjection] = [
        .init(pattern: "URLSession", target: "Sources/AkashicCore/Models.swift",
              line: "let _ = URLSession.shared"),
        .init(pattern: "URLRequest", target: "Sources/akashic-mcp/Server.swift",
              line: "let pendingRequest: URLRequest? = nil"),
        // 新檔、第三層：路徑用拼接產生——它只存在於副本，寫成字面值的話 trigger-coverage
        // 會把它當成「守衛引用了不存在的檔」
        .init(pattern: "NWConnection", target: "Sources/AkashicStoreIO/Nested/" + "ConfinementProbe" + ".swift",
              line: "let pendingConnection: NWConnection? = nil", createsFile: true),
        .init(pattern: "import Network", target: "Sources/AkashicCore/Venue.swift",
              line: "import Network"),
        .init(pattern: "/usr/bin/curl", target: "Sources/akashic/CreateEntryCommand.swift",
              line: "let fetchTool = \"/usr/bin/curl\""),
        .init(pattern: "import Security", target: "Sources/AkashicCore/Temporal.swift",
              line: "import Security"),
        .init(pattern: "SecItem", target: "Sources/akashic/CLI.swift",
              line: "// uses SecItemCopyMatching"),
        .init(pattern: "import LocalAuthentication", target: "Sources/akashic-guards/main.swift",
              line: "import LocalAuthentication"),
        .init(pattern: "/usr/bin/security", target: "Sources/akashic-mcp/Server.swift",
              line: "// reads the key via /usr/bin/security find-generic-password"),
    ]

    guard fm.isExecutableFile(atPath: BIN) else {
        print("✗ \(BIN) 不存在——先 swift build --product akashic-guards"); return 2
    }

    // ── 對帳：注入格 vs 守衛的封閉列舉 ─────────────────────────────────────
    let listed = networkConfinementPatterns.map { $0.pattern }
    let injected = injections.map { $0.pattern }
    let unlisted = injected.filter { !listed.contains($0) }
    let uninjected = listed.filter { !injected.contains($0) }
    guard unlisted.isEmpty, uninjected.isEmpty,
          Set(injected).count == injected.count, Set(listed).count == listed.count else {
        print("✗ 注入格與守衛的封閉列舉對不上（守衛 \(listed.count) 項、注入 \(injected.count) 格）")
        for p in uninjected { print("    · 守衛列了 `\(p)`，這裡沒有注入它的格子——它沒被驗過") }
        for p in unlisted { print("    · 這裡注入 `\(p)`，守衛的清單沒有它") }
        return 1
    }

    // stdout 與 stderr 接同一根 pipe：守衛把違規印在 stderr、摘要印在 stdout，分開依序讀的話
    // 其中一邊塞滿緩衝時兩個 process 會互等（`main.swift` 的 `Verdict` 記過 #394 R9 那次死鎖）。
    // 經 `runGuardProcess` 執行（#707）：它留下執行紀錄。
    func runGuard(in root: String, _ label: String, _ expect: GuardExpectation) -> (Int32, String) {
        let r = runGuardProcess([BIN, "network-confinement"], cwd: root, mergeOutput: true,
                                label: label, expect: expect)
        return (r.status, r.combined)
    }

    /// 把 `Sources/` 複製進暫存目錄、交給 `edit` 改、在那裡跑守衛。
    /// 複製不起來或 `edit` 套不上時回 nil——該格無效，不算被抓到。
    func withCopy(_ label: String, _ expect: GuardExpectation, _ edit: (String) -> Bool) -> (Int32, String)? {
        let tmp = NSTemporaryDirectory() + "network-confinement-mut-" + UUID().uuidString
        defer { try? fm.removeItem(atPath: tmp) }
        guard (try? fm.createDirectory(atPath: tmp, withIntermediateDirectories: true)) != nil,
              (try? fm.copyItem(atPath: "\(repoRoot)/Sources", toPath: tmp + "/Sources")) != nil,
              edit(tmp) else { return nil }
        return runGuard(in: tmp, label, expect)
    }

    /// 在副本裡注入一行，回傳那一行的行號；套不上時回 nil（既有目標被刪或改名、
    /// 新建目標卻已存在）。行號由這裡獨立算出，不取守衛的輸出——否則驗的是守衛與它自己一致。
    func inject(_ root: String, _ c: ConfinementInjection) -> Int? {
        let path = root + "/" + c.target
        let t: String
        if c.createsFile {
            guard !fm.fileExists(atPath: path),
                  (try? fm.createDirectory(atPath: dirOf(path), withIntermediateDirectories: true)) != nil
            else { return nil }
            t = "import Foundation\n\n"   // 讓注入落在第 3 行，而不是任何實作都會答對的第 1 行
        } else {
            guard let s = try? String(contentsOfFile: path, encoding: .utf8) else { return nil }
            t = s
        }
        let head = (t.isEmpty || t.hasSuffix("\n")) ? t : t + "\n"
        let lineNo = head.components(separatedBy: "\n").count
        guard (try? (head + c.line + "\n").write(toFile: path, atomically: true, encoding: .utf8)) != nil
        else { return nil }
        return lineNo
    }

    /// 守衛的違規行（`Verdict` 的格式：兩格縮排加 `✗`）。
    func violations(_ out: String) -> [String] {
        matches(out, #"(?m)^  ✗ (.+)$"#).map { (out as NSString).substring(with: $0.range(at: 1)) }
    }
    func head(_ out: String) -> String {
        out.split(separator: "\n").prefix(2).joined(separator: " / ")
    }

    // 工作樹的快照：跑完所有格子之後逐位元比對（檔頭最後一段）
    func snapshot() -> [String: Data] {
        var s: [String: Data] = [:]
        for rel in swiftSources() { s[rel] = fm.contents(atPath: "\(repoRoot)/\(rel)") ?? Data() }
        return s
    }
    let before = snapshot()

    var passed = 0, total = 0

    // ── 1. 原樣副本 ──────────────────────────────────────────────────────
    total += 1
    if let (rc, out) = withCopy("原樣副本", .green, { _ in true }) {
        if rc == 0 {
            print("✓ 原樣副本 → rc=0（兩個豁免檔把九個字樣寫成字面，仍然綠）"); passed += 1
        } else {
            print("✗ 原樣副本 → rc=\(rc) ← 基準就是紅的，下面每一格都證明不了什麼：\(head(out))")
        }
    } else {
        print("✗ 原樣副本 → 複製不起來，這一格無效")
    }

    // ── 2. 九個字樣，各注入一次到 AkashicS2 以外 ─────────────────────────
    for c in injections {
        total += 1
        let label = "`\(c.pattern)` 注入 \(c.target)"
        var lineNo: Int? = nil
        guard let (rc, out) = withCopy(label, .red, { root in
            lineNo = inject(root, c)
            return lineNo != nil
        }), let n = lineNo else {
            print("✗ \(label) → 注入套不上（" + (c.createsFile ? "新建的目標已存在" : "目標不存在")
                + "），未被抓到"); continue
        }
        let v = violations(out)
        let loc = NSRegularExpression.escapedPattern(for: "\(c.target):\(n)") + "(?![0-9])"
        let named = v.filter { !matches($0, loc).isEmpty && $0.contains("`\(c.pattern)`") }
        if rc != 0 && v.count == 1 && named.count == 1 {
            print("✓ \(label):\(n) → rc=\(rc)，唯一一條違規指名了檔案、行號與字樣"); passed += 1
        } else if rc == 0 {
            print("✗ \(label):\(n) → 守衛是綠的 ← 它看不見這個字樣")
        } else if named.isEmpty {
            print("✗ \(label):\(n) → rc=\(rc)，但沒有一條違規指名 \(c.target):\(n) 與 `\(c.pattern)`："
                + head(out))
        } else {
            print("✗ \(label):\(n) → rc=\(rc)，但違規有 \(v.count) 條 ← 紅的原因不只這一行："
                + pyRepr(Array(v.prefix(2))))
        }
    }

    // ── 3. 九個字樣一起放在 AkashicS2 底下 ───────────────────────────────
    total += 1
    let probe = home + "NetworkConfinementProbe" + ".swift"
    let probeText = injections.map { $0.line }.joined(separator: "\n") + "\n"
    if let (rc, out) = withCopy("九個字樣放在豁免目錄", .green, { root in
        (try? probeText.write(toFile: root + "/" + probe, atomically: true, encoding: .utf8)) != nil
    }) {
        // 紅的時候分兩種說：違規落在放置的檔 ＝ 豁免失效；全在別處 ＝ 紅的原因與放置無關
        // （多半是基準本身就紅）。混成一句會把後者誤報成前者。
        let inProbe = violations(out).filter { $0.hasPrefix(probe + ":") }
        if rc == 0 {
            print("✓ 九個字樣放在 \(probe) → rc=0（豁免目錄內不開火）"); passed += 1
        } else if !inProbe.isEmpty {
            print("✗ 九個字樣放在 \(probe) → rc=\(rc) ← 豁免目錄內也開火了（\(inProbe.count) 條）")
        } else {
            print("✗ 九個字樣放在 \(probe) → rc=\(rc)，違規都不在放置的檔 ← 紅的原因與放置無關"
                + "（基準是紅的？）：\(head(out))")
        }
    } else {
        print("✗ 九個字樣放在 \(probe) → 寫不進副本，這一格無效")
    }

    // ── 工作樹沒有被寫入 ───────────────────────────────────────────────────
    let after = snapshot()
    let untouched = before == after
    if untouched {
        print("✓ 工作樹沒有被寫入：Sources/ 下 \(after.count) 個 Swift 檔前後逐位元相同")
    } else {
        let changed = Set(before.keys).union(after.keys).filter { before[$0] != after[$0] }.sorted()
        print("✗ 工作樹被改了：\(pyRepr(Array(changed.prefix(5))))")
    }

    print("\n══ \(passed)/\(total) 格符合預期：原樣副本 1、九個字樣各一個失敗的 mutation、"
        + "\(home) 內的放置 1 ══")
    return passed == total && untouched ? 0 : 1
}
