# 為什麼 Akashic-Library 不只是 Google？——檢索、0／1、真值與世界表徵

> 這份文件是**哲學與設計上的反對意見／回應**，不是現行 store-format 規格。
> 它延伸：
>
> - [`../design-principles-and-philosophy.md`](../design-principles-and-philosophy.md)
> - [`logical-picture-future-and-questions.md`](logical-picture-future-and-questions.md)
>
> 核心問題是：如果搜尋引擎也能接受問題並輸出結果，甚至輸出 `0`／`1`，
> 那麼 Akashic-Library 作為《邏輯哲學論》的構造式詮釋，是否只是一個被哲學語言包裝的 Google？

## 一分鐘版

「Akashic 只是 Google」這個質疑，若只是指出**目前實作可能仍主要停留在索引與檢索層**，值得認真看待；
但若它主張搜尋與真值判定在概念上是同一件事，就犯了層次錯誤。

搜尋引擎通常回答：

```text
哪些文件與 query 相符？
哪些結果最相關？
資料庫裡有沒有這一列？
```

Tractarian world model 必須回答：

```text
這個符號結構表現哪一個可能事態？
在指定 interpretation／world 下，該事態是否成立？
來源只是提出 p，還是世界使 p 為真？
不知道 p，是否等於 not-p？
複合命題的真值如何由基本命題組合？
```

兩種系統都可能輸出一個 bit，但：

> **相同的輸出載體，不等於相同的語意。**

`grep` 找到字串可回傳 `0`；SQL `EXISTS` 可以回傳 `true`；分類器可以輸出 `1`；SAT solver 可以說
公式 satisfiable；命題 valuation 也可以使用 `1` 表示真。這些 `1` 所表示的事情完全不同。

Akashic 的非平凡性不在於「它也能吐出 0／1」，而在於是否能正式建立：

```text
符號／命題
→ projection rule
→ possible state of affairs
→ world-relative valuation
→ source / evidence / adjudication
→ compositional truth-functions
```

如果這些層次沒有實作，批評成立；如果這些層次被明確建構，「只是 Google」就不足以描述這個專案。

---

## 1. 先釐清對象：瀏覽器、Google、資料庫與世界模型不是同一層

「瀏覽器沒有真假值」抓到了方向，但還不夠精確。

### Browser

Browser 是介面與執行環境。它可以呈現搜尋結果、真值表、數學證明、資料庫結果或世界模型；
它本身不是這些語意系統。

### Search engine

搜尋引擎的典型工作是：

```text
crawl
→ index
→ match
→ rank
→ retrieve
```

它的核心輸出通常是 documents、snippets、scores、entities 或 answers。

### Database

資料庫可以回答：

```sql
SELECT EXISTS (...)
```

並輸出 `true`／`false`。但這個布林值首先表示：

> 指定資料庫狀態中是否存在符合條件的 row。

它不會自動表示：

> 現實世界是否使一個命題為真。

### Knowledge graph

Knowledge graph 比一般搜尋索引更接近 Akashic，因為它可以儲存 entities 與 relations；
但「graph 裡有一條 edge」仍可能只表示：

```text
某來源提出了這條 edge
系統匯入了這條 edge
目前資料集包含這條 edge
```

而不必然表示：

```text
這項事態在世界中成立
```

### Tractarian world model

一個以《邏輯哲學論》為目標的系統，必須再多做至少四件事：

1. 指定符號如何代表對象；
2. 指定符號配置如何投射到可能事態；
3. 指定在何種 world／interpretation 下命題為真；
4. 區分 assertion、evidence、acceptance 與 truth。

所以更精確的爭點不是：

> Browser 有沒有真假值？

而是：

> **系統中的 `0`／`1` 究竟是哪一種函數的值？它的 domain、interpretation 與 truth condition 是什麼？**

---

## 2. 「都吐 0／1」為什麼是平凡化

