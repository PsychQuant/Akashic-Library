// 負控的**執行期**證據（#707）。
//
// **為什麼有這個檔**：`migrated-guard-control` 要回答「每支在 `run-guards.sh` 裡跑的守衛，有沒有負控在驗它」。
// #689 的判準讀原始碼文字（harness 的宣告、argv 字面、資料檔欄位），而 #689 從 R1 到 R3 每一輪 verify 都做出新的
// 掏空寫法：只剩變數宣告、死函式、`#if false`、字串裡的呼叫、分派改成 `exit(0)`、runner 裡 `if false` 包住那一行
// ——負控的實體還在，執行已經不在，文字看不出這件事。現在證據改成**執行當下留下的紀錄**：
//
//   · 每個 `akashic-guards` 行程一開始寫一筆 `start`（`main.swift` 在分派之前呼叫 `recordGuardStart()`），
//     經 `finishGuard(_:)` 結束時寫一筆 `end`（含 rc）；
//   · harness 經 `runGuardProcess(...)` 執行守衛，**這個函式自己**在子行程結束後寫一筆 `invoke`：
//     執行了哪支守衛（argv、實際的 binary）、這一格的標籤、harness 預期什麼、觀察到的 rc、預期有沒有成立；
//   · harness 以 `declareNegativeControl(for:)` 在執行時宣告它是哪幾支守衛的負控（命名慣例 `<g>-mutations`
//     由 `migrated-guard-control` 從紀錄裡的名字推出，不必呼叫）。
//
// **紀錄的位置**：環境變數 `AKASHIC_GUARD_RUN_LOG` 指向的檔（`run-guards.sh` 在暫存目錄建一個，結束時刪掉，
// 從不在 repo 樹裡）。未設定時這裡的每個函式都不做任何事——守衛照常跑，只是不留紀錄。
//
// **格式**：一行一個 JSON 物件（鍵排序），共同欄位 `v`（格式版本，現為 1）、`event`、`run`（每個行程一個 UUID）、
// `self`（這個行程的子命令名）。各事件多出的欄位：
//
//   start    ——（無）
//   declare  —— `for`：守衛名的陣列
//   invoke   —— `target`（被執行的子命令）、`exe`（實際執行的 binary，解析過 symlink）、`argv`、`case`（標籤）、
//               `expect`（`red`／`green`／`output`／`none`）、`rc`、`met`（預期是否成立——由本檔比對，不是 harness 說的）
//   end      —— `rc`
//
// **harness 說不了謊的部分**：`self` 取自本行程的命令列、`rc` 與 `met` 由本檔在子行程結束後自己算（沒跑起來的子行程
// `met` 一律是 false）。harness 能決定的只有
// 它預期什麼與它宣告什麼——一支 harness 若根本沒有執行某支守衛，就不會有那一筆 `invoke`。
//
// **子行程拿不到這個環境變數**：`runGuardProcess` 把它從繼承的環境拿掉，所以 harness 在副本裡跑的守衛不會寫
// `start`（它們不是 runner 跑的），被 harness 執行的 harness（`oracle-precondition-control` 跑 `audit-guards-mutations`）
// 也不會寫。呼叫端若要子行程寫進某一份紀錄，得在 `env` 參數**明寫**它（`migrated-guard-control-mutations` 的迷你紀錄就是這樣）。
//
// **誠實邊界**：紀錄是一個一般檔案，任何行程都可以直接打開它、寫進一行假的 `invoke`——`migrated-guard-control`
// 分不出那一行是不是這裡寫的。它擋的是「負控的實體還在、執行已經不在」（遺忘與掏空），不是蓄意偽造。

import Foundation

/// harness 對一次子行程的預期。**比對由 `runGuardProcess` 做**，harness 只說它預期什麼。
enum GuardExpectation {
    /// rc ≠ 0——注入了缺陷，守衛必須變紅
    case red
    /// rc = 0——對照組、基準、不該開火的注入
    case green
    /// rc = 0 且 stdout 逐字等於它。給**本來就不會變紅**的列舉命令（`plugin-roots`）用：它的負控是「在一棵放了
    /// 干擾物的副本上，輸出剛好是該有的那份」
    case exactOutput(String)
    /// 輔助執行（取清單、做前置），harness 不看它的結果——不計入任何一邊
    case none

    var tag: String {
        switch self {
        case .red: return "red"
        case .green: return "green"
        case .exactOutput: return "output"
        case .none: return "none"
        }
    }

