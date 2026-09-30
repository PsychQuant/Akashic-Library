# 為「還沒發生過的形狀」寫守衛，是一列一列裁決出來的——不是判準推導出來的

適用於**新增一個當下零實例的東西**——或（第 4 類）對一條已存在、當下零筆記錄走進去的半吊子路徑決定動不動——封閉四類：

1. **守衛**：validator 的檢查、schema 的約束、CI 的 gate、任何「現在沒有資料會被它擋下」的防線。
2. **欄位**（2026-08-24 由 #394 的 `Organization.ror` 顯式擴入，見第 9–12 列）：一個模型裡的
   欄位，而當下全庫零筆記錄使用它。
3. **保留位置的 Requirement**（2026-09-09 由 #474 的「刊名沿革時間軸」顯式擴入，見第 22 列）：
   spec 裡一條描述**真實現象**的 Requirement，而當下零筆記錄用得到它。
4. **既有的半吊子路徑**（2026-09-18 由 #555 的 organization 攣生合併顯式擴入，見第 24 列）：一條記錄面收、
   處理面擲的管線——記得起來、解不掉——而當下零筆記錄走進去。

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
> **第 4 類同樣是顯式擴入的**（#555 R2，2026-09-18——R1 verify 四席各抓一次：第 24 列在表裡宣稱「理由是第四種」，
> 前言卻仍是封閉三類；理由的種類與**對象**的種類是兩件事，本段擴的是後者）。它的問題形狀與前三類相同（「現在
> 沒有實例，要不要現在做」），而**失敗的意義是第四種**：守衛失敗是漏報、欄位缺席是模型說了一句它沒打算說的話、
> Requirement 被當死重刪掉——而一條半吊子路徑的失敗是**使用者撞牆**（記了一筆解不掉的記錄）、或**被當成待修的
> 殘留而被人動手**（實作＝猜一個形狀、拿掉＝關掉記錄面）。**新的失敗意義是「撞牆」與「照猜出來的形狀實作了」兩項**（R2 verify 第 14 列；R3 verify 第 4／7／15 列——R3 曾寫「新的只有撞牆」
> 並斷言「前三類沒有任何一個有使用者面的後果」，對第 4／9／15／16 列為假：壞資料、誤導讀者、venue 消失都落在使用者身上）：前三類的失敗
> 都不是**使用者的一個操作被擋住**、也不是**有人照猜出來的形狀做了實作**。「拿掉」那一半**不是**新的——它就是第 3 類的「被當死重刪掉」
> （差別只在被刪的是 spec 文字還是一行 `byShape` 條目）；「實作」那一半的失敗意義是新的，但它的**理由**與第 10 列同形（形狀取決於一個
> 還不存在的用途）。所以「失敗意義不同」**不是**可拿去推第五類的判準——一個新形狀的失敗意義新不新，不決定它進不進表；
> 擴入靠的是顯式裁決。這一類的裁決可以是「什麼都不動」——那同時裁了
> 「不新增」與「不拿掉」，所以它是下面「不適用於移除」那句話的具名例外。所以第 24 列的理由欄不能沿用前二十三列
> 任何一條。
>
> 擴入**只到這四類為止**。第五類（例如「零實例的 CLI 命令」）出現時要再顯式擴一次，
> 不得從「半吊子路徑也算」推導出「命令也算」。
>
> **第 2 類在 2026-09-02 重審過一次**（#365 補第 12 列時，裁決 comment 明寫「三列一次加進去需要重新
> 檢視那個分類是否還成立」）。第 9–12 列現在都是欄位，而第 10–12 列與第 9 列有兩處不同：它們的裁決是
> **不寫**，且加進去**不是 additive**（`Author` 是 `enum`，加欄位要改成 `struct`）。**裁決：仍屬第 2 類。**
> 分類的判準是問題的形狀（「現在沒有實例，要不要現在做」），不是答案（寫／不寫）也不是代價（additive
> 與否）——第 11 列已把 non-additive 當**成本**計入理由欄，那是理由層的事實，不改它在哪一類。同案早先
> 一則 comment 說「型別重構不在本表」，與此不衝突：第 10–12 列問的是「要不要加一個欄位」，重構是加它
> 的**代價**，不是它的**種類**；一個純粹的重構提案（不新增任何零實例的東西）仍然不在本表。

不適用於**已有實例**的守衛（那不需要裁決，有東西壞了就修），也不適用於**移除**既有守衛
（那是 `no-compat-fallback` 的退場紀律，方向相反）。**第 4 類是這句話的具名例外**：它的「不拿掉」那一半
不屬退場紀律——`no-compat-fallback` 管的是同一語意的第二條讀法（相容 fallback），而 `byShape` 收 org 是
**尚未實作的正面能力**，不是相容路徑；那條規則第 2 條要量的「還有誰在走這條路」，正是第 24 列的觸發條件之二
（含 org 候選的 divergence 記錄數）。#555 R1 verify DA 第 22 列。

## 規則

對本表四類中的任一個做出裁決時——不論裁的是新增、不新增、保留、還是拿掉——**在下表加一列**：情形／裁決／理由。（這句曾寫「新增零實例守衛時」——第 2、3 類擴入時就與它分岔，第 4 類再拉寬一級（R2 verify 第 7 列）；R3 改成「新增……或對第 4 類做出動不動的裁決」，仍漏掉第 22 列那種對第 3 類的「保留」（R3 verify 第 6 列）——觸發條件要寫成與對象無關的形式。）**不得依性質相似類推**——覺得
「這跟第 2 列很像」不構成裁決，那正是要停下來想的訊號。

**本檔刻意不給總括判準。** 依全域 `common-spec-prose-enumeration`：一句「凡是成本低就寫」
會在邊界上自己長出沒人同意的答案，而那句話與下表**是兩份不會一起改的規格**。要判斷新情形，
讀下表的理由欄，然後**加一列**。