任何數位電腦最終都可以用 bit 表示結果。若僅因兩個系統都輸出 `0`／`1`，就說它們做的是同一件事，
那麼幾乎所有計算都會被抹平成同一種操作。

考慮以下函數：

### 字串比對

```text
match(document, query) ∈ {0, 1}
```

`1` 表示文件符合搜尋條件。

### 程式執行狀態

```text
exit_status(program) ∈ {0, 1, 2, ...}
```

許多 Unix 工具使用 `0` 表示成功，但這不是邏輯上的 truth。

### 分類器

```text
classifier(x) ∈ {0, 1}
```

`1` 表示模型把 `x` 分到某類，可能判錯，也可能只是超過門檻。

### SAT solver

```text
satisfiable(formula) ∈ {0, 1}
```

`1` 表示存在一個 assignment 使公式為真，不表示該公式描述的事情在 actual world 中已發生。

### SQL existence query

```text
exists(row satisfying condition) ∈ {0, 1}
```

`1` 表示資料庫中有列符合條件。

### 命題 valuation

```text
v_I,w(p) ∈ {0, 1}
```

`1` 表示在 interpretation `I` 與 world `w` 下，命題 `p` 為真。

它們共享相同的 codomain：

```text
{0, 1}
```

但 domain、函數規則與語意角色完全不同：

```text
match ≠ classify ≠ execute ≠ satisfy ≠ exist-in-database ≠ be-true-in-a-world
```

因此：

> **真值不是因為資料型別叫 Boolean 才成為真值。真值來自它在一套 interpretation、projection 與 compositional semantics 中扮演的角色。**

---

## 3. 最簡單的反例：搜尋到一個句子，不等於句子是真的

令：

```text
p = 地球是平的
not-p = 地球不是平的
```

假設 index 中有：

```text
document d1 asserts p
document d2 asserts not-p
```

搜尋 `地球是平的` 可以找到 `d1`：

```text
match(d1, query-p) = 1
```

搜尋 `地球不是平的` 也可以找到 `d2`：

```text
match(d2, query-not-p) = 1
```

搜尋引擎在這裡沒有矛盾。兩個 `1` 都表示：

```text
有文件符合這個 query
```

但若使用 classical valuation，在同一個 world、同一 interpretation 下：

```text
v(p) = 1
v(not-p) = 1
```

就不能被當作普通的一致 valuation。

Akashic 必須保存的是：

```text
asserts(d1, p)
asserts(d2, not-p)
```

然後再分別處理：

```text
source credibility
evidence for p
evidence against p
library adjudication
world-relative truth
```

這個例子直接顯示：

```text
「有文件如此說」
≠
「事情確實如此」
```

Google 的搜尋命中首先證明的是第一句，而不是第二句。

---

## 4. 搜尋的 0／1 與真值的 0／1

可以正式比較兩種函數。

### Boolean retrieval

令文件集合為 `D`、query 集合為 `Q`：

```text
m : D × Q → {0, 1}
```

其中：

```text
m(d, q) = 1
```

表示文件 `d` 符合 query `q` 的 retrieval criterion。

### Propositional valuation

令命題集合為 `P`、interpretation 為 `I`、world 為 `w`：

```text
v : P × I × W → {0, 1}
```

其中：

```text
v(p, I, w) = 1
```

表示在 `I` 與 `w` 下，`p` 所描繪的事態成立。

這兩者並不只是在演算法細節上不同；它們在問不同的問題：

```text
m 問：這個 representation 是否符合 retrieval condition？
v 問：這個 proposition 是否與指定 world 相符？
```

即使搜尋引擎把答案壓成：

```text
YES / NO
```

仍必須問：

```text
YES to what?
```

- 有匹配文件？
- 有資料列？
- 有來源提出？
- 知識圖譜中有 edge？
- 模型預測機率超過門檻？
- 所有可容許 worlds 都滿足？
- actual world 使 proposition 為真？

沒有這個語意區分，`1` 只是無標籤的 bit。

