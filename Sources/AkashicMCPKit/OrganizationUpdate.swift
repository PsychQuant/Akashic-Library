import Foundation
import AkashicCore
import AkashicStoreIO
import AkashicIndex

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
/// 一併加進 names。替換與撤回的邏輯是 `AuthorizedDesignation` 那一份（#554 從 `updateVenue` 搬出），這裡只做定位、寫入與報告。
/// `--unauthorize`（#559 的撤回）由同一份邏輯直接給出，兩面一起提供。
///
/// 子集關係與「每書寫系統至多一個」由 store 邊界擋（`writeOrganization` → `Organization.validate()` → `AuthorizedNames.validate`），
/// 這裡不重造。organization 沒有 venue 那道名字內容的不變式（#554 D8），新加進 names 的名字仍過入口的 vetting（canonical、逐項驗）——
/// 那是入口的輸入檢查，不是 store 的不變式。
///
/// ## 判定記錄
///
/// 指定與撤回都是判定（`two-kinds-of-edits` 的 AI 欄）。#564 已於 2026-10-01 裁決名字分類面全部要留判定記錄，另案落地（需要 store
/// format bump）；在那之前本面不寫記錄，報告的各桶就是那筆記錄要記的內容。
extension AkashicService {
    /// `update_organization` 只看參數的檢查與解析結果（#654 的形狀：CLI 的 `validate()` 呼叫同一個函式，早於開 store）。
    struct UpdateOrganizationArguments {
        let authorizeIn: [String]
        let authorizeBlanks: [String]
        let unauthorizeIn: [String]
        let unauthorizeBlanks: [String]
    }

    /// CLI 的 `validate()` 用：`update-organization` 只看參數的全部檢查。
    public static func checkUpdateOrganizationArguments(key: String, authorize: [String]?, unauthorize: [String]?) throws {
        _ = try updateOrganizationArguments(key: key, authorize: authorize, unauthorize: unauthorize)
    }

    static func updateOrganizationArguments(key: String, authorize: [String]?,
                                            unauthorize: [String]?) throws -> UpdateOrganizationArguments {
        guard StoreKey.isValid(key) else {
            throw ServiceError.invalid("organization key「\(displaySafeInvisible(key, max: 200))」不符合 \(StoreKey.pattern)")   // display-safe-exempt: StoreKey.pattern 是編譯期常量；key 已消毒
        }
        // 沒有要改的就不寫：一次沒有變動的寫入仍會重新序列化整筆記錄、重建 index，那不是呼叫端要的
        guard authorize != nil || unauthorize != nil else {
            throw ServiceError.invalid("沒有要改的——給 authorize（--authorize）或 unauthorize（--unauthorize）")
        }
        let (authorizeIn, authorizeBlanks) = try vetVenueNamesReportingBlanks(authorize, parameter: "authorize（--authorize）")
        let (unauthorizeIn, unauthorizeBlanks) = try vetVenueNamesReportingBlanks(unauthorize, parameter: "unauthorize（--unauthorize）")
        try refuseSameScriptClash(authorizeIn)
        try refuseAuthorizeUnauthorizeOverlap(authorizeIn: authorizeIn, unauthorizeIn: unauthorizeIn)
        return UpdateOrganizationArguments(authorizeIn: authorizeIn, authorizeBlanks: authorizeBlanks,
                                           unauthorizeIn: unauthorizeIn, unauthorizeBlanks: unauthorizeBlanks)
    }

    /// organization 的部分更新（#557）：`authorize` 同書寫系統替換、`unauthorize` 撤回——兩者的語意與 `updateVenue` 同一份
    /// （`AuthorizedDesignation`）。key 有不只一筆記錄時整批拒絕、零寫入（#669／#670：寫進哪一筆是猜）。
    public func updateOrganization(key: String, authorize: [String]?, unauthorize: [String]? = nil) throws -> String {
        let args = try Self.updateOrganizationArguments(key: key, authorize: authorize, unauthorize: unauthorize)
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
        let withdrawn = try designation.unauthorize(args.unauthorizeIn)   // 撤回先跑：成員資格看呼叫前的 authorized（同 venue）
        let report = try designation.authorize(args.authorizeIn)
        org.names = designation.names
        org.authorized = designation.authorized
        try store.writeOrganization(org)
        try LibraryIndex(store: store).rebuild()
        return try jsonString(["key": key,
                               "namesAdded": report.namesAdded.map { displaySafeInvisible($0, max: 200) },
                               "authorizedAdded": report.authorizedAdded.map { displaySafeInvisible($0, max: 200) },
                               "authorizedRemoved": report.authorizedRemoved.map { displaySafeInvisible($0, max: 200) },
                               "alreadyAuthorized": report.alreadyAuthorized.map { displaySafeInvisible($0, max: 200) },
                               "authorizedRewritten": report.authorizedRewritten.map { displaySafeInvisible($0, max: 200) },
                               "authorizeDropped": args.authorizeBlanks.map { displaySafeInvisible($0, max: 200) },
                               "authorizedWithdrawn": withdrawn.map { displaySafeInvisible($0, max: 200) },
                               "unauthorizeDropped": args.unauthorizeBlanks.map { displaySafeInvisible($0, max: 200) },
                               "authorizedTotal": org.authorized.count])   // display-safe-exempt: Int
    }
}
