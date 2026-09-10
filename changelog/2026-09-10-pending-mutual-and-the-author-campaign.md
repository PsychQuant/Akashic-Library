# 「兩邊都還沒有記錄」的異寫看得見了，author 域的 literal 因此收斂（#547 #552）

兩張 issue 是同一條線：#547 補上一個扣留機制，讓 campaign 跑得安全；campaign 跑完之後
建出的 3,707 筆 person 讓 #552 的缺口第一次有規模，於是同一天補完。

## #547 —— `bootstrap-people` 的第四段

`bootstrap-people` 原本只扣住「與**既有** person 寬鬆共鍵」的名字。兩個 literal
**互為異寫、而兩邊都還沒有記錄**時，那個判準對兩者都不成立——它會把兩個都建出來。

實測（live store 副本，2026-09-09）：865 → 4,687 筆 person，`Carol Dweck` 變成 **3 筆**
（`dweck-carol-s`／`dweck-c-s`／`dweck-carol-s-2`——`-2` 後綴表示它知道撞了還是分了），
全 3,822 筆只摺疊了 **1** 組異寫。

新增 `BootstrapReport.pendingMutual`：這種群扣住不建檔，`--apply` 與 `--json` 都說出來。

### verify 判 FAIL，而修復過程本身有三件事值得留著

6-AI verify 回 1 blocking ＋ 7 high。修完之後有三件**我自己說錯、被量測或負控推翻**的事：

**一、「巨型群」不存在。** 我把「253 組裡 109 組綁不同姓氏」歸咎於傳遞閉包，並在 doc
comment 寫它造出「十幾個名字、五種姓的巨型群」。把新組取傳遞閉包即還原舊組（同一份
`--json` 輸出，不必重編）：

| | 組數 | 跨姓氏組 | 最大組 |
|---|---:|---:|---:|
| 傳遞閉包 | 253 | 118（46%） | **7** |
| 逐鍵成組 | 285 | 123（43%） | **7** |

沒有巨型群，跨姓比例幾乎沒動。改成逐鍵成組買到的是**每一列的理由與對象一一對應**
（舊的 `sharedKeys` 是「碰到本組 ≥2 個成員的所有鍵」，對七人組等於什麼都沒說），
不是精確度。

**二、真正的成因不能砍。** 123 個跨姓組**全部**只靠 initials 鍵，由 reorder 鍵造成的
跨姓是 **0**——成因是 `LooseNameKey.initialsKeys` 對無逗號名字同時發出「姓在後」與
「姓在前」兩種解讀。而**同一個解讀也在產生真陽性**：`Cai Li` ≡ `Li Cai` 那一組唯一的鍵
是 `initials:li c`，來自 `Li Cai` 的姓在前解讀。收窄會弄丟一個真配對，而那正是中文名
發表順序會變的那一類。追蹤：**#550**（命名慣例的 type 軸——它不是 `WritingSystem`，
`Yung-Fong Hsu` 是 `.latn` 卻走中文慣例）。

**三、兩條「顯示上限」守衛守錯了東西。** 新加的 org 測試斷言「輸出裡沒有『只列前 20』」，
而**負控沒有變紅**：截斷行與 `prefix` 是兩個獨立的地方，只把 `prefix` 改回 20 時
`21 > 50` 為假、截斷行不觸發，輸出**列 20 筆而且一個字都不說**。people 側那條（同一輪
稍早加的）有完全相同的缺陷。兩條都改成斷言「21 筆全部列出」。

`--json` 的 `display-safe-exempt` 前提也是假的：`JSONSerialization` **只涵蓋 C0**，
U+007F／U+0080–U+009F（含 U+009B CSI）／U+202E／U+2028／U+FEFF 原樣通過，而背書它的守衛
用 `byte < 0x20` 判準——在 UTF-8 裡只可能看到 ASCII C0，**紅燈條件不可達**。改成序列化後
以 `UnsafeToEmitScalar`（與 `displaySafe` 同源）改寫危險 scalar，並追蹤字串字面值
（`.prettyPrinted` 在 token 之間送裸換行，一律改寫會產出不合法 JSON）。

### campaign（資料側，在 `~/.akashic` 的 9 個 commit）

工具就緒後跑完 author 域：

