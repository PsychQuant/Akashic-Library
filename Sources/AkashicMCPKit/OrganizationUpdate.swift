import Foundation
import AkashicCore
import AkashicStoreIO

/// #557：organization 的 `authorized` 寫入面（`update-organization --authorize`／`akashic_update_organization`）。
///
/// ## 為什麼有這一條
///
/// `Organization.authorized` 對齊 RDA 的 authorized access point（`Organization.swift` 的 doc），`doctor` 也把空的 authorized 算進
/// `no authorized name: … organization`——而在此之前**沒有任何面寫得進它**：`addOrganization` 不收、`OrgBootstrap` 不寫、
/// `authorize-names` 只管 person。2026-09-11 實測 live store 13 筆 organization、有 authorized 0 筆：那不是「還沒填」，是「填不了」，
/// `doctor` 那一行恆為真且無法消除。`displayName` 因此全部走 fallback（`names.current` 或裸 key）。
///
/// ## 語意與 venue 同一份
///
/// 使用者 2026-10-01 裁決：選形狀 2（新增 `update-organization` 面），先提供 `--authorize`，語意比照 `update-venue --authorize`——
/// 同 `WritingSystem` 原子替換，被換下來的名字移出 authorized、留在 names（organization 沒有 variant，本來就不會被標）；不在 names 的
/// 一併加進 names。替換的邏輯是 `AuthorizedDesignation` 那一份（#554 從 `updateVenue` 搬出），這裡只做定位、寫入與報告。
///
/// **沒有 `--unauthorize`**（#557 R1 verify 之後拿掉）：裁決只說「先提供 `--authorize`」，首輪實作順手加了撤回，是實作者的判斷不是使用者的
/// 裁決；而且它在 organization 上不是 venue 那個「回到誠實的未判定狀態」——organization 的 `names` 只增不減（沒有名字的移除面），
/// `authorize` 為了讓 authorized 成為 names 的子集會把新名字加進 names，撤回之後名字留著、authorized 回到空，`displayName` 的 fallback
/// 是 `names.current`（沒有時間欄位時取序列化順序最後一筆）——剛加進去的名字因此成為顯示名與匯出的 `name_current`（R1 verify DA 真 binary 重現）。
/// 待使用者裁決（連同 organization 要不要有名字的移除面）。
///
/// 子集關係與「每書寫系統至多一個」由 store 邊界擋（`writeOrganization` → `Organization.validate()` → `AuthorizedNames.validate`），
/// 這裡不重造。organization 沒有 venue 那道名字內容的不變式（#554 D8），要指定的名字仍過入口的 vetting（canonical、逐項驗）——
/// 那是入口的輸入檢查，不是 store 的不變式。**誠實邊界**：入口 vetting 對「本來就在 names 裡、含不可見字元」的名字也擋（先 vet 後查 names），
/// 而 organization 沒有任何面改或刪名字——那種名字（`add_organization` 照收）指定不了，出路是手改 YAML。沒有改它：先 canonical 查找再 vet
/// 會讓含不可見字元的名字進得了 authorized，而 organization 沒有 D8 的 store 不變式擋它（R1 verify 第 14／27 列，記錄在案、待裁）。
///
/// ## 判定記錄（#564）
///
/// 指定是判定（`two-kinds-of-edits` 的 AI 欄）。使用者 2026-10-01 裁決名字分類面要留判定記錄（五個面，organization 的是 `--authorize`）：
/// 理由（`judgement`）必填、證據（`rests_on`）可空，每次指定、確認各寫一筆 `field: authorized` 的記錄
/// （`AuthorizedDesignation.judgementRecords`），被 `authorize` 換下的舊指定也寫一筆撤回；需要 store format ≥ 22（寫入閘）。
/// organization 沒有 variant，不會有 `field: variant` 的記錄。
///
/// **organization 沒有撤回腿**：`--unauthorize` 已於 #557 R1 verify 之後拿掉（見上），待使用者裁決；所以名字分類的五個面裡 organization 只有
/// `--authorize`（撤回的裁決是 #559 對 venue 下的）。
extension AkashicService {
    /// `update_organization` 只看參數的檢查與解析結果（#654 的形狀：CLI 的 `validate()` 呼叫同一個函式，早於開 store）。
    struct UpdateOrganizationArguments {
        let authorizeIn: [String]
        let authorizeBlanks: [String]
        /// #564：理由與證據；`authorize` 一定有非空白的名字（沒有就在 `updateOrganizationArguments` 拒絕），所以恆非 nil
        let judgement: AuthorizedDesignation.Judgement?
    }

