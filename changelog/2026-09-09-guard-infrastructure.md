# 守衛基礎設施：`rawFile` 讀不到即中止、workflow `run:` 的腳本要存在（#527 #526）

兩張都是 #521 的 residue：那次修的是**實例**，這兩張修的是**形狀**。

## #527 —— `rawFile` 回空字串

`""` → `components(separatedBy: "\n")` → `[""]` → 走訪它的迴圈**零次迭代**，檢查印完標題就沒有
本體、rc 仍是 0。**缺口不是沉默，是偽裝成一次通過。**

**裁決取自量測，不是偏好。** 11 個呼叫點逐一追過路徑來源——glob、`GUARDS` 清單、固定的受保護檔
——**沒有一個容許缺席**。而真的容許缺席的兩處已經在**呼叫端**寫成 `fileExists(x) ? codeOnly(x) : ""`：
那是更好的位置，決定寫在做決定的地方、讀者看得到。

所以選 issue 的候選 1（`rawFile` 本身 fail-loud），不是候選 2（另加 `rawFileRequired`）：零個呼叫點
需要容忍版，把它留在 default 位置就是留一個**沒有人需要的陷阱**。

**rc=2 而不是 1**：1 是「守衛查到問題」，2 是「守衛跑不起來」——讀 CI 輸出的人要去修的東西不同。

**邊界**：mutation harness 的 8 處同形 `?? ""` 刻意不動——那些檔會改寫工作樹再還原，從葉函式
`exit` 會跳過還原、留下被 mutate 的 repo。它們已經用 `guard let … else { return }` 讓錯誤沿呼叫鏈
回去，那是對的形狀。

## #526 —— workflow 的 `run:`

#521 的四個實例裡**有兩個**是這個形狀，而**實例 4 是 verify 席找到的**：這個缺口已經讓一次封閉
列舉出錯。後果不對稱——一個掛掉的 step 會擋住其後**全部**步驟，`ci.yml:94` 那次擋掉的包含
AkashicApp（`swift test` 涵蓋不到的那塊，#101 的立案理由）。

**為什麼是獨立守衛。** issue 說的是「納入**某個**守衛的視野」，沒指定哪支。併進 `trigger-coverage`
的第一版實測讓該支的 mutation harness **5 個既有 case 同時失敗**——那些 case 刻意在 workflow 注入
指向不存在腳本的假命令（`plugin/tests/DELETED-numbers-audit.py`）來測 `invoked()` 的剖析，而本檢查
會如實報那些引用。**一支守衛的 harness 偽造某種內容，另一道檢查又對那種內容做存在性斷言，
兩者永久互相干擾。**

（過程中還撞到第二件事：`AuditGuardsMutations` 的複製清單少 `mcpb/manifest.json`，所以把
`trigger-coverage` 帶進那個 harness 會讓 baseline 就紅——那是 #518 記過的「`DATA` 的第三份副本」
殘留。沒有為了測試再補第四份。）

### 避開 issue 點名的兩個坑

- **只看 `run:` 且剝 shell 註解**——`ci.yml` 自己就有一段註解逐字寫著「原本是
  `python3 …/marker-parity-mutations.py`」。掃全檔會把那個**刻意記下的已刪檔名**當成引用，
  於是修好的東西因為被寫進註解而重新變紅。
- **空集合不得冒充通過**，且兩個原因訊息分得開：沒有 workflow 檔（repo 狀態）vs 有 workflow
  卻掃不到任何引用（掃描壞了）。

### tokenizer 的兩個真 bug，都是既有 case 撞出來的

`swift build`／`swift run` 的下一個 token 是**子命令**不是路徑，只有 `swift foo.swift` 是跑檔；
shell 運算子不是路徑——`cat x | bash && echo` 曾讓 `bash` 的下一個 token 是 `&&`，報「跑 &&，
而那個檔不在」。**假紅比漏報貴**（`zero-instance-guards` 第 6 列）。

## `zero-instance-guards` 第 20 列

理由與既有 19 列都不同：這一列的零是**剛剛被人工修完的**，而修它的那一輪自己證明了人工窮舉
不可靠——四個實例裡第四個是**別人**找到的，且與前三個形狀完全相同。不是第 1 列的「沒有跡象」，
也不是第 13 列的「跡象住在錯的地方」，是**看過了、看的是對的地方，仍然漏了一個**。

PR #534。
