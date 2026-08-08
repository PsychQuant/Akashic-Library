# 邏輯圖像能否描繪未來？——Bild、命題、問句與 Git branch

> 這份文件是**解釋**，不是規格。規範性原則仍以
> [`../design-principles-and-philosophy.md`](../design-principles-and-philosophy.md)
> §7、§12、§14、§16 與各版本 store-format／phase spec 為準。
>
> 本文處理四個容易混在一起的問題：
>
> 1. 《邏輯哲學論》的 **Bild** 為什麼應譯為 picture／圖像，而不是 Figure；
> 2. logical picture 能否描繪尚未發生的未來事態；
> 3. 問句是否也是一幅 logical picture；
> 4. Git branch 能否被當成 possible world。
>
> 文中對 Akashic 的對照是**受維根斯坦啟發的工程詮釋**，不是宣稱 Akashic 已把
> 《邏輯哲學論》逐條實作。

## 一分鐘版

- 維根斯坦的術語是德文 **Bild**，標準英文是 **picture**。`Figure` 不是圖像論的標準術語。
- logical picture 不只重畫已成立的事實；它首先表現邏輯空間中的一個**可能事態**。所以未來時點可以進入命題的內容。
- 圖像本身不「發問」。一個問題較精確地說，是把可能答案組織成一組可判定的命題圖像。
- 有意義不等於已知為真，也不等於未來已被形上學地決定。《邏輯哲學論》本身沒有提供完整的 branching-time 語意學。
- 現在的事實不能以邏輯必然性推出未來事件；預測、排程、假設與已發生事實必須分層。
- Git branch 可以作為「模型中的可能延續」的工程類比，但它不是維根斯坦原文中的 possible world，也不會因 merge 就變成實際世界。
- 對 Akashic 而言，未來內容應先作為帶來源與知識狀態的 assertion；等到相應時間出現 evidence／attestation 並經裁決，才可成為 accepted fact。

---

## 1. 先修正術語：Bild，不是 Figure

《邏輯哲學論》2.12 的德文是：

> **Das Bild ist ein Modell der Wirklichkeit.**

這裡的核心字是 **Bild**。標準英文翻譯使用 **picture**，中文可譯為「圖像」、
「圖示」或「圖式」。因此最穩定的術語對應是：

```text
Bild
└── picture
    └── 圖像／圖式
```

`Figure` 在英文裡容易指幾何圖形、論文插圖、數字或人物。它偶爾可以作為普通英文，
卻不是維根斯坦圖像論的標準專名。Akashic 的文件、型別或變數若要直接標示這個哲學來源，
應優先使用：

```text
LogicalPicture
PropositionalPicture
PictureModel
```

而不是：

```text
Figure
LogicalFigure
```

### 1.1 為什麼叫 picture

picture 不是因為命題必須「看起來像」現實，而是因為它具有一個能與現實逐項對照的結構：

```text
圖像中的元素        ↔ 世界中的對象
元素之間的配置      ↔ 對象之間可能的配置
整幅圖像            ↔ 一個可能事態
圖像與現實的符合    ↔ 真
圖像與現實的不符合  ↔ 假
```

因此，照片只是 picture 的一個特例。句子、樂譜、模型、圖表與形式化記錄也可能具有
picture-like 的功能，只要存在一條明確的 projection rule，使其結構能對應到所描繪的事態。

### 1.2 Tatsache 與 Sachverhalt 不宜混譯

使用者常見的英文版本把 **Sachverhalt** 譯作 *atomic fact*；其他譯法則使用
*state of affairs*。Akashic 應優先使用：

```text
Tatsache      = fact／事實
Sachverhalt   = state of affairs／事態
```

理由不是要解決全部翻譯爭議，而是要保留一個重要區分：

- **事態**可以被表現為一種可能配置；
- **事實**是實際成立的事態。

這個區分正好防止 Akashic 把「可以描述」誤寫成「已經成立」。

---

## 2. logical picture 的最小結構

《邏輯哲學論》2.13–2.15 把圖像拆成元素、元素配置與表現形式；2.181 把共享邏輯形式的圖像稱為
logical picture；2.202 則說圖像在邏輯空間中表現一個可能事態。

可以把最小結構寫成：