---

## 5. 資料庫裡沒有，不等於世界中為假

「只是 Google／資料庫」的另一個問題，是它容易暗中採用 closed-world assumption：

```text
not found
therefore false
```

但 Akashic 的核心倫理與圖像論要求至少區分：

```text
true
false
unknown
unrecorded
unresolved
conflicted
unsupported
not expressible in current schema
```

例如：

```text
沒有查到 authored(P, W)
```

可能表示：

1. `P` 沒有寫 `W`；
2. 圖書館尚未匯入相關來源；
3. 作者名字尚未 resolution；
4. 來源彼此衝突；
5. 目前 schema 無法表達該角色；
6. query 寫錯；
7. index 過期，但 canonical store 有資料。

因此：

```text
search result count = 0
≠
v(p) = 0
```

若 Akashic 把這兩者混在一起，它就真的會退化成檢索系統。

---

## 6. Akashic 應具有的三個不同函數

最少應區分 retrieval、epistemic adjudication 與 truth valuation。

### 6.1 Retrieval

```text
R(q, library_state) → ranked records / assertions / sources
```

這一層與 Google、全文搜尋、vector search、SQL query 類似。

### 6.2 Epistemic／archival adjudication

```text
J(p, evidence, policy, time)
→ accepted / rejected / unresolved / conflicted
```

這一層回答：

> 圖書館目前依哪些來源與規則，如何處理這項主張？

### 6.3 World-relative valuation

```text
V(p, interpretation, world) → true / false
```

這一層回答：

> 在指定模型／世界中，`p` 所描繪的事態是否成立？

三者可能相關，但不能等同：

```text
R(q) finds assertion p
≠ J(p) accepts p
≠ V(p) = true
```

專案真正困難之處，就是讓這三層既能連接，又不互相冒充。

---

## 7. Google 可以有 Knowledge Graph；那 Akashic 還有什麼不同？

反對者可以進一步說：現代搜尋引擎不只是 keyword matching，也有 entities、relations、direct answers、
knowledge panels 與模型生成答案。因此，把 Google 說成純文件搜尋也可能過度簡化。

這個反駁是合理的。Akashic 不能只靠「我有 graph」就宣稱自己不同。

真正的界線應放在**可審計的語意承諾**：

| 問題 | 一般搜尋／answer system | Akashic 的目標 |
|---|---|---|
| identity 如何決定 | 內部模型，通常不透明 | canonical identity + evidence + adjudication |
| edge 表示什麼 | 搜尋／回答所需的知識表示 | assertion、relation、source、acceptance 分層 |
| 未知與 false | 常依產品目的處理 | 必須正式區分 |
| time | 可能用於 freshness/ranking | valid time 與 recorded time 是語意層 |
| conflicting sources | 可折疊成單一答案 | competing assertions 可共存 |
| truth condition | 通常不是公開的形式契約 | 必須寫出 projection 與 valuation |
| possible worlds | 非核心 | 若宣稱 Tractarian interpretation，必須明定 |
| Git history | 部署／程式歷史 | canonical meaning 與修正史的一部分 |
| 語言界線 | 產品能力邊界 | 可說／不可說必須由 representation boundary 顯示 |

這不是說 Google 原理上不能加入上述能力；而是：

> **一旦一個搜尋系統正式加入這些語意層，它也就不再只是普通意義的搜尋引擎。**

所以爭論不應建立在品牌名稱，而應建立在 architecture 與 semantics。

---

## 8. 這個質疑在哪種情況下會成立？

「Akashic 只是 Google」不能被簡單嘲笑，因為它可以成為一項有力的失敗測試。

若專案最後只有：

```text
文件匯入
全文索引
vector embedding
entity lookup
相關性排序
LLM 摘要
```

那麼無論文件中引用多少維根斯坦，它仍主要是搜尋／知識管理系統。

以下情況會使質疑成立：