## 裁決史（封閉列舉——現有 73 列，一列不多一列不少）

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
| 13 | **零實例，但同族的結構缺口已經出現三次、stale 實際累積過一次——抓到它的三個機制全是場外的，沒有一個是守衛**（#464：死 verdict 掃描。resolution verdict 的 value 指向一個沒有載入的 holder。三個結構缺口：#232 rename／person 側、#271 merge／person 側、#460 venue 側（#460 的 changelog 原話「家族第三個缺口」）；實際量到的 stale 累積只有 #460 那一次（來源是 #456 的攣生合併批次），而抓到它的三個機制全在那一次——205 條 stale 由 #456 pilot 人肉抓、殘留 1 條由 verify lens 全庫掃抓、清理完整性靠 set-difference 腳本**驗**（驗不是抓）。2026-09-03 實測 live store 2,700 條 verdict（confirmed 與 rejected 合計），死引用 **0**。**零有第二個來源**：#463 網格裡還沒補的格——`renameEntry` 沒有 organizations 迴圈——今天沒被走過（organizations 持有的 verdict 只有 9 條、其 holder 沒被 rename 過；verify DA 在副本上 rename 兩次即得 4 條死 verdict）。**該格已於 2026-09-03 由 #463（PR #493）補齊，第二個來源自此消失**——現在的零只剩「清理過之後的零」一個來源。重跑指令見表下方） | ✅ **寫** | 前面各列的零實例都是「這個形狀還沒發生過」；這一列的零是**清理過之後的零**——形狀在 #460 真的發生過（205 條），只是被場外機制（人肉、verify lens、一次性腳本）掃乾淨了，store 裡因此看不到。所以本列的理由不是第 1 列的「不寫就沒有跡象」（跡象有，在 issue 史裡），而是**跡象住在錯的地方**：每一次都要一個人記得去看，而下一條 holder 退役路徑（#463 網格裡還沒補的格）不會有人記得。掃描放進 `StoreHealth` 是把跡象搬到工具會自己看的地方。**severity 是 warning，三個理由，且都是「現在」**：(1) 升 error 會把**第 8 列釘住的零翻掉**——那一列的依據是 per-record 的 error 級檢查全部是 key 合法性檢查、對載入後記錄不可達；死 verdict 若是 error 就是第一個既非 key 檢查又可達的 per-record error，`errorsFirst` 從裝飾品變承重結構，而第 8 列明寫那個轉變不得安靜發生——**本列因此繼承第 8 列的釘零義務**（測試釘住 malformed value 對已載入記錄不可達）。(2) #464 的 Expected 逐字寫「warning 級」。(3) 今天沒有處置命令，升 error 會讓一次合法的 rename 把 `validate` 打紅而修不掉。**不是**「rename 後常態為真」（假：只有 org 持有的那幾條）、也**不是**「rename 本來就全遷」（假：沒有 org 迴圈）——兩句 verify 都量過。#463 補完且有修復路徑後，error 要重開裁決，第 8 列與本列一起改（#463 已於 2026-09-03 補完；修復路徑仍缺，裁決未重開——#464 的 closing summary 記著）。**誠實邊界**：warning 級的 `validate` 對它 exit 仍為 0（DA 實測 5 條死 verdict 仍 exit=0）——它做到「掃得到」、做不到「叫醒」（`blocked-issues-must-be-scannable` 的同一條界線）；CLI 逐行可見、MCP 進 `recordIssues`，App 側欄「記錄」Section 渲染計數（#487，2026-09-04 落地；死 verdict 這一族沒有 per-record 上限——每筆 reference／配對／記錄各一則、與記錄持有的 verdict 數線性（`psychological-methods` 持 1,352 筆，holder 全退役就是 1,352 則），CLI `validate` 逐則完整；組合式的六族有上限，R24 D66／R25 D70／R26 D72）。**觸發條件可檢查（用含這條檢查的 binary，指令見表下方）**：「死 verdict」數應恆為 0；非零時先看 quarantined 清單——被 quarantine 的 holder 是「讀不到」不是「退役」，其餘才指向一條漏了遷移的退役路徑。**#554 R21／R22 補記**：rename 遇到目的鍵上已有的死 verdict 一律具名拒絕、零寫入（D60／D63，含 quarantined 檔——位元組比對 `<kind>:<newKey>`，R22 的行級比對被 YAML 折行擊穿，R22 verify 四席同指）——「處置是人的重新消歧」在 rename 這一格自此有閘（R21 verify 第 18 列：D60 曾只記在第 27 列） |
| 14 | **零實例、成本一個掃描，而判準取決於一個還不存在的相等定義**（#464 的第二個掃描項——同一 owner 對同一配對同時持有 `resolution-confirmed` 與 `resolution-rejected`。2026-09-03 實測 live store 以 (檔, holder) 與 (檔, 完整 value) 兩種收攏法各算一次，並存數皆 **0**；追蹤 #486，其 `### Blocking` 記 #470） | ✅ **寫**（2026-09-09 翻轉——觸發條件成立） | 與第 10 列同形——判準取決於一個還不存在的東西——而對象不同：那一列是**形狀**取決於用途，這一列形狀確定（一個並存掃描），是它要比較的**相等**取決於 #470：寫入面位元組精確、讀取面 `NameNormalization.matchingKey` 正規化，兩面今天對同一筆 verdict 答案不同。現在寫任一個，都是在 #470 之前偷偷定案第三份相等定義，裁決後必然分岔（`no-compat-fallback` 記過的形狀）。**本表第一個成本低而「不寫」的列**，理由與成本無關。本列**不取代** #486——「在等 #470」的可掃描位置是那張 issue 的 `### Blocking`，不是這張表（`blocked-issues-must-be-scannable` 的三個位置是封閉列舉）。**觸發條件已成立**：#470 於 2026-09-09 選定相等定義（正規化，且只住在鍵裡），本列依它自己寫下的條件改裁「寫」，在 #486 實作——`StoreHealth.contradictoryVerdictIssues`，warning 級，2026-09-09 實測 live store 仍 **0**。**翻轉的方式本身值得留著**：這一列不是被人想起來才改的，是它自己寫下了一個**機械可檢查**的觸發條件（另一張 issue 的 state），而那張 issue 一 close 就到期。對照第 10、12 列——它們的觸發條件是「出現一個需要它的場景」，沒有任何機制會叫醒任何人。**change `resolution-verdict-states` 補記（2026-09-25，#619／#636）**：矛盾只比 confirmed×rejected——兩個判定層級（nominated／judged）都算、`resolution-undecided` 不參與（未決是查證歷史，與判定並存不是矛盾）；配對鍵的單一定義搬到 `ProvenanceReference.verdictPairingKey`，本掃描與合併閘（D31／D34）的兩份複本都改呼叫它 |
| 15 | **零實例，而零是本機的——同一份 store 在別台機器上全是實例**（#453：本機缺承重存檔的掃描。記錄的 provenance 指向一個本機 `sources/` 沒有的 digest。2026-09-04 實測 live store：62 個 digest 引用、41 個 distinct `sha256:`，**本機缺 1 筆**——而那一筆不是缺席，是 divergence `B354B9E9…` 的 `judgement.restsOn` 裝了一個 URL、根本不是 digest（訊息分開說，見 `danglingSourceIssues`）；同一份 store 拿掉 `sources/` 的副本跑同一支 binary：**41 筆**（40 venue ＋ 1 divergence）。兩層盲區都實測為真：`missingSourceDigests` 不掃 venue（#406 起承重證據住在 venue 上）也不掃 `Entry.references`（第 15 條邊）；且它零 production 呼叫端——doctor 接的是 `auditSourceIndex()`，捏造的 digest 在 blob 與 index 兩邊都不在、兩邊一致、audit 說「全部一致」。重跑指令見表下方） | ✅ **寫** | 前面各列的零，成立與否**不取決於在哪台機器上量**；這一列的零**只在這台機器上為真**——`sources/` 不進 git（`replace-endnote-and-zotero` 的承重閘：第三方版權 PDF 住在那裡），所以每一台新 clone 上這個數字都是「全部」。與第 13 列（清理過之後的零）最像而不同：那一列的零是**時間上**的（曾經非零、掃乾淨了），這一列的零是**空間上**的（換一台機器就非零）——而任何只在本機量的守衛都會對它報綠。第 3 列「未涵蓋不得冒充通過」正是 `auditSourceIndex` 的沉默形：沒被檢查與檢查過且乾淨在輸出上相同。**severity 是 warning**：記錄合法可載入、缺的是位元組，而其他 clone 上「全部 dangling」是常態，error 會讓 `hasErrors` 翻紅擋住 export 類流程。**用詞「本機缺」不寫「偽造」**：本機分不出「從未存在」與「沒同步」，訊息把這個邊界說出來。**觸發條件可檢查**（指令見表下方）：本機數字應恆等於「不是合法 digest 的引用數」（今天 1）；多出來的那些指向沒同步的 `sources/` 或真的捏造——先同步，同步後仍在的才是後者 |
| 16 | **零實例，而它守的是一個已裁決「現在不改形狀」的 O(n) 增長**（#499：venue 側 verdict 數逼近 decode 預算的 warning。第 13 條邊在 venue 側是 O(catalog)——`psychological-methods` 2026-09-04 實測 **1,352** 筆 resolution verdict、268 KB；硬預算 200,000 節點、每筆 verdict 量測 9 節點（2026-09-01：14,031／1,556），門檻＝預算一半÷9＝**11,111** 筆。沒有一本刊接近門檻 → 0 實例。使用者裁決（2026-09-04）：候選 3——不改序列化位置、半預算處出聲、達門檻重開裁決；候選 2（sidecar ledger）是那時的形狀。重跑指令見表下方） | ✅ **寫** | 前面各列的守衛守的是「某個形狀出現」；這一列守的是**一條已知會漲、且裁決了暫不改形狀的曲線**——它的零不是「還沒發生」，是「還沒漲到」。不寫的代價與第 1 列同形（撞上硬預算時整檔 quarantine、venue 消失，而在那之前沒有任何跡象），但理由多一層：**裁決本身依賴這個守衛**。候選 3 之所以可接受，是因為「達門檻時重開」被承諾為一個工具會自己看的門檻，而不是散文觸發條件（`blocked-issues-must-be-scannable` 的誠實邊界：散文命題沒有機制會叫醒任何人）。拿掉守衛，裁決就退化成「等它壞」。~~門檻由量測換算（節點／筆）而不是憑空的數字，`VenueVerdictBudgetWarningTests` 釘住那個換算。~~（2026-09-26 失效：那個換算量的是對 store 檔不生效的節點軸，見本列末的更正；門檻現在是讀取上限的一半，測試釘的是這個推導。）**觸發條件可檢查**：任一 venue 的 warning 出現即重開第 13 條邊的規模化裁決，不要只放寬預算。**2026-09-26 更正（#645 R2 verify DA，真 binary 量過）：本列的「硬預算」量錯了東西**——`AliasEventBudget.estimate` 的節點軸只在檔案含 alias 時生效，store 寫出的檔不含 alias，讀取路徑上唯一會觸發的是 8 MiB 的檔案位元組上限（65,000 筆 verdict 的檔照常載入，8.7 MB 的檔才被 quarantine）。門檻因此改量**記錄檔本身的位元組**，取讀取上限的一半（`AliasEventBudget.recordFileWarningBytes`＝4 MiB；live 最大檔 268,627 bytes），`nodesPerVenueVerdict` 與 `venueVerdictWarningThreshold` 退場。**裁決不變**（候選 3：不改序列化位置、半預算處出聲、達門檻重開）——變的是預算的量綱；warning 出現時先查是否有呼叫端在重複記未決（venue 也收未決記錄，#619），再判斷是不是 O(catalog) 的歸戶在長 |
| 17 | **零實例，而零的來源是「寫入面剛長出來」**（#450：拆分後錨失效的兩種 warning——某 person／organization 持有的 resolution verdict 其 literal 已被 work 的拆分記錄退役（孤兒 verdict）、拆分記錄各段全不在作者位。2026-09-07 實測 live store：拆分記錄 **0** 筆——#443 已拆的 4 筆「某人與雷庚玲」（store `32916ba`）沒有記錄，因為那時值域還沒有這一格、且 #450 裁決不回填；產生實例的唯一路徑（`splitAuthors` 寫記錄）在本 change 才存在，所以兩種 warning 今天必為零。重跑指令見表下方） | ✅ **寫** | 前面各列的零各有來源——還沒發生（第 1 列）、走不到（第 8 列）、掃乾淨了（第 13 列）、在這台機器上（第 15 列）、還沒漲到（第 16 列）；這一列的零是**形狀已經發生過 4 次、只是沒被記下**——寫入面在本 change 才長出來，實例從第 5 次拆分起才可能出現。不寫的代價與第 1 列同形而更具體：下一次拆分後，一條指向已退役作者位的 `resolution-rejected` 會讓 `resolve-people` 永遠不再提名那一段（否決抑制以 (citekey, literal) 配對），而沒有任何跡象——那正是 `literal-first-then-key` 說的「誤不可逆」在 verdict 側的形。**釘零的方式**：`OrphanedSplitVerdictScanTests.testCleanStoreReportsNothing` 釘住乾淨為零、`testRejectedLiteralLaterSplitIsAnOrphan` 釘住形狀出現即報、`testSameLiteralOnDifferentWorkIsNotAnOrphan` 釘住鍵是 (citekey, literal) 不是 literal。severity 是 warning（處置是人的重新消歧，不是修檔；`validate` exit 仍 0——「掃得到」不「叫醒」，#464 的同一條界線）。**觸發條件可檢查**（指令見表下方）：live store 第一次跑 `--split-author` 之後兩個計數才可能非零；非零時先看孤兒 verdict——那是要人動手的那種，各段全不在只是提醒記錄留著供 un-split |
| 18 | **零實例，而零只存在於「已經進來的資料」上——守衛守的是入口**（#519：`AddOnlyEnrichment` 對單一字串的 65,536 位元組上限。2026-09-08 實測 live store：1,517 筆 abstract，最長 **4,220 bytes**、p99 2,185、中位 1,137；全部 6,125 個 `fields` 值的最長也是同一筆。離上限還有 **15.5 倍**，今日零實例。**但那個形狀已經被造出來過**：#516 verify 用一份 5 MB 摘要走**同一條鏈**實測 RSS 46.6 MB、`proposals.json` 5.0 MB 原樣流進 store 欄位——是上限的 **80 倍**。重跑指令見表下方） | ✅ **寫** | 前十七列的零都是關於**已經在庫裡的東西**——還沒發生（第 1 列）、走不到（第 8 列）、掃乾淨了（第 13 列）、在這台機器上（第 15 列）、還沒漲到（第 16 列）、寫入面剛長出來（第 17 列）。這一列的零**量的是出口，而守衛裝在入口**：store 的最長值是 4,220 bytes，是因為進得來的都小；而這道檢查管的是 adapter **這一次遞過來**的字串，那個長度不受庫內歷史約束。與第 16 列（已知會漲的曲線）最像而不同：**這裡沒有曲線**——實例不會由目錄成長慢慢逼近，它會由一次外部呼叫**一步跨過**，而 #516 verify 已經一步跨過 80 倍。所以「還沒漲到」對它不成立，「還沒發生」也不精確：形狀發生過，只是發生在測試裡而不是 store 裡。**裁決的第二半是語意**：超限**整批拒絕、零寫入、具名，不截斷**——截斷會讓一個不是來源給的值進 store 且不出聲。那一半動到了 `lossless-intake` 的封閉列舉，故該檔在同一輪顯式加了一節「有界拒絕」並寫明它**不是**那張表的第三類（成員資格是「可以丟掉這個欄位、繼續匯入」，而以大小為名的成員會被類推成「太長的欄位可以丟掉」）。**上限值不是挑的，是兩個量出來的錨點夾出來的**：下界是實測最長值的 15.5 倍，上界是 `AliasEventBudget.maxBytes`（**輸入檔**預算 8 MiB）的 1/128 未跳脫、**1/32 已跳脫**（實測 YAML 序列化放大：ASCII／CJK／換行 1.00×、`\t` 2.00×、控制字元 4.00×——單一欄位不會主導整筆記錄的預算） |
| 19 | **零實例，而被守的是「辯護」不是事實**（#479：本表每一列都要在「各列共通的東西」有一條 bullet 講它自己的理由。2026-09-09 實測 22 列全部有**自己的** bullet（判準是「以 `- 第 N 列的理由是` 開頭的行」，不是段落裡任何一次提到 N——那一段到處是跨列比較，鬆的判準讓拿掉某列的 bullet 也不會紅，實測過）；20 條 bullet 涵蓋 22 列，一條可涵蓋多列（「第 10、11、12 列的理由是三個**不同的**…」），所以判準是**每個列號至少被引用一次**而非「bullet 數等於列數」；未被引用的列 **0**。重跑指令見表下方） | ✅ **寫** | 前十八列守的都是**可判定的性質**——欄位在不在、數字對不對、檔案存不存在、記錄形狀合不合法。這一列守的是**這張表存在的理由本身**：表是規格，理由欄是它的辯護，而共通段是那個辯護的第二層（它說明每一列的理由**彼此不同**，那正是本檔不寫總括判準的依據）。**少一條 bullet 不會讓任何檢查變錯**——沒有任何數字會偏、沒有任何斷言會紅——它只會讓下一個人拿判準去類推，而那是本檔開宗明義禁止的動作。所以這一列的失敗不是「漏報」也不是「假訊號」，是**規格的辯護少了一角而規格本身看起來完好**。漂移真的發生過：第 12 列的裁決 2026-08-28 就下了，2026-09-02 才補進表，中間五天表與裁決不同步（只是當時漂的是列不是 bullet）。**觸發條件可檢查**（指令見表下方）：未被引用的列數應恆為 0 |
| 20 | **零實例，而作者對同一形狀的窮舉自己漏了一格**（#526：workflow 的 `run:` 跑一支不存在的腳本。#521 的四個實例裡**有兩個**是這個形狀——`census-parity.yml` 與 `ci.yml` 各跑一支在 `989ac64`（#433「Python 歸零」）刪掉的 `.py`——而**實例 4 是 verify 席找到的**：當時的封閉列舉漏了它。2026-09-09 實測 live repo：2 個 workflow 檔、**5** 個腳本引用、不存在 **0**。重跑指令見表下方） | ✅ **寫** | 前十九列的零各有來源——還沒發生（第 1 列）、走不到（第 8 列）、掃乾淨了（第 13 列）、在這台機器上（第 15 列）、還沒漲到（第 16 列）、寫入面剛長出來（第 17 列）、量的是出口（第 18 列）。這一列的零是**剛剛被人工修完的**，而修它的那一輪自己證明了人工窮舉不可靠：四個實例裡第四個是**別人**找到的，且它與前三個形狀完全相同。所以理由不是第 1 列的「不寫就沒有跡象」（跡象有，就在同一張 issue 裡），也不是第 13 列的「跡象住在錯的地方」（它就在眼前）——是**看過了、看的是對的地方，仍然漏了一個**。守衛換掉的不是人的注意力，是「這件事需要注意力」這個前提。後果不對稱使它值得：一個掛掉的 step 會擋住其後**全部**步驟，`ci.yml:94` 那次擋掉的包含 AkashicApp（`swift test` 涵蓋不到的那塊，#101 的立案理由）。**它刻意不住在 `trigger-coverage` 裡**——併進去實測讓該支的 mutation harness **5 個既有 case 同時失敗**：那些 case 刻意在 workflow 注入指向不存在腳本的假命令（`plugin/tests/DELETED-numbers-audit.py`）來測 `invoked()` 的剖析，而本檢查會如實報那些引用。一支守衛的 harness 偽造某種內容，另一道檢查又對那種內容做存在性斷言，兩者永久互相干擾。**觸發條件可檢查**（指令見表下方）：「不存在」應恆為 0；非零時那個 step 已經是壞的，修路徑或刪 step，不要放寬檢查 |
| 21 | **零實例，而既有守衛的謂詞對這一類成員結構上不可能為真**（#522：受保護清單少了成員。`trigger-coverage` 的 `missing` 問的是「清單裡列的路徑還在不在磁碟上」——而 **glob 產生的成員永遠不會「列了卻不存在」**，它只會停止被列出。2026-09-09 實測三組：刪一整支守衛、刪一條 glob 規則檔、拿掉一條顯式 `DATA` 條目（重編 binary 後），**三組全部 rc=0 並印「無缺口」**。棘輪落地後三組皆 rc=1 具名；當下棘輪與清單相符、差異 **0**。重跑指令見表下方） | ✅ **寫** | 前二十列的零都是關於「**還沒有**這個守衛」——沒發生、走不到、掃乾淨了、在這台機器上、還沒漲到、寫入面剛長出來、量的是出口、窮舉漏了一格。這一列不同：**守衛在，而且天天跑，只是它的謂詞對 70 個成員裡的 **48** 個永遠不可能為真（glob 與 `swiftGuards()` 衍生的那些；顯式字面 22 個，2026-09-27 重量，量法見表下方——立案時是 58／37／21；#629 移植後 2026-09-29 重量是 61 個成員、43 個衍生、18 個顯式，比例同形）**。它不是漏看，是問了一個那一類成員答不錯的問題。所以理由既不是「缺跡象」（第 1 列）也不是「跡象住在錯的地方」（第 13 列）——**跡象根本無法產生**。**它刻意不住在 `trigger-coverage` 裡**，理由同第 20 列（那支的 mutation harness 會偽造它要檢查的內容）；清單則來自**同一個** `protectedInventory()`——一個自己算一遍的棘輪只會證明它自己與自己一致。**為什麼不是「把 glob 換成顯式清單」**（issue 列的另一個候選）：顯式條目 22/22 由 `missing` 逐條具名（2026-09-27；立案時 19/19——結構上恆為全部，`missing` 逐條檢查 `DATA`），但換掉之後**忘記加新規則檔是靜默的**，同一個失效換一步，而規則檔正是本 repo 承載裁決的地方。**為什麼它不是 #518 記過的「第 N 份副本」**：那次的缺陷是複製清單與 `DATA` 之間沒有東西在對帳，而棘輪整個存在理由就是被對帳——同形先例是 `hash-table-drift.sh`（生成表的漂移守衛；#629 隨 census 移植成 Swift 而退場——它守的「census 自己實作的 marker 解析與讀端不分岔」在只剩一份實作後不成立，先例的形狀仍在）。**觸發條件可檢查**（指令見表下方）：差異應恆為 0；非零時先讀是「少了」還是「多了」——前者確認刪檔是有意的，後者確認新成員真的有讀者（往已在 CI paths 的路徑根加零讀者的檔可以零成本灌水） |
| 22 | **零實例，而它是一條 spec Requirement 不是程式**（#474：venue 的 `names` 時間軸——刊名沿革。#422 把它保留而收窄（`variant` 不得帶時間），於是沿革成了一個「保留位置」的形狀。2026-09-09 實測 live store：venue **406** 筆、`names` 帶任一時間欄位（`start`／`end`／`ended`／`attested`）的 **0** 筆。重跑腳本見表下方） | ✅ **保留** | 前二十一列講的都是**程式**——守衛（第 1–8、13、15–18、20、21 列）與欄位（第 9–12、14、19 列）。這一列講的是 **spec 裡的一條 Requirement**，而它的失敗方式是第三種：守衛失敗是**漏報**、欄位缺席是**模型說了一句它沒打算說的話**，而一條零實例的 Requirement 的失敗是——**有人把它當死重刪掉**（「405 筆沒有一筆用到，留著幹嘛」），然後那個形狀到達時沒有位置可落。**保留而不刪的理由是那個現象是真的**：JRSS Series B／C 的分裂、`bulletin-of-the-institute-of-mathematics-academia-sinica` 的新舊系列都是 store 今天**表達不了**的實例（`entity-backlink-completeness` 的「分裂／繼承」那一節記著同一組例子）。**零實例的成因也具名**：異寫法佔著它的位置——#422 之前 `names` 時間軸同時裝沿革與異寫，收窄之後異寫搬到 `variant`，而沿革還沒有人填。**觸發條件可檢查**（指令見表下方）：帶時間欄位的 venue 數 > 0 即代表沿革開始被用——那時第 16 列（venue verdict 預算）與 `which-side-does-a-relation-live-on` 的「分裂／繼承」觸發條件 ② 也一起到期，三處要一起讀 |
| 23 | **零實例，而製造它的那條路徑是本輪自己開的**（#457：移除記錄與作者位互相矛盾——某 work 帶一筆「移除：理由」說某個 literal 已退役，而它現在又在作者位上。2026-09-09 實測 live store：移除記錄 **0** 筆——寫入面（`--drop-author`）在本 change 才存在，所以矛盾今天必為零。重跑指令見表下方） | ✅ **寫** | 第 17 列的零也是「寫入面剛長出來」，而這一列多一件事：**矛盾的可達路徑是本 change 自己造出來的**。移除之後 `authors` 變成**空的**，而 `enrich --include-absent-authors` 的既有契約正好是「只在 authors 完全為空時補」——於是同一個字串補得回去，那時 store 同時斷言「它已退役」與「它是作者」。所以這不是「還沒發生的形狀」，是**新面把一個原本不可達的狀態變成可達**，而讓它可達的那一步與守衛必須在同一個 change 裡（`entity-backlink-completeness` 引 3.325 的立場：矛盾寫不出來最好，寫得出來就要出聲）。與第 8 列成鏡像：那一列的零由**別處的**程式（load 的 quarantine）造成、可能被改掉而沒人知道；這一列的零由**本 change 之前沒有這個面**造成，而面已經有了，所以零是暫時的。severity 是 warning（記錄合法，失效的是證據錨——同 `staleSplitRecords` 的既有分級；`validate` exit 仍 0）。**觸發條件可檢查**（指令見表下方）：計數應恆為 0；非零時先確認是不是補值面把它加回來的——要嘛再移除一次，要嘛刪掉那筆記錄，不要兩者並存 |
| 24 | **零實例，而它是一條「記得起來、解不掉」的半吊子管線——且零是雙重的**（#555：organization 的攣生合併。`recordDivergence` 的 `byShape` 收 org、`resolveDivergence` 對它擲 `unsupportedShape`。2026-09-11 實測 live store：organization **13** 筆、寬鬆共鍵的重複群 **0** 組、含 org 候選的 divergence 記錄 **0** 筆——沒有重複可合、也沒有人記過（2026-09-18 R2 重跑相同）。另有 **3** 筆帶 `parents` 時間軸，那是 venue 合併沒有的問題（部分—整體關係怎麼併，`Organization.parents` 的 doc comment 明寫它與 person 的隸屬是不同的 predicate）。**誠實邊界（兩種形狀結構上看不到，R3 verify DA 第 11 列：R3 寫「一種」）**：(1) 一筆把三個機構黏在一格的 org（AERA＋APA＋NCME，R1 verify DA 第 42 列）——那是 #443「某人與雷庚玲」的形不是攣生；(2) **同一機構的單／複數誤植**（`Institute of Statistical Science`／`Sciences`，`identity-is-judged-not-matched` 記的那對）——`LooseTitleKey` 刻意不摺詞形（提名不是判定），所以若因此建出兩筆 org，它們是真的攣生而「重複群」永遠是 0。所以「重複群 0 組」承載的比它讀起來弱。重跑指令見表下方） | ⚠ **暫不做——既不實作也不拿掉** | 前二十三列裡只有第 22 列同樣是「不動既有的東西」——它的對象是一條 spec Requirement、失敗方式是被當死重刪掉；本列的對象是一條**程式**的半吊子管線（第 4 類，前言 2026-09-18 顯式擴入——R1 寫「前二十三列的裁決都是寫或不寫」，對第 22 列的「保留」為假，R1 verify 第 2／21 列），而不動它可以接受的理由是**它已經誠實了**：#553 讓 `unsupportedShape` 的訊息從一份與分支對帳的清單（`mergeableShapes`——`testUnsupportedShapeMessageNamesTheRealDomain` 釘的是「venue 在清單裡」與「org 仍擲 `unsupportedShape`」，**不是**「org 不在清單裡」：把 org 加進清單而不動 switch 它五條斷言照綠；後者自 R2 起由 `UnmergeableDivergenceScanTests.testOrganizationCandidateIsReported` 釘住，R2 寫「parity 測試釘 venue-in／org-out」，R2 verify 第 13／16 列）生成——「organization 的合併管線尚未實作——支援的是 person／work／venue」——使用者撞到時看到的是真話。**代價不是零**（R1 verify 第 4 列，R1 寫「代價是零」）：第一筆被記下的 org divergence 沒有面刪得掉（divergence 沒有移除面，#586）、只能手改 YAML——**2026-09-28 起有 `dismiss-divergence`／`akashic_dismiss_divergence`**（#586，只刪記錄、理由只進報告、要求已 commit），這項代價自此是「要人判定放棄」而不是「只能手改」；雙重零實例讓這項代價今天未兌現，且自 R2 起它一出現就由 `StoreHealth.unmergeableDivergences` 出聲。動它的兩個方向代價都更高：**實作**要替 `parents` 時間軸設計合併形狀，零實例時做等於猜（同第 10 列「形狀取決於一個還不存在的用途」）；**拿掉**（`byShape` 移除 org）是關掉記錄面——一組真的 org 攣生在合併面落地之前只能留在人的腦裡，正是 #71「判斷留不下來」的病；venue 在 #553 之前就是這個姿態，而 #553 把記錄面與合併面綁在同一個 change，因為兩者分開時記錄面先開會撞牆（本列）、合併面先開則沒有輸入（R1 寫成「關掉它等於斷言 org 永遠不會有歧異」，那是稻草人——R1 verify 第 14 列）。**本列覆寫 #555 `## Expected` 的二選一（「要嘛有合併路徑、要嘛不進 `byShape`」）與 #553 changelog「venue 不重蹈」那句對 org 的延伸——覆寫者是使用者 2026-09-11 拍板；`## Expected` 依 idd-update 契約不改，覆寫記在這裡與 issue 的 Key Decisions（R1 verify 第 1／20 列）。** 零的來源要說真話（R1 寫「不取決於任何程式」，假的——R1 verify DA 第 8 列）：它由三件事按住——org 域剛重啟（#304）；#548 的 `pendingResolution` 扣留（`OrgBootstrap` 對與既有 org 寬鬆共鍵的名字不建檔，`OrgBootstrapResolveTests.testLooseKeyCollisionWithExistingOrgRoutesToPendingResolution` 釘住）；CJK 機構名產不出 key（`akashic bootstrap-organizations` 2026-09-18 實跑：無可自動建立的候選，另有 1 個產不出 key 的機構名待人工指定）。所以本列與第 8 列同型（零的來源在別處），並繼承它的釘零義務——上面那支測試就是。**觸發條件**：org 重複群 > 0 **或** 出現第一筆含 org 候選的 divergence 記錄——任一成立即重開，那時要選的是實作或拿掉，不再是暫不做。後者自 R2 起由工具出聲（`StoreHealth.unmergeableDivergences`，warning——第 16 列的紀律：散文觸發條件沒有機制會叫醒任何人，R1 verify 第 13 列）。**出聲的面要點名、邊界要說**（R2 寫「doctor／App 各一格」，R2 verify 第 6 列）：`akashic validate` 的逐則 warning＋家族計數行、MCP `akashic_doctor` payload 的 `unmergeableDivergences` 計數與 `recordIssues` 裡的逐則（同第 13 列的寫法，R3 verify 第 23 列）、App 側欄——CLI `akashic doctor` **不印** per-record 家族（既有慣例：`validate` 印計數行的家族本次從五個變六個，這是第六個），而 warning 級的 `validate` 對它 exit 仍為 0：與第 13 列同一條誠實邊界，它做到「掃得到」、做不到「叫醒」；前者仍是散文腳本，bootstrap 的扣留是它在寫入端的閘。這也是 `no-compat-fallback` 第 2 條要量的「還有誰在走這條路」（R1 verify DA 第 22 列），但「拿掉」不路由到那條規則——理由在前言。重開時 `entity-backlink-completeness` 第 9 條邊要一起改。**若實作，`DivergenceResolve.swift` 裡帶 `org-merge-slot` 標記的每一格要同批補**（數量以 `grep -c 'org-merge-slot' Sources/AkashicStoreIO/DivergenceResolve.swift` 量、不寫死——#558 R1 verify 第 9 列說「三格不是兩格」，R2 同一個 commit 又新增兩格而三處散文仍寫三，R2 verify 第 8／15 列；#555 R2 把手寫的 `mergeableShapes` 也標進去（R1 verify 第 10 列：它與 switch 分岔不會報錯，而訊息的誠實靠它），兩個會 throw `unsupportedShape` 的入口刻意不標——它們是 loud 的，實作時不可能不碰；#558 對 venue 漏掉的是 `doomedRelativePaths` 那格：只補部分會做出一個看起來完整、對 org holder 永遠回空的閘）|
| 25 | **零實例，而實例全部是在 verify 裡被造出來的——守衛裝在 store 邊界，零量的是五個寫入者的出口**（#554 R5，使用者裁決 D8：venue 名字內容的不變式——canonical 形、無控制／格式／不可見字元、至少一個字母或數字、三張清單各無近重複對（names 的例外：兩段都帶不相交時間的沿革改回舊名，R6）——住在 `Venue.validate()`，error 級；謂詞一份在 `NameIdentity.wellFormednessIssue`、與輸出閘 `UnsafeToEmitScalar` 共用危險 scalar 的定義，「不可見」用 Unicode 的 `Default_Ignorable_Code_Point`（R6；R5 用 generalCategory 四類，VS16／CGJ 是 Mn、Hangul filler 是 Lo，全放行），ZWJ／ZWNJ 只在兩個脈絡合法——(a) 掛在同一文字**字母**上的 virama 之後（virama 與中間的標記都是基底那個文字的；右鄰居若在要是同一文字的字母／數字，空白視同沒有）、(b) 左鄰居是 join-control 文字的字母／標記／數字、右鄰居是**同一文字**的字母／數字或同一 Indic 文字的 virama（R6；R5 的「兩側是字母」對拉丁字母 fail-open；R7 再收區塊裡的標點與連續 joiner——R6 verify 第 1／19 列；R8 再收基底要是字母、兩側同文字、右側不收標記——R7 verify 第 1／26／33 列；R9 再收 virama 與標記要與基底同文字、放行詞尾 chillu 後的空白與 Bengali ya-phalaa 的 `<RA, ZWJ, VIRAMA, YA>`——R8 verify 第 6／10／11 列，D21／D22；R10 再收 virama 之前的 joiner 只在 Devanagari／Bengali 且 virama 之後要接同文字的字母——R9 對十個 Indic 文字一起放行且不看右脈絡，`क\u{200D}\u{094D}` 與 `क्` 渲染相同而各自進得了 names，R9 verify DA 第 10 列，D26），U+2800 顯式列入不可見（第 20 列）。2026-09-12 實測 live store：venue **485** 筆，四條不變式的違反字串 **0**、names 近重複對 **0**；而 R2–R5 四輪 verify 用真 binary 寫進了 `\r`／`\n`／LS／`—`／`×`／RLO／ZWSP／ALM／TAG 字元／尾隨空白／NFD 位元組／拉丁字母夾 ZWNJ／VS16／CGJ／Hangul filler——每一個都是實例，只是發生在 scratch store 而不是 live store。重跑腳本見表下方） | ✅ **寫（error 級、在 store 邊界）** | 第 18 列的理由是「零量的是出口而守衛裝在入口」；這一列多一件事：**入口有五個**（`updateVenue` 的三個名字迴圈、`addVenue`、`VenueBootstrap`）。R2→R4 三輪把閘裝在 `updateVenue` 的三個迴圈裡，每一輪都修在看見的那一圈，R4 verify 指出同一欄位還有 `addVenue`（連空字串都收）與 `VenueBootstrap`（只 trim）——`Venue.swift` 自己的 dated-variant 守衛 doc 早就寫著「守衛住在 validate → writeVenue 的交會處才擋得住所有路徑」。所以本列的裁決有兩半：**寫**（零實例但實例已被造出四次），**以及寫在 store 邊界而不是任何一個寫入面**——寫入面（`vetVenueNames`）留作入口的好訊息，不再是防線。**severity 是 error** 而非 warning，理由是 live store 0 筆違反（提級不拒絕任何既有記錄——但別的 clone 若持有手改的記錄，`akashic validate` 對它會 exit 1）且違反的後果是 displayName 直接壞掉（`displayName` 讀 `authorized`，#475）。**這與第 8／13 列的前提要對帳**（R5 verify 第 12 列）：那兩列說「per-record 的 error 級檢查全是 key 檢查、對載入後的記錄不可達」——**對 venue／organization 自 #227（authorized ⊆ names）／#422（帶時間 variant）／#473（孤兒 variant）起就已為假**：venue 的內容檢查全在寫入期、decode 不驗，所以載入後可達、`StoreHealth.perRecordIssues` 收得到；第 8 列的 pin test 只對 entry／person／divergence 改壞 key，證的是「key 錯會 quarantine」，不是那句前提。本列不翻第 8 列的裁決（`errorsFirst` 的排序仍是對的），只把那句前提的失效日期寫出來——它在本列之前就失效了，本列把可達的 error 類別從三個擴到七個。**誠實邊界**：不變式的 NFC 對 CJK 相容表意文字有損（U+FA10 塚 → U+585A）——位元組層有損、Swift 層無損（Swift `==` 早已視為相等）；ZWJ／ZWNJ 保留但只在 `NameIdentity.joinerIsLegal` 的兩個脈絡；DI 一律拒等於拒掉 IVS／蒙古文 FVS／希伯來 CGJ 等真實正字法用字——fail-closed、零實例、Claude 代裁 D9 的取捨，寫在 §5.7 誠實邊界（R6 verify 第 5／23 列）；私用區（Co）不擋，因為 doc 從未宣稱它；`canonical` 只丟 `White_Space` scalar、不刪任何其他 scalar（R6——R5 在 Character 上切，「空白＋combining mark」整個 cluster 被刪）。**觸發條件可檢查**（指令見表下方）：`akashic validate` 對 venue 的名字內容 error 應恆為 0；非零時那筆是手改或舊 binary 寫的，修法是人改 YAML（同 dated-variant 的立場，不猜、不靜默修；訊息自 R6 起逐條說改什麼）——**第 1 條（canonical 形）的確定性那一類自 #575 起另有機械修復面** `akashic repair-venue-names`（使用者 2026-09-28 裁決：乾跑逐筆列出「venue／清單[index]：before → after」、`--apply` 才寫、要求那些 venue 檔已 commit、任一筆過不了寫入閘整批零寫入；正規化後仍不合法、改完造出近重複或記錄還有其他 error、有 reference 指著舊拼法的，它只具名與理由、一筆都不動——那些仍是人改 YAML。它是名字的第六個寫入者，同樣經 `writeVenue`，本列的守衛因此不必另裝閘——「寫在 store 邊界」的裁決在這裡兌現一次） |
| 26 | **零實例，而它守的是三個閘共同的前提——閘擋工具面、守衛掃非工具面**（#554 R10 verify 第 2／5／10 列，Claude 代裁 D28：同一 work 兩條 key 邊指同一 venue。D25（repoint／demote 拒）、D27（repoint 後不得出現）、D28（apply 不得造出）三個閘守的都是「配對只由一條邊實例化」，而 store 另有手改與舊 binary 兩個寫入者不經任何閘；R10 verify 用真 binary 三次造出這個形（`apply` 兩條同刊名的 literal 邊、`repoint` 改指到本 work 已有邊的 venue），`validate`／`doctor`／App 全綠，使用者直到想 demote 才知道。2026-09-14 實測 live store：2,411 筆 work、同 venue 兩條 key 邊 **0**。重跑腳本見表下方） | ✅ **寫（warning 級、在 `Entry.validate()`）** | 第 25 列的理由是「入口有五個」而守衛裝在 store 邊界；這一列的入口在 R11 之後只剩**不經工具的兩個**（手改、舊 binary）——venue 合併**不是**入口（`resolveVenueDivergence` 對改指倖存者的 key 邊去重；R11 verify DA 第 14 列真 binary 造出的是另一個形：合併後一條 literal 邊指向 work 已 key 的 venue，它不造出重複的 key 邊，由 D33 的逐筆略過處理、提名照常；反方向倒是真的——它對 entry 的 key 邊去重時會把與被併鍵無關的既有重複 key 邊一併收成一條，是 #572 落地前唯一的移除面，R12 verify logic 第 38 列），而那兩個正是閘擋不到的。**守衛與閘是同一條不變式的兩半**：閘讓工具面造不出這個形，守衛讓已經在庫裡的看得見——少了守衛，D25 的拒絕就是使用者第一次知道自己的 store 走進這一格的時刻，而那時他要做的操作已經被擋。**severity 是 warning**，理由與第 13 列同型：記錄合法可載入（兩條邊各自指向存在的 venue），失效的是判定逆轉的前提；升 error 會讓一筆只能手改才修得好的 work 擋住自己所有的寫入，而處置面當時還不存在（#572；2026-09-28 起有 `resolve-venues --drop-venue`，severity 不因此重開——warning 的理由是「記錄合法可載入」，與處置面在不在無關）。與第 23 列（可達性是本 change 造出來的）成鏡像：那一列是新面讓不可達變可達、守衛與面同批；這一列是新閘讓可達變**不可達**（對工具面），守衛守的是關掉之前寫進去的與繞過工具寫進去的。R15 起有家族前綴（`Entry.duplicateVenueEdgePrefix`）、`StoreHealth.duplicateVenueEdges` 計數（doctor／App 各一格）、每筆 work 最多列 20 個 venue（第 27 列同一批，R14 verify regression 第 22 列、security 第 18 列）。**觸發條件可檢查**（指令見表下方）：計數應恆為 0；非零時先看那筆是不是 R11 之前的 binary 寫的（`apply` 的兩次歸戶）——修法是刪掉多餘的邊，以 `resolve-venues --drop-venue` 刪（#572，2026-09-28 落地；之前只能手改 YAML） |
| 27 | **零實例，而它是同一句不變式的另一半——第一半的守衛結構上照不到它**（#554 R13 verify DA 第 16 列，Claude 代裁 D36：同一 (venue, work) 上 ≥2 個正規化後不同的 confirmed literal。§3.5 把配對唯一性寫成一句 normative 的兩半，第 26 列守的是第一半（work 的邊），第二半住在 venue 的 references 上——`Venue.validate()` 不掃 verdict 配對、`StoreHealth` 沒有對應項，全樹「個不同的 confirmed literal」只出現在 `confirmedLiteral` 的**拒絕訊息**，零 validate／doctor 呼叫端。而真正造出第二半的路徑（work 合併把兩筆 work 的邊連同 verdict 併到一筆——R13 verify DA 第 3 列純工具面重現：`--apply` 兩個刊名變體 ＋ `resolve-divergence`）結構上**不會**點亮第一半的燈：被併 work 連同它的邊一起刪掉，倖存者只剩一條邊，validate 零診斷、`--demote` 撞 D23。2026-09-15 實測 live store：venue **485** 筆、對同一 work 持 ≥2 個正規化後不同 confirmed literal 的 **0** 筆。重跑腳本見表下方） | ✅ **寫（warning 級、在 `Venue.validate()`）** | 第 26 列的理由是「閘與守衛是同一條不變式的兩半」——閘擋工具面、守衛掃非工具面；這一列是**同一條不變式的另一半要有自己的守衛**：兩半在偵測面上互斥（造出第二半的路徑不點亮第一半的燈），所以第 26 列的量測「應恆為 0」只兌現了一半，而本檔自己的紀律是「寫出條件而不是只寫數字」。裁決有兩半：寫（零實例但實例已在 verify 裡被造出、且 R14 之前純工具面造得出），**以及不改成只修散文**——DA 給的另一個出口是把 §3.5 那句改成「第二半今天沒有掃描面」，那等於把一個已知可達的狀態留在「只有 demote／repoint 撞上時才知道」。**severity 是 warning**，理由與第 26 列同型：記錄合法可載入，失效的是判定逆轉的前提（D23 從此拒那筆 work 的 demote／repoint）；處置是手改 YAML 留一筆——#572 的 `--drop-venue` 刪的是邊不是 verdict，這一格至今沒有工具面，升 error 會讓一筆只能手改才修得好的 venue 擋住自己所有的寫入。**鍵不是一把是兩把，掃描兩類都掃**（R15，Claude 代裁 D39；R14 verify Codex 第 3 列、requirements 第 5 列：R14 寫「鍵與 D23／`verdictEqualityKey`／#486 同一把（`matchingKey`）」——假的，D23 的拒絕（`confirmedLiteral`）比**位元組**，只差大小寫或 NFC 形的兩筆 confirmed 讓 demote／repoint 必拒而 R14 的掃描零診斷）：以位元組相異的 confirmed 分組，正規化後不同＝不變式的違反、只差位元組＝重複的判定記錄（工具面以 `verdictEqualityKey` 去重、寫不出它），兩類同一家族前綴（`Venue.confirmedLiteralAmbiguityPrefix`）、措辭分開；`StoreHealth.confirmedLiteralAmbiguities` 有計數（doctor／App 各一格——R14 verify regression 第 22 列：兩族 per-record warning 沒有家族，MCP 截 20 則、App 預覽 5 則時可能完全看不到）；每筆 venue 最多列 20 筆 work、其餘一句概括（第 16／18 列：讀取路徑上對未信任內容跑，鄰居剛為此加了上限）。**生產端自 R15 起三個面都 fail-closed**（D38；R14 verify Codex 第 1 列 HIGH：D34 只裝在合併路徑，apply／repoint 對「目的 venue 已對該 work 持有另一個 confirmed literal、沒有對應的邊」的形照寫）：`apply` 對它逐筆略過並具名（`skippedConflictingConfirmedLiteral`）、`repoint` 對預測後的 verdict 集合驗、整批拒絕零寫入。**R16（R15 verify 30 列，6 席齊）**：「位元組」要真的是位元組——R15 的去重寫 Swift `==`（canonical equivalence），NFC／NFD 的兩筆被收攏成一筆、兩類 warning 都不出而 D23 照拒（requirements 第 1 列 HIGH；D42 改 `Set<[UInt8]>`，與 `confirmedLiteral` 同一把、O(N)）；混合情形（三筆裡兩筆只差位元組）第一類訊息點名那一組（第 23 列）；概括句不進家族（DA 第 29 列：帶家族前綴時 `StoreHealth` 把它算成一則，25 筆 work 報 21——改用 `Entry.perRecordCapSummaryPrefix`）；生產端的閘也比位元組、同一 literal 的另一個拼法也略過／拒（D43，Codex 第 3 列 HIGH：放行同鍵異拼法之後 demote 還回舊拼法）、apply 的閘移到重複邊檢查之後（D44，regression 第 2 列 HIGH）。**R17（R16 verify：31 findings 合併成 24 列，6 席齊；列號＝報告的合併列號）**：合併是第三個會動到同一批 verdict 的面——收攏的勝者政策在拼法位元組不同時改由倖存配對自己的那筆勝、收攏列印兩個拼法（D47，第 1 列 HIGH；#468 的弱血統優先只在同拼法時適用）；近重複組上限只數真的出聲的組（D48，第 2 列 HIGH：21 組合法沿革曾被判 error、所有寫入面關門）；D43 訊息兩桶同時說（D50，第 7 列）；混合註記截在 5 組時揭露（第 10 列）；第 27 列量測段的 grep 註記改成它量的單位（第 9 列）。**R18（R17 verify：31 findings 合併成 20 列，6 席齊）**：收攏的勝者先看**活著的邊**（D51，第 1 列 HIGH：keeper 對某 work 的 confirmed 可能沒有邊，被併記錄的那筆才是那條邊記錄的字；三條收攏路徑同一個政策，rename 只收攏動到的鍵——D53，第 3 列）；近重複的概括句分「真違反」與「同名段過多」兩類、authorized／variant 也先分組、整筆記錄另有 100,000 對求值總量上限（D52，第 7／8 列）；家族計數是下限、`cappedRecords` 自成一族（D54，第 5 列）；第 25 列的量測 grep 補兩類求值上限句並排除概括句（第 11 列）。**R19（R18 verify：5 席 session limit、Codex 席 3 列，不完整）**：rename 的收攏以鍵整組算（D55，第 1 列 HIGH：R18 的單一槽位記帳讓三方碰撞由 YAML 順序決定）；`cappedRecords` 以記錄計（D56，第 2 列）、App 側欄渲染它且家族值標成下限（D57，第 3 列）。**R20（R19 verify：34 列，5 席齊、Codex 席 HTTP 429）**：早已指向新鍵的死 verdict 不論 field 一律丟（D58，第 1 列 HIGH：D55 的分組含 field，異 field 的死 rejected 逃過、rename 後與遷來的 confirmed 成 #486 矛盾對；merge 對同一形狀早已整批拒）；`total`／`errors` 也是下限（D59，第 7 列）；**本列的「應恆為 0」只涵蓋 venue×work**——其餘六格（person／organization 持 work、三種 holder 持 person）沒有掃描面，rename 也不替它們判定（第 4 列，寫進 §3.5）。**R21（R20 verify：26 列，5 席齊）**：D58 的丟棄退場——rename 對目的鍵上已有 verdict 的 holder 具名拒絕、零寫入（D60，第 1–5 列 HIGH：D58 只在 holder 另有被改寫 verdict 時生效，且生效時是無乾跑、無逆操作的判定刪除，與本表第 13 列「死 verdict 的處置是人的重新消歧」相牴觸）；rename 自此沒有任何會刪判定**內容**的路徑（R22 D62 之後才為真：R21 仍以拼法位元組折疊、會丟 judgement 不同的那筆——R21 verify DA 第 14 列；D61 把 quarantined 檔納入 D60 的母體——**R23 D63** 改成位元組比對，R22 的行級 needle 含空白、被 YAML 折行擊穿）。**R22（R21 verify：37 列，6 席齊）**：D62 留下的同鍵異 judgement 沒有掃描面（第 14 列）→ 第 28 列。**觸發條件可檢查**（指令見表下方）：兩個計數應恆為 0；非零時那筆是 R14 之前的 work 合併、手改或舊 binary 寫的——修法是刪掉不屬於那條邊的 confirmed verdict |
| 28 | **零實例，而它守的是另一條裁決刻意留下的狀態——「零資訊損失」把一筆判定從當場刪改成留著，而留著的那一格沒有任何面看得見**（#554 R22 verify security 第 14 列，Claude 代裁 D64：同一筆記錄對同一配對持有 ≥2 筆同 field 的判定記錄（`verdictEqualityKey` 相同）。工具面的寫入以那把鍵去重、寫不出它（`appendIfAbsent`）；rename 自 R22 D62 起**刻意保留**它——只折整筆**位元組**相等的重複（R24 D65：R23 的鍵是合成 `Hashable`、canonical 相等，NFC／NFD 曾被折掉；訊息的「全部完全相同」自 R24 起也以 `byteExactKey` 判），R21 之前會當場折掉並回報；`contradictoryVerdicts` 只比 confirmed×rejected、第 27 列的第二類以位元組相異分組，都認不得它；而下一次 person／venue 合併會以 #468 的血統層收成一筆。第 27 列第二類已報的那一格（venue×work 的 confirmed、只差位元組）**不重報**——同一件事出兩則是雜訊；**只在每筆各有自己拼法、且 judgement／rests-on 全同時**（R25 D67／R26 D71；R24 verify 第 8／10／18 列：第 27 列以位元組去重、看不到「同一拼法出現兩次」，R24 的排除把 `Alpha`／`Alpha`／`ALPHA` 這種混合組整組吞掉；R25 verify 第 1／3／5／10／12／18 列 HIGH：R25 的排除不看 kind，`Alpha`／`ALPHA` 各帶相反 judgement 時三個面只說「只差位元組…留一筆」——一個真的證據衝突被一句銷毀判定的指令取代），家族計數不含被排除那一格（accessor doc、doctor 描述、App help 寫明）；訊息自 R25 分三向（拼法只差位元組／judgement 或 rests-on 不同／全同，R24 verify 第 3／11／16 列）；本族報的是它認不得的：位元組相同的重複、rejected 的重複、person 配對的重複、person／organization 持有的重複。每筆記錄至多 `Entry.perRecordWarningCap` 則、其餘一句概括（首版無上限，一個 20 筆 work × 6 對的 venue 出 120 則、把 doctor 的 `count` 從 20 推到 140，全套測試抓到）。**這個上限三個面共有**（R24 D66；R23 verify Codex 第 2 列）：它在產生訊息時就生效，CLI `validate` 只是不加面級的 20 則截斷——被截的記錄在 CLI 也只有概括句，`ValidatePerRecordCapCLITests` 釘住。**上限在渲染之前套**（R26；R25 verify Codex 第 4 列：R25 先把全部組渲染完再 `prefix(cap)`）。**有上限的是組合式的六族**（R26 D72；R25 verify DA 第 2 列 HIGH：R25 寫「五族」、漏掉 person 近重複——它當時無上限，200 個共用 matchingKey 的名字真 binary 吐 19,900 則、7.6 MB、`cappedRecords` 0；R25 還說其餘家族「每筆至多一則、撐不爆」，對六族全假——它們是每筆 reference／配對／記錄各一則、與資料項數線性）：venue 名字內容、venue 近重複、person 近重複（#576 在本輪落地：先以 matchingKey 分組、一組一則、每筆記錄 20 組、組內 5,000 對、**整筆 100,000 對**——R27 D76 的第五層，warning 級只計數；R28 起小組先評估、預算不鎖存，R27 verify DA 第 22 列：插入序讓巨型同鍵組把其後的真違反整批餓死）、重複 venue 邊、confirmed literal、重複判定記錄；venue 的求值上限命中自 R26 起也留 `perRecordCapSummaryPrefix` 概括句（第 23／31 列：曾漏計 `cappedRecords`）。2026-09-16 實測 live store：`重複的判定記錄` **0**。重跑指令見表下方） | ✅ **寫（warning 級、在 `StoreHealth`）** | 第 23 列的理由是「可達性是本 change 自己造出來的」；這一列多一件事：**可達性是本 change 的另一條裁決刻意造出來的**——D62 為了不刪判定而留下這個狀態，代價正是它在中間那一格看不見。守衛不是在替 D62 擦拭，是 D62 的另一半：留著而不出聲，等於把「rename 當場刪、有回報」換成「合併時刪、回報在另一個命令的輸出裡」，後者未必更好。severity 是 warning，理由與第 13／26 列同型：記錄合法可載入，兩筆各自都是一個人的判定，error 會讓一筆只能手改才修得好的記錄擋住自己所有的寫入。訊息把三個來源（手改、舊 binary、rename 帶過來）與下游（合併收攏）都說出來——第 27 列第二類的訊息曾只怪手改與舊 binary，而 rename 就會帶過去（R22 verify 第 25 列，同輪補上）。**觸發條件可檢查**（指令見表下方）：計數應恆為 0；非零時先看是不是剛 rename 過——那兩筆在舊鍵上就已經並存，處置是留一筆或改其中一筆的 value。**change `resolution-verdict-states` 補記（2026-09-25，#619／#636）**：分組鍵從 `verdictEqualityKey` 換成**記錄鍵** `verdictRecordKey`——同一配對的 nominated 與 judged 是兩筆記錄不是重複（#636 並存），未決記錄只有整筆位元組相同才算重複（同一配對的多次查證是設計上要保留的）；訊息裡「工具面的寫入以…去重」同步改寫 |
| 29 | **零實例，而它守的是另一個守衛的前提——一個常數必須大於等於全樹每個 sink 的輸出上限**（#554 R31／R32：`ErrorDisplay.inputScalarCeiling`＝4,096。D83 讓逃脫只讀每行前 ceiling 個輸入 scalar，等價性的前提是「任一 sink 的輸出上限 ≤ ceiling」——每個輸入 scalar 至少產生一個輸出 scalar，所以輸出上限之內的字串不受截短影響；前提一破，被 ceiling 截短的行會冒充完整的行、且每個 sink 都綠。2026-09-18 實測 Sources（HEAD `58bab46d`，R33 重量）：`displaySafeError(max:)` 57 站點、`displaySafeClipOnly(max:)` **39** 站點、sink 宣告的預設值 3 個（`displaySafeMultiline`／`displaySafeAssembled`／`displaySafeErrorMultiline` 的 400）、呼叫端字面的 `maxLineLength:` **0** 個，最大 4,096，**超過 ceiling 的 0**。**R32 寫的是 18／3，而它自己附的腳本第一次重跑就給出 39／5**（R32 verify 第 3／10／15 列，三席獨立重跑）：R32 的第三族（`maxLineLength` 與 `max` 兩個 `Int =` 預設值一起掃）把 `displaySafe`／`displaySafeInvisible` 的**生產者輸入預算** 200 也掃進來——它們不是 sink、與 ceiling 的前提無關，卻撐著那一族的地板（刪掉三個真的 sink 預設值裡的兩個仍綠）；clipOnly 的地板 15 是照量錯的 18 打的折，允許 62% 的站點靜默消失。R31 的第一版只掃 `displaySafeError(max:)` 與字面 `maxLineLength:`——後者全樹零命中、多行家族的上限是宣告的預設值 400、`displaySafeClipOnly` 完全沒掃，於是把預設值改成 8,192 守衛照綠（R31 verify 第 6／16／30 列）；R32 分三族各自有地板；R33 把生產者拿出族、分四族、地板照實測訂（50／35／3／0——第四族零實例、地板 0 明寫「可為空，不撐任何地板」）。重跑腳本見表下方） | ✅ **寫（四族各自有地板；第四族可為空）** | 第 16 列的理由是「裁決依賴守衛」（門檻到了才重開）；這一列更緊：**另一個守衛的正確性依賴它**——`testInputCeilingDoesNotChangeClippedOutput` 證的是「有界＝無界」，而那個等式只在 sink 上限 ≤ ceiling 時成立，本列守的就是那個前提。零的來源與前面各列都不同：不是還沒發生、不是掃乾淨了、不是在這台機器上，是**兩個數字今天恰好對齊**（最大 sink 4,096＝ceiling 4,096），而改任一邊都是一行 diff、不會有任何測試因此變錯（每個 sink 自己的測試只看自己的數）。**地板要分族**：R31 的單一地板由 57 個 `displaySafeError` 站點撐著，`maxLineLength:` 那一半通過的方式是「什麼都沒找到」——與第 3 列「未涵蓋不得冒充通過」、R29 NC4「空掃描不是通過」同一個形狀，在同一支守衛裡再犯一次。**而族要照它守的東西分，地板要照實測訂**（R33）：R32 分了族卻把兩個不是 sink 的生產者預設值混進第三族，又把一個量錯的數當地板——這一列自己在同一天就示範了「寫死的計數會與目錄分岔」，且分岔發生在它宣稱可重跑的腳本上。**觸發條件可檢查**（腳本見表下方）：超過 ceiling 的站點數應恆為 0；非零時要一起抬 ceiling（並重量線性），不是放寬那一個 sink |
| 30 | **零實例，而上限守的記錄設計上只增不減**（#619 R1 verify security：未決腿的三個上限——一次 200 個 id、20 個 digest、單句說明 4,096 位元組。2026-09-25 實測 live store 8,747 筆 reference：最長的判定理由 687 位元組、rests-on 最多 3 個；`resolution-undecided` 0 筆——format 19 尚未部署。重跑腳本見表下方） | ✅ **寫（整批拒絕、零寫入、不截斷）** | 第 18 列的上限守的是一次遞進來的字串，並夾在兩個量測錨點之間；這一列多一件事：**被守的記錄設計上不退役**——未決是查證歷史，只收位元組相同的重複，一個會迴圈的呼叫端每跑一次就多留一筆。說明與 digest 的上限各有量測錨點（687 位元組的約 6 倍、3 個的約 7 倍）；**id 數 200 沒有可量的母體**——它限的是一次呼叫的批次大小、不是記錄內容，取 CLI 單批 triage 的量級，這一格是推估不是量測（R2 verify DA 第 16 列）。**誠實邊界**：上限只約束一次呼叫、不約束累積——累積由預算 warning 出聲：venue 側是第 16 列，person 與 organization 側是第 31 列（#645；organization 側由 #643 的未決腿加入）。**觸發條件可檢查**（腳本見表下方）：任一筆 reference 的說明或 rests-on 逼近上限時重開。**#645 落地、原本寫下的第二個觸發條件成立（2026-09-26）：重開後裁決不變**——三個上限仍只擋單次呼叫，累積改由第 31 列出聲（量記錄檔的位元組）；上限的量測錨點沒有變 |
| 31 | **零實例，而它是一條已有守衛的曲線換了持有者**（#645：person／organization 的記錄檔逼近讀取上限。第 16 列守 venue 側；person 側的增長來源是一個人的著作數，#619 起多了不退役的 `resolution-undecided`（一筆說明可寫到 4,096 位元組），#643 起 organization 同。2026-09-26 實測 live store：person 4,575 筆、最大檔 10,869 bytes（`chen-chien-hsiun`）；organization 13 筆、最大檔 717 bytes；門檻 4,194,304——0 實例。重跑腳本見表下方） | ✅ **寫（warning 級、在 `StoreHealth`，門檻與量法同第 16 列）** | 第 16 列的理由是「裁決依賴守衛」——暫不改形狀之所以可接受，是因為漲到門檻時工具會出聲；這一列是**同一條曲線的另一個持有者一直沒有那盞燈**，而讓它開始漲的是一個新面（未決腿）。所以理由不是第 1 列的「不寫就沒有跡象」，是**第 30 列自己寫下的誠實邊界**（上限只擋單次呼叫、不擋累積）要有工具面兌現，否則那句邊界就是一句沒有後續的散文。**量的是檔案位元組**：初版照第 16 列用節點換算的筆數，R1 verify 指出未決記錄會先撞上位元組上限而加了「內容位元組」軸，R2 verify DA 再指出節點軸對 store 檔根本不生效——兩次修的都是估計，真正的預算是讀取路徑的 `maxBytes`，檔案大小已含 YAML 跳脫與 verdict 以外的內容，直接量它（第 16 列同日更正）。**門檻不另立常數**（`recordFileWarningBytes` 兩族共用——同一個預算的第二份描述會分岔）。**前綴分開**（`holderVerdictBudgetPrefix`）：兩族計數分開，而處置的第一步相同（先查重複記未決）。**誠實邊界**：warning 只在讀取面計算，~~寫入路徑有 2 倍寬限——一次夠大的寫入（judge／refute 的理由沒有長度上限）可以從門檻之下直接跳過讀取上限，warning 來不及出聲；那是寫入閘的缺口，記 #648。~~ → **#648（2026-09-28）更正並關閉**：前半的前提量錯了——encode 的語意 canary 一直以讀取上限（1 倍）擋著，超過 8 MiB 的寫入從未落盤，只是拒絕不具名、而多檔寫入面在它觸發之前已有檔落盤（撕裂）。現在寫入的位元組上限是讀取上限、具名拒絕，2 倍只給不增長的改寫，多檔面在任何檔落盤之前逐筆 preflight，judge／refute 的理由上限 4,096 位元組——見第 39 列。warning 仍只在讀取面計算：它管漸進的增長，單步的跳躍由寫入閘擋。**觸發條件可檢查**（指令見表下方）：計數應恆為 0；非零時先看那筆記錄的 `resolution-undecided` 筆數 |
| 32 | **零實例，而謂詞寫寬的方向是 Unicode——前件看起來是「數字」，實際是「任何書寫系統的數字」**（#589：ISSN／ISBN／ORCID 共用的 `idCompact` 以 `CharacterSet.alphanumerics` 過濾、以 `wholeNumberValue` 取值，兩者都認 Unicode 數字；全形與阿拉伯-印度數字寫成的號過得了 mod-11、原樣成為 `normalized`。#556 R4 verify security 席實測。2026-09-26 實測 live store 141 個 issn／orcid／isbn 值（issn 59、orcid 42、isbn 40；YAML 解析。先前寫過 1,739（行級 regex）與 282（本列腳本把每個值掃了兩次，R1 verify 四席同指）——兩個都不要用），另有 DOI 註冊者段同形（R1 verify：`isNumber` 認全形；live store 2,445 個 DOI），非 ASCII **0** 筆；新 binary `validate` rc=0、無新隔離。重跑腳本見表下方） | ✅ **寫（在 `idCompact`，非 ASCII 的英數字元換成必定失敗的 `?`；已入庫的會在載入時被隔離）** | 第 2 列的理由是「前件寫寬了會誤傷」；這一列相反——前件寫寬了會**放行**，而放行的東西看起來是對的（第 4 列的偽裝性）：一個全形寫成的 ISSN 過得了 check digit，而 `identity-is-judged-not-matched` 讓識別碼相等**單獨**就能做身分判定，所以它是一個看起來像決定性證據的假號。修在 `idCompact` 而不是三個呼叫端，因為三個呼叫端共用它，修一處就全部關掉；**換成 `?` 而不是濾掉**，因為濾掉會讓夾在 ASCII 號裡的非 ASCII 字元被靜默吞掉、號照樣通過。判斷在 `uppercased()` 之前做（合字 `ﬀ` 轉大寫後是 ASCII 的 `FF`）。**已入庫的處置是隔離而不是 warning**：這一族在 decode 時本來就以 `ISSN(v) != nil` 驗證、不合法整檔隔離（`IdentifierYAML.make`），收緊謂詞之後非 ASCII 號自然落進同一條路，與其他不合法的號同級；零實例所以不需要遷移（`no-compat-fallback`）。PMID 以 `UInt64(s)` 解析、ROR 以 `Int(…)` 加 ASCII 字母表，都只收 ASCII，不在此列；DOI 的**註冊者段**同形（`isNumber`）、R1 起一併只收 ASCII，後綴本來就可以含 Unicode、不動。**觸發條件可檢查**（腳本見表下方）：非 ASCII 數應恆為 0；非零時那筆在新 binary 下會被隔離，修法是把號改寫成 ASCII |
| 33 | **一半零實例、一半兩筆，而同一個檢查只寫了三分之一**（#579、#652：work 的三種參照邊——`.key` 作者、`.organization` 作者、`venues[].key`——只有第一種有懸空檢查（`crossRecordIssues` 的「作者 key 沒有對應的 people 檔」）。2026-09-26 新 binary 對 live store：懸空的 venue 邊 **0** 筆；懸空的團體作者 **2** 筆（`anon1954technical` 的 `American Psychological Association`、`anon2014pisa` 的 `OECD`——2026-08-20 #340 批次手寫，payload 是名稱不是 key，而且不是合法 StoreKey）。重跑指令見表下方） | ✅ **寫（warning，在 `crossRecordIssues`；key 不是合法 StoreKey 時訊息另說「不可能對應任何記錄」）** | 第 13 列的理由是「跡象住在錯的地方」；這一列更早一步——**跡象根本不存在**，而同形的檢查就在隔壁：person 那一半有、另外兩半沒有，是檢查寫的時候只有 person 那一種邊。所以它不是新守衛的裁決，是把既有守衛的前件補完（第 2 列的「前件多寬」，方向是寫窄了）。**severity 是 warning**，理由與既有的懸空作者相同：懸空參照讓畫面少東西、不毀資料，而解析中途本來就會有；#579 另提的「error、與 person／organization 的 key 檢查對齊」不採——那些是**記錄自身**的 key，load 就 quarantine；這裡是**參照**，quarantine 整筆 work 會讓一條壞邊把整篇作品藏起來。非法 key 另附說明，因為記錄的 key 在 load 時就驗過，一條非法 key 的邊不是「目標還沒建」而是「永遠建不出來」。工具面不寫得出它（`attribute-org` 先驗 org 存在），實例只可能來自手寫、刪除或改名。**觸發條件可檢查**：venue 邊的數應恆為 0；團體作者那兩筆的處置是人的判斷——建 org 記錄再改 key，或改回 `literal:` 交給 `resolve-organizations`（目前沒有把 `.organization` 退回 literal 的工具面，只能手改 YAML） |
| 34 | **零實例，而第 33 列補完 work 側之後，同一種懸空在 person 與 organization 側仍然沒有檢查**（#660：第 7 條邊 `Person.profile.affiliations` 與第 8 條邊 `Organization.parents` 的 `.key` 指向不存在的 organization。#656 R1 verify DA 以 scratch store 實測 `akashic validate` rc=0、零 warning；#656 讓隸屬那一半在匯出表裡以 `affiliation_kind = 'organization' AND organization_id IS NULL` 分得出來，但要自己寫 SQL 才看得到；上級機構那一半在任何面都看不到——`organization.parent_id` 只看現任上級，懸空、字面、沒有上級三者都是 NULL（R1 verify DA）。2026-09-27 實測 live store：organization 13 筆、person 4,575 筆，懸空的隸屬 key **0**、懸空的上級機構 key **0**。重跑腳本見表下方） | ✅ **寫（warning，在 `crossRecordIssues`；key 不是合法 StoreKey 時同第 33 列另說「不可能對應任何記錄」）** | 第 33 列的理由是「同一個檢查只寫了三分之一」；這一列是**那一次補完只補了 work 那一側**——封閉列舉裡指向 organization 的邊有五條——第 1 條的 `.organization` 作者、第 7 條、第 8 條，以及第 9 條（divergence 候選的 organization shape）與第 13 條（verdict value 的 `organization:` holder）；後兩條早有檢查（懸空候選的 warning、死 verdict 掃描）。第 33 列照 work 的欄位窮舉，第 7、8 條住在別的形狀上而沒被看到（R1 verify 指出本列初稿寫「三條」，在自己講的那條軸上數錯）（`entity-backlink-completeness` 記過相鄰的形狀：補了形狀、沒窮舉它的欄位——這次是窮舉了一個形狀的欄位、沒窮舉指向同一個目標的其他形狀）。**severity 是 warning**，理由同第 33 列：懸空參照讓畫面少東西、不毀資料，quarantine 整筆 person 會讓一條壞隸屬把整個人藏起來。**literal 不報**：未歸戶的隸屬是誠實狀態（`literal-first-then-key`）。上級機構的環已有檢查（#179），懸空的上級在那條檢查裡只是「不成環」、不出聲——本列補的是它沒問的那一半。實例只可能來自手寫、刪除 organization 檔、或手改 org key（`resolve-organizations` 升格前先驗 org 存在）。**觸發條件可檢查**：兩個數應恆為 0；非零時處置是人的判斷——建那筆 organization，或把 key 改回 `literal:` 交給 `resolve-organizations` |
| 35 | **零實例，而可達路徑是一次相等定義的替換打開的**（#582：同一筆記錄裡 ≥2 筆**非判定** reference 彼此 canonical 相等——只差 NFC／NFD，或位元組完全相同。#554 R25／R26 把 `paginated` 冪等閘、`UpdatePerson` 的 append-only、`AddOnlyEnrichment.applied` 的去重換成位元組相等（D69／D73），於是只差位元組的變體寫得進來；而第 28 列那一族第一行就只看 verdict 欄位。2026-09-27 實測 live store：非判定 reference 90 筆、重複組 **0**；新 binary 的 `validate` 對 live store 這一族 0 則。重跑腳本見表下方） | ✅ **寫（warning，`StoreHealth.duplicateReferences`；不設 per-record 上限）** | 第 28 列的理由是「可達性是本 change 的另一條裁決刻意造出來的」；這一列同形而**對象不同**：那一列是 rename 為了不刪判定而留下的判定記錄重複，這一列是位元組相等的去重為了不丟位元組而收下的非判定 reference 變體——同一個取捨（零資訊損失）在兩類欄位上各開一格，第 28 列只照判定那一格。issue 給的另一個出口是「裁決變體是合法並存、不報」：不採，因為並存的兩筆對同一件事說了兩次，合併時 `fieldsLostByMerging` 以位元組比對，倖存者只有其中一種拼法時合併會被擋下（issue 記載的路徑），那時才第一次出聲、而且出在錯的操作上。**位元組完全相同的也報**、措辭分開，一組裡兩種都有時兩件事都說。初稿寫「位元組完全相同的工具面寫不出」，R1 verify DA 以真 binary 否掉：`dropAuthors`／`splitAuthors` 對 work 的 references 直接 append，同一個移除做兩次就留下兩筆逐位元組相同的記錄。**計數的單位是組**，一筆記錄可以有好幾組。**誠實邊界**：只看 canonical 相等——只差 Cf 字元（ZWSP 之類）或只差 rests-on 順序的兩筆不報，它們在 D69／D73 之前也不被 `==` 去重，不是那次替換打開的格。**不設上限**：一組一則，則數至多是該記錄非判定 reference 數的一半——線性家族（與死 verdict 同類），不是第 28 列那種組合式家族。**severity 是 warning**：兩筆都合法，處置是人決定留哪一筆。**觸發條件可檢查**：計數應恆為 0；非零時先看是不是 NFC／NFD 變體——那是位元組相等的去重收下的，確認兩筆說的是同一件事後留一筆 |
| 36 | **零實例，而製造它的通道是新開的，且它的錯看起來是對的**（#588：同一個 ISSN 掛在 2 個以上 venue。ISSN 的 mod-11 檢查碼擋得住亂碼，擋不住**合法但屬於姊妹刊的號**——JRSS-A／B／C 在模糊搜尋下都會命中，而 #556 起 `akashic-verify-venue` 把查到的 ISSN 寫進 venue。同輪補上移除面（`update-venue --remove-issn`／MCP `remove_issn`）：在此之前掛錯的號只能手改 YAML。2026-09-27 實測 live store：venue 485 筆、ISSN 值 59 個、distinct 59、掛在 ≥2 個 venue 的 **0**。重跑腳本見表下方） | ✅ **寫（warning，在 `crossRecordIssues`，以正規形比對）** | 第 4 列的理由是「錯誤的偽裝性」——猜錯的結果看起來是對的；這一列同形而更尖：`identity-is-judged-not-matched` 讓識別碼相等**單獨**就能做身分判定，所以一個掛錯刊的號不只是一筆錯的欄位，是一個看起來像決定性證據的假身分宣稱，之後以它為據的攣生判定都建在上面。與第 32 列（前件寫寬會放行假號）不同：那一列的號本身不合法、改謂詞就擋得住；這一列的號合法，錯的是它掛在哪裡，只有跨記錄比對看得到。**severity 是 warning**：兩本刊共用一個號可能是其中一本記錯，也可能兩筆是同一本刊（那時要走合併），那是判斷不是修檔；訊息把兩個出口都說出來。**移除面與守衛同批**：只有守衛而沒有移除面，warning 出現時唯一的出路是手改 YAML（`replace-endnote-and-zotero` 第 4 條）。移除的理由只進報告（使用者 2026-09-27 裁決；git 保存的是移除前的檔，理由要留在 git 得由操作者寫進 commit message），移除前要求那筆 venue 檔已 commit（`assertRecordsRecoverable`，#573 的閘一般化）。**觸發條件可檢查**（腳本見表下方）：計數應恆為 0；非零時先查兩本刊是不是同一本，不是就移除記錯的那個號 |
| 37 | **零實例，而舊稽核的謂詞對新長出來的寫入面結構上不可能為真——而正確的謂詞不存在**（#658：CLI 的每一個葉命令、`resolve-people`／`resolve-venues`／`resolve-organizations` 的每一條腿，都要在 `Sources/akashic/WriteGateRulings.swift` 的裁決表有一格——過閘、不閘並寫出這一格自己的理由、或不寫 store。舊稽核（`DestructiveTargetGateTests`）只認布林的 `--apply`／`--reject` 宣告：預設就寫的命令與逐 id 的寫入腿長出來時它不會紅（#653 R1 verify requirements 席）。同一形狀先前的實例：#580 R1 的 `authorize-names`（宣告寫成 `: Bool` 而漏網，也一直沒有閘）、#650 的 `rename`（沒有閘）與 `rename-person`（呼叫閘卻不在手寫清單），以及本輪才發現的手寫清單裡的 `migrate-venue-variants`（列為過閘卻從未呼叫閘——它的 `--apply` 自 #554 R15 起一律拒絕）。2026-09-28 實測（與 #575 同批整合後；`repair-venue-names` 是第 57 格）：CLI 葉命令 57 個、裁決 57 格、兩個差集皆空（過閘 16、逐腿 3、不閘 18、不寫 20；同日 #586 R1 verify 把 `dismiss-divergence` 改為過閘後是 17／3／17／20）；三個逐腿命令的旗標 14／7／7 條、差集皆空。重跑指令見表下方） | ✅ **寫（測試：執行期命令樹雙向比對、不閘的格理由非空、過閘的集合由表現算且與閘的呼叫點一致、逐腿以真 binary 驗）** | 第 21 列的理由是「既有守衛的謂詞對那一類成員結構上不可能為真」——那一列換一個謂詞（棘輪）就解決了；這一列換不了，因為**「該不該閘」是裁決不是性質**：#653 的「只閘不可逆的」沒有一句可機械判定的「可逆」（`resolve-people` 的逐篇判定沒有把作者位退回 literal 的工具面，而它不閘）。所以守衛不判斷對錯，只要求**每一格都有裁決、不閘的寫出自己的理由**，並釘住兩件可機械核對的事：表說過閘的命令原始碼真的呼叫閘、反之亦然；逐腿的裁決對真 binary 成立（過閘的腿未指名目標時被擋、不閘的腿的樣本走得到參數檢查之後）。這是第 7 列的形：它兌現的是一個嚴格更弱的命題——通過不代表理由對，理由仍是人寫的。**過閘的集合改由表現算**：先前手寫的 `destructiveCommands` 與測試裡的第二份清單已經分岔（測試那份漏了 `migrate-identifiers`／`enrich`／`enrich-from-zotero`，「成員真的呼叫閘」對那三個從沒驗過），`--yes` 的說明也改由同一張表產生。**誠實邊界**：逐腿只做三個命令——`update-venue`、`update-person`、`library` 以命令為單位裁決，它們新長一個寫入旗標時看不到；裁決為不寫 store 的命令，測試只驗它不呼叫閘、不驗磁碟。**觸發條件可檢查**（指令見表下方）：兩個差集應恆為空；非空時在表加一格——過閘、不閘（寫理由）或不寫 store，不從鄰居類推 |
| 38 | **零實例，而它守的是讀取面對「哪一筆」的回答——兩筆同 kind 同 key 的記錄會讓一份「單筆明細」變成兩筆的聯集**（#581：`validate --owner`／MCP `akashic_doctor` 的 `owner` 以 (kind, key) 定位一筆記錄，per-record 問題以 (族名, key) 篩出——同 kind 同 key 兩筆以上時篩出的是它們的聯集，而輸出的標題說「這一筆」。**跨 kind 同 key 不是零實例**：2026-09-28 實測 organization 與 venue 共用 2 個 key（`american-psychological-association`、`american-educational-research-association`），那是 kind 必填的理由、不是本列。**同 kind 的重複只有一部分有既有檢查**：`crossRecordIssues` 報 citekey 與 person key 的重複，venue 與 organization 的重複 key 沒有任何檢查會報（兩筆照常載入）。2026-09-28 實測 live store：person 4,575、work 2,563、venue 485、organization 13、divergence 1 筆，同 kind 重複 key **0**。重跑腳本見表下方） | ✅ **寫（拒絕、不猜——訊息列出各筆的檔名 UUID；CLI exit 1、MCP 回錯誤）** | 第 4 列的理由是「錯誤的偽裝性」——猜錯的結果看起來是對的；這一列同形而位置不同：前面各列守的是 store 的內容，這一列守的是**讀取面對「哪一筆」的回答**。聯集裡的每一則都是真的，錯在標題——而使用者正是為了看「那一筆」才指名的；在全庫輸出裡兩筆同 key 至少還有 citekey／person key 的跨記錄 error 旁證，在單筆明細裡什麼都沒有。**不選「兩筆都列、各自標記」**：`OwnedIssue` 以 (族名, key) 為身分，兩筆同 key 的記錄在那個結構裡本來就分不開，要分得開得讓每一則帶 UUID——那是換 `OwnedIssue` 的形狀、動到三個面，為一個零實例的形狀付出不成比例的代價。**訊息列出各筆的檔名 UUID**，因為重複的 key 本身指不到任何一個檔（`entities/` 以 UUID 命名）。**誠實邊界**：venue 與 organization 的重複 key 沒有跨記錄檢查，所以在這兩個 kind 上本列的拒絕是那個重複**唯一**會出聲的地方，而且只在有人剛好指名那個 key 時出聲；訊息照實說「目前沒有跨記錄檢查報」、不假稱 validate 會列出（#581 首版就這樣假稱過，同輪改掉）。補上那兩個 kind 的跨記錄檢查不在 #581 的範圍，記在 #669（2026-09-28 開立：讀取端還有七處以 `uniqueKeysWithValues` 建查找表，重複 key 會讓 `export-bib` 等直接崩潰）。成本是一個計數比較。**觸發條件可檢查**（腳本見表下方）：同 kind 重複 key 應恆為 0；非零時先修重複（citekey 與 person key 由 `validate` 的跨記錄 error 指路，venue 與 organization 要看檔），再用 owner |
| 39 | **零實例，而它守的是單步的跳躍——一次寫入把一筆讀得回來的記錄推過讀取上限，漸進的預警看不到**（#648，使用者 2026-09-28 裁決兩件都做：(a) 寫出的位元組上限是讀取上限 `AliasEventBudget.maxBytes`（8 MiB），`writePathMultiplier` 的 2 倍只給**不增長**的改寫——寫出的位元組 ≤ 目的檔目前的位元組（`writeByteLimit(replacing:)`）；(b) resolve-people 的 judge／refute 理由上限 4,096 位元組，與未決腿同一個常數（`maxStatementBytes`）。**issue 的前提有一半不成立**（2026-09-28 讀碼並以測試確認）：「寫得進去、讀不回來」在 encode 層不會發生——語意 canary（`decode(out)`）一直以 1 倍擋著，只是拒絕不具名（`fileTooLarge`，訊息說「單一超大節點」），2 倍的外層檢查對位元組從未生效；成立的是另一半：多檔寫入面在那道拒絕觸發之前已有檔落盤（judge 先寫 entry、person 被拒——作者位歸戶而 verdict 沒寫）。2026-09-28 實測 live store：5 族 7,637 筆記錄，最大檔 268,627 bytes（venue `psychological-methods`）、超過 8,388,608 的 **0**；判定記錄最長理由 687 位元組。重跑腳本見表下方） | ✅ **寫（encode 層具名拒絕、零寫入；寬限只給不增長的改寫；多檔寫入面在任何檔落盤之前逐筆 preflight；judge／refute 理由整批拒絕、不截斷）** | 第 31 列的理由是「同一條曲線換了持有者」，它自己寫下的誠實邊界是「warning 只在讀取面、一次夠大的寫入從門檻之下直接跳過讀取上限」——這一列兌現那句邊界的另一半：**漸進的增長由第 16／31 列出聲，單步的跳躍要在寫入端擋**。與第 18 列（入口的字串上限）同形而對象不同：那一列限一個字串，這一列限寫出的整筆記錄，而兩種上限各自都不夠——字串上限擋不住很多個字串（未決腿一次 200 × 4,096 位元組，控制字元經 YAML 跳脫成 4 倍，約 3.3 MB），記錄上限擋不住多檔面的撕裂。所以裁決有三半：寫入閘在 encode（`AliasEventBudget.checkWriteSize`，六個 encoder 共用，拒絕具名記錄與兩個位元組數）、多檔寫入面逐筆 `preflightWrite`（writeX 在寫入當下跑的每一道，含 #631 目的檔與 encode）、judge／refute 的理由在輸入端先擋。**不另立控制字元規則**（使用者 2026-09-28）：4 倍跳脫是 YAML 的合法表示，由 1 倍寫入閘擋下。**寬限只作用於已經讀不回來的檔**：目的檔 ≤ 讀取上限時，不增長的改寫本來就在上限之內；目的檔超過時它在載入時已被 quarantine，entities 佈局的 #631 拒絕覆寫它，寬限只在 legacy 佈局落地——它從不把一個讀得回來的檔變成讀不回來。**誠實邊界**：(1) preflight 以每筆記錄 encode 兩次換零寫入；(2) 有逐筆收容語意的面（resolve-people 的 apply／reject、resolve-venues 的 reject）不 preflight——它們既有的契約是逐筆回報寫入失敗，拒絕現在具名，但仍可能部分落地；(3) 不經 encode 的文字層遷移（`IdentifierMigration` 的形狀升級）不受本閘管；(4) rename 與合併的 preflight dry-encode 不傳目的檔大小，比實際寫入嚴（fail-closed）——對 legacy 佈局裡已讀不回來的檔不給寬限。**C2b verify（2026-09-29）補上三個漏掉的多檔寫入者**：`import-wos`（先前逐列寫、無收容，第 N 列被拒時前 N−1 列已落盤、報告隨 throw 丟掉）、`authorize-names`（只擋了 #641 那一類）、`repair-venue-names`（手寫了前置的子集、少 #631 目的檔檢查）——三者都改成先對整個寫入集合 `preflightWrite`。先前這張表的誠實邊界沒有列它們，是漏看不是裁決。**觸發條件可檢查**（腳本見表下方）：超過讀取上限的檔數應恆為 0；最大檔逼近上限時第 16／31 列的 warning 先響，那時同時查是否有單一呼叫帶進大量內容 |
| 40 | **零實例，而拒絕一直都在——只是問在錯的時間點**（#641：legacy 殘留（`entries/<citekey>.yaml`／`people/<key>.yaml`）加上三者之一——未受 git 追蹤或有未 commit 的修改、目的檔 `entities/<id>.yaml` 被隔離或是另一種記錄、同一個 id 兩份並存——的 work／person，寫入當下一定被 #631 的前置拒絕；那個拒絕發生在多檔寫入者的中途時，前面幾筆已經落盤。#631 R2 verify 以真 binary 重現 judge、refute、org apply、repoint／demote、migrate-identifiers 的撕裂，最後一處讓 ISSN 從 work 移除卻沒寫進 venue、重跑也救不回。2026-09-28 實測 live store：legacy 殘留 `entries/` **0** 個檔、`people/` **0** 個檔——load 不判斷任何記錄。重跑腳本見表下方） | ✅ **寫（load 時以同一組前置判斷標註，併進 `unlocatableCitekeys` 與新增的 `unlocatablePersonKeys`；validate 報 warning）** | 第 21 列的理由是「既有守衛的謂詞對那一類成員結構上不可能為真」；這一列的謂詞沒有問題——#631 的前置判斷對這些記錄答得完全正確，錯在**問的時間**：寫入當下才問，「拒絕」到達時同一個操作的前幾筆已經落盤。所以修法不是換謂詞，是**把同一組判斷（`assertEntitiesDestination`、`legacyMoveCandidate`、`filesNotSafelyRecoverable`）搬到 load 再問一次**，不另寫一份（`no-compat-fallback` §同一件事只能有一份描述）；答案記在記錄旁（`FileSituation`：不參與相等、不序列化），併進「無法唯一定位」的定義，#627／#628 已接好的各面閘因此在第一次寫入之前就拒絕或具名略過——那些面一行不改就拿到第 3 類；person 側的寫入者（judge／refute／apply／reject／undecided、org 以 person 為 holder 的各腿、App 的 accept、authorize-names）另接新的 `unlocatablePersonKeys`。寫入當下的檢查留著當最後一道防線：load 到寫入之間檔案處境可以變（有人在中間 commit 或刪檔），那一段的撕裂本列擋不住。**person 側只收兩類**（key 重複、檔案處境）：作品側的「共用 id」不收——people 表以 key 為主鍵，entities 佈局下共用 id 必然有一筆是 legacy（它已經落在檔案處境那一類），收進來只會多擋住住在 `entities/` 那一筆寫得進去的記錄（`unlocatablePersonKeys` 的 doc 逐條寫著）。**兩筆都還是 legacy、共用同一個 id 時**（C2b verify，Codex HIGH）：目的檔此刻不存在，逐筆的 #631 檢查各自通過，第一筆搬進 `entities/<id>.yaml` 之後第二筆才撞上——load 另外跨記錄比 legacy 那一段的 id，把兩筆都標出來（仍是第 2 類「檔案處境」，不新增類別；作品側本來就有「共用 id」那一類）。**severity 是 warning**：記錄讀得到、內容完好，擋的是寫入；升 error 會讓 `assertNoCrossRecordErrors` 擋下不相干的改名與合併。**成本**：只有 `entries/` 或 `people/` 裡真的有 YAML 時才判斷，git 對整批搬移候選只跑一次——live store 零成本。**誠實邊界**（沒接的寫入者，逐一點名）：`import-zotero` 與 `migrate-provenance` 是逐筆收容（每筆一個檔、寫入當下的拒絕逐筆回報，不撕裂），沒有接；`fmt`／`migrate-person-identity` 直接寫檔、不經 #631；`decodeCaptured` 的唯讀快照不標註（它的契約是不重讀磁碟，也沒有寫入者）。**觸發條件可檢查**（腳本見表下方）：legacy 殘留數應恆為 0；非零時 `akashic validate` 逐筆說哪一筆寫入時會被拒、為什麼，處置是人的——把 legacy 檔 commit（之後寫入會搬移它）、刪掉兩份裡的一份、或修好被隔離的目的檔 |
| 41 | **零實例，而同一個值在兩層有相反的身分——作為位址合法、作為引用不合法**（#654：空內容的 digest，即 0 byte 的 SHA-256 `sha256:e3b0c442…`。#546 在 `store-source` 擋下了 0 byte 的內容，但引用端照收這個 digest——`enrich` 的 `sourceDigest`、`update-person` 的 references、`update-venue --paginated` 與各 undecided 腿的 rests-on、`record-divergence` 的依據、`akashic.sources`——所以一筆指向「空存檔」的 reference 仍寫得進去，只是 blob 不再會被存下來。2026-09-28 實測 live store：記錄 7,637 筆、`sha256:` 值 95 個、指向空內容 digest 的 **0** 個；另有 `sources/index.jsonl` 1 列指向空 blob、那個 blob 在場（#546 之前兩次失敗抓取留下的，沒有記錄引用它）。重跑腳本見表下方） | ✅ **寫（error 級、在 `ProvenanceReference.isValidDigest`；位址層另用只看形狀的 `isWellFormedDigest`）** | 第 32 列的理由是「前件寫寬的方向是放行」；這一列同形而放行的不是假號，是一個真的、形狀完全合法的值——它的錯不在形狀，在於它是常數、對所有空輸入都相同，不指認任何一份存檔，所以只看形狀的檢查全部報綠。**閘放在謂詞本身而不是 `enrich` 入口**（使用者 2026-09-28 裁決）：引用端的寫入面不只一個、再加上載入，逐面補會重演第 25 列「入口有五個」的形；修在共用謂詞一處全部關掉，同第 32 列。**裁決的第二半是把謂詞拆成兩個**：`sources/` 的路徑解析與 `index.jsonl` 的文法、以及 `AuthorListFingerprint` 的持久形只看形狀。live store 的 index 有一列指向空 blob，若 index 文法也排除它，那一列會被判成無法解析，而 index 有無法解析的行時 `store-source` 對**所有**新內容拒寫——一次為了守零實例而加的收緊會把一個能用的 store 關掉（負控實測：index 文法改回 `isValidDigest`，`store-source` 拒寫）。fingerprint 是作者清單的 domain-separated 雜湊、不是內容位址，空內容的 digest 不可能是它的值，那件事由比對時的「不符」說出來。**已入庫的處置是隔離**：digest 在 decode 時本來就驗、不合法整檔隔離，收緊謂詞之後空內容 digest 自然落進同一條路（同第 32 列），零實例所以不需要遷移（`no-compat-fallback`）；訊息說「0 byte」而不是「形狀必須是 …」——對一個形狀合法的值說形狀錯是假話。**誠實邊界**：那個空 blob 與它的 index 列仍在，清掉它需要一個移除存檔的面（#544 同族）；timeline 的舊 `source:` 若裝著它，`migrate-provenance` 略過並說 0 byte、原資料不動。**部署視窗**（#654 R1 verify DA）：收緊的是載入謂詞而沒有自己的 format bump。升級之前的舊 binary（plugin wrapper 下載的 MCP server、App）仍收空內容 digest，而 #546 的失敗抓取正是會產生它的情境；它寫進共用 store 的記錄會被新 binary 整檔隔離。format 21（#642）的 marker 升上去之後舊 binary 整個拒開 store，這個視窗隨之關閉——所以三個 binary 都升完再升 marker。**觸發條件可檢查**（腳本見表下方）：指向空內容 digest 的值應恆為 0；非零時那筆在新 binary 下會被隔離，修法是重新取得內容、`store-source` 存檔後改引用新的 digest |
| 42 | **零實例，而重複 key 在兩個形狀有檢查、在另兩個形狀沒有——沒有檢查的那兩個，讀取時不是少報，是崩潰**（#669：兩筆 venue 或兩筆 organization 持同一個 key。`crossRecordIssues` 只查 citekey 與 person key；以 `Dictionary(uniqueKeysWithValues:)` 建 store key 查找表的地方遇到重複直接 trap——`export-bib`、`apa7Report`、CSL、Projection、attribute-org 的 org 表、migrate-identifiers 的 venue 表，連重複的 person key 在匯出端也一樣；其餘以 `uniquingKeysWith` 建表的地方安靜地留第一筆。同一輪查到同形的第二個來源：MCP／CLI 的 payload 以**消毒後**的字串為鍵，截斷不是單射——`enrich` 的 `provenanceOmitted`（#668 起收 `fields.<鍵>`）遇到兩個共用 80 字元前綴的欄位名，真 binary `Fatal error: Duplicate values for key`、rc=133。2026-09-28 實測 live store：venue 485、organization 13，同 kind 重複 key 0 組。重跑見表下方） | ✅ **寫（error 級、在 `crossRecordIssues`；讀取端不 trap；以 key 定位寫入的兩個面拒絕；源碼掃描守衛）** | 第 33 列的理由是「同一個檢查只寫了三分之一」；這一列同形而後果更重：沒有檢查的那一格讓讀取端**崩潰**——`uniqueKeysWithValues` 對重複鍵是 precondition failure，不是可捕捉的錯誤，一筆手改的 YAML 就讓 `export-bib` 與 MCP server 整個停掉。**severity 是 error**，與 citekey、person key 同級：key 是 `.key(…)` 參照、verdict holder 與每一個寫入面的定位依據，重複時改名與合併（`assertNoCrossRecordErrors`）要先停；第 38 列的定址拒絕原本是這兩個 kind 的重複**唯一**出聲的地方，它的訊息自本列起指路 validate。**讀取端留第一筆**：選哪一筆是列舉順序、不是判定，validate 的 error 說明了它（同 `fields` 的既有處置：消毒後的鍵先依原始鍵排序再留第一個）。**寫入面拒絕**：attribute-org（把 verdict 寫進那個 organization）與 migrate-identifiers（把 ISSN 搬進那個 venue）在重複時整批拒絕、零寫入——同 #627 對 citekey。**其餘寫入面由 #670 補上**：resolve-venues／resolve-organizations 的 verdict 寫入與 update-venue 原本不看跨記錄 error、安靜地留第一筆；現在比照 #627／#641 的無法唯一定位——顯式點名的腿整批拒絕，逐筆略過的腿（apply 的 D33、judge、undecided）具名略過，列表以 `unlocatableVenueKey`／`unlocatableOrganizationKey` 旗標標出（`unlocatableVenueKeys`／`unlocatableOrganizationKeys`）。index 重建對重複的 venue／person key 留第一筆（在此之前 PRIMARY KEY 擲錯，寫入面在檔案落地後才重建，一次不相干的合法寫入會回報失敗）。守衛是 `DuplicateVenueOrgKeyTests.testNoStoreKeyLookupTableTrapsOnDuplicates`：掃 `Sources/`，`uniqueKeysWithValues` 的來源以 `$0.key`／`$0.citekey`／`displaySafe…` 為鍵即紅（由生成器發的 ref 不在前件裡）。**觸發條件可檢查**：重複 key 應恆為 0；非零時先在 YAML 改掉其中一筆的 key——這個 error 在時改名與合併都先停，所以合併不是第一步；若兩筆其實是同一本刊，改完之後再走 record-divergence／resolve-divergence（#669 R1 verify：訊息原本把合併列成並列的出路，而合併正被同一個 error 擋住） |
| 43 | **零實例，而它守的是合併把沿革安靜地拿掉**（#565：venue 合併時，被併者的名字段與倖存者（或先併入的被併者）同名，時間、source、note 不完全相同，又不能並存。先前 `mergedVenueKeeper` 以 `TemporalValue(value:)` 重建被併者的名字，時間、source、note 一律丟掉，同名段被 canonical 濾除而不出聲。2026-09-29 唯讀量測 live store：venue 485、名字段 537，帶時間 0、帶 source 0、帶 note 0；含 venue 候選的 divergence 0。重跑腳本見表下方） | ✅ **寫（不能並存的同名段具名拒絕、零寫入；其餘名字整段搬）** | 第 22 列替沿革在 spec 裡留了位置；這一列守那個位置的**另一端**：合併正是把落進位置的沿革拿掉的那一步，而結果是一筆看起來健康的 venue（第 4 列的偽裝性）。哪一段的時間才對是判斷，合併不猜，所以不能並存的同名段具名拒絕；能並存的整段搬（時間、source、note 都保留），被併者原本在 variant 的才標 variant，其餘併入後未標（#554 D1 的論證用在合併端）。「能不能並存」與 `validate()` 的近重複檢查共用 `Venue.sameNameSegmentsCanCoexist` 一份。**R1 verify（2026-09-29，四席同指）**：分類不取決於被併者順序（倖存者原本沒有的名字，任一被併者列在 variant 就標）；「完全相同的段」比 source／note 的 UTF-8 位元組（`String ==` 會靜默丟掉只差 NFC／NFD 的一份）；名字併入改成以 canonical 鍵建索引的線性計算（首版是二次方，被併者與倖存者各 6,000 個相異名字約 78 秒）；不能並存的清單至多列 20 組並給總數。**出路（#675）**：拒絕的出路原本只有手改 YAML；自 #675 起有編輯面（`update-venue --edit-name-segment`／MCP `edit_name_segment`：改同名段的時間、`source`、`note`，或刪掉一段），拒絕訊息指向它並保留「也可以手改 YAML」——合併仍不替人判定哪一段對，判定由那個面承擔。**觸發條件可檢查**：帶時間、source 或 note 的名字段數 > 0——那時第 22 列的觸發條件也一起到期 |
| 44 | **零實例，而設閘的判準早就寫在程式裡，只是答案剛變**（#567：format < 14 的 store 寫出帶 `variant` 的 venue。`migrate-venue-variants` 退場刪除之後，「有沒有 pre-bump 遷移」的答案從「有」變成「沒有」；`LibraryStore` 的註解本來就寫著「#567 退場時一併裁」。2026-09-29：live store format 18，format-13 的 store 零實例） | ✅ **寫（同 `paginated` 的閘：format < 14 且 variant 非空即拒）** | 與第 1 列同形——不寫的話，format-13 的 binary 會把異寫當一般名字顯示，而沒有任何跡象；差別在於這道閘不是新的判準，是既有判準在遷移退場後的答案。**誠實邊界**：`fmt` 不經 `assertVenueWritable`，不受這道閘管。**觸發條件可檢查**：`VenueStoreTests.testVariantWriteRefusedBelowFormat14` 釘住閘；live store 的 format 見表下方 |
| 45 | **零實例，而上限守的是一個新開的通用寫入面**（#587：`update-venue --references`／MCP `references` 一次 200 筆、statement 4,096 位元組、rests-on 20 個、其餘字串 65,536 位元組；`add_issn` 對認不出的角色與角色衝突拒收。2026-09-29 唯讀量測：venue 485、ISSN 值 59、認不出的角色 0；venue 的 references 只有 resolution-confirmed 2,200 筆與 paginated 36 筆，`field: issn` 0 筆；最長 judgement 287 位元組、rests-on 最多 3 個。重跑腳本見表下方） | ✅ **寫（整批拒絕、零寫入、不截斷）** | 與第 30 列同形——上限只約束單次呼叫，累積由第 16 列的預算 warning 出聲；錨點取既有常數（`maxStatementBytes`、`maxRestsOnPerCall`、`AddOnlyEnrichment.maxValueBytes`），不另立數字。一次 200 筆同第 30 列的 id 數：限的是批次大小，沒有可量的母體，是推估。角色的拒收比遷移嚴：遷移面對既有資料，對認不出的寫法保留原值、報 warning；寫入面不寫一個 `validate` 會報的值。**R1 verify（2026-09-29）**：通用面的 `field` 收窄成 `issn` 與 `names`——venue 的 reference 沒有移除面，`authorized` 的 reference 會鎖住 `authorize` 換對外形（只能手改 YAML 解開），`note` 沒有寫入面；同時關掉兩個耦合：合併把被併者 `field: issn`／`names` 的 reference 逐位元組搬到倖存者，同一個 ISSN 兩邊角色不同（或被併者有而倖存者沒有）具名拒絕 |
| 46 | **零實例，而路由用的字典安靜地選一筆**（#610：同一個 `(library_id, zotero_key)` 被兩筆以上 entry 宣稱，主來源與附加來源都算。三張路由索引都是後寫覆蓋先寫的字典，匯入只更新其中一筆，沒有任何地方說出來。2026-09-29 唯讀量測（R1 verify 重量）：work 2,568、Zotero 來源 535 個（附加來源 3 個），多筆宣稱 0、沒記 `library_id` 的主來源 0。重跑指令見表下方） | ✅ **寫（warning 在 `crossRecordIssues`；匯入端不更新、不新建，報 `ambiguousSourceClaims`）** | 與第 33／42 列同形：隔壁的重複（DOI、標題）有檢查，宣稱者的重複沒有；後果是把 Zotero 的書目欄位寫進別的記錄。宣稱者的定義只有 `ZoteroSourceClaims` 一份，匯入、驗證、App 共用——**含**沒記 `library_id` 的舊檔宣稱同一個裸 key 的 `?:<key>` 桶（R1 verify 之前這一半是假的：匯入端在行內另有一份 `legacies.count == 1`，載入時 doctor 看不到，CLI 提示指向一則不存在的警告）；同一筆 entry 被讀到兩次（#631 兩份並存）以 entry id 去重、只算一次。**severity 是 warning**：升 error 會讓 `assertNoCrossRecordErrors` 擋下改名與合併，而合併正是修復的出路。可達路徑：手改、舊 binary、#607 修掉的 legacy 認領。**觸發條件可檢查**：宣稱者 ≥2 的來源數應恆為 0 |
| 47 | **零實例，而同一個形狀已經真實發生過一次——零來自規則還不存在，不是來自清理**（#642：規則型／文件型 library 的既有成員不符規則、規則指向不在庫的 venue 或文件，以及未標性質的 library。2026-09-24 `akashic-work-references` 把 56 筆被引文獻掛進種子所屬的 library，其中 52 筆不是 Psychological Methods 的作品卻進了它的全量目錄；當時沒有任何守衛，是隔天的 verify 才發現，已在 store `2f18107a` 移除。2026-09-29 讀 live store：library 4 個、全部未標性質，規則型／文件型成員不符 **0**、讀不到的檔 0。重跑腳本見表下方） | ✅ **寫（warning；未標性質是 per-record，不符規則與懸空規則是跨記錄，每個 library 一則、點名前 5 筆）** | 第 13 列的零是「清理過之後的零」；這一列的形狀發生過一次，而今天的零來自 live store 的 4 個 library **都還沒標性質**——規則根本不存在，當然沒有東西不符。一旦有人 `set-kind`，零就取決於兩件事：`library add` 的逐筆比對（寫入端的閘，擋工具面），以及這盞燈。燈照的是閘擋不到的來源：手改 YAML、`set-kind` 當下就已經不符的既有成員（set-kind 只列出、不移除），以及規則建好之後依據才出問題的形狀（venue key 變成重複、文件被刪、排除的 citekey 被刪，#642 R1 verify 補）。**「format 21 之前的舊 binary」不再是獨立來源**（R1 verify 更正——整合時寫成三個來源之一）：寫入閘 `assertLibraryWritable` 擋的是 format < 21 的 store 寫規則型與文件型，舊 binary 沒有這道閘、也不讀 `membership`；但 marker 不到 21 時新 binary 寫不出規則型與文件型，舊 binary 又不認得它們，所以舊 binary 只有在**marker 被手改到 21 之後**才寫得進 ≥21 的 store 的規則型 library——那是「手改」的一種，不是另一個來源。這是第 26 列「閘與守衛是同一條不變式的兩半」的形。**severity 是 warning**：成員關係錯了不毀資料，error 會讓 `assertNoCrossRecordErrors` 擋下不相干的改名與合併。**未標性質也報**：未標就沒有依據，`library add` 一律拒絕；不報的話使用者只會看到 add 被拒，看不到原因住在哪裡。**觸發條件可檢查**（指令見表下方）：不符數應恆為 0；非零時用 `library check <key>` 看是哪幾筆、為什麼，處置是人的——remove，或規則寫錯了就 `set-kind` 改規則 |
| 48 | **零實例，而角色是新開的寫入通道每次查證都會寫的東西**（#587 R1 verify：venue 合併不比同一個 ISSN 的角色——被併者有角色而倖存者沒有、或兩邊不同（含遷移留下認不出的寫法），合併之後角色安靜消失。#587 起 `add_issn` 收角色、`akashic-verify-venue` 查證時會寫；同一輪 `field: issn`／`names` 的 reference 開放寫入，而合併原本對它們一律拒絕。2026-09-29 唯讀量測 live store：venue 485、ISSN 值 59、帶角色 9（print 4／electronic 4／linking 1）、含 venue 候選的 divergence 0、同一個號掛 2+ venue 0、`field: issn`／`names` 的 reference 0（venue 其餘非 verdict reference 只有 paginated 36）、讀不到的檔 0。重跑腳本見表下方） | ✅ **寫（角色遺失具名拒絕、零寫入、出路逐格；`field: issn`／`names` 的 reference 隨合併逐位元組搬）** | 第 4 列的理由是「錯誤的偽裝性」；這一列同形——角色掉了之後記錄仍是一筆看起來健康的 venue，`validate` 不會報——而可達性是 #587 的寫入面造成的（第 23 列的形），所以裁決與新面同批。角色比 `qualifierRaw` 的位元組（認不出的寫法也算，否則遷移留下的 `Online` 會被安靜覆寫）；被併者有而倖存者沒有、或兩邊不同，都具名拒絕，出路各寫（`--add-issn "號 (角色)"`；角色不同時先 `--remove-issn` 再 `--add-issn`，並說明會連帶刪那個號的 reference；認不出的寫法手改 YAML）。reference 那一半不是拒絕而是搬：`field: issn`／`names` 的值在倖存者上存在就逐位元組搬（`byteExactKey` 去重），乾跑與實跑共用 `venueReferenceCarry` 一份；`paginated`、手改的 `authorized`、`note` 仍拒絕——那幾格沒有工具面能搬。**誠實邊界**：搬過去的 reference 在倖存者上沒有移除面（#673）；名字存在與否以 `String ==` 判，倖存者以髒寫法持有同名時，搬過去的 value 位元組可以與名字不同。**觸發條件可檢查**（腳本見表下方）：含 venue 候選的 divergence 數 > 0 時這兩道才會被走到；守衛測試是 `VenueMergeReferencesAndISSNRolesTests` 的角色四支與 reference 四支 |
| 49 | **零實例，而形狀是一次裁決之後才合法、先前哪一面都看不見**（#609：附加來源已刪除而主連結仍在，以及沒有主來源、附加來源全部已刪除——#605 R1 裁決之後兩者都是合法狀態，但 `doctor`、index 的 `orphaned` 欄、App 裁決台都只看主來源。2026-09-29 唯讀量測 live store：work 2,568、Zotero 來源 535（附加 3）、整筆 orphan 0、附加來源已刪除 0、只有附加來源的 entry 0、讀不到的檔 0。重跑腳本見表下方） | ✅ **寫（列表面：`StoreHealth.orphanedCitekeys`／`orphanedAdditionalSourceCitekeys`；判準只有 `Entry.zoteroLinkState` 一份；處置在 App 裁決台）** | 第 46 列的理由是「路由字典安靜地選一筆」；這一列與它成對而守的東西不同：**合法狀態的可見性**。前面各列的零是壞形狀還沒發生，這一列的形狀是合法的，缺的是能看見它的判準——`.orphaned` 的母體在 #605 R1 之後擴大，每個 orphan 介面的判準卻還停在只看主來源，於是一筆作品已經從每一個連結的 library 消失，卻在每個介面都看不見。不寫的代價與第 1 列同形（第一次發生時沒有跡象）；成本是一個三值判準。判準只有一份（health、index、App 共用），各寫一份會分岔。它不是守衛（沒有 severity、不進 `validate`），所以這一列記的是「為什麼列表算數」。**誠實邊界**：index 的 `orphaned` 欄語意改了而沒有 schema bump，目前沒有讀者；「與 Zotero 脫鉤」延伸到新形狀而仍不帶理由與 git 閘，待使用者裁決。**觸發條件可檢查**（腳本見表下方）：兩個計數任一 > 0 即出現在 `akashic doctor`（`orphaned:`／`orphaned additional sources:`）、MCP `akashic_doctor`（`orphaned`／`orphanedAdditionalSources`）與 App 側欄 |
| 50 | **零實例，而檢查只問「在不在」，沒問「是不是一份檔」**（#614 b11c verify R1：`update-entry --add-source`／MCP `add_sources` 要求 digest 的內容已存在本機 `sources/`，而先前用 `fileExists(atPath:)` 判斷——它對同名的**目錄**也回 true；blob 被換成目錄或 symlink、index 那一列還在時，add-source 會宣告一份讀不到的副本而不出聲。2026-09-29 唯讀量測 live store：`sources/` 的 blob 99 個，非普通檔 0、`index.jsonl` 是普通檔。重跑腳本見表下方） | ✅ **寫（`SourcePresence.notRegularFile`，以 lstat 的類型判定；目錄、symlink、特殊檔案具名拒絕，乾跑與實跑一致、零寫入）** | 第 1 列的理由是「失敗的不可見性」；這一列同形——不寫的話，那個形狀第一次出現時 add-source 照常回報成功，而宣告的那份副本打不開。與第 15 列（本機缺承重存檔）相鄰而不同：那一列問的是位元組在不在這台機器上，這一列問的是在那個位置上的東西是不是一份檔。前件精確（lstat 的類型不是 regular），成本是一個屬性檢查。**symlink 也拒**：`sources/` 由 `store-source` 寫成普通檔，store 沒有任何一條路徑會寫出 symlink；若日後有意用 symlink 共用 blob，要回來改這一列。**誠實邊界**：只看類型、不重新雜湊內容（位元組與 digest 是否相符不在這道檢查裡）。**觸發條件可檢查**（腳本見表下方）：非普通檔數應恆為 0；非零時先查是誰放的，再依 add-source 的拒絕訊息處置 |
| 51 | **零實例，而「沒有東西可檢查」與「檢查過且乾淨」在輸出上分不開**（#629 移植 `rule-coverage` 成 `akashic-guards rule-coverage`：某個 plugin 根的 `rules/` 底下一條 `.md` 都沒有時，舊 shell 版因 glob 不命中而**意外**變紅，Swift 版的空迴圈會印綠燈。2026-09-29 量測：兩個 plugin 根（`plugin`、`plugins/akashic-discovery`）各 2 條規則，空的 `rules/` 0 個） | ✅ **寫（`RuleCoverage.swift` 對零條規則顯式 rc=1 並具名）** | 第 3 列的理由是「未涵蓋不得冒充通過」；這一列同形，差別在它是**移植時才可能長出來的沉默**：舊實作的紅是 glob 的副作用，不是裁決，換一個語言就換掉了。所以移植要把那個副作用寫成顯式的判定。成本一個分支。**負控**：`audit-guards-mutations` 的 `coverage④` 刪光 `plugin/rules/*.md`、期望「沒有任何 .md 規則檔」（#629 R1 加入；R2 verify 第 5 則指出本列先前仍寫「還沒有」）。**觸發條件可檢查**：`ls <plugin 根>/rules/*.md | wc -l` 應恆 ≥ 1；等於 0 時守衛紅，處置是補規則檔或把那個根移出 `plugin-roots` |
| 52 | **零實例，而少算一個檔的普查與「查完歸零」無法區分**（#629 移植 `literal-census.sh` 成 `akashic literal-census`：記錄檔讀不進來或不是一般檔時，Python 版 traceback、shell 版少算，Swift 版具名 exit 3 拒絕輸出計數（`LiteralCensus.Failure.unreadableRecord`）。2026-09-29 唯讀量測 live store：`entities/`／`entries/`／`people/` 的 `.yaml` 7,643 個，不可讀或非一般檔 0。重跑腳本見表下方） | ✅ **寫（exit 3、具名那個檔，不輸出任何計數）** | 第 3 列的理由是「守衛沉默時要不要說話」；這一列同形而後果更具體：普查的輸出是 `literal-first-then-key` 終局的**進度量測**（literal 邊數的趨勢），少算一個檔會讓數字往「歸零」那一側偏，而那正是量測要回答的問題。所以不是略過並警告，是整次拒絕輸出。釘住它的測試是 `LiteralCensusTests.testUnreadableRecordRefusesToCountRatherThanUndercount`。**#629 R1 補記（同一條理由，兩處同形）**：`entities/`、`entries/`、`people/` 任一個存在但**列不出來**也是具名 exit 3（`unlistableDirectory`，第一版把列目錄的錯誤轉成空清單，於是不可列的 `entities/` 印出全零的四域報告）；`akashic scan-yaml-profile` 的根不是資料夾、讀不到的檔或子資料夾、零個 `.yaml` 同樣具名失敗（先前印全零並 exit 0）。**觸發條件可檢查**（腳本見表下方）：不可讀或非一般檔數應恆為 0；非零時先修那個檔的權限或類型，再跑普查 |
| 53 | **零實例，而同一個不明確的依據設定時被拒、使用時被放行**（#642 b11d verify R1：規則型 library 的 venue key 之後變成重複、或排除清單的 citekey 打錯或已不在庫——`create`／`set-kind` 本來就拒絕重複的 venue key，`library add` 卻只比 key 字串；排除清單則從不查存在，打錯一個字排除就無聲失效。2026-09-29 唯讀量測 live store：library 4、規則型 0、排除清單指向不在庫 0、規則的 venue key 重複 0。重跑腳本見表下方） | ✅ **寫（寫入閘與 warning 同批：`LibraryMembershipCheck` 的 `ruleVenueAmbiguous`，三面都不寫、`library check` 揭露；`create`／`set-kind` 對不在庫的排除 citekey 具名拒絕；validate 報兩種 warning）** | 第 47 列的理由是「零來自規則還不存在」，燈照的是寫入閘擋不到的來源；這一列補兩個它沒照到的：依據本身出了問題（venue key 重複）與排除清單懸空。前者是第 26 列「閘與守衛是同一條不變式的兩半」的形——同一個依據在設定時被閘擋下、在使用時卻被放行，等於那條不變式只有一半；後者讓同一份程式對「排除清單是不是參照」給出相反的答案（改名與合併的守衛把它當參照，建立時卻不查）。**severity 是 warning**：成員關係錯了不毀資料，與第 47 列同級。**誠實邊界**：規則依據不明確時，連被排除的成員也回「依據不明確」而不是「排除」（Claude 代裁，依據問題優先）。**觸發條件可檢查**（腳本見表下方）：兩個數應恆為 0；非零時用 `library check <key>` 看是哪一條規則、哪個 citekey |
| 54 | **零實例，而先前的守衛是一條走不通的出路**（#642 b11d verify R1：改名碰到被 library 規則指涉的 citekey——文件型的 `document`、規則型的 `excluded`。#642 首版一律拒絕並指路「先 set-kind 改規則」，而文件型的 `set-kind` 要求新 citekey 已在庫、`rename` 要求它不在庫，出路是死路。2026-09-29 唯讀量測 live store：規則型與文件型 library 都是 0，被規則指涉的 citekey 0） | ✅ **寫（`renameEntry` 同批遷移規則裡的 citekey，registry 檔進同一批預檢與寫入，逐條列在 `RenameReport.libraryRulesRewritten`；三個前置拒絕、零寫入：新 citekey 已被規則指涉、被隔離的 registry 檔提到舊或新 citekey、要遷移的 registry 檔不可回溯）** | 改名不改身分，而 library 規則是關係邊第 16 條——改名本來就該遷移指向舊 key 的邊（第 13 條邊的 verdict value 是先例）。三個前置拒絕各擋一種遷移會造成的安靜錯誤：新 citekey 已被規則指涉時，改名會讓一條懸空的規則「復活」成指向另一筆；被隔離的 registry 檔看不到，遷移會漏掉它；registry 檔不可回溯時，被改寫的規則沒有舊值可取回。work 與 venue 合併維持拒絕，訊息改成可照做的 `set-kind` 命令、不經過 topic。**觸發條件可檢查**：規則型或文件型 library 出現之後，改名一筆被指涉的 citekey 時報告會多一段「library 成員規則已遷移」；守衛測試是 `LibraryMembershipStoreTests` 的改名六支 |
| 55 | **零實例，而整值替換會丟掉人的裁決，舊值只剩 git 那一份**（#642 b11d verify R1：`set-kind` 替換一個既有的成員性質時，排除清單這類逐筆寫下的裁決整份被換掉，先前不回顯舊值、也不要求舊值取得回來。2026-09-29 唯讀量測 live store：4 個 library 全未標性質，從未標標成任何一種不經這道閘，所以零實例） | ✅ **寫（替換既有性質時要求 `libraries/<key>.yaml` 已 commit 且乾淨；兩面回顯先前的性質；可回溯閘抽成共用核心 `LibraryStore.recoverabilityRefusal`，與 #573 那一族同一支）** | 第 44 列的理由是「既有判準的答案變了」；這一列同形而對象不同：#573 那一族的閘原本只看 `entities/` 的記錄檔，registry 檔在 `libraries/`，於是移除面一族的判準（舊值要能從 git 取回，使用者 2026-09-27 裁決）在這裡沒有套上。修法是把閘抽成共用核心、多收一種檔，不是複製一份邏輯。**Claude 代裁**：閘也涵蓋把 topic 換成別的性質（topic 沒有參數可失去，比必要的嚴）。**沒做的**：把規則放寬（降成 topic、清掉排除清單、換 venue）時要不要另外要求明確確認——待使用者決定；目前的防線只有回顯與 git。**觸發條件可檢查**：有 library 標了性質之後，替換它而 registry 檔未 commit 時 `set-kind` 拒絕；測試是 `LibraryMembershipServiceTests.testReplacingAnExistingMembershipRequiresACommittedRegistryFile`（回顯由 `testSetKindEchoesThePreviousMembership` 釘住） |
| 56 | **零實例，而 decode 接受它、唯一守著它的合併閘只擋一條進入路徑**（#679：附加 Zotero 來源沒記 `library_id`——匯入端與 `ZoteroSourceClaims.claims(of:)` 都對不回它，沒有別的 entry 宣稱那個條目時再匯入會另建一筆 twin；先前註解宣稱「由合併閘保證不會出現」，而合併閘只擋合併新收，管不到手改與舊檔。2026-09-29 唯讀量測 live store：work 2,569、主來源 532（沒記 `library_id` 0）、附加來源 3（沒記 `library_id` 0）、被 ≥2 筆宣稱的來源 0、讀不到的檔 0。重跑腳本見表下方） | ✅ **寫（warning、在 `Entry.validate()`，每筆 entry 一則、至多列 5 個來源鍵；訊息說出後果與兩條出路：補真正的 `library_id`，或以 `update-entry --remove-zotero-source` 移除）** | 第 4 列的理由是「錯誤的偽裝性」；這一列同形——那筆記錄看起來連著 Zotero，而下一次匯入會安靜地另建一筆，結果是一對看起來各自健康的攣生。與第 33 列也同形：同一族的檢查（#610 的多筆宣稱）只照到有 `library_id` 的那一半。**severity 是 warning**：記錄合法可載入；decode 拒收會讓既有的檔整個被隔離（`writeEntry` 不對 `Entry.validate()` 的 error 設閘，所以升 error 也擋不住寫入，那不是理由）。警告說的後果由 `AdditionalSourceWithoutLibraryReimportTests` 釘住，警告與行為不會分岔。**誠實邊界**（b13f R1 verify）：這則 warning 走一般的 per-record 通道，MCP `akashic_doctor` 的 `recordIssues` 是 errors 優先且截 20 則，沒有像 `duplicateVenueEdges` 那樣的 `StoreHealth` 家族計數，所以「觸發條件可檢查」實際只有 CLI `validate` 的 grep 可用；live 零實例、且是線性家族（一筆 entry 一則），接受。訊息說的 twin 是有條件的（單筆 `validate` 看不到別的 entry）。**觸發條件可檢查**（腳本見表下方）：`grep -a -q '附加 Zotero 來源沒記 library_id' "$(command -v akashic)" && akashic validate 2>&1 | grep -c '附加 Zotero 來源沒記 library_id'` 應恆為 0；非零時照訊息給的定位鍵處置 |
| 57 | **零實例，而錯的回應看起來是對的**（#629 第二塊：`akashic crossref-match` 以重播協定讀 skill 經 safari-browser 取回的 Crossref 回應，回應的 DOI 與請求的 DOI 不同時拒絕；DOI 插進網址前先驗形狀（`^10\.[0-9]{4,9}/` 後接不含空白、引號、反斜線、`$`、反引號、`#`、`?`、`%` 的字元，且沒有 `.`／`..` 路徑段）。指令從未對真回應跑過。2026-09-29 唯讀量測 live store：work 的 DOI 2,449 個，形狀檢查不過 0、讀不到的檔 0。重跑腳本見表下方） | ✅ **寫（身分不符具名拒絕、形狀不過的 DOI 不組成請求）** | 第 4 列的理由是「錯誤的偽裝性」；這一列同形：把另一個 DOI 的回應讀成這一個，比對照樣成功、結束碼 0，而結果是一筆看起來查證過的錯資料。這個形狀在頁內 fetch 已經發生過一次（PsychQuant/safari-browser#190：一批讀到上一批的結果、結束碼全為 0），所以讀回後核對身分是 `web-access-via-safari-browser` 的既有紀律，這裡把它落實成程式。形狀檢查與 `web-access.md` 的形狀表同一條。**#629 R1 補記**：查詢回應 200 而形狀不對（`message` 不是物件、`items` 不是陣列、任一缺席）同樣具名中止，不當成「沒有候選」——「查無此筆」與「回應壞了」在輸出裡不可區分正是這一列的形狀（`CrossrefMatchResponseShapeTests`）。**觸發條件可檢查**：形狀不過的 DOI 數應恆為 0；身分檢查由 `CrossrefMatchTests.testReverseVerifyRejectsAResponseAboutAnotherDOI` 與 `testAnUnsafeCandidateDOIIsNeverTurnedIntoARequest` 釘住 |
| 58 | **零實例，而半套的數字讀起來像完整的**（#629 第二塊：`akashic fulltext calibrate` 讀本機的 Crossref 回應目錄計分；缺任何一筆記錄時列出缺的網址並以結束碼 3 結束、不出數字，`--partial` 才照已有的量。校準從未在本機跑過——2026-09-24 那批語料本機找不到，重取要連網） | ✅ **寫（缺記錄預設不出數字）** | 第 3 列的理由是「未涵蓋不得冒充通過」；這一列同形：`22/28`、`0/808` 這類數字若只涵蓋有記錄的那一部分，讀的人會當成全部。拒絕輸出是預設，放行要顯式帶 `--partial`，而那時輸出本身就說明它是部分的。**誠實邊界**：移植時舊校準數字（自己 22/28、別篇 0/808）沒有重跑，替代證據是新舊判定規則的差分——它證明新舊判得一樣，不證明那組數字在新語料上仍成立。**「十七萬餘案 0 不一致」這個說法過寬（R1 verify 第 17 則）**：驗證席找到五處可重現的分岔（補充資料標題跨行、Foundation 的 NFKC、`İ`／`ı`、ICU 的 `\b`、`JSONSerialization` 的重複鍵與字串內 U+FEFF），R1 全部修掉；語料是本機 PDF 與隨機字串，不涵蓋全部 Unicode。**#629 R1 補記**：一個檔案都沒量到回結束碼 4（先前 0，全零的 `0/0` 讀起來像「沒有別篇被收」）、資料夾不存在具名失敗、形狀不合格的 DOI 不組網址，缺記錄的清單帶完整網址；新舊工具在本機能湊到的語料（10 份有標籤、41 份引擎一致）上輸出逐字相同，見 `changelog/2026-09-29-b13p-verify-r1.md`。**觸發條件可檢查**：`SkillToolsCLITests.testCalibrateListsMissingCrossrefRecordsAndMeasuresTheRest` 釘住結束碼 3 與缺記錄清單 |
| 59 | **零實例，而「移哪一筆」對兩筆完全相同的記錄沒有判定內容可依**（#673：`update-venue --remove-reference` 以 field＋value＋位元組鍵定位；兩筆 reference 的 `byteExactKey` 完全相同時具名拒絕、不挑一筆移。2026-09-29 唯讀量測 live store：venue 485、帶通用 reference 的 venue 0、位元組相同的重複組 0。重跑腳本見表下方） | ❌ **不寫（不給完全相同的重複一條移除路徑）** | 與第 10 列同形：形狀取決於一個還沒出現的用途——要嘛加 ordinal 指定第幾筆，要嘛一條「重複全收成一筆」的腿，兩者的語意不同，而今天沒有實例可以告訴我們哪一種才是使用者要的。先具名拒絕是可逆的；選錯一個形狀則是固定了一個介面。這種重複本來就由 `StoreHealth.duplicateReferences`（第 35 列）報出。**屬前言四類的第 1 類（守衛）**（b13f R1 verify 第 28 列）：本列裁的對象是那道具名拒絕——「無法判定移哪一筆」時 `--remove-reference` 拒絕、不挑——要不要**放行成一條移除路徑**；不寫的是放行，不是那道守衛；不是新的一類（前言明寫沒有「零實例的移除腿」這一類）。**觸發條件可檢查**（腳本見表下方）：位元組相同的重複組 > 0，或 `akashic validate` 對 venue 報「重複的 reference：」——那時重開，由使用者選形狀 |
| 60 | **零實例，而上限沒有量測依據、也不是位元組界線**（#673：venue 讀取面（CLI `venue`、MCP `akashic_venue`）顯示非判定的 references，至多 `venueReferencesCap`＝25 筆、每筆 `rests_on` 至多 5 個，以 `referencesTotal`／`referencesTruncated`／`rests_on_total` 揭露。2026-09-29 唯讀量測 live store：帶通用 reference 的 venue 0，單筆 venue 最多 0 筆） | ✅ **寫（第 1 類，守衛：上限 25 筆、`rests_on` 前 5 個，截斷一律揭露）** | 第 18 列的理由是「零量的是出口而守衛裝在入口」；這一列同形，差別在錨點：第 18 列夾在兩個量測之間，這一列**一個量測都沒有**——25 是**選的數字**（live store 沒有任何一筆通用 reference 可量），量級考量是一本刊的 ISSN 與名字各有幾筆來源記錄、再留一個數量級的餘裕。首版把它寫成「單筆各字串上限之和約 1.4 KB、25 筆約 35 KB、落在 MCP 單一輸出 48 KiB 之內」，b13f R1 verify 抓到三處錯：(1) 1.4 KB 把各字串的**字元**上限相加、當成位元組——CJK 一個字元 3 位元組；`displaySafe` 在逃脫模式數輸入 scalar，一個控制字元逃成 `\u{XXXX}`（8 字元），JSON 序列化再把反斜線加倍，最壞單筆約 6 KB（retrieval：value 200＋url 300＋retrieved 與 media_type 各 60 個 scalar 全是控制字元）、25 筆約 150 KB（推估）；(2) 48 KiB 是 `tools/list` 與 `candidateByteBudget`（resolve 候選、doctor 的 per-record 清單）的預算，**`akashic_venue` 沒有單一輸出的位元組預算**；(3) 同一個 payload 的 `works` 編年清單本來就無界（live：`psychological-methods` 1,352 筆、每筆標題至多 500 字元），所以這個上限保護不了輸出大小。**它實際做的事**：不讓 `references` 這一段跟著一本異常刊無限長（筆數上界）；單筆的字串各有字元上限。不設上限的代價是讀取面對未信任的 store 內容線性長大（第 16 列那一族）。**誠實邊界**：要限位元組得另設預算（`candidateByteBudget` 的形），此刻沒有實例；讀取面對 value 截在 200、url／statement 截在 300，逐字定位要對照 YAML。**觸發條件可檢查**：任一 venue 的輸出帶 `referencesTruncated: true`——那時才有實際分布可量，重量上限（並一併決定要不要設位元組預算） |
| 61 | **零實例，而上限守的是「理由只在報告裡」的那份輸出**（#680、#677、#673 的 b13f verify R1：移除面一族的報告輸出有上限——`update-entry --remove-zotero-source` 的 `zoteroSourcesRemaining` 兩面都截 20（`zoteroSourcesRemainingCap`，附總數）；`remove_sources` 的取得記錄（`sourcesAddedCap`）與 `remove_reference` 的 reference 內容（`removalDetailCap`）只在 MCP 面截 20，其後仍逐筆列定位鍵與理由，以 `detailsTruncated`／`detailsListed` 揭露。2026-09-29 唯讀量測 live store：work 2,572、有附加 Zotero 來源的 work 3（單筆最多 1）、單筆 work 最多 `akashic.sources` 0、venue 485、通用 reference 0、讀不到的檔 0。重跑腳本見表下方） | ✅ **寫（輸出上限，截斷一律揭露；理由逐筆不截）** | 第 60 列的理由是「上限只有算術可依」；這一列同形（20 是選的數字、限筆數不限位元組），差別在這一族每筆都帶理由，而理由依 2026-09-27 的裁決只在報告裡有一份——所以不截整筆、只截第三方的內容，與 `add_sources` 截整筆的先例刻意不同：截掉第 21 筆以後的理由就無處可記。**誠實邊界**：省略的內容只在 git 的移除前副本與 CLI 輸出裡；上限不保證輸出位元組。**觸發條件可檢查**（腳本見表下方）：出現 `detailsTruncated: true`，或 `zoteroSourcesRemainingTotal` > 20 時重量 |
| 62 | **零實例，而失敗是刪掉使用者已有的資料、而且發生在「下載成功」之後**（#629 R1 verify：`akashic fulltext fetch` 的輸出步驟對已存在的目的地「先刪再搬」——`--out` 是非空目錄時遞迴刪光，是普通檔時搬失敗前原檔已毀。2026-09-29 唯讀量測：`~/Downloads` 兩層內名為 `*.pdf` 的目錄或 symlink **0**。重跑指令見表下方） | ✅ **寫（三個目的地先 lstat、同目錄暫存檔＋rename）** | 第 1 列的理由是不寫就沒有跡象；這一列多一層：**跡象指向錯的方向**——命令回報下載成功，被刪的是使用者原本就有的東西。成本是一次 lstat。釘住 `FulltextFetchHardeningTests.testANonEmptyDirectoryAtOutIsRefusedAndKept` 與 `testAWriteFailureAfterTheTempFileWasCreatedKeepsTheOriginalFile`（後者以 `RLIMIT_FSIZE` 讓寫入在暫存檔建立後失敗） |
| 63 | **零實例，而「git 答不出來」與「不在 repo 裡」在輸出上分不開，閘又是隱私閘**（#629 R1 verify：fetch 的 git 閘寫成「git 回 0 才算在 repo 裡」，git 起不來、rev-parse 非零、dubious ownership 全被讀成「不在工作樹」而放行——PDF 可能寫進一個會推上 remote 的 repo。2026-09-29 唯讀量測：`$TMPDIR`、`~`、`~/Downloads`、`/tmp` 逐層往上都沒有 `.git`） | ✅ **寫（祖先沒有 `.git` 由檔案系統事實判；有才問 git，答不出來一律拒絕）** | 第 3 列同形——沒被檢查冒充成檢查過且乾淨——而後果更重：外流進 remote 不可逆（git 隱私邊界）。git 呼叫改走 `LibraryStore.hardenedGit`（#585 那一份），不另寫第三份。釘住 `FulltextFetchHardeningTests` 的 git 一族七個測試 |
| 64 | **零實例，而兩個 JSON 解析器對同一份輸入安靜地給出不同答案**（#629 R1 verify：`JSONSerialization` 對重複鍵取第一個、吃掉字串開頭的 U+FEFF、接受尾隨逗號、拒 NaN，Python `json.loads` 四處都相反；從 Python 移植過來的 `abstracts-to-proposals`、`crossref-match` 因此可能對同一份檔讀出不同的欄位值。2026-09-29 唯讀量測（表下方腳本）：`~/.akashic/sources/` 裡整份可解析的 JSON 文件 88 份，重複鍵 0、尾隨逗號 0、字串值開頭是 U+FEFF 的 0；#629 R1 以另一個量法報 1,800 個文件，母體不同，兩數都不為 0 的只有文件數） | ✅ **寫（`PyJSONParser`，照 `json.loads` 的文法）** | 第 4 列的偽裝性：解析成功、欄位有值，只是那個值不是來源的意思；`lossless-intake` 的「來源給什麼收什麼」在解析這一層就可能失真。釘住 `PyJSONParserTests`（38 個 Python 案例）與 `AbstractProposalsPythonJSONTests`。**誠實邊界**：仍有三處與 Python 不同（深度上限 512、孤立代理對拒絕、超出 `Int` 的整數退成 `Double`），寫在型別 doc |
| 65 | **零實例，而同一個推導有四份、各自讀起來都通順**（#663：CLI、MCP、App 三個讀取面與匯出端各自推導「這個人的隸屬現況」，只被觀測到的段在三個面說成「曾隸屬」、匯出端說 `undetermined`，要拿兩者對照才看得出。2026-09-29 唯讀量測 live store：person 4,575，無隸屬 4,413、現職 116、只有已結束 46、只被觀測到 0、混合 0；Core 以外直接用 `latestPastSegment` 的檔 0） | ✅ **寫（源碼掃描守衛）** | 第 13 列同形（清理過之後的零）：四份併成 `TimelineOf.standing` 一份之後，第五個讀取面若又自己寫 `current ?? latestPastSegment`，不會有任何跡象。`entity-backlink-completeness` 執行細節 2 的「一個讀取面只能有一條實作路徑」在這裡由源碼掃描兌現。守衛 `TimelineStandingTests.testNoReadSurfaceCallsLatestPastSegmentDirectly`，負控 `testTheScanRecognisesAViolationAndAllowsTheCoreFiles` |
| 66 | **零實例，而帳密一旦寫進 git 追蹤的 YAML 就收不回來**（#674：person 與 venue 的 references 寫入面對 retrieval 的 `url` 只收 http／https 且不含帳密、`retrieved` 是 ISO 8601、`status` 在 100–599。2026-09-29 唯讀量測：person、venue、organization 的 retrieval reference 0 筆（references 8,693 筆全是 judgement）；work 的 33 筆全是 https、無帳密、`YYYY-MM-DD`、status 200。重跑腳本見表下方） | ✅ **寫（入口拒絕，整批零寫入）** | 第 18 列同形：零量的是出口，守衛裝在入口。多一層：url 裡的帳密是秘密（`lossless-intake` 不收的第 1 類），寫進去之後 git 歷史裡永遠在。**誠實邊界**：只擋 userinfo，query 或路徑裡的 token 擋不到；~~`enrich` 的來源欄位沒有跟著收緊，是另一份契約——而 live store 僅有的 33 筆 retrieval url 正是經它寫入的，追蹤於 #695~~ → **#695（2026-09-30）起不成立**：守衛搬到 Core 的 `RetrievalWriteShape`，`enrich` 的 `sourceURL`／`sourceRetrieved`／`sourceStatus` 呼叫同一個函式（整批拒絕）；那 33 筆全數通過（2026-09-30 重量） |
| 67 | **零實例，而欄位的語意改了、卻沒有任何讀者**（#684：index 的 `entries.orphaned` 在 #609 改由 `Entry.zoteroLinkState == .orphaned` 判定，`schemaVersion` 仍是 5。2026-09-29 量測：`Sources/` 讀這一欄的地方 0 處、建表恰 1 處） | ❌ **暫不做（不 bump）** | 第 10 列同形——要不要做取決於一個還不存在的東西，這裡是讀者。index 是衍生物，store 一寫就因 mtime 過期重建，舊 binary 建的 index 到那時自癒；沒有讀者就沒有東西受漂移影響，bump 只會讓每個使用者白重建一次。**觸發條件**：出現第一個讀者時，`schemaVersion` 與 `PRAGMA user_version = 5` 兩處同步升 6（後者是寫死的重複） |
| 68 | **零實例，而清單會由一次匯入一步跨過**（#684：MCP `akashic_import_zotero` 的 `ambiguousSourceClaims` 至多 20 個來源、每個來源 20 個宣稱者，揭露 `ambiguousSourceClaimsTotal`／`ambiguousSourceClaimsTruncated`；CLI 全列。2026-09-29 唯讀量測：work 2,572、Zotero 來源 535、被 ≥2 筆宣稱 0、最大宣稱者數 1。重跑腳本見表下方） | ✅ **寫** | 與第 18、30 列同形：沒有曲線，實例會由一次匯入一步跨過；上限保護的是 LLM context，不是 store。**觸發條件**：任一次匯入回 `ambiguousSourceClaimsTruncated: true` 就重開 |
| 69 | **零實例，而它是沿革位置的第一個寫入面**（#675：`update-venue --edit-name-segment`／MCP `edit_name_segment` 改名字段的時間欄位、`source`、`note` 或刪段。上限沿用既有常數——一次 200 項、理由 4,096 位元組、`source`／`note` 65,536 位元組；`attested` 200 點是推估、沒有母體（R1 起每個點也有 65,536 位元組上限）；ISO 8601 前綴與區間有效性只在這個入口驗。2026-09-29 唯讀量測 live store：venue 485、名字段 537，帶時間 0、帶 source 0、帶 note 0。重跑腳本見表下方） | ✅ **寫（整批拒絕、零寫入、不截斷；時間欄位入口驗）** | 與第 45 列同形：上限只擋單次，累積由第 16／31 列出聲。差別在對象：第 22 列替沿革保留位置、第 43 列守合併時不把它拿掉，而在此之前**沒有任何面寫得進去**——這是第一個。ISO 只在入口驗、不升成 `validate()` 的 error：載入端對 venue 日期不驗是既有裁決（#85），升級會讓手改的值從「載入得了」變成「所有寫入被拒」。**誠實邊界**：手改的非 ISO 值仍載入得了，沿革豁免不認它。**觸發條件**：帶時間、source 或 note 的名字段數 > 0——那時第 22、43 列同時到期 |
| 70 | **零實例，而它是清單清空之後留著的機制**（#690：`trigger-coverage` 的「宣告範圍裡不在受保護集合的檔」檢查，與它的已知缺口清單 `.githooks/acknowledged-ci-gaps.txt`。立案時兩條缺口——`network-confinement` 與 `zero-instance-rows-audit` 宣告讀 `Sources/*/*.swift`，115 個不受保護的檔改動時 CI 不跑它們；使用者 2026-09-30 裁決 A 讓 `census-parity.yml` 的 `paths` 涵蓋 `Sources/**`，兩條隨之消失、清單清空。2026-09-30 量測：宣告範圍的缺口 **0**、清單條目 **0**。重跑指令見表下方） | ✅ **寫檢查、保留清單（清單是資料檔，三條分支各有負控）** | 第 13 列的零是「清理過之後的零」；這一列同形，多一件事：**清空它的是一次計費裁決**。`paths` 若因成本再收窄，同一個缺口立刻回來，那時要的是「列管並追蹤」，而不是只有紅燈或什麼都沒有。留著的代價是一條可能變成豁免的路，所以三道閘：每一條必附 `#<issue>`、缺口消失而條目還在是缺口（過期）、格式不對是缺口。R1 verify（requirements、logic、regression 三席）指出清單是編譯期常數時這三條分支沒有任何負控走得到——harness 改的是 copy 裡的檔、改不到 binary；清單因此搬進資料檔，`trigger-coverage-mutations` 三格各走一條，另兩格各釘宣告範圍檢查的兩個判斷（workflow 有跑這支守衛、`paths-ignore`，DA 席實測兩者改壞時負控全綠）。R2 verify 指出那三格只走到欄數：`#<issue>` 的格式與「樣式要相等」兩個條件拿掉時負控仍 44/44，`TODO` 當第三欄的一行會把缺口放過；補五格（第三欄不是 `#<issue>`、第一或第二欄空、樣式與宣告不同、CRLF 行尾、同一條列兩次），並把兩格 workflow 注入改成 Actions 收的設定（同一個事件不能同時有 `paths` 與 `paths-ignore`）。`#<issue>` 只驗格式，不驗 issue 存在或仍開著——那一半靠下面的觸發條件。**觸發條件可檢查**（指令見表下方）：清單有條目時，逐條確認它的 issue 還開著；issue 關了而條目還在，把條目拿掉——缺口若也還在，守衛照常紅 |
| 71 | **零實例，而它守的是另一支守衛的輸入讀不讀得懂**（#689：`migrated-guard-control` 的兩個出口——一支 harness 以命名慣例或 `// negative-control-for:` 宣告了某支守衛、source 裡卻沒有執行它的寫法（「宣告是空的」）；`run-guards.sh` 裡一處 `.build/debug/akashic-guards` 不落在任何被抽取認得的呼叫裡（「抽取認不出」）。兩個出口是 R1 verify 加的；R2 verify（Codex、logic、security、DA 四席）指出第二個與抽取共用同一條只認一個空格的 regex，雙空格、TAB、變數、引號的呼叫兩邊都看不到，改成獨立找 binary 路徑的每一處出現。2026-09-30 量測：兩個出口的訊息各 **0** 條。重跑指令見表下方） | ✅ **寫（兩個出口都計入 rc，各有負控）** | 第 21 列的理由是「既有守衛的謂詞對那一類成員結構上不可能為真」，換一個謂詞就好；這一列的兩個出口補的是**另一支守衛（負控的抽取）自己的輸入**，而補丁有一個第 21 列沒有的失效方式：**它的失敗條件若與它要補的那個抽取相同，抽取漏掉的寫法它也漏掉**，零實例量到的就只是「看不到」而不是「沒有」。R1 的「抽取認不出」就是這樣——它拿抽取那條 regex 去找漏網的呼叫。「宣告是空的」不出聲的代價是一句宣告讓人以為那支守衛有負控；「抽取認不出」不出聲的代價是那支守衛整個不在名單裡、不被要求負控——兩者都是看起來綠、其實沒量到。方向是誤報（看得見），所以不逐一擴充語法；例外只有兩個具名的形狀（`[ ! -x … ]` 存在檢查、整行只有一個 `echo "…"`），各有一格負控證明它們沒有放寬。**誠實邊界**：受測對象是 source 文字裡的執行寫法，不是 harness 執行時實際跑的守衛——死函式裡的直接執行字面與改成 `exit(0)` 的分派仍然通過（`MigratedGuardControl.swift` 檔頭列著四個形狀的現況），執行期的證據另開 issue。**觸發條件可檢查**（指令見表下方）：兩個數應恆為 0；非零時先看是不是 runner 或 harness 換了寫法——改成獨立一行、或讓宣告的守衛真的被執行，不要放寬偵測 |
| 72 | **零實例，而上限是一次裁決給的數字，守的是一步就跨得過的入口**（#703：`sources/` 單份內容的上限 `LibraryStore.maxSourceBytes`＝268,435,456 bytes（256 MiB；裁決原話「256 MB」），`store-source`（CLI／MCP `akashic_store_source`）、`SourceStore.storeSource`、`ZoteroStorageFile` 的定位與開檔、`copy-zotero-attachments`（含乾跑）都讀這一個常數。同批兩件：SHA-256 與複製改成逐塊（每塊讀完即釋放——R1 verify 之前這裡寫「記憶體與檔案大小無關」，當時不成立，見理由欄），`copy-zotero-attachments` 對已在 `sources/` 的同一個 digest 逐塊比對內容。2026-09-30 唯讀量測：Zotero storage 2,817 個檔、合計 61,047,841 bytes（`du -sh` 66 MB）、最大 5,499,190 bytes；`sources/` 104 個檔（含 `index.jsonl`）、最大 3,912,063 bytes——超過上限 **0**。重跑腳本見表下方） | ✅ **寫（超過的不截斷、不存、具名大小；單檔入口整個拒絕，批次入口逐檔略過）** | 第 18 列是入口的單一字串上限，值夾在兩個量測錨點之間；這一列同形而對象是整份內容，而且**只有一個錨點**：上限是使用者 2026-09-30 的裁決，約為最大單檔的 48.8 倍（以 MB 粗算 256／5.5 ≈ 46），不是兩個量測夾出來的。不寫的代價與第 18 列同形：沒有上限時，群組 library 裡別人放的一個大附件會被整份讀進記憶體（乾跑也一樣），而那是一次呼叫一步跨過、沒有曲線可以預警。與第 18 列不同的是拒絕的形狀：`copy-zotero-attachments` 的其他「這個檔不能收」（檔案不在、不是普通檔、0 byte）本來就逐檔具名略過，超過上限是同一類，整批拒絕會讓一個大附件擋住其餘全部——所以 `lossless-intake` 有界拒絕的第 1 條（整批）在這個入口換成逐檔、具名、附大小，該檔同批寫明為什麼仍不是靜默丟棄；單檔的 `store-source` 就是一整批，照第 1 條整個拒絕。**同批另兩件不是守衛**：逐塊**加上每塊讀完即釋放**是記憶體的界——~~`SourceIntakeStreamingTests.testDigestAndCopyNeverAskForMoreThanOneChunk` 釘住每次只要一塊~~（#703 R1 verify 第 2、8 則：那支只證每次只要一塊，量不到留住了幾塊；`FileHandle.read(upToCount:)` 回的 autoreleased 緩衝在 CLI 裡留到行程結束，改動前的 binary 存 128 MiB 的檔尖峰 RSS 284,557,312 bytes，比整份讀進來還多）→ 現在 `LibraryStore.pump` 每塊包一個 autorelease pool，由 `SourceIntakeMemoryCLITests` 以真 binary 的尖峰 RSS 釘住（#703 R1 實測：128 MiB 的檔比 1 MiB 的多 1,146,880 bytes，三個 48 MiB 的附件比一個 1 MiB 的多 3,964,928 bytes）；既有 blob 的比對是 #606 留下的缺口（被截短或換掉的 blob 以前看不出來；不符列在 `storedBlobMismatch`、不覆寫；R1 起新連結遇到位址上判不出來的存檔也不連）。**觸發條件可檢查**（腳本見表下方）：最大單檔逼近上限時回 #703 重開——那時先問那份檔是不是一份文獻的全文。 |
| 73 | **零實例，而殘留與進行中長得一樣**（#703 R1 verify 第 13、18、22、23 則：`writeBlob` 的暫存檔 `.<62 hex>.incoming-<UUID>` 只靠 `defer` 清理，行程在複製途中被殺掉（SIGKILL、斷電、逾時）時留在分片目錄裡，一份可以到上限那麼大；`auditSourceIndex` 只認 62 hex 的檔名，doctor 看不到、也沒有清理面。R1 verify 實測（#703）：對 240 MB 的檔跑 `store-source`、複製到一半 `kill -9`，留下 118,489,088 bytes 的暫存檔，之後 doctor 一切如常。2026-09-30 唯讀量測 live store：分片目錄裡這個形狀的檔 **0** 個。重跑指令見表下方） | ✅ **寫（warning 級：doctor 的 sources 一致性逐行列路徑與大小，MCP 與 App 讀同一份 audit；只報不刪）** | 第 15 列的零是本機的、第 23 列的可達路徑是本 change 自己開的；這一列兩者都有一點而理由不同：暫存檔是 #703 自己開始管的（先前的 `Data.write(.atomic)` 由 Foundation 管暫存，窗口只有一次寫入那麼長；現在是逐塊複製兩遍 I/O 的時間），它**必然**會在被殺的行程之後留下，而它與一個正在進行的存檔在磁碟上完全相同——所以守衛只能報、不能刪。以年齡判斷「一定是殘留」是猜（一份 256 MiB 的檔在慢磁碟上要寫多久沒有上界），猜錯的代價是刪掉別人正在寫的暫存、讓那一次存檔失敗；報而不刪的代價是人看一眼。**severity 是 warning**：記錄與 blob 都沒有壞，佔的是磁碟；它仍計入 `hasFindings`（要人看一眼，與孤兒 blob 同級）。**形狀只有一份**：建立（`writeBlob`）、預演（`preflightStoreSource`）與報告都讀 `LibraryStore.temporaryBlobName`／`isTemporaryBlobName`，FAT 卷上 macOS 自己寫的 `._` 檔不算。**觸發條件可檢查**（指令見表下方）：數目應恆為 0；非零時先確認沒有 `store-source`／`copy-zotero-attachments` 在跑，再刪掉那幾個檔 |

