-- Development config for working on claudinho.nvim from a local checkout.
-- Loaded by this fixture only: `vv nvim-tree` points Neovim at this folder.

return {
  dir = vim.fn.fnamemodify(vim.fn.stdpath("config"), ":h:h"), -- the repo root, two levels above the fixture config
  name = "claudinho.nvim",
  -- `cmd` lets lazy.nvim create the command stub that loads the plugin on first use,
  -- so `:Claudinho` works on a fresh start (a keys-only spec defers
  -- loading until a <leader>a* mapping is pressed).
  cmd = { "Claudinho" },
  keys = {
    -- AI/Claude Code prefix
    { "<leader>a", nil, desc = "AI/Claude Code" },

    -- Core Claude commands
    { "<leader>ac", "<cmd>Claudinho toggle<cr>", desc = "Toggle Claude" },
    { "<leader>af", "<cmd>Claudinho focus<cr>", desc = "Focus Claude" },
    { "<leader>am", "<cmd>Claudinho select-model<cr>", desc = "Select Claude model" },

    -- Tabs
    { "<leader>an", "<cmd>Claudinho new<cr>", desc = "New Claude tab" },
    { "<leader>al", "<cmd>Claudinho tab-next<cr>", desc = "Next Claude tab" },
    { "<leader>ah", "<cmd>Claudinho tab-prev<cr>", desc = "Previous Claude tab" },
    { "<leader>ax", "<cmd>Claudinho tab-close<cr>", desc = "Close Claude tab" },

    -- Context sending
    { "<leader>as", "<cmd>Claudinho add %<cr>", mode = "n", desc = "Add current buffer" },
    { "<leader>as", "<cmd>Claudinho send<cr>", mode = "v", desc = "Send to Claude" },
    {
      "<leader>as",
      "<cmd>Claudinho tree-add<cr>",
      desc = "Add file from tree",
      ft = { "NvimTree", "neo-tree", "oil", "minifiles", "netrw" },
    },

    -- Development helpers
    { "<leader>ao", "<cmd>Claudinho open<cr>", desc = "Open Claude" },
    { "<leader>aq", "<cmd>Claudinho hide<cr>", desc = "Hide Claude" },
    { "<leader>aK", "<cmd>Claudinho kill-all<cr>", desc = "Kill all Claude tabs" },

    -- Diff management (buffer-local, only active in diff buffers)
    { "<leader>aa", "<cmd>Claudinho diff-accept<cr>", desc = "Accept diff" },
    { "<leader>ad", "<cmd>Claudinho diff-deny<cr>", desc = "Deny diff" },
  },

  -- Development configuration - all options shown with defaults commented out
  ---@type PartialClaudinhoConfig
  opts = {
    -- Server Configuration
    -- port_range = { min = 10000, max = 65535 }, -- WebSocket server port range of each tab
    -- log_level = "info", -- "trace", "debug", "info", "warn", "error"
    -- terminal_cmd = nil, -- Custom terminal command (default: "claude")
    -- notify = false, -- Informative notifications (errors and replies always show)

    -- Send/Focus Behavior
    focus_after_send = true, -- Focus Claude terminal after successful send while connected

    -- Selection Tracking
    -- track_selection = true, -- Enable real-time selection tracking
    -- visual_demotion_delay_ms = 50, -- Delay before demoting visual selection (ms)

    -- Connection Management
    -- connection_wait_delay = 600, -- Wait time after Claude's handshake before sending queued @ mentions (ms)
    -- connection_timeout = 10000, -- Time Claude Code has to connect before queued @ mentions time out (ms)

    -- Diff Integration
    -- diff_opts = {
    --   layout = "horizontal", -- "vertical" or "horizontal" diff layout
    --   open_in_new_tab = true, -- Open diff in a new tab (false = use current tab)
    --   keep_terminal_focus = true, -- Keep focus in terminal after opening diff
    --   hide_terminal_in_new_tab = true, -- Hide Claude terminal in the new diff tab for more review space
    --   auto_resize_terminal = true, -- false = own terminal width via ClaudinhoDiffOpened/Closed User autocmds
    -- },

    -- Window Configuration
    -- window = {
    --   layout = "right",                         -- "right", "left", "bottom", "float" or "tab"
    --   right = { width = 0.30, diff_width = nil }, -- width as a fraction; diff_width applies while a diff is open
    --   left = { width = 0.30, diff_width = nil },  -- the same, for the "left" layout
    --   bottom = { height = 0.30 },
    --   float = { width = 0.80, height = 0.80 },
    --   tab_title_max = 24,                       -- longest tab title in the winbar
    -- },

    -- Key mappings: the <leader>a* preset (off by default)
    -- keymaps = { preset = false },

    -- Development overrides (uncomment as needed)
    -- log_level = "debug",
  },
}
