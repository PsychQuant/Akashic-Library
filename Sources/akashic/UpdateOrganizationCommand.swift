import ArgumentParser
import Foundation
import AkashicCore
import AkashicStoreIO
import AkashicMCPKit

/// #557：organization 的部分更新——先有 `--authorize`（`authorized` 在此之前零寫入面）。
/// MCP 對應面是 `akashic_update_organization`；兩面同一個 `AkashicService.updateOrganization`（mcp-cli-parity 的 MCP 表那一列）。
/// 沒有 `--unauthorize`：裁決只說先提供 `--authorize`，而 organization 的 names 只增不減，撤回會讓剛加進 names 的名字成為 fallback 顯示名
/// （`OrganizationUpdate.swift` 的檔頭；待使用者裁決）。
struct UpdateOrganizationCmd: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "update-organization",
        abstract: "organization 的部分更新（#557）：--authorize 指定對外名稱（同書寫系統替換）——語意與 update-venue --authorize 同一份；沒有 --unauthorize（organization 的 names 只增不減，待裁）。organization 無法唯一定位（\(UnlocatableReason.organization)）時整批拒絕、零寫入")

    @OptionGroup var options: LibraryOptions

    @Argument(help: "既有 organization key")
    var key: String

    @Option(name: .customLong("authorize"), parsing: .upToNextOption,
            help: ArgumentHelp("指定為對外名稱的名字（可多個）。**不是 append**：authorized 每個書寫系統（han／latn／other）至多一個，"
                             + "同書寫系統原本的指定移出 authorized、留在 names（報告 authorizedRemoved）；不同書寫系統之間才是 append。"
                             + "被換下的名字可以再用 --authorize 指定回來（同書寫系統替換，位置不變）。"
                             + "一次給兩個同書寫系統的名字是矛盾，整批拒絕。不在 names 的一併加進 names（canonical 形，報告 namesAdded；organization 沒有名字的移除面，加進去的會留著）；"
                             + "相等看 canonical（前後／連續空白、NFC）。含控制／格式／不可見字元、或無任何字母或數字的名字整批拒絕（本來就在 names 裡的也一樣，出路是手改 YAML）。"
                             + "被換下來的舊指定若被 field: authorized 的 reference 指著，整批拒絕（organization 的 reference 沒有移除面，只能手改 YAML）。"
                             + "沒給、或只有空白項，整批拒絕（沒有要改的，用法錯誤 64）；給的名字都已是對外名稱＝不寫檔（報告 alreadyAuthorized）。"
                             + "判定記錄待 #564（2026-10-01 裁決要留，另案落地）。其他報告：authorizedRewritten（同名 NFD 舊指定換成 canonical）、"
                             + "authorizeDropped（整項空白）、authorizedNotCurrent（指定的名字在 names 的各段都已結束，displayName 會變成退役名）、authorizedTotal；"
                             + "寫檔成功而 index 重建失敗時，報告多 indexRebuilt: false 與 indexNote（要跑 akashic doctor 重建）"))
    var authorize: [String] = []

    /// 只看 argv 的檢查早於開 store（#654）：與服務在讀 store 之前跑的是同一個函式
    func validate() throws {
        try argvCheck {
            try AkashicService.checkUpdateOrganizationArguments(key: key, authorize: authorize)
        }
    }

    func run() throws {
        let store = try options.openStore()
        let service = AkashicService(root: store.root, key: store.key,
                                     environment: ProcessInfo.processInfo.environment)
        // 寫入面封閉例外形：只回 service payload（mcp-cli-parity 的既有裁決）
        print(try service.updateOrganization(key: key, authorize: authorize))
    }
}
