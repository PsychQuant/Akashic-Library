import XCTest
@testable import AkashicCore
@testable import AkashicStoreIO
@testable import AkashicMCPKit

/// `ToolPayloadScenarios` 的另一半：venue 的建檔與更新，以及三個 resolve 工具的每一條腿。
extension ToolPayloadScenarios {
    private static let firstEntry = "cheng2025identifiability"
    private static let venueEdge = "cheng2025identifiability:0"

    // MARK: - venue

    static let venues: [PayloadScenario] = [
        PayloadScenario("akashic_add_venue", "with issn", params: ["key", "names", "type", "note", "issn"]) {
            try $0.service.addVenue(key: "new-journal", names: ["New Journal", "  "], type: "periodical", note: "n", issn: ["1234-5679 (print)"])
        },
        PayloadScenario("akashic_update_venue", "add_names", params: ["key", "add_names", "note", "type"]) {
            try $0.service.updateVenue(key: "psychometrika", addNames: ["Psychometrika Journal", "  "], note: "n", type: "periodical")
        },
        PayloadScenario("akashic_update_venue", "add_issn", params: ["key", "add_issn"]) {
            try $0.service.updateVenue(key: "psychometrika", addNames: nil, note: nil, type: nil,
                                       addISSN: ["0033-3123 (print)", "1860-0980 (electronic)"])
        },
        // #564：三條名字分類腿必附 judgement（證據 rests_on 可省略；authorize 那個情境帶一個，讓 rests_on 也有情境宣告）
        PayloadScenario("akashic_update_venue", "add_variant", params: ["key", "add_variant", "judgement"]) {
            try $0.service.updateVenue(key: "psychometrika", addNames: nil, note: nil, type: nil, addVariant: ["PSYCHOMETRIKA", " "],
                                       judgement: "WoS 大寫形")
        },
        PayloadScenario("akashic_update_venue", "authorize", params: ["key", "authorize", "judgement", "rests_on"]) {
            try $0.service.updateVenue(key: "psychometrika", addNames: nil, note: nil, type: nil, authorize: ["Psychometrika"],
                                       judgement: "期刊官網刊頭", restsOn: [try $0.storeDigest()])
        },
        // #559：撤回（先指定一個、再撤回它；空白項進 unauthorizeDropped）
        PayloadScenario("akashic_update_venue", "unauthorize", params: ["key", "unauthorize", "judgement"]) {
            _ = try $0.service.updateVenue(key: "psychometrika", addNames: nil, note: nil, type: nil, authorize: ["Psychometrika"],
                                           judgement: "期刊官網刊頭")
            return try $0.service.updateVenue(key: "psychometrika", addNames: nil, note: nil, type: nil, unauthorize: ["Psychometrika", " "],
                                              judgement: "官網已改名")
        },
        PayloadScenario("akashic_update_venue", "paginated", params: ["key", "paginated", "judgement", "rests_on"]) {
            try $0.service.updateVenue(key: "psychometrika", addNames: nil, note: nil, type: nil, paginated: true,
                                       judgement: "傳統頁碼刊", restsOn: [try $0.storeDigest()])
        },
        PayloadScenario("akashic_update_venue", "clear_paginated", params: ["key", "clear_paginated", "judgement", "rests_on"]) {
            _ = try $0.service.updateVenue(key: "psychometrika", addNames: nil, note: nil, type: nil, paginated: true,
                                           judgement: "傳統頁碼刊", restsOn: [try $0.storeDigest()])
            return try $0.service.updateVenue(key: "psychometrika", addNames: nil, note: nil, type: nil, clearPaginated: true,
                                              judgement: "撤回", restsOn: [try $0.storeDigest()])
        },
        PayloadScenario("akashic_update_venue", "remove_issn", params: ["key", "remove_issn"]) {
            _ = try $0.service.updateVenue(key: "psychometrika", addNames: nil, note: nil, type: nil, addISSN: ["0033-3123"])
            $0.commit()
            return try $0.service.updateVenue(key: "psychometrika", addNames: nil, note: nil, type: nil, removeISSN: ["0033-3123=掛錯刊"])
        },
        PayloadScenario("akashic_update_venue", "references", params: ["key", "references"]) {
            _ = try $0.service.updateVenue(key: "psychometrika", addNames: nil, note: nil, type: nil, addISSN: ["0033-3123"])
            return try $0.service.updateVenue(key: "psychometrika", addNames: nil, note: nil, type: nil,
                                              references: [try $0.retrievalReference()])
        },
        PayloadScenario("akashic_update_venue", "remove_reference", params: ["key", "remove_reference"]) {
            _ = try $0.service.updateVenue(key: "psychometrika", addNames: nil, note: nil, type: nil, addISSN: ["0033-3123"])
            let reference = try $0.retrievalReference()
            _ = try $0.service.updateVenue(key: "psychometrika", addNames: nil, note: nil, type: nil, references: [reference])
            $0.commit()
            var removal = reference
            removal["reason"] = "這份來源查錯了刊"
            return try $0.service.updateVenue(key: "psychometrika", addNames: nil, note: nil, type: nil, removeReference: [removal])
        },
        // #675（R1 verify 第 5／13 列）：edit_name_segment 的三種回應形狀——有變動（沒有 authorized 的 venue 顯示名跟著換）、
        // 沒有變動（writeNote）、超過 20 項（detailsTruncated／detailsListed）
        PayloadScenario("akashic_update_venue", "edit_name_segment", params: ["key", "edit_name_segment"]) {
            _ = try $0.service.updateVenue(key: "psychometrika", addNames: ["Psychometrika Old"], note: nil, type: nil)
            $0.commit()
            return try $0.service.updateVenue(key: "psychometrika", addNames: nil, note: nil, type: nil, editNameSegment: [
                ["name": "Psychometrika Old", "set": ["start": "1990"], "reason": "1990 年起用這個刊名"]])
        },
        PayloadScenario("akashic_update_venue", "edit_name_segment unchanged", params: ["key", "edit_name_segment"]) {
            try $0.service.updateVenue(key: "psychometrika", addNames: nil, note: nil, type: nil, editNameSegment: [
                ["name": "Psychometrika", "set": ["source": NSNull()], "reason": "本來就沒有 source"]])
        },
        PayloadScenario("akashic_update_venue", "edit_name_segment over 20", params: ["key", "edit_name_segment"]) {
            let extra = (1...20).map { String(format: "Psychometrika Variant %02d", $0) }
            _ = try $0.service.updateVenue(key: "psychometrika", addNames: extra, note: nil, type: nil)
            $0.commit()
            return try $0.service.updateVenue(key: "psychometrika", addNames: nil, note: nil, type: nil,
                                              editNameSegment: (["Psychometrika"] + extra).map { ["name": $0, "set": ["note": "n"], "reason": "r"] })
        },
    ]

