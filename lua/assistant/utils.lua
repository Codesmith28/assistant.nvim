local config = require 'assistant.config'
local utils = {}

---@return integer, integer
local function get_view_size()
  local vw = vim.o.columns
  local vh = vim.o.lines - vim.o.cmdheight

  if vim.o.laststatus ~= 0 then
    vh = vh - 1
  end

  return vw, vh
end

---@param message string
function utils.info(message)
  vim.notify(message, vim.log.levels.INFO, { title = 'Assistant.nvim' })
end

---@param message string
function utils.warn(message)
  vim.notify(message, vim.log.levels.WARN, { title = 'Assistant.nvim' })
end

---@param message string
function utils.error(message)
  vim.notify(message, vim.log.levels.ERROR, { title = 'Assistant.nvim' })
end

---@param str string
function utils.to_snake_case(str)
  return str
    :gsub('^%s*(.-)%s*$', '%1')
    :gsub('[^%w%s_]', '')
    :gsub('(%u+)(%u%l)', '%1_%2')
    :gsub('(%l)(%u)', '%1_%2')
    :gsub('(%d)(%a)', '%1_%2')
    :gsub('(%a)(%d)', '%1_%2')
    :gsub('%s+', '_')
    :gsub('_+', '_')
    :gsub('^_', '')
    :gsub('_$', '')
    :lower()
end

---@param str string
---@param n number
---@return table<string>
function utils.slice_first_n_lines(str, n)
  local lines = {}

  for line in str:gmatch '[^\n]*' do
    if line ~= '' then
      table.insert(lines, line)
    end

    if #lines == n then
      break
    end
  end

  return lines
end

---@param window Assistant.Window
function utils.create_window(window)
  if window.winid and vim.api.nvim_win_is_valid(window.winid) then
    return
  end

  window.bufnr = vim.api.nvim_create_buf(false, true)
  window.winid = vim.api.nvim_open_win(window.bufnr, window.enter, utils.get_win_config(window))
end

---@param window? Assistant.Window
function utils.remove_window(window)
  if not window then
    return
  end

  if window.winid and vim.api.nvim_win_is_valid(window.winid) then
    vim.api.nvim_win_close(window.winid, true)
  end

  if window.bufnr and vim.api.nvim_buf_is_valid(window.bufnr) then
    vim.api.nvim_buf_delete(window.bufnr, { force = true })
  end
end

---@param events string|string[]
---@param options vim.api.keyset.create_autocmd
function utils.create_autocmd(events, options)
  options = options or {}
  options.group = config.augroup
  vim.api.nvim_create_autocmd(events, options)
end

---@class Asssistant.Window.Keyamp.Config
---@field mode string|string[]
---@field lhs string
---@field rhs string|function|Assistant.Action
---@field options? vim.keymap.set.Opts

---@param key_config Asssistant.Window.Keyamp.Config
function utils.set_keymap(key_config)
  key_config = key_config or {}
  local mode = key_config.mode or 'n'
  local lhs = key_config.lhs
  local rhs = key_config.rhs
  local opts = vim.tbl_deep_extend('force', key_config.options or {}, {
    silent = true,
    noremap = true,
    desc = (type(rhs) == 'table' and rhs:get_name() or nil),
  })

  if type(rhs) == 'string' then
    vim.keymap.set(mode, lhs, rhs, opts)
  elseif type(rhs) == 'function' then
    vim.keymap.set(mode, lhs, rhs, opts)
  else
    vim.keymap.set(mode, lhs, function()
      rhs()
    end, opts)
  end
end

---@param winid integer
---@param win_config vim.api.keyset.win_config
function utils.set_win_config(winid, win_config)
  if winid and vim.api.nvim_win_is_valid(winid) then
    vim.api.nvim_win_set_config(winid, vim.tbl_deep_extend('force', vim.api.nvim_win_get_config(winid), win_config))
  end
end

---@param window Assistant.Window
---@param option string
---@param value any
function utils.set_win_option(window, option, value)
  if vim.wo then
    vim.wo[window.winid][option] = value
  else
    vim.api.nvim_set_option_value(option, value, { win = window.winid })
  end

  if not window.wo then
    window.wo = {}
  end

  window.wo[option] = value
end

---@param window Assistant.Window
---@param option string
---@param value any
function utils.set_buf_option(window, option, value)
  if vim.bo then
    vim.bo[window.bufnr][option] = value
  else
    vim.api.nvim_set_option_value(option, value, { buf = window.bufnr })
  end

  if not window.bo then
    window.bo = {}
  end

  window.bo[option] = value
end