對本表四類中的任一個做出下一次裁決（新增、不新增、保留、拿掉）= 在這張表加一列。

**第 12 列的零是駁回出來的——量測腳本**（2026-09-03，`~/.akashic/entities`）。第一行印 person 總數與三個計數，對應第 12 列情形欄的 865／11／1／0（有 ≥2 個不同 confirmed literal 的 person、其中跨書寫系統的、其中有兩個彼此無共同 token 拉丁名的）；接著逐人列出那些 literal，**駁回理由要拿這份清單逐筆核對**（實跑：10 組只差縮寫形、標點或大小寫，1 組跨書寫系統）。「拉丁名」的判準寫在腳本裡（至少一個字母，且每個字母的 Unicode 名稱都以 `LATIN ` 或 `FULLWIDTH LATIN ` 開頭——後者是 #568 補的，與 Swift 的 `WritingSystem` 對齊；live store 沒有全形名字，計數不受影響——漢字、假名、諺文、西里爾都不算；不要求 ASCII、不靠 code-point 範圍）。這個判準改了兩次：第一版只排除 CJK，會把其他書寫系統當拉丁名、空 token 會誤算「無共同 token」（Codex R2 抓到）；第二版要求至少一個 ASCII 字母且只認部分拉丁區塊，`É` 單獨會被判非拉丁、`[À-ɏ]` 範圍含 `×`／`÷`（Codex R3 抓到）。三版在 live store 上都得同一組數——邊界案例目前沒有實例，但判準要與散文說的一致：

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
def is_latin_letter(c): return c.isalpha() and unicodedata.name(c, '').startswith(('LATIN ', 'FULLWIDTH LATIN '))   # #568：與 Swift 的 WritingSystem 同一條；全形的名稱是 FULLWIDTH LATIN …
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