    // MARK: - resolve_people

    static let resolvePeople: [PayloadScenario] = [
        PayloadScenario("akashic_resolve_people", "list") { try $0.service.resolvePeople(apply: nil) },
        // #700：people[ref] 的區辨欄位要有情境產生——三個名字（namesTotal）、ORCID／OpenAlex／卒年、現職、
        // 已結束的隸屬與只被觀測到的隸屬（#663 的兩組鍵）
        PayloadScenario("akashic_resolve_people", "list with distinguishing fields") {
            try $0.distinguishableAmbiguity()
            return try $0.service.resolvePeople(apply: nil)
        },
        PayloadScenario("akashic_resolve_people", "apply", params: ["apply"]) {
            try $0.service.resolvePeople(apply: ["desc2020:1:desc-solo"])
        },
        PayloadScenario("akashic_resolve_people", "reject", params: ["reject"]) {
            try $0.service.resolvePeople(apply: nil, reject: ["desc2020:1:desc-solo"])
        },
        PayloadScenario("akashic_resolve_people", "apply+reject", params: ["apply", "reject"]) {
            try $0.service.resolvePeople(apply: ["desc2020:1:desc-solo"], reject: ["desc2021:0:desc-solo"])
        },
        PayloadScenario("akashic_resolve_people", "judge", params: ["judge"]) {
            try $0.service.resolvePeople(apply: nil, judge: ["desc2020:0:desc-amb-1=第一作者的機構與這位相符",
                                                             "no-such2020:0:desc-amb-1=work 不存在"])
        },
        PayloadScenario("akashic_resolve_people", "refute", params: ["refute"]) {
            try $0.service.resolvePeople(apply: nil, refute: ["desc2020:0:desc-amb-2=機構不符"])
        },
        PayloadScenario("akashic_resolve_people", "undecided", params: ["undecided", "rests_on"]) {
            try $0.service.resolvePeople(apply: nil, undecided: ["desc2020:0:desc-amb-1=查了機構仍無法判定"],
                                         restsOn: [try $0.storeDigest()])
        },
        PayloadScenario("akashic_resolve_people", "split_author", params: ["split_author"]) {
            try $0.service.splitAuthors(["split2020:0: and =兩位作者被黏成一格"])
        },
        PayloadScenario("akashic_resolve_people", "un_split", params: ["un_split"]) {
            _ = try $0.service.splitAuthors(["split2020:0: and =兩位作者被黏成一格"])
            $0.commit()
            return try $0.service.unsplitAuthors(["split2020:Alpha One and Beta Two"])
        },
        PayloadScenario("akashic_resolve_people", "drop_author", params: ["drop_author"]) {
            try $0.service.dropAuthors(["drop2020:No authorship indicated=無署名的佔位字串"])
        },
        PayloadScenario("akashic_resolve_people", "attribute_org", params: ["attribute_org"]) {
            try $0.service.attributeToOrganizations(["org2020:0:global-research-institute=團體作者"])
        },
    ]

    // MARK: - resolve_venues

