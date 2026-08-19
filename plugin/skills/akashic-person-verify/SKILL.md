---
name: akashic-person-verify
description: 歸戶查證——判定「這個 literal 作者是不是這個人」並把判定落成 Akashic 的 verdict。給一個未歸戶的作者字串（或 resolve-people 列出的候選／歧義），依標準證據鏈查 Europe PMC 著作軌跡、ORCID employment、OpenAlex 隸屬史、出版商頁逐作者機構綁定，組出 affiliation timeline 與判定建議，經使用者確認後以 akashic_resolve_people 的 apply/reject 寫入 resolution-confirmed／resolution-rejected。當使用者說「查一下這個作者是不是他」「這個名字歸不歸得了戶」「幫我查證這批候選」「這個人是不是所上的人」，或 resolve-people 出現需要人判斷的歧義時使用。與 akashic-bootstrap 的分工：bootstrap 補資料進 store，本 skill 判定身分並記 verdict——查證結論要落地時兩者常接續使用。
---

# 歸戶查證：從 literal 到 verdict

判定「這個 literal 作者字串是不是這個人」，把判定連同證據落成 store 的 verdict。

**預設是查到消歧為止，不是查完就問。** 使用者 2026-08-20 定調：「這些全部都是要繼續查直到消歧異為止……除非真的無法確認才是人來決定」。

所以三個出口的**優先序**是：

1. **證據具決定性 → 直接 apply／reject**，並在報告裡寫出是哪一條證據、以及它為什麼具決定性。
2. **證據不足 → 換一條線繼續查**（下面的來源表不是「跑完四格就交差」的清單，是排到用完為止的順序）。
3. **真的查不出來 → 才交人**，且必須說出**已經排除了什麼**、**卡在哪一步**，並記 divergence（Step 3 第三個出口）。「我查了幾個來源都沒有」不算已排除。

**「絕不自動合併」仍然成立**，它管的是**沒有決定性證據時不得靠相似度硬併**——不是「有決定性證據也要先問」。判準見下方〈什麼算決定性〉。

## 為什麼需要紀律

姓名欄位的資訊量不足以支撐身分判定（實測：同一人的兩種署名 Jaccard 0.40、不同人的兩個名字反而 0.50）。判定要靠名字**以外**的證據，而每個證據來源各有自己的失效模式——見 [references/verification-traps.md](references/verification-traps.md)。查證結論若不落地，下次遇到同一個配對就要整套重查：#232 之後判定有正式載體（verdict＋三態計數），查一次記一次。

## Workflow

### 0. 先看 store 現況

```
akashic_resolve_people（不帶參數）      # 候選（apply 的合法目標——仍須查證＋確認）、歧義（要人判斷）、已否決沉底列、三態計數
akashic_people（query:）               # 找 key／確認實體存在——回 key、aliases、ORCID，不含隸屬與著作
akashic_person（key:）                 # 單人聚合：names / affiliations / 著作（現算）
```

要查證的配對通常來自這裡：candidates 列的 `id`（三段形 `citekey:authorIndex:personKey`——釘 person）就是之後 apply/reject 的把手。**先確認配對還在**——resolver 已排除的（已否決）不會重列。

### 0.5 先查**庫內**的出處訊號（在打任何外部 API 之前）

**實測教訓（2026-08-20）**：24 筆「Chen, Y.-H.」的決定性證據一直在庫裡——那些 entry 帶
`tags: CV import, Yi-Hau Chen`，是從**他本人的 CV** 匯入的。匯入來源本身就斷言了作者身分，
比任何外部姓名比對都強。當時卻先去打了 ORCID 與 OpenAlex。

動外部之前先看這三處：

| 位置 | 看什麼 |
|---|---|
| `Entry.akashic.tags` | 有沒有 `CV import` ＋ 人名、`<某人> publications` 之類的**匯入批次標記** |
| `Entry.provenance` | `zotero_key`／來源檔——同一批匯入的其餘記錄能不能互相佐證 |
| 候選 person 的 `著作數` 與 `verdicts` | 空殼記錄（`⚠ 無任何區辨欄位`、著作 0–1 筆）與有數十筆著作＋既有 verdict 的人，不是同一個量級的候選 |

