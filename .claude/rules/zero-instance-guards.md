# 為「還沒發生過的形狀」寫守衛，是一列一列裁決出來的——不是判準推導出來的

適用於**新增一個當下零實例的東西**，封閉二類：

1. **守衛**：validator 的檢查、schema 的約束、CI 的 gate、任何「現在沒有資料會被它擋下」的防線。
2. **欄位**（2026-08-24 由 #394 的 `Organization.ror` 顯式擴入，見第 9–12 列）：一個模型裡的
   欄位，而當下全庫零筆記錄使用它。
3. **保留位置的 Requirement**（2026-09-09 由 #474 的「刊名沿革時間軸」顯式擴入，見第 22 列）：
   spec 裡一條描述**真實現象**的 Requirement，而當下零筆記錄用得到它。

> **第 2 類是顯式擴入的，不是類推來的。** 本檔原本只寫「守衛」，而 #394 要裁決的
> `Organization.ror` 是欄位——把它塞進守衛表就是本規則自己禁止的「依性質相似類推」。
> 擴入的理由是**問題的形狀相同**：兩者都是「現在沒有實例，要不要現在做」，而兩者的
> 代價都落在未來某個沒有人在看的時刻。**但失敗的意義不同**（守衛失敗是漏報，欄位缺席
> 是模型說了一句它沒打算說的話），所以第 9 列的理由欄不能沿用前八列任何一條。
>
> **第 3 類同樣是顯式擴入的**（#474，2026-09-09）。它的問題形狀與前兩類相同（「現在沒有
> 實例，要不要現在做」），而**失敗的意義是第三種**：守衛失敗是漏報、欄位缺席是模型說了
> 一句它沒打算說的話，而一條零實例的 Requirement 的失敗是——**有人把它當死重刪掉**，
> 然後那個形狀到達時沒有位置可落。所以第 22 列的理由欄不能沿用前二十一列任何一條。
>
> 擴入**只到這三類為止**。第四類（例如「零實例的 CLI 命令」）出現時要再顯式擴一次，
> 不得從「Requirement 也算」推導出「命令也算」。
>
> **第 2 類在 2026-09-02 重審過一次**（#365 補第 12 列時，裁決 comment 明寫「三列一次加進去需要重新
> 檢視那個分類是否還成立」）。第 9–12 列現在都是欄位，而第 10–12 列與第 9 列有兩處不同：它們的裁決是
> **不寫**，且加進去**不是 additive**（`Author` 是 `enum`，加欄位要改成 `struct`）。**裁決：仍屬第 2 類。**
> 分類的判準是問題的形狀（「現在沒有實例，要不要現在做」），不是答案（寫／不寫）也不是代價（additive
> 與否）——第 11 列已把 non-additive 當**成本**計入理由欄，那是理由層的事實，不改它在哪一類。同案早先
> 一則 comment 說「型別重構不在本表」，與此不衝突：第 10–12 列問的是「要不要加一個欄位」，重構是加它
> 的**代價**，不是它的**種類**；一個純粹的重構提案（不新增任何零實例的東西）仍然不在本表。

不適用於**已有實例**的守衛（那不需要裁決，有東西壞了就修），也不適用於**移除**既有守衛
（那是 `no-compat-fallback` 的退場紀律，方向相反）。

## 規則

新增零實例守衛時，**在下表加一列**：情形／裁決／理由。**不得依性質相似類推**——覺得
「這跟第 2 列很像」不構成裁決，那正是要停下來想的訊號。

**本檔刻意不給總括判準。** 依全域 `common-spec-prose-enumeration`：一句「凡是成本低就寫」
會在邊界上自己長出沒人同意的答案，而那句話與下表**是兩份不會一起改的規格**。要判斷新情形，
讀下表的理由欄，然後**加一列**。

## 裁決史（封閉列舉——現有 27 列，一列不多一列不少）