1. `assertion exists` 被直接當成 `assertion is true`；
2. `not found` 被直接當成 false；
3. relation 只是 graph edge，沒有 projection／truth condition；
4. source、evidence、adjudication 與 world fact 沒有分層；
5. possible world 只是 Git branch 的比喻，沒有 valuation semantics；
6. elementary proposition 沒有明確 primitive profile；
7. truth-functions 只有程式中的 Boolean operators，沒有命題語意；
8. `0`／`1` 沒有標示是 match、acceptance、satisfaction 還是 truth；
9. 系統不能保存矛盾來源而不使 world layer 自身矛盾；
10. 《邏輯哲學論》的命題只被註解引用，沒有 realization mode 或 invariant。

因此最有力的回應不是：

> 這個質疑很蠢。

而是：

> **請指出 Akashic 的哪一層只做 retrieval；我們再展示 proposition、projection、valuation、provenance 與 adjudication 如何超出 retrieval。若展示不出來，質疑就是對的。**

---

## 9. 要讓專案不再 trivial，最低限度必須實作什麼？

### 9.1 Typed proposition representation

不能只保存文字：

```text
"P wrote W"
```

而要有可解釋的結構：

```text
authored(P, W)
```

包含 argument positions、predicate identity、time、role 與 context。

### 9.2 Projection rule

系統必須知道：

```text
符號 P 指涉哪個 person identity
符號 W 指涉哪個 work identity
authored 的方向與 arity 是什麼
什麼世界狀態會使命題成立
```

### 9.3 World／model context

不能只問：

```text
p 是真是假？
```

而要問：

```text
p 在哪個 interpretation／world／time 下為真？
```

### 9.4 Truth-functional composition

若：

```text
p = authored(P, W)
q = affiliated_with(P, O, t)
```

系統必須能組成並評價：

```text
p and q
not-p
p or q
p implies q
```

而不只是對每個字串個別搜尋。

### 9.5 Unknown 不等於 false

需要明確區分至少：

```text
true
false
undetermined in model
unknown to library
conflicted evidence
not expressible
```

### 9.6 Assertion 不等於 fact

至少需要：

```text
source S asserts p
source T denies p
evidence E supports p
library accepts p at t
world w satisfies p
```

### 9.7 Provenance 與 adjudication

每個 accepted claim 應能追溯：

```text
誰提出？
何時提出？
依據是什麼？
誰裁決？
何時修正？
```

### 9.8 Negative／refusal semantics

系統必須能拒絕把沒有 projection rule 或 truth condition 的內容偽裝成普通 fact。

### 9.9 Tractatus conformance matrix

每一條欲實現的命題應標示：

```text
instance
structural invariant
semantic operation
formal derivation
refusal
shown constraint
meta-elucidation
declared nonconformance
```

否則「表徵《邏輯哲學論》」只是一個無法反駁的口號。

---

## 10. 更強的形式比較

可以把一般搜尋系統簡化為：

```text
SearchSystem = ⟨D, Q, Index, Score, Rank⟩
```

其中：

- `D`：文件；
- `Q`：queries；
- `Index`：可搜尋表示；
- `Score(d, q)`：相關性；
- `Rank(q)`：排序結果。

而 Tractarian Akashic 至少需要：

```text
AkashicSemantics =
⟨O, A, P, I, W, π, V, S, E, J, H⟩
```

其中：

- `O`：可指涉 identities；
- `A`：possible states of affairs；
- `P`：propositions；
- `I`：interpretations；
- `W`：worlds／world models；
- `π`：proposition 到 state of affairs 的 projection；
- `V`：world-relative valuation；
- `S`：sources；
- `E`：evidence；
- `J`：adjudication；
- `H`：versioned history。

搜尋仍然可以是 Akashic 的一個子系統：

```text
Search ⊂ Akashic
```

但不能反過來說：

```text
Akashic = Search
```

除非上述語意結構實際上不存在。

---

