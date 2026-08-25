# 兩席終於跑起來，第一件事就是找到我一小時前種下的資料損失

2026-08-25 下午。`logic` 與 `security` 兩個 verify lens 在前兩輪都因 API 中斷未完成
（0/2）。這一輪 **3/3 全部回報**——三條已修，兩條記為未修。

## 為什麼這輪跑得起來

前兩輪失敗的**不是模型，是我的 prompt**。我叫 agent 去讀 `CLAUDE.md` 與
`.claude/rules/*.md`——那是這個 repo 最大的檔案，sonnet 一讀就進 compact 迴圈。
第一輪五席全滅、燒 3.7M token 換零產出；第二輪改善後仍死兩席。

這輪改三件事：**只跑 3 席**（窄 fan-out，依 doctrine 可用 opus 的大 context）、
**明令禁讀那些檔**（規則內容直接摘進 prompt——它本來就在我的 context 裡）、
**diff 先切到各席真正管的檔案**（1013 ＋ 840 行，可整份讀）。

## 找到的第一件事：型別在中途降級成字串

```swift
struct VenuePlan { var values: [String] }        // ← 只存正規形
v.issn = plan.values.compactMap(ISSN.init)        // ← ISSN.init 把 medium 設 nil
```

`[ISSN]` → `[String]` → `[ISSN]` 的往返兩端型別相同，**中間那一段裝不下 medium**。

兩層損失：本輪剛從括號註記解析出來的 medium 在寫入時蒸發；而 `merged` 的種子是
venue **既有的** `issn`，所以**磁碟上已經有的 qualifier 也被壓掉**。

也就是說：我一小時前逐筆還原的那 9 個 qualifier，**任何一次碰到那 5 個 venue 的
`--apply` 都會刪除它們**。而它不出現在 blockers、skipped、`discardedAnnotations`
任何一處——因為 `VenuePlan` 根本沒有 qualifier 的位置可以回報。

修法是讓 plan 直接帶 `[ISSN]`，`values` 降為現算的顯示用。

## CRITICAL：漏掉的檔在同一次 run 的下一行就被 quarantine

`upgradingIdentifierShape` 是純字面比對：頂格 `issn:` ＋ 頂格 `- `。以下每一種都是
**合法 YAML、載入面照吃**，但升級一律認不出：

- 縮排序列 `  - 1234-5679`（yq、Prettier、多數編輯器的 YAML 格式化都輸出這種）
- flow 序列 `issn: [0033-3123, 1860-0980]`
- key 與元素之間有空行
- 混合形狀（第一個元素已是 `- value:` 帶 `qualifier:` 續行 → 續行不是 `- ` → **其後全漏**）
- CRLF（`"issn:\r" != "issn:"`）

而漏掉之後**不是沒事**：緊接著的 `store.load()` 對裸純量元素直接拒讀 → 整檔
quarantine → 那個 venue 從 `load.venues` 消失，報告卻說一切正常，甚至可能印出
誤導的「venue「X」不存在——ISSN 無處可放」。

**對照組就在隔壁**：`AuthorizedNameMigration.run` 對非空 `quarantined` 直接拒跑，
理由逐字是「本工具**看不見**它們」。同一個 store、同一個 load、相反的紀律。現已比照。

可達性不是假設：#394 自己的 parity 裁決寫明識別碼「沒有任何面寫得進結構化欄位……
唯一的路是手改 YAML」——而手寫 YAML 正是縮排序列最常出現的地方。

## HIGH：`p.changes` 未經 displaySafe

那些字串含 `entry.fields[key]` 的**原值**，而 `fields` 是 `lossless-intake` 的自由字典
（來源給什麼就收什麼）。一個含 ANSI 序列的 Zotero 欄位值可以清掉上一行、改寫使用者
看到的統計，使用者據此下 `--apply`。

同一支命令的其他六處紀律都是對的（都包了 `displaySafe` 或帶具名的
`// display-safe-exempt:`），所以這不是「這支命令不受規範」，是**漏了一格**。

## 尚未修（具名，不假裝不存在）

1. **`ISSNMedium(loose:)` 認不出的 qualifier 在 decode 靜默丟棄。** `withQualifier`
   走 `q.flatMap(ISSNMedium.init(loose:))`，認不出回 `nil`——沒有 diagnostic、沒有
   `invalidField`、沒有任何回報。而 `VenueYAML.encode` 的 canary（`guard back == v`）
   **看不到**它，因為 `Identifier.==` 刻意只比 `normalized`。
   `Online` 正是 Crossref／Zotero 對電子 ISSN 最常見的寫法。
   註記自己寫「認不出回 nil——**不猜**」，而「不猜」被實作成「靜默丟」——那是
   `lossless-intake` 執行細節 3 具名為最糟的形式。
2. **pre-flight 沒有模擬 `writeVenue` 的其他三道 throw 閘**
   （`assertIdentifierReferencesWritable`、format<12 的 venue type 閘、
   `assertNoErrors(v.validate())`）。work 先寫、venue 後寫，venue 那格 throw 之後
   例外穿出 `run()`——ISSN 從兩邊同時消失，**且 report 在印任何東西之前就被丟棄**。
   乾跑無法預告：pre-flight 的事實集合刻意設計成乾跑與 apply 相同，而這三道閘
   不在那個集合裡。

## 一句話

**這三條全部是我今天寫的程式碼**，而第一條違反的正是我今天引用過三次的那條規則
（`lossless-intake`：丟棄必須可見）。跨模型的獨立審查抓到了我自己讀三遍都沒看到的東西
——這與 `common-spec-prose-enumeration` 記過的那個對照事實同型：
**作者自審驗得了「我打算做的有沒有做到」，驗不了「做出來的東西自己有沒有矛盾」。**
