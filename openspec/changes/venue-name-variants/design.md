# Design

## 1. `variant` 的形狀：跟 person 一樣，還是跟 organization 一樣？

三個候選，第一個否決、第二個採用、第三個記錄為考慮過：

| 形狀 | 判斷 |
|---|---|
| **A. person 的巢狀分割**（`names: {authorized: [...], variant: [...]}`）| ❌ 需要改所有現有 402 筆的結構，而它們的 `authorized:` 已在**頂層**。改結構的成本落在 402 筆，換到的只有「跟 person 長得一樣」 |
| **B. 頂層再加一個 `variant:` 清單**（與既有 `authorized:` 並列）| ✅ **採用**。402 筆不動，35 筆補一個鍵。additive，舊 binary tolerant-preserve |
| C. 在 names item 上加 `kind: variant` 標記 | ⚠ 考慮過。它讓每一筆名字自帶角色，理論上更精確，但**它把兩個分割混在同一個清單裡**，於是「取全部 authorized」變成一次過濾而非一次讀取——與既有 402 筆的讀法不一致 |

B 的形狀因此是：

```yaml
venue:
key: plos-one
names:
- value: PLOS ONE
authorized:
- PLOS ONE
variant:
- PLoS One
- PLoS ONE
```

**為什麼不是「把 variant 從 names 移走」**：`names` 仍是那本刊所有已知名字的**全集**，
`authorized` 與 `variant` 是它上面的兩個標記。這與 person 的既有語意一致
（`authorized-name` spec 通篇把 variant 當成「同一個人的另一種寫法」而非另一個實體）。

## 2. 時間軸語意：收窄而不是刪除

`venue-entity` spec 的「Venue name history timeline」Requirement **不刪**。它的
Scenario（`end: 2003` / `start: 2003`）目前零實例，但那是**還沒發生**，不是**不會發生**
——刊名沿革是真的存在的現象（#421 舉了 JRSS Series B／C 的例子）。

改的是它的**適用範圍**：時間欄位只出現在沿革的 names item 上，`variant` 分割內的名字
不帶時間。這讓「零實例」從一個**尷尬**（宣稱的用途沒人用）變成一個**誠實的狀態**
（那個用途還沒遇到，而現在有東西擋著它的位置了）。

依 `zero-instance-guards` 的紀律，這是該檔裁決表的一個新情形——它不是「為還沒發生的
形狀寫守衛」，是「為還沒發生的形狀**保留位置**」。若要進那張表，需要新增一列
（本提案不代做，因為那條規則明寫不得依性質相似類推）。

## 3. format bump 與部署順序

本改動是 **additive**（新增一個可選的頂層鍵），舊 binary 讀到會走 tolerant-preserve
原樣保留。但**遷移**那 35 筆會改寫檔案內容，所以仍需 format bump 到 **14**。

`format bump 會打死三個 binary`——CLI、`akashic-mcp`、App 各自獨立編譯，只升一個的話
另外兩個對 format 14 的 store **整份拒讀**。部署順序（沿用 #304 venue change 的既有六步）：

1. 三個 binary 全部 build 到含新 `supported = 14` 的版本
2. `migrate-venues`（或新的 `migrate-venue-variants`）**乾跑**，逐筆列出將改寫的檔案
3. 確認每個將被改寫的檔**自身**受 git 追蹤（per-file trackedness pre-flight）
4. `--apply`
5. `akashic validate` 零 diagnostic
6. 手動 bump `store.yaml` 的 format 到 14

**遷移命令走 CLI-only**（`mcp-cli-parity` 的既有裁決：格式遷移＝維運例外，MCP 的 LLM
消費者不是該角色）。要在該檔的 CLI-only 表加一列。

## 4. 遷移的判準：哪些名字是 variant？

**不猜。** 依 `identity-is-judged-not-matched`，「這兩個字串是同一本刊的兩種寫法」是
一個判定，不是字串比對的結果。但這裡有一個**它不適用**的情形：

那 35 筆的多個名字**已經在同一筆記錄裡**——它們是誰的別名，前一次判定已經做過了
（那正是它們被寫進同一個 `names` 的原因）。本次遷移不做新判定，只是把既有判定的結果
**重新分類**：`authorized` 清單裡有的留在 authorized，其餘進 variant。

這是機械的、可逆的、零新斷言。若某一筆其實是沿革（不是異寫法），遷移會把它誤標成
variant——**所以乾跑要逐筆印出來給人看**，而不是靜默套用。實測 35 筆，人工過目可行。

## 5. 與 #421 的關係

#421 有三層裁決，本提案只解掉**第二層的前提**（「`names` 的時間軸什麼時候會真的開始
帶時間」——答案是：等 variant 搬走之後，它才有可能只裝沿革）。

**不解**的兩層：person 的名字要不要有時間軸（第 1 層）、分裂要不要有模型位置（第 3 層）。
後者是 `entity-backlink-completeness` 封閉列舉的新一條邊，需要寫出「為什麼那個方向是
正典」——那是獨立的裁決。
