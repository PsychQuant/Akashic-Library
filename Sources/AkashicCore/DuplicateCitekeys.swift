import Foundation

/// `LibraryStore.load()` 對一筆 work／person **檔案處境**的觀察（#641）——**不是記錄內容**。
///
/// entities 佈局的 store 若還留著 legacy 殘留（`entries/<citekey>.yaml`／`people/<key>.yaml`），寫入當下的
/// #631 前置（`LibraryStore.entryWritePlan`／`personWritePlan`）會對某些記錄一定拒絕：同一個 id 兩份並存、
/// 目的檔 `entities/<id>.yaml` 被 quarantine 或其實是另一種記錄、legacy 單份不能安全搬移（key 與檔名不符、
/// 不受 git 追蹤或有未 commit 的修改）。那個拒絕若發生在多檔寫入者的中途，前面幾筆已經落盤、store 被撕成一半
/// （#641：judge、refute、org apply、repoint、demote、migrate-identifiers 都以真 binary 重現過）。
///
/// load 用**同一組**前置判斷（不另寫一份）先算出哪些記錄一定寫不進去，記在這裡；`unlocatableCitekeys`／
/// `unlocatablePersonKeys` 把它算進「無法唯一定位」，於是 #627／#628 已經接好的各面閘在**第一次寫入之前**就拒絕或
/// 略過它們。寫入當下的 #631 檢查留著當最後一道防線。
///
/// - YAML 不讀也不寫它；手工組出來的記錄恆為 `nil`。只有 `LibraryStore.load()`（讀磁碟的那一條）設定它——
///   `decodeCaptured` 的唯讀快照不設（它的契約是不重讀磁碟，而判斷要看 git；快照沒有寫入者）。
/// - **不參與相等**：相等問的是記錄內容。兩筆內容相同的記錄是同一筆，不論 load 當時看到它的檔案處境如何——
///   否則 `a == b` 型的比較（WoS 的「unchanged」判定、`changedSlots`、org apply 的「有沒有改到」）會把一筆
///   只是被觀察到有問題的記錄當成「內容變了」。
public struct FileSituation: Equatable {
    /// 寫入這筆記錄時 #631 的寫入前置一定會拒絕的原因（**已消毒**——load 以 `displaySafeError` 建構）；`nil`＝沒有。
    public var unwritableReason: String?

    public init(unwritableReason: String? = nil) {
        self.unwritableReason = unwritableReason
    }

    /// 恆等——見型別 doc 的「不參與相等」。
    public static func == (lhs: FileSituation, rhs: FileSituation) -> Bool { true }
}

/// 「無法唯一定位」說給人聽的那一句（#641）——各寫入面的拒絕與略過訊息都用它，不各寫一份。
///
/// 先前每個面各寫一句「citekey 重複或與另一筆 work 共用 id」（二十幾處）；第 3 類併進定義之後，那句話對第 3 類的記錄
/// 是假的，而二十幾份副本不會一起改。這裡只說有哪幾種、去哪裡看是哪一種，不說是哪一種——那由 `akashic validate` 逐筆列出。
public enum UnlocatableReason {
    /// `unlocatableCitekeys` 的三類。
    public static let work = "citekey 重複、與另一筆 work 共用 id，或它的檔案寫入時會被拒——akashic validate 列出是哪一種"
    /// `unlocatablePersonKeys` 的兩類。
    public static let person = "person key 重複，或它的檔案寫入時會被拒——akashic validate 列出是哪一種"
}

extension Collection where Element == Entry {   // 多次遍歷——限定 Collection（#627 R3：Sequence 不保證能重走，單次序列會回空集合＝把重複當成可定位）
    /// 出現兩次以上的 citekey（#627）。寫入路徑要問的是涵蓋更廣的 `unlocatableCitekeys`。
    ///
    /// citekey 重複是 store「被支援的損壞態」：載入不拒、`validate` 另行報告。但寫入路徑
    /// 多半以 citekey 當 entry 的唯一鍵，用 `Dictionary(…, uniquingKeysWith:)` 靜默選一筆——
    /// 於是判定可能寫到**另一筆 work 的另一個作者**上，而且不出聲。凡是以 citekey 定位
    /// entry 的寫入面，都先問 `unlocatableCitekeys`：命中就拒絕或具名略過，不猜是哪一筆。
    ///
    /// **只有這一個定義**——各路徑各算一次會長出兩種「重複」的意思。
    public var duplicatedCitekeys: Set<String> {
        var seen = Set<String>(), dup = Set<String>()
        for e in self where !seen.insert(e.citekey).inserted { dup.insert(e.citekey) }
        return dup
    }

