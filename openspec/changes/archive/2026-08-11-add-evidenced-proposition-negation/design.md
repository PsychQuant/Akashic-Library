## Context

#202 讓每次命題求值綁定可信 `LibrarySnapshot`、content revision、`ValidDay` 與 typed evidence trace，但命題內容仍只是封閉 atomic `Proposition`。`YesNoQuestion.Answer.no` 是標籤，`Stance.denied` 是來源對 atom 的 meta-level 立場；兩者都不能代替可求值的 `¬p`。此外，`authored` 目前沒有 canonical 作者清單完備性證言，正確地把沒有匹配作者視為未定，而非 false。

這兩個缺口必須一起處理。若只加入 `.not`，現行資料仍無法產生可證成的 `.fails`／`.no`；若把 caller-supplied Bool 或未納入 snapshot revision 的 witness 塞進 `PropositionModel`，相同 snapshot ID 會因外掛資料得到不同結果，直接破壞 #202 的重播契約。#204 將加入有限 conjunction／disjunction／implication，因此 #203 必須建立唯一且可延伸的 expression 與遞迴 trace，而不是一次性的否定 wrapper。

## Goals / Non-Goals

**Goals:**

- 以結構 identity 表示 atomic proposition 與任意有限層數的顯式否定。
- 讓三值否定保留 snapshot、valid day、undetermined reason 與完整 operand evidence。
- 讓 no-answer 攜帶可直接進入 assertion／adjudication 的 `¬subject` holds valuation。
- 讓 canonical Entry 可選擇性保存具 content-addressed provenance 的作者清單完備性證言，且 revision 自動涵蓋該證言 bytes。
- 只有在 witness 綁定當下 work UUID、exact author snapshot 且所有作者槽已歸戶時，才由排除目標 person 推得 authored fails。
- 保持 `Stance.denied(p)` 與 `.asserted(.not(.atom(p)))` 的型別與裁決語意分離。

**Non-Goals:**

- 不加入 `and`、`or`、`implies`、語意等價判定或正規形；這些由 #204 承接。
- 不建立通用 closed-world assumption、任意 negative anti-join 或負向查詢 CLI。
- 不把 Zotero `Entry.provenance`、裸 Bool、Git branch／commit 或 caller 自填 revision 當完備性證言。
- 不自動替既有 Entry 補 witness，也不把作者資料缺席、空清單或 unresolved literal 自動解讀為反證。
- 不宣稱已實作《邏輯哲學論》的完整否定理論或真值函數完備性。

## Decisions

### 保留封閉 atom，新增單一有界結構 expression

`Proposition` 繼續只定義具固定 arity／role 的 atomic predicate。新增 `public indirect enum PropositionExpression: Equatable, Hashable`，初版只有 `.atom(Proposition)` 與 `.not(PropositionExpression)`；#204 必須擴充同一 enum，不能另建 formula AST。

expression identity 是結構語法：`¬¬p != p`；double negation 只在求值結果上與 `p` 相同，不在 `Equatable` 中做語意化簡。`Hashable` 將 atom／not node tag 與 payload 依結構送入 `Hasher`，遵守相等值具相同 hash 的契約；不宣稱 Swift 未保證的「不相等值永不碰撞」。`validate()` 逐層檢查 atom 並將 operator nesting 限制為 64；過深 expression 擲具型別錯誤。因 public enum case 仍可直接構造，`evaluate`、`answer` 與 `adjudicate` 都必須重做 boundary validation。`Equatable`／`Hashable` 以迭代方式剝離 unary nodes，避免 caller 對尚未驗證的深鏈做雜湊時遞迴爆棧。

安全建構器提供 `.makeAtom` 與 `.makeNot`。`Proposition.expression` 只是不擲出的結構提升 convenience，不宣稱它已驗證 caller 直接建立的 public `Proposition` case；所有語意邊界仍必須重驗。`YesNoQuestion` 的 throwing initializer 同時驗證 subject 與可能產生的 `.not(subject)`，因此 question subject 最多使用 63 層 operator，保證 no-answer 永遠仍是合法 expression。

替代方案是在 `Proposition` 直接加入 `.not`。這會把 atomic predicate 的 projection switch 與 formula operator 混在一起，也讓 #204 難以區分「投射 atom」與「求值 expression」，因此拒絕。

### 使用遞迴 typed trace 與獨立 established-answer valuation

