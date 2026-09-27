## Summary

`venue-entity` spec 補一條 Requirement「Venue name well-formedness」，把 `docs/store-format.md` §5.7 的名字內容不變式寫進規格，每條不變式配一個 scenario。

## Motivation

#554 D8 把 venue 名字內容的不變式裝在 `Venue.validate()`（error 級、寫入期），規範文字只寫在 `docs/store-format.md` §5.7。`venue-entity` spec 已有兩條同形的驗證期 Requirement（authorized／variant 互斥、variant 不帶時間欄位），但沒有這一條。

結果是 Spectra 的 drift 與 audit 看不到 D8：下一個動到 venue names 的 change 沒有 Requirement 可以對照，審查者讀 spec 會以為合法 venue 記錄只受那兩條約束（#570）。

## Proposed Solution

在 `venue-entity` spec 新增一條 Requirement，以規格語言寫出六條不變式，每條一個 scenario：

1. canonical 形（NFC、無前後空白、內部空白收成一個 U+0020）；
2. 不含危險或不可見 scalar——集合是輸出閘 `UnsafeToEmitScalar` 扣掉私用區（#569 起輸出閘本身就是性質）；ZWJ／ZWNJ 只在兩個脈絡合法；
3. 至少一個字母或數字（generalCategory 的 L 或 N 類）；
4. 每張清單內沒有 canonical 相等的兩筆；`names` 的例外是同名的沿革段，「不相交」照 §5.7 的定義；
5. 同名段的組內求值上限（5,000 對）；
6. 整筆記錄的求值總量上限（100,000 對）。

scalar 類別的完整清單、接合字元兩個脈絡的逐條判準、訊息措辭，Requirement 明寫以 §5.7 為細節來源，不在 spec 裡複述。spec 管「什麼是合法記錄」，§5.7 管「怎麼逐字元判定」，避免同一份判準有兩個會分岔的副本。

§5.7 開頭那句「在 spec 補齊之前，本節是唯一的規範來源」同批改寫，改成指向這條 Requirement。

## Non-Goals

- 不改任何程式碼：`Venue.validate()` 的行為不變。這是規格補齊。
- 不把接合字元的脈絡判準逐條搬進 spec。那些判準由 `NameIdentity.joinerIsLegal` 與 §5.7 承載，搬進來會製造第二份會分岔的描述。
- 不涵蓋 person／organization 的名字檢查。它們各有自己的規則。

## Alternatives Considered

- **只在 spec 加一句「見 §5.7」**：Spectra 的 drift 仍然看不到任何具體條文，這正是 #570 要解決的問題。
- **把 §5.7 整段搬進 spec、刪掉 §5.7**：§5.7 是手改 YAML 的人讀的 store 契約（與 §3.4 同級），拿掉會讓那些讀者失去依據。

## Impact

- Affected specs: `venue-entity`（modified：新增一條 Requirement）
- Affected code:
  - Modified: docs/store-format.md（§5.7 開頭一句改成指向 spec Requirement）