| # | 情形 | 裁決 | 理由 |
|---|---|---|---|
| 1 | **零實例、成本一行、前件精確**（#254：`duplicate-rationale` 擴及同命題內兩條 relation。全 corpus 被 >1 條共用的 rationale 種類數 = 0）| ✅ **寫** | 成本是一行前件；而不寫的話，那個形狀第一次出現時**不會有任何跡象**——它會通過 validate、通過測試，只在有人逐條讀 corpus 時才看得出來 |
| 2 | **零實例、成本一行、但前件寫寬了會誤傷**（#253：issue 的 Expected 寫「對所有 status 檢查」。若照字面實作成「任一 relation」會 flag 上百條）| ✅ **寫，但先實測界定前件** | 判準不是「要不要寫」而是「前件多寬」。實測「rationale 引用了 issue」恰好命中 issue 具名的三筆、零附帶損害；「任一 relation」則會 flag 上百條。**沒有那次量測就不該動手** |
| 3 | **未涵蓋不得冒充通過**（#326：`BibValidator` 的必要欄位表只涵蓋 7 個 entry type，store 另有 47 筆不在表內）| ✅ **寫「未涵蓋」的出口** | 這一列不是「要不要寫守衛」而是「守衛沉默時要不要說話」。若只回 issues，「沒被檢查」與「檢查過且乾淨」在輸出上完全一樣——`lossless-intake` 執行細節 3 的「靜默是最糟的形式」 |
| 4 | **猜錯不會有跡象，而猜的代價是整組欄位需求**（#367：`bootstrap-venues` 的型別衝突守衛。同一個刊名來自不同種類的來源欄位時不建檔、交人裁。實測 441 個 literal 全部只對應一個欄位種類 → 0 實例）| ✅ **寫** | 前三列的代價都落在「看不見」；這一列的代價是**看得見但看起來是對的**。`VenueType` 決定「哪些欄位存在」（#324 的 §11 判準），所以取錯 type 不是標籤錯而是**整組欄位需求錯**——而那筆記錄會通過所有檢查，因為它確實滿足了（錯的）那一組。守衛的成本是一個 `guard`，不寫的代價是一筆看起來健康的壞資料 |
| 5 | **重複看起來像多一份覆蓋**（#407 R67c：負控 harness 裡兩個 case 若輸出逐字相同即互相不可區分。實測 35 個 case → 未具名的重複 0 組）| ✅ **寫** | 前四列的代價都落在「被守衛的東西」上；這一列落在**守衛自己身上**。一個重複的 case 會讓計數從 35 變 36、多印一個 `✓`，維護者讀成「又多檢查了一件事」——而那是同一件事查了兩次。它不是看不見（第 1 列）、不是假訊號（第 4 列）、不是沉默的歧義（第 3 列），是**對測試自己的覆蓋率說謊**。成本是零：既有迴圈本來就跑完全部 case，這裡只是分組 |
| 6 | **假紅會讓所有紅燈失效**（#407 R67e：ROBUST 負控拿「守衛在未注入 copy 上的輸出」當 oracle、要求逐字相同。那個前提是輸出決定性——實測 2 支守衛各跑兩次皆逐字相同、無 temp 路徑洩漏 → 0 實例）| ✅ **寫** | 前五列的失敗都**只傷到自己那一格**；這一列的失敗會外溢。守衛若哪天開始印時間／耗時／temp 路徑／走訪順序，逐字比對就偶發變紅——而**偶發的紅**比漏報更貴：維護者學會「這支有時候會紅，重跑就好」，那個習慣會套用到**所有**守衛身上。所以本 harness 唯一一個「失敗會傷到其他守衛」的機制，自己要被檢查。成本是每支 ROBUST 守衛多跑一次未注入（實測 2 支、約 2 秒） |
| 7 | **守衛兌現的是一句散文，而它只兌現得了一部分**（#414：`booktitleCarrierTypes` 的成員資格判準只存在於 doc comment，「不得依性質相似類推第三個」沒有可執行的程序。守衛改成「本表成員不得帶 `editor`」——實測 54 筆成員記錄觸發 0）| ✅ **寫，但明寫它只是必要條件** | 前六列的守衛，通過時至少**指向**它們要證的那個性質；這一列連指都沒指到——它查的是一個**嚴格更弱的命題**。這一列不是——一個不帶 `editor` 的新型別**仍未必**該進表，那一步永遠是人工裁決。所以本列的裁決有兩半：寫（它讓一句空頭承諾變成部分可兌現），**以及在守衛旁邊明寫它兌現不了的那一半**。只做前半會把一個空頭承諾換成另一個——讀者會以為「守衛綠了＝成員資格對了」，而那正是 #414 指出的原病 |
| 8 | **守衛防的是一個當下不可達的狀態**（#416 R1：`errorsFirst` 讓 error 排在 warning 之前，因為 MCP 面截斷 20 則。實測**五族的 error 級 per-record 檢查全部是 key 合法性檢查，而 load 對每族做同樣檢查並 quarantine 整個檔**——那些 error 分支對載入後的記錄結構上不可達，0 實例）| ✅ **寫，但把「為什麼是零」也釘住** | 前七列的零實例都是「那個形狀還沒出現」；這一列是「那個形狀**目前走不到**」——不可達性由**別處的**驗證（load 的 quarantine）造成，而那是我沒有控制、也沒有守衛盯著的東西。所以本列的裁決有兩半：寫那個排序（成本一行，且它一旦可達就是**看不見的漏報**），**以及寫一條測試釘住「現在為什麼是零」**。只做前半的話，日後有人在 `validate()` 加一條非 key 的 error 級檢查，零實例悄悄變成一實例而沒有任何人知道排序守衛從裝飾品變成了承重結構。**前提的失效日期（#554 R6 補記）**：「per-record 的 error 級檢查全是 key 檢查」對 venue／organization **自 #227（authorized ⊆ names）／#422／#473 起就不成立**——那些內容檢查在寫入期、decode 不驗，載入後可達；本列的 pin test `testNoPerRecordErrorIsReachableFromALoadedStore` 只對 entry／person／divergence 改壞 key，證的是「key 錯會 quarantine」而不是這句前提，是弱測試。排序守衛因此早已是承重結構，不是裝飾品；本列的裁決（寫）不變，只是理由的第二半（釘零）從那時起就沒釘住。第 25 列把可達的 error 類別再擴四個並在該列對帳 |
| 9 | **一個零實例的欄位，而缺席會被讀成「不可能」**（#394：`Organization.ror`。實測 8 筆 organization、**0 筆帶 ror**；`Venue.issn` 有 39、`Entry.doi` 有 664，只有 organization 這一格是空的） | ✅ **寫** | **前八列講的都是守衛，這一列講的是欄位**——它不查任何東西，所以「失敗」的意思不同。不寫的代價不是漏報，是**模型會說一句它沒打算說的話**：一個讀者問「Akashic 有沒有模型化機構的識別碼」，會看到 person 有 `orcid`、venue 有 `issn`、organization 什麼都沒有，於是合理推論「機構沒有識別碼可記」。而那是假的——ROR 存在、`identity-is-judged-not-matched` 的封閉例外節具名列了它，我們只是還沒有資料。**缺席在這裡不是中性的，它是一個關於世界的斷言**，而那個斷言是錯的。成本是一個 `ROR?` 欄位（additive，舊 binary tolerant-preserve）|
| 10 | **零實例、成本高，而形狀取決於一個還不存在的用途**（#365：`Author.correspondingAuthor`。APA7 的參考文獻**不印**通訊作者，所以它服務的是 CV 產生或作者查詢——而那兩個功能都不存在。實測 55 筆 work 的作者含 `che-cheng`，而「其中幾筆是通訊作者」在 store 內**不是可求值的命題**） | ❌ **不寫** | **本表第一個「不寫」，而它是本檔自己預測過的**（見下方「還沒出現過的情形」——那段寫著「零實例且成本高的守衛……那一列的理由**很可能是『不寫』**」）。理由不是成本高本身，是**形狀取決於用途而用途不存在**：`Bool` 還是 `Set<index>` 只有那個場景能決定，現在選一個等於用猜的固定一個介面。與第 9 列（`Organization.ror`）的關鍵差別：那一列的**形狀是確定的**（ROR 是純量），缺的只是資料。**觸發條件**（逐字取自 2026-08-28 裁決 §1）：出現第一個需要它的場景（CV 產生器、或一個「我是哪幾篇的通訊作者」的查詢）——那時形狀才能被決定。這一格沒有機械量測，需要人指認 |
| 11 | **零實例、成本高，而既有欄位已經承載它**（#365：`Author.role`。實測 `fields` 的 role 一族恰 **2 筆**（`editor` ×2），其餘八個相關欄位全零；而那 2 筆已由 `fields["editor"]` 承載、#350 已讓 `EDITOR` 在編著作品上滿足 APA7 下限） | ❌ **不寫** | 與第 10 列同為「不寫」而**理由完全不同**：這一列的形狀是確定的，缺的是**理由**——為 2 筆把 `Author` 從 `enum` 改成 `struct`（非 additive、bump store format、**`Sources/` 54 行／26 檔，含 `Tests/` 153 行／64 檔**——量法與重跑指令見表下方；先前寫「46 個呼叫點」而三個來源給出三個數，見 #481）不成比例。**觸發條件可檢查**：`fields` 的 role 一族 ≥ 20 筆，**或**出現一個 role 是 `fields` 承載不了的（同一人在同一篇既是作者又是譯者——那時 `fields["translator"]` 與 `authors` 會各自說一半） |
| 12 | **零實例，而它屬於另一個型別**（#365：`Author.pseudonym`。筆名是「這個人也用那個名字發表」——關於**人**的事實，`PersonNames` 已有可承載它的 `variant` 分區；authorship 側只在「同一人在**不同作品**用不同筆名、且兩個名字都要進各自的參考文獻」時才需要 per-occurrence 的名字選擇，且與 #386 的 per-work judged authorship 是同一個位置。**這一列的零是駁回出來的，不是量出來的**：2026-09-03 實測 865 筆 person 中 **11** 筆有 ≥2 個彼此不同的 confirmed literal（其中 1 筆跨書寫系統：`che-cheng` 的 `Che Cheng`／`鄭澈`），全部可駁回——腳本逐人列出的 literal 顯示 10 組只差縮寫形、標點或大小寫（APA7 的參考文獻本來就把 given name 正規化成首字母，差異活不到輸出），跨書寫系統那筆由 #81 的 `.latn` 裁決吸收；而「兩個彼此無共同 token 的拉丁名」（真筆名的形狀）**0** 筆。量測腳本與清單見表下方） | ❌ **不寫** | 與第 10、11 列同為「不寫」而理由是**第三種：位置錯了**。第 10 列缺用途、第 11 列缺理由，這一列連問題都問錯了型別——把筆名放進 `Author` 會讓「人的名字」這個事實有兩個家（`Person.names` 與每一筆 authorship）。這裡引的是 `entity-backlink-completeness` 的**立場**（《邏輯哲學論》3.325 的工程類比：讓那種分岔在記法裡**寫不出來**）而非它的封閉列舉——那張表管的是關係邊，名字是屬性，所以這是受稽核的類比，不是類推。APA7 對筆名的處置（用出版時的名字、必要時方括號補真名）是**呈現層**規則，讀的是 `Person.names`——它已經有兩個分區可用。觸發條件見情形欄；**這一格沒有機械量測，需要人指認**（store 沒有筆名的表示法，連查詢都寫不出來——與第 11 列不同，那列至少有一個可數的析取項）。觸發時要的是 per-occurrence 的**選擇**（指向 `Person.names` 裡某一個名字的 selector），不是名字的第二份 copy，所以它不製造第二個家；#386 的 `judgeAuthorships` 是同一個位置的先例（per-work 的判定），但它選的是**人**（收 personKey）不是名字——selector 的形狀是觸發時才裁的事。落點在 #386 那一族，不是 `Author.pseudonym` |
| 13 | **零實例，但同族的結構缺口已經出現三次、stale 實際累積過一次——抓到它的三個機制全是場外的，沒有一個是守衛**（#464：死 verdict 掃描。resolution verdict 的 value 指向一個沒有載入的 holder。三個結構缺口：#232 rename／person 側、#271 merge／person 側、#460 venue 側（#460 的 changelog 原話「家族第三個缺口」）；實際量到的 stale 累積只有 #460 那一次（來源是 #456 的攣生合併批次），而抓到它的三個機制全在那一次——205 條 stale 由 #456 pilot 人肉抓、殘留 1 條由 verify lens 全庫掃抓、清理完整性靠 set-difference 腳本**驗**（驗不是抓）。2026-09-03 實測 live store 2,700 條 verdict（confirmed 與 rejected 合計），死引用 **0**。**零有第二個來源**：#463 網格裡還沒補的格——`renameEntry` 沒有 organizations 迴圈——今天沒被走過（organizations 持有的 verdict 只有 9 條、其 holder 沒被 rename 過；verify DA 在副本上 rename 兩次即得 4 條死 verdict）。**該格已於 2026-09-03 由 #463（PR #493）補齊，第二個來源自此消失**——現在的零只剩「清理過之後的零」一個來源。重跑指令見表下方） | ✅ **寫** | 前面各列的零實例都是「這個形狀還沒發生過」；這一列的零是**清理過之後的零**——形狀在 #460 真的發生過（205 條），只是被場外機制（人肉、verify lens、一次性腳本）掃乾淨了，store 裡因此看不到。所以本列的理由不是第 1 列的「不寫就沒有跡象」（跡象有，在 issue 史裡），而是**跡象住在錯的地方**：每一次都要一個人記得去看，而下一條 holder 退役路徑（#463 網格裡還沒補的格）不會有人記得。掃描放進 `StoreHealth` 是把跡象搬到工具會自己看的地方。**severity 是 warning，三個理由，且都是「現在」**：(1) 升 error 會把**第 8 列釘住的零翻掉**——那一列的依據是 per-record 的 error 級檢查全部是 key 合法性檢查、對載入後記錄不可達；死 verdict 若是 error 就是第一個既非 key 檢查又可達的 per-record error，`errorsFirst` 從裝飾品變承重結構，而第 8 列明寫那個轉變不得安靜發生——**本列因此繼承第 8 列的釘零義務**（測試釘住 malformed value 對已載入記錄不可達）。(2) #464 的 Expected 逐字寫「warning 級」。(3) 今天沒有處置命令，升 error 會讓一次合法的 rename 把 `validate` 打紅而修不掉。**不是**「rename 後常態為真」（假：只有 org 持有的那幾條）、也**不是**「rename 本來就全遷」（假：沒有 org 迴圈）——兩句 verify 都量過。#463 補完且有修復路徑後，error 要重開裁決，第 8 列與本列一起改（#463 已於 2026-09-03 補完；修復路徑仍缺，裁決未重開——#464 的 closing summary 記著）。**誠實邊界**：warning 級的 `validate` 對它 exit 仍為 0（DA 實測 5 條死 verdict 仍 exit=0）——它做到「掃得到」、做不到「叫醒」（`blocked-issues-must-be-scannable` 的同一條界線）；CLI 逐行可見、MCP 進 `recordIssues`，App 側欄「記錄」Section 渲染計數（#487，2026-09-04 落地；完整逐行仍是 CLI `validate`）。**觸發條件可檢查（用含這條檢查的 binary，指令見表下方）**：「死 verdict」數應恆為 0；非零時先看 quarantined 清單——被 quarantine 的 holder 是「讀不到」不是「退役」，其餘才指向一條漏了遷移的退役路徑 |
| 14 | **零實例、成本一個掃描，而判準取決於一個還不存在的相等定義**（#464 的第二個掃描項——同一 owner 對同一配對同時持有 `resolution-confirmed` 與 `resolution-rejected`。2026-09-03 實測 live store 以 (檔, holder) 與 (檔, 完整 value) 兩種收攏法各算一次，並存數皆 **0**；追蹤 #486，其 `### Blocking` 記 #470） | ✅ **寫**（2026-09-09 翻轉——觸發條件成立） | 與第 10 列同形——判準取決於一個還不存在的東西——而對象不同：那一列是**形狀**取決於用途，這一列形狀確定（一個並存掃描），是它要比較的**相等**取決於 #470：寫入面位元組精確、讀取面 `NameNormalization.matchingKey` 正規化，兩面今天對同一筆 verdict 答案不同。現在寫任一個，都是在 #470 之前偷偷定案第三份相等定義，裁決後必然分岔（`no-compat-fallback` 記過的形狀）。**本表第一個成本低而「不寫」的列**，理由與成本無關。本列**不取代** #486——「在等 #470」的可掃描位置是那張 issue 的 `### Blocking`，不是這張表（`blocked-issues-must-be-scannable` 的三個位置是封閉列舉）。**觸發條件已成立**：#470 於 2026-09-09 選定相等定義（正規化，且只住在鍵裡），本列依它自己寫下的條件改裁「寫」，在 #486 實作——`StoreHealth.contradictoryVerdictIssues`，warning 級，2026-09-09 實測 live store 仍 **0**。**翻轉的方式本身值得留著**：這一列不是被人想起來才改的，是它自己寫下了一個**機械可檢查**的觸發條件（另一張 issue 的 state），而那張 issue 一 close 就到期。對照第 10、12 列——它們的觸發條件是「出現一個需要它的場景」，沒有任何機制會叫醒任何人 |
| 15 | **零實例，而零是本機的——同一份 store 在別台機器上全是實例**（#453：本機缺承重存檔的掃描。記錄的 provenance 指向一個本機 `sources/` 沒有的 digest。2026-09-04 實測 live store：62 個 digest 引用、41 個 distinct `sha256:`，**本機缺 1 筆**——而那一筆不是缺席，是 divergence `B354B9E9…` 的 `judgement.restsOn` 裝了一個 URL、根本不是 digest（訊息分開說，見 `danglingSourceIssues`）；同一份 store 拿掉 `sources/` 的副本跑同一支 binary：**41 筆**（40 venue ＋ 1 divergence）。兩層盲區都實測為真：`missingSourceDigests` 不掃 venue（#406 起承重證據住在 venue 上）也不掃 `Entry.references`（第 15 條邊）；且它零 production 呼叫端——doctor 接的是 `auditSourceIndex()`，捏造的 digest 在 blob 與 index 兩邊都不在、兩邊一致、audit 說「全部一致」。重跑指令見表下方） | ✅ **寫** | 前面各列的零，成立與否**不取決於在哪台機器上量**；這一列的零**只在這台機器上為真**——`sources/` 不進 git（`replace-endnote-and-zotero` 的承重閘：第三方版權 PDF 住在那裡），所以每一台新 clone 上這個數字都是「全部」。與第 13 列（清理過之後的零）最像而不同：那一列的零是**時間上**的（曾經非零、掃乾淨了），這一列的零是**空間上**的（換一台機器就非零）——而任何只在本機量的守衛都會對它報綠。第 3 列「未涵蓋不得冒充通過」正是 `auditSourceIndex` 的沉默形：沒被檢查與檢查過且乾淨在輸出上相同。**severity 是 warning**：記錄合法可載入、缺的是位元組，而其他 clone 上「全部 dangling」是常態，error 會讓 `hasErrors` 翻紅擋住 export 類流程。**用詞「本機缺」不寫「偽造」**：本機分不出「從未存在」與「沒同步」，訊息把這個邊界說出來。**觸發條件可檢查**（指令見表下方）：本機數字應恆等於「不是合法 digest 的引用數」（今天 1）；多出來的那些指向沒同步的 `sources/` 或真的捏造——先同步，同步後仍在的才是後者 |
| 16 | **零實例，而它守的是一個已裁決「現在不改形狀」的 O(n) 增長**（#499：venue 側 verdict 數逼近 decode 預算的 warning。第 13 條邊在 venue 側是 O(catalog)——`psychological-methods` 2026-09-04 實測 **1,352** 筆 resolution verdict、268 KB；硬預算 200,000 節點、每筆 verdict 量測 9 節點（2026-09-01：14,031／1,556），門檻＝預算一半÷9＝**11,111** 筆。沒有一本刊接近門檻 → 0 實例。使用者裁決（2026-09-04）：候選 3——不改序列化位置、半預算處出聲、達門檻重開裁決；候選 2（sidecar ledger）是那時的形狀。重跑指令見表下方） | ✅ **寫** | 前面各列的守衛守的是「某個形狀出現」；這一列守的是**一條已知會漲、且裁決了暫不改形狀的曲線**——它的零不是「還沒發生」，是「還沒漲到」。不寫的代價與第 1 列同形（撞上硬預算時整檔 quarantine、venue 消失，而在那之前沒有任何跡象），但理由多一層：**裁決本身依賴這個守衛**。候選 3 之所以可接受，是因為「達門檻時重開」被承諾為一個工具會自己看的門檻，而不是散文觸發條件（`blocked-issues-must-be-scannable` 的誠實邊界：散文命題沒有機制會叫醒任何人）。拿掉守衛，裁決就退化成「等它壞」。門檻由量測換算（節點／筆）而不是憑空的數字，`VenueVerdictBudgetWarningTests` 釘住那個換算。**觸發條件可檢查**：任一 venue 的 warning 出現即重開第 13 條邊的規模化裁決，不要只放寬預算 |
| 17 | **零實例，而零的來源是「寫入面剛長出來」**（#450：拆分後錨失效的兩種 warning——某 person／organization 持有的 resolution verdict 其 literal 已被 work 的拆分記錄退役（孤兒 verdict）、拆分記錄各段全不在作者位。2026-09-07 實測 live store：拆分記錄 **0** 筆——#443 已拆的 4 筆「某人與雷庚玲」（store `32916ba`）沒有記錄，因為那時值域還沒有這一格、且 #450 裁決不回填；產生實例的唯一路徑（`splitAuthors` 寫記錄）在本 change 才存在，所以兩種 warning 今天必為零。重跑指令見表下方） | ✅ **寫** | 前面各列的零各有來源——還沒發生（第 1 列）、走不到（第 8 列）、掃乾淨了（第 13 列）、在這台機器上（第 15 列）、還沒漲到（第 16 列）；這一列的零是**形狀已經發生過 4 次、只是沒被記下**——寫入面在本 change 才長出來，實例從第 5 次拆分起才可能出現。不寫的代價與第 1 列同形而更具體：下一次拆分後，一條指向已退役作者位的 `resolution-rejected` 會讓 `resolve-people` 永遠不再提名那一段（否決抑制以 (citekey, literal) 配對），而沒有任何跡象——那正是 `literal-first-then-key` 說的「誤不可逆」在 verdict 側的形。**釘零的方式**：`OrphanedSplitVerdictScanTests.testCleanStoreReportsNothing` 釘住乾淨為零、`testRejectedLiteralLaterSplitIsAnOrphan` 釘住形狀出現即報、`testSameLiteralOnDifferentWorkIsNotAnOrphan` 釘住鍵是 (citekey, literal) 不是 literal。severity 是 warning（處置是人的重新消歧，不是修檔；`validate` exit 仍 0——「掃得到」不「叫醒」，#464 的同一條界線）。**觸發條件可檢查**（指令見表下方）：live store 第一次跑 `--split-author` 之後兩個計數才可能非零；非零時先看孤兒 verdict——那是要人動手的那種，各段全不在只是提醒記錄留著供 un-split |
| 18 | **零實例，而零只存在於「已經進來的資料」上——守衛守的是入口**（#519：`AddOnlyEnrichment` 對單一字串的 65,536 位元組上限。2026-09-08 實測 live store：1,517 筆 abstract，最長 **4,220 bytes**、p99 2,185、中位 1,137；全部 6,125 個 `fields` 值的最長也是同一筆。離上限還有 **15.5 倍**，今日零實例。**但那個形狀已經被造出來過**：#516 verify 用一份 5 MB 摘要走**同一條鏈**實測 RSS 46.6 MB、`proposals.json` 5.0 MB 原樣流進 store 欄位——是上限的 **80 倍**。重跑指令見表下方） | ✅ **寫** | 前十七列的零都是關於**已經在庫裡的東西**——還沒發生（第 1 列）、走不到（第 8 列）、掃乾淨了（第 13 列）、在這台機器上（第 15 列）、還沒漲到（第 16 列）、寫入面剛長出來（第 17 列）。這一列的零**量的是出口，而守衛裝在入口**：store 的最長值是 4,220 bytes，是因為進得來的都小；而這道檢查管的是 adapter **這一次遞過來**的字串，那個長度不受庫內歷史約束。與第 16 列（已知會漲的曲線）最像而不同：**這裡沒有曲線**——實例不會由目錄成長慢慢逼近，它會由一次外部呼叫**一步跨過**，而 #516 verify 已經一步跨過 80 倍。所以「還沒漲到」對它不成立，「還沒發生」也不精確：形狀發生過，只是發生在測試裡而不是 store 裡。**裁決的第二半是語意**：超限**整批拒絕、零寫入、具名，不截斷**——截斷會讓一個不是來源給的值進 store 且不出聲。那一半動到了 `lossless-intake` 的封閉列舉，故該檔在同一輪顯式加了一節「有界拒絕」並寫明它**不是**那張表的第三類（成員資格是「可以丟掉這個欄位、繼續匯入」，而以大小為名的成員會被類推成「太長的欄位可以丟掉」）。**上限值不是挑的，是兩個量出來的錨點夾出來的**：下界是實測最長值的 15.5 倍，上界是 `AliasEventBudget.maxBytes`（**輸入檔**預算 8 MiB）的 1/128 未跳脫、**1/32 已跳脫**（實測 YAML 序列化放大：ASCII／CJK／換行 1.00×、`\t` 2.00×、控制字元 4.00×——單一欄位不會主導整筆記錄的預算） |
| 19 | **零實例，而被守的是「辯護」不是事實**（#479：本表每一列都要在「各列共通的東西」有一條 bullet 講它自己的理由。2026-09-09 實測 22 列全部有**自己的** bullet（判準是「以 `- 第 N 列的理由是` 開頭的行」，不是段落裡任何一次提到 N——那一段到處是跨列比較，鬆的判準讓拿掉某列的 bullet 也不會紅，實測過）；20 條 bullet 涵蓋 22 列，一條可涵蓋多列（「第 10、11、12 列的理由是三個**不同的**…」），所以判準是**每個列號至少被引用一次**而非「bullet 數等於列數」；未被引用的列 **0**。重跑指令見表下方） | ✅ **寫** | 前十八列守的都是**可判定的性質**——欄位在不在、數字對不對、檔案存不存在、記錄形狀合不合法。這一列守的是**這張表存在的理由本身**：表是規格，理由欄是它的辯護，而共通段是那個辯護的第二層（它說明每一列的理由**彼此不同**，那正是本檔不寫總括判準的依據）。**少一條 bullet 不會讓任何檢查變錯**——沒有任何數字會偏、沒有任何斷言會紅——它只會讓下一個人拿判準去類推，而那是本檔開宗明義禁止的動作。所以這一列的失敗不是「漏報」也不是「假訊號」，是**規格的辯護少了一角而規格本身看起來完好**。漂移真的發生過：第 12 列的裁決 2026-08-28 就下了，2026-09-02 才補進表，中間五天表與裁決不同步（只是當時漂的是列不是 bullet）。**觸發條件可檢查**（指令見表下方）：未被引用的列數應恆為 0 |
| 20 | **零實例，而作者對同一形狀的窮舉自己漏了一格**（#526：workflow 的 `run:` 跑一支不存在的腳本。#521 的四個實例裡**有兩個**是這個形狀——`census-parity.yml` 與 `ci.yml` 各跑一支在 `989ac64`（#433「Python 歸零」）刪掉的 `.py`——而**實例 4 是 verify 席找到的**：當時的封閉列舉漏了它。2026-09-09 實測 live repo：2 個 workflow 檔、**5** 個腳本引用、不存在 **0**。重跑指令見表下方） | ✅ **寫** | 前十九列的零各有來源——還沒發生（第 1 列）、走不到（第 8 列）、掃乾淨了（第 13 列）、在這台機器上（第 15 列）、還沒漲到（第 16 列）、寫入面剛長出來（第 17 列）、量的是出口（第 18 列）。這一列的零是**剛剛被人工修完的**，而修它的那一輪自己證明了人工窮舉不可靠：四個實例裡第四個是**別人**找到的，且它與前三個形狀完全相同。所以理由不是第 1 列的「不寫就沒有跡象」（跡象有，就在同一張 issue 裡），也不是第 13 列的「跡象住在錯的地方」（它就在眼前）——是**看過了、看的是對的地方，仍然漏了一個**。守衛換掉的不是人的注意力，是「這件事需要注意力」這個前提。後果不對稱使它值得：一個掛掉的 step 會擋住其後**全部**步驟，`ci.yml:94` 那次擋掉的包含 AkashicApp（`swift test` 涵蓋不到的那塊，#101 的立案理由）。**它刻意不住在 `trigger-coverage` 裡**——併進去實測讓該支的 mutation harness **5 個既有 case 同時失敗**：那些 case 刻意在 workflow 注入指向不存在腳本的假命令（`plugin/tests/DELETED-numbers-audit.py`）來測 `invoked()` 的剖析，而本檢查會如實報那些引用。一支守衛的 harness 偽造某種內容，另一道檢查又對那種內容做存在性斷言，兩者永久互相干擾。**觸發條件可檢查**（指令見表下方）：「不存在」應恆為 0；非零時那個 step 已經是壞的，修路徑或刪 step，不要放寬檢查 |
| 21 | **零實例，而既有守衛的謂詞對這一類成員結構上不可能為真**（#522：受保護清單少了成員。`trigger-coverage` 的 `missing` 問的是「清單裡列的路徑還在不在磁碟上」——而 **glob 產生的成員永遠不會「列了卻不存在」**，它只會停止被列出。2026-09-09 實測三組：刪一整支守衛、刪一條 glob 規則檔、拿掉一條顯式 `DATA` 條目（重編 binary 後），**三組全部 rc=0 並印「無缺口」**。棘輪落地後三組皆 rc=1 具名；當下棘輪與清單相符、差異 **0**。重跑指令見表下方） | ✅ **寫** | 前二十列的零都是關於「**還沒有**這個守衛」——沒發生、走不到、掃乾淨了、在這台機器上、還沒漲到、寫入面剛長出來、量的是出口、窮舉漏了一格。這一列不同：**守衛在，而且天天跑，只是它的謂詞對 58 個成員裡的 **37** 個永遠不可能為真（glob 與 `swiftGuards()` 衍生的那些；顯式字面 21 個，量法見表下方）**。它不是漏看，是問了一個那一類成員答不錯的問題。所以理由既不是「缺跡象」（第 1 列）也不是「跡象住在錯的地方」（第 13 列）——**跡象根本無法產生**。**它刻意不住在 `trigger-coverage` 裡**，理由同第 20 列（那支的 mutation harness 會偽造它要檢查的內容）；清單則來自**同一個** `protectedInventory()`——一個自己算一遍的棘輪只會證明它自己與自己一致。**為什麼不是「把 glob 換成顯式清單」**（issue 列的另一個候選）：顯式條目今天 19/19 由 `missing` 逐條具名，但換掉之後**忘記加新規則檔是靜默的**，同一個失效換一步，而規則檔正是本 repo 承載裁決的地方。**為什麼它不是 #518 記過的「第 N 份副本」**：那次的缺陷是複製清單與 `DATA` 之間沒有東西在對帳，而棘輪整個存在理由就是被對帳——同形先例是 `hash-table-drift.sh`（生成表的漂移守衛）。**觸發條件可檢查**（指令見表下方）：差異應恆為 0；非零時先讀是「少了」還是「多了」——前者確認刪檔是有意的，後者確認新成員真的有讀者（往已在 CI paths 的路徑根加零讀者的檔可以零成本灌水） |
| 22 | **零實例，而它是一條 spec Requirement 不是程式**（#474：venue 的 `names` 時間軸——刊名沿革。#422 把它保留而收窄（`variant` 不得帶時間），於是沿革成了一個「保留位置」的形狀。2026-09-09 實測 live store：venue **406** 筆、`names` 帶任一時間欄位（`start`／`end`／`ended-unknown`／`attested`）的 **0** 筆。重跑腳本見表下方） | ✅ **保留** | 前二十一列講的都是**程式**——守衛（第 1–8、13、15–18、20、21 列）與欄位（第 9–12、14、19 列）。這一列講的是 **spec 裡的一條 Requirement**，而它的失敗方式是第三種：守衛失敗是**漏報**、欄位缺席是**模型說了一句它沒打算說的話**，而一條零實例的 Requirement 的失敗是——**有人把它當死重刪掉**（「405 筆沒有一筆用到，留著幹嘛」），然後那個形狀到達時沒有位置可落。**保留而不刪的理由是那個現象是真的**：JRSS Series B／C 的分裂、`bulletin-of-the-institute-of-mathematics-academia-sinica` 的新舊系列都是 store 今天**表達不了**的實例（`entity-backlink-completeness` 的「分裂／繼承」那一節記著同一組例子）。**零實例的成因也具名**：異寫法佔著它的位置——#422 之前 `names` 時間軸同時裝沿革與異寫，收窄之後異寫搬到 `variant`，而沿革還沒有人填。**觸發條件可檢查**（指令見表下方）：帶時間欄位的 venue 數 > 0 即代表沿革開始被用——那時第 16 列（venue verdict 預算）與 `which-side-does-a-relation-live-on` 的「分裂／繼承」觸發條件 ② 也一起到期，三處要一起讀 |
| 23 | **零實例，而製造它的那條路徑是本輪自己開的**（#457：移除記錄與作者位互相矛盾——某 work 帶一筆「移除：理由」說某個 literal 已退役，而它現在又在作者位上。2026-09-09 實測 live store：移除記錄 **0** 筆——寫入面（`--drop-author`）在本 change 才存在，所以矛盾今天必為零。重跑指令見表下方） | ✅ **寫** | 第 17 列的零也是「寫入面剛長出來」，而這一列多一件事：**矛盾的可達路徑是本 change 自己造出來的**。移除之後 `authors` 變成**空的**，而 `enrich --include-absent-authors` 的既有契約正好是「只在 authors 完全為空時補」——於是同一個字串補得回去，那時 store 同時斷言「它已退役」與「它是作者」。所以這不是「還沒發生的形狀」，是**新面把一個原本不可達的狀態變成可達**，而讓它可達的那一步與守衛必須在同一個 change 裡（`entity-backlink-completeness` 引 3.325 的立場：矛盾寫不出來最好，寫得出來就要出聲）。與第 8 列成鏡像：那一列的零由**別處的**程式（load 的 quarantine）造成、可能被改掉而沒人知道；這一列的零由**本 change 之前沒有這個面**造成，而面已經有了，所以零是暫時的。severity 是 warning（記錄合法，失效的是證據錨——同 `staleSplitRecords` 的既有分級；`validate` exit 仍 0）。**觸發條件可檢查**（指令見表下方）：計數應恆為 0；非零時先確認是不是補值面把它加回來的——要嘛再移除一次，要嘛刪掉那筆記錄，不要兩者並存 |
| 24 | **零實例，而它是一條「記得起來、解不掉」的半吊子管線——且零是雙重的**（#555：organization 的攣生合併。`recordDivergence` 的 `byShape` 收 org、`resolveDivergence` 對它擲 `unsupportedShape`。2026-09-11 實測 live store：organization **13** 筆、寬鬆共鍵的重複群 **0** 組、含 org 候選的 divergence 記錄 **0** 筆——沒有重複可合、也沒有人記過。另有 **3** 筆帶 `parents` 時間軸，那是 venue 合併沒有的問題（部分—整體關係怎麼併，`Organization.swift:84-88` 明寫它與 person 的隸屬是不同的 predicate）。重跑指令見表下方） | ⚠ **暫不做——既不實作也不拿掉** | 前二十三列的裁決都是「寫」或「不寫」某個東西；這一列裁決的是**對一個已存在的半吊子什麼都不動**，而那之所以可接受，理由是第四種：**它已經誠實了**。#553 把 `unsupportedShape` 的訊息改成從實際支援的清單生成（「organization 的合併管線尚未實作——支援的是 person／work／venue」），所以留著它的代價是零——使用者撞到時看到的是真話。而動它的兩個方向代價都不是零：**實作**要替 `parents` 時間軸設計合併形狀，零實例時做等於猜（同第 10 列「形狀取決於一個還不存在的用途」）；**拿掉**（`byShape` 移除 org）會連記錄面一起關——`record-divergence` 是「當場記錄而非當場判斷」（#77），關掉它等於斷言 org 永遠不會有需要延後判定的歧異，那是關於世界的斷言。**一個誠實的半吊子比一個猜出來的完整更好。** 與第 8 列（零的來源在別處）最像而不同：那一列的零由另一段程式造成、可能被改掉而沒人知道；這一列的零由 org 域剛重啟（#304）造成，而 `bootstrap-organizations` 今天 0 候選——零會不會被打破取決於使用量，不取決於任何程式。**觸發條件可檢查**（指令見表下方）：org 重複群 > 0 **或** 出現第一筆含 org 候選的 divergence 記錄——任一成立即重開，那時要選的是實作或拿掉，不再是暫不做。**若實作，`doomedRelativePaths`／`holderRelativePaths` 的 org 分支要同批補**（#558 對 venue 漏掉的正是這兩格）|
| 25 | **零實例，而實例全部是在 verify 裡被造出來的——守衛裝在 store 邊界，零量的是五個寫入者的出口**（#554 R5，使用者裁決 D8：venue 名字內容的不變式——canonical 形、無控制／格式／不可見字元、至少一個字母或數字、三張清單各無近重複對（names 的例外：兩段都帶不相交時間的沿革改回舊名，R6）——住在 `Venue.validate()`，error 級；謂詞一份在 `NameIdentity.wellFormednessIssue`、與輸出閘 `UnsafeToEmitScalar` 共用危險 scalar 的定義，「不可見」用 Unicode 的 `Default_Ignorable_Code_Point`（R6；R5 用 generalCategory 四類，VS16／CGJ 是 Mn、Hangul filler 是 Lo，全放行），ZWJ／ZWNJ 只在兩個脈絡合法——(a) 掛在同一文字**字母**上的 virama 之後（virama 與中間的標記都是基底那個文字的；右鄰居若在要是同一文字的字母／數字，空白視同沒有）、(b) 左鄰居是 join-control 文字的字母／標記／數字、右鄰居是**同一文字**的字母／數字或同一 Indic 文字的 virama（R6；R5 的「兩側是字母」對拉丁字母 fail-open；R7 再收區塊裡的標點與連續 joiner——R6 verify 第 1／19 列；R8 再收基底要是字母、兩側同文字、右側不收標記——R7 verify 第 1／26／33 列；R9 再收 virama 與標記要與基底同文字、放行詞尾 chillu 後的空白與 Bengali ya-phalaa 的 `<RA, ZWJ, VIRAMA, YA>`——R8 verify 第 6／10／11 列，D21／D22；R10 再收 virama 之前的 joiner 只在 Devanagari／Bengali 且 virama 之後要接同文字的字母——R9 對十個 Indic 文字一起放行且不看右脈絡，`क\u{200D}\u{094D}` 與 `क्` 渲染相同而各自進得了 names，R9 verify DA 第 10 列，D26），U+2800 顯式列入不可見（第 20 列）。2026-09-12 實測 live store：venue **485** 筆，四條不變式的違反字串 **0**、names 近重複對 **0**；而 R2–R5 四輪 verify 用真 binary 寫進了 `\r`／`\n`／LS／`—`／`×`／RLO／ZWSP／ALM／TAG 字元／尾隨空白／NFD 位元組／拉丁字母夾 ZWNJ／VS16／CGJ／Hangul filler——每一個都是實例，只是發生在 scratch store 而不是 live store。重跑腳本見表下方） | ✅ **寫（error 級、在 store 邊界）** | 第 18 列的理由是「零量的是出口而守衛裝在入口」；這一列多一件事：**入口有五個**（`updateVenue` 的三個名字迴圈、`addVenue`、`VenueBootstrap`）。R2→R4 三輪把閘裝在 `updateVenue` 的三個迴圈裡，每一輪都修在看見的那一圈，R4 verify 指出同一欄位還有 `addVenue`（連空字串都收）與 `VenueBootstrap`（只 trim）——`Venue.swift` 自己的 dated-variant 守衛 doc 早就寫著「守衛住在 validate → writeVenue 的交會處才擋得住所有路徑」。所以本列的裁決有兩半：**寫**（零實例但實例已被造出四次），**以及寫在 store 邊界而不是任何一個寫入面**——寫入面（`vetVenueNames`）留作入口的好訊息，不再是防線。**severity 是 error** 而非 warning，理由是 live store 0 筆違反（提級不拒絕任何既有記錄——但別的 clone 若持有手改的記錄，`akashic validate` 對它會 exit 1）且違反的後果是 displayName 直接壞掉（`displayName` 讀 `authorized`，#475）。**這與第 8／13 列的前提要對帳**（R5 verify 第 12 列）：那兩列說「per-record 的 error 級檢查全是 key 檢查、對載入後的記錄不可達」——**對 venue／organization 自 #227（authorized ⊆ names）／#422（帶時間 variant）／#473（孤兒 variant）起就已為假**：venue 的內容檢查全在寫入期、decode 不驗，所以載入後可達、`StoreHealth.perRecordIssues` 收得到；第 8 列的 pin test 只對 entry／person／divergence 改壞 key，證的是「key 錯會 quarantine」，不是那句前提。本列不翻第 8 列的裁決（`errorsFirst` 的排序仍是對的），只把那句前提的失效日期寫出來——它在本列之前就失效了，本列把可達的 error 類別從三個擴到七個。**誠實邊界**：不變式的 NFC 對 CJK 相容表意文字有損（U+FA10 塚 → U+585A）——位元組層有損、Swift 層無損（Swift `==` 早已視為相等）；ZWJ／ZWNJ 保留但只在 `NameIdentity.joinerIsLegal` 的兩個脈絡；DI 一律拒等於拒掉 IVS／蒙古文 FVS／希伯來 CGJ 等真實正字法用字——fail-closed、零實例、Claude 代裁 D9 的取捨，寫在 §5.7 誠實邊界（R6 verify 第 5／23 列）；私用區（Co）不擋，因為 doc 從未宣稱它；`canonical` 只丟 `White_Space` scalar、不刪任何其他 scalar（R6——R5 在 Character 上切，「空白＋combining mark」整個 cluster 被刪）。**觸發條件可檢查**（指令見表下方）：`akashic validate` 對 venue 的名字內容 error 應恆為 0；非零時那筆是手改或舊 binary 寫的，修法是人改 YAML（同 dated-variant 的立場，不猜、不靜默修；訊息自 R6 起逐條說改什麼） |
| 26 | **零實例，而它守的是三個閘共同的前提——閘擋工具面、守衛掃非工具面**（#554 R10 verify 第 2／5／10 列，Claude 代裁 D28：同一 work 兩條 key 邊指同一 venue。D25（repoint／demote 拒）、D27（repoint 後不得出現）、D28（apply 不得造出）三個閘守的都是「配對只由一條邊實例化」，而 store 另有手改與舊 binary 兩個寫入者不經任何閘；R10 verify 用真 binary 三次造出這個形（`apply` 兩條同刊名的 literal 邊、`repoint` 改指到本 work 已有邊的 venue），`validate`／`doctor`／App 全綠，使用者直到想 demote 才知道。2026-09-14 實測 live store：2,411 筆 work、同 venue 兩條 key 邊 **0**。重跑腳本見表下方） | ✅ **寫（warning 級、在 `Entry.validate()`）** | 第 25 列的理由是「入口有五個」而守衛裝在 store 邊界；這一列的入口在 R11 之後只剩**不經工具的兩個**（手改、舊 binary）——venue 合併**不是**入口（`resolveVenueDivergence` 對改指倖存者的 key 邊去重；R11 verify DA 第 14 列真 binary 造出的是另一個形：合併後一條 literal 邊指向 work 已 key 的 venue，它不造出重複的 key 邊，由 D33 的逐筆略過處理、提名照常；反方向倒是真的——它對 entry 的 key 邊去重時會把與被併鍵無關的既有重複 key 邊一併收成一條，是 #572 落地前唯一的移除面，R12 verify logic 第 38 列），而那兩個正是閘擋不到的。**守衛與閘是同一條不變式的兩半**：閘讓工具面造不出這個形，守衛讓已經在庫裡的看得見——少了守衛，D25 的拒絕就是使用者第一次知道自己的 store 走進這一格的時刻，而那時他要做的操作已經被擋。**severity 是 warning**，理由與第 13 列同型：記錄合法可載入（兩條邊各自指向存在的 venue），失效的是判定逆轉的前提；升 error 會讓一筆只能手改才修得好的 work 擋住自己所有的寫入，而處置面還不存在（#572）。與第 23 列（可達性是本 change 造出來的）成鏡像：那一列是新面讓不可達變可達、守衛與面同批；這一列是新閘讓可達變**不可達**（對工具面），守衛守的是關掉之前寫進去的與繞過工具寫進去的。R15 起有家族前綴（`Entry.duplicateVenueEdgePrefix`）、`StoreHealth.duplicateVenueEdges` 計數（doctor／App 各一格）、每筆 work 最多列 20 個 venue（第 27 列同一批，R14 verify regression 第 22 列、security 第 18 列）。**觸發條件可檢查**（指令見表下方）：計數應恆為 0；非零時先看那筆是不是 R11 之前的 binary 寫的（`apply` 的兩次歸戶）——修法是刪掉多餘的邊，#572 落地前只能手改 YAML |
| 27 | **零實例，而它是同一句不變式的另一半——第一半的守衛結構上照不到它**（#554 R13 verify DA 第 16 列，Claude 代裁 D36：同一 (venue, work) 上 ≥2 個正規化後不同的 confirmed literal。§3.5 把配對唯一性寫成一句 normative 的兩半，第 26 列守的是第一半（work 的邊），第二半住在 venue 的 references 上——`Venue.validate()` 不掃 verdict 配對、`StoreHealth` 沒有對應項，全樹「個不同的 confirmed literal」只出現在 `confirmedLiteral` 的**拒絕訊息**，零 validate／doctor 呼叫端。而真正造出第二半的路徑（work 合併把兩筆 work 的邊連同 verdict 併到一筆——R13 verify DA 第 3 列純工具面重現：`--apply` 兩個刊名變體 ＋ `resolve-divergence`）結構上**不會**點亮第一半的燈：被併 work 連同它的邊一起刪掉，倖存者只剩一條邊，validate 零診斷、`--demote` 撞 D23。2026-09-15 實測 live store：venue **485** 筆、對同一 work 持 ≥2 個正規化後不同 confirmed literal 的 **0** 筆。重跑腳本見表下方） | ✅ **寫（warning 級、在 `Venue.validate()`）** | 第 26 列的理由是「閘與守衛是同一條不變式的兩半」——閘擋工具面、守衛掃非工具面；這一列是**同一條不變式的另一半要有自己的守衛**：兩半在偵測面上互斥（造出第二半的路徑不點亮第一半的燈），所以第 26 列的量測「應恆為 0」只兌現了一半，而本檔自己的紀律是「寫出條件而不是只寫數字」。裁決有兩半：寫（零實例但實例已在 verify 裡被造出、且 R14 之前純工具面造得出），**以及不改成只修散文**——DA 給的另一個出口是把 §3.5 那句改成「第二半今天沒有掃描面」，那等於把一個已知可達的狀態留在「只有 demote／repoint 撞上時才知道」。**severity 是 warning**，理由與第 26 列同型：記錄合法可載入，失效的是判定逆轉的前提（D23 從此拒那筆 work 的 demote／repoint）；處置是手改 YAML 留一筆，#572 落地前沒有工具面，升 error 會讓一筆只能手改才修得好的 venue 擋住自己所有的寫入。**鍵不是一把是兩把，掃描兩類都掃**（R15，Claude 代裁 D39；R14 verify Codex 第 3 列、requirements 第 5 列：R14 寫「鍵與 D23／`verdictEqualityKey`／#486 同一把（`matchingKey`）」——假的，D23 的拒絕（`confirmedLiteral`）比**位元組**，只差大小寫或 NFC 形的兩筆 confirmed 讓 demote／repoint 必拒而 R14 的掃描零診斷）：以位元組相異的 confirmed 分組，正規化後不同＝不變式的違反、只差位元組＝重複的判定記錄（工具面以 `verdictEqualityKey` 去重、寫不出它），兩類同一家族前綴（`Venue.confirmedLiteralAmbiguityPrefix`）、措辭分開；`StoreHealth.confirmedLiteralAmbiguities` 有計數（doctor／App 各一格——R14 verify regression 第 22 列：兩族 per-record warning 沒有家族，MCP 截 20 則、App 預覽 5 則時可能完全看不到）；每筆 venue 最多列 20 筆 work、其餘一句概括（第 16／18 列：讀取路徑上對未信任內容跑，鄰居剛為此加了上限）。**生產端自 R15 起三個面都 fail-closed**（D38；R14 verify Codex 第 1 列 HIGH：D34 只裝在合併路徑，apply／repoint 對「目的 venue 已對該 work 持有另一個 confirmed literal、沒有對應的邊」的形照寫）：`apply` 對它逐筆略過並具名（`skippedConflictingConfirmedLiteral`）、`repoint` 對預測後的 verdict 集合驗、整批拒絕零寫入。**R16（R15 verify 30 列，6 席齊）**：「位元組」要真的是位元組——R15 的去重寫 Swift `==`（canonical equivalence），NFC／NFD 的兩筆被收攏成一筆、兩類 warning 都不出而 D23 照拒（requirements 第 1 列 HIGH；D42 改 `Set<[UInt8]>`，與 `confirmedLiteral` 同一把、O(N)）；混合情形（三筆裡兩筆只差位元組）第一類訊息點名那一組（第 23 列）；概括句不進家族（DA 第 29 列：帶家族前綴時 `StoreHealth` 把它算成一則，25 筆 work 報 21——改用 `Entry.perRecordCapSummaryPrefix`）；生產端的閘也比位元組、同一 literal 的另一個拼法也略過／拒（D43，Codex 第 3 列 HIGH：放行同鍵異拼法之後 demote 還回舊拼法）、apply 的閘移到重複邊檢查之後（D44，regression 第 2 列 HIGH）。**R17（R16 verify 31 列，6 席齊）**：合併是第三個會動到同一批 verdict 的面——收攏的勝者政策在拼法位元組不同時改由倖存配對自己的那筆勝、收攏列印兩個拼法（D47，DA 第 1 列 HIGH；#468 的弱血統優先只在同拼法時適用）；近重複組上限只數真的出聲的組（D48，DA 第 2 列 HIGH：21 組合法沿革曾被判 error、所有寫入面關門）；D43 訊息兩桶同時說（D50）；混合註記截在 5 組時揭露；第 27 列量測段的 grep 註記改成它量的單位。**觸發條件可檢查**（指令見表下方）：兩個計數應恆為 0；非零時那筆是 R14 之前的 work 合併、手改或舊 binary 寫的——修法是刪掉不屬於那條邊的 confirmed verdict |

