# 文獻資料更新一律從上游 store 開始——交付層只投影，不修正

使用者 2026-09-22（+08:00）定調：「你可以在 `.claude/rules` 加入一個規定，就是要更新文獻的話都必須要從上游開始更新，這可能也要做成 akashic library 的規定」。

適用於**任何消費 Akashic store 資料的下游 pipeline、交付物、匯出格式**——本 repo 的 `export-tables`／`export-bib`／MCP／CLI 讀取面產出的東西，以及任何外部消費端 repo 再加工這些產出物的第二層產物（JSON／CSV／SQLite／`.bib` 等）。

**本檔有兩份鏡像**（作用半徑不同、讀不到彼此）：使用者的全域規則目錄（另一個私有 repo，每個專案都載入）的 `rules/common-akashic-upstream-first.md`，與 `plugin/rules/` 的 plugin 副本（未落地）。本檔是正本；三份的同步義務記在 #691，細節見文末〈注入到消費端〉。

不適用於**讀取面的呈現細節**（欄位排版、截斷、消毒）——那由 `entity-backlink-completeness` 的「一個讀取面只有一條實作路徑」管；本規則管的是**事實本身**該修在哪，不是格式該長什麼樣。

## 規則

1. **文獻資料（work／person／organization／venue 的欄位、歸戶、關係）的錯誤，修在 Akashic store，不修在匯出產物、交付物、下游 pipeline 的相容層。**
2. **交付層允許做的只有投影**：選欄、改名、剝除隱私欄位、加標記欄（如 evidence／provenance）。**投影不得改變上游資料的事實陳述**——把「已離職」投影成「現職」不是選欄，是改寫事實。標記欄只能由 store 已有的值算出；store 沒有的事實（例如只寫在 pipeline 內部 note 的離職日期）不是標記，是第 1 條要在上游修的東西。
3. **上游暫時修不了時**（工具缺口、要等 issue 落地），交付層可以**遮蔽**（置空、不宣稱），但必須同時滿足兩件事：
   - **(a)** 在上游（Akashic-Library）開 issue，並在遮蔽處註明 issue 號；Akashic-Library 是公開 repo，issue 文字用角色描述，不寫消費端的私有 repo 名與非公開人士的姓名；
   - **(b)** 遮蔽是暫時的，上游修好後移除——不是永久留著的相容層（同 `no-compat-fallback` 對相容路徑的既有要求：留著的路徑要有退場條件，不是「之後再說」）。
4. **判準**：這個改動是不是「這個值本來就對，只是要不要顯示、叫什麼名字（欄位名、檔名，不是實體的顯示名）、放不放進這次交付」——是，才算投影；牽涉「這件事是不是真的」，就不是投影，是修正，修正只能在上游做。「值本來就對」由上游的查證決定，不由交付層自行認定。

## 為什麼

同一件事在交付層修，只對**那一份**產物有效；store 沒修，下一個消費者（另一條 view、`export-bib`、任何統計計數）照樣拿到錯的——而且每次個別繞過都看起來很合理，這正是安靜失敗的形狀（`replace-endnote-and-zotero` 第 4 條記過同一個病：「這個功能我回去用 Zotero 做」一旦變成常態，就是取代失敗的樣子）。

投影與修正的界線容易被「反正使用者已經看過乾跑報告、同意了」模糊掉——但同意能決定的是要不要做、做哪一批，不能讓一個錯的事實變成對的（`plugin/rules/source-of-truth-over-consent.md` 對寫入面的同一句話，這裡是它在**交付**面的鏡像）。

## 觸發過的實例

**2026-09-22 · 一個下游視覺化專案（私有 repo）的交付 R2**：交付一份給下游視覺化用的 JSON／CSV／SQLite，verify 抓到三個資料問題——一位已離職的博士後被標成 `current`（JSON 給了一段開放式任期）、person 名字用 key 頂替、同一個 DOI 的兩筆記錄未消歧（twin）。R2 的第一輪修法是在**交付層**加 `membership`／`evidence` 欄位與明示排除清單把這幾筆遮住，之後才回頭在 Akashic-Library 開 issue 修上游。順序倒了：這三個問題的根都在上游（store 的資料，或把它匯出的工具），不是投影選擇——`membership` 欄承載了 store 沒有的更正，排除清單把錯的記錄藏起來而不是修掉。離職日期原本只寫在 pipeline 內部的 `note` 欄，而 JSON 格式連這個 `note` 欄都沒帶，於是同一批交付物裡 CSV／SQLite 藏著更正、JSON 完全沒有，三種輸出格式彼此不一致，且沒有一個是「對的」——只是「錯得不一樣」。

