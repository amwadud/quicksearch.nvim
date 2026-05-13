-- quicksearch.nvim
-- Floating search launcher — window style taken directly from ThePrimeagen/99

local M = {}

-- ─────────────────────────────────────────────
-- Config
-- ─────────────────────────────────────────────
M.config = {
  border = "rounded",
  title  = " 🔍 QuickSearch ",
  keymap = "<leader>s",
  engines = {
    { key = "g", label = "Google",        url = "https://www.google.com/search?q=" },
    { key = "d", label = "DuckDuckGo",    url = "https://duckduckgo.com/?q=" },
    { key = "y", label = "YouTube",       url = "https://www.youtube.com/results?search_query=" },
    { key = "r", label = "Reddit",        url = "https://www.reddit.com/search/?q=" },
    { key = "h", label = "HackerNews",    url = "https://hn.algolia.com/?q=" },
    { key = "n", label = "npm",           url = "https://www.npmjs.com/search?q=" },
    { key = "p", label = "PyPI",          url = "https://pypi.org/search/?q=" },
    { key = "m", label = "MDN",           url = "https://developer.mozilla.org/en-US/search?q=" },
    { key = "s", label = "StackOverflow", url = "https://stackoverflow.com/search?q=" },
    { key = "w", label = "Wikipedia",     url = "https://en.wikipedia.org/wiki/Special:Search?search=" },
    { key = "G", label = "GitHub",        url = "https://github.com/search?q=" },
  },
  open_cmd = nil,
}

-- ─────────────────────────────────────────────
-- Helpers
-- ─────────────────────────────────────────────

local function urlencode(str)
  str = str:gsub("\n", " ")
  str = str:gsub("([^%w%-%.%_%~ ])", function(c)
    return string.format("%%%02X", string.byte(c))
  end)
  return str:gsub(" ", "+")
end

local function detect_open_cmd()
  if M.config.open_cmd then return M.config.open_cmd end
  if vim.fn.has("mac") == 1 then return "open" end
  if vim.fn.has("win32") == 1 then return "start" end
  return "xdg-open"
end

local function open_url(url)
  vim.fn.jobstart({ detect_open_cmd(), url }, { detach = true })
  vim.notify("Opening: " .. url, vim.log.levels.INFO, { title = "QuickSearch" })
end

local function get_visual_selection()
  local s = vim.fn.getpos("'<")
  local e = vim.fn.getpos("'>")
  local lines = vim.fn.getregion(s, e, { type = vim.fn.visualmode() })
  return vim.fn.join(lines, " "):gsub("^%s+", ""):gsub("%s+$", "")
end