新增下一個零實例守衛 = 在這張表加一列。

**第 12 列的零是駁回出來的——量測腳本**（2026-09-03，`~/.akashic/entities`）。第一行印 person 總數與三個計數，對應第 12 列情形欄的 865／11／1／0（有 ≥2 個不同 confirmed literal 的 person、其中跨書寫系統的、其中有兩個彼此無共同 token 拉丁名的）；接著逐人列出那些 literal，**駁回理由要拿這份清單逐筆核對**（實跑：10 組只差縮寫形、標點或大小寫，1 組跨書寫系統）。「拉丁名」的判準寫在腳本裡（至少一個字母，且每個字母的 Unicode 名稱都以 LATIN 開頭——漢字、假名、諺文、西里爾都不算；不要求 ASCII、不靠 code-point 範圍）。這個判準改了兩次：第一版只排除 CJK，會把其他書寫系統當拉丁名、空 token 會誤算「無共同 token」（Codex R2 抓到）；第二版要求至少一個 ASCII 字母且只認部分拉丁區塊，`É` 單獨會被判非拉丁、`[À-ɏ]` 範圍含 `×`／`÷`（Codex R3 抓到）。三版在 live store 上都得同一組數——邊界案例目前沒有實例，但判準要與散文說的一致：

```bash
python3 - <<'EOF'
import glob, io, re, os, collections, unicodedata
root = os.path.expanduser('~/.akashic/entities')
people = 0
lits = collections.defaultdict(set)
for f in glob.glob(root + '/*.yaml'):
    t = io.open(f, encoding='utf8').read()
    if not t.startswith('person:'): continue
    people += 1
    key = re.search(r'^key: (.+)$', t, re.M).group(1).strip()
    for m in re.finditer(r'^\s*- field: resolution-confirmed\n\s*value: (.+)$', t, re.M):
        v = m.group(1).strip().strip('"\'')
        if ' :: ' in v: lits[key].add(v.split(' :: ', 1)[1])
multi = {k: sorted(v) for k, v in lits.items() if len(v) >= 2}
# 拉丁名 ＝ 至少一個字母，且每個字母的 Unicode 名稱都以 LATIN 開頭（漢字、假名、諺文、西里爾、阿拉伯……都不算；
# 不要求 ASCII、不靠 code-point 範圍——範圍會漏掉後面的拉丁區塊、也會把 × ÷ 當字母）
def is_latin_letter(c): return c.isalpha() and unicodedata.name(c, '').startswith('LATIN')
def latin(s): return any(c.isalpha() for c in s) and all(is_latin_letter(c) for c in s if c.isalpha())
def toks(s):
    out, cur = set(), ''
    for c in s.lower():
        if is_latin_letter(c): cur += c
        elif cur: out.add(cur); cur = ''
    if cur: out.add(cur)
    return out
cross = sorted(k for k, v in multi.items() if len({latin(x) for x in v}) > 1)
disjoint = sorted(k for k, v in multi.items()
                  if any(latin(a) and latin(b) and toks(a) and toks(b) and not (toks(a) & toks(b))
                         for a in v for b in v if a < b))
print(f'person={people} multi={len(multi)} cross={len(cross)} disjoint={len(disjoint)}')   # 2026-09-03：865 11 1 0
for k in sorted(multi): print(' ', k, '|', ' / '.join(multi[k]))
print('cross:', cross); print('disjoint:', disjoint)
EOF
```