**但出處訊號的作用域要看準**：`CV import ＋ 某人` 斷言的是「**這篇 entry** 出自那個人的
CV」，**不是**「這篇裡的**每個** literal 都是他」。同一篇裡的其他歧義 literal 是**共同作者**，
本訊號對它們不發言。（實測：29 列帶該 tag，其中 27 列是他本人的署名、2 列是共同作者。）

### 1. 證據鏈（依序查，每一源記 URL＋取得日期）

依序而非並行，因為前一源的結果會縮小後一源的查詢（例如 Europe PMC 找到的 ORCID iD 直接餵給第 2 步）。

**先看領域**：Europe PMC 只涵蓋生醫（統計／數學／CS 期刊實測 0/4 收錄，見 [work-sources.md](../akashic-bootstrap/references/work-sources.md)）——目標領域非生醫時，第 1 源**直接改走 OpenAlex（第 3 源）**，其餘順序不變。

| # | 來源 | 查什麼 | 端點 |
|---|---|---|---|
| 1 | **Europe PMC** | 這個名字的著作軌跡（機構欄隨年份的變化）。**生醫限定**（見上） | `https://www.ebi.ac.uk/europepmc/webservices/rest/search?query=AUTH:"<姓名>"&resultType=core&format=json`——**必帶 `resultType=core`**：預設 lite 不含 authorList／機構欄（見 work-sources.md 的 Europe PMC 段） |
| 2 | **ORCID** | employment（自報、只列現職——見 person-sources.md）。**works 清單預設不是自報**，見下方〈ORCID 的著作清單通常是機器灌的〉 | 見 akashic-bootstrap 的 [person-sources.md](../akashic-bootstrap/references/person-sources.md)（端點、暱稱陷阱、employment 不回填歷史） |
| 3 | **OpenAlex** | 隸屬**史**（依著作聚合的 institution 時間軸——ORCID 缺歷史時的主要救援） | `https://api.openalex.org/authors?search=<姓名>`；機構過濾用 institution ID 不用字串（見 traps） |
| 4 | **出版商頁** | 逐作者機構綁定（破 Crossref 扁平陣列錯位的唯一辦法） | 論文 DOI 落地頁；同團隊姊妹作可佐證。headless 抓取常 403（ScienceDirect 實測全滅）——**不要反覆重試，改真瀏覽器**（safari-browser；見 work-sources.md 的出版商頁段） |

### 什麼算「決定性」（封閉列舉——現有 3 類，不得依性質相似類推第 4 類）

只有下列三類單獨足以支撐 apply。其餘一律是**佐證**，要與其中之一同時成立才算數。

| # | 決定性證據 | 為什麼 |
|---|---|---|
| 1 | **庫內出處**：該 entry 帶指名某人的匯入批次標記（`CV import ＋ 人名`），且該 literal 是**那個人的署名寫法** | 匯入來源本身就斷言了作者身分，不經任何姓名比對 |
| 2 | **論文自己登記的機構**與該候選的隸屬時間窗相符，且其餘候選的機構**不符** | 機構字串來自論文，**不受作者實體合併污染**——見下 |
| 3 | **ORCID works 中 `source` 為本人**的條目，標題與該 work 相符 | 那才是本人簽署過的 |

反面（**不足以**單獨支撐 apply，即使看起來很強）：標題相似度、共同作者重疊、期刊領域相符、
OpenAlex 把某個 ORCID 掛在該作者位上。

### 兩則來源可靠性事實（2026-08-20 實測，會改變你怎麼讀證據）

**ORCID 的著作清單通常是機器灌的，不是自報。** 逐筆檢查
`work-summary[].source.source-name.value`：

```
陳君厚 0000-0003-0899-7477 → Scopus 64、Crossref 10、本人 0
程毅豪 0000-0003-4038-9439 → Scopus 71、本人 20、Crossref 14、MDPI 1
```