`Valuation` 改存 `expression: PropositionExpression`。既有 atom evidence 移入 `AtomicEvidenceTrace`；`EvidenceTrace` 是 public 唯讀 value，以 module-internal recursive storage 表示 atom 與 negation node。外部 caller 只能從 production `Valuation` 取得 trace，並透過 `kind`、`operand`、`scope`、`projection`、`evidence`、`snapshotQuarantine`、`conclusion` 等唯讀 view 稽核；不暴露可自由拆配 operand 與 conclusion 的 public raw constructor。module-internal negation constructor 必須由 operand conclusion 機械導出新 conclusion，而且 `Equatable` 以迭代方式比較 node chain，不使用 synthesized recursive equality。

替代方案是 public recursive enum case。對抗測試證實它不但允許 caller 作出「operand 為 holds 卻宣稱 negation conclusion 也為 holds」的假 trace，32,768 層鏈的 synthesized equality 還會穩定 stack overflow，因此拒絕。

module-internal 的 truth negation helper 只交換 holds／fails，對 `.undetermined(reason)` 原值回傳；不公開 context-free `TruthValue.negated`，避免 caller 繞過 expression、context 與 trace。expression evaluator 先求 atom，再由內向外逐層建立 negation trace；同一 context 不重載 store、不重跑另一份 model。

`AnswerResult` 明分 `subjectValuation` 與 optional `EstablishedAnswer`。subject holds 時，yes 的 established valuation 就是同一 subject／holds；subject fails 時，no 的 established valuation 是 `.not(subject)`／holds，trace 以 negation node 包住 subject／fails trace；subject 未定時 established answer 必須是 nil。如此 negative answer 能直接作為 asserted expression 的求值依據，而不會拿 `p/fails` valuation 去裁決 `¬p` 造成 expression mismatch。

替代方案只加 `negativeExpression` 欄位而沿用 subject valuation。這會讓 expression 與 valuation 不一致，無法通過 exact-expression adjudication，因此拒絕。

### 將完備性 witness 保存於 Akashic-owned canonical Entry metadata

`AkashicMeta` 新增 optional `authorListCompleteness: AuthorListCompletenessWitness`，YAML 形狀固定為：

```yaml
akashic:
  author-list-completeness:
    work-id: 11111111-1111-1111-1111-111111111111
    author-list-fingerprint: sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb
    attested-authors:
      - key: author-a
      - key: author-b
    references:
      - field: authors
        url: https://example.test/work
        retrieved: "2026-08-10"
        status: 200
        media-type: text/html
        content: sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
      - field: authors
        judgement: The cited source enumerates the complete author list.
        rests-on:
          - sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
```

這個 optional Akashic namespace 欄位由 StoreIO 既有 canonical YAML capture 納入 revision；不另加 revision side channel。舊資料缺席時完全維持 open-world 行為，Zotero pull 也不會覆寫 Akashic-owned metadata。

替代方案是 `PropositionModel(snapshot:witnesses:)` 或 caller-supplied Bool。它們未被 snapshot digest 涵蓋，能在相同 revision 下改變 truth，因此拒絕。另一方案把證言塞進 Zotero `Entry.provenance`；該 namespace 只描述匯入 metadata，且可由 pull 覆寫，也予以拒絕。

### 要求封閉 provenance chain 與 exact snapshot binding

`AuthorListCompletenessWitness` 以 throwing initializer 驗證：work UUID、作者槽 snapshot、references 非空；每筆 reference 的 `field` 必須恰為 `authors`、`value` 必須缺席；至少一筆 retrieval 必須有合法 `sha256:` content digest；至少一筆非空 judgement 必須有非空 `rests-on`，且每個 digest 都必須對應同一 witness bundle 內的 retrieval content。所有 author key 必須符合 `StoreKey`，literal 不得為空，但 literal 的存在不會讓 witness 變成 identity-level 排除證明。

`AuthorListFingerprint` 由 ordered `attested-authors` 以 `akashic-author-list-v1` domain、UInt64 big-endian slot count、每個 `Author` case tag、raw UTF-8 byte length 與 bytes 計算 SHA-256；key／literal、順序與 NFC／NFD raw bytes 都不可碰撞或被正規化。YAML 必須保存 fingerprint，decode 驗證它等於 attested snapshot 的衍生值。保留 exact list 是為了人工與機械稽核；fingerprint 則提供具版本的 compact binding，兩者不一致一律拒絕。fingerprint 不含 `StoreRevision`，避免 canonical bytes 自我參照。

Entry YAML decode 在取得 entry ID 與 authors 後驗證 `work-id == Entry.id`、fingerprint 與 `attested-authors` 相符，且 `attested-authors == Entry.authors`，不符即 quarantine；同一 Entry 最多一筆 witness，重複 YAML key 在 mapping boundary 拒絕，不能讓一筆 valid witness 遮掉 stale witness。`PropositionModel` 再驗一次，防止 module-internal／測試或 in-memory mutation 繞過 decode。Model validation 使用具型別、順序穩定且顯示有界的 binding issue payload，不採 first-wins。