**第 16 列的量測（2026-09-04；2026-09-26 改量檔案位元組，可重跑）**：warning 數 `akashic validate 2>&1 | grep -c 'venue 的記錄檔逼近讀取上限'`（應為 0；2026-09-26 前綴改名，舊前綴是「venue 的 verdict 數逼近 decode 預算」——量的已不是筆數）；最大檔 `ls -l ~/.akashic/entities/*.yaml | sort -k5 -n | tail -1`（2026-09-26：268,627 bytes，即 `psychological-methods`，1,352 筆 verdict）；門檻 `AliasEventBudget.recordFileWarningBytes`（4,194,304＝8 MiB÷2）。舊門檻 11,111 筆（200,000÷2÷9）量的是對 store 檔不生效的節點軸，已退場。

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
（2026-09-09：58；2026-09-14 重跑：59；2026-09-27：70；2026-09-29（#629 移植後）：61）。**顯式 vs glob 的拆分**——顯式＝路徑字面出現在 `ProtectedInventory.swift` 裡的那些（受保護清單的單一來源，#522 起從 `TriggerCoverage.swift` 搬過去；#571 之前腳本仍在舊檔找，所以量到 2）：

```bash
python3 - <<'EOF'
import io
lines = [l for l in io.open(".githooks/protected-ratchet.txt", encoding="utf8").read().split("\n") if l]
src = io.open("Sources/akashic-guards/ProtectedInventory.swift", encoding="utf8").read()
explicit = [l for l in lines if f'"{l}"' in src]
print(f"受保護 {len(lines)}｜顯式字面 {len(explicit)}｜glob／衍生 {len(lines)-len(explicit)}")
EOF
# 2026-09-09：受保護 58｜顯式字面 21｜glob／衍生 37
# 2026-09-14 重跑：59｜2｜57——「顯式字面」從 21 掉到 2 不是計數誤差，`TriggerCoverage.swift` 的路徑字面寫法變了，
# 這個拆分判準已失效；本列理由欄的 37/58 與 19/19 隨之過期（#554 R9 verify 第 17／20 列，#571 另案重定量法）
# 2026-09-27（#571）：原因不是寫法變了，是**清單換了家**——#522 把它搬進 `ProtectedInventory.swift`，腳本還在舊檔找。
# 腳本改指新檔後重量：受保護 70｜顯式字面 22｜glob／衍生 48
# 2026-09-29（#629：十一個 shell／Python 守衛與測試移植成 Swift 或退場、兩個 Swift 守衛新增）重量：受保護 61｜顯式字面 18｜glob／衍生 43
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
    if m and re.search(r'^\s+(start|end|ended|attested):', m.group(1), re.M): dated += 1
print(f"venue {n} 筆｜names 帶時間欄位 {dated} 筆")   # 2026-09-09：406 / 0；2026-09-14 重跑：485 / 0；2026-09-29 鍵改成 ended 後重跑：485 / 0
EOF
```

