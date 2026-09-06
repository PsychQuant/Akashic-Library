import ArgumentParser
import Foundation
import AkashicCore
import AkashicMCPKit

/// generic add-only 補值（#458）：`akashic enrich --from <file.json> [--apply] [--include-absent-authors] [--json]`。
///
/// 政策寫在 `AddOnlyEnrichment` 的型別註解裡（canonical 說明，此處不複製一份會分岔的副本）；
/// `enrich-from-zotero` 是它的 Zotero adapter。這裡只記 CLI 面的三個決定：
///
/// 1. **`--from` 收 `[Proposal]` JSON 檔**，不收命令列 key=value——一批提案動輒上百筆、值是整段摘要，
///    命令列裝不下也逃脫不完；檔案由腳本產、由人審。解析走 `AddOnlyEnrichment.decodeProposals`，
///    與 MCP 面同一個解析器。
/// 2. **dry-run 是預設**，且 dry-run 印的就是 apply 會寫的那份計畫。`--apply` 走 #298 的破壞性
///    目標閘：提案逐筆指名 citekey／DOI、沒有篩選式批次，但它仍改寫既有記錄檔，而豁免一個寫入
///    命令需要的理由比加上它多（同 `enrich-from-zotero`）。
/// 3. **`--json` 原樣轉印 service payload**，人可讀分支從**同一個 payload** 渲染——不重新查、
///    不重新判斷（`entity-backlink-completeness` 執行細節 2）。CLI 面不截 items（人的終端機可捲、
///    可 pipe）；MCP 面截 20，要全部就用這裡。
struct EnrichCmd: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "enrich",
        abstract: "generic add-only 補值：以 citekey 或 DOI 指名 work，只補 fields 裡不存在的鍵（doi／pmid／isbn 走結構化欄位、issn 拒；不動 type／title／venues；作者需 --include-absent-authors 且僅在完全為空時）")

    @OptionGroup var options: LibraryOptions

    @Option(name: .long, help: "提案 JSON 檔：[{citekey|doi, fields{…}, date?, authors?, sourceDigest?}]（每筆 citekey 或 doi 恰一個）")
    var from: String

    @Flag(name: .long, help: "實際寫入（預設只列出計畫）")
    var apply = false

    @Flag(name: .long, help: "entry 的 authors 完全為空時補提案裡的 literal 作者（非空一律不動）")
    var includeAbsentAuthors = false

    @Flag(name: .long, help: "輸出 service 的 JSON payload 原樣")
    var json = false

    func run() throws {
        if apply { try options.assertDestructiveTargetNamed("enrich") }

        let url = URL(fileURLWithPath: (from as NSString).expandingTildeInPath)
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw ValidationError("找不到提案檔：\(displaySafe(url.path, max: 300))")
        }
        let proposals: [AddOnlyEnrichment.Proposal]
        do {
            proposals = try AddOnlyEnrichment.decodeProposals(from: try Data(contentsOf: url))
        } catch let e as AddOnlyEnrichment.InputError {
            // 訊息含檔案裡的鍵名＝未信任字串
            throw ValidationError(displaySafe(e.description, max: 400))
        }

        // **`key:` 必帶**（#220 HIGH）：漏掉會讓已註冊的 store 被當成 keyless 而長出第二份 index。
        let store = try options.openStore()
        let service = AkashicService(root: store.root, key: store.key,
                                     environment: ProcessInfo.processInfo.environment)
        let payload: String
        do {
            payload = try service.enrich(proposals: proposals, dryRun: !apply,
                                         includeAbsentAuthors: includeAbsentAuthors, itemLimit: nil)
        } catch let e as ServiceError {
            throw ValidationError(e.errorDescription ?? String(describing: e))   // display-safe-exempt: service 已在 throw 站點消毒
        }

        if json {
            print(payload)
            return
        }

        // 人可讀分支從**同一個 payload** 渲染——不重新查、不重新判斷。值已由 service 逐個 displaySafe。
        let obj = (try? JSONSerialization.jsonObject(with: Data(payload.utf8))) as? [String: Any] ?? [:]
        let counts = obj["counts"] as? [String: Int] ?? [:]
        func n(_ k: String) -> Int { counts[k] ?? 0 }
        print("提案 \(obj["proposals"] as? Int ?? proposals.count) 筆："   // display-safe-exempt: Int
              + "可補 \(n("added"))、已有 \(n("skipped"))、DOI 歧義 \(n("ambiguous"))、"   // display-safe-exempt: Int
              + "找不到 \(n("notFound"))、只有被拒的 \(n("rejected"))")   // display-safe-exempt: Int

        let items = obj["items"] as? [[String: Any]] ?? []
        for item in items {
            let idx = (item["index"] as? Int ?? 0) + 1
            let ck = item["citekey"] as? String ?? "—"
            let category = item["category"] as? String ?? "?"
            print("")
            print("  [\(idx)] \(ck)  \(category)")   // display-safe-exempt: service 已對每個值 displaySafe；index 是 Int
            for a in item["additions"] as? [[String: String]] ?? [] {
                let kind = a["kind"] == "identifier" ? "（結構化）" : ""
                print("    + \(a["key"] ?? "")\(kind) = \(a["value"] ?? "")")   // display-safe-exempt: service 已對每個值 displaySafe
            }
            for k in item["alreadyPresent"] as? [String] ?? [] {
                print("    = \(k)（已有，未動）")   // display-safe-exempt: service 已對每個值 displaySafe
            }
            if let matches = item["matches"] as? [String], !matches.isEmpty {
                print("    命中：\(matches.joined(separator: "、"))")   // display-safe-exempt: service 已對每個值 displaySafe
            }
            if let reason = item["reason"] as? String {
                print("    · \(reason)")   // display-safe-exempt: service 已對每個值 displaySafe
            }
            for r in item["refused"] as? [String] ?? [] {
                print("    ✗ 不採用：\(r)")   // display-safe-exempt: service 已對每個值 displaySafe
            }
            // 部分成功另有通道（#394 verify R9）：解出的那些已經採用了，不能沿用 ✗。
            for r in item["partial"] as? [String] ?? [] {
                print("    ◐ 部分解析：\(r)")   // display-safe-exempt: service 已對每個值 displaySafe
            }
            if let digest = item["sourceDigest"] as? String {
                print("    來源：\(digest)（只記在報告，不進 store）")   // display-safe-exempt: service 已對每個值 displaySafe
            }
        }

        guard apply else {
            print("")
            print("（dry-run）加 --apply 實際寫入。**只加原本不存在的鍵**——既有值、type、title、venues 一律不動；"
                  + "作者僅在 --include-absent-authors 且 authors 完全為空時補。")
            return
        }
        let written = obj["written"] as? [String] ?? []
        print("")
        print("已寫入 \(written.count) 筆。")   // display-safe-exempt: Int
        if let failed = obj["writeFailed"] as? [String: String], !failed.isEmpty {
            print("寫入失敗 \(failed.count) 筆：")   // display-safe-exempt: Int
            for (k, e) in failed.sorted(by: { $0.key < $1.key }) {
                print("  \(k): \(e)")   // display-safe-exempt: service 已對每個值 displaySafe
            }
        }
    }
}
