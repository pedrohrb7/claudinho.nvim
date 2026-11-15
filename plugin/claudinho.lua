if vim.fn.has("nvim-0.12") ~= 1 then
  vim.api.nvim_err_writeln("Claudinho requires Neovim >= 0.12")
  return
end

if vim.g.loaded_claudinho then
  return
end
vim.g.loaded_claudinho = 1
if require("claudinho.conflict").check() then
  return
end

--- Example: In your `init.lua`, you can set `vim.g.claudinho_auto_setup = { auto_start = true }`
--- to automatically start Claudinho when Neovim loads.
if vim.g.claudinho_auto_setup then
  vim.defer_fn(function()
    require("claudinho").setup(vim.g.claudinho_auto_setup)
  end, 0)
end

-- Commands are now registered in lua/claudinho/init.lua's _create_commands function
-- when require("claudinho").setup() is called.
-- This file (plugin/claudinho.lua) is primarily for the load guard
-- and the optional auto-setup mechanism.

local main_module_ok, _ = pcall(require, "claudinho")
if not main_module_ok then
  vim.notify("Claudinho: Failed to load main module. Plugin may not function correctly.", vim.log.levels.ERROR)
end
