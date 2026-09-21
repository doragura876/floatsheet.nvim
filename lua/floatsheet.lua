-- --------------------------------------------------
-- floatsheet
--   覚えたいキーバインド等をmarkdownで書いておき、右下の小さなフロートに
--   出しっぱなしにするユーティリティ。フォーカスは動かず、フロートを出した
--   まま今まで開いていた画面を操作できる。
--
--   【ページの定義】(init.lua)
--     require('floatsheet').setup{
--       pages = {
--         { name = "neogit", file = "neogit.md" },  -- fileはdir(既定: floatsheet/)からの相対
--       },
--     }
--
--   【API】
--     toggle()   表示/非表示
--     next() / prev()   ページ移動(循環。非表示なら開いてから移動)
--     edit()     現在ページのmdを分割で開く
--
--   表示は毎回ファイルを読み直すが、表示中に別窓で保存しても、次に
--   移動/トグルするまでは古い表示のまま。
-- --------------------------------------------------
local M = {}

local cfg = {
  pages = {},
  dir = vim.fn.stdpath("config") .. "/floatsheet",
  width = 80,
  height = 10, -- 本文の最大行数。超えた分は切り詰めて末尾行を「…」にする
}

local state = {
  idx = 1,
  visible = false,
  buf = nil,
  wins = {}, -- tabpage handle -> win。フロートはタブごとに必要
}

local function page_path(page)
  local f = vim.fn.expand(page.file)
  if f:sub(1, 1) == "/" then return f end
  return cfg.dir .. "/" .. f
end

-- 表示用の行を返す(最大cfg.height行)
local function page_lines(page)
  local path = page_path(page)
  if vim.fn.filereadable(path) == 0 then
    return { "(ファイルが見つかりません)", path }
  end
  local lines = vim.fn.readfile(path)
  if #lines == 0 then return { "(空のページです)" } end
  if #lines > cfg.height then
    lines = vim.list_slice(lines, 1, cfg.height)
    lines[cfg.height] = "…"
  end
  return lines
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

local function win_config(height, title, footer)
  local width = math.max(20, math.min(cfg.width, vim.o.columns - 4))
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
    title = " " .. title .. " ",
    title_pos = "center",
    footer = " " .. footer .. " ",
    footer_pos = "center",
    focusable = false,
    zindex = 20, -- 既定(50)より下に置き、補完などのポップアップの邪魔をしない
  }
end

local function set_lines(buf, lines)
  vim.bo[buf].modifiable = true
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].modifiable = false
end

local function render()
  local n = #cfg.pages
  if n == 0 then
    vim.notify("floatsheet: pagesが未定義です", vim.log.levels.WARN)
    state.visible = false
    return
  end
  state.idx = ((state.idx - 1) % n) + 1
  local page = cfg.pages[state.idx]
  local lines = page_lines(page)
  local buf = ensure_buf()
  set_lines(buf, lines)

  local conf = win_config(#lines, page.name, ("%d/%d"):format(state.idx, n))
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

local function close_all()
  for tab, win in pairs(state.wins) do
    if vim.api.nvim_win_is_valid(win) then pcall(vim.api.nvim_win_close, win, true) end
    state.wins[tab] = nil
  end
end

function M.toggle()
  if state.visible then
    state.visible = false
    close_all()
  else
    state.visible = true
    render()
  end
end

local function move(delta)
  state.idx = state.idx + delta
  state.visible = true
  render()
end

function M.next() move(1) end
function M.prev() move(-1) end

function M.edit()
  local page = cfg.pages[state.idx]
  if not page then return end
  local path = page_path(page)
  vim.fn.mkdir(vim.fn.fnamemodify(path, ":h"), "p")
  vim.cmd("split " .. vim.fn.fnameescape(path))
end

function M.setup(opts)
  cfg = vim.tbl_extend("force", cfg, opts or {})
  local group = vim.api.nvim_create_augroup("floatsheet", { clear = true })
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
