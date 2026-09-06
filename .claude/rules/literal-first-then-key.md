# 每個 entity reference 都先以 literal 進庫，再經顯式消歧升格為 key

使用者 2026-08-16（+08:00）定調（#304）：「每一個 entity 都應該要先當作 literal 然後
disambiguity 成 key」。同日並裁定終局語意（#303／#304）：「查完＝把所有 literal 都轉成
key，不限於人，而是所有 entity」。

適用於**任何把 entity reference 寫進 store 的路徑**——importer（`import-wos`／
`import-zotero`）、`create-entry`、MCP 寫入 tool、以及未來任何新的寫入面。作用對象是
**二態 ref**（`.key`／`.literal`）所在的邊：現有的封閉列舉第 1（`Entry.authors`）、
第 7（`Person.profile.affiliations`）、第 8（`Organization.parents`）條，以及 #304
審議中要新增的 ref 種類（期刊／學程等）——**新 ref 種類一旦落地即自動受本規則管**。

不適用於**純量欄位**（`fields` 裡的書目字串）——它們是否升格為 ref 由 #304 的判準
裁決；升格前它們不是 reference，本規則不對其發言。

## 規則（生命週期三段，順序不可跳）

1. **進庫時不猜 key。** 來源給的字串以 `.literal` 原樣進庫。匯入端**絕不**自動歸戶——
   即使字串與某個既有 entity 的名字完全相同。寧漏勿誤：漏（literal 待消歧）可逆，
   誤（錯誤歸戶）把兩個身分熔在一起，發現時已經有下游依賴。
2. **literal 是誠實狀態，不是壞掉的 key。** 呈現時照樣顯示（給名字、不給 key），
   讓使用者看得出哪些還沒歸戶——這是 `entity-backlink-completeness` 執行細節 3 的
   既有立場，本規則把它從呈現面擴展到生命週期面。
3. **升格是顯式消歧動作。** literal → key 只經消歧路徑（`resolve-people` 一族、
   divergence 記錄＋judgement、或人工單筆裁決），且升格留下 provenance（resolution
   verdict，#232 的機制）。**不在讀取時自動配對**——讀取面看到 literal 就回報 literal。

**終局（#303 campaign 的完成定義）**：所有 literal 都轉成 key，全 entity 域。
殘留 literal＝查證未完成，不是穩態。campaign 的進度量測即 literal 邊數的趨勢。

### 量測的讀法：拆分使 literal 邊數**上升**，那是進步不是退步（#451）

`split-author`（#443）把一個黏著的 literal（「某人與雷庚玲」）拆成 N 個作者位——1 條 literal
邊變成 N 條。實測（store `32916ba`，2026-08-28）：2029 → 2028 → 拆 4 筆後**淨值上升**。
照上一段的字面讀，趨勢「倒退」了；實際上是**一個合成的假人變成 N 個誠實的未歸戶名字**，
每一個都比原本那一條更接近終局（原本那一條永遠升格不了——沒有一個 person 對應它）。

所以讀這個數字的三個消費端——`akashic doctor` 的 `unresolvedAuthorLiterals`、
`resolve-people` 的 literal 計數表、#443 一族的規模統計——**趨勢要與拆分次數並讀**：
同一期間的拆分數是進步的另一半。

~~**目前只能散文並讀，不能機械並讀**：store 不記得哪些作者位是拆出來的（split 的持久化是
#450 的值域裁決，尚未定案）。~~ → **#450 定案（2026-09-07）：可機械標註**。拆分自此在 work 側
留記錄（`references` 的 `field: authors`，value＝原 literal、statement 列各段），`Entry.splitRecords`
一行就能算出「其中 N 個作者位來自拆分」；把這個數字放進三個消費端的量測輸出是後續工作，本節先記
可行性。**#443 已拆的 4 筆不回填**（原文與理由只在 git 歷史），所以那 4 筆仍只能散文並讀——
機械標註從第 5 筆起。

## 為什麼：兩個方向的失敗不對稱

| 方向 | 失敗模式 | 可逆性 |
|---|---|---|
| literal-first（本規則） | 一批待消歧的積壓（#303 實測：2,123/3,720 邊，57.1%） | **可逆**——隨時可消歧，資訊零損失 |
| 進庫時猜 key | 同名熔合：兩個人共用一筆記錄，著作互相污染 | **不可逆**——發現時下游（backlink、verdict、index）已建在錯的身分上 |

這與 `no-compat-fallback` 記錄的 #241 教訓同構：把身分變成名字的函數（v5(key)）在
「補值」場景是特性、在「新建」場景是缺陷。匯入時自動配對正是「用名字決定身分」——
同一個錯誤換個位置再犯。

第二個論證來自 #300 裁決的六理由第 4 條：`.literal` 的可表達性是**作品側儲存的
決定性論證**——store 能誠實持有「身分尚未確立的 authorship 事實」。若匯入端被允許
猜 key，這個誠實狀態就永遠不會出現，整條論證失去實例。

## 觸發過的實例

- **2026-08-16 · #303**：literal 歸零 campaign 開案時實測 57.1% 的 author 邊是 literal，
  高頻榜首（`Yung-Fong Hsu`×18 等）都是店裡已有記錄的人——證明「進庫不猜」有真實成本
  （積壓），但積壓全數可由 `resolve-people` 一輪收割，成本是暫時的。
- **2026-08-16 · #304**：TIGP 學程連 literal 都不是（模型外散文）——反例證明「先當作
  literal」的前提是**那個 reference 種類存在於模型中**。一般化到期刊（371 個 distinct
  journaltitle）／學程後，它們的初始狀態同樣是 literal，不是直接建 entity 再配對。

## 跟其他 rules 的關係

- `lossless-intake`：管**欄位**進庫不丟；本規則管**reference** 進庫的初始狀態。
  同一個匯入動作兩條都適用：欄位原樣收、ref 以 literal 收。
- `entity-backlink-completeness`：執行細節 3（literal 顯示不冒充 identity）是本規則
  第 2 段的呈現面；本規則補上它的前傳（怎麼進來）與後傳（怎麼離開 literal 態）。
- `no-compat-fallback`：#241 的「推導是補值還是決定身分」判準——本規則第 1 段是
  該判準在匯入面的落地。
- 全域 `common-spec-prose-enumeration`：本規則的適用範圍綁在**二態 ref 所在的邊**
  （封閉列舉的具名條目），不寫成「凡是像 reference 的東西」——純量欄位要不要升格
  是 #304 的裁決，不由本規則類推。