**第 13 列的量測（2026-09-03，可重跑，且自證）**：死 verdict 數 `grep -a -q '死 verdict' "$(command -v akashic)" && akashic validate 2>&1 | grep -c '死 verdict'`（應印 0；**沒印任何東西＝你的 `akashic` 是沒有這條檢查的舊 binary**——verify 實測 PATH 上的 `~/bin/akashic` 就是這樣：對一份真有 5 條死 verdict 的副本它回 0、`.build/debug/akashic` 回 5。「沒被檢查」與「檢查過且乾淨」在輸出上不可區分，第 3 列的理由）；verdict 總數 `grep -h 'field: resolution-' ~/.akashic/entities/*.yaml | wc -l`（2,700，含 confirmed 與 rejected）。第一版寫 2,698 並附 owner-kind 拆分——那是用單行正則掃出來的，漏掉兩筆被 YAML 折行的長 value；grep 的數才是可重跑的，拆分不承載裁決、不列。

**第 15 列的量測（2026-09-04，可重跑）**：本機缺承重存檔數 `akashic validate 2>&1 | grep -c '本機缺承重存檔：'`（用含這條檢查的 binary——同第 13 列的自證：舊 binary 印不出東西，「沒被檢查」與「檢查過且乾淨」在輸出上不可區分；2026-09-04 實測 1，且那一筆是 URL 不是 digest）；distinct digest 引用數 `grep -ohE 'sha256:[0-9a-f]{64}' ~/.akashic/entities/*.yaml | sort -u | wc -l`（41）；「其他機器上會是多少」的下限＝把 `sources/` 排除後複製一份再跑同一支 binary（41，全部 venue 加那筆 divergence）。**#507 落地後**（2026-09-04）那筆 URL 已補存 landing page 並改成 digest，本機重跑為 0。

