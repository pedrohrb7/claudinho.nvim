---@meta
---@brief [[
--- Centralized type definitions for Claudinho.nvim public API.
--- This module contains all user-facing types and configuration structures.
---@brief ]]
---@module 'claudinho.types'

-- Version information type
---@class ClaudinhoVersion
---@field major integer
---@field minor integer
---@field patch integer
---@field prerelease? string
---@field string fun(self: ClaudinhoVersion): string

-- Diff behavior configuration
---@class ClaudinhoDiffOptions
---@field layout ClaudinhoDiffLayout
---@field open_in_new_tab boolean Open diff in a new tab (false = use current tab)
---@field keep_terminal_focus boolean Keep focus in terminal after opening diff
---@field hide_terminal_in_new_tab boolean Hide Claude terminal in newly created diff tab
---@field on_new_file_reject ClaudinhoNewFileRejectBehavior Behavior when rejecting a new-file diff
---@field auto_resize_terminal boolean Let the plugin resize the Claude terminal across the diff lifecycle (default true); set false to own width via the ClaudinhoDiffOpened/Closed User autocmds

-- Model selection option
---@class ClaudinhoModelOption
---@field name string
---@field value string

-- Log level type alias
---@alias ClaudinhoLogLevel "trace"|"debug"|"info"|"warn"|"error"

-- Diff layout type alias
---@alias ClaudinhoDiffLayout "vertical"|"horizontal"|"unified"

-- Behavior when rejecting new-file diffs
---@alias ClaudinhoNewFileRejectBehavior "keep_empty"|"close_window"

-- Terminal split side positioning
---@alias ClaudinhoSplitSide "left"|"right"

-- In-tree terminal provider names
---@alias ClaudinhoTerminalProviderName "auto"|"native"|"external"|"none"

-- Terminal provider-specific options
---@class ClaudinhoTerminalProviderOptions
---@field external_terminal_cmd string|(fun(cmd: string, env: table): string)|table|nil Command for external terminal (string template with %s or function)

-- Working directory resolution context and provider
---@class ClaudinhoCwdContext
---@field file string|nil   -- absolute path of current buffer file (if any)
---@field file_dir string|nil -- directory of current buffer file (if any)
---@field cwd string        -- current Neovim working directory

---@alias ClaudinhoCwdProvider fun(ctx: ClaudinhoCwdContext): string|nil

-- @ mention queued for Claude Code
---@class ClaudinhoMention
---@field file_path string The absolute file path to mention
---@field start_line number? Optional start line (0-indexed for Claude compatibility)
---@field end_line number? Optional end line (0-indexed for Claude compatibility)
---@field deadline number When the queue clears the mention with an error (vim.loop.now() time)

-- Payload delivered as `data` to a `User ClaudinhoSendComplete` autocmd. Fired
-- once per file, synchronously, when a send is accepted while Claude is connected.
-- Lines are 0-indexed (Claude convention, NOT 1-indexed editor lines) and may be
-- nil for whole-file/directory sends. file_path is the absolute path Claude
-- received (a directory ends in /). See README "Events".
---@class ClaudinhoSendCompleteData
---@field file_path string Absolute path Claude received (a directory ends in /)
---@field start_line number? Start line, 0-indexed for Claude, or nil
---@field end_line number? End line, 0-indexed for Claude, or nil
---@field context string? Internal logging tag (e.g. "ClaudeCodeSend"); best-effort, may change

-- Terminal provider interface
---@class ClaudinhoTerminalProvider
---@field setup fun(config: ClaudinhoTerminalConfig)
---@field open fun(cmd_string: string, env_table: table, config: ClaudinhoTerminalConfig, focus: boolean?)
---@field close fun()
---@field toggle fun(cmd_string: string, env_table: table, effective_config: ClaudinhoTerminalConfig)
---@field simple_toggle fun(cmd_string: string, env_table: table, effective_config: ClaudinhoTerminalConfig)
---@field focus_toggle fun(cmd_string: string, env_table: table, effective_config: ClaudinhoTerminalConfig)
---@field get_active_bufnr fun(): number?
---@field is_available fun(): boolean
---@field ensure_visible? function
---@field _get_terminal_for_test fun(): table?

