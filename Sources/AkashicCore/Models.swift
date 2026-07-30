import Foundation

/// 文獻條目——store 的基本單位（entries/<citekey>.yaml 的記憶體形）。
public struct Entry: Equatable {
    /// 不可變機器身分；citekey 改名不斷鏈。
    public var id: UUID
    /// 人類可讀、可改名的引用鍵。
    public var citekey: String
    /// biblatex entry type（article / book / incollection / …）。
    public var type: String
    public var title: String
    public var authors: [Author]
    public var date: String?
    /// 其餘 biblatex 欄位（journaltitle / volume / doi / …）。
    public var fields: [String: String]
    public var attachments: [AttachmentRef]
    /// Zotero namespace——pull 管理、pull 可覆寫。
    public var provenance: Provenance?
    /// Akashic 自有 namespace——pull 絕不觸碰。
    public var akashic: AkashicMeta
    /// 頂層未知欄位（tolerant-preserve，#23）。
    public var unknownFields: [UnknownField]

    public init(id: UUID, citekey: String, type: String, title: String,
                authors: [Author] = [], date: String? = nil,
                fields: [String: String] = [:], attachments: [AttachmentRef] = [],
                provenance: Provenance? = nil, akashic: AkashicMeta = AkashicMeta(),
                unknownFields: [UnknownField] = []) {
        self.id = id
        self.citekey = citekey
        self.type = type
        self.title = title
        self.authors = authors
        self.date = date
        self.fields = fields
        self.attachments = attachments
        self.provenance = provenance
        self.akashic = akashic
        self.unknownFields = unknownFields
    }
}

/// 作者二態：已解析（引用 people/ 的 person key）或未解析裸字串。
public enum Author: Equatable {
    case key(String)
    case literal(String)

    public var displayName: String {
        switch self {
        case .key(let k): return k
        case .literal(let s): return s
        }
    }
}

/// 未知欄位（store-format §5 v1.3 tolerant-preserve，#23）：較新版本寫入、
/// 本版不認識的欄位。decode 時整棵保留（value 為 YAML 序列化文字），encode 時
/// 原樣寫回——舊 binary 的 read-modify-write 不得剝掉新欄位（資料毀損防線）。
public struct UnknownField: Equatable {
    public var key: String
    /// 該欄位 value 節點的 YAML 序列化文字（round-trip 保真載體）。
    public var yaml: String

    public init(key: String, yaml: String) {
        self.key = key
        self.yaml = yaml
    }
}

public struct AttachmentRef: Equatable {
    public enum Kind: String, Equatable {
        /// 相對 Zotero 資料目錄的 reference（storage/<KEY>/<file>）。
        case zotero
        /// 相對 attachment pool 的路徑。
        case pool
    }

    public var kind: Kind
    public var path: String

    public init(kind: Kind, path: String) {
        self.kind = kind
        self.path = path
    }
}

public struct Provenance: Equatable {
    public var zoteroKey: String
    public var zoteroVersion: Int
    /// Zotero libraryID（personal=1；缺欄位＝pre-Phase-2 舊檔，合法）。
    public var libraryID: Int?
    /// mapping 產出的 biblatex 面向 SHA-256——update 條件之一
    /// （version 較新 OR hash 不同），同時涵蓋本機未同步修改與 mapping 演進。
    public var zoteroHash: String?
    public var importedAt: Date?
    /// Zotero 端已刪除的標記時間；不自動刪 entry，人工裁決。
    public var orphanedAt: Date?

    public init(zoteroKey: String, zoteroVersion: Int,
                libraryID: Int? = nil, zoteroHash: String? = nil,
                importedAt: Date? = nil, orphanedAt: Date? = nil) {
        self.zoteroKey = zoteroKey
        self.zoteroVersion = zoteroVersion
        self.libraryID = libraryID
        self.zoteroHash = zoteroHash
        self.importedAt = importedAt
        self.orphanedAt = orphanedAt
    }
}

public struct AkashicMeta: Equatable {
    public var tags: [String]
    /// 所屬 library keys（#13 membership views）——store 是全集，library 只是成員集合；
    /// 空陣列＝只屬全集 view。元素須符合 StoreKey 格式（write 時驗證）。
    public var libraries: [String]
    public var status: String?
    public var relations: Relations
    /// akashic namespace 內的未知欄位（tolerant-preserve，#23）——
    /// 歷史上 schema 演化就發生在這層（#13 的 `libraries` 即是）。
    public var unknownFields: [UnknownField]

    public init(tags: [String] = [], libraries: [String] = [],
                status: String? = nil, relations: Relations = Relations(),
                unknownFields: [UnknownField] = []) {
        self.tags = tags
        self.libraries = libraries
        self.status = status
        self.relations = relations
        self.unknownFields = unknownFields
    }

