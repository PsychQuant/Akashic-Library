# 身分是判定出來的——一條規則、一張被撤回的 issue、一條新的寫入路徑（#383 #386 #388 #389）

2026-08-20 下午。這一輪的主線只有一句話：**`literal → key` 是 AI 判斷函數，不是字串謂詞。**
而它是**從一個失敗裡長出來的**——失敗的是我自己，連續兩版。

## 起點：一個看起來很合理的 bug

#383 說 `initials` 層對「已帶完整名」的 literal 仍只比首字母：literal `Chen-Yu Lin` 與候選
`Lin, Cheng-Yu`／`Lin, Chien-Yu`／`Lin, Ching-Yu` 全部相撞，三個完整名兩兩不同。實測 71 列
歧義裡有 32 列（45%）是這個形狀。

診斷做得很順：root cause 定位在 `LooseNameKey.initialsKeys` 無條件降維，而 doc comment 與
spec 的**所有** initials 範例都是「一側縮寫」——**實作範圍大於設計範圍**，spec 從未規定
literal 是完整名時該怎樣。

然後提了修法。**兩版，都錯。**

## 第一版：判準寫錯

「縮寫形」的判準寫成「given 段**存在**單字母段」。使用者問了一句「authorized name 不是
沒有縮寫嗎？」，一量就破：866 個 authorized name 用這個判準報 46 筆，其中 44 筆是誤判——
`Reeves, Gillian K.` 是西式中間名縮寫、`Liu, I-Ling` 的 `I` 是真的單字母音節（怡／伊）。

正確判準是「**全部**皆單字母」，這樣只報 2 筆（`Chang, Y-H.`／`Chen, J-W.`）。

**誤判方向是危險的那邊**：被誤判成縮寫的 person 會**逃過抑制**，假提名照樣存活。

## 第二版：修好判準，但整個方向是範疇錯誤

使用者指出「人名是靈活的，最後的判斷需要 AI agent 而不是程式」，並指向 2026-08-13 的
lab meeting 簡報。讀完之後，第二版當場被自己的驗證打死：

```
literal    'Shieh, Grace S.'        given = {grace, s}          → 判為完整名
authorized 'Shwu-Rong Grace Shieh'  given = {shwu, rong, grace} → 完整名
tokens 不符 ⇒ 抑制（不提名）
```

而簡報記載這個案例**已經付過代價**：「查證前，謝叔蓉的兩種名字被當成兩個人建了檔。
合併後她的論文歸回 PI，有 PI 的論文從 79 篇修正為 **81 篇**。」

**我的規則會重新製造一個已經被修掉的錯。**

## 為什麼整條路都是錯的

簡報第 2 頁的量測是決定性的：

| 配對 | Jaccard |
|---|---|
| **同一人**：`Grace S. Shieh` ／ `Shwu-Rong Grace Shieh` | **0.40** |
| **不同人**：`Shu-Chun Chen` ／ `Chun-houh Chen` | **0.50** |

**不同人的相似度比同一人高。** 任何字串謂詞——不論多精巧——都站在這條線的錯誤一側。

第二個論證：**沒有一個「正確字串」可以比**（所方正式名稱是單數 `Institute of Statistical
Science`，ScienceDirect 印的是複數，兩種都真實存在於文獻裡）。

第三個是哲學的：簡報引 Kripke，**名字指涉誰由因果來歷決定，不由描述最像決定**。字串謂詞
是純粹的描述論。

而簡報第 12 頁把設計寫進了函數簽章：`key = ` **`normalize`** `(name)`，**底線標示需要 AI
判斷的函數**；`normalize` 不只看名字，而是查作品特性、共同作者、機構字串。

## 產出一：規則（PR #390）

`.claude/rules/identity-is-judged-not-matched.md`。要點：

- 身分判定**不得由字串謂詞單獨做出**，必須引用名字以外的證據
- **提名是 recall，判定是 precision**：`LooseNameKey` 檔頭本來就寫著「鍵只用於配對，
  永不用於判定」。所以**提名過寬不是缺陷**——收窄它會把「這些請判斷」變成「什麼都沒有」，
  而靜默是 `lossless-intake` 列為最糟的失敗形式
