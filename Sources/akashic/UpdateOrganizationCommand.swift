import ArgumentParser
import Foundation
import AkashicCore
import AkashicStoreIO
import AkashicMCPKit

/// #557：organization 的部分更新——先有 `--authorize` 與 `--unauthorize`（`authorized` 在此之前零寫入面）。
/// MCP 對應面是 `akashic_update_organization`；兩面同一個 `AkashicService.updateOrganization`（mcp-cli-parity 的 MCP 表那一列）。
struct UpdateOrganizationCmd: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "update-organization",
        abstract: "organization 的部分更新（#557）：--authorize 指定對外名稱（同書寫系統替換）、--unauthorize 撤回——語意與 update-venue 的同名兩條腿同一份。organization 無法唯一定位（\(UnlocatableReason.organization)）時整批拒絕、零寫入")

    @OptionGroup var options: LibraryOptions

    @Argument(help: "既有 organization key")
    var key: String

    @Option(name: .customLong("authorize"), parsing: .upToNextOption,
            help: ArgumentHelp("指定為對外名稱的名字（可多個）。**不是 append**：authorized 每個書寫系統（han／latn／other）至多一個，"
                             + "同書寫系統原本的指定移出 authorized、留在 names（報告 authorizedRemoved）；不同書寫系統之間才是 append。"
                             + "一次給兩個同書寫系統的名字是矛盾，整批拒絕。不在 names 的一併加進 names（canonical 形，報告 namesAdded）；"
                             + "相等看 canonical（前後／連續空白、NFC）。含控制／格式／不可見字元、或無任何字母或數字的名字整批拒絕。"
                             + "被換下來的舊指定若被 field: authorized 的 reference 指著，整批拒絕（organization 的 reference 沒有移除面，只能手改 YAML）。"
                             + "判定記錄待 #564（2026-10-01 裁決要留，另案落地）。其他報告：alreadyAuthorized（no-op 但不沉默）、"
                             + "authorizedRewritten（同名 NFD 舊指定換成 canonical）、authorizeDropped（整項空白）、authorizedTotal"))
    var authorize: [String] = []

    @Option(name: .customLong("unauthorize"), parsing: .upToNextOption,
            help: ArgumentHelp("撤回對外名稱（可多個，同 update-venue --unauthorize）：名字必須是現有的 authorized（相等看 canonical），"
                             + "移出 authorized、留在 names。不是現有成員、同一個名字又在 --authorize、被 field: authorized 的 reference 指著，"
                             + "都整批拒絕、零寫入。先於 --authorize 執行。報告：authorizedWithdrawn、unauthorizeDropped"))
    var unauthorize: [String] = []

    /// 只看 argv 的檢查早於開 store（#654）：與服務在讀 store 之前跑的是同一個函式
    func validate() throws {
        try argvCheck {
            try AkashicService.checkUpdateOrganizationArguments(key: key,
                                                                authorize: authorize.isEmpty ? nil : authorize,
                                                                unauthorize: unauthorize.isEmpty ? nil : unauthorize)
        }
    }

    func run() throws {
        let store = try options.openStore()
        let service = AkashicService(root: store.root, key: store.key,
                                     environment: ProcessInfo.processInfo.environment)
        // 寫入面封閉例外形：只回 service payload（mcp-cli-parity 的既有裁決）
        print(try service.updateOrganization(key: key,
                                             authorize: authorize.isEmpty ? nil : authorize,
                                             unauthorize: unauthorize.isEmpty ? nil : unauthorize))
    }
}