**第 16 列的量測（2026-09-04，可重跑）**：warning 數 `akashic validate 2>&1 | grep -c 'venue 的 verdict 數逼近'`（應為 0）；最大刊的 verdict 數 `grep -c 'field: resolution-' ~/.akashic/entities/<psychological-methods 的 uuid>.yaml`（1,352；找 uuid 用 `grep -l '^key: psychological-methods' ~/.akashic/entities/*.yaml`）；門檻 `AliasEventBudget.venueVerdictWarningThreshold`（11,111＝200,000÷2÷9）。

**第 19 列的量測（2026-09-09，可重跑）**：未被 bullet 引用的列數應為 0——`akashic-guards zero-instance-rows-audit 2>&1 | grep -c '沒有任何 bullet 講它'`（用含這條檢查的 binary；同第 13 列的自證，舊 binary 印不出東西）。手算對照：

```bash
python3 - <<'EOF'
import io, re
t = io.open('.claude/rules/zero-instance-guards.md', encoding='utf8').read()
rows = [int(n) for n in re.findall(r'^\| (\d+) \|', t, re.M)]
i = t.index('## 各列共通的東西'); sec = t[i:]
cited = set()
for m in re.finditer(r'^- 第 ([0-9、]+) 列的理由是', sec, re.M):   # 與守衛同一條規則
    cited.update(int(x) for x in m.group(1).split('、') if x.isdigit())
print(f'表列數 {len(rows)}  未被引用 {sorted(set(rows) - cited)}')
EOF
# 2026-09-09：表列數 19  未被引用 []
```

**第 11 列的量測（2026-09-09 重量，可重跑）**——**三個來源曾給出三個數**（issue body 90/14、裁決 comment 46/27、2026-09-03 verify 99 行／28 檔），而三者都沒寫**量法**，所以無從收斂。這裡把量法釘死：

```bash
# 量法：型別名 `Author` 的出現。`enum → struct` 是型別形狀的改變，
# 每一個提到這個型別的地方都可能要動（宣告、pattern match、建構、簽章）。
grep -rhoE '\bAuthor\b' Sources/ --include='*.swift' | wc -l          # 54  行
grep -rlE  '\bAuthor\b' Sources/ --include='*.swift' | wc -l          # 26  檔
grep -rhoE '\bAuthor\b' Sources/ Tests/ --include='*.swift' | wc -l   # 153 行（含測試）
grep -rlE  '\bAuthor\b' Sources/ Tests/ --include='*.swift' | wc -l   # 64  檔（含測試）
```

**不能用 `case .key`／`case .literal`／`case .organization` 數**（那大概是先前某個數字的來源）：實測 **五個** enum 共用這些 case 名——`Author`、`VenueRef`、`Organization` 的 ref、`OrgResolver` 的、以及 `AkashicProposition` 的 `EntityRef`。那樣數會把另外四個一起算進來（實測 102 行／29 檔，高估近一倍）。

**編譯器的精確值拿不到（誠實邊界）**：給 `Author` 加一個 case 再 build 是最精確的量法，但 SwiftPM **在第一個失敗的 module 就停**——實測只看得到 `AkashicCore` 的 2 個 exhaustive-switch 錯誤，下游 module 根本沒編到。要真值得逐 module 迭代修補再重編，那是另一件事。上面的文字量法是可重跑、可否證的替代，**不宣稱它等於編譯器的答案**。

**第 18 列的量測（2026-09-08，可重跑）**：上限值 `AddOnlyEnrichment.maxValueBytes`（65,536）；庫內最長值——**必須用 YAML 解析器，不能用行為單位的 grep**（長 value 會被折行，本檔第 13 列的量測就踩過同一個坑）：

```bash
python3 - <<'EOF'
import glob, io, os, yaml, collections
root = os.path.expanduser('~/.akashic/entities')
absn, alln = [], []
for f in glob.glob(root + '/*.yaml'):
    try: d = yaml.safe_load(io.open(f, encoding='utf8'))
    except Exception: continue
    if not isinstance(d, dict): continue
    for k, v in (d.get('fields') or {}).items():
        if not isinstance(v, str): continue
        alln.append(len(v.encode('utf8')))
        if k.startswith('abstract'): absn.append(len(v.encode('utf8')))
absn.sort(); alln.sort()
p = lambda L, q: L[min(len(L)-1, int(len(L)*q))] if L else 0
print(f'abstract n={len(absn)} p50={p(absn,.5)} p99={p(absn,.99)} max={absn[-1]}')
print(f'全部 fields 值 n={len(alln)} max={alln[-1]} → 餘裕 {65536/alln[-1]:.1f} 倍')
EOF
# 2026-09-08：abstract n=1517 p50=1137 p99=2185 max=4220 ／ 全部 n=6125 max=4220 → 15.5 倍
```

守衛本身是否在跑（自證，同第 13 列的形狀——舊 binary 印不出東西）：

```bash
python3 -c "import json;print(json.dumps([{'citekey':'x','fields':{'abstract':'a'*65537}}]))" > /tmp/over.json
akashic enrich --library <某個 store> --from /tmp/over.json --json 2>&1 | grep -c '超過上限'   # 應為 1
```

**第 17 列的量測（2026-09-07，可重跑）**：兩種 warning 數 `akashic validate 2>&1 | grep -c '拆分後的孤兒 verdict'` 與 `akashic validate 2>&1 | grep -c '拆分記錄的各段都已不在作者位'`（應皆為 0；用含這條檢查的 binary——同第 13 列的自證，舊 binary 印不出東西）；拆分記錄數 `grep -c '^  *- field: authors$' ~/.akashic/entities/*.yaml | awk -F: '{s+=$2} END {print s}'`（0——#443 已拆的 4 筆沒有記錄，不回填）；那 4 筆的下落 `grep -l '雷庚玲' ~/.akashic/entities/*.yaml | wc -l`（4 個檔含該姓名，其中的拆分無記錄可機械辨認）。

**第 20 列的量測（2026-09-09，可重跑）**：`akashic-guards workflow-run-scripts`（rc=0 時印
「workflow `run:` 引用的 N 個腳本全部存在」——2026-09-09 為 **5**；非零時逐條印出是哪個
workflow 的第幾行跑了哪個不在的檔）。workflow 檔數 `ls .github/workflows/*.yml | wc -l`（2）。
**自證同第 13 列**：舊 binary 沒有這個子命令會印 usage 而不是 0，兩者分得開。

**第 21 列的量測（2026-09-09，可重跑）**：差異數 `akashic-guards protected-ratchet`
（相符時印「受保護清單與棘輪相符：N 條」、rc=0；不符時逐條印「少了／多了」、rc=1；
棘輪檔不存在 rc=2——三種分得開）。清單條數 `wc -l < .githooks/protected-ratchet.txt`
（2026-09-09：58；2026-09-14 重跑：59）。**顯式 vs glob 的拆分**——顯式＝路徑字面出現在 `TriggerCoverage.swift` 裡的那些：

```bash
python3 - <<'EOF'
import io
lines = [l for l in io.open(".githooks/protected-ratchet.txt", encoding="utf8").read().split("\n") if l]
src = io.open("Sources/akashic-guards/TriggerCoverage.swift", encoding="utf8").read()
explicit = [l for l in lines if f'"{l}"' in src]
print(f"受保護 {len(lines)}｜顯式字面 {len(explicit)}｜glob／衍生 {len(lines)-len(explicit)}")
EOF
# 2026-09-09：受保護 58｜顯式字面 21｜glob／衍生 37
# 2026-09-14 重跑：59｜2｜57——「顯式字面」從 21 掉到 2 不是計數誤差，`TriggerCoverage.swift` 的路徑字面寫法變了，
# 這個拆分判準已失效；本列理由欄的 37/58 與 19/19 隨之過期（#554 R9 verify 第 17／20 列，#571 另案重定量法）
```

**三組刪除實測**要在副本上做（複製 `plugin`／`.github`／`Sources`／
`.githooks`／`.claude/rules`／`CLAUDE.md`／`mcpb/manifest.json` 到暫存目錄，在那裡以 cwd 執行）
——顯式條目那一組另需重編 binary，因為守衛跑的是已編譯的那一份而不是原始碼。

**第 22 列的量測（2026-09-09，可重跑）**：

```bash
python3 - <<'EOF'
import glob, io, os, re
n = dated = 0
for f in glob.glob(os.path.expanduser('~/.akashic/entities') + '/*.yaml'):
    t = io.open(f, encoding='utf8').read()
    if not t.startswith('venue:'): continue
    n += 1
    m = re.search(r'^names:\n((?:- .*\n|  .*\n)+)', t, re.M)
    if m and re.search(r'^\s+(start|end|ended-unknown|attested):', m.group(1), re.M): dated += 1
print(f"venue {n} 筆｜names 帶時間欄位 {dated} 筆")   # 2026-09-09：406 / 0；2026-09-14 重跑：485 / 0
EOF
```