-- Terminal configuration
---@class ClaudinhoTerminalConfig
---@field split_side ClaudinhoSplitSide
---@field split_width_percentage number
---@field diff_split_width_percentage number? -- optional terminal width while a diff is active; defaults to split_width_percentage
---@field provider ClaudinhoTerminalProviderName|ClaudinhoTerminalProvider
---@field show_native_term_exit_tip boolean
---@field terminal_cmd string?
---@field provider_opts ClaudinhoTerminalProviderOptions?
---@field auto_close boolean
---@field auto_insert boolean -- auto-enter terminal mode when the plugin opens/focuses the Claude terminal; native not on <C-w>l, except after a new-tab diff put the terminal in its tab and until that window closes (#232); false keeps Normal mode + scroll position
---@field env table<string, string>
---@field cwd string|nil                 -- static working directory for Claude terminal
---@field git_repo_cwd boolean|nil      -- use git root of current file/cwd as working directory
---@field cwd_provider? ClaudinhoCwdProvider -- custom function to compute working directory
---@field fix_streamed_paste boolean|"auto"|nil -- work around Neovim <0.12.2 terminal paste fragmentation (#161); "auto" (default) enables only on affected versions

-- Port range configuration
---@class ClaudinhoPortRange
---@field min integer
---@field max integer

-- Server status information
---@class ClaudinhoServerStatus
---@field running boolean
---@field port integer?
---@field client_count integer
---@field clients? table<string, any>

-- Main configuration structure
---@class ClaudinhoConfig
---@field port_range ClaudinhoPortRange
---@field auto_start boolean
---@field terminal_cmd string|nil
---@field env table<string, string>
---@field log_level ClaudinhoLogLevel
---@field track_selection boolean
---@field focus_after_send boolean
---@field visual_demotion_delay_ms number
---@field connection_wait_delay number
---@field connection_timeout number
---@field diff_opts ClaudinhoDiffOptions
---@field models ClaudinhoModelOption[]
---@field disable_broadcast_debouncing? boolean
---@field enable_broadcast_debouncing_in_tests? boolean
---@field terminal ClaudinhoTerminalConfig?
---@field window ClaudinhoWindowConfig
---@field keymaps ClaudinhoKeymapsConfig
---@field notify boolean Informative notifications (errors and replies always show)

---@class ClaudinhoWindowConfig
---@field layout "right"|"bottom"|"float"|"tab"
---@field right { width: number, diff_width: number|nil }
---@field bottom { height: number }
---@field float { width: number, height: number }
---@field tab_title_max integer

---@class ClaudinhoKeymapsConfig
---@field preset boolean

---@class (partial) PartialClaudinhoConfig: ClaudinhoConfig

-- Options of lockfile.create
---@class ClaudinhoLockfileOpts
---@field ide_name string|nil            -- the `ideName` of the lock file (default "Neovim")
---@field workspace_folders string[]|nil -- the `workspaceFolders` (default: cwd plus the LSP folders)

-- Server interface for main module
---@class ClaudinhoServerFacade
---@field start fun(config: ClaudinhoConfig, auth_token: string|nil): (success: boolean, port_or_error: number|string)
---@field stop fun(): (success: boolean, error_message: string?)
---@field broadcast fun(method: string, params: table?): boolean
---@field get_status fun(): ClaudinhoServerStatus

-- Main module state
---@class ClaudinhoState
---@field config ClaudinhoConfig
---@field server ClaudinhoServerFacade|nil
---@field port integer|nil
---@field auth_token string|nil
---@field initialized boolean

-- This module only defines types, no runtime functionality
return {}
