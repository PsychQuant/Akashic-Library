# 量測指令要能自證：「印 0」與「檢查過且乾淨」要分得開

從 [`zero-instance-guards`](zero-instance-guards.md) 的量測段抽出來的通則（#711，使用者 2026-10-05 裁決：規則檔裡本身是通則的段落抽成獨立的小規則）。
那份表有幾十條「重跑指令」，原本各自寫「同第 13 列的自證」，而那個「自證」的寫法與理由只住在第 13 列與第 19 列的量測段裡（現在都在量測文件）。

適用於**零實例裁決表的量測**——規則檔與 [`docs/zero-instance-measurements.md`](../../docs/zero-instance-measurements.md)（量測文件）裡給人重跑的指令；
`zero-instance-rows-audit` 兩份都掃。其他地方（changelog、issue comment、別的規則檔）寫給人照抄重跑的量測，用同一個寫法——守衛不掃那裡。

## 規則

1. **數 `akashic`／`akashic-guards` 輸出的量測只有一種寫法**，寫在 fence 裡的一行、或不跨行的一段 inline code：

   `[: "${V:?…}" && [test -f "$V/store.yaml" && ]]LC_ALL=C grep -a -q '<片段>' <BIN> && <BIN> <參數> 2>&1 | grep -c '<樣式>'`

   方括號是可有可無的前置條件。這一行與守衛的 `selfProofTemplate` 逐字相同，守衛查這件事；判讀的細節（什麼算一個單位、什麼算計數）
   只寫在 `ZeroInstanceRowsAudit.swift` 的 `selfProofIssues`，片段的條件只寫在 `selfProofNeedleIssues`，這裡不複述。

   - **閘**（`grep -a -q '<片段>' <BIN>`）證明被量的那支 binary 有這條檢查。沒有閘時，沒有那條檢查的舊 binary 什麼都不數、印 `0`——
     與「檢查過且乾淨」在輸出上分不開。`<BIN>` 兩處逐字相同，是路徑或 `"$(command -v akashic)"`，不是裸名。
   - **`LC_ALL=C` 不能省**：macOS 的 `/usr/bin/grep` 在 UTF-8 locale 下對 binary 比不到中文，會把新 binary 讀成舊的（#710）。
   - **片段取那則訊息裡夠長、只有那則訊息有的一段**：太短的片段在任何 binary 裡都找得到（閘恆真），落在短字串字面段裡的片段在 release
     建置裡位元組不連續（閘把有這條檢查的 binary 讀成舊的，#711 R1）。條件的完整清單在 `selfProofNeedleIssues`，守衛紅時訊息說是哪一條。
   - **必要的變數寫在整條最前面**：`: "${V:?…}" && …`。寫在管線裡的 `${V:?…}` 只結束那一段的子 shell，管線右邊的 `grep -c` 照樣印 `0`；
     `--library "$V"` 另要 `test -f "$V/store.yaml" && `——V 打錯成一個不是 store 的目錄時 `validate` 報錯、計數照印 `0`（#711 R4）。
2. **讀 store 的腳本用 YAML 解析器，不用行級 grep**：長的 value 會被 YAML 折行，行級比對會少算而不出聲（量測文件裡第 13、18 列的量測都踩過）。
3. **讀不到或不是記錄的檔要計數並印出來**，不靜默跳過：`except: continue` 把「整支腳本壞掉」換成「安靜少算」（量測文件裡第 24 列的量測段）。
4. **每個數字旁寫日期與條件**（`# 2026-09-29：…`）：數字會過期，寫出條件，重跑的人才知道比的是什麼。`measured-numbers-audit` 對規則檔與量測文件裡
   的「實測 N」要求時間錨或可重跑的指令。
5. **新增合模板的量測之後，把量測文件的棘輪下限調高**（`<!-- zero-instance-rows-audit 棘輪：… -->`）：它記依閘去重後至少幾條，少於下限守衛就紅。

## 守衛與它管不到的

`zero-instance-rows-audit` 掃規則檔與量測文件：提到 binary 又有計數的單位就是一條量測，不合模板即紅、具名那一行；量測文件裡一條都掃不到也紅；
合模板的量測依閘去重後少於棘輪下限也紅。負控是 `audit-guards-mutations` 裡 `zi-rows：` 開頭的格子。

**認不出來、所以不紅的寫法是開放的**：binary 的輸出先存進變數或檔案、在另一個單位計數；以別名、複本或名字不含 akashic 的變數執行 binary；
散文裡 binary 名與計數不在同一個邏輯行。它們由棘輪兜底——擋得住整批流失，擋不住少量。

## 為什麼

第 13 列的量測立案時，PATH 上的 `~/bin/akashic` 是沒有那條檢查的舊版：對一份真有 5 條死 verdict 的副本回 0，`.build/debug/akashic` 回 5。
之後 #711 的四輪 verify 每一輪都找到一種讓閘形同虛設的寫法（`;` 接上、閘與被量的不是同一支、管線裡的 `${V:?…}`），所以寫法收成一種、由守衛逐字比對。
逐輪的細節在量測文件最後一節與 changelog（`2026-10-01-measurement-self-proof-and-ci-gap-size.md`、`2026-10-02-measurement-*.md`、
`2026-10-04-b32-f7-fixes-711-712.md`、`2026-10-05-b34-k3-fixes-711-712.md`）。
