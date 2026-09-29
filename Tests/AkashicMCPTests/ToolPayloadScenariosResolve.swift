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
        PayloadScenario("akashic_add_venue", "with issn") {
            try $0.service.addVenue(key: "new-journal", names: ["New Journal", "  "], type: "periodical", note: "n", issn: ["1234-5679 (print)"])
        },
        PayloadScenario("akashic_update_venue", "add_names") {
            try $0.service.updateVenue(key: "psychometrika", addNames: ["Psychometrika Journal", "  "], note: "n", type: nil)
        },
        PayloadScenario("akashic_update_venue", "add_issn") {
            try $0.service.updateVenue(key: "psychometrika", addNames: nil, note: nil, type: nil,
                                       addISSN: ["0033-3123 (print)", "1860-0980 (electronic)"])
        },
        PayloadScenario("akashic_update_venue", "add_variant") {
            try $0.service.updateVenue(key: "psychometrika", addNames: nil, note: nil, type: nil, addVariant: ["PSYCHOMETRIKA", " "])
        },
        PayloadScenario("akashic_update_venue", "authorize") {
            try $0.service.updateVenue(key: "psychometrika", addNames: nil, note: nil, type: nil, authorize: ["Psychometrika"])
        },
        PayloadScenario("akashic_update_venue", "paginated") {
            try $0.service.updateVenue(key: "psychometrika", addNames: nil, note: nil, type: nil, paginated: true,
                                       judgement: "傳統頁碼刊", restsOn: [try $0.storeDigest()])
        },
        PayloadScenario("akashic_update_venue", "clear_paginated") {
            _ = try $0.service.updateVenue(key: "psychometrika", addNames: nil, note: nil, type: nil, paginated: true,
                                           judgement: "傳統頁碼刊", restsOn: [try $0.storeDigest()])
            return try $0.service.updateVenue(key: "psychometrika", addNames: nil, note: nil, type: nil, clearPaginated: true,
                                              judgement: "撤回", restsOn: [try $0.storeDigest()])
        },
        PayloadScenario("akashic_update_venue", "remove_issn") {
            _ = try $0.service.updateVenue(key: "psychometrika", addNames: nil, note: nil, type: nil, addISSN: ["0033-3123"])
            $0.commit()
            return try $0.service.updateVenue(key: "psychometrika", addNames: nil, note: nil, type: nil, removeISSN: ["0033-3123=掛錯刊"])
        },
        PayloadScenario("akashic_update_venue", "references") {
            _ = try $0.service.updateVenue(key: "psychometrika", addNames: nil, note: nil, type: nil, addISSN: ["0033-3123"])
            return try $0.service.updateVenue(key: "psychometrika", addNames: nil, note: nil, type: nil,
                                              references: [try $0.retrievalReference()])
        },
        PayloadScenario("akashic_update_venue", "remove_reference") {
            _ = try $0.service.updateVenue(key: "psychometrika", addNames: nil, note: nil, type: nil, addISSN: ["0033-3123"])
            let reference = try $0.retrievalReference()
            _ = try $0.service.updateVenue(key: "psychometrika", addNames: nil, note: nil, type: nil, references: [reference])
            $0.commit()
            var removal = reference
            removal["reason"] = "這份來源查錯了刊"
            return try $0.service.updateVenue(key: "psychometrika", addNames: nil, note: nil, type: nil, removeReference: [removal])
        },
    ]

    // MARK: - resolve_people

    static let resolvePeople: [PayloadScenario] = [
        PayloadScenario("akashic_resolve_people", "list") { try $0.service.resolvePeople(apply: nil) },
        PayloadScenario("akashic_resolve_people", "apply") {
            try $0.service.resolvePeople(apply: ["desc2020:1:desc-solo"])
        },
        PayloadScenario("akashic_resolve_people", "reject") {
            try $0.service.resolvePeople(apply: nil, reject: ["desc2020:1:desc-solo"])
        },
        PayloadScenario("akashic_resolve_people", "apply+reject") {
            try $0.service.resolvePeople(apply: ["desc2020:1:desc-solo"], reject: ["desc2021:0:desc-solo"])
        },
        PayloadScenario("akashic_resolve_people", "judge") {
            try $0.service.resolvePeople(apply: nil, judge: ["desc2020:0:desc-amb-1=第一作者的機構與這位相符",
                                                             "no-such2020:0:desc-amb-1=work 不存在"])
        },
        PayloadScenario("akashic_resolve_people", "refute") {
            try $0.service.resolvePeople(apply: nil, refute: ["desc2020:0:desc-amb-2=機構不符"])
        },
        PayloadScenario("akashic_resolve_people", "undecided") {
            try $0.service.resolvePeople(apply: nil, undecided: ["desc2020:0:desc-amb-1=查了機構仍無法判定"],
                                         restsOn: [try $0.storeDigest()])
        },
        PayloadScenario("akashic_resolve_people", "split_author") {
            try $0.service.splitAuthors(["split2020:0: and =兩位作者被黏成一格"])
        },
        PayloadScenario("akashic_resolve_people", "un_split") {
            _ = try $0.service.splitAuthors(["split2020:0: and =兩位作者被黏成一格"])
            $0.commit()
            return try $0.service.unsplitAuthors(["split2020:Alpha One and Beta Two"])
        },
        PayloadScenario("akashic_resolve_people", "drop_author") {
            try $0.service.dropAuthors(["drop2020:No authorship indicated=無署名的佔位字串"])
        },
        PayloadScenario("akashic_resolve_people", "attribute_org") {
            try $0.service.attributeToOrganizations(["org2020:0:global-research-institute=團體作者"])
        },
    ]

    // MARK: - resolve_venues

    static let resolveVenues: [PayloadScenario] = [
        PayloadScenario("akashic_resolve_venues", "list") { try $0.service.resolveVenues(apply: nil) },
        PayloadScenario("akashic_resolve_venues", "apply") { try $0.service.resolveVenues(apply: [venueEdge]) },
        PayloadScenario("akashic_resolve_venues", "reject") { try $0.service.resolveVenues(apply: nil, reject: [venueEdge]) },
        PayloadScenario("akashic_resolve_venues", "apply+reject") {
            try $0.service.resolveVenues(apply: [venueEdge], reject: ["venue2020:0"])
        },
        PayloadScenario("akashic_resolve_venues", "repoint") {
            _ = try $0.service.resolveVenues(apply: [venueEdge])
            $0.commit()
            return try $0.service.resolveVenues(apply: nil, repoint: ["\(venueEdge):psychometrika-other"])
        },
        PayloadScenario("akashic_resolve_venues", "demote") {
            _ = try $0.service.resolveVenues(apply: [venueEdge])
            $0.commit()
            return try $0.service.resolveVenues(apply: nil, demote: [venueEdge])
        },
        PayloadScenario("akashic_resolve_venues", "undecided") {
            try $0.service.resolveVenues(apply: nil, undecided: ["\(venueEdge):psychometrika=查了 ISSN 仍無法判定"],
                                         restsOn: [try $0.storeDigest()])
        },
        PayloadScenario("akashic_resolve_venues", "drop_venue") {
            try $0.service.resolveVenues(apply: nil, drop: ["\(venueEdge)=誤植的邊"])
        },
    ]

    // MARK: - resolve_organizations

    static let resolveOrganizations: [PayloadScenario] = [
        PayloadScenario("akashic_resolve_organizations", "list") { try $0.service.resolveOrganizations(apply: nil) },
        PayloadScenario("akashic_resolve_organizations", "apply") {
            try $0.service.resolveOrganizations(apply: [$0.orgCandidateID])
        },
        PayloadScenario("akashic_resolve_organizations", "reject") {
            try $0.service.resolveOrganizations(apply: nil, reject: [$0.orgCandidateID])
        },
        PayloadScenario("akashic_resolve_organizations", "undecided") {
            try $0.service.resolveOrganizations(apply: nil, undecided: ["\($0.orgCandidateID)@institute-of-statistical-science=查了機構名仍無法判定"],
                                                restsOn: [try $0.storeDigest()])
        },
        PayloadScenario("akashic_resolve_organizations", "judge") {
            try $0.service.resolveOrganizations(apply: nil, judge: ["\($0.orgCandidateID)@institute-of-statistical-science=同一機構的舊名"])
        },
    ]
}

extension PayloadWorld {
    /// world 的機構隸屬候選：`<holderKey>::<literal>`。
    var orgCandidateID: String { "iss-member::Institute of Statistical Science" }

    /// 一筆合法的 venue references 項（retrieval：ISSN 的來源）。
    func retrievalReference() throws -> [String: Any] {
        ["field": "issn", "value": "0033-3123", "kind": "retrieval", "url": "https://portal.issn.org/resource/ISSN/0033-3123",
         "retrieved": "2026-09-29", "status": 200, "media_type": "text/html", "content": try storeDigest()]
    }
}