```text
Picture P
├── elements
│   ├── e1 represents object o1
│   └── e2 represents object o2
├── configuration
│   └── R(e1, e2)
├── projection rule
│   └── maps R(e1, e2) to R(o1, o2)
└── sense
    └── the possible state of affairs R(o1, o2)
```

真假不是 picture 的組成材料，而是 picture 與現實比較後的結果：

```text
P depicts S
S obtains in reality      → P is true
S does not obtain         → P is false
```

這也解釋為什麼**假命題仍然有意義**。它仍然告訴我們世界必須如何，才會使它為真。

---

## 3. 維根斯坦自己的例子，以及它們對 Akashic 的意義

### 3.1 桌子、椅子與書：配置本身表達意義

3.1431 要我們想像不用文字，而用桌子、椅子、書等空間物件構成 propositional sign。
這些物件彼此的空間位置就能表達命題的 sense。

例如：

```text
[BOOK]   [LAMP]
```

若 projection rule 約定水平位置表示 `left_of`，這個配置可以描繪：

```text
left_of(book, lamp)
```

重點不在 BOOK 或 LAMP 各自，而在它們**被安排成什麼關係**。

對 Akashic 而言：

```text
Person P
Work W
```

只是兩個可指涉項目。加入：

```text
authored(P, W)
```

才形成一個可判真偽的事態。

### 3.2 `aRb`：不是符號列，而是符號之間真的有配置

3.1432 的要點是：不是整串 `aRb` 額外說明「a 與 b 有 R 關係」；而是符號 `a` 與 `b`
在命題符號中被安排成某種關係，這個**符號事實**描繪了對象事實。

```text
符號層：R(a, b)
          │ projection
世界層：R(A, B)
```

這對資料建模很重要。把三個字串放進同一陣列：

```yaml
- a
- R
- b
```

還不等於形成 picture。系統必須知道哪一項是端點、哪一項是 relation、方向如何、
時間與角色如何附著，以及如何投射到世界主張。

### 3.3 樂譜、唱片溝槽、聲波與音樂思想

4.014–4.0141 的例子把樂譜、唱片溝槽、聲波與音樂思想放在一起。它們表面完全不同，
卻能依規則互相轉換，因而共享某種結構。

```text
score
  ↕ projection rule
sound waves
  ↕ projection rule
gramophone groove
```

這比「照片像被拍物」更接近 Akashic：

```text
YAML canonical record
  ↕ parser / schema / projection
Swift value
  ↕ export rule
CSL-JSON / BibLaTeX / graph view
```

但要注意：衍生格式只有在轉換規則保存相關結構時，才是同一內容的不同表現。
一旦 export 丟失 provenance、identity 或 temporal distinctions，它就不再是可逆的完整 picture，
而只是目的限定的 projection。

### 3.4 假圖像仍然是圖像

假設記錄提出：

```text
located_in(book, drawer)
```

實際上書在桌上。這筆 assertion 是假的，但不是無意義的。因為我們知道現實必須如何，
它才會為真。

因此 Akashic 必須區分：

```text
well-formed assertion
truth status
evidence
adjudication
```

不能把「驗證通過」直接等同於「世界中為真」。Schema validation 只證明它是一個可解析、
符合記法的 picture candidate，不證明 reality agrees with it。

### 3.5 同一 sense 可以有不同載體

一句自然語言、YAML relation record、圖形邊與 SQL row 可能表達同一個 authorship sense：

```text
「P 寫了 W」
authored(P, W)
P --authored--> W
(subject=P, predicate=authored, object=W)
```

它們是否真的等價，不由外觀決定，而由 projection rules 與保存的 distinctions 決定。
例如 SQL row 若沒有作者次序、角色、來源與有效時間，就只保留了原 assertion 的一部分。

---

## 4. 對現有 §14 對照表的質疑與修正

`design-principles-and-philosophy.md` §14 目前使用一張直覺對照表：

```text
Entity                  = 圖像元素
Relation / assertion    = 元素的配置
Schema / ontology       = 可表現形式
Record                   = 可能事態的圖像
Evidence / adjudication = 圖像與世界的比較機制
```

這張表作為入口是有用的，但若把等號理解成哲學上的同一，就會過度延伸。