- 判準：一個改動若讓某個配對**不再出現在任何人眼前**，它動的是 recall，要以
  「會不會讓真配對永久消失」來審

同一個 PR 把 CLAUDE.md 的 Rules 段從**描述性**改成**規範性**（「所有實踐都必須遵守」），
並補三條執行語意：規則勝過臨場判斷／覺得錯了就顯式改規則不要靜默偏離／封閉列舉不得類推。

## 產出二：#383 撤回，#386 升為承重（PR #391、本輪實作）

#383 的修法整個撤回。那 32 列的真正缺口**不在提名層，在判定層不存在**——今天是人用眼睛掃
清單，而判定所需的證據（DOI → 該作者位登記機構 → 共同作者 → 庫內出處）在前一輪已經手動
做成功過，**攔下了 15 筆純靠名字會做錯的合併**。

於是 #386（共用 literal 沒有 per-work 歸戶路徑）從 side gap 變成主線：**查得出來，寫不進去。**

實測：literal「C-H Chen」的 15 列，逐篇查該作者位在論文上登記的機構後分屬**至少 6 個不同
機構**（統計所 2、慈濟 3、長庚 2、UC Davis 2、UCSD 2、其餘各 1）。歧義的兩條既有出口
（補 alias、`add-person`）都是**全庫**動作，對共用 literal 會誤傷其餘列。

### 設計：讓判定成為一個不同的型別

```
提名（recall）    ResolutionCandidate { …, tier }        ← 字串鍵產生
判定（precision） JudgedPairing       { …, judgement }   ← 名字以外的證據
                                        ↑ 無 tier、無 restsOn
```

兩者 conform 同一個 `AuthorPairing` 協定（citekey／authorIndex／literal／personKey），
`apply` 泛型化——**寫入邏輯與三道守衛逐字不變**。

**型別保證自動保住**：`AmbiguousMatch` 的欄位是 `personKeys`（**複數**）——歧義的
「是哪一個人」尚未決定，所以單數欄位在那個型別上不存在，它結構上 conform 不了。既有的
「兩個欄位而非 sum type」設計靠同一件事讓「不小心 apply 一個歧義」寫不出來；本協定沿用它。

### 一個被反轉的決策：判定要不要「傳染」

第一版主張判定的 rule **不進** `confirmedByLiteral`，怕一次正確判定把其餘 occurrence 升成
可 apply 候選。使用者說「**提名沒關係，但決定還是要交給 AI**」——查證後發現那個風險
**已由既有機制擋住**：CLI 裸 `--apply` 對任何非 exact 層一律拒絕（該閘的註解記著它是實測
「一發寫 5 筆 initials verdict、**4 筆錯配**」之後加的），MCP 面要求 per-id 顯式指名。

而傳染**反而更好**：一次判定把同 literal 在全庫的每一處翻出來、附帶血統揭露，交 AI 逐列
決定。不傳染的話那些 occurrence 永遠停在歧義桶，**沒有任何東西指出「其中一列已經有人判過
了」**。

實作階段確認：傳染**零 production 改動**就成立——既有 `confirmedByLiteral` 本來就收任何
work-holder verdict 而不看 rule。

### rule 字面值：`author-judged-per-work`

**刻意不用 `author-name-` 前綴**——那個前綴的意思是「靠作者名字比對出來的」，而判定不是。
沿用會讓校準統計把兩種完全不同的證據混在一起。一條測試專門釘住這個意圖。

### 實作中被抓到的兩件事

**一、我違反了自己寫的 spec。** 把 service 寫成「任一筆不合法即整體 abort」，但 spec
requirement 明文 `SHALL NOT abort the remaining pairings`。正確切法：**輸入語法錯 → abort**
（缺 `=`／非三段形／重複 id／空白 judgement／person 不存在）；**store 狀態不符 → skip 並
具名**（work 不存在／索引越界／位置已歸戶）。依 CLAUDE.md 新增的「規則勝過臨場判斷」，
改實作不改 spec。

