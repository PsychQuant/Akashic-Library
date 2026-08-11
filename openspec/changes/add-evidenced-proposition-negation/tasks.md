## 1. Canonical witness TDD 失敗基線

- [x] 1.1 [P] 依 `Canonical entries SHALL carry a typed author-list completeness witness` 與「將完備性 witness 保存於 Akashic-owned canonical Entry metadata」建立 `AuthorshipCompletenessTests` RED matrix，固定 v1 fingerprint golden vector、slot boundary／case tag／順序／NFC-NFD 分離、read-only throwing construction 與 64-hex digest 形狀；以 `swift test --scratch-path /tmp/akashic-203-witness -Xswiftc -warnings-as-errors --filter AuthorshipCompletenessTests` 在型別尚不存在時編譯失敗驗證。
- [x] 1.2 依 `Completeness provenance SHALL form a closed local evidence chain`、`Witnesses SHALL bind exactly to the current work and author snapshot`、`Witness serialization SHALL be additive, deterministic, and revision-bearing` 與「要求封閉 provenance chain 與 exact snapshot binding」建立 RED tests，涵蓋 forged public reference、外部 digest、錯 work UUID、author 增刪／重排／raw bytes、duplicate key、citekey rename、YAML fixed-point、unknown-field coexistence、quarantine 與 witness-only revision change；以精確 Core／StoreIO filters 的 compile 或 assertion failure 驗證。

## 2. Canonical witness 與 snapshot 實作

- [x] 2.1 實作 `AuthorListFingerprint`、`AuthorListCompletenessWitness` 與 typed bounded errors，使 domain／UInt64 big-endian count／case tag／UTF-8 length framing、provenance revalidation 及 `String(describing:)`／`String(reflecting:)` 消毒契約成立；以 1.1 fingerprint、forgery、post-escape bound tests 全綠驗證。
- [x] 2.2 依「以 optional additive schema 落地且不升 store version」把 witness 接入 `AkashicMeta` 與 Entry canonical YAML，固定 key order、strict nested shape、semantic canary、absence zero-diff 及舊 binary unknown-preserve 邊界；以 1.2 round-trip、duplicate、unknown coexistence、malformed quarantine tests 全綠，並確認 `StoreVersion` 不變。
- [x] 2.3 在 Entry decode 與 `PropositionModel` 建構雙重驗證 work ID／fingerprint／exact ordered authors，讓 stale programmatic record 產生 deterministic aggregate binding error且 witness bytes 進同一次 accepted capture revision；以 citekey rename、copy-to-work、author mutation、input reorder、A→B snapshot revision tests 全綠驗證。

## 3. Expression／trace／answer TDD 失敗基線

- [x] 3.1 [P] 依 `Proposition expressions SHALL represent bounded structural negation` 與「保留封閉 atom，新增單一有界結構 expression」建立 `NegationTests` RED matrix，固定 p／¬p／¬¬p structural equality 與 hashed-collection identity（不斷言 raw `hashValue` 零碰撞）、double-negation semantics、nested malformed atom、64／65 depth、迭代 equality/hash 與 question reserve-one budget；以 warnings-as-errors Proposition filter 在 expression API 尚不存在時編譯失敗驗證。
- [x] 3.2 依 `Negation evaluation SHALL derive a recursive evidence trace`、`Valuation outcomes SHALL retain context and structured evidence` 與「使用遞迴 typed trace 與獨立 established-answer valuation」建立 holds↔fails、全部 undetermined reason identity、雙 not 節點、atom-only-once、context／quarantine／evidence exact preservation、外部 raw trace constructor 不可用與 32,768 層 equality 不爆棧 RED tests；以 public recursive enum case、synthesized equality、flat trace 或只改 truth 無法滿足 assertions 驗證。
- [x] 3.3 依 `Evaluation SHALL preserve open-world uncertainty` 與「authored 只有在完整且全數歸戶的排除證據下才 fails」建立真實 canonical producer RED tests，固定 positive-match precedence、valid exact resolved exclusion→fails、無 witness→undetermined、matching／nonmatching literal 均阻擋 fails、witnessed／unwitnessed empty list、stale model rejection及 affiliated 永不 fails；以移除既有偽造 `.fails` producer 後的精確 truth／trace assertions 驗證。
- [x] 3.4 依 `Yes-no questions SHALL expose a tri-valued answer space`、`Fact acceptance SHALL be gated from recorded assertions`、`Denied stance SHALL remain distinct from asserted negation` 與「denied stance 不得自動轉換成 asserted negation」建立 subject／established valuation、no→¬subject/holds、negative subject no→¬¬p、undetermined無 established answer、negative fact、expression mismatch precedence與 denied refusal RED tests。

## 4. Expression、求值與裁決實作

- [x] 4.1 實作唯一 `PropositionExpression.atom／not`、safe factories、max-depth validation 及 custom iterative equality/hash，並讓 evaluate／answer／adjudicate 重驗所有 nested atoms；以 3.1 及 malformed key／literal 四 API propagation tests 全綠驗證，且不新增 #204 binary operators。
- [x] 4.2 將 `Valuation` 改為完整 expression identity，把 flat trace 升級為具 module-internal recursive storage 的 public 唯讀 `EvidenceTrace`，以受控 atom／negation constructor、迭代 equality 與 computed kind／operand／audit access 阻止假 conclusion 與深鏈爆棧，並由內向外包裝而不重載 store；以 3.2 external typecheck refusal、conclusion==truth、operand trace exact identity、double-not layer count、32,768 層 equality 與 mutation tests 全綠驗證。
- [x] 4.3 讓 authored evaluator按 positive key、matching literal、其他 literal、unwitnessed resolved exclusion、witnessed resolved exclusion的固定 precedence產生 holds／具名 undetermined／fails，並把 witness與全部 author slots寫入 atomic trace；以 3.3 及 #202 valid-day/context、#205 canonical-input regression tests 全綠驗證。
- [x] 4.4 遷移 `YesNoQuestion`、`AnswerResult`／`EstablishedAnswer`、`Assertion`、`AcceptedFact` 與 refusal payload 到 expression，使 no 持有自己的 ¬subject/holds valuation、undetermined 不產生可主張內容、exact-expression mismatch 早於 stance/truth；以 3.4 與 repo-wide caller scan 全綠驗證。

## 5. 規格、文件與 Tractatus 對照

- [x] 5.1 依「只更新有直接證據的 Tractatus 對照並保留 #204 邊界」更新 `docs/store-format.md`、public API comments 與 4.023、4.05、4.06、4.2、4.25、4.26、4.431、5、5.31、5.44、5.51、5.512、6.5 corpus claim／locator／history，維持原 partial／aspirational／intentional_nonconformance 狀態並重產並排 Markdown；以 strict corpus validate、連續兩次 render hash 相等、`render --check` 及過時 `testAuthoredNeverReturnsFails`／“no negation” 掃描無殘留驗證。

## 6. 完成與對抗閘門

- [x] 6.1 依 `Observable behavior and API`、`Failure modes`、`Acceptance and verification` 與 `Scope boundaries` 執行六項 load-bearing mutants（略過 nested validation、unknown→fails、absence→fails、忽略 witness binding、no 沿用 subject valuation、denied 自動轉 negation），每項先 RED 再還原；其後跑 warnings-as-errors affected/full Swift suite、external API typecheck、Spectra analyze／strict validate、strict corpus validate／render check、source asset digest、whitespace／scope gates 與三路獨立 audit，並確認 #205→#202→#203 archive prerequisite 仍被如實報告而未擅自封存。
