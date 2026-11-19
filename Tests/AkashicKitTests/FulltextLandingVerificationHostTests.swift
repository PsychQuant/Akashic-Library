import XCTest
import Foundation
@testable import AkashicSkillTools

/// #781 第 3 輪 verify 第 3 列：落點那一段只在新分頁的主機是被按的那一頁的主機、或已知的驗證服務時才收下它。驗證服務在 SKILL 的 `jq` 裡
/// 寫了一份（`def vsvc:` 那一行），這裡把它對 `BotSignals.isKnownVerificationService` 釘住：兩份對每一個網址都要說同一句話。
final class FulltextLandingVerificationHostTests: XCTestCase {
    private func repoRoot() throws -> URL {
        var dir = URL(fileURLWithPath: #filePath)
        for _ in 0..<10 {
            dir.deleteLastPathComponent()
            if FileManager.default.fileExists(atPath: dir.appendingPathComponent("Package.swift").path) { return dir }
        }
        throw XCTSkip("找不到 repo root")
    }

    private func jqPath() throws -> String {
        try XCTUnwrap(["/usr/bin/jq", "/opt/homebrew/bin/jq"].first { FileManager.default.isExecutableFile(atPath: $0) }, "需要 jq")
    }

    // spec-example: fulltext-division-of-labour / The verification hosts of the landing block are BotSignals'
    func testTheLandingBlocksVerificationHostsAreBotSignals() throws {
        let jq = try jqPath()
        let skill = try String(contentsOf: try repoRoot().appendingPathComponent("plugin/skills/akashic-fetch-fulltext/SKILL.md"), encoding: .utf8)
        let def = try XCTUnwrap(skill.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }.first { $0.hasPrefix("def vsvc:") },
                                "SKILL 的落點那一段沒有 def vsvc: 那一行")
        let urls = [
            "https://challenges.cloudflare.com/turnstile/v0/x", "https://a.challenges.cloudflare.com/x", "https://hcaptcha.com/x",
            "https://newassets.hcaptcha.com/captcha/v1", "https://recaptcha.net/recaptcha/api2", "https://www.recaptcha.net/x",
            "https://www.google.com/recaptcha/api2/anchor?k=1", "https://google.com/recaptcha/x", "https://www.google.com/search?q=recaptcha",
            "https://mail.google.com/recaptcha/x", "http://challenges.cloudflare.com/x", "HTTPS://HCAPTCHA.COM/x",
            "https://evilhcaptcha.com/x", "https://hcaptcha.com.evil.example/x", "https://user@hcaptcha.com/x", "https://hcaptcha.com:8443/x",
            "https://evil.example\\.hcaptcha.com/x", "https://hcaptcha.com", "https://pub.example/doi/10.1/x", "about:blank", "", "//hcaptcha.com/x",
        ]
        for url in urls {
            let p = Process()
            p.executableURL = URL(fileURLWithPath: jq)
            p.arguments = ["-nr", "--arg", "u", url, "\(def) $u | vsvc"]
            let out = Pipe(); p.standardOutput = out; p.standardError = Pipe()
            try p.run(); p.waitUntilExit()
            XCTAssertEqual(p.terminationStatus, 0, url)
            let said = String(decoding: out.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
            XCTAssertEqual(said, String(BotSignals.isKnownVerificationService(url: url)), url)
        }
    }
}