替代方案只在 statement 文字搜尋「complete」。自由文字不是機械契約，跨語言也不穩定；完整性由 typed container 宣告，judgement statement 只保留人可讀理由。

### authored 只有在完整且全數歸戶的排除證據下才 fails

atomic authored evaluator 的 precedence 固定如下：

1. 任一作者 key 等於 person key → `holds`，trace 保留全部 author slots 與 witness（若有）。
2. 沒有 key match，但存在與 person 名稱相符的 literal → `undetermined(supportingEvidenceUnresolved)`。
3. 沒有 key match，但任一其他 literal 尚未歸戶 → `undetermined(authorIdentityUnresolved)`；不能用字串不相似推定不是同一人。
4. 全部作者槽皆為 resolved key，且沒有有效、snapshot-bound completeness witness → `undetermined(noSupportingEvidence)`。
5. 全部作者槽皆為 resolved key，且有效 witness 的 exact snapshot 排除該 person → `fails`，trace 必須包含 witness 及每個 author slot。

空作者陣列只有在具有效 witness 明示「此 exact 空清單已完備」時才形成排除證據；單純缺席或空陣列不產生 fails。Affiliated 沒有 completeness witness，行為不變，仍不產生 fails。

### denied stance 不得自動轉換成 asserted negation

`Assertion` 與 `AcceptedFact` 改存 expression。`adjudicate` 先驗 assertion／valuation expression 完全相等，再驗 stance，最後只接受 holds。`.denied(.atom(p))` 即使來源意圖是否定，也只記錄來源對 `p` 的立場並被 `stanceIsNotAssertion` 拒絕；只有 `.asserted(.not(.atom(p)))` 搭配相同 negated expression 的 holds valuation才能成為 negative fact。

不提供 denied-to-negation convenience conversion。需要保存來源否認與邏輯負命題時，caller 必須建立兩筆語意不同的紀錄或明示建立 asserted negation。

### 以 optional additive schema 落地且不升 store version

`author-list-completeness` 位於既有 tolerant-preserve 的 `akashic` namespace，缺席合法且不改既有 encode bytes；舊 binary 會把未知子區塊逐字保留。新 binary 的 encoder 以固定 key 順序輸出，decode／encode semantic canary 比較 witness，known shape 內未知鍵、重複鍵、錯誤 tag、錯誤 digest 或 snapshot mismatch 全部 fail closed。

因此不升 `StoreVersion`、不做 bulk migration。新增 round-trip、unknown-field coexistence、quarantine、semantic canary 與 snapshot revision change 測試，證明 schema additive 但 truth-affecting bytes 一定改變 revision。

### 只更新有直接證據的 Tractatus 對照並保留 #204 邊界

4.023、4.05、4.06、4.2、4.25、4.26、4.431、5、5.31、5.44、5.51、5.512、6.5 的 corpus record 修訂過時 claim／locator，加入 #203 的 expression／negation／witness／no-answer／negative fact code 與 test locator；generated Markdown 由 renderer 重新產生。關係維持原本誠實的 `partial`、`aspirational` 或 `intentional_nonconformance` 邊界，理由明載本 change 只完成 unary negation 與 authored completeness vertical slice，truth-functional composition 仍由 #204 承接。

封存順序固定為 #205 → #202 → #203；在前兩個 change 進入主 spec 前，#203 analyze 的 shared-requirement gap 屬治理前置，不得用重複或降格 delta 來掩蓋。

## Implementation Contract

### Observable behavior and API

- `PropositionExpression` 對 `.atom`／`.not` 提供結構 equality／hash、深度上限驗證與 context-bound evaluation；malformed atom 或過深 expression 一律擲 typed error，不轉成 undetermined。
- `Valuation.expression`、`Assertion.expression`、`AcceptedFact.expression` 與 adjudication mismatch payload 使用同一 expression type。
- `EvidenceTrace` 以受控 module-internal constructor 產生 atom／negation node；public caller 只有唯讀 kind／operand／audit views，無法伪造 conclusion。negation 保存完整 operand trace，且其 conclusion 必須等於 operand truth 的三值否定；snapshot ID、valid day、quarantine 與 atomic evidence 不得改寫或截短。
- `YesNoQuestion.answer(in:)` 永遠保留 subject valuation；yes／no 另回一份 expression 與 truth 一致、可裁決且 truth 為 holds 的 established answer valuation；undetermined 不回 established answer。
- `AuthorListCompletenessWitness` 是 Entry Akashic metadata 的 typed optional；其 YAML work ID、versioned author-list fingerprint、attested authors 與 provenance chain 全部參與 canonical snapshot revision。
- authored 只按上述五階 precedence 求值；witness mismatch 在 model 建構前拒絕，不得降格成 `.undetermined`。

