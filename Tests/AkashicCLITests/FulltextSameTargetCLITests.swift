import XCTest
import Foundation

/// #781 第 4 輪 verify 第 1、2 列：`akashic fulltext same-target`——按了頁面上這篇自己的連結之後多出來的那一個分頁，顯示的是不是那個連結指的網址。
/// 真 binary。三個值都從檔案讀（頁面決定的字串不經命令列）；不碰瀏覽器、不連網、不寫任何檔。
final class FulltextSameTargetCLITests: XCTestCase {
    private var base: URL!

    override func setUpWithError() throws {
        base = FileManager.default.temporaryDirectory.appendingPathComponent("akashic-same-target-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: base) }

    private func run(_ args: [String]) throws -> (status: Int32, out: String, err: String) {
        let p = Process()
        p.executableURL = CLITestHarness.productsDirectory.appendingPathComponent("akashic")
        p.arguments = args
        p.environment = ProcessInfo.processInfo.environment.filter { !$0.key.hasPrefix("AKASHIC_") }
        let out = Pipe(), err = Pipe()
        p.standardOutput = out; p.standardError = err; p.standardInput = FileHandle.nullDevice
        try p.run()
        let o = out.fileHandleForReading.readDataToEndOfFile(), e = err.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        return (p.terminationStatus, String(decoding: o, as: UTF8.self), String(decoding: e, as: UTF8.self))
    }

    private func path(_ name: String) -> String { base.appendingPathComponent(name).path }

    /// 三個檔各寫一個值（結尾帶換行，與 `jq -r`、`get attr` 的輸出一樣；nil 就不寫那個檔），跑命令。
    private func judge(page: String?, href: String?, tab: String?) throws -> (status: Int32, out: String, err: String) {
        for (name, value) in [("page", page), ("href", href), ("tab", tab)] {
            try? FileManager.default.removeItem(atPath: path(name))
            if let value { try Data((value + "\n").utf8).write(to: URL(fileURLWithPath: path(name))) }
        }
        return try run(["fulltext", "same-target", "--page-file", path("page"), "--href-file", path("href"), "--tab-file", path("tab")])
    }

    private static let page = "https://pub.example/doi/full/10.1/x?a=1#akashic-0123456789abcdef"

    // spec-example: fulltext-division-of-labour / Same-target verdicts
    func testSameTargetVerdicts() throws {
        let rows: [(href: String, tab: String, printed: String)] = [
            ("/doi/pdf/10.1/x", "https://pub.example/doi/pdf/10.1/x", "match"),                       // 根相對
            ("/doi/pdf/10.1/x", "https://pub.example/doi/pdf/10.1/x#page=2", "match"),                // 片段不比
            ("https://pub.example/doi/pdf/10.1/x", "https://PUB.example:443/doi/pdf/10.1/x", "match"), // 絕對；主機大小寫、預設埠號
            ("x.pdf", "https://pub.example/doi/full/10.1/x.pdf", "match"),                            // 相對路徑
            ("?download=true", "https://pub.example/doi/full/10.1/x?download=true", "match"),         // 只有查詢字串
            ("//cdn.example/x.pdf", "https://cdn.example/x.pdf", "match"),                            // 沒有 scheme 的 //
            ("/a/./b/../c", "https://pub.example/a/c", "match"),                                      // 路徑裡的 . 與 ..
            ("/redirect", "https://pub.example/target", "differ"),                                    // 轉址過的連結（2026-11-20 實測的 M2e）
            ("/doi/pdf/10.1/x", "https://pub.example/doi/pdf/10.1/x?token=1", "differ"),              // 查詢字串不同
            ("/doi/pdf/10.1/x", "http://pub.example/doi/pdf/10.1/x", "differ"),                       // 新分頁不是 https
            ("/doi/pdf/10.1/x", "favorites://", "differ"),                                            // ⌘T 的分頁（M3）
            ("/doi/pdf/10.1/x", "", "differ"),                                                        // 新分頁沒有網址
            ("#", "https://pub.example/doi/full/10.1/x?a=1", "unresolvable"),                         // 只有片段（M5 的按鈕）
            ("", "https://pub.example/doi/full/10.1/x?a=1", "unresolvable"),                          // 空的
            ("javascript:void(0)", "https://pub.example/x", "unresolvable"),                          // 不是 http(s) 的 scheme
            ("http://pub.example/x.pdf", "http://pub.example/x.pdf", "unresolvable"),                 // http
            ("https://u:p@pub.example/x.pdf", "https://pub.example/x.pdf", "unresolvable"),           // 帶帳密
            ("/a b", "https://pub.example/a%20b", "unresolvable"),                                    // 要轉寫的字元
            ("/doi/full/10.1/x?a=1", "https://pub.example/doi/full/10.1/x?a=1", "unresolvable"),      // 解析之後就是那一頁自己
        ]
        for row in rows {
            let r = try judge(page: Self.page, href: row.href, tab: row.tab)
            XCTAssertEqual(r.status, 0, "\(row) \(r.err)")
            XCTAssertEqual(r.out, row.printed + "\n", "href \(row.href)、分頁 \(row.tab)")
        }
    }

    /// 規格的表以外、同一條規則的幾個邊角：都往不收的方向。
    func testSameTargetNeverMatchesWhatItCannotResolve() throws {
        let rows: [(page: String, href: String, tab: String, printed: String)] = [
            (Self.page, "  /doi/pdf/10.1/x  ", "https://pub.example/doi/pdf/10.1/x", "match"),                   // 屬性前後的空白（瀏覽器會去掉）
            (Self.page, "/doi/pdf/10.1/x", "https://pub.example:8443/doi/pdf/10.1/x", "differ"),                // 埠號不同
            (Self.page, "/doi/pdf/10.1/x", "https://pub.example.evil.example/doi/pdf/10.1/x", "differ"),        // 主機只是前綴相同
            (Self.page, "/doi/pdf/10.1/x", "https://user@pub.example/doi/pdf/10.1/x", "differ"),                // 新分頁帶帳密
            (Self.page, "/doi/pdf/10.1/x?", "https://pub.example/doi/pdf/10.1/x", "differ"),                    // 空的查詢字串與沒有查詢字串
            (Self.page, "mailto:a@pub.example", "https://pub.example/x", "unresolvable"),
            (Self.page, "data:text/html,x", "https://pub.example/x", "unresolvable"),
            (Self.page, "file:///etc/hosts", "https://pub.example/x", "unresolvable"),
            (Self.page, "/a\\b", "https://pub.example/a/b", "unresolvable"),                                    // 反斜線
            (Self.page, "/é", "https://pub.example/%C3%A9", "unresolvable"),                                    // 非 ASCII
            (Self.page, "/a\tb", "https://pub.example/ab", "unresolvable"),                                     // 中間的 tab
            (Self.page, "https://pub.example\\@evil.example/x", "https://evil.example/x", "unresolvable"),
            (Self.page, "//10.0.0.1/x.pdf", "https://10.0.0.1/x.pdf", "match"),                                 // 主機的形狀只看 DNS 名稱的字元；按不按是第 1 步的事
            ("https://user:pw@pub.example/a", "/b", "https://pub.example/b", "unresolvable"),                   // 那一頁自己的網址帶帳密
            ("about:blank", "/b", "https://pub.example/b", "unresolvable"),
            ("https://pub.example/a\nhttps://evil.example/a", "/b", "https://pub.example/b", "unresolvable"),   // 頁面的檔有兩行
        ]
        for row in rows {
            let r = try judge(page: row.page, href: row.href, tab: row.tab)
            XCTAssertEqual(r.status, 0, "\(row) \(r.err)")
            XCTAssertEqual(r.out, row.printed + "\n", "頁面 \(row.page)、href \(row.href)、分頁 \(row.tab)")
        }
    }

    // spec-example: fulltext-division-of-labour / Same-target reads files and refuses what it cannot read
    func testSameTargetReadsFilesAndRefusesWhatItCannotRead() throws {
        // 2026-11-20 的測試頁是本機的 http：這個命令只收 https 與 DNS 名稱，所以對它們一律不收
        var r = try judge(page: "http://127.0.0.1:47231/a", href: "/b", tab: "http://127.0.0.1:47231/b")
        XCTAssertEqual(r.status, 0, r.err)
        XCTAssertEqual(r.out, "unresolvable\n")
        // href 的檔不在（第 1 步沒有讀到 href）：當成沒有 href
        r = try judge(page: Self.page, href: nil, tab: "https://pub.example/doi/pdf/10.1/x")
        XCTAssertEqual(r.status, 0, r.err)
        XCTAssertEqual(r.out, "unresolvable\n")
        // 新分頁或那一頁的檔讀不到：什麼都不印，結束碼 1
        r = try judge(page: Self.page, href: "/doi/pdf/10.1/x", tab: nil)
        XCTAssertEqual(r.status, 1)
        XCTAssertEqual(r.out, "")
        r = try judge(page: nil, href: "/doi/pdf/10.1/x", tab: "https://pub.example/doi/pdf/10.1/x")
        XCTAssertEqual(r.status, 1)
        XCTAssertEqual(r.out, "")
        // 三個值都只從檔案來：沒有收網址的選項
        let help = try run(["fulltext", "same-target", "--help"])
        XCTAssertEqual(help.status, 0)
        for option in ["--page-file", "--href-file", "--tab-file"] { XCTAssertTrue(help.out.contains(option), help.out) }
        for option in ["--page ", "--href ", "--tab ", "--url"] { XCTAssertFalse(help.out.contains(option), "不該有 \(option)：\(help.out)") }
        r = try run(["fulltext", "same-target", "--page", Self.page, "--href", "/x", "--tab", "https://pub.example/x"])
        XCTAssertEqual(r.status, 64, "值不能寫在命令列上")
        XCTAssertEqual(r.out, "")
    }

    /// 太長的內容不是一個網址。
    func testAnOversizedFileIsNotResolved() throws {
        let r = try judge(page: Self.page, href: "/" + String(repeating: "a", count: 70_000), tab: "https://pub.example/x")
        XCTAssertEqual(r.status, 0, r.err)
        XCTAssertEqual(r.out, "unresolvable\n")
    }
}
