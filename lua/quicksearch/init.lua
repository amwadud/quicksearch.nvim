-- quicksearch.nvim
-- Floating search launcher — window style from ThePrimeagen/99
-- Enhancements: legend bar, search history, live URL preview, context-aware engine

local M = {}

-- ─────────────────────────────────────────────
-- Config
-- ─────────────────────────────────────────────
M.config = {
  border   = "rounded",
  title    = " 🔍 QuickSearch ",
  keymap   = "<leader>s",
  history_max  = 50,
  history_path = vim.fn.stdpath("data") .. "/quicksearch_history.json",
  engines = {
    { key = "g", label = "Google",        url = "https://www.google.com/search?q=",                  ft = {} },
    { key = "d", label = "DuckDuckGo",    url = "https://duckduckgo.com/?q=",                        ft = {} },
    { key = "y", label = "YouTube",       url = "https://www.youtube.com/results?search_query=",     ft = {} },
    { key = "r", label = "Reddit",        url = "https://www.reddit.com/search/?q=",                 ft = {} },
    { key = "h", label = "HackerNews",    url = "https://hn.algolia.com/?q=",                        ft = {} },
    { key = "n", label = "npm",           url = "https://www.npmjs.com/search?q=",                   ft = { "javascript", "typescript", "json" } },
    { key = "p", label = "PyPI",          url = "https://pypi.org/search/?q=",                       ft = { "python" } },
    { key = "m", label = "MDN",           url = "https://developer.mozilla.org/en-US/search?q=",     ft = { "javascript", "typescript", "html", "css" } },
    { key = "s", label = "StackOverflow", url = "https://stackoverflow.com/search?q=",               ft = {} },
    { key = "w", label = "Wikipedia",     url = "https://en.wikipedia.org/wiki/Special:Search?search=", ft = {} },
    { key = "G", label = "GitHub",        url = "https://github.com/search?q=",                      ft = { "lua", "go", "rust", "c", "cpp" } },
    { key = "R", label = "Rust Docs",     url = "https://doc.rust-lang.org/std/?search=",            ft = { "rust" } },
    { key = "l", label = "Lua Docs",      url = "https://www.google.com/search?q=lua+5.1+",          ft = { "lua" } },
    { key = "c", label = "crates.io",     url = "https://crates.io/search?q=",                       ft = { "rust", "toml" } },
  },
  open_cmd = nil,
}

-- ─────────────────────────────────────────────
-- History  (persisted JSON, cycled with C-p / C-n)
-- ─────────────────────────────────────────────

local History = {}

function History.load()
  local path = M.config.history_path
  local f = io.open(path, "r")
  if not f then return {} end
  local raw = f:read("*a")
  f:close()
  local ok, data = pcall(vim.json.decode, raw)
  return (ok and type(data) == "table") and data or {}
end

function History.save(list)
  local path = M.config.history_path
  local f = io.open(path, "w")
  if not f then return end
  f:write(vim.json.encode(list))
  f:close()
end

function History.push(query)
  if not query or query == "" then return end
  local list = History.load()
  -- remove duplicate if present
  for i, v in ipairs(list) do
    if v == query then table.remove(list, i); break end
  end
  table.insert(list, 1, query)
  while #list > M.config.history_max do table.remove(list) end
  History.save(list)
end

-- ─────────────────────────────────────────────
-- Context-aware default engine
-- ─────────────────────────────────────────────

local function get_context_engine()
  -- filetype of the buffer we came from (before opening the float)
  local ft = vim.bo.filetype
  if not ft or ft == "" or ft == "quicksearch" then return nil end
  local best = nil
  for _, e in ipairs(M.config.engines) do
    if vim.tbl_contains(e.ft, ft) then
      -- prefer more specific: engines with fewer fts win
      if not best or #e.ft < #best.ft then
        best = e
      end
    end
  end
  return best
end

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
-- Geometry
-- ─────────────────────────────────────────────

local function get_ui_dimensions()
  local ui = vim.api.nvim_list_uis()[1]
  return ui.width, ui.height
end

local function centered_config(win_w, win_h, title)
  local ui_w, ui_h = get_ui_dimensions()
  return {
    relative  = "editor",
    style     = "minimal",
    border    = M.config.border,
    title     = title,
    title_pos = "center",
    width     = win_w,
    height    = win_h,
    row       = math.floor((ui_h - win_h) / 2),
    col       = math.floor((ui_w - win_w) / 2),
    zindex    = 1,
  }