### 質疑一：Akashic entity 不是《邏輯哲學論》的 simple object

Tractarian object 是圖像論中的形式條件；Akashic entity 則可能是有內部欄位、版本、
時間軸與裁決歷史的複雜記錄。

### 回應

等號應讀成「在這個工程類比中扮演相似角色」，不是本體論同一：

```text
Akashic entity reference ≈ picture element
Akashic entity record    ≠ Tractarian simple object
```

真正進入一幅具體 picture 的，通常不是整份 entity file，而是其中穩定的 identity reference。

### 質疑二：整份 record 通常不只是一幅 picture

一份 Person 或 Work record 可能同時包含：

- identity；
- 多個名稱使用；
- 多段時間軸；
- 多筆 assertion；
- provenance；
- competing evidence；
- adjudication state。

它不是一個單一命題，而是許多命題與後設紀錄的 container。

### 回應

更精確的映射是：

```text
relation instance / assertion  ≈ 一幅命題圖像
entity record                  ≈ 多幅圖像及其歷史的 canonical container
```

### 質疑三：schema 不等同於 logical form

Akashic schema 是明文寫出的工程文法，可以版本化、遷移與修改；維根斯坦的 logical form
不是一份可被系統完整列出的 YAML schema。

### 回應

schema 最多是**projection grammar 的顯式部分**，而不是 logical form 本身：

```text
schema / ontology
≈ what Akashic explicitly commits to as a notation and validation grammar
≠ the total logical form that makes representation possible
```

### 質疑四：evidence／adjudication 不是 picture 之外的純粹裁判

Evidence、source 與 adjudication 本身也都是世界中的事件，可以再被 picture：

```text
source S asserted p at t0
reviewer R accepted p at t1
library revised p at t2
```

### 回應

同一項資料可在兩個角色中出現：

1. 相對於第一階 assertion，它是比較與裁決材料；
2. 作為檔案史的一部分，它自己又是可被描述的第二階事態。

所以 Akashic 不是只保存 picture 與 reality，還保存**誰在何時用什麼根據比較了它們**。

---

## 5. 質疑：未來還不是事實，logical picture 怎麼描繪它？

這個質疑把兩件事合併了：

1. 某事態現在是否實際成立；
2. 我們現在是否能表現「它在未來時點成立」這種可能性。

logical picture 的首要對象不是「已被證明為真的事實」，而是可能事態。令：

```text
p@t1 = located_in(researcher, osaka, 2027-05)
```

只要我們知道：

- `researcher` 與 `osaka` 指涉什麼；
- `located_in` 如何組織兩端；
- `2027-05` 如何索引有效時間；
- 什麼觀察會使這個 assertion 為真或為假；

那麼 `p@t1` 現在就有 sense。它描繪的是：

```text
在 t1，researcher 與 osaka 形成 located_in 事態
```

### 回應：未來時態不破壞 picture relation

圖像可以先於被描繪事態的實際發生而存在，因為 picture 的 sense 由可能配置決定，
不是由當下已知的 truth value 決定。

```text
現在：p@t1 已有 sense
現在：p@t1 的 truth 可能未知
t1 後：依 reality／evidence 判定 p@t1
```

### 但不能從這裡推出「未來已經決定」

這裡必須保持克制。《邏輯哲學論》沒有提供完整的 tense logic 或 branching-time semantics。
「未來命題現在有 sense」不會自動回答：

- 它現在是否已經非真即假；
- 未來是否形上學地開放；
- 所有可能延續是否同樣真實；
- truth bearer 應是時態命題、帶時間索引的無時態命題，或其他形式。

因此 Akashic 可以採用 time-indexed proposition 的工程表示，但不應宣稱這已解決
open future 的形上學問題。

---

## 6. 質疑：一幅 picture 可以「問」未來嗎？

嚴格來說，picture／proposition 的功能是提出一個可真可假的 sense；問句則要求從可能答案中
作出區分。可以把 yes–no question 重建為：

```text
Q(p@t1) = { p@t1, not-p@t1 }
```

例如：

```text
「researcher 在 2027-05 會位於 Osaka 嗎？」
```

不是一幅真假已定的 picture，而是要求在兩幅互斥的 picture 中判定：