    /// 無法唯一定位一筆 work 檔的 citekey。**封閉三類**（不得依性質相似類推第四類）：
    ///
    /// 1. citekey 重複（#627）。
    /// 2. 該 entry 的 id 與另一筆共用（#627 R2）。citekey 本身唯一，但寫入以 id 定檔（`entities/<id>.yaml`），改它等於
    ///    改兄弟的檔——實測 drop-author 會把另一筆 work 整個蓋掉。
    /// 3. load 判定它的檔案寫入時一定會被拒（`fileSituation.unwritableReason`，#641）：legacy 殘留加上 quarantine、
    ///    兩份並存或不能安全搬移。那一格的拒絕發生在寫入當下，而寫入者多半一次寫好幾個檔——先前前面幾筆已經落盤
    ///    才撞上它。現在它與前兩類一起在第一次寫入之前被各面閘擋下。
    ///
    /// resolve-people、resolve-venues、resolve-organizations 各腿、tag／link／set-status、library、enrich 一族、
    /// migrate-identifiers、import-wos 的回填、App 的裁決台問的都是這個集合。第 3 類只在 `LibraryStore.load()` 讀進來的記錄上有值——手工組出來的
    /// entries 只看得到前兩類。
    public var unlocatableCitekeys: Set<String> {
        var idCount: [UUID: Int] = [:]
        for e in self { idCount[e.id, default: 0] += 1 }
        var out = duplicatedCitekeys
        for e in self where idCount[e.id, default: 0] > 1 { out.insert(e.citekey) }
        for e in self where e.fileSituation.unwritableReason != nil { out.insert(e.citekey) }   // #641
        return out
    }
}

extension Collection where Element == Person {
    /// 出現兩次以上的 person key（#641；`crossRecordIssues` 另把它報成 error）。
    public var duplicatedPersonKeys: Set<String> {
        var seen = Set<String>(), dup = Set<String>()
        for p in self where !seen.insert(p.key).inserted { dup.insert(p.key) }
        return dup
    }

    /// 無法唯一定位一筆 person 檔的 key（#641）——`unlocatableCitekeys` 的 person 版。**封閉兩類**（不得依性質相似類推第三類）：
    ///
    /// 1. key 重複：寫入面以 key 定位 person（`Dictionary(…, uniquingKeysWith:)`），重複時靜默選一筆。
    /// 2. load 判定它的檔案寫入時一定會被拒（`fileSituation.unwritableReason`）——與作品側第 3 類同一組判斷。
    ///
    /// **作品側的「與另一筆共用 id」刻意不收**，理由逐條、各有可查的出處：
    /// - index 的 people 表以 key 為主鍵（`LibraryIndex`：`people(key TEXT PRIMARY KEY, …)`），共用 id 不會讓 rebuild 丟掉一筆；
    ///   作品側收它的一半理由是 index 的 entries 以 UUID 為主鍵、會靜默丟掉一筆（`crossRecordIssues` 報 error），這一半在 person 側不存在。
    /// - 另一半理由是「寫入以 id 定檔、改它等於改兄弟的檔」。entities 佈局下兩筆 person 不可能都住在 `entities/`（檔名就是 id），
    ///   所以共用 id 必然有一筆是 legacy 殘留——那一筆寫入時會被 #631 拒（兩份並存），load 已經把它標進第 2 類；
    ///   住在 `entities/` 的那一筆寫的是它自己的檔，收進來只會多擋一筆寫得進去的記錄（`LoadTimeUnlocatableTests` 釘住兩半）。
    ///   legacy 佈局下寫入以 key 定檔，共用 id 不碰兄弟。
    ///
    /// 寫 person 的多檔寫入者（resolve-people 的 apply／reject／judge／refute／undecided、resolve-organizations 以 person
    /// 為 holder 的各腿、App 的裁決台、authorize-names）在第一次寫入之前問它：命中就拒絕或具名略過，語意與同一面對
    /// `unlocatableCitekeys` 的處置相同。
    public var unlocatablePersonKeys: Set<String> {
        var out = duplicatedPersonKeys
        for p in self where p.fileSituation.unwritableReason != nil { out.insert(p.key) }
        return out
    }
}
