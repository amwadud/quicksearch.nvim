# quicksearch.nvim

A minimal floating search launcher for Neovim — type a query, pick a search engine, open in browser.

```
╭────────────────────  QuickSearch ────────────────────╮
│  neovim lua floating window                             │
╰─────────────────────────────────────────────────────────╯
```

After pressing Enter, a picker appears:

```
╭─────────── Search: "neovim lua floating" ───────────╮
│  [g]  Google                                        │
│  [d]  DuckDuckGo                                    │
│  [y]  YouTube                                       │
│  [r]  Reddit                                        │
│  [h]  HackerNews                                    │
│  [n]  npm                                           │
│  [p]  PyPI                                          │
│  [m]  MDN                                           │
│  [s]  StackOverflow                                 │
│  [w]  Wikipedia                                     │
│  [G]  GitHub                                        │
╰─────────────────────────────────────────────────────╯
```

---

## Install

**lazy.nvim:**
```lua
{
  "yourname/quicksearch.nvim",
  config = function()
    require("quicksearch").setup()
  end,
}
```

**packer.nvim:**
```lua
use {
  "yourname/quicksearch.nvim",
  config = function()
    require("quicksearch").setup()
  end
}
```

---

## Default Keymaps

| Key          | Mode   | Action                         |
|--------------|--------|--------------------------------|
| `<leader>s`  | Normal | Open search prompt             |
| `<leader>sw` | Normal | Search word under cursor       |
| `<leader>s`  | Visual | Search visual selection        |

---

## Configuration

```lua
require("quicksearch").setup({
  -- Floating window dimensions
  width = 60,
  border = "rounded", -- "single", "double", "rounded", "shadow", none

  -- Keymap (set to nil to disable)
  keymap = "<leader>s",

  -- Add or remove search engines
  engines = {
    { key = "g", label = "Google",       url = "https://www.google.com/search?q=" },
    { key = "d", label = "DuckDuckGo",   url = "https://duckduckgo.com/?q=" },
    { key = "y", label = "YouTube",      url = "https://www.youtube.com/results?search_query=" },
    { key = "r", label = "Reddit",       url = "https://www.reddit.com/search/?q=" },
    { key = "h", label = "HackerNews",   url = "https://hn.algolia.com/?q=" },
    { key = "n", label = "npm",          url = "https://www.npmjs.com/search?q=" },
    { key = "p", label = "PyPI",         url = "https://pypi.org/search/?q=" },
    { key = "m", label = "MDN",          url = "https://developer.mozilla.org/en-US/search?q=" },
    { key = "s", label = "StackOverflow",url = "https://stackoverflow.com/search?q=" },
    { key = "w", label = "Wikipedia",    url = "https://en.wikipedia.org/wiki/Special:Search?search=" },
    { key = "G", label = "GitHub",       url = "https://github.com/search?q=" },
  },

  -- Override OS open command (auto-detected: open / xdg-open / start)
  open_cmd = nil,
})
```

---

## Commands

| Command                | Description                    |
|------------------------|--------------------------------|
| `:QuickSearch`         | Open prompt                    |
| `:QuickSearchWord`     | Search word under cursor       |
| `:QuickSearchVisual`   | Search visual selection        |

---

## In the Engine Picker

- Press the **letter key** shown in `[x]` to open that engine
- Press **1–9** as number shortcuts for the first 9 engines
- `q` or `<Esc>` to cancel

---

## How It Works

1. `<leader>s` opens a `buftype=prompt` floating window
2. You type your query and press `<Enter>`
3. The engine picker window opens — each engine bound to a key
4. The URL is assembled as `url_prefix + urlencode(query)` and opened with your OS's open command

---

## Requirements

- Neovim >= 0.9
- A browser set as your OS default