```text
located_in(researcher, osaka, 2027-05)
not located_in(researcher, osaka, 2027-05)
```

### 回應：問題是對 logical space 的切分操作

較精確的說法不是：

> Figure 在詢問未來。

而是：

> **一個 future query 以一組可表達的 answer-propositions 切分目前模型所容許的未來延續。**

《邏輯哲學論》6.5 把「可表達的問題」與「可表達的答案」連在一起，但它沒有提供一套完整的
interrogative semantics。上面的集合表示是對圖像論的現代化重建，不是維根斯坦原文中的公式。

### 對 Akashic 的直接後果

```text
Query        = 對紀錄／模型執行的操作
Assertion    = 可真可假的內容
Fact         = 經 reality comparison 與裁決而接受的 assertion
```

因此 query 本身不應因為被執行，就寫入 World fact layer。只有「某人在某時提出了這個問題」
才是一項可另行保存的 usage event。

---

## 7. 質疑：既然現在已有 picture，是否可以從現在讀出未來？

不可以把 picture theory 變成預言機。

《邏輯哲學論》5.1361 明確否定從現在事件對未來事件作邏輯推導；6.363–6.36311 把歸納描述為
選擇與經驗相容的簡單規律，並以「明天太陽升起」說明它仍是 hypothesis；6.37 再區分因果期待與
logical necessity。

### 回應：三種「必然」必須拆開

| 狀態 | 意義 | 能否由 picture alone 得到 |
|---|---|---:|
| logically necessary | 否定它會產生邏輯矛盾 | 只在邏輯關係中 |
| model-necessary | 目前指定的所有模型延續都滿足它 | 可以，但只相對於模型 |
| causally expected／high probability | 依規律、資料或模型高度預期 | 需要經驗假設 |
| scheduled／intended | 有計畫、承諾或制度安排 | 需要來源與狀態 |
| actually occurred | 相應事態在世界中已成立 | 需要 reality comparison |
| accepted fact | 圖書館依證據與規則接受它 | 需要 adjudication |

最危險的誤寫是：

```text
all modeled branches satisfy p
therefore p is logically necessary
```

正確的是：

```text
all modeled branches satisfy p
therefore p is necessary relative to this model and these constraints
```

模型可能漏掉可能性；自然定律也不是邏輯恆真式。

---

## 8. 質疑：Git branch 就是 possible world 嗎？

Git branch 很適合表示「從共同歷史分出的不同延續」：

```text
history up to t0
├── branch-a: p@t1
└── branch-b: not-p@t1
```

但這只是工程類比。

### 回應：可以使用，但必須標示四個限制

#### 8.1 《邏輯哲學論》談 logical space，不是 Git branch semantics

維根斯坦談的是可能事態及其組合所形成的邏輯空間。把 branch 當成完整 possible world，
是後加的模型設計，不是原文中的資料結構。

#### 8.2 一條 branch 不一定是一個完整世界

它可能只記一組差異：

```text
branch-a adds p
branch-b adds not-p
```

其餘世界狀態由共同 ancestor 提供。因此 branch 更像一個 world-delta 或 candidate history，
除非系統明確定義其 closure。

#### 8.3 merge 不是「這個世界成真」

Git merge 只表示版本歷史被合併。它不證明被合併內容在現實中成立。

```text
merge commit
≠ metaphysical actualization
≠ empirical verification
≠ adjudicative acceptance
```

要表達「哪個未來成為實際歷史」，仍需要 evidence、valid time、recorded time 與 adjudication。

#### 8.4 開發分支與世界分支不可混為一談

一般 branch 可能只是：

- 修正程式；
- 改 schema；
- 重寫文件；
- 實驗不同 UI。

這些不是 possible worlds。若 Akashic 日後真的使用 branch 表示 world alternatives，
必須讓這個用途在 namespace、metadata 或 repository boundary 上可辨識，不能從「它是 branch」
就推論「它是一個世界」。

---

## 9. Akashic 如何記錄未來而不冒充預言機

未來內容應先進入 assertion／projection 層，而不是直接進入 accepted world fact。

下列只是語意示例，不是目前 schema 的欄位規格：

