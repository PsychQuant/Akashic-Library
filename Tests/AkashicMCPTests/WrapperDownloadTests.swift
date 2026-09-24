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
        // 假 gh：`release download <TAG> …` 依 STUB_TAG_OK 成敗；不帶 tag（latest）一律成功並給 LATEST
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
