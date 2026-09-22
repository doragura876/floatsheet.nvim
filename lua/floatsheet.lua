-- --------------------------------------------------
-- floatsheet
--   覚えたいキーバインド等を1つのmarkdownに書いておき、右下の小さなフロートに
--   出しっぱなしにするユーティリティ。フォーカスは動かず、フロートを出した
--   まま今まで開いていた画面を操作できる。
--
--   【ページの定義】
--     1ファイルの中で、H1見出し(`# ` )がページの区切り。次のH1までが1ページ。
--     コードブロック内の `# ` は区切りとして扱わない。見出し行は本文に出さず、
--     最初の見出しより前の行は無視する。
--
--       # 1:Neogit        <- 先頭が「英数1文字 + :」なら、その1文字がページ移動キー
--       - ...
--       # A:Overlook
--       - ...
--       # キーなしページ   <- タブと next/prev では移動できる
--
--   【設定】(init.lua)
--     require('floatsheet').setup{
--       file = "~/xxx/floatsheet.md",  -- 既定: stdpath("config") .. "/floatsheet.md"
--       jump_prefix = "<Leader>?",     -- 未指定ならページ移動キーは登録しない
--     }
--
--   【API】
--     toggle()    表示/非表示
--     next() / prev()   ページ移動(循環。非表示なら開いてから移動)
--     jump(key)   ページ名の先頭キーで移動(jump_prefixのkeymapから呼ばれる)
--     edit()      現在ページの見出し行にカーソルを合わせてmdを分割で開く
--
--   ページ名のキーにn/p/eは使えない(next/prev/editのkeymapと衝突するため)。
--   mdの保存(BufWritePost)で自動的に読み直す。それ以外の変更は、次に
--   トグル/移動したときに反映される。
-- --------------------------------------------------
local M = {}

local cfg = {
  file = vim.fn.stdpath("config") .. "/floatsheet.md",
  width = 80,
  height = 30, -- 本文の最大行数。超えた分は切り詰めて末尾行を「…」にする(画面に収まらなければさらに縮む)
  jump_prefix = nil,
}

local RESERVED_KEYS = { n = true, p = true, e = true }

local state = {
  idx = 1,
  visible = false,
  buf = nil,
  wins = {}, -- tabpage handle -> win。フロートはタブごとに必要
  pages = {}, -- { label=, key=, lnum=, lines={} }
  maps = {}, -- 登録済みのページ移動keymap(lhs)
}

local function file_path()
  local f = vim.fn.expand(cfg.file)
  if f:sub(1, 1) ~= "/" then f = vim.fn.stdpath("config") .. "/" .. f end
  return f
end

local function define_hl()
  vim.api.nvim_set_hl(0, "FloatsheetTab", { link = "TabLine", default = true })
  vim.api.nvim_set_hl(0, "FloatsheetTabActive", { link = "TabLineSel", default = true })
end