| | 開場 | 收尾 |
|---|---:|---:|
| person 記錄 | 865 | **4,572** |
| author literal 邊 | 6,037（77.5%） | **103（1.3%）** |
| distinct literal | 3,884 | **65** |
| `bootstrap-people` candidates | 3,241 | **0** |

依 occurrences 降冪分四批、共判定 **267 列**互為異寫的共鍵組（591 個寫法），每一列都用
**名字以外的證據**：`Chi-Chung Wen` 五種寫法十二篇全與 `yi-hau-chen` 合著；`James J. Chen`
五種寫法共用 `chen-an-tsai`／`kodell`／`young` 的毒理 QSAR 圈。反過來 `Daniel McNeish`
（quant methods）與 `Daniel Muise`（Stanford Screenomics）領域完全不重疊。

**四筆羅馬化跨寫是自動路徑找不到的**（`LooseNameKey` 檔頭明寫那是查表域、刻意不收斂）：
梁庚辰 → `liang-k-c`、雷庚玲 → `lay-keng-ling`、張泰銓 → `chang-tai-chuan`、
蔡宜妙 → `tsai-yi-miau`。

殘留 65 筆是**誠實狀態**：58 筆寬鬆層縮寫形（已正確路由到逐筆查證流程）、3 筆古典文獻
（班固、姚振宗、顏師古——issue #547 (4) 的既有裁決）、4 筆縮寫對。

## #552 —— 縮寫形與引用形是同一類

`AuthorizedNameMigration.propose` 只消去**引用形**。它自己的設計表寫著理由：「引用形是
索引系統的產物，不是他的名字」——而縮寫形是**同一種產物**（期刊作者欄把 `Ulf` 排成
`U.`）。campaign 之後全 store 有 **87** 組卡在 `undecided`。

修法是**擴既有判準，不加啟發式**。`NameForm.isAbbreviation(_:of:)` 切成音節後段數必須
相同，每段要嘛逐字相等、要嘛是對方的單字母首字：

| 配對 | 判定 | 為什麼 |
|---|---|---|
| `Y.-F. Hsu` ／ `Yung-Fong Hsu` | ✅ | 三段對三段 |
| `Hongyun Liu` ／ `H. Y. Liu` | ❌ | 兩段對三段——要先知道哪幾個音節屬同一個 given name |
| `I-Ling Liu` ／ `Ivy Liu` | ❌ | `I-Ling` 是兩個音節，`I` 不是縮寫記號 |

第二列刻意留給人（那是 #550 的軸）；第三列是 `identity-is-judged-not-matched` 記的 #383
反例組。音節切分建在 `NameNormalization.matchingKey` 之上——連字號家族的清單不另立第二份。

第二半：消去後若存活者正規化是同一個名字（`Carol S Dweck` ／ `Carol S. Dweck`），留空
等於要人回答一個沒有內容的問題。`NameForm.preferredRendering` 挑一個寫法，順序是
非全大寫 → ASCII 標點 → 首字母帶句點（APA7）→ 較少空白分段（羅馬化中文名的連字號慣例）
→ 字典序。

實測：留空 **87 → 9**，而那 9 筆正好是機器不該碰的三類（名字順序、變音符號、拼錯）
加一筆全是引用形的。逐一判定後 **4,571/4,572 已指定**；`wei-chun-yu` 刻意留空——兩個
寫法都是引用形，而自然語序的形式根本不在 `names` 裡，補一個沒有來源用過的寫法就是
#227 說的機械偽造。

### 一條既有測試的判定被翻轉，fixture 刻意保留

`testMigrationLeavesGenuineAmbiguityUndecided` 原本斷言 `["Wei-chung Liu", "W. C. Liu"]`
留空，註解寫著「兩個都不是引用形——那是真的要人判斷」。本輪認定那個理由對縮寫形不成立。
**不換 fixture**——換掉會讓「這個判定曾經是相反的」從紀錄裡消失；改名為
`testAbbreviationIsNoLongerTreatedAsGenuineAmbiguity` 並寫明理由，原本那一半的保證由新的
`testGenuinelyDifferentNamesStayUndecided` 接手。

## 一併開的三張

- **#550** 命名慣例的 type 軸（上面第二點的證據都在那張）
- **#551** `mcp-cli-parity` 的稽核程序枚舉不到 per-command 旗標（38 `@Flag`／91 `@Option`）
  ——原本那句「`--json` 不是新能力」是用重新分類迴避問題
- **#552** 已於同日修完並關閉
