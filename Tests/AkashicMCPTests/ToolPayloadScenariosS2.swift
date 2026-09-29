import XCTest
import Foundation
@testable import AkashicS2

/// `akashic_s2`（#664）的情境。它不經 `AkashicService`、走 async 的 `S2Tool.run`，所以另放一檔。
///
/// 不連網：base URL 覆寫到本機、請求由 `S2ToolStub`（`S2ToolTests.swift`）攔截；覆寫 base URL 時不讀 keychain（#664 design）。
/// 情境閉包是同步的，以 semaphore 等 async 結果——`S2Tool.run` 不依賴 main actor，阻塞呼叫端的執行緒不會卡死它。
extension ToolPayloadScenarios {
    static let s2: [PayloadScenario] = [
        PayloadScenario("akashic_s2", "references（分頁端點）") { _ in
            S2ToolStub.install { request in
                if request.url!.path.hasSuffix("/references") {
                    let rows: [[String: Any]] = [["citedPaper": ["paperId": "p0", "title": "A"]]]
                    return (200, try! JSONSerialization.data(withJSONObject: ["offset": 0, "data": rows]))
                }
                return (200, try! JSONSerialization.data(withJSONObject: ["paperId": "seed", "referenceCount": 1]))
            }
            return try runS2(S2ToolArguments(endpoint: "references", id: "DOI:10.1/x", fields: [], limit: 10))
        },
        PayloadScenario("akashic_s2", "status") { _ in
            try runS2(S2ToolArguments(endpoint: "status"))
        },
    ]

    private static func runS2(_ args: S2ToolArguments) throws -> String {
        let stateDir = NSTemporaryDirectory() + "s2-payload-\(UUID().uuidString)"
        defer { try? FileManager.default.removeItem(atPath: stateDir) }
        let env = ["HOME": NSTemporaryDirectory(), "AKASHIC_S2_STATE_DIR": stateDir,
                   "AKASHIC_S2_KEYCHAIN_SERVICE": "akashic-test-\(UUID().uuidString)",
                   "AKASHIC_S2_BASE_URL": "http://127.0.0.1:9"]
        let box = OutcomeBox()
        let done = DispatchSemaphore(value: 0)
        let session = S2ToolStub.session()
        Task.detached {
            box.set(await S2Tool.run(args, environment: env, session: session))
            done.signal()
        }
        guard done.wait(timeout: .now() + 30) == .success else {
            throw NSError(domain: "ToolPayloadScenariosS2", code: 1, userInfo: [NSLocalizedDescriptionKey: "akashic_s2 情境逾時"])
        }
        let outcome = try XCTUnwrap(box.get())
        if outcome.isError {
            throw NSError(domain: "ToolPayloadScenariosS2", code: 2, userInfo: [NSLocalizedDescriptionKey: outcome.text])
        }
        return outcome.text
    }
}

private final class OutcomeBox: @unchecked Sendable {
    private let lock = NSLock()
    private var value: S2ToolOutcome?
    func set(_ v: S2ToolOutcome) { lock.lock(); value = v; lock.unlock() }
    func get() -> S2ToolOutcome? { lock.lock(); defer { lock.unlock() }; return value }
}
