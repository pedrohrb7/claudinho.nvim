-- Minimal repro config for claudinho.nvim issues.
--
-- This fixture intentionally avoids a plugin manager so it's easy to run and reason about.
--
-- Usage (from repo root):
--   source fixtures/nvim-aliases.sh
--   repro
--
-- To edit this config:
--   vve repro

-- Ensure this repo is on the runtimepath so `plugin/claudinho.lua` is loaded.
local config_dir = vim.fn.stdpath("config")
local repo_root = vim.fn.fnamemodify(config_dir, ":h:h")

vim.opt.rtp:prepend(repo_root)

-- Basic editor settings
vim.g.mapleader = " "
vim.g.maplocalleader = "\\"

local ok, claudinho = pcall(require, "claudinho")
assert(ok, "Failed to load claudinho.nvim from repo root: " .. tostring(claudinho))

claudinho.setup({
  log_level = "debug",
  diff_opts = {
    layout = "vertical",
    open_in_new_tab = false,
    keep_terminal_focus = false,
  },
})

-- Keymaps (kept small on purpose)
vim.keymap.set("n", "<leader>ac", "<cmd>Claudinho toggle<cr>", { desc = "Toggle Claude" })
vim.keymap.set("n", "<leader>af", "<cmd>Claudinho focus<cr>", { desc = "Focus Claude" })
vim.keymap.set("n", "<leader>aa", "<cmd>Claudinho diff-accept<cr>", { desc = "Accept diff" })
vim.keymap.set("n", "<leader>ad", "<cmd>Claudinho diff-deny<cr>", { desc = "Deny diff" })

-- Convenience helpers for iterating on this fixture.
vim.api.nvim_create_user_command("ReproEditConfig", function()
  local config_path = vim.fn.stdpath("config") .. "/init.lua"

  -- Open the config file without `:edit` / `vim.cmd(...)` so we don't trigger
  -- Treesitter "vim" language injections (which can be noisy if parsers/queries mismatch).
  local bufnr = vim.fn.bufadd(config_path)
  vim.fn.bufload(bufnr)
  vim.api.nvim_set_current_buf(bufnr)
end, { desc = "Edit the repro Neovim config" })

vim.keymap.set("n", "<leader>ae", "<cmd>ReproEditConfig<cr>", { desc = "Edit repro config" })
vim.keymap.set("n", "<leader>aw", function()
  vim.notify(("windows in tab: %d"):format(vim.fn.winnr("$")))
end, { desc = "Claude: show window count" })
