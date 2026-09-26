import Foundation
import AkashicCore

/// 一個 **view 的判準**（#54／#65）。
///
/// ## 為什麼住在 `config.yaml` 而不是 `entities/`
///
/// `docs/explainers/entity-vs-view.md` 已經拍板，本型別只是把那個決定落地：
///
/// - **判準**（「隸屬時間軸匹配統計所」這個條件本身）→ `config.yaml`。**它是設定，
///   不是知識。**
/// - **外延**（實際符合的那組人與著作）→ 衍生索引，可以隨時丟掉重算。
///
/// **view 不是 entity**，本型別不動 `EntityKind`、不新增形狀裸標籤、`entities/`
/// 不會出現 `view:`。#54 的裁決不因為「現在有實作了」而鬆動——實作的位置正是它
/// 當時被指定的位置。
///
/// ## 缺這一半的代價（#65 記錄的實例）
///
/// 判準被推到 store 之外，由每個下游消費者各自重新發明。storyline#5 的
/// `4AK_build_duckdb.R` 裡那段 filter **就是**這裡該有的東西——只是它住在另一個
/// repo、另一種語言、另一個人維護的檔案裡。後果是判準不可稽核、會分岔、無法演化，
/// 而成員清單被迫用一份 `.txt` 代替（**外延被當成判準用**，正是 explainer 警告的
/// 方向反轉）。
public struct ViewDefinition: Equatable {
    public var key: String
    public var description: String?
    /// person 的判準：隸屬（`affiliations`）匹配這個 organization key。
    ///
    /// **只收 `.key` 不收 `.literal`**：未歸戶的 literal 是合法的長期狀態，但拿它
    /// 當判準會讓 view 的成員資格隨拼寫漂移。要納入某個 literal，先把它歸戶
    /// （`resolve-organizations`）——那才是那個動作存在的理由。
    public var personAffiliation: String?
    /// work 的判準：作者裡有人屬於本 view 的 person 外延。
    ///
    /// **以 view 自身為參照，不是再寫一次條件**：兩處各寫一次就是 #65 說的
    /// 「判準會分岔」在同一個檔案裡重演。
    public var workHasAuthorInView: Bool

    public init(key: String, description: String? = nil,
                personAffiliation: String? = nil, workHasAuthorInView: Bool = false) {
        self.key = key
        self.description = description
        self.personAffiliation = personAffiliation
        self.workHasAuthorInView = workHasAuthorInView
    }
}

/// view 的**外延**——誰在裡面。
///
/// 這是衍生物：不寫進 `entities/`、不進版控、可以隨時丟掉重算。
public struct ViewExtension: Equatable {
    public let key: String
    /// 符合判準的 person key（排序）。
    public let people: [String]
    /// 作者裡有人在 `people` 內的 work citekey（排序）。
    public let works: [String]
}

public extension ViewExtension {
    /// 依外延把一份 load 收斂成匯出用的子集（#274）。**純函式**——不碰磁碟。
    ///
    /// 收斂語意（FK 完整性優先，三條都是為了讓下游關聯表不出現懸空外鍵）：
    /// - `entries`：citekey 在 `works` 內。
    /// - `people`：外延成員 **∪ 被保留著作引用的 `.key` 作者**。合著者若被濾掉，
    ///   `RelationalExport` 會把已歸戶的 `.key` 退化成 `researcher_id IS NULL` ＋
    ///   name_full 印 key 字串——那把「已歸戶但非成員」與「未歸戶」折成同一個觀察，
    ///   事後無法區分。view 的語意是「這些著作與相關的人」，合著者屬於相關的人。
    /// - `organizations`：被保留 person 的隸屬時間軸引用的 `.key` 機構、**被保留著作的團體作者**（#596——
    ///   publication_author 的 organization_id 外鍵與顯示名靠它），加上其 `parents` 的**遞移閉包**
    ///   （organization 表的 parent_id 外鍵）。
    ///   `.literal` 與懸空 `.key` 本來就由 `RelationalExport` 回 NULL，不在此補。
    func scope(_ load: LibraryLoad) -> (entries: [Entry], people: [Person],
                                        organizations: [Organization]) {
        let workSet = Set(works)
        let entries = load.entries.filter { workSet.contains($0.citekey) }

        var personKeys = Set(people)
        for e in entries {
            for a in e.authors {
                if case let .key(k) = a { personKeys.insert(k) }
            }
        }
        let keptPeople = load.people.filter { personKeys.contains($0.key) }

        // 機構閉包：隸屬引用與團體作者起步，沿 parents 走到頂（worklist；懸空的 .key 走不動，
        // 自然終止——不造 id 的立場與 RelationalExport 一致）
        let orgByKey = Dictionary(load.organizations.map { ($0.key, $0) },
                                  uniquingKeysWith: { a, _ in a })
        var orgKeys = Set<String>()
        var worklist: [String] = []
        for p in keptPeople {
            for v in p.profile.affiliations.entries {
                if case let .key(k) = v.value { worklist.append(k) }
            }
        }
        // #596：作者位指到的機構（團體作者）與隸屬同待遇——不收的話 publication_author 的 organization_id
        // 接不上外鍵、name_full 拿不到顯示名。
        for e in entries {
            for a in e.authors {
                if case let .organization(k) = a { worklist.append(k) }
            }
        }
        while let k = worklist.popLast() {
            guard !orgKeys.contains(k), let org = orgByKey[k] else { continue }
            orgKeys.insert(k)
            for v in org.parents.entries {
                if case let .key(pk) = v.value { worklist.append(pk) }
            }
        }
        let keptOrgs = load.organizations.filter { orgKeys.contains($0.key) }
        return (entries, keptPeople, keptOrgs)
    }
}

public extension ViewDefinition {
    /// 算出外延。**純函式**——輸入是一份 `LibraryLoad`，不碰磁碟。
    ///
    /// person 側：`profile.affiliations` 的任一段 `.key` 等於 `personAffiliation`。
    /// **不比對時間範圍**——「現在還在不在」是另一個問題（`DateRange` 的
    /// `endedUnknown` 語意未定，見 #63），而 view 要回答的是「屬於過」。
    /// 那個取捨寫在這裡，不留給呼叫端各自猜。
    func extension_(in load: LibraryLoad) -> ViewExtension {
        var people: [String] = []
        if let org = personAffiliation {
            people = load.people.filter { p in
                p.profile.affiliations.entries.contains {
                    if case let .key(k) = $0.value { return k == org }
                    return false
                }
            }.map(\.key).sorted()
        }
        var works: [String] = []
        if workHasAuthorInView, !people.isEmpty {
            let member = Set(people)
            works = load.entries.filter { e in
                e.authors.contains {
                    if case let .key(k) = $0 { return member.contains(k) }
                    return false
                }
            }.map(\.citekey).sorted()
        }
        return ViewExtension(key: key, people: people, works: works)
    }
}