Scopus／Crossref 那些條目是**按名字做的消歧結果**——拿它去驗另一個按名字做的消歧，
**兩邊會一起錯**，而看起來像互相印證。只有 `source` 是本人姓名的條目算自報。

**OpenAlex 的作者實體會把 CJK 縮寫名過度合併。** 實測：17 筆「C-H Chen」全部被掛上
陳君厚的 ORCID；改看**該作者位的機構**後，只有 **2 筆**真的在中研院，其餘 15 筆分屬慈濟、
長庚、馬偕、UC Davis、國衛院、UCSD、陸軍軍醫大學、北榮、北醫、高醫——是完全不同的人。

所以**逐篇的機構（`authorships[i].institutions` 與 `raw_affiliation_strings`）是可信的，
而作者實體上掛的 ORCID 不是**：前者來自論文，後者來自 OpenAlex 自己的消歧。

實用查法（有 DOI 時最快）：

```
https://api.openalex.org/works/doi:<DOI>?mailto=<你的信箱>
→ authorships[<該作者位的索引>].institutions / .raw_affiliation_strings
```

⚠ 用索引取之前先驗**位置沒錯位**：該位置的作者名，其「姓＋首字母」必須與 literal 相同。

**什麼時候可以停**：判定所需的是「足以區分候選」的證據，不是全部四源。至少兩源**各自回傳非空證據**、相互一致且無反證 → 可以組 timeline 了——空回應沒有反證能力，不計入「一致」（Europe PMC 對非生醫領域結構性空手，正是這種假一致的來源）；有衝突或歧義（同名兩人）→ 繼續往下查到能區分為止。

**「一致」有一個結構性假象要防**：store 只列一個候選 ≠ 世界上只有一個同名者——人物庫還沒記錄第二個人時，resolver 的歧義偵測不會觸發（bootstrap 有同一條警告）；而 AUTH 搜尋的結果也可能把同名者的著作混成同一條軌跡（CJK 姓名碰撞面實測：93/724 個「姓＋首字母」鍵對到 2+ 人）。兩源在**混同的軌跡**上照樣「一致且無反證」。timeline 出現不連貫的領域／機構／地理跳躍時，當歧義處理——不要硬拼成一條線。

### 2. 組 affiliation timeline

把各源的機構＋時間窗排成一條線，標出每段的來源：

```
2020–2022  臺大醫技        ← Europe PMC 著作機構欄（3 篇）
2021-07–2024-12  統計所博後  ← ORCID employment＋Europe PMC 8 篇交叉
2025–      聯合醫事檢驗所    ← ORCID employment（現職）
```

**快照與歷史對不上不是矛盾**——名冊是快照、出版品是歷史（離職者結構性不在名冊；見 traps）。timeline 的作用正是把兩者放在同一條時間軸上讓判定有據。

### 3. 判定建議 → 使用者確認 → 落 verdict

查證報告的形狀（給使用者裁決用；仿 bootstrap 乾跑報告「每列帶判定依據」的紀律）：

1. affiliation timeline（Step 2 的產物）
2. 判定建議＋依據（「timeline 與 work 的年份／機構相符，建議 confirm」）
3. **逐來源證據清單**——每一源一列：URL＋取得日期＋它支撐 timeline 的哪一段。
   查證結果只留在對話裡就會蒸發（下次同一配對整套重查）；這份清單是「查一次
   記一次」在報告層的落地形式

給出報告，然後**問使用者**。動手寫入前先確認 store 有退路（`git status` 乾淨或先 commit）——批次寫入沒有內建復原（理由見 bootstrap 的對等段落，不複製）。確認後：

```
akashic_resolve_people apply:["<citekey>:<index>:<personKey>", …]   # 確認歸戶——同動作寫 confirmed（rule 依 tier 分開記）
akashic_resolve_people reject:["<citekey>:<index>:<personKey>", …]  # 查過了不是他——寫 rejected，entry 不動
```