end

local function create_floating_window(win_cfg, enter)
  local buf_id = vim.api.nvim_create_buf(false, true)
  local win_id = vim.api.nvim_open_win(buf_id, enter, win_cfg)
  vim.wo[win_id].wrap = true
  return win_id, buf_id
end

-- ─────────────────────────────────────────────
-- Legend bar  (mirrors 99's create_window_legend)
-- Rendered as a borderless float pinned just below the input window.
-- ─────────────────────────────────────────────

local function create_legend(parent_win_id, parent_cfg, context_engine)
  local hint = context_engine
    and string.format("  :w=search  C-p/n=history  context:%s  q=cancel", context_engine.label)
    or  "  :w=search  C-p/n=history  q=cancel"

  local ui_w, ui_h = get_ui_dimensions()
  local legend_w = parent_cfg.width
  local legend_h = 1

  -- position: one row below the bottom border of the input window
  local parent_bottom = parent_cfg.row + parent_cfg.height + 1  -- +1 for border
  -- clamp so it doesn't go off screen
  if parent_bottom + legend_h >= ui_h then
    parent_bottom = parent_cfg.row - legend_h - 1
  end

  local cfg = {
    relative  = "editor",
    style     = "minimal",
    border    = "none",
    width     = legend_w,
    height    = legend_h,
    row       = parent_bottom,
    col       = parent_cfg.col,
    zindex    = 2,   -- just above the input window
    focusable = false,
  }

  local legend_win, legend_buf = create_floating_window(cfg, false)
  vim.bo[legend_buf].buftype   = "nofile"
  vim.bo[legend_buf].bufhidden = "wipe"

  -- truncate hint to window width
  local display = hint:sub(1, legend_w)
  vim.api.nvim_buf_set_lines(legend_buf, 0, -1, false, { display })
  vim.bo[legend_buf].modifiable = false

  -- highlight
  vim.api.nvim_buf_call(legend_buf, function()
    vim.cmd([[syntax match QSLegendKey /\:w\|C-p\|C-n\|q/]])
    vim.cmd([[syntax match QSLegendContext /context:\S*/]])
  end)

  -- live URL preview: update legend line as user types in parent buf
  return legend_win, legend_buf
end

-- ─────────────────────────────────────────────
-- Live URL preview  (updates legend second line or virtual text)
-- ─────────────────────────────────────────────

local preview_nsid = vim.api.nvim_create_namespace("quicksearch.preview")

local function update_preview(input_buf, legend_buf, legend_w, default_engine)
  if not vim.api.nvim_buf_is_valid(input_buf) then return end
  if not vim.api.nvim_buf_is_valid(legend_buf) then return end

  local lines = vim.api.nvim_buf_get_lines(input_buf, 0, -1, false)
  local parts = {}
  for _, line in ipairs(lines) do
    local trimmed = line:gsub("^%s+", ""):gsub("%s+$", "")
    if trimmed ~= "" then table.insert(parts, trimmed) end
  end
  local query = table.concat(parts, " ")

  local engine = default_engine or M.config.engines[1]
  local preview_url = query ~= "" and (engine.url .. urlencode(query)) or ""
  local display     = preview_url ~= "" and ("  → " .. preview_url) or "  → (type to preview URL)"

  -- write into legend buf (make it writable momentarily)
  vim.bo[legend_buf].modifiable = true
  vim.bo[legend_buf].readonly   = false
  local truncated = display:sub(1, legend_w)
  vim.api.nvim_buf_set_lines(legend_buf, 0, -1, false, { truncated })
  vim.bo[legend_buf].modifiable = false
  vim.bo[legend_buf].readonly   = true
end

-- ─────────────────────────────────────────────
-- Engine picker
-- ─────────────────────────────────────────────

local function show_engine_picker(query, default_engine)
  if not query or query == "" then return end

  -- Sort: context engine first if present, then rest
  local engines = {}
  if default_engine then
    table.insert(engines, default_engine)
  end
  for _, e in ipairs(M.config.engines) do
    if not default_engine or e.key ~= default_engine.key then
      table.insert(engines, e)
    end
  end

  local max_label = 0
  for _, e in ipairs(engines) do
    if #e.label > max_label then max_label = #e.label end
  end

  local lines = {}
  for i, e in ipairs(engines) do
    local marker = (i == 1 and default_engine) and " ★" or ""
    table.insert(lines, string.format("  [%s]  %s%s%s",
      e.key, string.rep(" ", max_label - #e.label), e.label, marker))
  end

  local ui_w, ui_h = get_ui_dimensions()
  local win_w = max_label + 16
  local win_h = #lines
  local short = query:sub(1, 20) .. (query:len() > 20 and "…" or "")
  local cfg   = centered_config(win_w, win_h,
    string.format(' Search: "%s" ', short))

  local win_id, buf_id = create_floating_window(cfg, true)
  vim.bo[buf_id].buftype   = "nofile"
  vim.bo[buf_id].bufhidden = "wipe"
  vim.bo[buf_id].swapfile  = false
  vim.api.nvim_buf_set_lines(buf_id, 0, -1, false, lines)
  vim.bo[buf_id].modifiable = false
  vim.bo[buf_id].readonly   = true
  vim.wo[win_id].cursorline = true

  vim.api.nvim_buf_call(buf_id, function()
    vim.cmd([[syntax match QSKey     /\[.\]/]])
    vim.cmd([[syntax match QSLabel   /\]  \S.*/]])
    vim.cmd([[syntax match QSStar    /★/]])
  end)

  local close = function()
    if vim.api.nvim_win_is_valid(win_id) then
      vim.api.nvim_win_close(win_id, true)
    end
  end

  local bopts = { buffer = buf_id, nowait = true, noremap = true, silent = true }

  vim.keymap.set("n", "<CR>", function()
    local idx = vim.api.nvim_win_get_cursor(win_id)[1]
    local e   = engines[idx]
    if e then close(); open_url(e.url .. urlencode(query)) end
  end, bopts)

  for i, e in ipairs(engines) do
    local url = e.url .. urlencode(query)
    vim.keymap.set("n", e.key, function() close(); open_url(url) end, bopts)
    if i <= 9 then
      vim.keymap.set("n", tostring(i), function() close(); open_url(url) end, bopts)
    end
  end

  -- y = yank URL instead of opening
  vim.keymap.set("n", "y", function()
    local idx = vim.api.nvim_win_get_cursor(win_id)[1]
    local e   = engines[idx]
    if e then
      local url = e.url .. urlencode(query)
      vim.fn.setreg("+", url)
      vim.fn.setreg('"', url)
      close()
      vim.notify("Yanked: " .. url, vim.log.levels.INFO, { title = "QuickSearch" })
    end
  end, bopts)

  vim.keymap.set("n", "q",     close, bopts)
  vim.keymap.set("n", "<Esc>", close, bopts)
end

-- ─────────────────────────────────────────────
-- Input window
-- ─────────────────────────────────────────────

function M.open(prefill)
  -- capture filetype BEFORE we open the float (it will change to "quicksearch")
  local context_engine = get_context_engine()

  local ui_w, ui_h = get_ui_dimensions()
  local win_w = math.floor(ui_w * 2 / 3)
  local win_h = math.floor(ui_h * 1 / 3)
  local input_cfg = centered_config(win_w, win_h, M.config.title)

  local win_id, buf_id = create_floating_window(input_cfg, true)

  vim.api.nvim_buf_set_name(buf_id, "quicksearch-prompt")
  vim.wo[win_id].number    = true
  vim.bo[buf_id].filetype  = "quicksearch"
  vim.bo[buf_id].buftype   = "acwrite"
  vim.bo[buf_id].bufhidden = "wipe"
  vim.bo[buf_id].swapfile  = false

  vim.api.nvim_set_current_win(win_id)

  if prefill and prefill ~= "" then
    vim.api.nvim_buf_set_lines(buf_id, 0, -1, false, { prefill })
    vim.api.nvim_win_set_cursor(win_id, { 1, #prefill })
  end

  vim.cmd("startinsert!")

  -- ── Legend bar ──────────────────────────────
  local legend_win, legend_buf = create_legend(win_id, input_cfg, context_engine)

  -- ── History state ───────────────────────────
  local history     = History.load()
  local history_idx = 0   -- 0 = current input, 1+ = history entries
  local saved_input = ""  -- saves what user typed before cycling history

  -- ── Autocmd group ───────────────────────────
  local group = vim.api.nvim_create_augroup(
    "quicksearch_prompt_" .. buf_id, { clear = true })

  local function do_close()
    if vim.api.nvim_win_is_valid(legend_win) then
      vim.api.nvim_win_close(legend_win, true)
    end
    if vim.api.nvim_win_is_valid(win_id) then
      vim.api.nvim_win_close(win_id, true)
    end
  end

  local function do_submit()
    local lines = vim.api.nvim_buf_get_lines(buf_id, 0, -1, false)
    -- filter blank lines, join non-blank with single space
    local parts = {}
    for _, line in ipairs(lines) do
      local trimmed = line:gsub("^%s+", ""):gsub("%s+$", "")
      if trimmed ~= "" then table.insert(parts, trimmed) end
    end
    local query = table.concat(parts, " ")
    do_close()
    if query ~= "" then
      History.push(query)
      show_engine_picker(query, context_engine)
    end
  end

  -- ── Live preview: update legend on every text change ────────────────
  vim.api.nvim_create_autocmd({ "TextChanged", "TextChangedI" }, {
    group    = group,
    buffer   = buf_id,
    callback = function()
      update_preview(buf_id, legend_buf, win_w, context_engine or M.config.engines[1])
    end,
  })

  -- ── BufWriteCmd: submit via :w ───────────────────────────────────────
  vim.api.nvim_create_autocmd("BufWriteCmd", {
    group    = group,
    buffer   = buf_id,
    callback = function()
      if not vim.api.nvim_win_is_valid(win_id) then return end
      do_submit()
    end,
  })

  -- ── BufLeave: trap focus ─────────────────────────────────────────────
  vim.api.nvim_create_autocmd("BufLeave", {
    group    = group,
    buffer   = buf_id,
    callback = function()
      if vim.api.nvim_win_is_valid(win_id) then
        vim.api.nvim_set_current_win(win_id)
      end
    end,
  })

  -- ── WinClosed / BufUnload: cleanup ──────────────────────────────────
  vim.api.nvim_create_autocmd("WinClosed", {
    group   = group,
    pattern = tostring(win_id),
    callback = function() vim.api.nvim_del_augroup_by_id(group) end,
  })
  vim.api.nvim_create_autocmd("BufUnload", {
    group    = group,
    buffer   = buf_id,
    callback = function() vim.api.nvim_del_augroup_by_id(group) end,
  })

  local bopts = { buffer = buf_id, nowait = true, noremap = true, silent = true }

  -- q → cancel (normal mode)
  vim.keymap.set("n", "q", function()
    vim.api.nvim_del_augroup_by_id(group)
    do_close()
  end, bopts)

  -- ── History navigation: C-p (older) / C-n (newer) ───────────────────
  local function set_input(text)
    vim.bo[buf_id].modifiable = true
    vim.api.nvim_buf_set_lines(buf_id, 0, -1, false, { text })
    vim.bo[buf_id].modifiable = true  -- acwrite keeps it writable
    -- move cursor to end of line
    local col = math.max(0, #text - 1)
    pcall(vim.api.nvim_win_set_cursor, win_id, { 1, col })
    update_preview(buf_id, legend_buf, win_w, context_engine or M.config.engines[1])
  end

  vim.keymap.set("i", "<C-p>", function()
    if #history == 0 then return end
    -- save current input before entering history
    if history_idx == 0 then
      local cur = vim.api.nvim_buf_get_lines(buf_id, 0, -1, false)
      saved_input = table.concat(cur, " ")
    end
    history_idx = math.min(history_idx + 1, #history)
    set_input(history[history_idx])
  end, bopts)

  vim.keymap.set("i", "<C-n>", function()
    if history_idx == 0 then return end
    history_idx = history_idx - 1
    if history_idx == 0 then
      set_input(saved_input)
    else
      set_input(history[history_idx])
    end
  end, bopts)
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

  vim.api.nvim_set_hl(0, "QSKey",          { fg = "#f7c948", bold = true })
  vim.api.nvim_set_hl(0, "QSLabel",        { fg = "#a8d8a8" })
  vim.api.nvim_set_hl(0, "QSStar",         { fg = "#f7c948", bold = true })
  vim.api.nvim_set_hl(0, "QSLegendKey",    { fg = "#7aa2f7", bold = true })
  vim.api.nvim_set_hl(0, "QSLegendContext",{ fg = "#f7c948" })

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
