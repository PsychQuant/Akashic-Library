# 已識別的歧義，要在不可逆的寫入**之前**消解——政策預設不是判定的替代品

使用者 2026-09-09（+08:00）定調（#547）：「**以消歧異為準**」，並指名這條規則的來源是
[Foresay](https://github.com/kiki830621/foresay)（Human-AI Confirmation Protocol）。

適用於**寫入面**，且滿足下列**其一**（封閉二類，不得依性質相似類推第三類）：

1. **操作本身不可逆**——store 無法回到先前狀態（合併＋刪檔、格式遷移、身分熔合）。
2. **操作可逆，但它的逆操作是維運例外**——逆操作要求 git 工作樹乾淨、乾跑逐筆過目、
   或屬 `mcp-cli-parity` CLI-only 表的「維運例外」那一類。`resolve-divergence`
   （合併＋全庫參照改寫＋刪檔）即此形。

不適用於**讀取面**，也不適用於**逆操作與正操作同級**的寫入面（`tag`／`link`／
`library add`／`set-status` 那類冪等的集合語意——錯了再跑一次就好）。

## 規則

**當一個歧義在寫入之前就已經被識別出來，不得用政策預設把它做掉。** 三個分支，
逐一對應 Foresay `core/protocol.yaml` 的 `response_types`：

| store 的狀態 | Foresay 的終端 | 本 repo 的落地 |
|---|---|---|
| 不清楚（`not_clear`） | 「Disambiguate（依 disambiguation taxonomy），**然後重跑乾跑**」 | **先消歧，再寫**。消歧的結果餵回同一個乾跑 |
| 清楚但不可逆 | 「Confirm——渲染格式、**等使用者**、才執行」 | 乾跑逐筆過目 ＋ 顯式 `--apply` |
| 清楚且可逆 | 「直接跑，然後回報做了什麼」 | 照跑 |

**判不出來的，不寫，留在誠實狀態。** Foresay `docs/ambiguity.md` 把它列為第三層
（pragmatic／referential ambiguity——「這個 argument 指涉什麼」），並明寫**原則上無法由
文法消除**；它的出路是確認迴圈，或**標為 residue**（`concept.md` §4.6）。本 repo 的
residue 就是 `.literal`——`literal-first-then-key` 已經說了「literal 是誠實狀態，不是壞掉
的 key」，兩者是同一件事的兩種說法。

## 為什麼：判定相同，落地的代價差一個量級

「事前消歧」與「事後補救」問的是**同一個問題**（這幾個東西是不是同一個），差的是
那個判定落在什麼操作上：

| | 事前消歧 | 事後補救 |
|---|---|---|
| 面 | 建檔／寫入（`add-person`） | 合併（`resolve-divergence`） |
| 動作 | 一次 additive 寫入 | 合併 ＋ **全庫參照改寫 ＋ 刪檔** |
| 可逆性 | additive | **不可逆** |
| 前置 | 無 | git 工作樹乾淨、乾跑逐筆過目 |
| `mcp-cli-parity` 分類 | 一般寫入面 | **維運例外** |

**沒有任何情況下後者比前者好。** 這不是取捨，是一個嚴格佔優的順序。

而 Foresay R01 給了它 design-time 的版本：「**不可逆性不只在執行時逼出 confirm 分支，
它在設計時就縮窄了可說的形狀**——一個人核准的確認，如果那個形狀從來沒被約束過，
那個核准值不了多少」。

## 「安全的預設」不是本規則的例外——它是本規則的另一個分支

`bootstrap-people` 的政策是「**寧可分割，絕不合併**」，而那個方向**是對的**：
過度分割可回收（合併），錯誤熔合不可回收（`identity-is-judged-not-matched` 記的
謝叔蓉案，81 篇的代價付過一次）。

**所以本規則不否定那個預設，它限定那個預設的適用時機**：

> 安全預設是「**你無法消歧時**該往哪邊倒」，不是「**你可以消歧卻不做**」的許可。

判準可機械檢查：**那個歧義在操作之前是不是已經被識別出來了？**

- 已識別（你手上有一份組別清單）→ 先消歧。用預設等於明知故犯
- 未識別（要跑下去才知道會撞）→ 用安全預設，並**把撞到的印出來**

## 觸發過的實例

**2026-09-09 · #547**（本規則的直接起因）：`bootstrap-people --apply` 對 3,822 個
待建檔 literal，實測（live store 副本）865 → **4,687** 筆 person，其中：

```
Carol Dweck → dweck-carol-s ／ dweck-c-s ／ dweck-carol-s-2      3 筆
Bentler     → bentler-p-m ／ bentler-peter-m                      2 筆
```

`-2` 後綴表示程式**知道**撞了、還是分了。全 3,822 筆只摺疊了 **1** 組異寫
（`Eric-Jan Wagenmakers ≡ Eric‐Jan Wagenmakers`——U+002D vs U+2010，位元組差異，
不是名字形差異）。

**而那個歧義在操作之前就已經識別得出來**：把待建檔的 literal 依寬鬆鍵分組即得
——實測 3,917 個 distinct literal → **168 組**組員 >1（2 個異寫 135 組／3 個 20 組／
4 個 9 組／5–7 個 4 組），3,490 個單一寫法不必判定，38 個算不出寬鬆鍵。

出口實測可行：`add-person <key> --name <異寫1> --name <異寫2> …` 之後，那些 literal
從 `bootstrap-people` 的建檔提案**消失**，`resolve-people` 全部 `exact`（alias 完全命中）
指向同一筆。**零重複身分產生，`resolve-divergence` 完全不出現。**

**但同組不等於同一人**——這一句與上一句同等重要：

```
wang-ch: Chien-Hsun Wang ／ Chung-Ho Wang ／ Chih-Hsiung Wang ／ C.-H. Wang
         ↑ 前三個是三個不同的人；第四個縮寫形不知道是誰
```

所以每組要判的是「這組裡**哪些**是同一人」。而 `C.-H. Wang` 那一格判不出來時，
依本規則**不建、留在 literal**——那正是 Foresay 的 residue。

## 誠實邊界：本規則不主張「消歧比較容易」

換順序**不會**讓身分判定變容易。`C.-H. Wang` 是誰仍然要名字以外的證據（共同作者、
機構、作品領域——`identity-is-judged-not-matched` 的核心），事前判與事後判一樣難。

**本規則改變的是判不出來時的落點**：事前判，判不出的留在 literal（誠實狀態）；
事後判，它已經是一筆記錄了，清掉要走刪檔。

## 跟其他規則的關係

- `identity-is-judged-not-matched`：那條說**判定不得由字串謂詞代做**；本條說
  **那個判定該在什麼時候做**。兩條合起來：不能用字串謂詞代替判定（誰做），
  也不能用政策預設代替判定（何時做）。
- `literal-first-then-key`：那條的「literal 是誠實狀態」就是本條的 residue 出口。
  那條管生命週期的**起點**（進庫不猜），本條管**升格之前那一刻**。
- `two-kinds-of-edits`：本條是「提名（程式）→ 判定（AI）→ 落地（程式）」三段裡
  **第二段不得被第三段吞掉**的具體要求。
- `no-compat-fallback`：那條管「一次改完 vs 留兩條讀法」，理由同型——當下的痛
  vs 未來無界的代價。本條是它在**身分**這一軸的版本。
- 全域 `common-spec-prose-enumeration`：本檔的適用範圍是封閉二類，刻意不寫成
  「凡是危險的寫入都要先消歧」——那句話會在邊界上長出沒人同意的答案。

## 來源

[Foresay](https://github.com/kiki830621/foresay)（private）的三處，逐一對應本檔：

| Foresay | 本檔用它做什麼 |
|---|---|
| `core/protocol.yaml` 的 `response_types` | 三分支表的正典（`not_clear` 的終端是「先消歧再重跑乾跑」） |
| `docs/ambiguity.md` 第三層（pragmatic／referential） | 「判不出來的留在誠實狀態」的依據——那一層原則上不可由文法消除 |
| `00_principles/rules/R01`（Reversibility Governs Argument Openness） | 「不可逆性在 design-time 就縮窄可說的形狀」 |

Foresay 的核心第 4 條「**Clarify before execute — never guess**」是本規則的一句話版本。

**本檔不是 Foresay 的副本**：Foresay 管的是**人機確認的格式與迴圈**，本檔管的是
**本 repo 的寫入面在什麼時候必須先消歧**。兩者是協定與落地的關係，不是兩份會分岔
的規格（`no-compat-fallback` §「同一件事只能有一份描述」的判準：這兩份描述的**不是**
同一件事）。
