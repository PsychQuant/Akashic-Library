# Akashic 的目標是完全取代 EndNote 與 Zotero

Akashic 不是「Zotero 的補充」，也不是「架在 Zotero 之上的一層」。目標是**完全取代 EndNote 與 Zotero**——終局狀態是不裝它們也能做完所有事。

使用者 2026-08-10（+08:00）定調。

## 這不是願景宣言，是裁決依據

設計出現分岔時拿這四條來裁：

1. **檔案要住在 Akashic 裡，不是指向別人的儲存。**
   `attachments.zotero:`（指進 Zotero 資料目錄）是**過渡期權宜**，不是終局形狀。凡是「必須先裝 Zotero 才能用」的功能都不算完成。

2. **位元組要複製一份進 store。**
   使用者明確要求（2026-08-10）。**不採**「只放指標、不複製外部檔案」的方案——那讓 Akashic 依賴外部檔案樹的完整性與命名穩定性，與取代目標直接矛盾。重複儲存是可接受的成本。

3. **對 Zotero 的單向 pull 是暫時的。**
   `docs/store-format.md` §2.5 已把 Zotero 標為「過渡期」「降級為擷取前端」。新增任何對 Zotero 的依賴，都要先回答「取代之後這條路怎麼辦」。

4. **能力缺口要被記成 issue，不能靠「反正還有 Zotero」帶過。**
   使用者說「這個功能我回去用 Zotero 做」一旦變成常態，就是取代失敗的樣子——而且它是**安靜的**失敗，因為每次個別繞過都看起來很合理。

## 要覆蓋哪些能力（**開放清單，尚未盤點**）

以下是**已知**缺口，**不是封閉列舉**，也**不代表其餘皆已具備**。正式盤點應另開 issue 做，本節只是提醒「取代」這個詞涵蓋的面比想像大。

| 對象 | 已知缺口（未窮舉） |
|------|-------------------|
| Zotero | 瀏覽器一鍵擷取（Connector）、PDF 閱讀器與註記、筆記、CSL 樣式廣度、Word／LibreOffice 引用外掛、群組庫 |
| EndNote | Cite While You Write、output styles、Find Full Text、travelling library |

Akashic 已有的對應面（entity store、citekey、biblatex／CSL export、MCP、原生 App、內容定址的 `sources/`、欄位層級 `references:`、divergence record）**不在此表**——此表只列缺口，不是能力對照表。

## 為什麼是 rule 不是 issue

它是**每次都要拿出來對的判準**，不是一件會做完的事。寫成 issue 會被 close 掉然後遺忘，而分岔會一直出現。

## 觸發過的實例

**2026-08-10 · [#223](https://github.com/PsychQuant/Akashic-Library/issues/223)**（一份 PDF 是 source 還是 attachment）：`attachments.pool:` 的唯一實質理由是「不想複製大檔」。使用者定調要複製（第 2 條），加上「檔案要住在 Akashic 裡」（第 1 條），`pool:` 的存在理由消失——本 rule 直接裁掉了那個分支，不必再權衡。

把實例留在文件裡，是因為只留結論的話，日後維護者會覺得「這條寫得囉嗦、我幫它精簡一下」而把裁決力刪掉（見全域 rule `common-spec-prose-enumeration.md`）。

## 一個非顯而易見的後果

完全取代 Zotero，意味著**大量第三方版權 PDF 會進入本機 store**。`sources/` 的 gitignore 排除與 `SourceStore` 的 fail-closed 驗證（寫入前用 git 自身忽略判定確認，未生效拒寫）因此從「保險」升級為**承重結構**——取代做得越徹底，那道閘擋住的東西越多。

**不得為了任何便利放寬它。** 相關規範見 `openspec/specs/provenance-reference/spec.md` 的「Stored content SHALL NOT be tracked by the version-control remote」與全域 `~/.claude/CLAUDE.md` 的 Git 隱私邊界。