```yaml
content:
  predicate: located_in
  subject: researcher-id
  object: osaka-id
  valid_time: 2027-05

epistemic_status: scheduled
source: invitation-or-plan-id
recorded_at: 2026-08-08
adjudication: unresolved
```

可能的知識狀態至少要能區分：

```text
hypothetical   只是在考慮一種可能
predicted      由模型或規律推估
scheduled      已有計畫或制度安排
intended       某行動者表達意圖
conditional    只在某條件下成立
attested       有來源證明某時點曾成立
refuted        證據支持其不成立
cancelled      原排程／意圖後來被取消
accepted       圖書館依規則接受為事實
```

這些狀態不能互相偷渡。例如：

```text
scheduled → actually occurred
```

不是自動轉換。排程可能取消、延誤或改地點。

### 時間到達後的流程

```text
future assertion p@t1
→ t1 到達
→ 收集 source / observation / record
→ 比較 picture 與 reality
→ 保存支持或反對 evidence
→ adjudicate
→ accepted / refuted / unresolved
```

圖書館因此可以保存「人們如何談論未來」，而不假裝自己從未來取得既成事實。

---

## 10. `satisfied`、`true`、`witnessed` 與 `attested` 的分工

這幾個詞不應互換。

### `satisfied`

用於模型語意：

```text
world/model w satisfies proposition p
w ⊨ p
```

它只說在指定 interpretation 下，`p` 在 `w` 中成立。possible branch 也可以 satisfy `p`。

### `true`

用於命題與實際世界的符合：

```text
p is true in the actual world
```

工程上仍需說明「actual world」由哪個資料層、時間與裁決狀態代表。

### `witnessed`

適合指有一個具體對象、事件或證據項能展示 existential claim 的成立，例如：

```text
exists x: authored(x, W)
witness = P
```

若只是說「某個 possible branch 讓 p 成立」，用 `satisfies` 比 `witnesses` 更精確。

### `attested`

適合檔案與 provenance：

```text
source S attests that p held at t
```

它表示「有來源如此證明／記載」，不自動等於 `p` 真，也不自動等於圖書館已 accepted。

### 建議用語

```text
branch/model satisfies p
source attests p
evidence supports p
adjudicator accepts p
actual history makes p true
```

這條詞彙鏈能防止「模型內可滿足」一路滑成「現實中已證實」。

---

## 11. 八個 Akashic 例子

### 例 1：entity 清單還不是世界圖像

```text
Person P
Work W
Organization O
```

只是可供配置的元素。至少要有：

```text
authored(P, W)
affiliated_with(P, O, t)
```

才開始說世界如何成立。這呼應「世界是事實的總體，不是事物的總體」。

### 例 2：錯誤 authorship 仍是有意義的 picture

```text
authored(P, W)
```

即使最後被證據否定，它仍然是一個可理解的 assertion。正確處理是保存來源、反證與裁決，
不是因為它為假就宣稱它從來不是命題。

### 例 3：名字不是 picture element 的穩定身分

```text
"Chen, YC"
```

可能是未解析 literal。只有 projection 已確定時，它才代表某個 Person identity。
因此 literal、name usage 與 resolved UUID 必須分層。

### 例 4：未來隸屬

```text
affiliated_with(P, O, 2027-05)
```

現在可以有 sense，但可能只是 offer、acceptance、intention 或 prediction。
`valid_time` 在未來不等於 assertion 已是 accepted fact。

### 例 5：取消不等於抹除

```text
t0: scheduled(event E, t1)
t2: cancelled(event E)
```

取消後不能刪掉 t0 的排程主張，因為「曾經排定」本身是歷史事實；但也不能把排程保留成
「E 在 t1 實際發生」。

### 例 6：問句不是 fact

```text
query: Did E occur at t1?
answers:
  - occurred(E, t1)
  - not occurred(E, t1)
```

可保存的是 query event 與後來的 answer assertion；不能把 query body 直接存成 world fact。

### 例 7：所有 branch 都有，不代表邏輯必然

若模型只允許兩條 branch，而兩條都含：

```text
P remains a person
```

這可能來自 schema invariant，而不是世界中的經驗事實。要問的是：

- 這是記法條件？
- identity invariant？
- domain assumption？
- 還是可由 observation 推翻的 assertion？

