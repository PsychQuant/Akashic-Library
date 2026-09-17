/// **當下已裁決的全部欄位**（六個型別檔的 `public var` ＋ `public let`）。
///
/// 由 `plugin/tests/backlink-field-ratchet.py` 的 `ADJUDICATED` **機械抽取**
/// （`ast.literal_eval`），不是手抄——兩版的清單因此**同源**，而不是我小心的結果。
let adjudicated: Set<String> = [
    "Divergence.candidates", "Divergence.id", "Divergence.judgement",
    "Divergence.key", "Divergence.prefers", "Divergence.question",
    "Divergence.restsOn", "Divergence.shape", "Divergence.statement",
    "Divergence.unknownFields", "Models.akashic", "Models.all",
    "Models.attachments", "Models.authorListCompleteness", "Models.authorized",
    "Models.authors", "Models.citekey", "Models.cites",
    "Models.date", "Models.dateIsConfirmedAbsent", "Models.description",
    "Models.died", "Models.displayName", "Models.doi",
    "Models.fields", "Models.id", "Models.importedAt",
    "Models.isEmpty", "Models.isbn", "Models.key",
    "Models.kind", "Models.libraries", "Models.libraryID",
    "Models.message", "Models.name", "Models.names",
    "Models.note", "Models.openalex", "Models.orcid",
    "Models.orphanedAt", "Models.path", "Models.pmid",
    "Models.profile", "Models.provenance", "Models.raw",
    "Models.references", "Models.related", "Models.relations",
    "Models.severity", "Models.sources", "Models.status",
    "Models.tags", "Models.thesis", "Models.title",
    "Models.type", "Models.unknownFields", "Models.variant",
    "Models.venues", "Models.zoteroHash", "Models.zoteroKey",
    "Models.zoteroVersion", "Organization.authorized", "Organization.displayName",
    "Organization.dissolved", "Organization.founded", "Organization.id",
    "Organization.key", "Organization.names", "Organization.note",
    "Organization.parents", "Organization.references", "Organization.ror",
    "Organization.unknownFields",
    // Provenance.byteExactKey（#554 R24 D65）：computed、不序列化、由已裁決的 field／value／kind 現算——不是關係邊，
    // 是「兩筆完全相同」的位元組鍵（entity-backlink-completeness 第 ③ 步兩問皆否）
    "Provenance.byteExactKey", "Provenance.encoded", "Provenance.field",
    "Provenance.holder", "Provenance.holderKind", "Provenance.kind",
    "Provenance.literal", "Provenance.value", "Temporal.administrative",
    "Temporal.affiliations", "Temporal.appointments", "Temporal.attested",
    "Temporal.contacts", "Temporal.current", "Temporal.end",
    "Temporal.endedUnknown", "Temporal.entries", "Temporal.fields",
    "Temporal.inSerializationOrder", "Temporal.isEmpty", "Temporal.isOpen",
    "Temporal.latestPastSegment", "Temporal.makesTemporalClaim", "Temporal.note", "Temporal.range",
    "Temporal.ranks", "Temporal.sorted", "Temporal.source",
    "Temporal.start", "Temporal.usesAttested", "Temporal.usesEndedUnknown",
    "Temporal.value", "Venue.authorized", "Venue.displayName",
    "Venue.id", "Venue.issn", "Venue.key",
    "Venue.names", "Venue.note", "Venue.paginated", "Venue.references",
    "Venue.type", "Venue.unknownFields", "Venue.variant",
]

/// 葉欄位 → 它的宣告型別。**名字不變而語意改變，所有棘輪都看不到**（#407 R59）。
let edgeTypes: [String: String] = [
    "Divergence.candidates": "[DivergenceCandidate]",
    "Divergence.prefers": "String?",
    "Divergence.restsOn": "[String]",
    "Models.attachments": "[AttachmentRef]",
    "Models.authors": "[Author]",
    "Models.cites": "[String]",
    "Models.libraries": "[String]",
    "Models.references": "[ProvenanceReference]",
    "Models.related": "[String]",
    "Models.tags": "[String]",
    "Models.venues": "[VenueRef]",
    "Organization.parents": "TimelineOf<OrgRef>",
    "Organization.references": "[ProvenanceReference]",
    "Temporal.affiliations": "TimelineOf<OrgRef>",
    "Venue.references": "[ProvenanceReference]",
]

/// 六個型別檔。**封閉列舉**——新增一個型別檔要顯式加進來。
let ratchetFiles = ["Models", "Organization", "Divergence", "Temporal", "Provenance", "Venue"]