    static let resolveVenues: [PayloadScenario] = [
        PayloadScenario("akashic_resolve_venues", "list") { try $0.service.resolveVenues(apply: nil) },
        PayloadScenario("akashic_resolve_venues", "apply", params: ["apply"]) { try $0.service.resolveVenues(apply: [venueEdge]) },
        PayloadScenario("akashic_resolve_venues", "reject", params: ["reject"]) { try $0.service.resolveVenues(apply: nil, reject: [venueEdge]) },
        PayloadScenario("akashic_resolve_venues", "apply+reject", params: ["apply", "reject"]) {
            try $0.service.resolveVenues(apply: [venueEdge], reject: ["venue2020:0"])
        },
        PayloadScenario("akashic_resolve_venues", "repoint", params: ["repoint"]) {
            _ = try $0.service.resolveVenues(apply: [venueEdge])
            $0.commit()
            return try $0.service.resolveVenues(apply: nil, repoint: ["\(venueEdge):psychometrika-other"])
        },
        PayloadScenario("akashic_resolve_venues", "demote", params: ["demote"]) {
            _ = try $0.service.resolveVenues(apply: [venueEdge])
            $0.commit()
            return try $0.service.resolveVenues(apply: nil, demote: [venueEdge])
        },
        PayloadScenario("akashic_resolve_venues", "undecided", params: ["undecided", "rests_on"]) {
            try $0.service.resolveVenues(apply: nil, undecided: ["\(venueEdge):psychometrika=查了 ISSN 仍無法判定"],
                                         restsOn: [try $0.storeDigest()])
        },
        PayloadScenario("akashic_resolve_venues", "drop_venue", params: ["drop_venue"]) {
            try $0.service.resolveVenues(apply: nil, drop: ["\(venueEdge)=誤植的邊"])
        },
    ]

    // MARK: - resolve_organizations

    static let resolveOrganizations: [PayloadScenario] = [
        PayloadScenario("akashic_resolve_organizations", "list") { try $0.service.resolveOrganizations(apply: nil) },
        PayloadScenario("akashic_resolve_organizations", "apply", params: ["apply"]) {
            try $0.service.resolveOrganizations(apply: [$0.orgCandidateID])
        },
        PayloadScenario("akashic_resolve_organizations", "reject", params: ["reject"]) {
            try $0.service.resolveOrganizations(apply: nil, reject: [$0.orgCandidateID])
        },
        PayloadScenario("akashic_resolve_organizations", "undecided", params: ["undecided", "rests_on"]) {
            try $0.service.resolveOrganizations(apply: nil, undecided: ["\($0.orgCandidateID)@institute-of-statistical-science=查了機構名仍無法判定"],
                                                restsOn: [try $0.storeDigest()])
        },
        PayloadScenario("akashic_resolve_organizations", "judge", params: ["judge"]) {
            try $0.service.resolveOrganizations(apply: nil, judge: ["\($0.orgCandidateID)@institute-of-statistical-science=同一機構的舊名"])
        },
    ]
}

extension PayloadWorld {
    /// 同名的兩個人（歧義條目），各帶一組區辨欄位：`stand-x` 有三個名字、已結束與只被觀測到的隸屬；`stand-y` 有 ORCID、
    /// OpenAlex、卒年與現職。
    func distinguishableAmbiguity() throws {
        var x = Person(key: "stand-x", names: PersonNames(variant: ["Stand Same", "S. Same", "Stand Q. Same"]))
        x.profile.affiliations = TimelineOf([
            TemporalValue(value: OrgRef.literal("Old Institute"), range: DateRange(start: "2010", end: "2018")),
            TemporalValue(value: OrgRef.literal("Seen Institute"), range: DateRange(attested: ["2021"])),
        ])
        try store.writePerson(x)
        var y = Person(key: "stand-y", names: PersonNames(variant: ["Stand Same"]))
        y.orcid = try XCTUnwrap(ORCID("0000-0003-4038-9439"))
        y.openalex = "A5023888391"
        y.died = "2024"
        y.profile.affiliations = TimelineOf([TemporalValue(value: OrgRef.literal("Now Institute"), range: DateRange(start: "2019"))])
        try store.writePerson(y)
        try store.writeEntry(Entry(id: UUID(), citekey: "stand2020", type: .periodicalArticle, title: "Stand",
                                   authors: [.literal("Stand Same")], date: "2020"))
    }

    /// world 的機構隸屬候選：`<holderKey>::<literal>`。
    var orgCandidateID: String { "iss-member::Institute of Statistical Science" }

    /// 一筆合法的 venue references 項（retrieval：ISSN 的來源）。
    func retrievalReference() throws -> [String: Any] {
        ["field": "issn", "value": "0033-3123", "kind": "retrieval", "url": "https://portal.issn.org/resource/ISSN/0033-3123",
         "retrieved": "2026-09-29", "status": 200, "media_type": "text/html", "content": try storeDigest()]
    }
}