    func isMet(rc: Int32, stdout: String) -> Bool {
        switch self {
        case .red: return rc != 0
        case .green: return rc == 0
        case .exactOutput(let want): return rc == 0 && stdout == want
        case .none: return true
        }
    }
}

/// 子行程的結果。`combined` 是 stdout 接 stderr（各 harness 原本的 `exec` 回傳的就是這個）。
struct GuardSpawn {
    let status: Int32
    let stdout: String
    let stderr: String
    var combined: String { stdout + stderr }
}

enum GuardRunLog {
    static let envKey = "AKASHIC_GUARD_RUN_LOG"
    static let formatVersion = 1
    /// 本行程的 run id。第一次被讀到時產生（`recordGuardStart()` 在分派前就讀它）。
    static let runID = UUID().uuidString

    static var path: String? {
        guard let p = ProcessInfo.processInfo.environment[envKey], !p.isEmpty else { return nil }
        return p
    }

    /// 本行程的子命令名（`akashic-guards <名>` 的 `<名>`）。
    static var selfName: String {
        CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : ""
    }

    /// symlink 解開、`.`／`..` 化簡後的絕對路徑。`.build/debug` 是指向 `.build/<triple>/debug` 的 symlink，
    /// 不解開的話同一支 binary 會有兩個名字。
    static func resolvedExecutable(_ path: String) -> String {
        let url = path.hasPrefix("/") ? URL(fileURLWithPath: path)
                                      : URL(fileURLWithPath: path, relativeTo: URL(fileURLWithPath: repoRoot))
        return url.absoluteURL.resolvingSymlinksInPath().standardizedFileURL.path
    }

    /// 本行程自己的 binary（解開後）。`migrated-guard-control` 拿它比對 `invoke` 的 `exe`。
    static var ownExecutable: String {
        resolvedExecutable(Bundle.main.executablePath ?? CommandLine.arguments[0])
    }

    /// 寫一行。環境變數未設定時不做任何事；**設定了卻寫不進去是致命的**（exit 74）——紀錄少一行，
    /// `migrated-guard-control` 會把它讀成「沒有跑」，那是錯的方向，所以在這裡就停下來、說出為什麼。
    static func append(_ fields: [String: Any]) {
        guard let path else { return }
        var obj = fields
        obj["v"] = formatVersion
        obj["run"] = runID
        obj["self"] = selfName
        guard JSONSerialization.isValidJSONObject(obj),
              var data = try? JSONSerialization.data(withJSONObject: obj, options: [.sortedKeys, .withoutEscapingSlashes])
        else { fail(path, "這一行無法編成 JSON") }
        data.append(0x0A)
        let fd = open(path, O_WRONLY | O_APPEND | O_CREAT, 0o644)
        guard fd >= 0 else { fail(path, "開不了檔（errno \(errno)）") }
        defer { close(fd) }
        // 一次 `write` 寫完整行：`O_APPEND` 讓每一次 write 都接在檔尾，同一行不會被別的行程插進來
        let ok = data.withUnsafeBytes { buf -> Bool in
            var off = 0
            while off < buf.count {
                let n = write(fd, buf.baseAddress! + off, buf.count - off)
                if n <= 0 { return false }
                off += n
            }
            return true
        }
        if !ok { fail(path, "寫入失敗（errno \(errno)）") }
    }

    private static func fail(_ path: String, _ why: String) -> Never {
        FileHandle.standardError.write(Data("✗ 寫不進負控的執行紀錄 \(path)：\(why)——紀錄少一行會被讀成「沒有跑」，所以停在這裡\n".utf8))
        exit(74)
    }
}

/// `main.swift` 在分派之前呼叫：這個行程開始了。
func recordGuardStart() {
    GuardRunLog.append(["event": "start"])
}

/// 分派的出口：寫 `end`（含 rc）再結束。沒經過這裡就結束的行程（直接 `exit`、crash）沒有 `end`，
/// 它執行過的東西不算數（`migrated-guard-control` 只採用以 rc=0 結束的 harness 的紀錄）。
func finishGuard(_ rc: Int32) -> Never {
    GuardRunLog.append(["event": "end", "rc": Int(rc)])
    exit(rc)
}