**第 23 列的量測（2026-09-09，可重跑）**：矛盾數 `akashic validate 2>&1 | grep -c '移除記錄與作者位互相矛盾'`
（應為 0；用含這條檢查的 binary——同第 13 列的自證，舊 binary 印不出東西）；移除記錄總數
`grep -c '^  judgement: 移除：' ~/.akashic/entities/*.yaml | awk -F: '{s+=$2} END {print s+0}'`
（2026-09-09：**0**——`--drop-author` 尚未對 live store 執行，等 store format bump 到 17）。

**第 24 列的量測（2026-09-11，可重跑）**：三個數字都要為零才維持「暫不做」；任一非零即重開。

```bash
python3 - <<'EOF'
import glob, io, os, unicodedata, yaml, collections
root = os.path.expanduser('~/.akashic/entities')
ART = {"the","a","an"}
def key(s):
    s = unicodedata.normalize('NFKC', s)
    s = ''.join('-' if unicodedata.category(c)=='Pd' else c for c in s)
    s = ''.join(c for c in s if unicodedata.category(c)!='Cf').lower().replace('&',' and ')
    s = ''.join(c if (c.isalnum() or c.isspace()) else ' ' for c in s)
    t = s.split()
    while t and t[0] in ART: t.pop(0)
    return ' '.join(t)
g = collections.defaultdict(set); n = with_parents = org_div = 0
for f in glob.glob(root + '/*.yaml'):
    t = io.open(f, encoding='utf8').read()
    if t.startswith('organization:'):
        n += 1; d = yaml.safe_load(t)
        if d.get('parents'): with_parents += 1
        for nm in [x['value'] if isinstance(x,dict) else x for x in (d.get('names') or [])]:
            if key(nm): g[key(nm)].add(d['key'])
    elif t.startswith('divergence:') and 'shape: organization' in t:
        org_div += 1
dupes = len([k for k, v in g.items() if len(v) >= 2])
print(f"organization {n} 筆｜重複群 {dupes} 組｜含 org 候選的 divergence {org_div} 筆｜帶 parents {with_parents} 筆")
EOF
# 2026-09-11：organization 13 筆｜重複群 0 組｜含 org 候選的 divergence 0 筆｜帶 parents 3 筆
```

**第 25 列的量測（2026-09-12，可重跑）**：venue 側名字內容的 error 應恆為 0——
`akashic validate 2>&1 | grep 'venue' | grep -c 'canonical 形\|近重複\|不是名字\|沒有名字\|格式或控制字元\|控制或方向控制\|不可見字元\|接合字元'`
（八個子串對應 `NameIdentity.wellFormednessIssue` 的七句訊息加 `Venue.validate()` 的近重複句——R5 的 grep 漏了空名的「沒有名字」，Python 對照卻算它，兩套量測分歧；R6 補齊並加不可見／接合字元兩類）
（用含這條檢查的 binary——同第 13 列的自證；注意 person 側另有 #296 的近重複 **warning**，
`grep 'venue'` 才不會把那些算進來）。Python 對照（不依賴 binary）：

```bash
python3 - <<'EOF'
import glob, io, os, re, unicodedata, yaml
# 鏡射 Swift 的 NameIdentity.wellFormednessIssue 與 Venue.validate() 的近重複掃描（改一邊要同批改另一邊）：
#  - canonical：NFC、只丟 White_Space（顯式集合——Python isspace() 把 U+001C–001F 也當空白，Swift 不會）、
#    內部空白串收成一個 U+0020
#  - 危險／不可見：Cc／Cf／Zl／Zp、Default_Ignorable_Code_Point（unicodedata 沒有 DI 屬性，用
#    DerivedCoreProperties 的區段列舉——UAX #44 的表，版本差異只在未指派碼位）、U+2800
#  - ZWJ／ZWNJ 例外：(a) 前一個 scalar 是 virama（ccc 9）、從 virama 往前跳過標記找到的基底是字母、virama 與
#    跳過的標記都是基底那個文字的（D22）、右鄰居若在要是同一文字的字母／數字——右鄰居是空白視同沒有（多字刊名的
#    詞尾 chillu）；(b) 左鄰居是 join-control 文字的字母／標記／數字、右鄰居是同一文字的字母／數字，或同一 Indic
#    Devanagari／Bengali 的 virama 且其後接同文字的字母（Bengali ya-phalaa <RA, ZWJ, VIRAMA, YA>，D21／D26——
#    每個引用實例都是 <C, J, H, C>，沒有後續輔音的 joiner 是純隱形位元組差）（標點不算；joiner 自己也不算，所以連續 joiner 必拒）
#  - 至少一個字母或數字（generalCategory 的 L／N 類——Python 的 isalnum() 正是這個，不含 Other_Alphabetic 的標記）
#  - names 近重複豁免：兩段都作時間宣稱（`DateRange.makesTemporalClaim`：start／end 非空、ended-unknown 為 true、
#    或 attested 非空）、一段的 end 與另一段的 start 都是 ISO 8601 前綴（鏡射 `ISO8601Prefix.isValid`：ASCII 數字、
#    月 01–12、日 01–31）、且 end 以較粗粒度截斷後嚴格小於 start
DI = [(0x00AD,0x00AD),(0x034F,0x034F),(0x061C,0x061C),(0x115F,0x1160),(0x17B4,0x17B5),(0x180B,0x180F),
      (0x200B,0x200F),(0x202A,0x202E),(0x2060,0x206F),(0x3164,0x3164),(0xFE00,0xFE0F),(0xFEFF,0xFEFF),
      (0xFFA0,0xFFA0),(0xFFF0,0xFFF8),(0x1BCA0,0x1BCA3),(0x1D173,0x1D17A),(0xE0000,0xE0FFF),(0x2800,0x2800)]
JOIN = [(0x0600,0x06FF,1),(0x0750,0x077F,1),(0x0870,0x089F,1),(0x08A0,0x08FF,1),(0xFB50,0xFDFF,1),(0xFE70,0xFEFF,1),(0x10EC0,0x10EFF,1),
        (0x0700,0x074F,2),(0x0860,0x086F,2),(0x0840,0x085F,3),(0x07C0,0x07FF,4),(0x1000,0x109F,5),(0x1780,0x17FF,6),
        (0x1800,0x18AF,7),(0x2D30,0x2D7F,8),(0x10D00,0x10D3F,9),(0x10F30,0x10F6F,10),(0x10F70,0x10FAF,11),(0x10AC0,0x10AFF,12),(0x1E900,0x1E95F,13),
        (0xA8E0,0xA8FF,100),(0x11B00,0x11B5F,100),(0xAA60,0xAA7F,5),(0xA9E0,0xA9FF,5)]   # R9：Devanagari／Myanmar 的補充區塊
def script(ch):   # 鏡射 NameIdentity.joinScript：同一文字的多個區塊同一 id；Indic 每 0x80 一個
    o = ord(ch)
    if 0x0900 <= o <= 0x0DFF: return 100 + (o - 0x0900) // 0x80
    return next((sid for a, b, sid in JOIN if a <= o <= b), None)
WSSET = {0x09,0x0A,0x0B,0x0C,0x0D,0x20,0x85,0xA0,0x1680,0x2028,0x2029,0x202F,0x205F,0x3000} | set(range(0x2000,0x200B))
inr = lambda c, R: any(a <= ord(c) <= b for a, b in R)
WS = lambda ch: ord(ch) in WSSET
JOINER = lambda ch: ch in '\u200c\u200d'
MARK = lambda ch: unicodedata.category(ch) in ('Mn','Mc')
VIRAMA = lambda ch: unicodedata.combining(ch) == 9
BASE = lambda ch: ch.isalnum()   # L 類或 N 類（isalnum 不含 Other_Alphabetic 的標記）
member = lambda ch: script(ch) is not None and (BASE(ch) or MARK(ch))   # (b) 支的左鄰居
def canon(s):
    s = unicodedata.normalize('NFC', s); out = []; pend = False
    for ch in s:
        if WS(ch): pend = bool(out); continue
        if pend: out.append(' '); pend = False
        out.append(ch)
    return ''.join(out)
def joiner_ok(s, i):
    p = s[i-1] if i > 0 else None; n = s[i+1] if i + 1 < len(s) else None
    if p is not None and VIRAMA(p):
        j = i - 2
        while j >= 0 and MARK(s[j]): j -= 1
        if j < 0 or script(s[j]) is None or not s[j].isalpha(): return False
        sc = script(s[j])
        if any(script(ch) != sc for ch in s[j+1:i]): return False   # virama 與跳過的標記同文字（D22）
        if n is None or WS(n): return True                          # 詞尾——含「後面是空白」
        return script(n) == sc and BASE(n)
    if p is None or n is None or script(p) is None or script(n) != script(p): return False
    if member(p) and BASE(n): return True
    # D21／D26：virama 之前的 joiner——只在 Devanagari（100）／Bengali（101），且 virama 之後要接同文字的字母
    if not (member(p) and VIRAMA(n) and script(p) in (100, 101) and i + 2 < len(s)): return False
    c = s[i+2]; return script(c) == script(p) and c.isalpha()
def issue(s):
    c = canon(s)
    if not c: return '空白'
    if s != c: return 'canonical'
    for i, ch in enumerate(s):
        if JOINER(ch):
            if not joiner_ok(s, i): return '接合字元'
            continue
        if inr(ch, DI): return '不可見'
        if unicodedata.category(ch) in ('Cc','Cf','Zl','Zp'): return '控制'
    if not any(ch.isalnum() for ch in s): return '無字母數字'
    return None
ISO = re.compile(r'[0-9]{4}(-(0[1-9]|1[0-2])(-(0[1-9]|[12][0-9]|3[01]))?)?')   # 鏡射 ISO8601Prefix.isValid：ASCII、月 01–12、日 01–31，不驗日曆
def before(end, start):   # 鏡射 Venue.segmentsAreDisjoint 的 before；PyYAML 會把 1933 讀成 int、2003-01-15 讀成 date，先 str()
    if end is None or start is None: return False
    end, start = str(end), str(start)
    if not (ISO.fullmatch(end) and ISO.fullmatch(start)): return False
    n = min(len(end), len(start)); return end[:n] < start[:n]
def well_formed(x):   # 鏡射 Venue.segmentIsWellFormed（R12）：在場的端點都是 ISO 前綴、且 start 以較粗粒度截斷後 ≤ end——倒置區間不解鎖豁免
    s, e = x.get('start'), x.get('end')
    if any(p is not None and not ISO.fullmatch(str(p)) for p in (s, e)): return False
    if s is not None and e is not None:
        s, e = str(s), str(e); n = min(len(s), len(e))
        if s[:n] > e[:n]: return False
    return True
def disjoint(a, b): return well_formed(a) and well_formed(b) and (before(a.get('end'), b.get('start')) or before(b.get('end'), a.get('start')))
dated = lambda x: (x.get('start') is not None or x.get('end') is not None   # 鏡射 DateRange.makesTemporalClaim
                   or x.get('ended-unknown') is True or bool(x.get('attested')))
def near_dup(a, b):   # a、b 是 names 段（dict）
    if canon(str(a['value'])) != canon(str(b['value'])): return False
    return not (dated(a) and dated(b) and disjoint(a, b))
# 固定案例：Swift 測試（VenueNameInvariantTests）的同一組，兩邊答案要一致
fixed = {'Psychometrika':None, '1843':None, 'نشریه\u200cروان':None, '۱۴۰۰\u200cها':None, 'ന്\u200d':None, 'क्\u200dष':None,
         'ࡀ\u200dࡁ':None, '\U0001E900\u200c\U0001E901':None, 'क़्\u200dष':None, 'بَ\u200cب':None,
         'Journal \u0967\u094d\u200d':'接合字元', 'क्\u200cA':'接合字元', 'ک\u200cक':'接合字元',
         'ا\u200c\u064eب':'接合字元', '\u064e':'無字母數字', '\u0640':None,
         # R9：D22（virama／標記同文字、詞尾含空白）、D21（Indic virama 之前的 joiner）、補充區塊
         'ک\u094d\u200d':'接合字元', 'क\u09cd\u200dष':'接合字元', 'क\u09bc\u094d\u200dष':'接合字元', 'क\u093c\u094d\u200dष':None,
         'അവന്\u200d വന്നു':None, 'ত্\u200d ব':None, 'ب\u200c ب':'接合字元',
         'র\u200d\u09cdযাব':None, 'क\u200d\u094dष':None, 'ক\u200c\u09cdষ':None, '\u1000\u200d\u1039\u1000':'接合字元',
         'ក\u200d\u17d2ត':'接合字元', 'क\u200d\u09cdष':'接合字元', 'A\u200d\u094dष':'接合字元',
         'क्\u200d\ua8fb':None, '\uaa60\u200d\uaa61':None, '\ua9e0\u200c\ua9e1':None,
         # R10：D26——virama 之後要接同文字的字母、只收 Devanagari／Bengali
         'क\u200d\u094d':'接合字元', 'क\u200c\u094d':'接合字元', 'क\u200c\u094dJournal':'接合字元', 'Journal क\u200d\u094d':'接合字元',
         'র\u200d\u09cd':'接合字元', 'क\u200d\u094d\u0967':'接合字元', 'क\u200d\u094d\u093e':'接合字元', 'क\u200d\u094d ष':'接合字元',
         'ல\u200d\u0bcdல':'接合字元', 'ക\u200d\u0d4dക':'接合字元', 'Journal क\u200d\u094dष':None,
         'Psycho\u200cmetrika':'接合字元', 'Zwj\u200d':'接合字元', 'A\u200c،B':'接合字元', 'ک\u200cA':'接合字元',
         'ا\u200c\u200cب':'接合字元', 'Psychometrika्\u200d':'接合字元',
         '心\ufe0f理學報':'不可見', '\u3164':'不可見', 'Psychometrika\u2800':'不可見',
         'Psycho\u200bmetrika':'不可見', 'Psychometrika\u202e':'不可見', 'A\x1cB':'控制',
         'Psychometrika ':'canonical', '×':'無字母數字', '':'空白'}
mism = [(k, issue(k), v) for k, v in fixed.items() if issue(k) != v]
assert not mism, mism
S = lambda **kw: dict(value='Sankhyā', **kw)
dup_cases = [((S(start='1933',end='1960'), S(start='2002',end='2007')), False),
             ((S(start='1933',end='1960'), S(start='1950')), True),
             ((S(start='1933',end='1960'), S()), True),
             ((S(start='1933',end='1960'), S(start='1960-06')), True),
             ((S(start='1933',end='1960'), S(start='1960')), True),
             ((S(attested=['1950']), S(attested=['2005'])), True),
             ((S(start='1933',end='1960-12'), S(start='1961')), False),
             ((S(start='1933',end='2003-01'), S(start='2003-1')), True),
             ((S(start='1933',end='1960-10'), S(start='1960-9')), True),
             ((S(start=1933,end=1960), S(start=2002,end=2007)), False),
             # R9：ISO 鏡射 isValid（月 13、非 ASCII 數字都不是端點）、dated 鏡射 makesTemporalClaim
             ((S(start='1933',end='1960-13'), S(start='1961')), True),
             ((S(start='1933',end='١٩٦٠'), S(start='2002')), True),
             ((S(start='1933',end='1960'), S(**{'ended-unknown': False})), True),
             ((S(start='1933',end='1960'), S(attested=[])), True),
             ((S(start='1933',end='1960'), S(start='1961', **{'ended-unknown': True})), False),
             # R12：區間本身要有效（R11 verify Codex 第 3 列）——倒置、或未參與比較的端點不是 ISO，都不豁免
             ((S(start='2000',end='1900'), S(start='1950',end='1960')), True),
             ((S(start='民國49',end='1960'), S(start='1961',end='1970')), True),
             ((S(start='1960',end='1960-06'), S(start='1961')), False)]
bad_dup = [(a, b, got, want) for (a, b), want in dup_cases if (got := near_dup(a, b)) != want]
assert not bad_dup, bad_dup
n=bad=dup=0
for f in glob.glob(os.path.expanduser('~/.akashic/entities')+'/*.yaml'):
    t=io.open(f,encoding='utf8').read()
    if not t.startswith('venue:'): continue
    n+=1; d=yaml.safe_load(t)
    segs=[x if isinstance(x,dict) else {'value': x} for x in (d.get('names') or [])]
    names=[str(x['value']) for x in segs]
    for lst in (names, d.get('authorized') or [], d.get('variant') or []):
        for s in lst:
            if issue(str(s)) is not None: bad+=1
    for i in range(len(segs)):
        for j in range(i+1, len(segs)):
            if near_dup(segs[i], segs[j]): dup+=1
    for lst in (d.get('authorized') or [], d.get('variant') or []):
        ks=[canon(str(s)) for s in lst]
        if len(ks)!=len(set(ks)): dup+=1
print(f"venue {n}｜違反不變式的字串 {bad}｜近重複對 {dup}")   # 2026-09-14：485 / 0 / 0（R10 重跑仍是）
EOF
```