---@param window Assistant.Window
---@return vim.api.keyset.win_config
function utils.get_win_config(window)
  return {
    style = 'minimal',
    width = window.width(get_view_size()) + (window.width_delta or 0),
    height = window.height(get_view_size()) + (window.height_delta or 0),
    col = window.col(get_view_size()) + (window.col_delta or 0),
    row = window.row(get_view_size()) + (window.row_delta or 0),
    border = config.values.ui.border,
    title = window.title,
    title_pos = window.title_pos,
    relative = 'editor',
    zindex = window.zindex or 1,
  }
end

---Ensure output directory exists for binaries
---@param dir? string
function utils.ensure_out_dir(dir)
  dir = dir or (config.values.core and config.values.core.out_dir) or '.bin'
  local fs = require 'assistant.core.fs'
  local filedir = fs.get_file_dir()
  if filedir and filedir ~= '' and vim.fn.isdirectory(filedir) == 1 then
    local target = filedir .. '/' .. dir
    if vim.fn.isdirectory(target) == 0 then
      vim.fn.mkdir(target, 'p')
    end
  end

  local cwd = vim.fn.getcwd()
  local cwd_target = cwd .. '/' .. dir
  if vim.fn.isdirectory(cwd_target) == 0 then
    vim.fn.mkdir(cwd_target, 'p')
  end
end

---@class Assistant.Processor.SourceConfig
---@field extension string
---@field compile? Assistant.Processor.Command
---@field execute? Assistant.Processor.Command
---@field template? string

---@return Assistant.Processor.SourceConfig
function utils.get_source_config()
  local state = require 'assistant.state'
  local fs = require 'assistant.core.fs'
  local out_dir = (config.values.core and config.values.core.out_dir) or '.bin'
  utils.ensure_out_dir(out_dir)

  local filename = state.get_local_key 'filename' or vim.fn.expand '%:t:r'
  local extension = state.get_local_key 'extension' or vim.fn.expand '%:e'
  local filedir = fs.get_file_dir()
  local cwd = vim.fn.getcwd()

  ---@param str string
  ---@return string
  local function format(str)
    if not str then
      return ''
    end
    return str
      :gsub('%$FILENAME_WITH_EXTENSION', string.format('%s.%s', filename, extension))
      :gsub('%$FILENAME_WITHOUT_EXTENSION', filename)
      :gsub('%$OUT_DIR', out_dir)
      :gsub('%$FILEDIR', filedir or '')
  end

  local ft = state.get_local_key 'filetype'
  if not (ft and config.values.commands[ft]) then
    for k, cmd in pairs(config.values.commands or {}) do
      if cmd.extension == extension then
        ft = k
        break
      end
    end
  end
  if not (ft and config.values.commands[ft]) then
    ft = config.values.core.default_source or next(config.values.commands or {})
  end

  if not (ft and config.values.commands and config.values.commands[ft]) then
    utils.error 'No configuration found for language/filetype'
    return {}
  end

  local command = vim.deepcopy(config.values.commands[ft])

  if command.compile then
    command.compile.main = format(command.compile.main)

    for i = 1, #(command.compile.args or {}) do
      command.compile.args[i] = format(command.compile.args[i])
    end
  end

  if command.execute then
    command.execute.main = format(command.execute.main)

    for i = 1, #(command.execute.args or {}) do
      command.execute.args[i] = format(command.execute.args[i])
    end
  end

  -- If file is in a subdirectory relative to cwd, adjust relative paths
  if filedir and filedir ~= cwd and command then
    local rel_dir = vim.fn.fnamemodify(filedir, ':.')
    if rel_dir and rel_dir ~= '' and rel_dir ~= '.' then
      local target_file = string.format('%s.%s', filename, extension)

      if command.compile and command.compile.args then
        for i, arg in ipairs(command.compile.args) do
          if string.match(arg, '^%./' .. vim.pesc(out_dir) .. '/') then
            command.compile.args[i] = './' .. rel_dir .. '/' .. out_dir .. '/' .. filename
          elseif string.match(arg, '^' .. vim.pesc(out_dir) .. '/') then
            command.compile.args[i] = rel_dir .. '/' .. arg
          elseif arg == target_file or string.match(arg, target_file .. '$') then
            command.compile.args[i] = rel_dir .. '/' .. target_file
          end
        end
      end

      if command.execute and command.execute.main then
        if string.match(command.execute.main, '^%./' .. vim.pesc(out_dir) .. '/') then
          command.execute.main = './' .. rel_dir .. '/' .. out_dir .. '/' .. filename
        end
      end
    end
  end

  return command
end

return utils
