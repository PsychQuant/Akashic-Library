# 2026-09-27 回到預設建置系統：外部探針兩種佈局都認得，拔掉 native 釘子（#577）

Xcode 27（2026-09-16）起，`swift build`／`swift test` 的預設建置系統從 native 改成 swiftbuild，而且沒有環境變數可以切回。`AkashicPropositionTests` 有三個外部探針測試，是以 `.xctest` 所在目錄反推 native 的佈局（`Modules/` 與往上兩層的 `checkouts/`），所以在 swiftbuild 下必紅。

當時的中間項是把 native 釘在七處：pre-push、`ci.yml` 五處、`census-parity.yml` 一處。每處 build 之後都要把 `.build/debug` 手動指回 native 的產物目錄，因為守衛從那裡找 binary，而 swiftbuild 會把連結改指到別處。SwiftPM 已把 `--build-system native` 標為 deprecated，並預告會移除。

## 改了什麼

- **探針**：佈局判斷收進 `SwiftcProbe.layout(products:)`。
  - 有 `Modules/` 就用它（native），沒有就用 products 目錄本身（swiftbuild 的 `.build/out/Products/Debug`）。
  - `checkouts/Yams` 逐層往上找，不寫死層數。
  - 存在斷言改查 `AkashicProposition.swiftmodule` 本身。
- **pre-push、`ci.yml`、`census-parity.yml`**：拿掉 `--build-system native` 與手動重指 `.build/debug`／`.build/release` 的段落。預設建置系統建完會自己指好連結，所以這三處只核對 `.build/debug`（或 `.build/release`）解析到的目錄等於 `swift build --show-bin-path`，不等就中止——守衛不會跑到別次建置的 binary。
- **`PrePushHookTests`**：
  - 期望的呼叫改成不帶 `--build-system native`。
  - 兩支驗「重指」的測試（`.build/debug` 是真目錄、是普通檔案）驗的是被拿掉的行為，刪掉。
  - 「native 產物目錄不在就中止」改成 `testHookAbortsWhenDotBuildDebugIsNotThisBuildsProducts`：連結指向別處時 hook 非零結束、說明原因、不跑守衛。
- **`TractatusInterfaceTests`**：對 `ci.yml` 的字串斷言改成不帶旗標的版本。

## 量測

- native 下 `AkashicPropositionTests` 121/0，swiftbuild 下 121/0。
- 負控：四個檔換回舊版（寫死 native 佈局），在 swiftbuild 下紅 27 條斷言，全在三個探針裡。
- swiftbuild 下 `.build/debug` 自動指向 `out/Products/Debug`，與 `swift build --show-bin-path` 一致；`akashic` 與 `akashic-guards` 都在裡面（2026-09-27 實測）。