- id 用**列表給的三段形**（#303 起釘 person——提名改指時顯式拒絕；不要手拼）
- apply 與 reject **可同一次呼叫**（#272 起兩段式：reject 腿先完整提交、apply 腿在新快照重解析、按腿回報）；CLI 面維持分兩次
- reject 之後該配對不再被提名；**同 literal 在別的 entry 是另一次觀察**，照提、照查
- **第三個出口——查不出來**：證據不足以判定時，用 `akashic_record_divergence` 把進度落地（question＝這個配對的同一性問題、candidates＝兩造、rests_on＝已蒐集的 URL＋取得日期）再停手。pending 是現算的缺席、什麼都不記；divergence 才是「查過什麼、查到哪、為何停」的載體，下次接手從那裡續查
- verdict 需要 store format ≥ 8；format 不足時 reject 會硬擋指路、apply 照常歸戶但跳過 verdict 並明說（**不必預查 format**——兩個失敗模式都會自己說話，直接動手即可）
- 三態計數（confirmed／rejected／pending）從 verdict 現算——**只報計數不報比率**，pending（還沒查的）永遠可見

查證過程取得的**新事實**（ORCID iD、隸屬任期、異名）不屬於 verdict——那是補資料，交給 [akashic-bootstrap](../akashic-bootstrap/SKILL.md) 寫進 person 記錄（含 provenance reference），兩個 skill 常接續使用。

## 邊界

- **歧義列（同 literal 對到 2+ person）不可 apply**。出口（#303 R2/R3 定案）：**補區辨欄位不會改變提名**（resolver 只比 names——ORCID／隸屬是給你判斷用的）。查證確定歸屬後：(a) 是清單中某人 → 把該寫法補成其 **variant alias 並帶 provenance reference** → 該列升 exact 候選 → 顯式 apply；(b) 是**第三個人** → `add-person` 以該寫法為 name 建檔 → exact 單命中優先於寬鬆碰撞 → 顯式 apply。⚠ alias 補寫用 `update_person` 時 `names` 是**整組替換**——先讀出現有 names、附加後整組回寫，直接送單一 alias 會刪光其他名字。
  **⚠ 補 alias 是全庫動作，作用面比你查證過的那一批大**：它會把**所有**正規化後相同的寫法
  一起升成 exact。改完必須重跑 `resolve_people` 並**逐筆解釋歧義集合的每一個增減**——
  實測（2026-08-20）補兩個 alias 後歧義少了 28 筆而非預期的 27，多出來的那筆是第三種拼法
  （無句點的「Y-H Chen」）落在**另一個人**身上，靠 DOI→機構查出來後 `reject` 掉。
  「數字往好的方向動」不等於「動對了」
- **一個 literal 由多個真人共用時，上面的 (a)／(b) 都不適用**——alias 是全庫的，會把其他人
  的列一起誤升。實測「C-H Chen」15 列分屬至少 6 個不同機構的人。目前**沒有 per-work 的歸戶
  路徑**（追蹤：Akashic-Library#386）；在它出現之前，這類配對查證完成後**只記錄結論、不寫入**
- **配對不在 candidates 列時沒有 apply 把手**——同上：先讓配對能以 exact 成為候選（補 alias 或建檔），重跑 resolve 再 apply
- **查不出來是合法結果**。「證據不足以判定」就說證據不足，讓配對留在 pending **並記 divergence**（Step 3 的第三個出口）——pending 可見是設計，不是待消滅的數字
- **承重頁面要存檔**：判定所依據的網頁內容存進 `sources/`（content-addressed）、經 bootstrap 寫入 person 的 `references`——寫法依 [writing-to-the-store.md](../akashic-bootstrap/references/writing-to-the-store.md)。非承重的佐證列 URL 即可。（verdict **刻意**不攜 rests-on——設計裁決見 Akashic-Library#280：已判定的證據住 person `references`、未判定的住 divergence `restsOn`，兩載體依生命週期分工）
