# venue 的 verdict 跟著 citekey 走（#460）

work 的 citekey 退役（rename／merge）時，venue 身上的 `work:` holder verdict 現在一併遷移。
在此之前兩處遷移迴圈都只掃 people——#232 修 rename、#271 修 merge 時 venue verdict
（#304 引入，`entity-backlink-completeness` 第 13 條邊）尚不存在或被漏，家族第三個缺口。

## 實測的洞（#456 pilot 抓到）

合併 `bakeman1996btesting` → `bakeman1996testing` 後，`psychological-methods` venue 仍持
`'work:bakeman1996btesting :: Psychological Methods'`——指向已刪 citekey 的死 verdict。
#456 批次（204 組攣生合併）後全庫累積 **204 條** stale。

更尖的一半：**rejected verdict stale 會讓否決抑制安靜失效**——同一配對被重新提名，
打破 #232 自己的「Rejection SHALL be distinct from absence」。

## 修了什麼

- `DivergenceResolve.swift`（resolveWorkDivergence）與 `LibraryStore.swift`（renameEntry）
  各加 venue 遷移迴圈——**完全鏡射既有 person 迴圈**：同 `VerdictPairingValue` 文法、
  同 (field,value) 冪等收攏、同 encode-先行的撕裂防護、同 failures 回報
- 測試四支（RED→GREEN）：merge 遷移到 survivor／同值冪等收攏成一筆／rename 遷移到
  newKey／rejected 欄位同樣遷移
- 一次性清理（store 資料操作，隨 store commit 不在本 diff）：204 條 stale 按
  doomed→keeper 映射驗證後冪等收攏——203 條淨刪（keeper 版已在）＋1 條遷移，
  venue verdicts 1556 → 1353，validate 全綠

## 誠實邊界

- merge 側的冪等收攏**對順序敏感**（doomed verdict 排在 keeper 原版之前時，keeper 原版
  不查重）——person 側自 #271 即有此形，venue 鏡射刻意繼承（同構同修），另案 #461
- 「同構鏡射」是選擇不是必然：抽 generic helper 會動到兩個既有迴圈，blast radius 更大；
  重複的代價由 #461 修復時一併重估