**第 26 列的量測（2026-09-14，可重跑）**：warning 數 `akashic validate 2>&1 | grep -c '條邊指向同一 venue'`（應為 0；用含這條
檢查的 binary——同第 13 列的自證，舊 binary 印不出東西；R15 起每筆 work 最多列 20 個 venue、其餘一句概括——概括句自 R16 起前綴
`則數已達上限`、不含這個子串也不進家族，所以這個數與 `StoreHealth.duplicateVenueEdges` 都是「受影響數，至多每筆 20」，R15 verify 第 18／29 列）。Python 對照（不依賴 binary；`work:` 檔的 `venues` 裡 `key:` 出現兩次以上）：

```bash
python3 - <<'EOF'
import glob, io, os, re, collections
n = dup = multi = 0
for f in glob.glob(os.path.expanduser('~/.akashic/entities') + '/*.yaml'):
    t = io.open(f, encoding='utf8').read()
    if not t.startswith('work:'): continue
    n += 1
    m = re.search(r'^venues:\n((?:- .*\n|  .*\n)+)', t, re.M)
    if not m: continue
    keys = re.findall(r'^- key: (.+)$', m.group(1), re.M)
    edges = len(re.findall(r'^- ', m.group(1), re.M))
    if edges > 1: multi += 1
    if len(keys) != len(set(keys)): dup += 1
print(f"work {n} 筆｜>1 條 venue 邊 {multi} 筆｜同 venue 兩條 key 邊 {dup} 筆")   # 2026-09-14：2411 / 3 / 0
EOF
```

**第 27 列的量測（2026-09-15，可重跑；R15 分兩類、R16 對齊位元組）**：warning 數 `akashic validate 2>&1 | grep -c '個正規化後不同的 confirmed literal'`
與 `akashic validate 2>&1 | grep -c '筆只差位元組的 confirmed literal'`（應皆為 0；用含這條檢查的 binary——同第 13 列的自證，舊 binary 印不出東西；
家族總數 `akashic validate 2>&1 | grep -c '同一 work 多個 confirmed literal'`——R16 起**不含**概括句（它的前綴是 `則數已達上限`），所以家族總數＝
受影響的 work 數、至多每筆 venue 20；**兩類不是互斥分割**（R15 verify 第 23 列）：一筆 work 三個 literal、其中兩個只差位元組時只出第一類、訊息尾
附「另有 1 筆只差位元組的重複記錄」，第二類的 grep 不算它；`grep -c '只差位元組'` 數的是**含位元組重複的訊息行數**、不是組數——一則第一類
訊息最多點名 5 組（第 6 組起以「…共 N 組」揭露）、一則第二類訊息涵蓋一筆 work 的全部拼法；真要數「work 對」用下方鏡射的 `bytes_only`，
組數目前沒有 CLI 指令能數（R16 verify requirements 第 11 列、logic 第 14 列）。Python 對照（不依賴 binary；鏡射
`NameNormalization.matchingKey`——改一邊要同批改另一邊。**鏡射的兩處已知差異在 R15 對齊**（R14 verify logic 第 17 列、DA 第 23 列、
regression 第 30 列）：空白類用 Swift `Character.isWhitespace` 的 `White_Space` 集合，不用 Python `str.split()`（它把 U+001C–001F 也當空白
——store 內不可達，但同檔第 25 列早就顯式列舉了）；連字號家族在 **grapheme cluster** 上比（Swift 的 `hyphenFamily.contains(Character)`）
——連字號後面跟著組合符號時整個 cluster 不在家族裡、**不**取代，DA 實測 `A-\u0301B` 與 `A\u2010\u0301B` 在 Swift 是兩個鍵而 R14 的鏡射判成一個。
**R16 再對齊兩處**（R15 verify logic 第 9／11 列、DA 第 24 列；Claude 代裁 D46，2026-09-16 用逐字複製的 `matchingKey` 探針量過）：(1) 空白也在
Character 上切——**機制是 grapheme 分群，不是 `isWhitespace` 讀幾個 scalar**（R17 更正，R16 verify DA 第 10 列：R16 寫成「只看第一個 scalar」，
鏡射照著無條件吞，60,033 例差分裡 2,967 例源於此）：U+0020 與其他 Zs 類空白（NFKC 後大多已折成 U+0020；U+1680 仍是 Zs）後面的組合符號依
GB9 併進同一個 cluster，`split(whereSeparator: \.isWhitespace)` 看到的是一個 `isWhitespace` 為 true 的 Character、**整個丟掉**、組合符號一起消失
（`A \u0301B` → `a b`；`canonical` 自 R6 起在 scalar 上切、不會這樣——`matchingKey` 這個資料損失另案 **#574**，鏡射照現況鏡射，修那條時要同批改這裡）；
而 TAB／LF／VT／FF／CR／NEL／LS／PS 在 GCB 屬 **Control**，依 GB4 後面一定斷開，組合符號自成 cluster、**保留**（`A\t\u0301B` → `a \u0301b`）——
2026-09-16 探針對全部 14 個 `White_Space` scalar 逐一量過，14 個裡 8 個是這一類；
(2) 連字號後接 ZWJ／ZWNJ 也是同一個 cluster（Grapheme_Extend）、不取代，之後 Cf 才被刪（`A\u2010\u200DB` → `a\u2010b`）。鏡射只認 M 類與
ZWJ／ZWNJ 當 extender——Swift 的 grapheme 規則另收 U+FF9E／FF9F（Lm）與 emoji modifier（Sk）等，刊名裡零實例，記為鏡射的誠實邊界（第 24 列）；
`lowercased()` 與 Python `lower()` 對特殊大小寫（İ、ß）的差異同屬邊界；**NFKC 那一步本身也有一處差異**（DA 第 10 列）：Foundation 的
`precomposedStringWithCompatibilityMapping` 對 `0301 FF9F 0BCD` 不做 canonical reordering（輸出 `0301 309A 0BCD`），ICU／Python 會——這個差分發生在任何
clustering 之前、修 clustering 收斂不了，同屬邊界）：

```bash
python3 - <<'EOF'
import glob, io, os, re, unicodedata, yaml
# 鏡射 NameNormalization.matchingKey：NFKC → 連字號家族（整個 grapheme cluster 恰為一個連字號才算：後接 M 類、ZWJ、ZWNJ 都不算）→ '-'
# → 刪 Cf → 小寫 → White_Space 收斂為單一空格（顯式集合，與第 25 列的 WSSET 同一份定義；在 Character 上切——**Zs 類**空白後面掛著的
# 組合符號隨那個 cluster 一起被丟掉（GB9），鏡射 Swift 的資料損失，#574；Control 類空白（TAB／LF／VT／FF／CR／NEL／LS／PS）後面依 GB4 斷開、
# 組合符號保留——R17 更正，R16 verify DA 第 10 列）
HY = set('\u2010\u2011\u2012\u2013\u2014\u2015\u2212')
WS = {0x09,0x0A,0x0B,0x0C,0x0D,0x20,0x85,0xA0,0x1680,0x2028,0x2029,0x202F,0x205F,0x3000} | set(range(0x2000,0x200B))
MARK = lambda c: unicodedata.category(c).startswith('M')
def mk(s):
    s = unicodedata.normalize('NFKC', s)
    out = []
    for i, c in enumerate(s):
        nxt = s[i+1] if i + 1 < len(s) else ''
        extended = bool(nxt) and (MARK(nxt) or nxt in '\u200c\u200d')   # 同一個 grapheme cluster（R16：ZWJ／ZWNJ 也是 extender）
        out.append('-' if (c in HY and not extended) else c)
    s = ''.join(c for c in out if unicodedata.category(c) != 'Cf').lower()
    toks, cur, i = [], '', 0
    while i < len(s):
        c = s[i]
        if ord(c) in WS:
            if cur: toks.append(cur); cur = ''
            i += 1
            if unicodedata.category(c) == 'Zs':          # 只有 Zs 類空白會與後面的組合符號同 cluster（GB9）；Control 類依 GB4 斷開（R17）
                while i < len(s) and MARK(s[i]): i += 1  # 掛在空白上的組合符號隨 cluster 一起丟（R16，鏡射 Swift 的 grapheme 分群）
            continue
        cur += c; i += 1
    if cur: toks.append(cur)
    return ' '.join(toks)
# 固定案例（與 Swift 同一組期望；R15 起，R16 加三個——2026-09-16 用逐字複製的 matchingKey 探針逐一量過）：
assert mk('Chang, Y\u2010H.') == mk('Chang, Y-H.')            # 連字號家族
assert mk('A-\u0301B') != mk('A\u2010\u0301B')                # 連字號後接組合符號：cluster 不在家族裡，不取代（DA 第 23 列）
assert mk('Fann,  C.') == mk('Fann, C.') == mk('Fann,\tC.')    # 空白收斂
assert mk('Fann, C.\u200b') == mk('Fann, C.')                  # Cf 刪除
assert mk('A\u001fB') == 'a\u001fb'                            # U+001F 不是 White_Space（Python str.split 會切）
assert mk('A \u0301B') == 'a b'                                # 空白＋組合符號整個 cluster 被丟（Swift 的資料損失，#574；R15 verify logic 第 9 列）
assert mk('A\u2010\u200dB') == 'a\u2010b'                      # 連字號＋ZWJ 是一個 cluster、不取代，ZWJ 隨後被當 Cf 刪掉（logic 第 11 列）
assert mk('A\u00a0\u0301B') == 'a b'                           # NBSP 經 NFKC 成空格，同上
assert mk('A\t\u0301B') == 'a \u0301b'                          # TAB 是 GCB Control：組合符號自成 cluster、保留（R17；DA 第 10 列）
assert mk('A\u2028\u0301B') == 'a \u0301b'                      # LS 同上
n = flagged = pairs = bytes_only = 0
for f in glob.glob(os.path.expanduser('~/.akashic/entities') + '/*.yaml'):
    t = io.open(f, encoding='utf8').read()
    if not t.startswith('venue:'): continue
    n += 1
    d = yaml.safe_load(t)
    by = {}
    for r in d.get('references') or []:
        if r.get('field') != 'resolution-confirmed': continue
        m = re.match(r'^work:(\S+) :: (.*)$', str(r.get('value', '')), re.S)
        if not m: continue
        by.setdefault(m.group(1), {}).setdefault(m.group(2), mk(m.group(2)))   # 位元組相異的 literal → 鍵
    bad = [w for w, lits in by.items() if len(set(lits.values())) > 1]
    dup = [w for w, lits in by.items() if len(lits) > 1 and len(set(lits.values())) == 1]
    if bad: flagged += 1; pairs += len(bad)
    bytes_only += len(dup)
print(f"venue {n} 筆｜對同一 work 持 ≥2 個正規化後不同 confirmed literal 的 venue {flagged} 筆（work 對 {pairs} 個）｜只差位元組的 work 對 {bytes_only} 個")   # 2026-09-15：485 / 0（0）/ 0
EOF
```

