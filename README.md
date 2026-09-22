# floatsheet.nvim

覚えたいキーバインドなどを 1 つの markdown ファイルに書いておき、画面の右下に小さな
フロートで出しっぱなしにできる、Neovim 用のチートシートプラグインです。

フロートは**フォーカスを奪いません**。表示したまま、今まで開いていたウィンドウで
そのまま操作を続けられます。追加したばかりのプラグインのキーを覚えたいときに便利です。

```
 ┌ 編集中の画面 ───────────────────────────────┐
 │                                             │
 │      ╭ 1:Neogit  A:Overlook  B:Snippets ──╮ │
 │      │ - <Leader>gg  open                 │ │
 │      │ - c c         commit               │ │
 │      ╰────────────────────────────────────╯ │
 └─────────────────────────────────────────────┘
```

## 特徴

- 1 つの markdown ファイルの中に、複数のページを書けます (`# 見出し` がページの区切り)。
- 上の枠に全ページのタブを並べ、今のページだけ色を変えます。
- ページ名を `1:名前` / `A:名前` のように書くと、`<prefix>1` / `<prefix>A` でそのページへ直接移動できます。
- フォーカスを奪わないフロート。表示したまま編集でき、カーソルも動きません。
- ステータスラインの上、右下に表示。大きさはページの内容に合わせて縮みます。
  既定は最大 80 桁 x 30 行で、画面が小さければさらに縮みます。
- md を保存すると、ページ名・タブ・移動キー・表示をすぐ読み直します。
- 表示状態はタブページの移動やウィンドウサイズの変更にも追従します。
- 任意: [markview.nvim](https://github.com/OXY2DEV/markview.nvim) が入っていれば
  markdown を装飾して表示します。無ければ treesitter のハイライトのみです。

## 必要なもの

- Neovim **0.10 以上** (フロートの `footer`・`winfixbuf` と、タイトルのチャンク指定を使うため)。開発は 0.12 で行っています。
- 任意: markdown を装飾表示する [markview.nvim](https://github.com/OXY2DEV/markview.nvim)

## インストール

[lazy.nvim](https://github.com/folke/lazy.nvim) の例:

```lua
{
  "doragura876/floatsheet.nvim",
  opts = {
    file = "~/.config/nvim/floatsheet.md", -- 省略時も同じ場所
    jump_prefix = "<Leader>?",             -- ページ移動キーのプレフィックス
  },
  keys = {
    { "<Leader>??", function() require("floatsheet").toggle() end, desc = "floatsheet toggle" },
    { "<Leader>?n", function() require("floatsheet").next()   end, desc = "floatsheet next page" },
    { "<Leader>?p", function() require("floatsheet").prev()   end, desc = "floatsheet prev page" },
    { "<Leader>?e", function() require("floatsheet").edit()   end, desc = "floatsheet edit page" },
  },
}
```

`jump_prefix` を指定すると、`<Leader>?1` のようなページ移動キーはプラグインが
自動で登録します (which-key にもページ名で出ます)。`toggle` / `next` / `prev` / `edit` の
キーは自分で割り当ててください。

## markdown の書き方

`# ` (H1) の見出しが 1 ページです。次の `# ` までが、そのページの本文になります。

```markdown
# 1:Neogit

- `<Leader>gg` Neogit を開く
- `c c` コミット
- `P p` プッシュ

# A:Overlook

- `<Leader>pd` 定義をフロートで覗く

# ページ名だけの例

- 先頭に `英数:` が無いページは、タブと next / prev で移動します
```

- **ページ名**: 見出しの文字列がそのままタブに表示されます。見出し行は本文には表示しません。
- **移動キー**: 見出しが「英数 1 文字 + `:`」で始まる場合だけ、その 1 文字が移動キーになります
  (`1:名前` → `<prefix>1`、`A:名前` → `<prefix>A`)。大文字と小文字は別のキーです。全角の `：` は対象外です。
- **予約キー**: `n` `p` `e` は next / prev / edit と衝突するため使えません (警告してスキップします)。
  キーが重複した場合は、先に書いたページを優先し、警告します。
- **コードブロック**: ` ``` ` や `~~~` の中の `# ` は、ページの区切りとして扱いません。
- **最初の見出しより前**の行は無視します。
- **本文の先頭の空行はそのまま表示します** (末尾の空行は取り除きます)。

## 設定

```lua
require("floatsheet").setup({
  file = vim.fn.stdpath("config") .. "/floatsheet.md",
  width = 80,        -- ウィンドウ幅の上限 (画面が狭ければ縮みます)
  height = 30,       -- 本文の最大行数 (画面に収まらなければさらに縮みます)
  jump_prefix = nil, -- 例: "<Leader>?"。未指定ならページ移動キーは登録しません
})
```

| オプション    | 既定値                                   | 説明 |
|---------------|------------------------------------------|------|
| `file`        | `stdpath("config") .. "/floatsheet.md"`  | ページを書いた markdown ファイル。`~` が使えます。相対パスは `stdpath("config")` からの相対です。 |
| `width`       | `80`                                     | ウィンドウ幅の上限。 |
| `height`      | `30`                                     | 本文の最大行数。超えた分は切り詰め、最後の行を `…` にします。 |
| `jump_prefix` | `nil`                                    | ページ移動キーのプレフィックス。`jump_prefix .. 1文字` にキーを登録します。 |

## API

| 関数                             | 説明 |
|----------------------------------|------|
| `require("floatsheet").toggle()` | 表示 / 非表示を切り替えます。 |
| `require("floatsheet").next()`   | 次のページへ (末尾からは先頭へ循環)。非表示なら開いてから移動します。 |
| `require("floatsheet").prev()`   | 前のページへ (先頭からは末尾へ循環)。非表示なら開いてから移動します。 |
| `require("floatsheet").jump(key)`| ページ名の先頭キーで移動します。`jump_prefix` のキーから呼ばれます。 |
| `require("floatsheet").edit()`   | 現在のページの見出し行にカーソルを合わせて、md を水平分割で開きます。 |

## ハイライト

タブの色は、次のハイライトグループで変更できます。既定では `TabLine` / `TabLineSel` にリンクします。

| グループ              | 用途 |
|-----------------------|------|
| `FloatsheetTab`       | 現在ではないページのタブ |
| `FloatsheetTabActive` | 現在のページのタブ |

## 注意点

- 上の枠に収まらないほどタブが多い場合は、現在のページ以外を「移動キーだけ (キーが無ければ番号)」に縮めて表示します。
- md は、`toggle` / `next` / `prev` / `jump` のたびにも読み直します。表示中に別のエディタで
  変更した場合は、次にそれらを実行するまで反映されません (nvim での保存は即時に反映されます)。
- markview.nvim を使う場合、markdown の表の前後には空行を入れてください。
  markview は表の罫線をその空行を使って描画します。
- フロートの `zindex` は 20 です。通常のフロート (既定 50) より下にあるため、
  補完メニューなどのポップアップはこの上に表示されます。

## ライセンス

[MIT](./LICENSE)