## 誠實邊界

本規則管的是**設計與實作時的紀律**，不是自動偵測——沒有機械檢查能判斷一次投影是不是偷偷改了事實陳述，這件事仍要靠審查（跨模型 verify、`akashic-verify-person`／`akashic-verify-venue` 的判定紀律）抓，那次交付正是被 verify 抓到才回頭修的。

## 跟其他規則的關係

- `plugin/rules/source-of-truth-over-consent.md`（plugin 隨附；`.claude/rules/` 底下的規則在 plugin 安裝處讀不到——本檔的 plugin 副本尚未落地，見下）：那條管**寫入 store 時**依據是什麼；本條管**store 已經對了之後，下游不得再改**。兩條合起來涵蓋「寫對」與「別在下游把它寫錯」。
- `replace-endnote-and-zotero`：本規則第 3 條的「遮蔽必須暫時、上游修好即移除、要開 issue」是它第 4 條「能力缺口要記 issue，不能靠繞過帶過」的同一個立場，套用在交付層。
- `no-compat-fallback`：第 3 條的退場要求引用它對相容路徑的既有紀律——遮蔽本質上就是一條臨時的相容路徑。
- 全域 `common-spec-prose-enumeration`：本檔的判準（第 4 條）是一句可獨立驗證的性質（「事實 vs 呈現」），不是拿本檔的觸發實例去類推——單一實例不構成封閉列舉，新的邊界情形回到判準本身判斷，不回到「那次交付長什麼樣」。

## 注入到消費端

三份描述的同步與 plugin 副本的落地記在 **#691**（那裡有 `### Blocking`）；這一節只記兩份鏡像的形狀與它們和本檔的差異。

**plugin 副本未落地**：要放 `plugin/rules/upstream-first-bibliographic-updates.md`（隨 `akashic-mcp` plugin 安裝到消費端 repo，由 skill 以相對路徑引用——見 `CLAUDE.md`〈plugin 另有自己的規則目錄〉段）。卡在 `akashic-guards rule-coverage`：`plugins/akashic-discovery/rules` 是指向 `plugin/rules` 的 symlink，所以 `plugins/akashic-discovery/skills/` 底下**每一個** skill 的 SKILL.md 都要加一行引用，而那個目錄在 #617 那條工作線手上（#642 曾在其中一個檔加過引用，所以這不是排他鎖，是協調——等 #617 釋出或使用者同意）。在那之前，本檔只約束在本 repo 工作的人與模型，以及載入全域鏡像的 session。

**全域鏡像**：使用者的全域規則目錄（另一個私有 repo）的 `rules/common-akashic-upstream-first.md`，每個專案都載入。2026-09-29 本機已 commit 並生效，**尚未推上那個 repo 的 remote**——其他機器在推送之前看不到（#691）。形狀比照同目錄的 mail 規則鏡像：開頭寫明正本是本檔、衝突時以本檔為準。

**規則段（第 1–4 條）與本檔逐字相同**，唯一的差異是第 3 條 (b) 括號裡去掉「同 `no-compat-fallback` 對相容路徑的既有要求：」這個引用（那條規則在消費端讀不到），它要求的內容（留著的路徑要有退場條件）保留。其餘刻意的差異：

- 鏡像沒有本檔的適用範圍細節（`export-tables` 等本 repo 的面）與「不適用：呈現細節」那一句——鏡像的讀者在消費端 repo，那些面不在他手上。
- 鏡像沒有〈誠實邊界〉、〈跟其他規則的關係〉、〈注入到消費端〉三段；〈為什麼〉與觸發實例是縮寫，最後一句（同意不能授權改寫事實）是本檔〈為什麼〉第二段的縮寫。

**改本檔的規則段時要同一個變更裡改鏡像**；做不到時（沒有另一個 repo 的存取範圍），在 #691 記下改了哪一條、哪一份還沒跟。兩份描述的是同一件事、作用半徑不同（`no-compat-fallback`〈同一件事只能有一份描述〉的第二類），本 repo 的守衛讀不到另一個 repo，所以沒有機械比對。