-- H1見出しでページに分割する。コードブロック内の `# ` は区切りにしない
local function parse(path)
  local pages = {}
  if vim.fn.filereadable(path) == 0 then return pages end
  local fence, cur
  for lnum, line in ipairs(vim.fn.readfile(path)) do
    local mark = line:match("^%s*(```+)") or line:match("^%s*(~~~+)")
    if mark then
      if not fence then
        fence = mark
      elseif mark:sub(1, 1) == fence:sub(1, 1) and #mark >= #fence then
        fence = nil
      end
    end
    local title = (not fence and not mark) and line:match("^#%s+(.-)%s*$") or nil
    if title and title ~= "" then
      cur = { label = title, key = title:match("^([A-Za-z0-9]):"), lnum = lnum, lines = {} }
      pages[#pages + 1] = cur
    elseif cur then
      cur.lines[#cur.lines + 1] = line
    end
  end
  for _, page in ipairs(pages) do
    while #page.lines > 0 and page.lines[#page.lines]:match("^%s*$") do
      page.lines[#page.lines] = nil
    end
  end
  return pages
end

local function clear_maps()
  for _, lhs in ipairs(state.maps) do pcall(vim.keymap.del, "n", lhs) end
  state.maps = {}
end

-- jump_prefix .. key にページ移動のkeymapを登録し直す。衝突したキーは警告してスキップする
local function register_maps(notify)
  clear_maps()
  if not cfg.jump_prefix then return end
  local seen = {}
  for _, page in ipairs(state.pages) do
    local key = page.key
    if key then
      if RESERVED_KEYS[key] then
        if notify then
          vim.notify(("floatsheet: '%s' は予約キーのため移動キーにできません (%s)"):format(key, page.label), vim.log.levels.WARN)
        end
      elseif seen[key] then
        if notify then
          vim.notify(("floatsheet: キー '%s' が重複しています。先のページを優先します (%s)"):format(key, page.label), vim.log.levels.WARN)
        end
      else
        seen[key] = true
        local lhs = cfg.jump_prefix .. key
        vim.keymap.set("n", lhs, function() M.jump(key) end,
          { noremap = true, silent = true, desc = "floatsheet: " .. page.label })
        state.maps[#state.maps + 1] = lhs
      end
    end
  end
end

-- mdを読み直してページ一覧とkeymapを更新する。表示中のページは見出し名で追従する
local function reload(notify)
  local cur = state.pages[state.idx] and state.pages[state.idx].label
  state.pages = parse(file_path())
  state.idx = 1
  for i, page in ipairs(state.pages) do
    if page.label == cur then state.idx = i break end
  end
  register_maps(notify)
end

-- 本文の最大行数。画面(cmdline・ステータスライン・枠2行)に収まる範囲に丸める
local function max_height()
  local status = vim.o.laststatus == 0 and 0 or 1
  local room = vim.o.lines - vim.o.cmdheight - status - 2
  return math.max(1, math.min(cfg.height, room))
end

local function win_width()
  return math.max(20, math.min(cfg.width, vim.o.columns - 4))
end

local function page_lines(page, maxh)
  local lines = page.lines
  if #lines == 0 then return { "(空のページです)" } end
  if #lines > maxh then
    lines = vim.list_slice(lines, 1, maxh)
    lines[maxh] = "…"
  end
  return lines
end

-- 上枠に全ページのタブを並べる。収まらないときは現在のページ以外をキーだけ(無ければ番号)に縮める
local function tab_title(width)
  local function build(compact)
    local chunks, total = {}, 0
    for i, page in ipairs(state.pages) do
      local active = i == state.idx
      local text = (compact and not active) and (page.key or tostring(i)) or page.label
      text = " " .. text .. " "
      chunks[#chunks + 1] = { text, active and "FloatsheetTabActive" or "FloatsheetTab" }
      total = total + vim.fn.strdisplaywidth(text)
    end
    return chunks, total
  end
  local chunks, total = build(false)
  if total > width - 2 then chunks = build(true) end
  return chunks
end

local function ensure_buf()
  if state.buf and vim.api.nvim_buf_is_valid(state.buf) then return state.buf end
  local buf = vim.api.nvim_create_buf(false, true)
  vim.bo[buf].bufhidden = "hide"
  vim.bo[buf].swapfile = false
  -- FileType autocmd(LSP・折りたたみ等)を走らせないためnoautocmdで設定する
  vim.api.nvim_buf_call(buf, function() vim.cmd("noautocmd setlocal filetype=markdown") end)
  pcall(vim.treesitter.start, buf, "markdown")
  state.buf = buf
  return buf
end

-- markview.nvimの装飾を効かせる。既定のhybrid_modes(カーソル下だけ生表示)は
-- フロートのカーソル位置(1行目)が生のまま残るため、このバッファだけ切る
local function decorate(buf)
  local ok, mv = pcall(require, "markview")
  if not ok then return end
  pcall(mv.actions.attach, buf, { enable = true, hybrid_mode = false })
  pcall(mv.actions.render, buf)
end

local function win_config(height)
  local width = win_width()
  local status = vim.o.laststatus == 0 and 0 or 1
  return {
    relative = "editor",
    anchor = "SE",
    row = vim.o.lines - vim.o.cmdheight - status,
    col = vim.o.columns,
    width = width,
    height = height,
    style = "minimal",
    border = "rounded",
    title = tab_title(width),
    title_pos = "left",
    focusable = false,
    zindex = 20, -- 既定(50)より下に置き、補完などのポップアップの邪魔をしない
  }
end

local function set_lines(buf, lines)
  vim.bo[buf].modifiable = true
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].modifiable = false
end

local function close_all()
  for tab, win in pairs(state.wins) do
    if vim.api.nvim_win_is_valid(win) then pcall(vim.api.nvim_win_close, win, true) end
    state.wins[tab] = nil
  end
end

local function render()
  local n = #state.pages
  if n == 0 then
    vim.notify("floatsheet: ページがありません。'# 名前' の見出しを書いてください: " .. file_path(), vim.log.levels.WARN)
    state.visible = false
    close_all()
    return
  end
  state.idx = ((state.idx - 1) % n) + 1
  local lines = page_lines(state.pages[state.idx], max_height())
  local buf = ensure_buf()
  set_lines(buf, lines)

  local conf = win_config(#lines)
  local tab = vim.api.nvim_get_current_tabpage()
  local win = state.wins[tab]
  if win and vim.api.nvim_win_is_valid(win) then
    vim.api.nvim_win_set_config(win, conf)
  else
    conf.noautocmd = true
    win = vim.api.nvim_open_win(buf, false, conf)
    state.wins[tab] = win
    vim.wo[win].wrap = false
    vim.wo[win].conceallevel = 2
    vim.wo[win].winfixbuf = true
  end
  decorate(buf)
end

function M.toggle()
  if state.visible then
    state.visible = false
    close_all()
  else
    reload(false)
    state.visible = true
    render()
  end
end

local function move(delta)
  reload(false)
  state.idx = state.idx + delta
  state.visible = true
  render()
end

function M.next() move(1) end
function M.prev() move(-1) end

function M.jump(key)
  reload(false)
  for i, page in ipairs(state.pages) do
    if page.key == key then
      state.idx = i
      state.visible = true
      render()
      return
    end
  end
end

function M.edit()
  local path = file_path()
  local page = state.pages[state.idx]
  vim.fn.mkdir(vim.fn.fnamemodify(path, ":h"), "p")
  vim.cmd("split " .. vim.fn.fnameescape(path))
  if page then
    pcall(vim.api.nvim_win_set_cursor, 0, { page.lnum, 0 })
    vim.cmd("normal! zt")
  end
end

function M.setup(opts)
  cfg = vim.tbl_extend("force", cfg, opts or {})
  define_hl()
  reload(true)
  local group = vim.api.nvim_create_augroup("floatsheet", { clear = true })
  -- カラースキーム変更でハイライトが消えるため、タブのリンクを張り直す
  vim.api.nvim_create_autocmd("ColorScheme", { group = group, callback = define_hl })
  -- mdの保存でページ名・移動キー・表示を更新する(シンボリックリンク経由でも同一ファイルなら反応)
  vim.api.nvim_create_autocmd("BufWritePost", {
    group = group,
    callback = function(args)
      local a, b = vim.uv.fs_realpath(args.file), vim.uv.fs_realpath(file_path())
      if not a or a ~= b then return end
      reload(true)
      if state.visible then render() end
    end,
  })
  -- 画面サイズが変わったら右下に寄せ直す
  vim.api.nvim_create_autocmd("VimResized", {
    group = group,
    callback = function()
      if state.visible then render() end
    end,
  })
  -- 表示状態はタブをまたいで共有する(フロートはタブごとに作り直す)
  vim.api.nvim_create_autocmd("TabEnter", {
    group = group,
    callback = function()
      if state.visible then vim.schedule(render) end
    end,
  })
  -- タブを閉じたら、そのタブのフロートの記録を捨てる
  vim.api.nvim_create_autocmd("TabClosed", {
    group = group,
    callback = function()
      for tab in pairs(state.wins) do
        if not vim.api.nvim_tabpage_is_valid(tab) then state.wins[tab] = nil end
      end
    end,
  })
end

return M