    /// CLI 的 `validate()` 用：`update-organization` 只看參數的全部檢查。
    public static func checkUpdateOrganizationArguments(key: String, authorize: [String],
                                                        judgement: String? = nil, restsOn: [String]? = nil) throws {
        _ = try updateOrganizationArguments(key: key, authorize: authorize, judgement: judgement, restsOn: restsOn)
    }

    static func updateOrganizationArguments(key: String, authorize: [String], judgement: String? = nil,
                                            restsOn: [String]? = nil) throws -> UpdateOrganizationArguments {
        guard StoreKey.isValid(key) else {
            throw ServiceError.invalid("organization key「\(displaySafeInvisible(key, max: 200))」不符合 \(StoreKey.pattern)")   // display-safe-exempt: StoreKey.pattern 是編譯期常量；key 已消毒
        }
        let (authorizeIn, authorizeBlanks) = try vetVenueNamesReportingBlanks(authorize, parameter: "authorize（--authorize）")
        // 沒有要改的就不寫：沒給、給了空陣列、或全是空白項是同一件事（R1 verify 第 13／16／26／28 列：MCP 的 `[]` 與 `[" "]` 曾走完寫檔與重建
        // index，而 CLI 把空陣列轉成 nil 早就擋了——兩面不一致，也與這句註解的意圖相反）。看**過了 vetting 的結果**，不看原始的 optional。
        guard !authorizeIn.isEmpty else {
            throw ServiceError.invalid("沒有要改的——authorize（--authorize）要給至少一個名字（沒給、空陣列、全是空白項都算沒給）")
        }
        try refuseSameScriptClash(authorizeIn)
        // #564：理由必填、證據可空（venue 同一個函式）。上面已擋掉沒有要指定的名字，所以走到這裡一定在分類
        let nameJudgement = try nameClassificationJudgement(classifying: true, judgement: judgement, restsOn: restsOn)
        return UpdateOrganizationArguments(authorizeIn: authorizeIn, authorizeBlanks: authorizeBlanks, judgement: nameJudgement)
    }

