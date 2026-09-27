## 1. 規格與文件

- [ ] 1.1 確認 spec delta 的六條不變式與 `docs/store-format.md` §5.7 一致：逐條對照 §5.7 第 1–6 條的判準（canonical 形、輸出閘扣私用區與接合字元、L／N 類、canonical 相等與沿革豁免的「不相交」定義、5,000 對、100,000 對），數字與例外條件相同；驗證方式是逐條並排讀過，差異記在本 task 旁
- [ ] 1.2 以 `VenueNameInvariantTests` 與真 binary 核對每個 scenario 的結果：尾隨空白、TAG 字元、波斯文合法 ZWNJ、`×`、`1843`、Sankhyā 沿革（不相交與端點相等兩種）、authorized 重複、超過 100 筆同名段；每個 scenario 至少有一支既有測試或一次 scratch store 的 `validate` 實跑對應
- [ ] 1.3 改寫 §5.7 開頭「在 spec 補齊之前，本節是唯一的規範來源；follow-up 見 #570」那一句：改成本節是 `venue-entity` spec「Venue name well-formedness」Requirement 的逐字元細節來源，兩者要一起改；驗證方式是 grep 該句舊文字不再出現
