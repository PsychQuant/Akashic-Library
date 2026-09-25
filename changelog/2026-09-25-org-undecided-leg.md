# 2026-09-25 — org-undecided-leg（#643）

resolve-organizations 補上未決（`resolution-undecided`）的寫入面，與 resolve-people／resolve-venues（#619）同契約。

## 新增

- **未決腿**：CLI `resolve-organizations --undecided <id>@<orgKey>=<說明> [--rests-on …]`，MCP `akashic_resolve_organizations` 的 `undecided`／`rests_on`。單獨呼叫，不與 apply／reject 組合。三種 holder 都開：person 的 affiliation、organization 的 parents、work 的團體作者位。
- **id 形狀**（使用者 2026-09-25 裁決）：`<列表的 id>@<orgKey>=<說明>`。列表的 id 逐字取用：`holderKey::literal`，或 work 的 `citekey[i]::literal`。
  - org 的 id 帶 literal，而機構名稱可能含 `=`、`@`。所以解析不以第一個或最後一個 `=` 切：在每個 `@<StoreKey>=` 位置試切，前綴必須恰為這次列表的已知 id，恰一個位置成立才收，零個或多個一律整批拒絕。
  - orgKey 必須是那一列提名的 org。
- **歧義條目可記**：一個 literal 命中 2+ 個 org 時，可以逐個 org 記未決；MCP 的歧義條目自此帶 `id`。
- **揭露**：
  - MCP 候選列帶 `undecidedChecks`（整數）；歧義條目帶 `undecidedChecks`（orgKey 對應次數，只列非零）；頂層帶 `undecidedTotal`（候選配對）與 `ambiguityUndecidedTotal`（歧義條目）。
  - CLI 列表逐列印 `id:`，查過未決的列標「查過未決 N 次」。
- **CLI 篩選式 `--apply` 排除查過未決的候選**：另列排除清單，並指路到 MCP 的逐 id apply。全數排除時零寫入、非零結束。`--reject` 不排除。

## 契約（兩面同）

- 整批拒絕、零寫入：
  - 切不出或切出多個位置；
  - id 重複；
  - 說明空白；
  - org 不存在，或不屬於那一列；
  - digest 形狀不合；
  - store format < 19；
  - `rests_on` 沒有伴隨 `undecided`；
  - 超過上限：一次 200 個 id、20 個 digest、單句 4,096 位元組，或單筆 id 超過「最長列表 id ＋ 256 ＋ 4,096 位元組」；
  - 同一個 id 同時對應 person 與 organization 兩種 holder。
- 逐筆略過並具名：配對已判定，或 citekey 無法唯一定位（#628）。
- 完全相同的記錄已在時回報 `alreadyRecorded`。同一次呼叫的第二個相同記錄報成本次寫入。
- 已知 id（R2 起）：列表那次（帶否決過濾）的列全部認得；不帶否決那次只補配對已判定的列。列表上看得到的 id 一定認得；已否決的配對若仍被產出，走「已判定、逐筆略過」；離開列表而沒有人判定過的舊 id 整批拒絕。

## R1 verify（6 席，38 項：0 HIGH、16 MEDIUM）之後的修正

- **rowID 撞號**：person 與 organization 同 key、同 literal 時兩列的 id 相同，先前併成一列、記錄寫到先解析到的 holder 下。現在整批拒絕並具名（apply／reject 的 id 同樣相撞，目前沒有工具面分得開，出路是改名 person 的 key）
- **已知 id 的來源**：先前只用不帶否決過濾的 resolve，parents 的循環守衛會把否決過的邊當成本輪已接受的邊，擋掉列表上看得到的列——從列表逐字複製的 id 被整批拒絕。改成兩次 resolve 的聯集
- **解析的工作量**：先前每個 `@` 都組一次前綴，60 KB 的輸入跑 14 秒（DA 實測），而說明的 4,096 位元組上限在切完之後才檢查。現在只在前綴長度等於某個已知 id 的位置才組字串；單筆 id 超過「最長列表 id ＋ 256 ＋ 4,096 位元組」在試切之前就擋；上限與 format 在載入全庫之前擋
- **位元組比對**：rowID 比對改成位元組層（Swift `String` 的 `==` 會把 NFC 與 NFD 當成同一列）
- **錯誤訊息**：格式錯與「@ 之前的部分不是這次列表的 id」（那一列可能已歸戶或否決）分開說
- **計數語意**：MCP 的 `undecidedTotal` 先前是全庫所有未決狀態的配對數，與 CLI 四態計數行、resolve-people 的同名欄位不同。改成候選配對的數目；歧義條目另給 `ambiguityUndecidedTotal`，CLI 另印一行
- **逐筆略過的類別**：spec／design 列的「work 不存在」「位置已不是 literal」在 org 腿走不到（那種列不在 resolve 結果裡），改成寫明它們是整批拒絕
- **CLI**：`--undecided` 不接受 `--holder`／`--org`；消毒或截斷改了 id 時該行標出它不能逐字送回
- **已判定的判準**每個 org 只掃一次 references（同 people／venues 的 R3 修正）
- 文件寫明兩個已知邊界：某個 literal 恰為另一個 literal 接上 `@<key>=` 時的切法；記錄是 work 層級、不帶作者位
- CLI 沒有逐 id 的 apply，查過未決的候選在 CLI 上歸戶不了——與 #624 不完全同形，缺口記 #647

## 重構

- people／venues／organizations 三個未決腿共用 `checkUndecidedCall`（上限、format、rests-on）、`checkUndecidedStatement`（說明）與 `undecidedPayload`。
- 列表回程把手 `orgRowID` 收成單一定義，由候選列、歧義條目、未決 id 共用。

## 不在範圍

- 沒有任何 org 命中的 literal：它不在列表上，也沒有被判的 org。
- 撤回未決。
- App 的 org 裁決台（目前不存在）。

## R2 verify（6 席，27 項：0 HIGH、7 MEDIUM）之後的修正

- **已知 id 的來源再收窄**：R1 把不帶否決那次整批併入，DA 用真 binary 重現兩個後果——一筆已否決的 person 列讓列表上唯一的 org 列被當成撞號而整批拒絕；否決另一個配對後離開列表、沒有人判定過的舊 id 仍被收下，寫出任何揭露面都看不到的記錄。現在不帶否決那次只補配對已判定的列；撞號只在兩列都在列表上時成立
- **試切**：說明只在恰一個切法時組，第二個切法成立即停（先前每個成立的切法各複製一次尾段）
- **單筆 id 的長度上限**：orgKey 的餘裕改用這次列表最長的 orgKey（StoreKey 沒有長度上限，先前寫死 256）
- **回應裡的 id 不截斷到 200**：org 的 id 帶整個 literal、orgKey 在尾端，截斷會讓同一歧義條目兩個 org 的結果長得一樣
- **CLI `--undecided` 的 help 與 MCP 描述對齊**：位元組比對、已知邊界、撞號拒絕、work 層級記錄、單筆 id 上限、不接受 `--holder`／`--org`
- CLI `--apply` 全數排除時，排除原因含 citekey 重複的也說出來
- MCP 列表的 note 說明歧義條目的 id 只用於 undecided
- 累積的誠實邊界（`zero-instance-guards` 第 30 列、`UndecidedVerdicts.swift` 的註解）補上 organization 側，#645 擴及 organization
- tasks.md 補上 R1 的更正
- 記為已知邊界、不改：已判定而兩次 resolve 都不產出的列（已 apply、兩條互相成環且都已否決的 parents 邊）以「不是這次列表的 id」整批拒絕；CLI 列表每列多一行 id，會消耗歧義段的位元組預算