**第 23 列的量測（2026-09-09，可重跑）**：矛盾數 `akashic validate 2>&1 | grep -c '移除記錄與作者位互相矛盾'`
（應為 0；用含這條檢查的 binary——同第 13 列的自證，舊 binary 印不出東西）；移除記錄總數
`grep -c '^  judgement: 移除：' ~/.akashic/entities/*.yaml | awk -F: '{s+=$2} END {print s+0}'`
（2026-09-09：**0**——`--drop-author` 尚未對 live store 執行，等 store format bump 到 17）。

**第 24 列的量測（2026-09-11 首量；2026-09-18 R2 改寫並重跑，可重跑）**：觸發條件見理由欄（R2 寫「情形欄」，指錯欄——R2 verify 第 12 列）——腳本印的五個數裡**重複群**與**含 org 候選的 divergence** 兩個要為零才維持「暫不做」；organization 總數與帶 `parents` 筆數是脈絡，不是觸發（R1 寫「三個數字都要為零、任一非零即重開」，對自己的基線 13／3 就是假的——R1 verify 第 5／9 列）；第五個數**讀不到或不是記錄的檔**是母體的誠實邊界——一個壞檔曾讓整支腳本 traceback、四個數一個都不印（R1 第 28 列的處置「同第 16 列」只兌現了解析那一半，R2 verify 第 9 列），而照抄第 18 列腳本的 `except: continue`（R3 寫「第 12 列」，那支根本沒有 try——R3 verify 第 10 列；第 18 列那支至今仍是靜默跳過，已知缺口：它量的是長度分布，少算一筆不改變 15.5 倍的結論）會把「零輸出」換成「安靜少算」；現在跳過並計數。**這個數與 `akashic validate` 的 quarantine 是有向的包含、不是相等**（R3 寫「對得起來」，R3 verify 第 1／3／12 列三席同指）：它只涵蓋 YAML 解不開與頂層不是 mapping，quarantine 另含解析得了但 schema 不合法的記錄（非 UUID 檔名、形狀標籤帶值……），那些檔**會被腳本算進前四個數**——所以 quarantine ≥ 這個數是常態；非零時去對 quarantine 清單，別追一個不存在的差。腳本的母體是磁碟上的 `.yaml`，binary 的母體是載入成功的記錄，兩邊的 org divergence 數在有 quarantine 檔時可以不同（方向是腳本多報）。目錄讀不到（新 clone、HOME 打錯）印一句具名的話後退出，不 traceback（R3 verify 第 16／19 列）。「含 org 候選的 divergence」那個數（R3 寫「第二個數」，照位置讀是重複群——R3 verify 第 13 列）自 R2 起由 binary 出聲：`grep -a -q '沒有合併管線' "$(command -v akashic)" && akashic validate 2>&1 | grep -c '^⚠ divergence .*歧異記錄的 shape 沒有合併管線：'`（應印 0；**沒印任何東西＝PATH 上的 `akashic` 是沒有這條檢查的舊 binary**——R3 的指令沒有這道閘，2026-09-18 實測 `~/bin/akashic` 就是舊的、照抄印 0 冒充乾淨，R3 verify 第 5 列；第 13 列的構造逐字搬過來。**行首錨 `^⚠ divergence `** 讓 store 內容偽造不了它：一個名字含這句話的 venue 會讓無錨的 grep 多算（R3 verify 第 18 列，實測 2 個假 venue 名字得 2），錨在 binary 自己印的前綴上就不會；**帶全形冒號**——它數的是逐則 warning，家族計數行用 ASCII 冒號；不帶冒號會把計數行也數進去、一筆記錄得 2，R2 verify 第 10 列 Codex）；理由欄那句 bootstrap 的重跑：`akashic bootstrap-organizations`（2026-09-18：無可自動建立的候選，另有 1 個產不出 key 的機構名待人工指定）。R1 的腳本對檔首註解與 `.YAML` 靜默漏算、`shape: organization` 是含空白的無錨點子字串、值不 `str()` 就當掉（R1 verify 第 16／26／28／29 列）——R2 改以 yaml 解析後看頂層鍵與 `candidates[].shape`；`key()` 是 `LooseTitleKey.key` 的鏡射，改一邊要同批改另一邊；固定案例的出處逐條寫（R2 寫「取自那個檔頭」，四條裡兩條不是——R2 verify 第 17 列）：JRSS 的三種標點寫法與 BJMSP 的 `&`／and 取自 `LooseTitleKey` 檔頭；`The Guilford Press`＝`Guilford Press` 取自 live store 的 venue `the-guilford-press`（names 同時有兩種寫法）；`Science`≠`Sciences` 是**負控**、取自 `identity-is-judged-not-matched`（所方正式名稱與 ScienceDirect 的誤植）。

