# libyaml（vendored，#36 / #27）

來源：Yams 的 `Sources/CYaml`（MIT，Copyright (c) 2016 JP Simard；libyaml 本身
Copyright (c) 2006-2016 Kirill Simonov，同 MIT）。

## 為什麼 vendor 而不是用 Yams 的

**Yams 把 `CYaml` 宣告為 target 而非 product**，外部套件取不到。而 event-level 解析是
`#36` 排除清單裡**唯一剩下的方向**——五次文字層守衛全部失敗（見 `docs/store-format.md` §5
與 #36 的排除表）。

## 只帶 parser 面

`api.c` / `parser.c` / `reader.c` / `scanner.c` —— **不帶** `emitter.c` / `writer.c`。
輸出仍走 Yams（我們不需要第二個 emitter，而多一個就多一份要保持一致的行為）。

## 更新

libyaml 極少變動。要跟上 Yams 的版本時重跑：

    cp .build/checkouts/Yams/Sources/CYaml/src/{api,parser,reader,scanner}.c \
       .build/checkouts/Yams/Sources/CYaml/src/yaml_private.h Sources/CLibYAML/src/
    cp .build/checkouts/Yams/Sources/CYaml/include/yaml.h Sources/CLibYAML/include/