## 各列共通的東西（觀察，不是判準）

第 1–9 列與第 13、14 列的裁決都是「寫」（第 14 列是 2026-09-09 從「不寫」翻過來的）、第 10–12 列（皆出自 #365）是「不寫」，但**理由各不相同**，這正是不寫總括判準的原因：

- 第 1 列的理由是**失敗的不可見性**（不寫 → 第一次發生時沒跡象）
- 第 2 列的理由是**前件的精確度**（要不要寫沒有疑問，寬度才是問題）
- 第 3 列的理由是**沉默的歧義**（守衛本身沒問題，它的「沒說話」有問題）

- 第 4 列的理由是**錯誤的偽裝性**（守衛沒問題、沉默也沒問題，問題是猜錯的結果**看起來
  是對的**）
- 第 6 列的理由是**訊號可信度的外溢**——前五列的失敗都關在自己那一格裡，這一列的
  失敗會讓人開始不相信別格的紅燈
- 第 5 列的理由是**覆蓋率的自我謊報**——前四列講的都是「被守衛的東西」出了什麼事，
  這一列講的是**守衛自己**：它多印了一個 ✓，而那個 ✓ 沒有對應到任何新的事實
- 第 7 列的理由是**兌現範圍的誠實**——它的守衛**通過了也不代表對**，所以它的裁決
  包含「必須在它旁邊寫出它管不到什麼」
- 第 9 列的理由是**缺席本身在說話**——前八列問「這個守衛該不該存在」，這一列問「這個
  欄位不存在時，讀者會推論出什麼」。答案是「機構沒有識別碼可記」，而那是假的
- 第 8 列的理由是**零的來源在別處**——前七列的「還沒發生」是關於世界；這一列的
  「走不到」是關於**另一段程式**（load 的 quarantine），而那段程式可以改而不會有人
  想到這裡。所以它的裁決包含「釘住為什麼是零」，不只是「寫這個守衛」
- 第 10、11、12 列的理由是三個**不同的**「不寫」——缺用途（形狀由用途決定）、缺理由（既有欄位承載、
  不成比例）、**位置錯了**（筆名是 Person 側的事實）。三列同出自 #365 而不可互換，正是這張表
  不寫總括判準的理由再一次實例。區辨全在**觸發後會發生什麼**：第 11 列越過門檻後欄位**進** `Author`、
  第 10 列用途出現後進 authorship 側（`Author` 上的 `Bool`、或 `Entry` 上的 `Set<index>`——由那個場景決定）、第 12 列**永遠不進** `Author`（落點在 #386 那一族）
- 第 13 列的理由是**跡象住在錯的地方**——它與第 1 列（缺跡象）、第 8 列（零的來源在別處）最像而都不同：跡象存在（三張 issue 的家族史），零也是真的零（#460 清理過之後的零），問題是每次都靠人記得去看。守衛各列（第 1–8 列）問「守衛該不該存在」，這一列問「已經發生過的形狀，為什麼還是零實例」——答案是場外機制，而場外機制不會自己跑
- 第 16 列的理由是**裁決依賴守衛**——前十五列的守衛是裁決的結果，這一列的守衛是裁決的**前提**：「暫不改形狀」只有在「漲到門檻時工具會出聲」為真時才站得住。它的零是「還沒漲到」，與第 1 列（還沒發生）、第 13 列（掃乾淨之後）、第 15 列（在這台機器上）都不同
- 第 15 列的理由是**零是本機的**——前十四列的零不取決於在哪台機器上量，這一列換一台機器就非零；它與第 13 列（時間上的零）成對：一個是「掃乾淨之後」，一個是「在這台機器上」。任何只在本機量的守衛都會對它報綠，所以掃描要住在每台機器都會跑的 `StoreHealth` 裡
- 第 19 列的理由是**被守的是辯護不是事實**——前十八列的失敗都會讓某個可判定的性質變錯（數字偏了、檔案不在、記錄形狀壞了），這一列的失敗**不讓任何東西變錯**，只讓「每列理由彼此不同」這個說明缺一角。而那個說明正是本檔不寫總括判準的依據，所以它缺一角就等於判準悄悄回來了
- 第 18 列的理由是**零量的是出口而守衛裝在入口**——前十七列的零都是關於已經在庫裡的東西，這一列的零（庫內最長 4,220 bytes）與它要防的東西（adapter 這一次遞過來的字串）不是同一個母體。與第 16 列（已知會漲的曲線）最像而不同：沒有曲線，實例會由一次外部呼叫一步跨過，而 #516 verify 已經一步跨過 80 倍
- 第 17 列的理由是**寫入面剛長出來**——與第 13 列（掃乾淨之後）最像而相反：那一列是形狀發生過、被場外機制清掉；這一列是形狀發生過 4 次、從未被記下，因為記錄它的值域在本 change 才存在。零從第 5 次拆分起才可能被打破，而守衛必須在那之前就在
- 第 22 列的理由是**它不是程式**——前二十一列講守衛與欄位，這一列講 spec 裡的一條 Requirement，而它的失敗是「被當死重刪掉」，不是漏報也不是錯誤的缺席斷言
- 第 21 列的理由是**既有守衛的謂詞對那一類成員結構上不可能為真**——它不是漏看，是問了一個 glob 成員答不錯的問題（「列了卻不存在」對只會變少的成員永遠為假）。前二十列的零都是關於「還沒有這個守衛」，這一列的守衛在、而且天天跑
- 第 20 列的理由是**窮舉自己漏了一格**——與第 1 列（缺跡象）、第 13 列（跡象住在錯的地方）都不同：跡象就在同一張 issue 裡、就在眼前，而窮舉它們的人仍然漏了第四個，是**別人**找到的。守衛換掉的不是注意力，是「這件事需要注意力」這個前提
- 第 23 列的理由是**可達性是本 change 自己造出來的**——第 17 列的零同樣是「寫入面剛長出來」，但那一列的形狀早已在庫外發生過 4 次；這一列的**矛盾狀態**在本 change 之前根本不可達（沒有面能把作者位清空），是新面把它變成可達的。讓它可達的那一步與守衛因此必須同批落地
- 第 14 列的理由是**判準的輸入未定**——與第 10 列（缺用途）同形而不同：那一列缺的是形狀由什麼決定，這一列形狀確定、缺的是它要比較的「相等」的定義，而定義在 #470 手上。寫了就是替 #470 預先裁決。**2026-09-09 #470 裁決後本列翻成「寫」**，理由隨之變成第二個、也是本表目前唯一的一個：**觸發條件是機械可檢查的，所以它自己到期**——不像第 10、12 列要人指認
- 第 25 列的理由是**入口有五個**——第 18 列的「零量的是出口而守衛裝在入口」對它也成立，但那一列只有一個入口；這一列三輪 verify 各修一個入口，第四、第五個仍開著。守衛的位置本身是裁決的一半：寫在 store 邊界，不寫在任何一個面
- 第 27 列的理由是**同一條不變式的另一半要有自己的守衛**——第 26 列的閘與守衛守的是「一條邊」那一半；「一個 literal」那一半的違反由另一條路徑造出、第一半的燈不亮。兩半各自要一盞燈，否則「應恆為 0」只量了一半
- 第 26 列的理由是**閘與守衛是同一條不變式的兩半**——第 25 列把守衛裝在 store 邊界，因為入口有五個；這一列的三個閘（D25／D27／D28）已把工具面全關，剩下的入口是閘擋不到的手改與舊 binary，守衛守的正是那兩個。與第 23 列成鏡像：那一列是新面讓不可達變可達，這一列是新閘讓可達變不可達（對工具面）
- 第 24 列的理由是**半吊子已經誠實**——前二十三列裁的是「寫或不寫某個東西」，這一列裁的是「對一個已存在的東西什麼都不動」。留著的代價是零，因為 #553 讓錯誤訊息說真話；動它的兩個方向（實作／拿掉）代價都不是零。與第 10 列（缺用途）最像：實作那一半同樣是「形狀取決於還不存在的用途」；但第 10 列的對象根本不存在，這一列的對象已經在、且已經誠實

**「完備」在第 1–7 列裡有三種強度，不是兩種**（#414 R1 自審更正——這一段原本寫
「前六列在前件內都完備」，而那對第 5、6 兩列為假）：

| 強度 | 哪幾列 | 通過代表什麼 |
|---|---|---|
| 檢查**就是**那個性質 | 1–4 | 前件成立即違規，通過即乾淨 |
| 檢查是那個性質，但由**有限抽樣**建立 | 5、6 | 強證據不是證明——第 6 列跑兩次逐字相同，證不到「輸出是決定性的」這個全稱命題；第 5 列找不到逐字重複，也不排除「兩個 case 印不同的字卻查同一件事」 |
| 檢查是一個**嚴格更弱的命題** | 7 | 通過只排除一個已知會錯的形狀（帶 `editor`），對真正的問題（「這個型別該不該在表裡」）**不提供任何證據** |

第 7 列與第 5、6 列的差別因此是**種類**而非程度：後者的缺口是知識論的（樣本數），
前者的缺口是結構的（問了另一個問題）。

一句「成本低就寫」會把這些理由壓成同一件事，然後在下一個還沒出現過的情形上給出沒人同意的答案。

（這句與下方同型的那句**刻意不寫序數**。它們寫過序數，而序數在本檔過期了兩次：「第十個情形」在第 10、11 列進表（2026-08-28）後一直留到 2026-09-02 的 diff 仍未改；「第 12 個」被改成「第 13 個」的同一天，#464 已排定在表尾加第 13 列——把正在修的缺陷複製到下一列。表頭的列數有 `measured-numbers-audit` 盯著，散文裡的「第 N 個」沒有守衛認得，所以不寫。#365 verify DA，2026-09-03。）

**第 4 列與第 1 列的差別值得看一眼**（兩者最像）：第 1 列不寫的話，那個形狀第一次出現時
**不會有任何跡象**；第 4 列不寫的話，會有跡象——一筆完全正常的 venue 記錄——只是那個跡象
指向錯的方向。前者是缺訊號，後者是**假訊號**。

~~**還沒出現過的情形**：零實例且**成本高**的守衛。真出現時要加一列，而那一列的理由
**很可能是「不寫」**~~ → **2026-08-28 出現了，而且一次三個**（第 10、11、12 列，皆出自 #365；第 12 列於 2026-09-02 補進表——2026-08-28 的裁決 comment 三項都裁了，只有前兩列當時被寫進來）。

**那個預測對了三分之一**：三列的裁決確實都是「不寫」，但它預測的理由（成本高）**只涵蓋第 11
列**。第 10 列的理由是**形狀取決於一個還不存在的用途**——成本高只是背景，真正擋住它的是
「現在選一個形狀等於用猜的固定一個介面」；第 12 列的理由是**位置錯了**——成本根本不是問題，
問題是它不該進這個型別。

**三列的理由不可互換，這是本表存在的理由的再一次實例**：一句「零實例且成本高就不寫」會把
它們壓成同一件事，然後在下一個還沒出現過的情形上給出沒人同意的答案（序數刻意不寫，理由見上）。

**現在還沒出現過的**：零實例、成本**低**、而裁決是「不寫」的情形。**「成本與裁決兩軸完全相關」這句話
曾寫在這裡，被本表自己否掉了**（#365 verify DA，2026-09-03）：第 3、7 列根本沒有陳述成本，第 12 列的成本
在上一段被明文否認為理由——12 個資料點裡 2 個沒有成本值、1 個的成本值不相干，剩下的「相關」是讀情形欄
的樣板前綴得來的，而拿樣板前綴當性質正是本檔禁止的「依性質相似類推」。誠實的版本是：**陳述了成本的
那幾列**裡，低成本的都「寫」、高成本的都「不寫」。結論不依賴那個統計，且在相關被削弱後更強——連相關都
不完整，就更不該拿它當判準。真出現時要加一列，不要從「成本低就寫」推導。

→ **2026-09-03 出現了**：第 14 列成本低、裁決「不寫」——理由是判準的輸入（相等定義）取決於 #470，與成本無關。預測對的是「會出現」；它的理由又是一個新的，這正是不寫總括判準的理由再一次實例。

→ **而它在 2026-09-09 又消失了**：#470 一 close，第 14 列依自己寫下的觸發條件翻成「寫」。所以「零實例、成本低、裁決不寫」這一格**現在又是空的**——那不是預測失效，是那一列的觸發條件真的到期了。留著這兩句是因為只寫最新狀態會讓下一個人以為這格從未有過成員。

## 為什麼是「一列一列」而不是判準

`common-spec-prose-enumeration` 記過這個形狀的失敗史（`PsychQuant/perspective-writer#7`
連續三輪跨模型盲驗抓到同一缺陷的三種變體）。它的第 3 條執行細節說：**把失敗史寫進文件本身**，
否則日後的維護者會覺得「這條寫得囉嗦，我幫它總括一下」而改回去。

本檔就是那條規則的直接應用：**表是規格，理由欄是它的辯護，兩者在同一列所以不會分岔。**

## 跟其他規則的關係

- `no-compat-fallback`：管**既有**相容路徑何時退場（往回收）；本條管**還不存在**的守衛何時
  長出來（往外長）。同一個生命週期軸的兩端，方向相反
- `lossless-intake`：第 3 列的理由直接引用它的「靜默是最糟的形式」
- 全域 `common-spec-prose-enumeration`：本檔的形狀（封閉表、無總括判準、理由與裁決同列）
  是它的執行細節 1 與 3 的落地