不同層次不能用同一個 `true` 混過去。

### 例 8：record 是 picture archive

```text
entities/<uuid>.yaml
```

可能同時保存或連結：

```text
identity
names over time
affiliations over time
assertions
sources
adjudications
```

它較像一個有版本的檔案夾，而不是一幅單一圖像。真正 picture-like 的最小單位通常是
其中一筆可判真偽的 assertion／relation instance。

---

## 12. 後期維根斯坦提供的第二層限制

即使上述區分都寫進 schema，規則仍不能自行決定所有未來案例。這正是主文件 §15–§16
引入 language game 與 rule-following 的理由。

例如 `scheduled` 的實際用法仍需要共同體判準：

- 口頭說「明年去大阪」算 intention 還是 schedule？
- 收到邀請但尚未接受算 conditional 還是 scheduled？
- 行程已買票但簽證未核准，狀態如何？
- 活動改成線上，原 `located_in` assertion 是 cancelled、refuted，還是被新 assertion 取代？

字典不能單獨決定。意義存在於使用、修正、先例與制度中。

因此早期與後期維根斯坦在 Akashic 中分工如下：

```text
早期：要求 assertion 有可比較的結構與 truth condition
後期：提醒 truth-condition schema 的實際套用仍依賴公開實踐
```

這不是前後互相取消，而是兩個不同層次的紀律。

---

## 13. 對 Akashic 文件與設計的結論

### 術語

- 直接引用《邏輯哲學論》時，使用 **Bild／picture／圖像**。
- `Figure` 只保留普通英文用途，不作為 picture theory 的專名。
- `StateOfAffairs` 指被描繪的可能事態。
- `Assertion` 指帶來源、脈絡與可判真偽內容的圖書館記錄。
- `Query` 指對 assertions／models 的操作，不是 fact。

### 映射

```text
identity reference                 ≈ picture element
assertion / relation instance      ≈ propositional picture
record                             ≈ container of pictures and their history
schema                             ≈ explicit notation / projection grammar
evidence + adjudication            ≈ archived comparison practice
```

所有 `≈` 都是結構類比，不是哲學同一。

### 未來

```text
future proposition
≠ future fact already retrieved

future query
= partition of expressible answer-propositions

possible branch satisfies p
≠ p has been witnessed in actual history

merge
≠ actualization
```

### 最終表述

> **A logical picture can depict a future state of affairs because it presents a possibility, not because it has already retrieved a future fact. A future question organizes alternative pictures; evidence and adjudication later determine which picture agrees with actual history.**

對 Akashic 而言，可以濃縮成：

> **圖像表現可能性；query 切分可能性；branch 保存模型延續；source 提供證據；adjudication 決定圖書館目前接受什麼。**

---

## 14. 原典索引

| 《邏輯哲學論》段落 | 本文用途 |
|---|---|
| 1、1.1 | 世界是事實的總體，不是事物清單 |
| 2.12–2.15 | 圖像是現實的模型；元素與配置 |
| 2.181–2.202 | logical picture 與可能事態 |
| 2.21–2.225 | 真／假需由圖像與現實比較 |
| 3.1431–3.1432 | 空間物件與 `aRb` 的配置例子 |
| 4.01–4.023 | 命題作為現實圖像；sense 與 yes／no 比較 |
| 4.014–4.0141 | 樂譜、唱片、聲波與 projection rule |
| 5.1361 | 未來事件不能由現在事件邏輯推出 |
| 6.363–6.36311 | 歸納與「明日太陽升起」仍屬 hypothesis |
| 6.37 | 只有 logical necessity |
| 6.5 | 可表達問題與可表達答案的關聯 |

原典可對照：

- [Tractatus Logico-Philosophicus：英文全文](https://www.wittgensteinproject.org/w/index.php/Tractatus_Logico-Philosophicus_%28English%29)
- [Logisch-philosophische Abhandlung：德文全文](https://www.wittgensteinproject.org/w/index.php/Logisch-philosophische_Abhandlung_%28Darstellung_in_Baumstruktur%29)
- [德英多語並列版](https://www.wittgensteinproject.org/w/index.php/Tractatus_Logico-Philosophicus_%28multilingual_side-by-side_view%29)
