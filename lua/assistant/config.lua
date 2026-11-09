---@class Assistant.Config.Core
---@field process_budget integer
---@field port integer
---@field default_source? string
---@field out_dir? string
---@field auto_select_single_source? boolean
---@field filename_generator fun(str: string): string

---@class Assistant.Config.UI
---@field border string
---@field diff_mode boolean
---@field title_components_separator string

---@class Assistant.Config
---@field mappings table<string, table<"i"|"n"|"v", table<string, Assistant.Action|function>>>
---@field commands table<string, Assistant.Processor.SourceConfig>
---@field ui Assistant.Config.UI
---@field core Assistant.Config.Core

local config = {}

local defaults = {
  commands = {
    python = {
      extension = 'py',
      compile = nil,
      execute = {
        main = 'python3',
        args = { '$FILENAME_WITH_EXTENSION' },
      },
    },
    cpp = {
      extension = 'cpp',
      compile = {
        main = 'g++',
        args = { '$FILENAME_WITH_EXTENSION', '-o', '$FILENAME_WITHOUT_EXTENSION' },
      },
      execute = {
        main = './$FILENAME_WITHOUT_EXTENSION',
        args = nil,
      },
    },
  },
  ui = {
    border = 'rounded',
    diff_mode = false,
    title_components_separator = '',
  },
  core = {
    process_budget = 5000,
    port = 10043,
    default_source = nil,
    out_dir = nil,
    auto_select_single_source = true,
  },
}

-- Initialize with defaults so requiring dependent modules (e.g. mappings) before overwrite() won't fail
config.values = vim.deepcopy(defaults)
config.namespace = vim.api.nvim_create_namespace 'assistant-nvim'
config.augroup = vim.api.nvim_create_augroup('assistant-nvim', { clear = true })

---@param opts? Assistant.Config
function config.overwrite(opts)
  config.values = vim.tbl_deep_extend('force', defaults, opts or {})
  -- If user specifically configured commands, allow pruning unspecified defaults
  if opts and opts.commands then
    for k in pairs(config.values.commands) do
      if not opts.commands[k] then
        config.values.commands[k] = nil
      end
    end
  end
  config.namespace = vim.api.nvim_create_namespace 'assistant-nvim'
  config.augroup = vim.api.nvim_create_augroup('assistant-nvim', { clear = true })
end

return config
