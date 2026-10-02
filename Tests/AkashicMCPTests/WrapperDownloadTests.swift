import XCTest

/// `plugin/bin/akashic-mcp-wrapper.sh` 的下載行為（#630）。
///
/// 2026-09-24 13:51 實際發生：`binary_version` 推成 0.12.1 時 release 的 asset 還在上傳，
/// 按 tag 下載失敗，wrapper 退回下載「latest」（仍是 0.12.0），**卻把 0.12.1 寫進版本檔**。
/// 從此它以為自己是新版、永遠不再下載，而 binary 是舊的——使用者的 store 全被拒。
///
/// 以假的 `gh`／`curl` 與暫存 HOME 重現，不碰網路也不碰真的 `~/bin`。
final class WrapperDownloadTests: XCTestCase {
    private var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("wrapper-\(UUID().uuidString)")
        let fm = FileManager.default
        for d in ["home/bin", "plugin/bin", "plugin/.claude-plugin", "stubs"] {
            try fm.createDirectory(at: root.appendingPathComponent(d), withIntermediateDirectories: true)
        }
        let repo = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
        try fm.copyItem(at: repo.appendingPathComponent("plugin/bin/akashic-mcp-wrapper.sh"),
                        to: root.appendingPathComponent("plugin/bin/akashic-mcp-wrapper.sh"))
        try #"{"name": "akashic-mcp", "version": "0.13.1", "binary_version": "0.12.1"}"#
            .write(to: root.appendingPathComponent("plugin/.claude-plugin/plugin.json"), atomically: true, encoding: .utf8)
        try writeExecutable("home/bin/akashic-mcp", "#!/bin/bash\necho OLD\n")
        try "0.12.0\n".write(to: root.appendingPathComponent("home/bin/.akashic-mcp.version"),
                             atomically: true, encoding: .utf8)
        // 假 gh：`release download <TAG> …` 依 STUB_TAG_OK 成敗；不帶 tag（latest）預設成功並給 LATEST，STUB_LATEST_OK=0 時失敗
        try writeExecutable("stubs/gh", """
            #!/bin/bash
            [ "$1 $2" = "release download" ] || exit 1
            shift 2
            tagged=true; case "$1" in --*) tagged=false ;; *) shift ;; esac
            dir=""; while [ $# -gt 0 ]; do [ "$1" = "--dir" ] && dir="$2"; shift; done
            if $tagged; then
              [ "${STUB_TAG_OK:-0}" = 1 ] || exit 1
              printf '#!/bin/bash\\necho NEW\\n' > "$dir/akashic-mcp"
            else
              [ "${STUB_LATEST_OK:-1}" = 1 ] || exit 1
              printf '#!/bin/bash\\necho LATEST\\n' > "$dir/akashic-mcp"
            fi
            """)
        try writeExecutable("stubs/curl", "#!/bin/bash\nexit 1\n")
    }

    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: root) }

    private func writeExecutable(_ rel: String, _ text: String) throws {
        let u = root.appendingPathComponent(rel)
        try text.write(to: u, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: u.path)
    }

    private func runWrapper(tagOK: Bool) throws -> (out: String, version: String) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/bash")
        p.arguments = [root.appendingPathComponent("plugin/bin/akashic-mcp-wrapper.sh").path]
        p.environment = ["HOME": root.appendingPathComponent("home").path,
                         "PATH": root.appendingPathComponent("stubs").path + ":/usr/bin:/bin",
                         "STUB_TAG_OK": tagOK ? "1" : "0"]
        let o = Pipe(); p.standardOutput = o; p.standardError = Pipe()
        p.standardInput = FileHandle.nullDevice
        try p.run(); p.waitUntilExit()
        let out = String(data: o.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        let version = (try? String(contentsOf: root.appendingPathComponent("home/bin/.akashic-mcp.version"),
                                   encoding: .utf8)) ?? ""
        return (out.trimmingCharacters(in: .whitespacesAndNewlines),
                version.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    /// 沒有現成的 binary、兩條下載路徑都失敗：訊息要說出兩次嘗試（gh release download、再 curl 公開網址）、網址、真正可能的原因
    /// （沒有網路、asset 還沒上傳），而且**不**把原因說成 gh 沒登入——repo 是公開的，兩條都不需要登入（#693 R1 verify 第 15／16／26／27 列：
    /// 先前寫「下載走 gh，需先 gh auth login」，指錯方向）。
    ///
    /// **環境一定要帶 UTF-8 locale**（#693 R2 verify 第 2／6 列）：先前這裡的 `p.environment` 只有 HOME／PATH，等於強制 C locale，而 bash 3.2 在 UTF-8
    /// locale 下會把緊接在 `$VAR` 後面的全形標點讀成變數名的一部分、`set -u` 之下整支腳本以 unbound variable 中止——新訊息在使用者實際的 locale 下
    /// 一行也印不出來，兩支測試卻全綠。`locale` 預設 `en_US.UTF-8`；要換 locale 的測試自己傳。
    private func runWrapperWithoutABinary(withGh: Bool, locale: String = "en_US.UTF-8",
                                          pluginJSON: String? = nil) throws -> (status: Int32, err: String) {
        // 同一個測試可以連跑幾次（不同 locale、有無 gh），所以移除與建立都要可重複
        try? FileManager.default.removeItem(at: root.appendingPathComponent("home/bin/akashic-mcp"))
        try? FileManager.default.removeItem(at: root.appendingPathComponent("home/bin/.akashic-mcp.version"))
        if let pluginJSON {
            try pluginJSON.write(to: root.appendingPathComponent("plugin/.claude-plugin/plugin.json"), atomically: true, encoding: .utf8)
        }
        let stubs = root.appendingPathComponent(withGh ? "stubs" : "stubs-nogh")
        if !withGh {
            try FileManager.default.createDirectory(at: stubs, withIntermediateDirectories: true)
            try? FileManager.default.removeItem(at: stubs.appendingPathComponent("curl"))
            try FileManager.default.copyItem(at: root.appendingPathComponent("stubs/curl"), to: stubs.appendingPathComponent("curl"))
        }
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/bash")
        p.arguments = [root.appendingPathComponent("plugin/bin/akashic-mcp-wrapper.sh").path]
        p.environment = ["HOME": root.appendingPathComponent("home").path, "PATH": stubs.path + ":/usr/bin:/bin", "STUB_TAG_OK": "0", "STUB_LATEST_OK": "0",
                         "LANG": locale, "LC_ALL": locale]
        let e = Pipe(); p.standardOutput = Pipe(); p.standardError = e
        p.standardInput = FileHandle.nullDevice
        try p.run(); p.waitUntilExit()
        return (p.terminationStatus, String(data: e.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? "")
    }

    func testTheFailureMessageNamesBothAttemptsTheUrlAndTheRealCauses() throws {
        let r = try runWrapperWithoutABinary(withGh: true)
        XCTAssertFalse(r.err.contains("unbound variable"), "UTF-8 locale 下變數名吃掉全形標點（#693 R2）：\(r.err)")
        let url = "https://github.com/PsychQuant/Akashic-Library/releases/download/akashic-mcp-v0.12.1/akashic-mcp"
        XCTAssertEqual(r.status, 1, r.err)
        XCTAssertTrue(r.err.contains("gh release download akashic-mcp-v0.12.1"), "第一次嘗試：\(r.err)")
        XCTAssertTrue(r.err.contains("curl \(url)"), "第二次嘗試與網址：\(r.err)")
        XCTAssertTrue(r.err.contains("沒有網路") && r.err.contains("asset 還沒上傳"), "真正可能的原因：\(r.err)")
        XCTAssertTrue(r.err.contains("不需要 gh auth login"), "repo 是公開的：\(r.err)")
        XCTAssertFalse(r.err.contains("需先 gh auth login"), "不得再把原因說成 gh 沒登入：\(r.err)")
    }

    func testTheFailureMessageSaysWhenGhIsNotInstalled() throws {
        let r = try runWrapperWithoutABinary(withGh: false)
        XCTAssertFalse(r.err.contains("unbound variable"), "UTF-8 locale 下變數名吃掉全形標點（#693 R2）：\(r.err)")
        XCTAssertEqual(r.status, 1, r.err)
        XCTAssertTrue(r.err.contains("gh（沒有安裝，略過）"), r.err)
        XCTAssertTrue(r.err.contains("curl https://github.com/PsychQuant/Akashic-Library/releases/download/akashic-mcp-v0.12.1/akashic-mcp"), r.err)
    }

    /// 兩個 UTF-8 locale、兩條路徑都要印得出訊息；C locale 本來就正常，不是這個缺陷的證據，所以不列。
    func testTheFailureMessageSurvivesEveryUtf8LocaleOnBothPaths() throws {
        for locale in ["en_US.UTF-8", "C.UTF-8"] {
            for withGh in [true, false] {
                let r = try runWrapperWithoutABinary(withGh: withGh, locale: locale)
                XCTAssertFalse(r.err.contains("unbound variable"), "\(locale) withGh=\(withGh)：\(r.err)")
                XCTAssertTrue(r.err.contains("download failed"), "\(locale) withGh=\(withGh) 要印得出 ERROR 行：\(r.err)")
                XCTAssertTrue(r.err.contains("可能原因"), "\(locale) withGh=\(withGh) 要印得出原因行：\(r.err)")
            }
        }
    }

    /// plugin.json 讀不到版本時：不組出不存在的 `akashic-mcp-v` tag 與網址（#693 LOW）。gh 那條下載 latest，curl 那條走 latest 的固定網址。
    func testTheFailureMessageDoesNotInventATagWhenNoVersionIsConfigured() throws {
        for withGh in [true, false] {
            let r = try runWrapperWithoutABinary(withGh: withGh, pluginJSON: #"{"name": "akashic-mcp"}"#)
            XCTAssertEqual(r.status, 1, r.err)
            XCTAssertFalse(r.err.contains("akashic-mcp-v"), "沒有版本就不得印出 tag：\(r.err)")
            XCTAssertTrue(r.err.contains("curl https://github.com/PsychQuant/Akashic-Library/releases/latest/download/akashic-mcp"),
                          "沒有版本時 curl 走 latest：\(r.err)")
            XCTAssertTrue(r.err.contains("最新 release 的 asset 還沒上傳"), r.err)
        }
    }

    /// 13:51 的情形：指定版本的 tag 下載失敗時，不得退回 latest、不得改版本檔，沿用現有 binary
    func testTaggedDownloadFailureKeepsExistingBinaryAndVersionFile() throws {
        let r = try runWrapper(tagOK: false)
        XCTAssertEqual(r.version, "0.12.0", "版本檔必須維持實際擁有的版本，下次啟動才會重試")
        XCTAssertEqual(r.out, "OLD", "必須沿用現有 binary，不得換成 latest")
    }

    func testTaggedDownloadSuccessInstallsThatVersion() throws {
        let r = try runWrapper(tagOK: true)
        XCTAssertEqual(r.version, "0.12.1")
        XCTAssertEqual(r.out, "NEW")
    }
}
