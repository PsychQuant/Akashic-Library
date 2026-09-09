# verdict 相等的單一定義，以及它解開的四張（#470 #486 #467 #469 #483）

#470 是關鍵：它一裁決，#486 就寫得出來，而 #467 寫出來的預測函數又直接餵給 #469 的閘門。

## #470 —— 兩個相等定義

寫入面（merge 的 `dedupKey`、rename 兩處 `seen`、`ResolutionLedger.appendIfAbsent`）比 `value` 的
**原字串**；讀取面（`PersonResolver` 的 `rejectedNorm`）比 `NameNormalization.matchingKey(literal)`。
於是 `work:k :: Fann, C.` 與 `work:k :: Fann,  C.` 在寫入面是兩筆、讀取面是同一筆——
「store 永不持有重複 verdict」在**讀取面的意義上**已經被違反，而兩面都不會出聲。

**裁決：取正規化的那一個。** 理由是 verdict 的用途本身：它抑制的是「這個 (holder, literal) 配對
已經判過了」，而提名層一路都用正規化比對（`LooseNameKey`／`PersonResolver.normalize`）。

**「正規化只住在鍵裡，不外洩成資料」不是本輪發明的**——它逐字寫在 `PersonResolver.normalize` 的
doc 上（「比對面吃正規化，輸出仍是原字串」）。本輪只是把那句話套到另一面。`value` 因此仍逐字存
原字串，`demote`（#418）仍取得回原本那個 literal。

**實測 live store：2,700 筆 verdict，正規化後重複而位元組不同的組 0**——統一不改變任何既有資料。

守衛掃**形狀**不掃名字：全樹不得再出現手寫的 `<field>\u{0}<value>` verdict 鍵（改名不會讓它失效，
而複製一份實作會），並斷言掃到的檔數 > 50——空集合不是綠。

## #486 —— 同配對的 confirmed／rejected 並存

前提是 #470：在它之前「同一配對」有兩個答案，先寫任一個就是偷偷定案第三份。

相等用 #470 的定義**去掉 `field`**——本掃描問的正是「兩個 field 對同一個配對」，把 field 放進鍵
會讓它永遠找不到東西。severity 是 warning：兩條 verdict 各自合法、檔案載入得了——壞掉的是**判定**
不是資料。輸出排序過：走訪 `Dictionary.values` 的順序未定義，不排序會讓逐字比對的負控偶發假紅。

`zero-instance-guards` 第 14 列依它自己寫下的觸發條件從「不寫」翻成「寫」。**那個翻轉的方式值得
留著**：這一列不是被人想起來才改的，是它的觸發條件**機械可檢查**（另一張 issue 的 state），
#470 一 close 就到期——對照第 10、12 列，它們要人指認。

## #467 —— dry-run 對 verdict 面沉默

`previewResolveDivergence` 只算 entry 側 relations 與 divergence 遷移。同檔反覆強調「dry-run 的
價值是誠實預告」，而 #461 讓那個未被預告的步驟從「只改值」升級成「會刪列」。

`predictedHolderVerdictMigration` 與實跑走**同一支純函數**，迴圈範圍逐一鏡射。**`ResolveReport` 的
`==` 納入這兩個欄位**——先前刻意不進的理由是「preview 側算不出來」，補上之後那個理由消失。

**CLI 的 dry-run 有自己的渲染路徑**，所以只補 model 等於沒補。

## #469 —— holder 檔不在版控閘內

`filesNotSafelyRecoverable` 只對 `doomedFiles` 跑。真正且唯一的暴露是：**被收攏掉的那一列若只存在
於未 tracked／dirty 的檔案裡，刪掉後 git 取不回**。

名單直接來自 #467 剛寫的預測函數——「會被改寫的是哪些」只能有一個答案，而閘門與實跑用不同的答案
正是這一族反覆的病。測試特地釘住「**無關的未追蹤記錄不進名單**」：「store 其他地方髒不影響這次
刪除的可回溯性」是這道閘既有的立場，擴大範圍不得把它推翻。

## #483 —— 寫入面的 bug 偽裝成遷移面的缺口

全樹最後一個兩路 `holderKind` 推導。#378 把 confirmed 路徑換成窮盡 switch 時沒跟著改 reject 路徑，
於是一個 `.work` 候選被否決會寫出 `org:<citekey>`——那條 verdict 在死 verdict 掃描下**必然**變死，
而訊息會把成因說成「遷移漏了這一格」。**修錯地方的成本比缺口本身高。**

定義搬到型別上，兩個呼叫端共用。窮盡 switch 不寫 `default`：值域加第四個成員時要編譯錯誤。

PR #535。
