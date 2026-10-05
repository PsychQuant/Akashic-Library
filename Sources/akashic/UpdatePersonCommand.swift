import Foundation
import ArgumentParser
import AkashicCore
import AkashicMCPKit

/// #68：person 的部分更新（CLI 面）。與 MCP 的 `akashic_update_person` 共用
/// `AkashicService.updatePerson` ——合併只有一條路，tolerant-preserve 與 canary 白拿。
struct UpdatePersonCmd: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "update-person",
        abstract: "person 的部分更新：提及的欄位整個換、未提及一律不動")

    @OptionGroup var options: LibraryOptions
    @Option(name: .long, help: "person key") var key: String
    @Option(name: .long, help: ArgumentHelp(
        "結構化欄位值（JSON object；缺席時讀 stdin）",
        discussion: "純量欄位收字串或 null（null＝清除）；names 收 {authorized:[…], "
            + "variant:[…]} object（全量替換；#227 巢狀化後平坦陣列拒收）；profile 收"
            + "維度 object（維度級覆寫，段形狀同 YAML：value/"
            + "start/end/ended/source/note）；references 收 object 陣列（append-only，與 update-venue --references 同一個解析，#674："
            + "retrieval 的 status 必填不預設 200、url 只收 http／https 且不含帳密、retrieved 是 ISO 8601、不認得的鍵拒收、"
            + "一次至多 200 筆／statement 4,096 位元組／rests_on 20 個；空陣列拒絕（#695）；verdict 欄位對拒收）"))
    var fields: String?
    @Flag(name: .long, help: "只預告會改什麼（含 format gate 預演），不寫入")
    var dryRun: Bool = false

    @Option(name: .long, help: ArgumentHelp(
        "--fields 的 names 動到 authorized 時的理由（#564）",
        discussion: "names 的替換讓名字進或出 authorized 時必填（只動 variant 的不必）；至多 4,096 位元組，開頭不得是組合符號或不可見字元、要有字母或數字。"
            + "只替有變動的名字寫（#564 使用者 2026-10-05 裁決）：每個成為對外形的名字寫一筆 field: authorized「指定：理由」、移到 variant 的寫「撤回：理由」，"
            + "仍是對外形的不寫；與那個名字最後一筆記錄位元組完全相同的不重寫，報告 judgementsRecorded（dry-run 是 judgementsToRecord）；需要 store format ≥ 22。"
            + "對外形不得整個離開 names（有沒有記錄都一樣：移出要寫撤回、記錄錨定 names——放在 variant，改正拼寫也是這樣一步做完，之後要刪再用 --remove-name）；"
            + "替換拿掉一個有記錄的名字也整批拒絕。給了理由而沒有名字進出 authorized、或替換會讓 person 沒有任何名字，都整批拒絕。authorized 一次至多 200 個（variant 不計）"))
    var judgement: String?

    @Option(name: .customLong("rests-on"), parsing: .upToNextOption,
            help: "--judgement 依據的證據 digest（sha256:64hex，0 byte 內容的 digest 拒收；先用 store-source 存檔）；可省略、至多 20 個，套用到這次的每一筆記錄")
    var restsOn: [String] = []

    @Option(name: .customLong("remove-name"),
            help: ArgumentHelp(
                "刪掉一個名字：<名字>=<理由>（可重複；以第一個 = 切）",
                discussion: "只收最後一筆名字分類記錄是「撤回」的名字（#564 第 2 點，打錯字的名字的出路）：從 variant 刪掉它，連同它的名字分類記錄。"
                    + "還在 authorized 的先用 --fields 的 names 把它移到 variant（附 --judgement，寫一筆撤回；需要 store format ≥ 22）。理由必填、只回在報告（namesRemoved）、不寫進 store；"
                    + "person 檔要已在 git 裡 commit、無未提交修改，未指名目標 store（--library／--yes）時拒絕（#564 使用者 2026-10-05 裁決：會刪判定記錄的面過閘；--dry-run 兩者都不檢查）。"
                    + "單獨呼叫，不與 --fields／--judgement／--rests-on 組合；一次至多 200 個。"
                    + "variant 裡沒有記錄的名字不必走這條（--fields 的 names 整份替換直接拿掉，只動 variant 不必附理由）；最後一筆不是撤回、被 field: names 的 reference 指著（person 的 reference 沒有移除面）、"
                    + "刪完 person 沒有任何名字，都整批拒絕、零寫入"))
    var removeName: [String] = []

    /// `--fields` 的值就是 argv——它不是 JSON object 是用法錯誤（64），在 `validate()` 擋、早於開 store（#549 R1）。
    /// 欄位名與各欄位的形狀也只看它（#654）：與服務套在既有記錄上的是同一個函式。stdin 來的同一份 JSON 是 argv 以外，不在這裡。
    func validate() throws {
        var dict: [String: Any]?
        if let fields {
            guard let d = Self.jsonObject(Data(fields.utf8)) else {
                throw ValidationError("--fields 必須是 JSON object")
            }
            dict = d
        }
        try argvCheck {
            // #564：--judgement／--rests-on／--remove-name 與 --fields 的組合、理由的形狀、名字數上限。fields 從 stdin 來時看不到它，
            // 組合的檢查留給服務（執行期，#549 邊界 1）——否則一句合法的「stdin 帶 names ＋ --judgement」會在這裡被說成「沒有 names」
            if dict != nil || !removeName.isEmpty {
                try AkashicService.checkUpdatePersonArguments(fields: dict, judgement: judgement,
                                                              restsOn: restsOn.isEmpty ? nil : restsOn,
                                                              removeNames: removeName.isEmpty ? nil : removeName)
            }
            if let dict, removeName.isEmpty { try AkashicService.checkUpdatePersonFields(dict) }
        }
    }

    private static func jsonObject(_ raw: Data) -> [String: Any]? {
        (try? JSONSerialization.jsonObject(with: raw)) as? [String: Any]
    }

    func run() throws {
        let dict: [String: Any]
        if !removeName.isEmpty {
            dict = [:]   // #564 第 2 點：刪名字是單獨呼叫，不讀 stdin
        } else if let fields, let d = Self.jsonObject(Data(fields.utf8)) {
            dict = d
        } else {
            // stdin 不是 argv：內容不對是執行期失敗（1），與 create-entry 從 stdin／--file 讀到壞 JSON 同一類（#549 R1）
            guard let d = Self.jsonObject(FileHandle.standardInput.readDataToEndOfFile()) else {
                throw RuntimeFailure.state("stdin 必須是 JSON object（或改用 --fields 直接給）")
            }
            dict = d
        }
        // #564 使用者 2026-10-05 裁決第 4 點：--remove-name 會刪判定記錄、以 key ＋ 名字定位（錯的 store 上照樣對得上，#580 的判準）——過目標確認閘
        if !removeName.isEmpty && !dryRun { try options.assertDestructiveTargetNamed("update-person", flag: "--remove-name", dryRunFlag: "--dry-run") }
        let store = try options.openStore()
        // `key:` 不可省——見 `PersonCommand.swift` 的長註解（verify #220 HIGH）。
        // **先前的註解說「寫入路徑所以沒炸」——那是假的**（#218 R2 verify MEDIUM，
        // regression 與 DA 兩個 lens 各自打臉）。這兩支同樣走 `ensureFreshIndex()`，
        // 在已註冊的 store 裡會**建整份第二個 index**；`create-entry` 之後 `query`
        // 看不到新資料，而且不自癒（query 的 `ensureCurrent()` 不看 mtime）。
        // 差別只在它們的**主要產出**不取自 index，不是它們不碰 index。
        let service = AkashicService(root: store.root, key: store.key,
                                     environment: ProcessInfo.processInfo.environment)
        // 輸出是 service 的 JSON（已 displaySafe）——CLI 原樣轉印
        print(try LegacyCopyReport.payload {   // #705：writtenWithLegacyCopy 進這份 JSON
            try service.updatePerson(key: key, fields: dict, dryRun: dryRun, fieldsGiven: removeName.isEmpty,
                                     judgement: judgement, restsOn: restsOn.isEmpty ? nil : restsOn,
                                     removeNames: removeName.isEmpty ? nil : removeName)
        })
    }
}
