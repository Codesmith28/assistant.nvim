local Window = require 'assistant.lib.window'
local constants = require 'assistant.constants'
local state = require 'assistant.state'
local utils = require 'assistant.utils'

---@class Assistant.Patcher.Options
---@field canvas Assistant.Canvas

---@class Assistant.Patcher : Assistant.Patcher.Options
local Patcher = {}

---@param options Assistant.Patcher.Options
function Patcher.new(options)
  return setmetatable({}, {
    __index = Patcher,
  }):init(options)
end

---@param options Assistant.Patcher.Options
function Patcher:init(options)
  for k, v in pairs(options or {}) do
    self[k] = v
  end

  return self
end

---@param content string
---@param options? table
---@param on_update fun(content: string)
function Patcher:update(content, options, on_update)
  options = options or {}
  local existing_patcher_window = state.get_local_key 'assistant-patcher-window'

  if existing_patcher_window then
    utils.remove_window(existing_patcher_window)
    state.set_local_key('assistant-patcher-window', nil)
    state.set_local_key('assistant-patcher-canvas', nil)
  end

  local patcher_window = Window.new {
    enter = true,
    zindex = 2,
    width = function(vw, _)
      return math.ceil(vw * constants.global_width) + 2
    end,
    height = function(_, vh)
      return math.ceil(vh * constants.global_height)
    end,
    col = function(vw, _)
      return math.floor((1 - constants.global_width) * 0.5 * vw) - 1
    end,
    row = function(_, vh)
      return math.floor((1 - constants.global_height) * 0.5 * vh)
    end,
  }

  local prompt = options.prompt or options.self or 'field'
  local tc_id = options.testcase_id or state.get_local_key 'assistant-cur-editing-id' or 1
  local title_label = string.format(' Testcase #%d %s | :w / <CR> to save | :q to cancel ', tc_id, prompt:upper())

  utils.create_window(patcher_window)

  state.set_local_key('assistant-patcher-window', patcher_window)
  state.set_local_key('assistant-patcher-canvas', self.canvas)

  utils.set_win_config(patcher_window.winid, {
    title = title_label,
    title_pos = 'center',
  })

  utils.set_buf_option(patcher_window, 'filetype', 'assistant-patcher')
  vim.bo[patcher_window.bufnr].buftype = 'acwrite'
  vim.b[patcher_window.bufnr].autoformat = false
  local dummy_name = string.format('assistant://patcher/%s_%d', prompt, patcher_window.bufnr)
  pcall(vim.api.nvim_buf_set_name, patcher_window.bufnr, dummy_name)

  utils.set_win_option(
    patcher_window,
    'winhighlight',
    table.concat({
      'Normal:AssistantNormal',
      'FloatBorder:AssistantBorder',
      'FloatTitle:AssistantTitle',
    }, ',')
  )

  local closed = false
  local function save_content(close_window)
    if not (patcher_window.bufnr and vim.api.nvim_buf_is_valid(patcher_window.bufnr)) then
      return
    end
    local lines = vim.api.nvim_buf_get_lines(patcher_window.bufnr, 0, -1, false)
    local full_text = table.concat(lines, '\n')
    vim.bo[patcher_window.bufnr].modified = false

    if close_window then
      closed = true
      utils.remove_window(patcher_window)
      state.set_local_key('assistant-patcher-window', nil)
      state.set_local_key('assistant-patcher-canvas', nil)
      utils.focus_panel()
    else
      utils.info('Saved ' .. prompt)
    end
    on_update(full_text, close_window)

    -- Refresh previewer canvas immediately if visible
    local pw = state.get_local_key 'assistant-previewer-window'
    local pc = state.get_local_key 'assistant-previewer-canvas'
    local tests = state.get_global_key 'tests'
    if pw and pc and tests and tests[tc_id] and pw.bufnr and vim.api.nvim_buf_is_valid(pw.bufnr) then
      pc:set(pw.bufnr, tests[tc_id])
    end
    state.persist()
  end

  utils.create_autocmd('WinClosed', {
    pattern = tostring(patcher_window.winid),
    callback = function()
      if not closed then
        closed = true
        if patcher_window.bufnr and vim.api.nvim_buf_is_valid(patcher_window.bufnr) and not vim.bo[patcher_window.bufnr].modified then
          local lines = vim.api.nvim_buf_get_lines(patcher_window.bufnr, 0, -1, false)
          local full_text = table.concat(lines, '\n')
          on_update(full_text, true)
        end
        utils.remove_window(patcher_window)
        state.set_local_key('assistant-patcher-window', nil)
        state.set_local_key('assistant-patcher-canvas', nil)
        utils.focus_panel()
      end
    end,
  })

  vim.api.nvim_create_autocmd('BufWriteCmd', {
    buffer = patcher_window.bufnr,
    callback = function()
      save_content(false)
    end,
  })

  utils.set_keymap {
    mode = 'n',
    lhs = '<cr>',
    rhs = function()
      save_content(true)
    end,
    options = {
      buffer = patcher_window.bufnr,
    },
  }

  vim.keymap.set({ 'n', 'i' }, '<C-s>', function()
    save_content(false)
  end, { buffer = patcher_window.bufnr, silent = true, desc = 'Save testcase' })

  vim.keymap.set('n', '<Esc>', function() end, { buffer = patcher_window.bufnr, silent = true, desc = 'Prevent accidental discard' })

  for mode, mappings in pairs(require('assistant.mappings').default_mappings.patcher or {}) do
    for k, v in pairs(mappings) do
      utils.set_keymap {
        mode = mode,
        lhs = k,
        rhs = v,
        options = {
          buffer = patcher_window.bufnr,
        },
      }
    end
  end

  self.canvas:set(patcher_window.bufnr, content)
end

return Patcher