-- ─────────────────────────────────────────────
-- Geometry  (mirrors 99's get_ui_dimensions + create_centered_window)
-- ─────────────────────────────────────────────

local function get_ui_dimensions()
  -- 99 uses nvim_list_uis()[1] — the actual terminal dimensions,
  -- not vim.o.lines/columns which can differ with cmdheight etc.
  local ui = vim.api.nvim_list_uis()[1]
  return ui.width, ui.height
end

--- Returns the nvim_open_win config table for a centered floating window.
--- Matches 99's full_config() exactly: style="minimal", zindex=1 default,
--- relative="editor", anchor from config.
local function centered_config(width_frac, height_frac, title)
  local ui_w, ui_h = get_ui_dimensions()
  local win_w = math.floor(ui_w * width_frac)
  local win_h = math.floor(ui_h * height_frac)
  return {
    relative  = "editor",
    style     = "minimal",          -- 99 uses this in full_config()
    border    = M.config.border,
    title     = title,
    title_pos = "center",
    width     = win_w,
    height    = win_h,
    row       = math.floor((ui_h - win_h) / 2),
    col       = math.floor((ui_w - win_w) / 2),
    zindex    = 1,                  -- 99's default in full_config()
  }
end

-- ─────────────────────────────────────────────
-- Low-level window factory  (mirrors create_floating_window in 99)
-- ─────────────────────────────────────────────

local function create_floating_window(win_cfg, enter)
  local buf_id = vim.api.nvim_create_buf(false, true)
  local win_id = vim.api.nvim_open_win(buf_id, enter, win_cfg)
  vim.wo[win_id].wrap = true   -- 99 sets this immediately after open
  return win_id, buf_id
end

-- ─────────────────────────────────────────────
-- Engine picker  (read-only select window — capture_select_input style)
-- ─────────────────────────────────────────────

local function show_engine_picker(query)
  if not query or query == "" then return end

  local lines, max_label = {}, 0
  for _, e in ipairs(M.config.engines) do
    if #e.label > max_label then max_label = #e.label end
  end
  for _, e in ipairs(M.config.engines) do
    table.insert(lines, string.format("  [%s]  %s%s",
      e.key, string.rep(" ", max_label - #e.label), e.label))
  end

  local short = query:sub(1, 20) .. (query:len() > 20 and "…" or "")
  local cfg   = centered_config(1/3, #lines / get_ui_dimensions(), -- height exact
    string.format(' Search: "%s" ', short))
  -- override height to exact line count (not a fraction)
  local ui_w, ui_h = get_ui_dimensions()
  cfg.width  = max_label + 14
  cfg.height = #lines
  cfg.row    = math.floor((ui_h - cfg.height) / 2)
  cfg.col    = math.floor((ui_w - cfg.width)  / 2)

  local win_id, buf_id = create_floating_window(cfg, true)

  -- buf options — same as 99's select window: nofile, readonly after load
  vim.bo[buf_id].buftype   = "nofile"
  vim.bo[buf_id].bufhidden = "wipe"
  vim.bo[buf_id].swapfile  = false

  vim.api.nvim_buf_set_lines(buf_id, 0, -1, false, lines)
  vim.bo[buf_id].modifiable = false
  vim.bo[buf_id].readonly   = true

  vim.wo[win_id].cursorline = true

  -- syntax highlights
  vim.api.nvim_buf_call(buf_id, function()
    vim.cmd([[syntax match QSKey   /\[.\]/]])
    vim.cmd([[syntax match QSLabel /\]  \S.*/]])
  end)

  local close = function()
    if vim.api.nvim_win_is_valid(win_id) then
      vim.api.nvim_win_close(win_id, true)
    end
  end

  local bopts = { buffer = buf_id, nowait = true, noremap = true, silent = true }

  -- <CR> on cursor line  (mirrors capture_select_input's <CR> handler)
  vim.keymap.set("n", "<CR>", function()
    local idx = vim.api.nvim_win_get_cursor(win_id)[1]
    local e   = M.config.engines[idx]
    if e then close(); open_url(e.url .. urlencode(query)) end
  end, bopts)

  -- letter keys
  for i, e in ipairs(M.config.engines) do
    local url = e.url .. urlencode(query)
    vim.keymap.set("n", e.key, function() close(); open_url(url) end, bopts)
    if i <= 9 then
      vim.keymap.set("n", tostring(i), function() close(); open_url(url) end, bopts)
    end
  end

  vim.keymap.set("n", "q",     close, bopts)
  vim.keymap.set("n", "<Esc>", close, bopts)
end

-- ─────────────────────────────────────────────
-- Input window  — matches 99's capture_input() exactly:
--   • buftype = "acwrite"   → :w fires BufWriteCmd (the submit trigger)
--   • BufWriteCmd autocmd   → collects lines, calls callback
--   • BufLeave autocmd      → forces focus back (traps user in float)
--   • WinClosed autocmd     → cancel path
--   • q keymap              → cancel
-- ─────────────────────────────────────────────

function M.open(prefill)
  local cfg    = centered_config(2/3, 1/3, M.config.title)
  local win_id, buf_id = create_floating_window(cfg, true)

  -- 99's set_defaul_win_options()
  vim.api.nvim_buf_set_name(buf_id, "quicksearch-prompt")
  vim.wo[win_id].number         = true   -- 99 turns number ON in capture_input
  vim.bo[buf_id].filetype       = "quicksearch"
  vim.bo[buf_id].buftype        = "acwrite"   -- key: makes :w fire BufWriteCmd
  vim.bo[buf_id].bufhidden      = "wipe"
  vim.bo[buf_id].swapfile       = false

  -- Focus this window (mirrors nvim_set_current_win in capture_input)
  vim.api.nvim_set_current_win(win_id)

  -- Prefill
  if prefill and prefill ~= "" then
    vim.api.nvim_buf_set_lines(buf_id, 0, -1, false, { prefill })
    vim.api.nvim_win_set_cursor(win_id, { 1, #prefill })
  end

  vim.cmd("startinsert!")

  local group = vim.api.nvim_create_augroup(
    "quicksearch_prompt_" .. buf_id, { clear = true })

  local function do_close()
    if vim.api.nvim_win_is_valid(win_id) then
      vim.api.nvim_win_close(win_id, true)
    end
  end

  local function do_submit()
    local lines = vim.api.nvim_buf_get_lines(buf_id, 0, -1, false)
    local query = table.concat(lines, " "):gsub("^%s+", ""):gsub("%s+$", "")
    do_close()
    if query ~= "" then show_engine_picker(query) end
  end

  -- ── BufWriteCmd: fired by <CR> → :w  (99's submit path) ────────────
  vim.api.nvim_create_autocmd("BufWriteCmd", {
    group    = group,
    buffer   = buf_id,
    callback = function()
      if not vim.api.nvim_win_is_valid(win_id) then return end
      do_submit()
    end,
  })

  -- ── BufLeave: trap focus back in the window  (99 does this) ─────────
  vim.api.nvim_create_autocmd("BufLeave", {
    group    = group,
    buffer   = buf_id,
    callback = function()
      if vim.api.nvim_win_is_valid(win_id) then
        vim.api.nvim_set_current_win(win_id)
      end
    end,
  })

  -- ── WinClosed: cancel when window is closed any other way ───────────
  vim.api.nvim_create_autocmd("WinClosed", {
    group   = group,
    pattern = tostring(win_id),
    callback = function()
      vim.api.nvim_del_augroup_by_id(group)
    end,
  })

  -- ── BufUnload: cleanup group ────────────────────────────────────────
  vim.api.nvim_create_autocmd("BufUnload", {
    group    = group,
    buffer   = buf_id,
    callback = function()
      vim.api.nvim_del_augroup_by_id(group)
    end,
  })

  local bopts = { buffer = buf_id, nowait = true, noremap = true, silent = true }

  -- <CR> in insert/normal → :w → BufWriteCmd fires
  vim.keymap.set("i", "<CR>", "<Esc>:w<CR>", bopts)
  vim.keymap.set("n", "<CR>", ":w<CR>",      bopts)

  -- q in normal mode = cancel  (99 adds this too)
  vim.keymap.set("n", "q", function()
    vim.api.nvim_del_augroup_by_id(group)
    do_close()
  end, bopts)

  -- <Esc> in insert → normal mode (standard Vim; user can then q or <CR>)
  -- no override needed — default <Esc> already exits insert mode
end

-- ─────────────────────────────────────────────
-- Convenience openers
-- ─────────────────────────────────────────────

function M.open_word()   M.open(vim.fn.expand("<cword>")) end
function M.open_visual() M.open(get_visual_selection())   end

-- ─────────────────────────────────────────────
-- Setup
-- ─────────────────────────────────────────────

function M.setup(opts)
  M.config = vim.tbl_deep_extend("force", M.config, opts or {})

  -- Highlights — link to theme where possible, fallback hardcoded
  vim.api.nvim_set_hl(0, "QSKey",   { fg = "#f7c948", bold = true })
  vim.api.nvim_set_hl(0, "QSLabel", { fg = "#a8d8a8" })

  vim.api.nvim_create_user_command("QuickSearch",
    function() M.open() end, {})
  vim.api.nvim_create_user_command("QuickSearchWord",
    function() M.open_word() end, {})
  vim.api.nvim_create_user_command("QuickSearchVisual",
    function() M.open_visual() end, { range = true })

  local key = M.config.keymap
  if key then
    vim.keymap.set("n", key,        M.open,        { desc = "QuickSearch: open" })
    vim.keymap.set("n", key .. "w", M.open_word,   { desc = "QuickSearch: word under cursor" })
    vim.keymap.set("v", key,        M.open_visual, { desc = "QuickSearch: visual selection" })
  end
end

return M