    /// unknownFields 必須參與 isEmpty——否則「只有未知欄位的 akashic 段」
    /// 會被 encode 整段略掉，靜默丟資料（#23）。
    public var isEmpty: Bool {
        tags.isEmpty && libraries.isEmpty && status == nil && relations.isEmpty
            && unknownFields.isEmpty
    }
}

/// Library registry（#13）：具名成員集合視角的 metadata。
/// 成員關係存在各 entry 的 `akashic.libraries`，不在此檔（per-entry membership）。
public struct Library: Equatable {
    public var key: String
    public var name: String
    public var description: String?
    /// 頂層未知欄位（tolerant-preserve，#23）。
    public var unknownFields: [UnknownField]

    public init(key: String, name: String, description: String? = nil,
                unknownFields: [UnknownField] = []) {
        self.key = key
        self.name = name
        self.description = description
        self.unknownFields = unknownFields
    }
}

/// 需要「存」的關係；同作者/同期刊由 metadata 推導、不存。
public struct Relations: Equatable {
    public var cites: [String]
    public var related: [String]

    public init(cites: [String] = [], related: [String] = []) {
        self.cites = cites
        self.related = related
    }

    public var isEmpty: Bool { cites.isEmpty && related.isEmpty }
}

/// 人物實體（people/<person-key>.yaml）。
public struct Person: Equatable {
    public var key: String
    public var names: [String]
    public var orcid: String?
    public var openalex: String?
    public var note: String?
    /// 頂層未知欄位（tolerant-preserve，#23）——如 #20 之後的 affiliations / facts。
    public var unknownFields: [UnknownField]

    public init(key: String, names: [String] = [], orcid: String? = nil,
                openalex: String? = nil, note: String? = nil,
                unknownFields: [UnknownField] = []) {
        self.key = key
        self.names = names
        self.orcid = orcid
        self.openalex = openalex
        self.note = note
        self.unknownFields = unknownFields
    }
}

public struct ValidationIssue: Equatable {
    public enum Severity: Equatable { case error, warning }

    public var severity: Severity
    public var message: String

    public init(severity: Severity, message: String) {
        self.severity = severity
        self.message = message
    }
}

/// 檔名安全的 key 格式（citekey 與 person key 共用）。
/// write-time 強制——不合格式的 key 絕不進 appendingPathComponent（path traversal 防護）。
public enum StoreKey {
    /// \A/\z 錨點：ICU 的 `$` 會在尾端換行前匹配，`\z` 才是嚴格字串結尾
    public static let pattern = "\\A[a-z0-9][a-z0-9-]*\\z"

    public static func isValid(_ key: String) -> Bool {
        key.range(of: pattern, options: .regularExpression) != nil
    }
}

extension Entry {
    private static let citekeyPattern = StoreKey.pattern

    public func validate() -> [ValidationIssue] {
        var issues: [ValidationIssue] = []
        if citekey.range(of: Self.citekeyPattern, options: .regularExpression) == nil {
            issues.append(ValidationIssue(
                severity: .error,
                message: "citekey '\(citekey)' 不符合 ^[a-z0-9][a-z0-9-]*$"))
        }
        if type.trimmingCharacters(in: .whitespaces).isEmpty {
            issues.append(ValidationIssue(severity: .error, message: "type 不可為空"))
        }
        if title.trimmingCharacters(in: .whitespaces).isEmpty {
            issues.append(ValidationIssue(severity: .warning, message: "title 為空"))
        }
        if Set(akashic.libraries).count != akashic.libraries.count {
            issues.append(ValidationIssue(severity: .warning,
                                          message: "akashic.libraries 含重複 key（load 已去重）"))
        }
        for f in unknownFields {
            issues.append(ValidationIssue(severity: .warning,
                message: "未知欄位「\(f.key)」——可能由較新版本寫入（已保留；升級 binary 或檢查 typo）"))
        }
        for f in akashic.unknownFields {
            issues.append(ValidationIssue(severity: .warning,
                message: "akashic 未知欄位「\(f.key)」——可能由較新版本寫入（已保留；升級 binary 或檢查 typo）"))
        }
        return issues
    }
}

extension Person {
    public func validate() -> [ValidationIssue] {
        var issues: [ValidationIssue] = []
        if !StoreKey.isValid(key) {
            issues.append(ValidationIssue(
                severity: .error,
                message: "person key '\(key)' 不符合 \(StoreKey.pattern)"))
        }
        for f in unknownFields {
            issues.append(ValidationIssue(severity: .warning,
                message: "未知欄位「\(f.key)」——可能由較新版本寫入（已保留；升級 binary 或檢查 typo）"))
        }
        return issues
    }
}