### Failure modes

- expression malformed／too deep：typed expression／proposition error；evaluate、answer、adjudicate 同樣 fail closed。
- witness shape／fingerprint／digest／provenance chain 錯誤：Entry decode quarantine 或 throwing witness initializer。
- witness 與 Entry ID／authors 不符：decode quarantine；programmatic model construction 回具型別、順序穩定的 aggregate validation error。
- unresolved literal：valuation 未定並保留 literal evidence；不產生 fails、no established answer 或 accepted fact。
- assertion expression 與 valuation expression 不同：mismatch 優先於 stance／truth；不得接受。

### Acceptance and verification

- AkashicCore／StoreIO tests 先 RED 後 GREEN，涵蓋 author fingerprint golden vector／framing collisions、valid／invalid provenance chain、exact snapshot binding、YAML round-trip、unknown-field coexistence、quarantine、revision change 與診斷消毒／上限。
- AkashicProposition tests 先 RED 後 GREEN，涵蓋 structural hash、double negation、64／65 depth、三值反轉、undetermined reason identity、fails precedence、所有 literal 邊界、no established valuation、denied／asserted-negation 分離、negative fact gate，trace raw-constructor 外部 typecheck 拒絕與 32,768 層 internal chain 的迭代 equality。
- mutation probes至少移除 expression boundary validation、把 undetermined 否定成 fails、從 absence 產生 fails、忽略 witness snapshot、讓 no 沿用 subject valuation、把 denied 自動轉 negation；每項都必須使指定測試 RED，還原後全綠。
- warnings-as-errors 執行受影響 targets 與完整 Swift suite；Spectra strict validate、corpus strict validate、deterministic render check、source asset digest 與 whitespace gates全數通過。

### Scope boundaries

本 change 只新增 unary negation 與 authored completeness vertical slice。不得順手加入 binary formula、通用 completeness registry、CLI、持久化 accepted facts、來源內容抓取或歷史 snapshot 儲存。

## Risks / Trade-offs

- [Risk] 完備性證言落後於作者清單，可能製造假的 negative fact → exact `work-id`＋versioned fingerprint＋`attested-authors` binding 在 decode 與 model boundary 雙重拒絕。
- [Risk] 任一 unresolved literal 被錯當「不是目標 person」→ 所有 literal 都阻擋 fails，並以具名 reason 保留。
- [Risk] no-answer 的內容與 valuation 分叉 → `EstablishedAnswer` 只保存其 own holds valuation，expression 由 valuation 取得，initializer 不公開。
- [Risk] 深層 public expression 與 recursive trace 造成 stack／CPU 放大 → expression 語意邊界上限 64，equality／hash／evaluation 使用迭代路徑；trace 不公開 raw node constructor，production 深度由 expression 上限約束，equality 仍用迭代路徑，診斷固定有界。
- [Risk] 新 schema 被舊 binary 剝除 → 欄位放在 tolerant-preserve Akashic namespace，並加 legacy unknown-field round-trip probe。
- [Risk] #202／#203 各建一套 trace → 直接把 #202 trace 升級為遞迴結構，computed access 維持既有 audit surface。
- [Trade-off] witness 重複保存作者 snapshot → 增加 YAML 體積，但換得可機械偵測 stale completeness claim；不得以只綁 citekey 的較小形狀取代。

## Migration Plan

1. 先新增 optional witness model／codec 與 RED/GREEN round-trip、validation tests；既有 Entry 缺席時 bytes 與 truth 不變。
2. 將 proposition public surface 遷移到 expression／recursive trace，再加入 authored fails 與 negative answer／fact tests。
3. 更新全部 repo callers、規格與 13 筆 corpus record，重新產生並排 Markdown。
4. 以完整測試、mutation、strict validation 與 deterministic render 驗證 frozen snapshot。
5. 若需回復，移除新 witness 欄位即可回到 open-world undetermined；不需 store migration。舊 binary 對欄位採 unknown-preserve，不得用會剝除 Akashic unknown metadata 的版本回寫。

## Open Questions

無。完整性 witness 的 canonical 歸屬、expression identity、depth budget、negative answer valuation 與封存順序均在本 design 固定；#204 只可在同一 expression／trace 上增加有限 binary operators。
