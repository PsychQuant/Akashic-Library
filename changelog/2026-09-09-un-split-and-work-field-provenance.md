# un-split 與 work 欄位的來源：兩張 follow-up 的值域裁決（#513 #517）

兩張都在補「已經做得到的事，卻沒有面把它表達出來」。

## #513 —— un-split

#450 讓拆分的判定持久化到 work 側，於是 un-split 所需的全部資訊自此在 store 內——**但沒有面
把它合回去**。還原只能手改 YAML（合回 N 個作者位、刪掉多出的位置、刪掉那筆記錄，三個動作要
一致），而那是 `replace-endnote-and-zotero` 第 4 條要防的安靜失敗。

`literal-first-then-key` 的整套論證建立在「誤可逆」上，而 split 這一腿在本面之前不可逆。

**它的阻塞是過期的**：`### Blocking` 寫「#450 的 PR merge」，而 #450 早在 2026-09-07 就 closed
——正是 `blocked-issues-must-be-scannable` 記過的「空等」形狀。

### 兩個值域裁決

**① 以值定位，同 value 多筆記錄拒絕不判定。** 同一筆 work 可對同一 literal 拆兩次，那時兩筆
記錄的 `parts` 可能不同，而「哪幾個作者位屬於哪一筆」**store 裡沒有東西說得出來**。形狀取自
`akashic_enrich` 對 DOI 命中 ≥2 筆的既有處置（`ambiguous`）。

**② 還原後刪掉那筆記錄。** 三個理由，最後一個決定性：記錄的存在理由是「`authors` 已經沒有原
literal 了」，還原後證據回到正典位置；留著會點亮 `staleSplitRecords`（一次**合法**的 un-split
製造永久 warning）；而最重要的是——**留著會讓 store 斷言一件假的事**：statement 是「拆為
⟦a⟧ ⟦b⟧」這個關於當前狀態的宣稱，還原後為假。3.325 的立場是讓那種矛盾寫不出來。

### 一處偏離 issue 的 Expected

它寫「`mcp-cli-parity` 兩張表各加一列」。而 `un_split` 是既有 `akashic_resolve_people` 的
**參數**不是新 tool——加列會讓該檔的封閉列舉與**它自己的機械稽核**對不上。改成在既有那列的
散文補一段。

## #517 —— work 欄位的來源，與「查過了、沒有」

#458 的兩個 residue 是同一個洞的兩面，issue 要求一次裁決。

### ① 前綴是量出來的，不是風格

`Entry.fields` 的鍵由來源決定（`lossless-intake`），所以它**必然**與 reference 保留的欄位名
撞上。實測 live store：**40 種鍵，其中 `doi` 3 筆、`isbn` 3 筆同名**。裸鍵名之下
「`field: doi` 指結構化清單還是 `fields["doi"]`」**今天就已經是歧義**——不是未來風險。

前綴（`fields.<鍵名>`）讓歧義寫不出來，而不是靠一份會漏的白名單。本 repo 已為白名單付過兩次
代價（`PATH_ROOTS`、`trigger-coverage` 的 `DATA`）。

### ② 負結果：value 缺席 ＋ retrieval

| 欄位 | 帶 value | 有這個欄位 | 讀法 |
|---|---|---|---|
| `doi` | 是 | 是 | 那個號來自這裡 |
| `doi` | 否 | 是 | 在這裡被查過，這是它給的 |
| `doi` | 否 | **否** | **查過了，沒有** |
| `doi` | 是 | 否 | 拒絕 |

第三列在此之前**寫不出來**：`doi` 的 reference 必須帶 value，而 value 必須是清單成員——清單
空的時候沒有任何合法寫法。於是「沒查」與「查了沒有」在 store 裡是同一個觀察。

**kind 必須是 retrieval**：一次查找的 url 與日期**沒有別的地方記**（`sources/index.jsonl` 記
origin／retrieved／media-type，**不記 url**）。

**issue 列的另一條路（空 `rests-on` 的一階 judgement）在結構上就寫不出來**——這些欄位都不在
`firstOrderRulingFields`，平面 init 已經擋下。那是好事：那個集合的成員資格是「原文逐字保存於
value 就是證據」，而負結果的 value 是空的。附帶好處是走 judgement 的必然帶著真的 digest，
**離線來源（紙本掃描件，沒有 url）因此也表達得出來**。

### ③ `sourceDigest` 從只回顯改成寫入

三欄齊備（digest ＋ url ＋ retrieved）時每個補進去的欄位一筆 retrieval，與被補的值**同一次
寫入**。只給 digest 仍只回顯，理由具名，不靜默。

**kind 必然是 retrieval 不是 judgement**，而那不只是形狀偏好：judgement 是 AI 編輯欄的產出物，
**一個決定論式的補值面不該發出判定**（`two-kinds-of-edits`）。

### normative spec 有一條直接牴觸，一併修

`provenance-reference` 原本寫「reference 指名記錄沒有的欄位 → SHALL reject」，而負結果的整個
表達法就是那件事。拆成兩個 Scenario ＋ 一張四格真值表。

**它沒有走 spectra 流程**：決定已由使用者拍板，而讓 spec 繼續斷言一件實作已不遵守的事，正是
本 change 自己在修的那個病。

## 一則自己踩到的錯

改 `entity-backlink-completeness` 時把散文塞進**表格儲存格裡**，把第 15 列拆成九行——表還在
（守衛只數列號 `^| N |`），渲染壞了。同一格裡還留著一句這次裁決之後為假的話（「這一格的例外
只有 `authors`……`fields.*` 要不要能攜帶來源是另一個問題」）。

守衛全綠而東西是壞的——與本輪反覆記的形狀同一個，只是換到 markdown 結構這一層。

PR #539、#540。
