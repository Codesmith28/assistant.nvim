local Window = require 'assistant.lib.window'
local state = require 'assistant.state'
local utils = require 'assistant.utils'

---@class Assistant.Picker.Options
---@field canvas Assistant.Canvas

---@class Assistant.Picker : Assistant.Picker.Options
local Picker = {}

---@param options Assistant.Picker.Options
function Picker.new(options)
  return setmetatable({}, {
    __index = Picker,
  }):init(options)
end

---@param options Assistant.Picker.Options
function Picker:init(options)
  for k, v in pairs(options or {}) do
    self[k] = v
  end

  return self
end

---@generic T
---@param items T[]
---@param options table
---@param on_choice fun(item: T)
function Picker:pick(items, options, on_choice)
  options = options or {}
  local core_cfg = (require('assistant.config').values and require('assistant.config').values.core) or {}

  if options.prompt == 'source' then
    if options.auto_select and options.default then
      on_choice(options.default)
      return
    end
    if core_cfg.default_source and vim.tbl_contains(items, core_cfg.default_source) then
      on_choice(core_cfg.default_source)
      return
    end
    if #items == 1 and core_cfg.auto_select_single_source ~= false then
      on_choice(items[1])
      return
    end
  elseif options.auto_select or (#items == 1 and core_cfg.auto_select_single_source) then
    on_choice(items[1])
    return
  end

  local existing_picker_window = state.get_local_key 'assistant-picker-window'

  if existing_picker_window then
    utils.remove_window(existing_picker_window)
    state.set_local_key('assistant-picker-window', nil)
    state.set_local_key('assistant-picker-canvas', nil)
  end

  local picker_window = Window.new {
    enter = true,
    zindex = 3,
    width = function(vw, _)
      return math.ceil(vw * 0.3)
    end,
    height = function()
      return math.min(#items, 5)
    end,
    col = function(vw, _)
      return math.floor((1 - 0.3) * 0.5 * vw)
    end,
    row = function()
      return 0
    end,
  }

  utils.create_window(picker_window)

  state.set_local_key('assistant-picker-window', picker_window)
  state.set_local_key('assistant-picker-canvas', self.canvas)

  utils.create_autocmd('WinClosed', {
    pattern = tostring(picker_window.winid),
    callback = function()
      utils.remove_window(picker_window)
      state.set_local_key('assistant-picker-window', nil)
      state.set_local_key('assistant-picker-canvas', nil)
      utils.focus_panel()
    end,
  })

  utils.set_win_config(picker_window.winid, {
    title = string.format(' %s ', options.prompt or 'picker'),
    title_pos = 'center',
  })

  utils.set_buf_option(picker_window, 'modifiable', false)
  utils.set_buf_option(picker_window, 'filetype', 'assistant-picker')
  vim.b[picker_window.bufnr].autoformat = false

  utils.set_win_option(picker_window, 'cursorline', true)
  utils.set_win_option(
    picker_window,
    'winhighlight',
    table.concat({
      'Normal:AssistantNormal',
      'FloatBorder:AssistantBorder',
      'FloatTitle:AssistantTitle',
    }, ',')
  )

  utils.set_keymap {
    mode = 'n',
    lhs = '<cr>',
    rhs = function()
      local current_line = vim.api.nvim_get_current_line()
      utils.remove_window(picker_window)
      state.set_local_key('assistant-picker-window', nil)
      state.set_local_key('assistant-picker-canvas', nil)
      utils.focus_panel()
      on_choice(current_line)
    end,
    options = {
      buffer = picker_window.bufnr,
    },
  }

  for mode, mappings in pairs(require('assistant.mappings').default_mappings.picker or {}) do
    for k, v in pairs(mappings) do
      utils.set_keymap {
        mode = mode,
        lhs = k,
        rhs = v,
        options = {
          buffer = picker_window.bufnr,
        },
      }
    end
  end

  self.canvas:set(picker_window.bufnr, items)
end

return Picker
