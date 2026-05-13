-- quicksearch.nvim entry point
-- Loaded automatically by Neovim's plugin system

if vim.g.loaded_quicksearch then
  return
end
vim.g.loaded_quicksearch = 1

require("quicksearch").setup()
