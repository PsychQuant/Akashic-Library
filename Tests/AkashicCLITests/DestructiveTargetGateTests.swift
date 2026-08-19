import XCTest

/// 破壞性寫入的目標 store 必須被指名（#298）。
///
/// 事故（2026-08-16）：在 scratch 目錄執行無 `--library` 的
/// `migrate-person-identity --apply`，解析循 registry 打到真 store，**867 個 person
/// 檔被改名重發 id**。核心不是解析錯了——是**呼叫者以為自己在 scratch**，而沒有任何
/// 東西告訴他。
final class DestructiveTargetGateTests: XCTestCase {

    private func repoRoot() throws -> URL {
        var dir = URL(fileURLWithPath: #filePath)
        for _ in 0..<10 {
            dir.deleteLastPathComponent()
            if FileManager.default.fileExists(
                atPath: dir.appendingPathComponent("Package.swift").path) { return dir }
        }
        throw XCTSkip("找不到 repo root")
    }

    private func source(_ rel: String) throws -> String {
        try String(contentsOf: try repoRoot().appendingPathComponent(rel), encoding: .utf8)
    }

    /// 封閉列舉恰好六個，且各自具名。
    ///
    /// 數字寫死是刻意的（同本 repo 其他「一格不多一格不少」的守衛）：新增破壞性命令
    /// 時這條會紅，逼人在同一個變更裡做出裁決。
    func testEnumerationIsClosed() throws {
        let src = try source("Sources/akashic/DestructiveTargetGate.swift")
        for name in ["migrate-person-identity", "migrate-venues", "bootstrap-people",
                     "bootstrap-organizations", "resolve-people", "resolve-organizations"] {
            XCTAssertTrue(src.contains("\"\(name)\""), "封閉列舉缺 \(name)")
        }
    }

    /// **機械稽核（命令 → 列舉）**：每個帶 `--apply` 的 subcommand 都必須在列舉內。
    ///
    /// 這條防的是「新增了破壞性命令但忘了分類」。型別層零 destructive marker——
    /// 38 個 subcommand 完全等價，所以漏掉不會有任何編譯期跡象。
    func testEveryApplyCommandIsEnumerated() throws {
        let gate = try source("Sources/akashic/DestructiveTargetGate.swift")
        for rel in ["Sources/akashic/Commands.swift", "Sources/akashic/VenueCommand.swift"] {
            let src = try source(rel)
            var currentCommand: String?
            for line in src.split(separator: "\n", omittingEmptySubsequences: false) {
                if let r = line.range(of: "commandName: \"") {
                    let rest = line[r.upperBound...]
                    currentCommand = String(rest.prefix(while: { $0 != "\"" }))
                }
                guard line.contains("var apply = false"), let cmd = currentCommand else { continue }
                XCTAssertTrue(gate.contains("\"\(cmd)\""),
                              "\(rel) 的 `\(cmd)` 有 --apply 但不在 destructiveCommands 內"
                              + "——新增破壞性命令必須在同一個變更裡加進封閉列舉（#298 D3）")
                currentCommand = nil
            }
        }
    }

    /// **機械稽核（列舉 → 命令）**：列舉的每個名字都要對得到一個真實 subcommand。
    ///
    /// 反向這條防的是**孤兒列**——命令改名或退場後，列舉留著一個永遠對不到東西的
    /// 名字，讀起來與有效裁決毫無區別。（同 `mcp-cli-parity` 第三個稽核方向的教訓。）
    func testEveryEnumeratedNameExists() throws {
        let commands = try source("Sources/akashic/Commands.swift")
            + (try source("Sources/akashic/VenueCommand.swift"))
        for name in ["migrate-person-identity", "migrate-venues", "bootstrap-people",
                     "bootstrap-organizations", "resolve-people", "resolve-organizations"] {
            XCTAssertTrue(commands.contains("commandName: \"\(name)\""),
                          "列舉裡的 `\(name)` 對不到任何 subcommand——命令退場後留下的孤兒列")
        }
    }

    /// 六個命令都真的呼叫了閘門，且**條件是 `apply`**。
    ///
    /// 沒有這條，列舉可以是完整的而閘門一次都沒被呼叫——那正是 #264 的
    /// `storeSource`（API 完整、零 production 呼叫端）的形狀。
    func testEveryEnumeratedCommandActuallyCallsTheGate() throws {
        let combined = try source("Sources/akashic/Commands.swift")
            + (try source("Sources/akashic/VenueCommand.swift"))
        for name in ["migrate-person-identity", "migrate-venues", "bootstrap-people",
                     "bootstrap-organizations", "resolve-people", "resolve-organizations"] {
            XCTAssertTrue(
                combined.contains("if apply { try options.assertDestructiveTargetNamed(\"\(name)\") }"),
                "`\(name)` 沒有呼叫閘門，或呼叫條件不是 `apply`——"
                + "列舉完整而閘門沒被呼叫，等於沒有閘門")
        }
    }

    /// 閘門**不得**查 CWD——那是被否決的方向 (b)。
    ///
    /// (b) 防不住本 issue 具名的事故：事故發生在 scratch 目錄，而它**不在任何已註冊
    /// store 內**，CWD 感知找不到 store 只能退回 registry，行為與現況相同。
    func testGateDoesNotConsultCurrentDirectory() throws {
        let src = try source("Sources/akashic/DestructiveTargetGate.swift")
        XCTAssertFalse(src.contains("currentDirectoryPath"),
                       "閘門不得查 CWD——方向 (b) 已被事故本身否決（#298 D1）")
    }

    /// 拒絕訊息必須說出**實際解析到的 store**，以及它與 CWD 無關。
    ///
    /// 這是事故最缺的東西：「你以為的目標」與「實際的目標」在那一刻才會對上。
    func testRefusalNamesTheResolvedStore() throws {
        let src = try source("Sources/akashic/DestructiveTargetGate.swift")
        XCTAssertTrue(src.contains("解析到的目標是"), "拒絕訊息必須說出目標")
        XCTAssertTrue(src.contains("與你目前所在的目錄無關"),
                      "必須明說它與 CWD 無關——那正是事故的誤解")
        XCTAssertTrue(src.contains("--yes"), "必須給出路")
        XCTAssertTrue(src.contains("--library"), "必須給出路")
    }
}