    /// organization 的部分更新（#557）：`authorize` 同書寫系統替換——語意與 `updateVenue` 同一份（`AuthorizedDesignation`）。
    /// key 有不只一筆記錄時整批拒絕、零寫入（#669／#670：寫進哪一筆是猜）。
    ///
    /// **都已是對外名稱而又沒有新記錄可寫＝不寫檔、不重建 index**（R1 verify 第 28 列）：一次沒有變動的寫入仍會重新序列化整筆記錄（人手編過的排版被正規化）、
    /// 重建 index；報告的 `alreadyAuthorized` 照給（冪等但不沉默）。**#564 起對已是對外名稱的名字說「確認」也留一筆記錄**，所以那是「有新記錄」、照寫；
    /// 同一句理由再確認一次（位元組完全相同）才是沒有新記錄。**寫檔成功之後 index 重建失敗不讓呼叫失敗**（第 1 列）：檔案已經落盤、
    /// 報告是改了什麼的唯一一份，重試只會得到 `alreadyAuthorized`——用移除面一族的做法（`RemovalReportSupport.swift`），報告多 `indexRebuilt: false`。
    public func updateOrganization(key: String, authorize: [String], judgement: String? = nil,
                                   restsOn: [String]? = nil) throws -> String {
        let args = try Self.updateOrganizationArguments(key: key, authorize: authorize, judgement: judgement, restsOn: restsOn)
        let load = try store.load()
        guard !load.organizations.unlocatableOrganizationKeys.contains(key) else {
            throw ServiceError.invalid("organization「\(displaySafeInvisible(key, max: 200))」無法唯一定位（\(UnlocatableReason.organization)）——整批拒絕、零寫入；先改掉其中一筆的 key")   // display-safe-exempt: UnlocatableReason.organization 是編譯期常量
        }
        guard var org = load.organizations.first(where: { $0.key == key }) else {
            throw ServiceError.notFound("organization「\(displaySafeInvisible(key, max: 200))」")
        }
        var designation = AuthorizedDesignation(
            names: org.names, authorized: org.authorized, variant: [], references: org.references,
            owner: .init(noun: "organization", referenceRemoval: nil))
        let report = try designation.authorize(args.authorizeIn)
        // 指定的名字在 names 裡的每一段都已結束：`authorized` 的 doc 說「從當前有效的名稱中指定」是慣例、`validate` 不擋，而本面是第一個寫得進它的面
        // （R1 verify 第 6／17 列）。不拒絕（沒有裁決要擋），但說出來：`displayName` 會變成那個已退役的名字。新加進 names 的名字沒有時間欄位、是開放段，不會在這裡。
        let designated = report.authorizedAdded + report.alreadyAuthorized + report.authorizedRewritten
        let notCurrent = designated.filter { name in
            let segments = designation.names.entries.filter { NameIdentity.canonical($0.value) == NameIdentity.canonical(name) }
            return !segments.isEmpty && segments.allSatisfy { !$0.range.isOpen }
        }
        let changed = !report.namesAdded.isEmpty || !report.authorizedAdded.isEmpty
            || !report.authorizedRemoved.isEmpty || !report.authorizedRewritten.isEmpty
        org.names = designation.names
        org.authorized = designation.authorized
        var judgementsRecorded = 0
        if let judgement = args.judgement {
            judgementsRecorded = NameClassificationRecord.append(
                AuthorizedDesignation.judgementRecords(withdrawn: [], authorize: report, judgement: judgement),
                to: &org.references)
        }
        var payload: [String: Any] = ["key": key,
                                      "namesAdded": report.namesAdded.map { displaySafeInvisible($0, max: 200) },
                                      "authorizedAdded": report.authorizedAdded.map { displaySafeInvisible($0, max: 200) },
                                      "authorizedRemoved": report.authorizedRemoved.map { displaySafeInvisible($0, max: 200) },
                                      "alreadyAuthorized": report.alreadyAuthorized.map { displaySafeInvisible($0, max: 200) },
                                      "authorizedRewritten": report.authorizedRewritten.map { displaySafeInvisible($0, max: 200) },
                                      "authorizeDropped": args.authorizeBlanks.map { displaySafeInvisible($0, max: 200) },
                                      "authorizedTotal": org.authorized.count,   // display-safe-exempt: Int
                                      "judgementsRecorded": judgementsRecorded]   // display-safe-exempt: Int
        if !notCurrent.isEmpty { payload["authorizedNotCurrent"] = notCurrent.map { displaySafeInvisible($0, max: 200) } }
        guard changed || judgementsRecorded > 0 else { return try jsonString(payload) }
        try store.writeOrganization(org)
        if let failure = rebuildIndexCapturingFailure() {
            Self.noteIndexRebuildFailure(failure, in: &payload,
                                         written: "這次 authorize 已經寫入磁碟——報告裡的 authorizedAdded／authorizedRemoved 是改了什麼，重試只會得到 alreadyAuthorized，先把報告存下來。")
        }
        return try jsonString(payload)
    }
}
