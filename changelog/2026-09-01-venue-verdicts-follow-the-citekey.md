# venue 的 verdict 跟著 citekey 走（#460）

work 的 citekey 退役（rename／merge）時，venue 身上的 `work:` holder verdict 現在一併遷移。
在此之前兩處遷移迴圈都只掃 people——#232 修 rename、#271 修 merge 時 venue verdict
（#304 引入，`entity-backlink-completeness` 第 13 條邊）尚不存在或被漏，家族第三個缺口。

## 實測的洞（#456 pilot 抓到）

合併 `bakeman1996btesting` → `bakeman1996testing` 後，`psychological-methods` venue 仍持
`'work:bakeman1996btesting :: Psychological Methods'`——指向已刪 citekey 的死 verdict。
#456 批次（204 組攣生合併）後全庫累積 **204 條** stale。

更尖的一半是**條件句**：rejected verdict 若 stale，否決抑制會安靜失效（同一配對被
重新提名，打破 #232 的「Rejection SHALL be distinct from absence」）。實測 venue 的
2,167 條 verdict 現況全為 confirmed、0 筆 rejected——這一半是 zero-instance guard，
不是已實現的事故。

## 修了什麼

- `DivergenceResolve.swift`（resolveWorkDivergence）與 `LibraryStore.swift`（renameEntry）
  各加 venue 遷移迴圈——鏡射既有 person 迴圈：同 `VerdictPairingValue` 文法、
  同 (field,value) 冪等收攏（rename 側順序無關；merge 側限 keeper-first 排列，#461）；
  rename 側前置閘完整鏡射寫入端（`assertVenueWritable` ＋ encode 先行——比 person
  側多一道，person 側的同型缺口屬 #461 家族另議）
- 測試五支：merge 遷移／keeper-first 收攏／doomed-first 斷言現況的 pin（#461 紅色
  目標）／rename 遷移／rejected 遷移
- 一次性清理（store 資料操作，隨 store commit 不在本 diff）：204 條 stale 按
  doomed→keeper 映射驗證後冪等收攏——203 條淨刪（keeper 版已在）＋1 條遷移，
  psychological-methods 單檔 verdicts 1556 → 1353（全庫 venue verdict 2,167），validate 全綠

## 誠實邊界

- merge 側的冪等收攏**對順序敏感**（doomed verdict 排在 keeper 原版之前時，keeper 原版
  不查重）——person 側自 #271 即有此形，venue 鏡射刻意繼承（同構同修），另案 #461
- 「同構鏡射」是選擇不是必然：抽 generic helper 會動到兩個既有迴圈，blast radius 更大；
  重複的代價由 #461 修復時一併重估