```bash
python3 - <<'EOF'
import io, os, unicodedata, yaml, collections
# 鏡射 LooseTitleKey.key（NFKC → 丟 Cf → 小寫 → `&`→and → 標點折成空白 → 剝前導冠詞）——改一邊要同批改另一邊。
# 樸素鏡射的誠實邊界：連字號家族與空白在 scalar 上處理，Swift 在 grapheme cluster 上（第 27 列量測段記過同一件事）；機構名裡零實例。
ART = {"the","a","an"}
def key(s):
    s = unicodedata.normalize('NFKC', str(s))
    s = ''.join(c for c in s if unicodedata.category(c) != 'Cf').lower().replace('&', ' and ')
    s = ''.join(c if (c.isalnum() or c.isspace()) else ' ' for c in s)
    t = s.split()
    while t and t[0] in ART: t.pop(0)
    return ' '.join(t)
# 固定案例（出處見上方散文：前兩條取自 LooseTitleKey 檔頭、第三條取自 live store 的 venue、第四條是負控；寬鬆鍵不摺詞形——那是提名不是判定）
assert key('Journal of the Royal Statistical Society Series B: Statistical Methodology') == key('Journal of the Royal Statistical Society Series B (Statistical Methodology)') == key('JOURNAL OF THE ROYAL STATISTICAL SOCIETY SERIES B-STATISTICAL METHODOLOGY')
assert key('British Journal of Mathematical & Statistical Psychology') == key('British Journal of Mathematical and Statistical Psychology')
assert key('The Guilford Press') == key('Guilford Press')
assert key('Institute of Statistical Science') != key('Institute of Statistical Sciences')
root = os.path.expanduser('~/.akashic/entities')
g = collections.defaultdict(set); n = with_parents = org_div = unreadable = 0
try: names = sorted(os.listdir(root))
except OSError as e: raise SystemExit(f'讀不到 {root}：{e}——五個數一個都沒量')   # 目錄層也不 traceback（R3 verify 第 16／19 列）
for name in names:
    if name.startswith('.') or not name.lower().endswith('.yaml'): continue   # 鏡射 LibraryStore 的過濾：`.YAML` 也算、dotfile 不算（R3 verify 第 17 列）
    try: d = yaml.safe_load(io.open(os.path.join(root, name), encoding='utf8'))
    except Exception: unreadable += 1; continue                 # 壞檔不當掉也不靜默——計數印出來（R2 verify 第 9 列）；quarantine ⊇ 這個數，見上方散文
    if not isinstance(d, dict): unreadable += 1; continue        # 不是 mapping 的 YAML 不是記錄，同上
    if 'organization' in d:                                   # 頂層鍵判 shape，不看檔首那一行（檔首註解會讓 startswith 漏掉）
        n += 1
        if d.get('parents'): with_parents += 1
        names = d.get('names') or []
        for x in (names if isinstance(names, list) else []):
            nm = x.get('value') if isinstance(x, dict) else x
            if nm is not None and key(nm): g[key(nm)].add(str(d.get('key')))
    elif 'divergence' in d:
        if any(isinstance(c, dict) and c.get('shape') == 'organization' for c in (d.get('candidates') or [])):
            org_div += 1
dupes = len([k for k, v in g.items() if len(v) >= 2])
print(f"organization {n} 筆｜重複群 {dupes} 組｜含 org 候選的 divergence {org_div} 筆｜帶 parents {with_parents} 筆｜讀不到或不是記錄的檔 {unreadable} 個")
EOF
# 2026-09-11：organization 13 筆｜重複群 0 組｜含 org 候選的 divergence 0 筆｜帶 parents 3 筆
# 2026-09-18 R2 重跑（改寫後的腳本）：同——13／0／0／3
# 2026-09-18 R3 重跑（加第五個數）：13／0／0／3／0；R4 重跑（目錄閘、dotfile 過濾）：同。對帳：organization 總數 `grep -l '^organization:' ~/.akashic/entities/*.yaml | wc -l`（13）、
#   `akashic divergences --json` 唯一一筆的 shape 是 person。R2 曾寫「`akashic doctor` 的 organization 計數 13」——**doctor 沒有 organization 總數**，
#   它印的 `no authorized name: … / 13 organization` 是沒有 authorized name 的機構數，今天相等只因 13 筆全無 authorized name（R2 verify 第 8 列 DA）
```

**第 25 列的量測（2026-09-12，可重跑）**：venue 側名字內容的 error 應恆為 0——
`akashic validate 2>&1 | grep 'venue' | grep -v '則數已達上限' | grep -c 'canonical 形\|近重複\|同名段過多\|求值總量\|不是名字\|沒有名字\|格式或控制字元\|控制或方向控制\|不可見字元\|接合字元'`
（十個子串對應 `NameIdentity.wellFormednessIssue` 的七句訊息加 `Venue.validate()` 的近重複句、組內求值上限句「同名段過多」與整筆記錄的求值總量句——R5 的 grep 漏了空名的「沒有名字」，Python 對照卻算它，兩套量測分歧；R6 補齊並加不可見／接合字元兩類；R18 加兩類求值上限句、並排除概括句（R17 verify 第 11 列：R17 的概括句含「venue」與「近重複」，會被數成一則名字內容 error，而求值上限那一類完全數不到）。**這個數量的是訊息行數**：近重複一組最多 3 對、概括句不算、每筆記錄至多 20 組——與下方 Python 對照的「對數」在配額到頂時必然分岔，兩邊都是 0 時才是同一件事）
（用含這條檢查的 binary——同第 13 列的自證；注意 person 側另有 #296 的近重複 **warning**，
`grep 'venue'` 才不會把那些算進來）。Python 對照（不依賴 binary）：

```bash
python3 - <<'EOF'
import glob, io, os, re, unicodedata, yaml
# 鏡射 Swift 的 NameIdentity.wellFormednessIssue 與 Venue.validate() 的近重複掃描（改一邊要同批改另一邊）：
#  - canonical：NFC、只丟 White_Space（顯式集合——Python isspace() 把 U+001C–001F 也當空白，Swift 不會）、
#    內部空白串收成一個 U+0020
#  - 危險／不可見：Cc／Cf／Zl／Zp、Default_Ignorable_Code_Point（unicodedata 沒有 DI 屬性，用
#    DerivedCoreProperties 的區段列舉——UAX #44 的表，版本差異只在未指派碼位）、`rendersBlank` 的五個碼位
#  - ZWJ／ZWNJ 例外：(a) 前一個 scalar 是 virama（ccc 9）、從 virama 往前跳過標記找到的基底是字母、virama 與
#    跳過的標記都是基底那個文字的（D22）、右鄰居若在要是同一文字的字母／數字——右鄰居是空白視同沒有（多字刊名的
#    詞尾 chillu）；(b) 左鄰居是 join-control 文字的字母／標記／數字、右鄰居是同一文字的字母／數字，或同一 Indic
#    Devanagari／Bengali 的 virama 且其後接同文字的字母（Bengali ya-phalaa <RA, ZWJ, VIRAMA, YA>，D21／D26——
#    每個引用實例都是 <C, J, H, C>，沒有後續輔音的 joiner 是純隱形位元組差）（標點不算；joiner 自己也不算，所以連續 joiner 必拒）
#  - 至少一個字母或數字（generalCategory 的 L／N 類——Python 的 isalnum() 正是這個，不含 Other_Alphabetic 的標記）
#  - names 近重複豁免：兩段都作時間宣稱（`DateRange.makesTemporalClaim`：start／end 非空、ended 為 true、
#    或 attested 非空）、一段的 end 與另一段的 start 都是 ISO 8601 前綴（鏡射 `ISO8601Prefix.isValid`：ASCII 數字、
#    月 01–12、日 01–31）、且 end 以較粗粒度截斷後嚴格小於 start
DI = [(0x00AD,0x00AD),(0x034F,0x034F),(0x061C,0x061C),(0x115F,0x1160),(0x17B4,0x17B5),(0x180B,0x180F),
      (0x200B,0x200F),(0x202A,0x202E),(0x2060,0x206F),(0x3164,0x3164),(0xFE00,0xFE0F),(0xFEFF,0xFEFF),
      (0xFFA0,0xFFA0),(0xFFF0,0xFFF8),(0x1BCA0,0x1BCA3),(0x1D173,0x1D17A),(0xE0000,0xE0FFF),(0x2800,0x2800),
      (0x13441,0x13442),(0x16FE4,0x16FE4),(0x1D159,0x1D159)]   # 後三組：`UnsafeToEmitScalar.rendersBlank`（#569 R1 verify）
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
                   or x.get('ended') is True or bool(x.get('attested')))
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
             ((S(start='1933',end='1960'), S(ended=False)), True),
             ((S(start='1933',end='1960'), S(attested=[])), True),
             ((S(start='1933',end='1960'), S(start='1961', ended=True)), False),
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
regression 第 30 列）：空白類用 Unicode 的 `White_Space` 集合（R15 當時 Swift 走 `Character.isWhitespace`；#574 起改在 scalar 上看 `properties.isWhitespace`，集合相同），不用 Python `str.split()`（它把 U+001C–001F 也當空白
——store 內不可達，但同檔第 25 列早就顯式列舉了）；連字號家族在 **grapheme cluster** 上比（Swift 的 `hyphenFamily.contains(Character)`）
——連字號後面跟著組合符號時整個 cluster 不在家族裡、**不**取代，DA 實測 `A-\u0301B` 與 `A\u2010\u0301B` 在 Swift 是兩個鍵而 R14 的鏡射判成一個。
**R16 再對齊兩處**（R15 verify logic 第 9／11 列、DA 第 24 列；Claude 代裁 D46，2026-09-16 用逐字複製的 `matchingKey` 探針量過）：(1) 空白也在
Character 上切——**機制是 grapheme 分群，不是 `isWhitespace` 讀幾個 scalar**（R17 更正，R16 verify DA 第 10 列：R16 寫成「只看第一個 scalar」，
鏡射照著無條件吞，60,033 例差分裡 2,967 例源於此）：U+0020 與其他 Zs 類空白（NFKC 後大多已折成 U+0020；U+1680 仍是 Zs）後面的組合符號依
GB9 併進同一個 cluster，`split(whereSeparator: \.isWhitespace)` 看到的是一個 `isWhitespace` 為 true 的 Character、**整個丟掉**、組合符號一起消失
（`A \u0301B` → `a b`；`canonical` 自 R6 起在 scalar 上切、不會這樣——`matchingKey` 這個資料損失另案 **#574**，鏡射照現況鏡射，修那條時要同批改這裡——**#574 已於 2026-09-27 修掉**：`matchingKey` 改在 scalar 上切，任何空白後面的組合符號都保留；下方鏡射與固定案例同批改。改之前量過 live store 202,139 個字串值，key 會變的 0 個）；
而 TAB／LF／VT／FF／CR／NEL／LS／PS 在 GCB 屬 **Control**，依 GB4 後面一定斷開，組合符號自成 cluster、**保留**（`A\t\u0301B` → `a \u0301b`）——
2026-09-16 探針對 `White_Space` 的 25 個碼位逐一量過，8 個是這一類（GCB Control）、17 個是 Zs（其中 U+2000–200A 的 11 個 NFKC 先折成 U+0020，落同一分支）——R17 曾寫「全部 14 個裡 8 個」，那是把 U+2000–200A 漏掉之後的數（R17 verify DA 第 10 列；同一份檔案第 25 列的 `WSSET` 自己就是 25 個），#574 的更正 comment 同批改；
(2) 連字號後接 ZWJ／ZWNJ 也是同一個 cluster（Grapheme_Extend）、不取代，之後 Cf 才被刪（`A\u2010\u200DB` → `a\u2010b`）。鏡射只認 M 類與
ZWJ／ZWNJ 當 extender——Swift 的 grapheme 規則另收 U+FF9E／FF9F（Lm）與 emoji modifier（Sk）等，刊名裡零實例，記為鏡射的誠實邊界（第 24 列）；
`lowercased()` 與 Python `lower()` 對特殊大小寫（İ、ß）的差異同屬邊界；**NFKC 那一步本身也有一處差異**（DA 第 10 列）：Foundation 的
`precomposedStringWithCompatibilityMapping` 對 `0301 FF9F 0BCD` 不做 canonical reordering（輸出 `0301 309A 0BCD`），ICU／Python 會——這個差分發生在任何
clustering 之前、修 clustering 收斂不了，同屬邊界）：

```bash
python3 - <<'EOF'
import glob, io, os, re, unicodedata, yaml
# 鏡射 NameNormalization.matchingKey：NFKC → 連字號家族（整個 grapheme cluster 恰為一個連字號才算：後接 M 類、ZWJ、ZWNJ 都不算）→ '-'
# → 刪 Cf → 小寫 → White_Space 收斂為單一空格（顯式集合，與第 25 列的 WSSET 同一份定義；在 **scalar** 上切，只丟空白、不刪其他 scalar
# ——#574 起。之前 Swift 在 Character 上切，Zs 類空白後面的組合符號隨 cluster 一起被丟，這裡曾照那個行為鏡射）
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
assert mk('A \u0301B') == 'a \u0301b'                          # #574 起空白後的組合符號保留（之前整個 cluster 被丟，R15 verify logic 第 9 列）
assert mk('A\u2010\u200dB') == 'a\u2010b'                      # 連字號＋ZWJ 是一個 cluster、不取代，ZWJ 隨後被當 Cf 刪掉（logic 第 11 列）
assert mk('A\u00a0\u0301B') == 'a \u0301b'                     # NBSP 經 NFKC 成空格，同上
assert mk('A\t\u0301B') == 'a \u0301b'                          # TAB：一直都保留；#574 起與 Zs 類空白一致
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

**第 28 列的量測（2026-09-16，可重跑）**：`akashic validate 2>&1 | grep -c '重複的判定記錄：'`（應為 0；用含這條檢查的 binary——同第 13 列的自證，
舊 binary 印不出東西；**帶冒號**——概括句的正文也含這六個字但接「；」，R24 verify 第 7 列，與第 27 列量測段修過的同一個錯；一則訊息＝一筆記錄的一個配對，
同一記錄兩個配對各有重複時是兩則，被截時是下限）。**D65 的量測（2026-09-17，R24）**：live store 8,671 筆 `value:` 行，以 NFC 正規化後計數的重複 **0** ＝
以原字串計數的重複 **0**——兩數相等即今天沒有只差 NFC／NFD 的配對，換鍵不改變任何既有記錄的意義（重跑：對每檔 `value:` 行各用 `unicodedata.normalize('NFC', v)`
與 `v` 各算一次 `Counter`，比較兩個重複數）。Python 對照要鏡射 `verdictEqualityKey`（field ＋ `kind:holder`
＋ `matchingKey(literal)`）——第 27 列的量測段已有 `mk()` 那份鏡射，以 (檔, field, `kind:holder`, `mk(literal)`) 分組、數 ≥2 的組即可，這裡不複製第二份。
同日順帶量的另一個數（D63 的立案理由）：live store 8,692 筆 verdict value 裡 **2 筆**被 emitter 折在 ` :: ` 之前——R22 的行級 needle 對它們永遠不命中。

**第 29 列的量測（2026-09-18，R33 重量，可重跑）**：`swift test --filter SanitizationBoundaryTests/testEverySinkBoundIsWithinTheInputCeiling`（四族各有地板，空掃描不是通過；第四族地板 0，它不撐任何東西）。Python 對照（不依賴 build；R32 的版本寫著 18／3 而腳本自己跑出 39／5——下面的期望值是 R33 實跑的）：

```bash
python3 - <<'EOF'
import re, glob, io
CEIL = 4096
fams = {'displaySafeError(max:)': r'displaySafeError\([^,)]+,\s*max:\s*([0-9_]+)\)',
        'displaySafeClipOnly(max:)': r'displaySafeClipOnly\((?:[^()]|\([^()]*\))*,\s*max:\s*([0-9_]+)\)',
        'sink 宣告的預設值': r'maxLineLength:\s*Int\s*=\s*([0-9_]+)',           # 生產者的 `max: Int = 200` 不在此族（R33）
        '呼叫端字面的 maxLineLength:': r'maxLineLength:\s*([0-9_]+)\b'}          # 零實例、地板 0
for name, pat in fams.items():
    ns = [int(m.replace('_','')) for f in glob.glob('Sources/**/*.swift', recursive=True)
          for m in re.findall(pat, re.sub(r'//.*', '', io.open(f, encoding='utf8').read()))]
    print(f"{name}: 站點 {len(ns)}｜最大 {max(ns) if ns else 0}｜超過 ceiling {sum(n > CEIL for n in ns)}")
EOF
# 2026-09-18（R33 實跑，HEAD 58bab46d）：displaySafeError(max:) 57｜4096｜0 ／ displaySafeClipOnly(max:) 39｜4096｜0 ／ sink 宣告的預設值 3｜400｜0 ／ 呼叫端字面 0｜0｜0
# R32 在這裡寫的是 18／3——腳本沒變、數字是抄錯的（R32 verify 第 3／10 列）；Swift 守衛的 `strippingLineComments` 比這裡的 `//.*` 保守，兩邊只會 ≥ 這些數
```

**第 30 列的量測（2026-09-25，可重跑）**：

```bash
python3 - <<'EOF'
import glob, io, os, yaml
mx = rmx = n = und = bad = 0
for f in glob.glob(os.path.expanduser('~/.akashic/entities') + '/*.yaml'):
    try: d = yaml.safe_load(io.open(f, encoding='utf8'))
    except Exception: bad += 1; continue          # 不靜默少算（第 24 列記過同形）
    if not isinstance(d, dict): bad += 1; continue
    for r in d.get('references') or []:
        if not isinstance(r, dict): continue
        n += 1
        if r.get('field') == 'resolution-undecided': und += 1
        j = r.get('judgement') or ''
        if isinstance(j, str): mx = max(mx, len(j.encode()))
        ro = r.get('rests-on') or []
        if isinstance(ro, list): rmx = max(rmx, len(ro))
print(f"reference {n}｜最長理由 {mx} 位元組（上限 4096；含 [rule: …] 尾註）｜rests-on 最多 {rmx}（上限 20）｜未決 {und}｜讀不到的檔 {bad}")
EOF
# 2026-09-25：reference 8747｜最長理由 687 位元組｜rests-on 最多 3｜未決 0
```

**第 31 列的量測（2026-09-26 改量檔案位元組，可重跑）**：warning 數 `grep -a -q 'person／organization 的記錄檔逼近讀取上限' "$(command -v akashic)" && akashic validate 2>&1 | grep -c 'person／organization 的記錄檔逼近讀取上限'`（應印 0；沒印任何東西＝舊 binary，同第 13 列的自證）。Python 對照量的就是工具比的那個數——記錄檔的位元組（讀不到的檔計數，同第 24 列）：

```bash
python3 - <<'EOF'
import glob, io, os, yaml
best = {'person': (0, ''), 'organization': (0, '')}; n = {'person': 0, 'organization': 0}; bad = 0
for f in glob.glob(os.path.expanduser('~/.akashic/entities') + '/*.yaml'):
    try: d = yaml.safe_load(io.open(f, encoding='utf8'))
    except Exception: bad += 1; continue
    if not isinstance(d, dict): bad += 1; continue
    for k in best:
        if k in d:
            n[k] += 1; size = os.path.getsize(f)
            if size > best[k][0]: best[k] = (size, str(d.get('key')))
print(n, '最大檔 bytes', best, '讀不到的檔', bad, '門檻 4194304')
EOF
# 2026-09-26：person 4575（最大 10869 bytes，chen-chien-hsiun）、organization 13（最大 717 bytes）｜讀不到 0
```

**第 32 列的量測（2026-09-26，可重跑）**：新 binary 對 live store 的 `akashic validate` rc 應為 0、沒有新的隔離（非 ASCII 號在載入時會被隔離）。Python 對照（用 YAML 解析，不用行級 grep——長 value 會折行）：

```bash
python3 - <<'EOF'
import glob, io, os, yaml
n = bad = unreadable = 0
for f in glob.glob(os.path.expanduser('~/.akashic/entities') + '/*.yaml'):
    try: d = yaml.safe_load(io.open(f, encoding='utf8'))
    except Exception: unreadable += 1; continue
    if not isinstance(d, dict): unreadable += 1; continue
    for key in ('issn', 'orcid', 'isbn'):      # store 檔是扁平 mapping（形狀標籤與欄位同層），只掃一次（R1 verify：上一版掃兩次）
        v = d.get(key)
        vals = [x.get('value') if isinstance(x, dict) else x for x in v] if isinstance(v, list) else ([v] if v is not None else [])
        for x in vals:
            n += 1
            if any(ord(c) > 127 for c in str(x)): bad += 1
    dois = d.get('doi') or []                   # doi 是清單（一筆作品可以有多個 DOI）
    for x in (dois if isinstance(dois, list) else [dois]):
        if any(ord(c) > 127 for c in str(x).split('/', 1)[0]): bad += 1  # DOI 註冊者段（R1 起同形）
