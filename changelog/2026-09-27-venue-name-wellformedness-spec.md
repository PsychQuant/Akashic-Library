# 2026-09-27 venue 名字內容的不變式寫進 spec（#570）

#554 D8 把 venue 名字內容的不變式裝在 `Venue.validate()`（error 級、寫入期），但規範文字只寫在 `docs/store-format.md` §5.7，`venue-entity` spec 沒有對應的 Requirement。後果是 Spectra 的 drift 與 audit 看不到它：審查一個動到 venue names 的 change 時，讀 spec 的人會以為合法的 venue 記錄只受「authorized／variant 互斥」與「variant 不帶時間欄位」兩條約束。

## 改了什麼

- **spec**：Spectra change `venue-name-wellformedness-spec`（已 archive）在 `venue-entity` spec 新增 Requirement「Venue name well-formedness」。它以規格語言寫出六條不變式：
  1. canonical 形；
  2. 不含輸出閘 `UnsafeToEmitScalar` 的成員（扣掉私用區），ZWJ／ZWNJ 只在兩個脈絡合法；
  3. 至少一個 L 或 N 類字元；
  4. 同一張清單內沒有 canonical 相等的兩筆，沿革豁免照 §5.7 的「不相交」定義；
  5. 同名段的組內求值上限 5,000 對；
  6. 整筆的求值上限 100,000 對。

  另有八個 scenario。
- **§5.7 的定位**：§5.7 仍是逐字元判定的細節來源（scalar 類別、接合字元的兩個脈絡、訊息措辭），spec 明寫兩者要一起改。§5.7 開頭那句「在 spec 補齊之前，本節是唯一的規範來源」改成指向這條 Requirement。
- 沒有程式碼改動。

## 驗證

- 六條不變式逐條與 §5.7 並排對照，數字與例外條件一致。
- 每個 scenario 都有 `VenueNameInvariantTests` 的既有測試對應（50 條全綠）：尾隨空白、TAG 字元、波斯文合法 ZWNJ、`×`、`1843`、Sankhyā 的不相交與端點相等、authorized 重複、超過 100 筆同名段。
- TAG 字元的拒絕另以真 binary 實跑過（#569 同日）。

`spectra task done` 認不得這個 change 的 task 編號，所以 archive 裡 tasks.md 的勾選框沒被勾上。三個 task 都已完成，以本檔為準；archive 目錄受保護，不去手改。
