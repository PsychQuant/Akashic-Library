# 識別碼有型別了，但還沒有落點——#394 的前三節落地，後六節沒有

2026-08-24 下午。這一輪沒有新的設計工作：把 `idd/394-first-class-identifiers` 這條**只存在
單機、從未推過 remote** 的分支推上去，然後 fast-forward 合進 main。5 個 commit、30 檔、
+520/−55。

值得寫下來的不是「合了什麼」，是**合進來的是半條 change**，而半條的安全性有一個很窄的理由。

## 落地的部分（§1–§3）

`Sources/AkashicCore/Identifier.swift` 有了六個帶驗證的 value type：`ISSN`／`DOI`／`PMID`／
`ISBN`／`ORCID`／`ROR`。它們不是 typealias，各自有形狀驗證與正規形輸出——`0003-066x` 讀得進
來、寫出去是 `0003-066X`；`12345` 與 `1467-8624(Electronic),0009-3920(Print)` 直接拒絕。

識別碼同時落到**它所識別的那個實體**上，這是 #394 標題後半句（「ISSN 放在錯的實體上」）的
修正：`Venue.issn: [ISSN]`、`Organization.ror: ROR?`、`Entry` 拿到 `doi`／`pmid`／`isbn`。
`Person.orcid` 從 `String?` 升為 `ORCID?`，五個消費面（App 審議面、MCP 的 update-person、
CLI、關聯匯出、divergence 解析）一併更新。

新測試 408 行（`IdentifierTests` 220、`IdentifierPlacementTests` 188）。

## 沒落地的部分（§4–§9），以及為什麼合進來仍然安全

**§4「YAML 編解碼」還沒做。** 查 `YAML.swift` 的 diff：它**只動了 `Person.orcid`**（那個鍵
本來就存在），上面那五個新欄位一個都沒接上序列化。

所以合進來之後，新欄位在型別上存在，但寫不進 YAML、也讀不出來。

**這安全，但理由很窄，值得寫清楚**：不是「序列化缺了沒關係」，而是**目前沒有任何生產者**
——`grep` 過 `Sources/`，這些欄位只有 default-empty 建構器，唯二的讀取面是
`DivergenceResolve` 的 `lostIdentifiers` 報告與 `canonicalDOIs` 從 `fields` 撈殘留。缺口的
前件永遠不成立，所以既有記錄的 YAML 不會變。

**這個窄理由的失效條件也具體**：一旦有人開始往 `Entry.doi` 寫值（importer、`create-entry`、
任何寫入面），值會在下一次讀-寫循環中**無聲消失**。那正是 `lossless-intake` 說的「靜默是
最糟的形式」。§4 落地前，這些欄位不該有生產者。

（注意這裡沒有主張「export 逐位元無差異」——那是 §7.1 的驗證目標，本輪沒跑。上面的論據是
結構性的：encode 沒接上 ＋ 無寫入路徑。）

## 一個作者自己就認出來的分岔

`Person.orcid` 的 decode 選了 **fail-closed**：形狀不合法就 quarantine 整筆，不靜默轉 `nil`。
而 §4 的最終目標是**讀取面寬容保留**（非法值仍能載入，由 `akashic validate` 具名回報）。

兩者不同，而分支的註解明寫了這件事、也明寫了為什麼現在選 fail-closed：quarantine 是**看得見
的**失敗（`doctor`／`validate` 報得出來），靜默轉 `nil` 則是資料無聲消失。也就是說 §3 與 §4
之間的讀取語意目前是兩套，這是**有記錄的**暫時狀態，不是漏掉的。

## 順帶修掉一個限定詞

`entity-backlink-completeness.md` 的封閉列舉判準原本寫「**純量的**外部識別碼——不算」。#394
把「純量的」三個字拿掉了。

理由是那個限定詞**描述的是當時的實例**（`orcid`／`openalex` 恰好都是純量），不是理由的一部分
——排除的根據是「指向 store 之外」，而基數與指向哪裡無關。`Venue.issn` 是清單（print 與
electronic 是兩個真的號），留著「純量的」它就會落在判準的字面之外、**看起來**該進封閉列舉，
於是一個外部識別碼被當成關係邊。

`plugin/tests/backlink-field-ratchet.py` 同步把五個欄位名加進排除清單，每一條都寫了它自己的
理由。欄位棘輪現況 113／已裁決 113。

## 量測

| | |
|---|---|
| `swift build -Xswiftc -warnings-as-errors` | 通過（12.6s） |
| `swift test` | **2092 tests, 0 failures, 2 skipped**（262s） |
| pre-push（20 支守衛 + build + test） | 全綠 |
| merge 形狀 | ahead=5 / behind=0，`--ff-only` |

## 還沒做

#394 仍開著。§4（YAML 編解碼）、§5（基數決定 provenance 驗證分支）、§6（format 12 → 13）、
§7（匯出面）、§8（`migrate-identifiers` 遷移）、§9（兩面對等與收尾）都還沒動。