print(f"issn／orcid／isbn 值 {n}｜非 ASCII（含 DOI 註冊者）{bad}｜讀不到的檔 {unreadable}")
EOF
# 2026-09-26（R1 重量）：141｜0｜0（另數了 2,445 個 DOI）
```

**第 33 列的量測（2026-09-26，可重跑）**：`akashic validate 2>&1 | grep -c '團體作者 key「'` 與 `akashic validate 2>&1 | grep -c 'venue key「.*」沒有對應的 venue 檔'`（#669 起 `venue key「…」重複` 也用這個前綴，所以錨在後半句；用含這條檢查的 binary——同第 13 列的自證，舊 binary 印不出東西；2026-09-26：2 與 0）。

**第 34 列的量測（2026-09-27，可重跑）**：`akashic validate 2>&1 | grep -c '隸屬 key「'` 與 `akashic validate 2>&1 | grep -c '上級機構 key「'`（用含這條檢查的 binary——同第 13 列的自證，舊 binary 印不出東西）。Python 對照（不依賴 binary；讀不到的檔計數，同第 24 列）：

```bash
python3 - <<'EOF'
import glob, io, os, yaml
root = os.path.expanduser('~/.akashic/entities')
orgs, affs, parents, bad = set(), [], [], 0
for f in glob.glob(root + '/*.yaml'):
    try: d = yaml.safe_load(io.open(f, encoding='utf8'))
    except Exception: bad += 1; continue
    if not isinstance(d, dict): bad += 1; continue
    if 'organization' in d:
        orgs.add(str(d.get('key')))
        parents += d.get('parents') or []
    elif 'person' in d:
        affs += (d.get('profile') or {}).get('affiliations') or []
def keyed(s):   # `- value: {key: X}` 是 .key；`- value: 名稱` 是 .literal
    v = s.get('value') if isinstance(s, dict) else None
    return str(v['key']) if isinstance(v, dict) and 'key' in v else None
da = sorted({k for s in affs if (k := keyed(s)) and k not in orgs})
dp = sorted({k for s in parents if (k := keyed(s)) and k not in orgs})
print(f"organization {len(orgs)}｜懸空的隸屬 key {len(da)} {da}｜懸空的上級機構 key {len(dp)} {dp}｜讀不到的檔 {bad}")
EOF
# 2026-09-27：organization 13｜懸空的隸屬 key 0 []｜懸空的上級機構 key 0 []｜讀不到的檔 0
```

**第 35 列的量測（2026-09-27，可重跑）**：`akashic validate 2>&1 | grep -c '重複的 reference：'`（用含這條檢查的 binary——同第 13 列的自證；**帶全形冒號**，否則會把計數行也數進去）。Python 對照（不依賴 binary；逐欄 NFC 等於 Swift `String` 的 canonical equivalence）：

```bash
python3 - <<'EOF'
import glob, io, os, unicodedata, yaml
VERDICT = {'resolution-confirmed', 'resolution-rejected', 'resolution-undecided'}
def key(o, norm):
    if isinstance(o, dict): return tuple(sorted((k, key(v, norm)) for k, v in o.items()))
    if isinstance(o, list): return tuple(key(v, norm) for v in o)
    return None if o is None else (unicodedata.normalize('NFC', str(o)) if norm else str(o))
refs = groups = variant = bad = 0
for f in glob.glob(os.path.expanduser('~/.akashic/entities') + '/*.yaml'):
    try: d = yaml.safe_load(io.open(f, encoding='utf8'))
    except Exception: bad += 1; continue
    if not isinstance(d, dict): bad += 1; continue
    by = {}
    for r in d.get('references') or []:
        if not isinstance(r, dict) or r.get('field') in VERDICT: continue
        refs += 1
        by.setdefault(key(r, True), []).append(key(r, False))
    for spellings in by.values():
        if len(spellings) > 1:
            groups += 1
            variant += len(set(spellings)) > 1
print(f"非判定 reference {refs}｜重複組 {groups}（其中只差位元組 {variant}）｜讀不到的檔 {bad}")
EOF
# 2026-09-27：非判定 reference 90｜重複組 0（其中只差位元組 0）｜讀不到的檔 0
```

**第 36 列的量測（2026-09-27，可重跑）**：`akashic validate 2>&1 | grep -c '掛在 .* 個 venue 上'`（用含這條檢查的 binary——同第 13 列的自證，舊 binary 印不出東西）。Python 對照（不依賴 binary；正規形＝去掉連字號、大寫；讀不到的檔計數，同第 24 列）：

```bash
python3 - <<'EOF'
import glob, io, os, yaml, collections
by = collections.defaultdict(set); n = bad = venues = 0
for f in glob.glob(os.path.expanduser('~/.akashic/entities') + '/*.yaml'):
    try: d = yaml.safe_load(io.open(f, encoding='utf8'))
    except Exception: bad += 1; continue
    if not isinstance(d, dict): bad += 1; continue
    if 'venue' not in d: continue
    venues += 1
    for x in d.get('issn') or []:
        v = x.get('value') if isinstance(x, dict) else x
        n += 1; by[str(v).replace('-', '').upper()].add(str(d.get('key')))
print(f"venue {venues}｜ISSN 值 {n}｜distinct {len(by)}｜掛在 ≥2 個 venue {sum(len(k)>1 for k in by.values())}｜讀不到的檔 {bad}")
EOF
# 2026-09-27：venue 485｜ISSN 值 59｜distinct 59｜掛在 ≥2 個 venue 0｜讀不到的檔 0
```

**第 37 列的量測（2026-09-28，可重跑）**：`PATH=/usr/bin:$PATH swift test --filter WriteGateRulingsTests 2>&1 | grep 'WriteGateRulings：'`（四行：CLI 葉命令數、裁決表格數、兩個差集與四種裁決的格數，以及三個逐腿命令各自的旗標數、裁決數與差集；沒印任何東西＝這個 test target 沒有這條檢查，同第 13 列的自證）。**不能用 `akashic --experimental-dump-help` 重算**：CLI 頂層對輸出逐行截 400、總行數截 200（2026-09-28 實測 7,062 行截成 200），JSON 在第 200 行被截斷。

```
# 2026-09-28：
WriteGateRulings：CLI 葉命令 57｜裁決表 57｜只在 CLI []｜只在表 []｜不寫 20／不閘 18／逐腿 3／過閘 16
WriteGateRulings：resolve-organizations 旗標 7｜裁決 7｜差異 []
WriteGateRulings：resolve-people 旗標 14｜裁決 14｜差異 []
WriteGateRulings：resolve-venues 旗標 7｜裁決 7｜差異 []
# 2026-09-28 #586 R1 verify 之後（dismiss-divergence 改為過閘，其餘三行不變）：
WriteGateRulings：CLI 葉命令 57｜裁決表 57｜只在 CLI []｜只在表 []｜不寫 20／不閘 17／逐腿 3／過閘 17
# 2026-09-29 #567 之後（`migrate-venue-variants` 退場刪除——它是那一格「不寫」；其餘三行不變）：
WriteGateRulings：CLI 葉命令 56｜裁決表 56｜只在 CLI []｜只在表 []｜不寫 19／不閘 17／逐腿 3／過閘 17
# 2026-09-29 batch11 整合之後（#544／#614 的 `update-entry` 過閘、#642 的 `library set-kind`（不閘）與 `library check`（不寫）；
# 其餘三行不變。整合 commit 先寫的 57／19／17 只加了 update-entry——把沒有 #642 的分支上的計數當成整合後的計數，
# #642 R1 verify 以 `swift test --filter WriteGateRulingsTests` 實印更正）：
WriteGateRulings：CLI 葉命令 59｜裁決表 59｜只在 CLI []｜只在表 []｜不寫 20／不閘 18／逐腿 3／過閘 18
```

**第 38 列的量測（2026-09-28，可重跑）**：拒絕本身由 `PerRecordFullListingTests.testNotFoundAndDuplicateKeysAreRefusedNotGuessed` 釘住（store 裡沒有重複時
binary 沒有東西可印，自證要靠測試）。Python 對照（不依賴 binary；讀不到的檔計數，同第 24 列；work 的 key 是 citekey、divergence 的 key 是檔名 UUID）：

```bash
python3 - <<'EOF'
import glob, io, os, yaml, collections, itertools
keys = collections.defaultdict(list); bad = 0
for f in glob.glob(os.path.expanduser('~/.akashic/entities') + '/*.yaml'):
    try: d = yaml.safe_load(io.open(f, encoding='utf8'))
    except Exception: bad += 1; continue
    if not isinstance(d, dict): bad += 1; continue
    for k in ('work', 'person', 'organization', 'venue', 'divergence'):
        if k in d:
            keys[k].append(os.path.basename(f)[:-5].upper() if k == 'divergence' else str(d.get('citekey' if k == 'work' else 'key')))
            break
dup = {k: sorted(x for x, n in collections.Counter(v).items() if n > 1) for k, v in keys.items()}
cross = {f'{a}×{b}': sorted(set(keys[a]) & set(keys[b])) for a, b in itertools.combinations(sorted(keys), 2) if set(keys[a]) & set(keys[b])}
print({k: len(v) for k, v in keys.items()}, '｜同 kind 重複 key', {k: len(v) for k, v in dup.items()}, '｜跨 kind 同 key', cross, '｜讀不到的檔', bad)
EOF
# 2026-09-28：person 4575、work 2563、venue 485、divergence 1、organization 13｜同 kind 重複 key 全 0｜跨 kind 同 key 只有 organization×venue 2 個｜讀不到的檔 0
```

**第 39 列的量測（2026-09-28，可重跑）**：唯讀，量的就是讀取路徑比的那個數——記錄檔的位元組（讀不到的檔計數，同第 24 列）；判定記錄的理由長度與 judge／refute 的上限對照（上限量的是呼叫端送來的理由，store 裡存的另含 `[rule: …]` 尾註，所以這個數偏大、方向安全）：

```bash
python3 - <<'EOF'
import glob, io, os, yaml
LIMIT = 8 * 1024 * 1024
best = {}; n = {}; bad = over = 0; jmax = (0, '')
for f in glob.glob(os.path.expanduser('~/.akashic/entities') + '/*.yaml'):
    size = os.path.getsize(f)
    if size > LIMIT: over += 1
    try: d = yaml.safe_load(io.open(f, encoding='utf8'))
    except Exception: bad += 1; continue
    if not isinstance(d, dict): bad += 1; continue
    kind = next((k for k in ('work', 'person', 'organization', 'venue', 'divergence') if k in d), None)
    if kind is None: bad += 1; continue
    n[kind] = n.get(kind, 0) + 1
    if size > best.get(kind, (0, ''))[0]: best[kind] = (size, str(d.get('key') or d.get('citekey') or d.get('id')))
    for r in d.get('references') or []:
        if isinstance(r, dict) and r.get('field') in ('resolution-confirmed', 'resolution-rejected'):
            j = r.get('judgement') or ''
            if isinstance(j, str) and len(j.encode()) > jmax[0]: jmax = (len(j.encode()), str(d.get('key')))
print('記錄數', n); print('各形狀最大檔 bytes', best)
print(f'超過讀取上限 {LIMIT} 的檔 {over}｜判定記錄最長理由 {jmax[0]} 位元組（{jmax[1]}；含 [rule: …] 尾註，上限 4096）｜讀不到的檔 {bad}')
EOF
# 2026-09-28：person 4575／work 2563／venue 485／organization 13／divergence 1；最大檔 venue 268627（psychological-methods）、
#   person 10869、work 5602、divergence 1004、organization 717；超過讀取上限 0｜最長理由 687 位元組｜讀不到 0
```

**第 40 列的量測（2026-09-28，可重跑）**：`akashic validate 2>&1 | grep -c '^⚠ \[跨記錄\] \(work\|person\)「.*」的檔案寫入時會被拒——'`（用含這條檢查的 binary——同第 13 列的自證，舊 binary 印不出東西；行首錨在 binary 自己印的前綴上，同第 24 列）。Python 對照（不依賴 binary；legacy 殘留是本列的前提——沒有它，load 不判斷任何記錄）：

```bash
python3 - <<'EOF'
import glob, os
root = os.path.expanduser('~/.akashic')
for d in ('entries', 'people'):
    n = len([f for f in glob.glob(os.path.join(root, d, '*')) if f.lower().endswith('.yaml')])
    print(f"legacy 殘留 {d}/：{n} 個檔")
EOF
# 2026-09-28：entries/ 0 個檔、people/ 0 個檔
```

**第 41 列的量測（2026-09-28，可重跑，唯讀）**：新 binary 對 live store 的 `akashic validate` 不應多出隔離（指向空內容 digest 的記錄在載入時被隔離）。Python 對照（不依賴 binary；YAML 解析後遞迴走過每個字串值，所以 `content`、`rests-on`、`akashic.sources`、divergence 的依據、timeline 的舊 `source:` 都涵蓋；讀不到的檔計數，同第 24 列）：

```bash
python3 - <<'EOF'
import io, json, os, yaml
E = 'sha256:e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855'   # 0 byte 的 SHA-256
root = os.path.expanduser('~/.akashic'); ents = os.path.join(root, 'entities')
hits, digests, files, bad = [], 0, 0, 0
def walk(o, path):
    global digests
    if isinstance(o, dict):
        for k, v in o.items(): walk(v, path + [str(k)])
    elif isinstance(o, list):
        for v in o: walk(v, path + ['[]'])
    elif isinstance(o, str) and o.startswith('sha256:'):
        digests += 1
        if o == E: hits.append('.'.join(path))
try: names = sorted(os.listdir(ents))
except OSError as e: raise SystemExit(f'讀不到 {ents}：{e}')
for n in names:
    if n.startswith('.') or not n.lower().endswith('.yaml'): continue
    try: d = yaml.safe_load(io.open(os.path.join(ents, n), encoding='utf8'))
    except Exception: bad += 1; continue
    if not isinstance(d, dict): bad += 1; continue
    files += 1; walk(d, [])
rows = empty_rows = 0
idx = os.path.join(root, 'sources', 'index.jsonl')
if os.path.exists(idx):
    for line in io.open(idx, encoding='utf8'):
        if not line.strip(): continue
        rows += 1
        try: empty_rows += json.loads(line).get('content') == E
        except Exception: pass
blob = os.path.join(root, 'sources', E[7:9], E[9:])
print(f"記錄 {files}｜sha256: 值 {digests}｜指向空內容 digest {len(hits)} {hits}｜index 列 {rows}（指向空 blob {empty_rows}）｜空 blob 在場 {os.path.exists(blob)}｜讀不到的檔 {bad}")
EOF
# 2026-09-28：記錄 7637｜sha256: 值 95｜指向空內容 digest 0 []｜index 列 95（指向空 blob 1）｜空 blob 在場 True｜讀不到的檔 0
```

**第 42 列的量測（2026-09-28，可重跑）**：`akashic validate 2>&1 | grep -c 'key「.*」重複——以 key 定位'`（用含這條檢查的 binary——同第 13 列的自證，舊 binary 印不出東西；錨在本列訊息自己的後半句上，不會數到第 33 列的懸空 venue key）。Python 對照見第 38 列的腳本——它逐 kind 數同 kind 重複 key（2026-09-28：全 0）。源碼那一半：`PATH=/usr/bin:$PATH swift test --filter DuplicateVenueOrgKeyTests/testNoStoreKeyLookupTableTrapsOnDuplicates`（2026-09-28：0 處違規）。

**第 43 列的量測（2026-09-29，可重跑）**：唯讀，數帶時間、source 或 note 的名字段，以及含 venue 候選的 divergence（讀不到的檔計數，同第 24 列）：

```bash
python3 - <<'EOF'
import glob, io, os, yaml
segs = dated = sourced = noted = venue_div = bad = 0
for f in glob.glob(os.path.expanduser('~/.akashic/entities') + '/*.yaml'):
    try: d = yaml.safe_load(io.open(f, encoding='utf8'))
    except Exception: bad += 1; continue
    if not isinstance(d, dict): bad += 1; continue
    if 'venue' in d:
        for x in d.get('names') or []:
            segs += 1
            if isinstance(x, dict):
                dated += any(x.get(k) is not None for k in ('start', 'end', 'ended', 'attested'))
                sourced += x.get('source') is not None
                noted += x.get('note') is not None
    elif 'divergence' in d:
        venue_div += any(isinstance(c, dict) and c.get('shape') == 'venue' for c in (d.get('candidates') or []))
print(f"名字段 {segs}｜帶時間 {dated}｜帶 source {sourced}｜帶 note {noted}｜含 venue 候選的 divergence {venue_div}｜讀不到的檔 {bad}")
EOF
# 2026-09-29：名字段 537｜帶時間 0｜帶 source 0｜帶 note 0｜含 venue 候選的 divergence 0｜讀不到的檔 0
# 2026-09-29 鍵改成 ended 後重跑（#675 R1 verify：先前查的 ended-unknown 不是 store 寫的鍵，只帶 ended: true 的段數不到）：同上
```

**第 44 列的量測（2026-09-29，可重跑）**：`grep '^format:' ~/.akashic/store.yaml`（2026-09-29：18）。**它量的是 live store 的 marker，不是情形欄說的「format-13 的 store 有幾筆帶 `variant` 的 venue」**（#642 R1 verify 第 40 則：兩者不是同一個命題）——後者只在 marker < 14 的 store 上有意義，而 live marker 是 18，所以這一列的零是「這台機器上沒有 store 落在閘管的範圍內」，不是「量到零筆違反」；閘本身由 `VenueStoreTests.testVariantWriteRefusedBelowFormat14` 釘住（那才是這一列的證據）。

**第 45 列的量測（2026-09-29，可重跑）**：唯讀（讀不到的檔計數，同第 24 列）：

```bash
python3 - <<'EOF'
import glob, io, os, yaml, collections
fields = collections.Counter(); issn = bad_q = jmax = rmax = bad = 0
for f in glob.glob(os.path.expanduser('~/.akashic/entities') + '/*.yaml'):
    try: d = yaml.safe_load(io.open(f, encoding='utf8'))
    except Exception: bad += 1; continue
    if not isinstance(d, dict) or 'venue' not in d: continue
    for x in d.get('issn') or []:
        issn += 1
        q = x.get('qualifier') if isinstance(x, dict) else None
        bad_q += q is not None and q not in ('print', 'electronic', 'linking')
    for r in d.get('references') or []:
        if not isinstance(r, dict): continue
        fields[r.get('field')] += 1
        j = r.get('judgement') or ''
        if isinstance(j, str): jmax = max(jmax, len(j.encode()))
        ro = r.get('rests-on') or []
        if isinstance(ro, list): rmax = max(rmax, len(ro))
print(f"ISSN 值 {issn}｜認不出的角色 {bad_q}｜references 各 field {dict(fields)}｜最長 judgement {jmax}｜rests-on 最多 {rmax}｜讀不到的檔 {bad}")
EOF
# 2026-09-29：ISSN 值 59｜認不出的角色 0｜references：resolution-confirmed 2200、paginated 36｜最長 judgement 287｜rests-on 最多 3｜讀不到的檔 0
```

**第 46 列的量測（2026-09-29，可重跑，唯讀）**：`akashic validate --library <store> 2>&1 | grep -c 'Zotero 來源.*被 [0-9]* 筆 entry 宣稱'`（同時涵蓋 `Zotero 來源「1:K」` 與 `Zotero 來源（裸 key「K」）` 兩種標籤；用含這條檢查的 binary——同第 13 列的自證，舊 binary 印不出東西）。Python 對照（不依賴 binary；鏡射 `ZoteroSourceClaims`：主來源與附加來源都算、沒記 `library_id` 的**主來源**進 `?:` 桶、沒記 `library_id` 的**附加來源**不算、以 entry id 去重）：

```bash
python3 - <<'EOF'
import glob, io, os, yaml, collections
claims = collections.defaultdict(set)   # 來源鍵 → entry id（以 id 去重，同一筆讀到兩次只算一次）
works = bad = extra_no_lib = 0
for f in glob.glob(os.path.expanduser('~/.akashic/entities') + '/*.yaml'):
    try: d = yaml.safe_load(io.open(f, encoding='utf8'))
    except Exception: bad += 1; continue
    if not isinstance(d, dict): bad += 1; continue
    if 'work' not in d: continue
    works += 1
    p = d.get('provenance')
    if isinstance(p, dict) and p.get('zotero_key') is not None:
        lid = p.get('library_id')
        claims[f"{'?' if lid is None else lid}:{p['zotero_key']}"].add(str(d.get('id')))
    for x in d.get('provenance_additional') or []:
        if not isinstance(x, dict) or x.get('zotero_key') is None: continue
        if x.get('library_id') is None: extra_no_lib += 1; continue   # 沒記 library_id 的附加來源不算
        claims[f"{x['library_id']}:{x['zotero_key']}"].add(str(d.get('id')))
multi = sorted(k for k, ids in claims.items() if len(ids) > 1)
legacy = sum(1 for k in claims if k.startswith('?:'))
print(f"work {works}｜來源鍵 {len(claims)}（其中沒記 library_id 的主來源 {legacy}）｜宣稱者 ≥2 的來源 {len(multi)} {multi[:5]}｜沒記 library_id 的附加來源（不算）{extra_no_lib}｜讀不到的檔 {bad}")
EOF
# 2026-09-29（R1 verify 重量）：work 2568｜來源鍵 535（其中沒記 library_id 的主來源 0）｜宣稱者 ≥2 的來源 0 []｜沒記 library_id 的附加來源（不算）0｜讀不到的檔 0
```

**第 47 列的量測（2026-09-29，可重跑，唯讀）**：`akashic validate 2>&1 | grep -c '筆成員不符規則（'`（R1 verify：訊息把指路句移到前段，冒號後接的是點名，所以錨在全形括號） 與 `akashic validate 2>&1 | grep -c '沒有標成員性質（'`（用含這條檢查的 binary——同第 13 列的自證，舊 binary 印不出東西；2026-09-29 預期 0 與 4）。Python 對照（不依賴 binary；只做規則型與文件型的比對，懸空規則由 binary 報）：

```bash
python3 - <<'PY'
import glob, io, os, yaml, collections
root = os.path.expanduser('~/.akashic')
libs, bad = {}, 0
for f in glob.glob(root + '/libraries/*.yaml'):
    try: d = yaml.safe_load(io.open(f, encoding='utf8'))
    except Exception: bad += 1; continue
    if isinstance(d, dict): libs[str(d.get('key'))] = d.get('membership')
works = []   # 保留重複：以 citekey 為鍵的 dict 會吞掉重複，「文件 citekey 重複」就永遠判不出來（#642 R1 verify 第 40 則）
for f in glob.glob(root + '/entities/*.yaml'):
    try: d = yaml.safe_load(io.open(f, encoding='utf8'))
    except Exception: bad += 1; continue
    if isinstance(d, dict) and 'work' in d: works.append(d)
kinds = collections.Counter((m or {}).get('kind', 'unmarked') if isinstance(m, dict) or m is None else 'malformed' for m in libs.values())
dup_ck = sum(n > 1 for n in collections.Counter(str(w.get('citekey')) for w in works).values())
viol = 0
for k, m in libs.items():
    if not isinstance(m, dict) or m.get('kind') not in ('rule', 'document'): continue
    for w in (w for w in works if k in ((w.get('akashic') or {}).get('libraries') or [])):
        if m['kind'] == 'rule':
            keys = [v.get('key') for v in (w.get('venues') or []) if isinstance(v, dict) and 'key' in v]
            ok = (w.get('citekey') not in (m.get('excluded') or [])) and m.get('venue') in keys \
                 and (not m.get('types') or w.get('type') in m['types'])
        else:
            doc = [x for x in works if x.get('citekey') == m.get('document')]
            ok = len(doc) == 1 and w.get('citekey') in (((doc[0].get('akashic') or {}).get('relations') or {}).get('cites') or [])   # len(doc) != 1：不在庫或 citekey 重複，一律不符
        viol += not ok
print(f"library {len(libs)}｜性質 {dict(kinds)}｜規則型／文件型成員不符 {viol}｜work 的重複 citekey {dup_ck} 組｜讀不到的檔 {bad}")
PY
# 2026-09-29：library 4｜性質 {'unmarked': 4}｜規則型／文件型成員不符 0｜讀不到的檔 0
# 2026-09-29（R1 verify 改寫：works 保留重複）：library 4｜性質 {'unmarked': 4}｜規則型／文件型成員不符 0｜work 的重複 citekey 0 組｜讀不到的檔 0
```

**第 48 列的量測（2026-09-29，可重跑，唯讀）**：角色的閘本身由 `VenueMergeReferencesAndISSNRolesTests` 釘住（live store 沒有含 venue 候選的 divergence，binary 沒有東西可印）。Python 對照（不依賴 binary；讀不到的檔計數，同第 24 列）：

```bash
python3 - <<'PY'
import io, os, yaml, collections
root = os.path.expanduser('~/.akashic/entities')
venues = issn_n = role_n = 0; roles = collections.Counter(); by = collections.defaultdict(set)
div_venue = refs_issn_names = paginated = bad = 0
try: names = sorted(os.listdir(root))
except OSError as e: raise SystemExit(f'讀不到 {root}：{e}')
for n in names:
    if n.startswith('.') or not n.lower().endswith('.yaml'): continue
    try: d = yaml.safe_load(io.open(os.path.join(root, n), encoding='utf8'))
    except Exception: bad += 1; continue
    if not isinstance(d, dict): bad += 1; continue
    if 'divergence' in d:
        if any(isinstance(c, dict) and c.get('shape') == 'venue' for c in (d.get('candidates') or [])): div_venue += 1
        continue
    if 'venue' not in d: continue
    venues += 1
    for x in d.get('issn') or []:
        v = x.get('value') if isinstance(x, dict) else x
        q = x.get('qualifier') if isinstance(x, dict) else None
        issn_n += 1; by[str(v).replace('-', '').upper()].add(str(d.get('key')))
        if q is not None: role_n += 1; roles[str(q)] += 1
    for r in d.get('references') or []:
        if not isinstance(r, dict): continue
        f = r.get('field')
        if f in ('issn', 'names'): refs_issn_names += 1
        elif f == 'paginated': paginated += 1
shared = sum(len(k) > 1 for k in by.values())
print(f"venue {venues}｜ISSN 值 {issn_n}｜帶角色 {role_n} {dict(roles)}｜含 venue 候選的 divergence {div_venue}｜同號掛 2+ venue {shared}｜field issn/names 的 reference {refs_issn_names}（paginated {paginated}）｜讀不到的檔 {bad}")
PY
# 2026-09-29：venue 485｜ISSN 值 59｜帶角色 9 {'linking': 1, 'electronic': 4, 'print': 4}｜含 venue 候選的 divergence 0｜同號掛 2+ venue 0｜field issn/names 的 reference 0（paginated 36）｜讀不到的檔 0
```

**第 49 列的量測（2026-09-29，可重跑，唯讀）**：`akashic doctor 2>&1 | grep -E '^orphaned( additional sources)?:'`（用含這條檢查的 binary——同第 13 列的自證，舊 binary 沒有第二行）。Python 對照（不依賴 binary；鏡射 `Entry.zoteroLinkState`，讀不到的檔計數，同第 24 列）：

```bash
python3 - <<'PY'
import glob, io, os, yaml, collections
# 鏡射 `Entry.zoteroLinkState`（#609）：
#   完好／整筆 orphan（主來源已刪除；或沒有主來源、附加來源 ≥1 且全部已刪除）／附加來源已刪除（主連結仍在，且至少一個附加來源已刪除）
state = collections.Counter()
sources = additional = bad = works = 0
for f in glob.glob(os.path.expanduser('~/.akashic/entities') + '/*.yaml'):
    try: d = yaml.safe_load(io.open(f, encoding='utf8'))
    except Exception: bad += 1; continue
    if not isinstance(d, dict): bad += 1; continue
    if 'work' not in d: continue
    works += 1
    p = d.get('provenance') if isinstance(d.get('provenance'), dict) else None
    extra = [x for x in (d.get('provenance_additional') or []) if isinstance(x, dict)]
    sources += (1 if p else 0) + len(extra); additional += len(extra)
    gone_extra = [x for x in extra if x.get('orphaned_at')]
    if p:
        if p.get('orphaned_at'): s = 'orphaned'
        else: s = 'additionalSourceOrphaned' if gone_extra else 'intact'
    else:
        if not gone_extra: s = 'intact'
        else: s = 'orphaned' if len(gone_extra) == len(extra) else 'additionalSourceOrphaned'
    state[s] += 1
    if not p and extra: state['(只有附加來源)'] += 1
print(f"work {works}｜Zotero 來源 {sources}（附加 {additional}）｜整筆 orphan {state['orphaned']}｜附加來源已刪除 {state['additionalSourceOrphaned']}｜只有附加來源的 entry {state['(只有附加來源)']}｜讀不到的檔 {bad}")
PY
# 2026-09-29：work 2568｜Zotero 來源 535（附加 3）｜整筆 orphan 0｜附加來源已刪除 0｜只有附加來源的 entry 0｜讀不到的檔 0
```

**第 50 列的量測（2026-09-29，可重跑，唯讀）**：閘本身由 `EntrySourceLinkTests.testABlobPathThatIsNotARegularFileIsRefused` 釘住（live store 沒有非普通檔，binary 沒有東西可印）。Python 對照（以 lstat 判類型，不跟隨 symlink）：

```bash
python3 - <<'PY'
import os, stat
root = os.path.expanduser('~/.akashic/sources')
n = 0; other = []; idx_kind = None
try: shards = sorted(os.listdir(root))
except OSError as e: raise SystemExit(f'讀不到 {root}：{e}')
for shard in shards:
    p = os.path.join(root, shard)
    if len(shard) != 2 or not stat.S_ISDIR(os.lstat(p).st_mode): continue
    for f in sorted(os.listdir(p)):
        st = os.lstat(os.path.join(p, f)); n += 1
        if not stat.S_ISREG(st.st_mode): other.append((shard + f, stat.filemode(st.st_mode)))