/// harness 在執行時宣告它是哪幾支守衛的負控。命名慣例（`<g>-mutations` 宣告 `<g>`）不必呼叫。
///
/// **為什麼要宣告，不只看執行**（#689 R1 verify，沿用到執行期）：`plugin-roots-mutations` 為了驗 plugin 根而讓
/// `trigger-coverage` 變紅，那不是 `trigger-coverage` 的負控——它有自己的 harness，刪掉那支時要紅。
func declareNegativeControl(for guards: [String]) {
    GuardRunLog.append(["event": "declare", "for": guards])
}

/// **harness 執行守衛的唯一入口**（#707）：跑子行程、等它結束，若它是 `akashic-guards <子命令>` 就寫一筆 `invoke`。
///
/// - `env`：加在繼承的環境之上。`AKASHIC_GUARD_RUN_LOG` 先從繼承的環境拿掉（理由見檔頭），要傳就明寫在這裡。
/// - `mergeOutput`：stdout 與 stderr 接同一根 pipe（依序交錯），`stdout` 裡是兩者、`stderr` 是空的。
///   分開時 stderr 寫進暫存檔而不是第二根 pipe——兩根 pipe 依序讀，其中一邊塞滿緩衝時兩個行程會互等
///   （`main.swift` 的 `Verdict` 記過 #394 R9 那次死鎖）。
/// - `label`：這一格的名字（寫進紀錄，截到 300 字）。
/// - `expect`：harness 的預期；成不成立由這裡用觀察到的 rc 與 stdout 算。**子行程根本沒跑起來時一律不成立**
///   （`met` 為 false，rc 是 127）：一次沒有發生的執行不能被記成「守衛如預期變紅」。
func runGuardProcess(_ argv: [String], cwd: String, env extra: [String: String] = [:],
                     mergeOutput: Bool = false, label: String, expect: GuardExpectation) -> GuardSpawn {
    precondition(!argv.isEmpty, "runGuardProcess：argv 是空的")
    let fm = FileManager.default
    let p = Process()
    p.executableURL = URL(fileURLWithPath: argv[0])
    p.arguments = Array(argv.dropFirst())
    p.currentDirectoryURL = URL(fileURLWithPath: cwd)
    var env = ProcessInfo.processInfo.environment
    env.removeValue(forKey: GuardRunLog.envKey)
    for (k, v) in extra { env[k] = v }
    p.environment = env

    let out = Pipe()
    var errFile: String? = nil
    if mergeOutput {
        p.standardOutput = out; p.standardError = out
    } else {
        let f = NSTemporaryDirectory() + "guard-stderr-" + UUID().uuidString
        fm.createFile(atPath: f, contents: nil)
        errFile = f
        p.standardOutput = out
        p.standardError = FileHandle(forWritingAtPath: f) ?? FileHandle.nullDevice
    }
    defer { if let f = errFile { try? fm.removeItem(atPath: f) } }

    let result: GuardSpawn
    var spawned = false
    if (try? p.run()) != nil {
        spawned = true
        let od = out.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        let ed = errFile.flatMap { fm.contents(atPath: $0) } ?? Data()
        result = GuardSpawn(status: p.terminationStatus,
                            stdout: String(data: od, encoding: .utf8) ?? "",
                            stderr: String(data: ed, encoding: .utf8) ?? "")
    } else {
        result = GuardSpawn(status: 127, stdout: "", stderr: "spawn 失敗：\(argv[0])")
    }

    if (argv[0] as NSString).lastPathComponent == "akashic-guards", argv.count >= 2 {
        GuardRunLog.append([
            "event": "invoke",
            "target": argv[1],
            "exe": GuardRunLog.resolvedExecutable(argv[0]),
            "argv": argv.dropFirst().map { String($0.prefix(200)) },
            "case": String(label.prefix(300)),
            "expect": expect.tag,
            "rc": Int(result.status),
            // 沒有跑起來的子行程（`spawn 失敗` 的 rc=127）不能算「如預期變紅」——那是 harness 自稱做了一次它沒做的執行
            "met": spawned && expect.isMet(rc: result.status, stdout: result.stdout),
        ])
    }
    return result
}

/// 內部：`runGuardProcess` 對「根本沒跑起來」的子行程怎麼記（#707）。不在 `run-guards.sh` 裡；
/// `migrated-guard-control-mutations` 帶自己的紀錄檔執行它、讀回那一筆 `invoke`——`met` 必須是 false。
func spawnProbe() -> Int32 {
    _ = runGuardProcess(["/nonexistent/akashic-guards", "decision-matrix-drift"], cwd: repoRoot,
                        label: "spawn 不起來", expect: .red)
    return 0
}