## 11. 一個 Akashic 例子：同一個問題的五種 `1`

命題：

```text
p = authored(P, W)
```

系統可能產生五種表面相同的 `1`：

### 1. Search match

```text
match(query, source-document) = 1
```

表示文件包含相關文字。

### 2. Record existence

```text
exists(assertion-record-for-p) = 1
```

表示 canonical store 中有一筆 assertion。

### 3. Source attestation

```text
attested_by(source, p) = 1
```

表示來源宣稱或支持 `p`。

### 4. Library acceptance

```text
accepted_by_library(p, t) = 1
```

表示圖書館在 `t` 時依規則接受 `p`。

### 5. World-relative truth

```text
V(p, I, w) = 1
```

表示 `p` 在 interpretation `I` 與 world `w` 中為真。

若程式只使用一個無型別的 `Bool` 傳遞這五件事，就會把整個哲學區分摧毀。

因此工程上應考慮語意型別，而不是只考慮 bit：

```text
MatchResult
RecordPresence
AttestationStatus
AdjudicationStatus
TruthValue
```

即使底層都以 `0`／`1` 編碼，上層也必須禁止彼此替換。

---

## 12. 維根斯坦式的核心回應

《邏輯哲學論》的 picture theory 並不是說：

> 對一句話執行查詢，系統回答 yes／no。

而是說：

> 命題符號的元素以某種方式配置，藉由 projection 表現對象可能如何配置；命題的真或假，取決於這個圖像是否與現實相符。

搜尋引擎可以搜尋命題；它不因此已經建立命題與現實之間的 picture relation。

所以最短的回應是：

```text
Google retrieves representations.
Akashic aims to model what those representations depict,
under what interpretation they are true or false,
and how the library knows or fails to know that.
```

中文可表述為：

> **Google 首先檢索表徵；Akashic 的目標是建模表徵所描繪的事態、使命題為真或假的條件，以及圖書館如何取得、爭議與修正這項認識。**

---

## 13. 對「這個質疑很蠢」的較精確評價

這個質疑有兩種版本。

### 弱版本：提醒專案可能只是搜尋工具

> 你目前展示的功能仍然是匯入、索引、查詢與回答，因此哲學主張可能超過實作。

這個版本不蠢，而且應成為專案的驗收壓力。它迫使 Akashic 證明自己真的有 formal semantics。

### 強版本：凡是輸出 0／1 的系統都等同於真值系統

> Google 也能回答 yes／no；Akashic 也吐 0／1，所以兩者沒有本質差異。

這個版本確實非常粗糙，因為它只看輸出編碼，忽略了：

- 被評價的對象不同；
- interpretation 不同；
- 函數的 domain 不同；
- `1` 的語意角色不同；
- compositional rules 不同；
- 與 reality 的比較關係不同。

它相當於說：

```text
溫度計顯示 1
投票系統顯示 1
邏輯系統顯示 1
因此三者做的是同一件事
```

問題不在數字，而在數字**代表什麼**。

---

## 14. 最終判準

Akashic 是否只是 Google，不應靠宣言決定，而應靠以下可證偽判準：

```text
Can the system distinguish:

retrieved(p)
asserted(p)
attested(p)
accepted(p)
satisfied(w, p)
true_in_actual_history(p)
unknown(p)
false(p)
not_expressible(p)
```

若不能，它仍主要是搜尋／資料管理系統。

若能，而且這些區分由 schema、型別、valuation、tests、Git history 與拒絕規則共同維持，
那麼它就不只是搜尋引擎；它是一個試圖把表徵、世界、真值與知識史放進同一個可審計架構的系統。

可以濃縮為：

> **`0`／`1` 很 trivial；使它成為真值的語意結構不 trivial。**

以及：

> **搜尋回答「哪裡出現了這個 representation」；圖像語意回答「這個 representation 描繪什麼，以及在什麼 world 中成立」。**

這才是 Akashic-Library 必須證明的差異。