ip = os.path.join(root, 'index.jsonl')
if os.path.lexists(ip): idx_kind = stat.filemode(os.lstat(ip).st_mode)
print(f"sources/ blob {n}｜非普通檔 {len(other)} {other}｜index.jsonl {idx_kind}")
PY
# 2026-09-29：sources/ blob 99｜非普通檔 0 []｜index.jsonl -rw-r--r--
```

**第 51 列的量測（2026-09-29，可重跑）**：`for r in $(akashic-guards plugin-roots); do printf '%s ' "$r"; ls "$r"/rules/*.md 2>/dev/null | wc -l; done`（2026-09-29：`plugin 2`、`plugins/akashic-discovery 2`）。

**第 52 列的量測（2026-09-29，可重跑，唯讀）**：

```bash
python3 - <<'PY'
import os
root = os.path.expanduser('~/.akashic')
n = bad = 0; badlist = []
for sub in ('entities', 'entries', 'people'):
    d = os.path.join(root, sub)
    if not os.path.isdir(d): continue
    for f in os.listdir(d):
        if not f.endswith('.yaml'): continue
        p = os.path.join(d, f); n += 1
        if not os.path.isfile(p) or not os.access(p, os.R_OK): bad += 1; badlist.append(p)
print(f"記錄檔 {n}｜不可讀或非一般檔 {bad} {badlist[:5]}")
PY
# 2026-09-29：記錄檔 7643｜不可讀或非一般檔 0 []
```

**第 53–55 列的量測（2026-09-29，可重跑，唯讀）**：三列共用一支腳本；第 54、55 列看的是規則型、文件型 library 的筆數（都是 0，所以被規則指涉的 citekey 與標了性質可被替換的 library 都是 0）：

```bash
python3 - <<'PY'
import glob, io, os, yaml, collections
root = os.path.expanduser('~/.akashic')
libs, works, venues, bad = {}, [], [], 0
for f in glob.glob(root + '/libraries/*.yaml'):
    try: d = yaml.safe_load(io.open(f, encoding='utf8'))
    except Exception: bad += 1; continue
    if isinstance(d, dict): libs[str(d.get('key'))] = d.get('membership')
for f in glob.glob(root + '/entities/*.yaml'):
    try: d = yaml.safe_load(io.open(f, encoding='utf8'))
    except Exception: bad += 1; continue
    if not isinstance(d, dict): bad += 1; continue
    if 'work' in d: works.append(str(d.get('citekey')))
    elif 'venue' in d: venues.append(str(d.get('key')))
have = set(works); vcount = collections.Counter(venues)
rules = {k: m for k, m in libs.items() if isinstance(m, dict) and m.get('kind') == 'rule'}
dangling = sum(1 for m in rules.values() for ck in (m.get('excluded') or []) if str(ck) not in have)
ambiguous = sum(1 for m in rules.values() if vcount[str(m.get('venue'))] > 1)
docs = {k: m for k, m in libs.items() if isinstance(m, dict) and m.get('kind') == 'document'}
doc_bad = sum(1 for m in docs.values() if works.count(str(m.get('document'))) != 1)
print(f"library {len(libs)}｜規則型 {len(rules)}｜排除清單指向不在庫 {dangling}｜規則的 venue key 重複 {ambiguous}｜文件型 {len(docs)}（文件不在庫或重複 {doc_bad}）｜讀不到的檔 {bad}")
PY
# 2026-09-29：library 4｜規則型 0｜排除清單指向不在庫 0｜規則的 venue key 重複 0｜文件型 0（文件不在庫或重複 0）｜讀不到的檔 0
```

**第 56 列的量測（2026-09-29，可重跑，唯讀）**：`grep -a -q '附加 Zotero 來源沒記 library_id' "$(command -v akashic)" && akashic validate 2>&1 | grep -c '附加 Zotero 來源沒記 library_id'`（**前綴的 `grep -a -q … &&` 是自證閘**，同第 13 列：`grep -c` 沒命中時印 `0`，舊 binary、usage error、乾淨 store 三者輸出都是 `0`，分不開；沒印任何東西＝PATH 上的 `akashic` 是沒有這條檢查的舊 binary。b13f R1 verify 第 31 列補上；第 33–36 列的同型缺口是既有的，本輪不動）。Python 對照（讀不到的檔計數，同第 24 列）：

```bash
python3 - <<'PY'
import glob, io, os, yaml, collections
n_work = additional = additional_nolib = primary_nolib = primary = 0
claims = collections.defaultdict(set)
bad = 0
for f in glob.glob(os.path.expanduser('~/.akashic/entities') + '/*.yaml'):
    try: d = yaml.safe_load(io.open(f, encoding='utf8'))
    except Exception: bad += 1; continue
    if not isinstance(d, dict): bad += 1; continue
    if 'work' not in d and 'citekey' not in d: continue   # 只看 work
    if 'citekey' not in d: continue
    n_work += 1
    eid = str(d.get('id') or f)
    p = d.get('provenance')
    if isinstance(p, dict):
        primary += 1
        lid = p.get('library_id')
        if lid is None: primary_nolib += 1
        claims[f"{lid if lid is not None else '?'}:{p.get('zotero_key')}"].add(eid)
    for x in (d.get('provenance_additional') or []):
        if not isinstance(x, dict): continue
        additional += 1
        lid = x.get('library_id')
        if lid is None: additional_nolib += 1
        else: claims[f"{lid}:{x.get('zotero_key')}"].add(eid)
multi = sum(1 for k, v in claims.items() if len(v) > 1)
print(f"work {n_work}｜主來源 {primary}（沒記 library_id {primary_nolib}）｜附加來源 {additional}（沒記 library_id {additional_nolib}）｜被 ≥2 筆宣稱的來源 {multi}｜讀不到的檔 {bad}")
PY
# 2026-09-29：work 2569｜主來源 532（沒記 library_id 0）｜附加來源 3（沒記 library_id 0）｜被 ≥2 筆宣稱的來源 0｜讀不到的檔 0
```

**第 57 列的量測（2026-09-29，可重跑，唯讀）**：

```bash
python3 - <<'PY'
import glob, io, os, re, yaml
pat = re.compile(r'^10\.[0-9]{4,9}/[^\s\'"\\$`#?%]+$')
n = bad = unreadable = 0; badlist = []
for f in glob.glob(os.path.expanduser('~/.akashic/entities') + '/*.yaml'):
    try: d = yaml.safe_load(io.open(f, encoding='utf8'))
    except Exception: unreadable += 1; continue
    if not isinstance(d, dict): unreadable += 1; continue
    if 'work' not in d: continue
    dois = d.get('doi') or []
    for x in (dois if isinstance(dois, list) else [dois]):
        v = str(x.get('value') if isinstance(x, dict) else x); n += 1
        segs = v.split('/')[1:]
        if not pat.fullmatch(v) or any(s in ('.', '..') for s in segs): bad += 1; badlist.append(v)
print(f"work DOI {n}｜形狀檢查不過 {bad} {badlist[:5]}｜讀不到的檔 {unreadable}")
PY
# 2026-09-29：work DOI 2449｜形狀檢查不過 0 []｜讀不到的檔 0
```

**第 58 列的量測**：沒有可量的母體（校準從未在本機跑過）；閘由上面那支 CLI 測試釘住。

**第 59–60 列的量測（2026-09-29，可重跑，唯讀）**：兩列共用一支腳本（它另外數了帶 `akashic.sources` 的 work，是 #677 移除腿的母體）：

```bash
python3 - <<'PY'
import glob, io, os, yaml, collections
root = os.path.expanduser('~/.akashic/entities')
venues = with_generic = generic = dup_groups = works = works_with_sources = sources_total = bad = 0
maxn = 0
for f in glob.glob(root + '/*.yaml'):
    try: d = yaml.safe_load(io.open(f, encoding='utf8'))
    except Exception: bad += 1; continue
    if not isinstance(d, dict): bad += 1; continue
    if 'venue' in d:
        venues += 1
        gen = [r for r in (d.get('references') or []) if isinstance(r, dict)
               and not str(r.get('field', '')).startswith('resolution-') and r.get('field') != 'paginated']
        if gen: with_generic += 1
        generic += len(gen); maxn = max(maxn, len(gen))
        c = collections.Counter(repr(sorted((k, str(v)) for k, v in r.items())) for r in gen)
        dup_groups += sum(1 for n in c.values() if n > 1)
    elif 'work' in d:
        works += 1
        s = (d.get('akashic') or {}).get('sources') or []
        if s: works_with_sources += 1; sources_total += len(s)
print(f"venue {venues}｜帶通用 reference 的 venue {with_generic}｜通用 reference {generic}（單筆 venue 最多 {maxn}）｜位元組相同的重複組 {dup_groups}"
      f"｜work {works}｜帶 akashic.sources 的 work {works_with_sources}（{sources_total} 條）｜讀不到的檔 {bad}")
PY
# 2026-09-29：venue 485｜帶通用 reference 的 venue 0｜通用 reference 0（單筆 venue 最多 0）｜位元組相同的重複組 0｜work 2569｜帶 akashic.sources 的 work 0（0 條）｜讀不到的檔 0
```

**第 61 列的量測（2026-09-29，可重跑，唯讀）**：

```bash
python3 - <<'PY'
import glob, io, os, yaml
root = os.path.expanduser('~/.akashic/entities')
works = with_add = maxadd = maxsrc = bad = venues = generic = 0
for f in glob.glob(root + '/*.yaml'):
    try: d = yaml.safe_load(io.open(f, encoding='utf8'))
    except Exception: bad += 1; continue
    if not isinstance(d, dict): bad += 1; continue
    if 'work' in d or 'citekey' in d:
        works += 1
        add = d.get('provenance_additional') or []
        if add: with_add += 1; maxadd = max(maxadd, len(add))
        maxsrc = max(maxsrc, len((d.get('akashic') or {}).get('sources') or []))
    elif 'venue' in d:
        venues += 1
        generic += sum(1 for r in (d.get('references') or []) if isinstance(r, dict)
                       and not str(r.get('field', '')).startswith('resolution-') and r.get('field') != 'paginated')
print(f"work {works}｜有附加 Zotero 來源的 work {with_add}（單筆最多 {maxadd}）｜單筆 work 最多 akashic.sources {maxsrc}｜venue {venues}｜通用 reference {generic}｜讀不到的檔 {bad}")
PY
# 2026-09-29：work 2572｜有附加 Zotero 來源的 work 3（單筆最多 1）｜單筆 work 最多 akashic.sources 0｜venue 485｜通用 reference 0｜讀不到的檔 0
```

**第 62 列的量測（2026-09-29，可重跑，唯讀）**：`find ~/Downloads -maxdepth 2 \( -type d -o -type l \) -name '*.pdf' | wc -l`（2026-09-29：0）。

**第 63 列的量測（2026-09-29，可重跑，唯讀）**：

```bash
python3 -c "
import os
for d in (os.environ.get('TMPDIR','/tmp'), os.path.expanduser('~'), os.path.expanduser('~/Downloads'), '/tmp'):
    p = os.path.realpath(d); hit = None
    while True:
        if os.path.exists(os.path.join(p, '.git')): hit = p; break
        if p == '/': break
        p = os.path.dirname(p)
    print(d, hit)"
# 2026-09-29：四個都 None
```

**第 64 列的量測（2026-09-29，可重跑，唯讀）**：

```bash
python3 - <<'PY'
import glob, io, json, os
root = os.path.expanduser('~/.akashic/sources'); docs = dup = trail = bom = 0
def hook(pairs):
    global dup
    keys = [k for k, _ in pairs]
    if len(keys) != len(set(keys)): dup += 1
    return dict(pairs)
def walk(o):
    global bom
    if isinstance(o, str) and o.startswith('\ufeff'): bom += 1
    elif isinstance(o, dict): [walk(v) for v in o.values()]
    elif isinstance(o, list): [walk(v) for v in o]
for f in glob.glob(root + '/*/*'):
    try: b = io.open(f, encoding='utf-8').read()
    except Exception: continue
    for chunk in ([b] if b.lstrip()[:1] in '[{' else b.splitlines()):
        if not chunk.strip(): continue
        try: o = json.loads(chunk, object_pairs_hook=hook)
        except Exception:
            if ',}' in chunk.replace(' ', '') or ',]' in chunk.replace(' ', ''): trail += 1
            continue
        docs += 1; walk(o)
print(f"JSON 文件 {docs}｜重複鍵 {dup}｜尾隨逗號 {trail}｜字串開頭是 U+FEFF {bom}")
PY
# 2026-09-29：88｜0｜0｜0（母體是整份或逐行解得出的 JSON；#629 R1 報的 1,800 是另一個量法，不要拿兩個數相比）
```

**第 65 列的量測（2026-09-29，可重跑，唯讀）**：`grep -rl latestPastSegment Sources | grep -v -e AkashicCore/Temporal.swift -e AkashicCore/TimelineStanding.swift -e akashic-guards/BacklinkRatchetData.swift | wc -l`（應為 0）；live store 的分布由 `TimelineStandingTests` 的形狀清單對照，量法見 changelog `2026-09-29-attested-affiliation-wording.md`。

**第 66 列的量測（2026-09-29，可重跑，唯讀）**：

```bash
python3 - <<'PY'
import glob, io, os, re, yaml, collections
root = os.path.expanduser('~/.akashic/entities'); bad = 0
retr = collections.Counter(); judg = collections.Counter(); userinfo = []; scheme = collections.Counter(); status = collections.Counter()
for f in glob.glob(root + '/*.yaml'):
    try: d = yaml.safe_load(io.open(f, encoding='utf8'))
    except Exception: bad += 1; continue
    if not isinstance(d, dict): bad += 1; continue
    holder = next((k for k in ('person', 'organization', 'venue', 'work', 'divergence') if k in d), None)
    for r in d.get('references') or []:
        if not isinstance(r, dict): continue
        if 'url' in r:
            retr[holder] += 1; u = str(r['url'])
            m = re.match(r'^([A-Za-z][A-Za-z0-9+.-]*):', u); scheme[(holder, m.group(1).lower() if m else 'none')] += 1
            if re.match(r'^[a-z]+://[^/]*@', u): userinfo.append((holder, u))
            status[(holder, r.get('status'))] += 1
        elif 'judgement' in r: judg[holder] += 1
print('retrieval', dict(retr), '｜judgement', dict(judg), '｜scheme', dict(scheme), '｜status', dict(status), '｜帶帳密', len(userinfo), '｜讀不到的檔', bad)
PY
# 2026-09-29：retrieval 只有 work 33（https、status 200）｜person／venue／organization 0｜帶帳密 0
```

**第 67 列的量測（2026-09-29，可重跑，唯讀）**：`grep -rnE '(SELECT|WHERE|ORDER BY|GROUP BY|JOIN)[^"]*\borphaned\b|row\["orphaned"\]|\$0\["orphaned"\]' Sources --include='*.swift' | wc -l`（應為 0）；對照 `grep -rn 'orphaned INT' Sources --include='*.swift' | wc -l`（建表恰 1）。

**第 68 列的量測（2026-09-29，可重跑，唯讀）**：

```bash
cd ~/.akashic/entities && python3 - <<'PY'
import glob, io, collections, yaml
claims = collections.defaultdict(set); works = bad = 0
for f in glob.glob('*.yaml'):
    try: d = yaml.safe_load(io.open(f, encoding='utf8'))
    except Exception: bad += 1; continue
    if not isinstance(d, dict) or 'work' not in d: continue
    works += 1; cite = str(d.get('citekey'))
    provs = ([d['provenance']] if isinstance(d.get('provenance'), dict) else []) + [p for p in (d.get('provenance_additional') or []) if isinstance(p, dict)]
    for p in provs:
        if p.get('zotero_key'): claims[f"{p.get('library_id','?')}:{p['zotero_key']}"].add(cite)
print(f"work {works}｜來源 {len(claims)}｜被 ≥2 筆宣稱 {sum(len(v)>=2 for v in claims.values())}｜最大宣稱者數 {max((len(v) for v in claims.values()), default=0)}｜讀不到的檔 {bad}")
PY
# 2026-09-29：work 2572｜來源 535｜被 ≥2 筆宣稱 0｜最大宣稱者數 1｜讀不到的檔 0
```

**第 69 列的量測（2026-09-29，可重跑，唯讀）**：第 43 列的量測腳本已涵蓋（名字段數、帶時間、帶 source、帶 note）；另數 `attested` 的最多點數：

```bash
python3 - <<'PY'
import glob, io, os, yaml
mx = bad = 0
for f in glob.glob(os.path.expanduser('~/.akashic/entities') + '/*.yaml'):
    try: d = yaml.safe_load(io.open(f, encoding='utf8'))
    except Exception: bad += 1; continue
    if not isinstance(d, dict) or 'venue' not in d: continue
    for x in d.get('names') or []:
        if isinstance(x, dict) and isinstance(x.get('attested'), list): mx = max(mx, len(x['attested']))
print(f"attested 最多 {mx} 點｜讀不到的檔 {bad}")
PY
# 2026-09-29：attested 最多 0 點｜讀不到的檔 0
```

**第 70 列的量測（2026-09-30，可重跑）**：宣告範圍每條宣告印一行，`✓` 是沒有缺口、`✗` 是未列管的缺口、`⊘` 是列管的缺口；清單條目數不含註解與空行。三條分支、格式閘的每個條件與兩個判斷的負控是 `.build/debug/akashic-guards trigger-coverage-mutations`（2026-09-30 R2：49/49）。**`✗⊘` 的 0 要配正對照一起讀**（R2 verify）：#690 之前的 binary 沒有範圍檢查、守衛中途以 rc=2 中止，`grep -c` 都印 0，與「沒有缺口」分不出來——所以先看 rc 與 `✓` 行數，`✓` 是 0 時下一行的 0 不算數。

```bash
out=$(.build/debug/akashic-guards trigger-coverage); echo "rc=$?"           # 2026-09-30：rc=0
printf '%s\n' "$out" | grep -cE '^✓ .*宣告 `'     # 正對照，2026-09-30：3（0＝這個 binary 沒有範圍檢查，或中途中止）
printf '%s\n' "$out" | grep -cE '^[✗⊘] .*宣告 `'  # 2026-09-30：0
grep -cvE '^#|^$' .githooks/acknowledged-ci-gaps.txt                    # 2026-09-30：0
```

**第 71 列的量測（2026-09-30，可重跑）**：兩個出口的訊息數。先確認這個 binary 有這兩條檢查（找不到就是 #689 R1 之前的 binary，下面的 0 不算數；`LC_ALL=C` 不能省——macOS 的 `/usr/bin/grep` 在 UTF-8 locale 下對 binary 檔比不到中文字串，2026-09-30 實測同一個 binary 印 0 與 3），
再看正對照：對應表每支有負控的守衛一行（`·` 開頭），是 0 表示守衛中途中止。負控是 `.build/debug/akashic-guards audit-guards-mutations` 裡 `migrated：` 開頭的格子
（2026-09-30 R2：整支 75/75）。

```bash
LC_ALL=C grep -a -q '抽取認不出' .build/debug/akashic-guards && LC_ALL=C grep -a -q '宣告是空的' .build/debug/akashic-guards && echo "有這兩條檢查"
out=$(.build/debug/akashic-guards migrated-guard-control); echo "rc=$?"   # 2026-09-30：rc=0
printf '%s\n' "$out" | grep -cE '^  · `'    # 正對照，2026-09-30：18
printf '%s\n' "$out" | grep -c '宣告是空的'   # 2026-09-30：0
printf '%s\n' "$out" | grep -c '抽取認不出'   # 2026-09-30：0
```

**第 72 列的量測（2026-09-30，可重跑，唯讀）**：量的是檔案大小（不是 `du` 的磁碟用量），不讀內容；symlink 不算。

```bash
python3 - <<'PY'
import os
CAP = 268_435_456   # LibraryStore.maxSourceBytes
for label, root in [('Zotero storage', '~/Zotero/storage'),
                     ('sources/', os.path.join(os.environ.get('AKASHIC_HOME', '~/.akashic'), 'sources'))]:
    root = os.path.expanduser(root)
    if not os.path.isdir(root): print(f'{label}：讀不到 {root}——沒有量'); continue
    n = tot = mx = over = 0
    for dp, _, fns in os.walk(root):
        for f in fns:
            p = os.path.join(dp, f)
            if os.path.islink(p) or not os.path.isfile(p): continue
            s = os.path.getsize(p); n += 1; tot += s; mx = max(mx, s); over += s > CAP
    print(f'{label}：檔 {n}｜合計 {tot} bytes｜最大 {mx} bytes｜超過上限 {over}')
PY
# 2026-09-30：Zotero storage：檔 2817｜合計 61047841 bytes｜最大 5499190 bytes｜超過上限 0
#             sources/：檔 104｜合計 19820273 bytes｜最大 3912063 bytes｜超過上限 0
```

**第 73 列的量測（2026-09-30，可重跑，唯讀）**：`find "${AKASHIC_HOME:-$HOME/.akashic}/sources" -mindepth 2 -maxdepth 2 -name '.*.incoming-*' | wc -l`（2026-09-30：0）。自證：用含這條檢查的 binary，`akashic doctor 2>&1 | grep -c '殘留的暫存檔'` 對上面那個數（至多 20 行，其餘一句概括）；舊 binary 印不出任何一行——「沒被檢查」與「檢查過且乾淨」在輸出上分不開，第 13 列的同一條。

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
- 第 29 列的理由是**另一個守衛的正確性依賴它**——第 16 列是裁決依賴守衛（門檻到了才重開），這一列是等價性證明的前提（sink 上限 ≤ ceiling）由它守；零是兩個數字今天恰好對齊，改任一邊都是一行 diff 而每個 sink 自己的測試都不會紅。地板要分族，否則一族的零命中被另一族撐成通過（R31 verify 第 6 列）
- 第 28 列的理由是**可達性是本 change 的另一條裁決刻意造出來的**——第 23 列是新面讓不可達變可達；這一列是為了不刪判定（D62）而選擇留下一個狀態，守衛是那個選擇的另一半：留著而看不見，等於把刪除延後到合併、把回報搬到另一個命令
- 第 30 列的理由是**被守的記錄不退役**——第 18 列守的是一次遞進來的字串，這一列守的記錄只增不減，所以上限只擋得住單次呼叫，累積要另一盞燈（venue 側是第 16 列、person 與 organization 側是第 31 列）
- 第 32 列的理由是**前件寫寬的方向是放行**——第 2 列怕寬了誤傷，這一列寬了會放行一個看起來是決定性證據的假號；修在共用的謂詞，而且換成必定失敗的字元而不是濾掉
- 第 33 列的理由是**同一個檢查只寫了三分之一**——跡象不是住錯地方（第 13 列），是根本不存在，而同形的檢查就在隔壁；補的是既有守衛的前件，不是新守衛
- 第 34 列的理由是**補完只補了一側**——第 33 列照 work 的欄位窮舉，指向同一個目標（organization）而住在別的形狀上的兩條邊沒被看到；窮舉的軸要是「指向誰」，不只是「住在誰身上」
- 第 35 列的理由是**同一個取捨在另一類欄位上開的格**——第 28 列照判定記錄那一格，位元組相等的去重在非判定 reference 上收下的變體沒有燈
- 第 36 列的理由是**假號的來源是合法的號掛錯地方**——第 4 列是猜錯的結果看起來對、第 32 列是謂詞寬到放行假號；這一列的號本身合法，錯在它屬於哪本刊，只有跨記錄比對看得到，且守衛要與移除面同批，否則 warning 沒有工具面的出口
- 第 37 列的理由是**舊謂詞對新形狀結構上不可能為真，而正確的謂詞不存在**——第 21 列換一個謂詞就好；這一列換不了，因為「該不該閘」是裁決不是性質，所以守衛只要求每一格都有裁決並寫出自己的理由（第 7 列的形：通過不代表理由對）
- 第 38 列的理由是**錯在標題不在內容**——第 4 列是猜錯的結果看起來對；這一列聯集裡的每一則都是真的，錯的是「這一筆」這個標題，而讀的人正是為了那個標題才指名。守的是讀取面的定址，不是 store 的內容
- 第 40 列的理由是**拒絕問在錯的時間點**——第 21 列是謂詞問了那一類成員答不錯的問題、第 13 列是跡象住在錯的地方；這一列的謂詞答得對、跡象也在，錯在答案到達時寫入已經進行到一半。修法是同一組判斷換一個時間點再問一次，不是寫第二份判斷
- 第 41 列的理由是**同一個值在兩層有相反的身分**——第 32 列放行的是形狀看起來對的假號；這一列的值形狀本來就對，錯在它不指認任何東西。閘在共用謂詞，而且要把謂詞拆成位址與引用兩個——否則為了守零實例而加的收緊會把 live store 的 `store-source` 關掉
- 第 42 列的理由是**沒有檢查的那一格讓讀取端崩潰**——第 33 列的缺口是少報，這一列的缺口是 trap；重複 key 的檢查補在 `crossRecordIssues`，查找表改成不 trap，以 key 定位寫入的面拒絕
- 第 43 列的理由是**合併是拿掉沿革的那一步**——第 22 列替沿革留位置，這一列守位置的另一端：落進去的東西不得在合併時安靜消失，而哪一段的時間對是判斷，合併不猜
- 第 44 列的理由是**既有判準的答案變了**——閘不是新的裁決，是遷移退場之後「有沒有 pre-bump 遷移」從有變成沒有
- 第 45 列的理由是**上限只擋單次**——同第 30 列，錨點取既有常數；累積由第 16 列出聲
- 第 46 列的理由是**路由字典安靜地選一筆**——隔壁的重複有檢查、宣稱者的重複沒有，匯入時把欄位寫進別的記錄
- 第 47 列的理由是**零來自規則還不存在**——第 13 列的零是清理過之後的零；這一列的形狀發生過一次（52 筆），今天的零是因為 live store 的 library 都還沒標性質。燈照的是寫入閘擋不到的三個來源（舊 binary、手改、set-kind 當下就不符的既有成員），同第 26 列閘與守衛的分工
- 第 48 列的理由是**新開的通道讓偽裝可達**——同第 4 列，角色掉了之後記錄看起來健康；可達性是 #587 的寫入面造成的（第 23 列的形），所以閘與新面同批，而 reference 那一半改成搬而不是拒絕
- 第 49 列的理由是**合法狀態的可見性**——前面各列的零是壞形狀還沒發生；這一列的形狀是合法的，缺的是能看見它的判準，而判準只有一份
- 第 50 列的理由是**「在不在」不等於「是不是一份檔」**——同第 1 列不寫就沒有跡象；與第 15 列相鄰：那一列問位元組在不在這台機器上，這一列問那個位置上是不是一份檔
- 第 51 列的理由是**移植會換掉意外的紅燈**——同第 3 列未涵蓋不得冒充通過；舊實作的紅是 glob 的副作用，換語言時要寫成顯式判定
- 第 52 列的理由是**進度量測不得往終局偏**——普查的數字就是 literal 歸零的進度，少算一個檔等於假進步，所以整次拒絕輸出
- 第 53 列的理由是**同一個依據兩個時間點給相反的答案**——設定時擋、使用時放，是第 26 列那條不變式只剩一半；排除清單懸空則讓同一份程式對「是不是參照」答兩種
- 第 54 列的理由是**守衛的出路要走得通**——一律拒絕而出路是死路的守衛等於沒有出路；改名本來就該遷移指向舊 key 的邊，三個前置拒絕擋住遷移本身的安靜錯誤
- 第 55 列的理由是**判準已經有了，只是沒套到這種檔**——同第 44 列既有判準的答案變了；registry 檔不在 `entities/`，移除面一族的可回溯要求原本照不到它
- 第 56 列的理由是**守著它的閘只擋一條路**——同第 4 列，對不回的來源讓再匯入安靜地造出攣生；合併閘管不到手改與舊檔
- 第 57 列的理由是**讀回後核對身分**——同第 4 列，別筆的回應看起來是對的；那個形狀在頁內 fetch 已經發生過，這裡把紀律落實成程式
- 第 58 列的理由是**半套的數字不得冒充全部**——同第 3 列，缺記錄時預設不出數字
- 第 59 列的理由是**形狀取決於還沒出現的用途**——同第 10 列，ordinal 與「全收成一筆」語意不同，先具名拒絕是可逆的
- 第 60 列的理由是**上限沒有量測依據、也不是位元組界線**——同第 18 列的出口與入口，差別在錨點：25 是選的數字；首版拿各字串的字元上限相加當位元組的算術並不成立（b13f R1 verify）
- 第 61 列的理由是**理由只有一份，所以只截第三方內容**——同第 60 列上限是選的數字；差別在逐筆帶理由，截整筆就等於丟理由
- 第 62 列的理由是**失敗看起來像成功**——第 1 列的不可見性再加一層：命令回報成功，被刪的是使用者原本就有的資料
- 第 63 列的理由是**答不出來被讀成否**——第 3 列同形，而閘是隱私閘，外流進 remote 不可逆
- 第 64 列的理由是**解析成功而值不是來源的意思**——第 4 列的偽裝性落在解析層，兩個實作對同一份輸入安靜地分岔
- 第 65 列的理由是**第五份推導不會有跡象**——第 13 列同形，四份併成一份之後由源碼掃描守單一路徑
- 第 66 列的理由是**秘密一進 git 就收不回來**——第 18 列的入口守衛，對象是 url 裡的帳密
- 第 67 列的理由是**沒有讀者就沒有漂移的受害者**——第 10 列同形的「不做」，觸發條件是第一個讀者
- 第 68 列的理由是**清單由一次匯入一步跨過**——同第 18、30 列，上限保護的是 LLM context
- 第 69 列的理由是**第一個寫得進沿革位置的面**——同第 45 列的單次上限；第 22 列保留位置、第 43 列守合併，這一列守寫入
- 第 70 列的理由是**清空它的是一次計費裁決**——第 13 列同形的「清理過之後的零」；機制留著是因為成本決定可以翻，而它留著的那條路要自己有負控（清單因此是資料檔）
- 第 71 列的理由是**偵測不得與它要補的抽取共用失敗條件**——第 21 列換一個謂詞就好；這一列補的是另一支守衛的輸入，補丁若與原抽取共用 regex，漏掉的寫法兩邊一起漏，零實例量到的只是「看不到」
- 第 72 列的理由是**上限是一次裁決給的數字**——第 18 列的上限夾在兩個量測錨點之間，這一列只有一個錨點（最大單檔的 48.8 倍）；批次入口逐檔略過而不整批拒絕，因為那個入口的其他「這個檔不能收」本來就逐檔具名
- 第 73 列的理由是**殘留與進行中長得一樣**——第 15 列的零是本機的、第 23 列的可達路徑是本 change 自己開的；這一列的東西是工具自己的失敗路徑必然留下的，而它與正在進行的存檔在磁碟上分不開，所以守衛只報不刪
- 第 31 列的理由是**同一條曲線換了持有者**——第 16 列的燈只照 venue；新面（未決腿）讓 person 與 organization 也開始累積，第 30 列寫下的誠實邊界要有工具面兌現，否則就是一句沒有後續的散文
- 第 39 列的理由是**單步的跳躍預警看不到**——第 16／31 列的燈在讀取面、照的是漸進的增長；一次寫入從門檻之下直接越過讀取上限時，燈來不及響，擋它的只能是寫入端。而那道閘要擋的不只是位元組：多檔寫入面在它觸發之前已有檔落盤，所以閘與零寫入的 preflight 同批
- 第 24 列的理由是**半吊子已經誠實**——前二十三列裡只有第 22 列同樣是「不動既有的東西」（比的是裁決的**動作**：那一列的對象是 spec 文字、失敗是被當死重刪掉；本列的對象是程式的半吊子管線、失敗是使用者撞牆或被當成待修殘留而被人動手）。留著的代價不是零（記了就刪不掉——#586 在 2026-09-28 補了移除面，代價從「刪不掉」降為「要人判定放棄」），而是今天未兌現、且一出現就會出聲；動它的兩個方向（實作／拿掉）代價都更高。與第 10 列（缺用途）最像的是理由的**形**：實作那一半同樣是「形狀取決於還不存在的用途」；但第 10 列的對象根本不存在，這一列的對象已經在、且已經誠實

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
  長出來（往外長）。同一個生命週期軸的兩端，方向相反——第 4 類（既有的半吊子路徑）是例外，它裁的是
  既有物動不動，理由在前言
- `lossless-intake`：第 3 列的理由直接引用它的「靜默是最糟的形式」
- 全域 `common-spec-prose-enumeration`：本檔的形狀（封閉表、無總括判準、理由與裁決同列）
  是它的執行細節 1 與 3 的落地
