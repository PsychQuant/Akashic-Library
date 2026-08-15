import Foundation
import CryptoKit

/// 從既有字串身分推出**確定性** UUID（#35）。
///
/// ## 為什麼必須確定性
///
/// `entities/<uuid>.yaml` 需要每筆記錄都有 UUID，但 legacy 的 `people/<key>.yaml`
/// 沒有 `id` 欄位。若讀取時隨機生一個，**同一個檔每次載入都會得到不同的 id**——
/// index 的 primary key、entry 的作者引用、graph 的節點全部會漂。
///
/// 所以用 **UUIDv5**（RFC 4122 §4.3：namespace UUID + name 的 SHA-1）。同一個
/// person key 永遠推出同一個 UUID，且不同 key 幾乎不可能碰撞。
///
/// ## 為什麼不用 hash 的前 16 bytes 就好
///
/// 會產生一個**不是合法 UUID** 的 128-bit 值（version / variant 位元沒設）。那種值
/// 在別的工具眼裡是壞掉的 UUID，而 store 的檔名要能被任何人用一般工具檢查。
public enum DeterministicUUID {

    /// Akashic person 的 namespace（**歷史常數**，#241 起無生產推導）。
    ///
    /// v5(personNamespace, key) 曾是 legacy 補值與 `Person.init` 的預設——#241 裁決
    /// 「識別子只能有一個產生事件」後，person id 一律建立時發 v4，推導函式
    /// `forPerson` 已退場（no-compat-fallback 第 3 條：退場後刪掉，不留著當保險）。
    /// 常數保留給測試 fabricate 舊形狀 fixture 與歷史對照；**不得**再出現任何以它
    /// 推導 person id 的生產呼叫端。
    public static let personNamespace = UUID(uuidString: "6b2f1d3e-9c47-4a58-8b21-0f5e7c9a4d16")!

    /// UUIDv5（SHA-1 based，RFC 4122 §4.3）。
    public static func v5(namespace: UUID, name: String) -> UUID {
        var bytes = [UInt8]()
        withUnsafeBytes(of: namespace.uuid) { bytes.append(contentsOf: $0) }
        bytes.append(contentsOf: Array(name.utf8))

        var digest = Array(Insecure.SHA1.hash(data: Data(bytes)))
        // version 5：高 nibble of byte 6 設為 0101
        digest[6] = (digest[6] & 0x0F) | 0x50
        // variant RFC 4122：高兩 bit of byte 8 設為 10
        digest[8] = (digest[8] & 0x3F) | 0x80

        let u = (digest[0], digest[1], digest[2], digest[3], digest[4], digest[5],
                 digest[6], digest[7], digest[8], digest[9], digest[10], digest[11],
                 digest[12], digest[13], digest[14], digest[15])
        return UUID(uuid: u)
    }

    /// Organization 的 namespace。與 person 分開——同一個 key 字串在兩個形狀下
    /// 必須推出**不同**的 UUID，否則一個叫 `iss` 的人與一個叫 `iss` 的機構會撞成同一筆。
    public static let organizationNamespace =
        UUID(uuidString: "3f9c8a71-2e64-4d0b-9a17-5c2e8b6f0d43")!

    public static func forOrganization(key: String) -> UUID {
        v5(namespace: organizationNamespace, name: key)
    }

    /// 歧異記錄的 namespace。與 person / organization 分開——歧異記錄不是實體，
    /// 它是「哪些實體可能是同一個」這個**未決問題**本身。
    public static let divergenceNamespace = UUID(
        uuidString: "3f4c9a71-2d68-4e15-9b03-7a6c1e5d8b24")!

    /// 歧異記錄的 id：由**候選鍵的集合**推出。
    ///
    /// 用集合而非問句：同一組候選就是**同一個未決問題**，換個問法不該累積成第二筆
    /// 記錄。排序後再雜湊，因為「這些是不是同一個」不因候選的排列而改變——`Divergence`
    /// 的相等性同樣不看候選順序。
    public static func forDivergence(candidateKeys: [String]) -> UUID {
        v5(namespace: divergenceNamespace, name: candidateKeys.sorted().joined(separator: "\n"))
    }
}