**二、既有計數守衛抓到新呼叫點。** `testEveryCLIServiceConstructionPassesRegistryKey` 因第
19 處 `AkashicService` 建構而紅，訊息直接指示要確認 `key: store.key`（#220 HIGH：keyless 會
分岔出第二份 index）。人工清單會與程式分岔，計數守衛不會。

## 產出三：兩張順帶開的 issue

- **#388** —— `resolve-people` 的清單顯示上限 `rows = 50` 寫死、無旋鈕。它**已實際阻礙**
  本輪量測三次（每次都靠暫改常數再還原才拿到完整清單）。
- **#389** —— **4 筆 person 的姓名被切壞且直接印進 `.bib`**：`Yang, Hwai-I`（楊懷壹）變成
  `Yang, Hwai-, I`，而 biblatex 的逗號語法是 `Last, Jr, First`，三段形會把 `I` 當名、
  `Hwai-` 當後綴；另有 `Ablm, Yen-Tsung Huang`（證照後綴被當姓，同時是重複 person）。

兩張都是量測 authorized name 時**順帶撈出來**的，與當時的主題無關但不丟棄。

## 產出四：`--refute` —— 判定的鏡像缺口（同日稍晚）

實作完 `--judge` 之後開始查那 69 筆歧義，第一批就撞到牆：

```
$ akashic resolve-people --refute ...   # 當時還不存在，先試既有的
$ akashic resolve-people --reject 'chen2013peptide:0:chun-houh-chen'
Error: 找不到：候選 id「chen2013peptide:0:chun-houh-chen」（先不帶 apply 列出候選）
```

**既有 `--reject` 只吃 resolver 提名出來的候選，歧義列一律 notFound。** 而
`akashic-person-verify` 明寫 reject 是三個出口之一（「查過了不是他」）——那個出口對歧義列
**從來沒有通過**。

#386 解掉了「說**是**他」，「說**不是**他」還是不通。而對共用 literal 來說，**否定才是
絕大多數的答案**：69 筆逐篇查該作者位在論文上登記的機構後，**22 筆已確定答案不在候選裡**
（UC Davis／UCSD／長庚／慈濟／馬偕／北榮／國衛院…）。

### 設計：否決是判定的鏡像，不是 reject 的變體

同一條解析與守衛，只差 `VerdictKind` 與「否決不動 entry」。`judgeAuthorships` 因此泛化為
收 kind，兩條路共用全部邏輯。

**「該位置已歸戶」對否決不是障礙**——否決不動 entry，已歸戶的位置仍可留下「另一個候選
不是他」的判定。literal 改由該位置的既有 verdict 取；取不到就略過**不猜**。

### 首批成果

39 個 (列, 候選) 配對、涵蓋 22 列，每筆 verdict 都帶逐字的機構證據，例如：

> 該作者位在論文上登記的機構是「Department of Otolaryngology, Chang Gung Memorial
> Hospital-Kaohsiung M」，不是中研院統計所（OpenAlex raw_affiliation_strings，2026-08-20 查證）

### 一個查證方法上的修正

第一版分類器把 `institutions` 與 `raw_affiliation_strings` 混在一起當機構證據，結果誤判
一筆：`yushuanshiau1996observation[3]` 的 `institutions` 含統計所，但 `raw` 說的是
「Department of Radiology, National Taiwan University Hospital」。

**`raw_affiliation_strings` 是逐作者的，`institutions` 可能是論文全體的。** 有 raw 就只信
raw——實測 55 筆有機構資料的列**全部**都有 raw，所以這個修正沒有覆蓋損失。

（該筆後來查明是真的雙隸屬，兩個字串都在 raw 裡——所以不是污染，但判準仍該以 raw 為準。）

## 方法論教訓（跨 session 值得記）

**「判準還不夠精確」是一個會無限迭代的錯誤診斷**，而每一輪迭代都看起來像進步。兩版判準、
兩次都錯、錯法不同——共同點是兩輪都在同一個範疇裡打轉（找更好的謂詞），而錯誤在範疇本身。

下次遇到 `literal → key` 的問題，先問**「這是機械查表還是 AI 判斷」**，不要先想 predicate。
