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
        abstract: "organization 的部分更新（#557）：--authorize 指定對外名稱（同書寫系統替換）——語意與 update-venue --authorize 同一份，必附 --judgement（名字分類的判定記錄，#564）；沒有 --unauthorize（organization 的 names 只增不減，待裁）。organization 無法唯一定位（\(UnlocatableReason.organization)）時整批拒絕、零寫入")

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
                             + "沒給、或只有空白項，整批拒絕（沒有要改的，用法錯誤 64）。必附 --judgement（#564）：寫 field: authorized 的判定記錄，同 update-venue --authorize；"
                             + "給的名字都已是對外名稱時寫一筆「確認」（報告 alreadyAuthorized），同一句理由已記過（位元組完全相同）才不寫檔。"
                             + "其他報告：authorizedRewritten（同名 NFD 舊指定換成 canonical）、"
                             + "authorizeDropped（整項空白）、authorizedNotCurrent（指定的名字在 names 的各段都已結束，displayName 會變成退役名）、authorizedTotal；"
                             + "寫檔成功而 index 重建失敗時，報告多 indexRebuilt: false 與 indexNote（要跑 akashic doctor 重建）"))
    var authorize: [String] = []

    @Option(name: .long,
            help: ArgumentHelp("理由（#564）：--authorize 必填，至多 4,096 位元組；每次指定、確認各寫一筆 field: authorized 的判定記錄"
                + "（「指定／確認：理由」，被換下的舊指定也寫一筆「撤回」），位元組完全相同的不重寫，報告 judgementsRecorded；需要 store format ≥ 22"))
    var judgement: String?

    @Option(name: .customLong("rests-on"), parsing: .upToNextOption,
            help: "理由依據的證據 digest（sha256:64hex，0 byte 內容的 digest 拒收；先用 store-source 存檔）；可省略、至多 20 個，套用到這次的每一筆記錄")
    var restsOn: [String] = []

    /// 只看 argv 的檢查早於開 store（#654）：與服務在讀 store 之前跑的是同一個函式
    func validate() throws {
        try argvCheck {
            try AkashicService.checkUpdateOrganizationArguments(key: key, authorize: authorize,
                                                                judgement: judgement, restsOn: restsOn.isEmpty ? nil : restsOn)
        }
    }

    func run() throws {
        let store = try options.openStore()
        let service = AkashicService(root: store.root, key: store.key,
                                     environment: ProcessInfo.processInfo.environment)
        // 寫入面封閉例外形：只回 service payload（mcp-cli-parity 的既有裁決）
        print(try service.updateOrganization(key: key, authorize: authorize,
                                             judgement: judgement, restsOn: restsOn.isEmpty ? nil : restsOn))
    }
}
