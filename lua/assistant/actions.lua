local Text = require 'assistant.lib.text'
local state = require 'assistant.state'
local utils = require 'assistant.utils'
local actions = {}

---@return number?
local function get_cur_testcase_ID()
  local panel_window = state.get_local_key 'assistant-panel-window' ---@type Assistant.Window
  local panel_canvas = state.get_local_key 'assistant-panel-canvas' ---@type Assistant.Canvas

  if not (panel_window and panel_window.bufnr and vim.api.nvim_buf_is_valid(panel_window.bufnr)) then
    return
  end

  return panel_canvas:get(panel_window.bufnr, panel_window.winid)
end

function actions.close_current()
  local match = string.match(vim.bo.filetype, '^[^-]+-(.+)$')

  if match then
    if vim.tbl_contains({ 'panel', 'previewer' }, match) then
      for _, window in ipairs {
        state.get_local_key 'assistant-panel-window',
        state.get_local_key 'assistant-previewer-window',
      } do
        utils.remove_window(window)
      end
    else
      utils.remove_window(state.get_local_key(string.format('assistant-%s-window', match)))
    end
  end
end

function actions.focus_panel()
  local panel_window = state.get_local_key 'assistant-panel-window'

  if panel_window and panel_window.winid and vim.api.nvim_win_is_valid(panel_window.winid) then
    vim.fn.win_gotoid(panel_window.winid)
  end
end

function actions.focus_previewer()
  local previewer_window = state.get_local_key 'assistant-previewer-window'

  if previewer_window and previewer_window.winid and vim.api.nvim_win_is_valid(previewer_window.winid) then
    vim.fn.win_gotoid(previewer_window.winid)
  end
end

function actions.run_testcases()
  local processor = require 'assistant.core.processor'
  local testcases = state.get_global_key 'tests' or {}
  if #testcases == 0 then
    utils.warn "No testcases to run. Press 'c' to create one."
    return
  end

  local selected = {}

  for i, testcase in ipairs(testcases) do
    if testcase.selected then
      table.insert(selected, i)
    end
  end

  if vim.tbl_isempty(selected) then
    local testcase_ID = get_cur_testcase_ID()

    if testcase_ID and testcases[testcase_ID] then
      processor.run_testcases { testcase_ID }
    else
      local all_ids = {}
      for i = 1, #testcases do
        table.insert(all_ids, i)
      end
      processor.run_testcases(all_ids)
    end
  else
    processor.run_testcases(selected)
  end
end

function actions.run_interactive()
  require('assistant.lib.terminal').new({ command = utils.get_source_config().execute }):spawn()
end

function actions.toggle_cur_selection()
  local testcase_ID = get_cur_testcase_ID()

  if testcase_ID then
    local testcase = state.get_global_key('tests')[testcase_ID]
    local panel_window = state.get_local_key 'assistant-panel-window'
    local panel_canvas = state.get_local_key 'assistant-panel-canvas'
    testcase.selected = not testcase.selected

    vim.schedule(function()
      panel_canvas:set(panel_window.bufnr, state.get_global_key 'tests')
    end)
  end
end

function actions.toggle_all_selection()
  local testcases = state.get_global_key 'tests'
  local all_selected = true

  for _, testcase in ipairs(testcases or {}) do
    if not testcase.selected then
      all_selected = false
      break
    end
  end

  local selected_ids = {}

  if all_selected then
    for i = 1, #testcases do
      table.insert(selected_ids, i)
      testcases[i].selected = false
    end
  else
    for i = 1, #testcases do
      if not testcases[i].selected then
        table.insert(selected_ids, i)
        testcases[i].selected = true
      end
    end
  end

  local panel_window = state.get_local_key 'assistant-panel-window'
  local panel_canvas = state.get_local_key 'assistant-panel-canvas'

  vim.schedule(function()
    panel_canvas:set(panel_window.bufnr, testcases)
  end)
end

local function patch_field(testcase_ID, field, on_done)
  local testcases = state.get_global_key 'tests'
  if not testcases or not testcases[testcase_ID] then
    return
  end

  state.set_local_key('assistant-cur-editing-id', testcase_ID)
  local cur_status = state.get_local_key 'status'
  if cur_status then
    cur_status.patcher = string.format('Patching(%s)', field)
  end

  require('assistant.builtins.__patcher').standard:update(
    testcases[testcase_ID][field] or '',
    { prompt = field, testcase_id = testcase_ID },
    function(content, is_done)
      testcases[testcase_ID][field] = content
      local pw = state.get_local_key 'assistant-previewer-window'
      local pc = state.get_local_key 'assistant-previewer-canvas'
      if pw and pc and pw.bufnr and vim.api.nvim_buf_is_valid(pw.bufnr) then
        pc:set(pw.bufnr, testcases[testcase_ID])
      end
      state.persist()
      if is_done ~= false and on_done then
        on_done()
      end
    end
  )
end

function actions.create_new_testcase()
  local panel_window = state.get_local_key 'assistant-panel-window'
  local panel_canvas = state.get_local_key 'assistant-panel-canvas'
  local tests = state.get_global_key 'tests'
  if not tests then
    tests = {}
    state.set_global_key('tests', tests)
  end

  table.insert(tests, { input = '', output = '' })
  local new_id = #tests

  if panel_window and panel_canvas and panel_window.bufnr and vim.api.nvim_buf_is_valid(panel_window.bufnr) then
    panel_canvas:set(panel_window.bufnr, tests)
    if panel_window.winid and vim.api.nvim_win_is_valid(panel_window.winid) then
      pcall(vim.api.nvim_win_set_cursor, panel_window.winid, { new_id, 0 })
    end
  end

  local pw = state.get_local_key 'assistant-previewer-window'
  local pc = state.get_local_key 'assistant-previewer-canvas'
  if pw and pc and pw.bufnr and vim.api.nvim_buf_is_valid(pw.bufnr) then
    pc:set(pw.bufnr, tests[new_id])
  end

  state.persist()

  -- Prompt editor for input first, followed by expected output
  vim.schedule(function()
    patch_field(new_id, 'input', function()
      vim.schedule(function()
        patch_field(new_id, 'output', function()
          utils.info(string.format('Testcase #%d saved!', new_id))
        end)
      end)
    end)
  end)
end

function actions.remove_testcases()
  local testcases = state.get_global_key 'tests' or {}
  local selected = {}

  for testcase_ID, testcase in ipairs(testcases) do
    if testcase.selected then
      table.insert(selected, testcase_ID)
    end
  end

  if vim.tbl_isempty(selected) then
    local testcase_ID = get_cur_testcase_ID()

    if testcase_ID then
      table.insert(selected, testcase_ID)
    end
  end

  table.sort(selected, function(a, b)
    return a > b
  end)

  for _, testcase_ID in ipairs(selected) do
    table.remove(testcases, testcase_ID)
  end

  local panel_window = state.get_local_key 'assistant-panel-window'
  local panel_canvas = state.get_local_key 'assistant-panel-canvas'

  if panel_window and panel_canvas and panel_window.bufnr and vim.api.nvim_buf_is_valid(panel_window.bufnr) then
    panel_canvas:set(panel_window.bufnr, testcases)
  end

  local cur_id = panel_canvas and panel_window and panel_canvas:get(panel_window.bufnr, panel_window.winid)
  local pw = state.get_local_key 'assistant-previewer-window'
  local pc = state.get_local_key 'assistant-previewer-canvas'
  if pw and pc and pw.bufnr and vim.api.nvim_buf_is_valid(pw.bufnr) then
    if cur_id and testcases[cur_id] then
      pc:set(pw.bufnr, testcases[cur_id])
    else
      pc:set(pw.bufnr, { input = '', output = '' })
    end
  end

  state.persist()
end

function actions.patch_testcase()
  local tests = state.get_global_key 'tests' or {}
  if #tests == 0 then
    actions.create_new_testcase()
    return
  end

  local testcase_ID = get_cur_testcase_ID() or 1
  if not tests[testcase_ID] then
    testcase_ID = 1
  end

  state.set_local_key('assistant-cur-editing-id', testcase_ID)
  local cur_status = state.get_local_key 'status'
  if cur_status then
    cur_status.picker = 'Picking(field)'
  end

  require('assistant.builtins.__picker').standard:pick({ 'input', 'output' }, { prompt = 'field' }, function(choice)
    patch_field(testcase_ID, choice)
  end)
end

function actions.which_key()
  local text = Text.new {}
  local mappings = require('assistant.mappings').default_mappings
  local gap = 5
  local mode_map = {
    n = 'Normal',
    i = 'Insert',
    v = 'Visual',
  }

  text:append('"MODE" | "KEY" | "ACTION"', 'AssistantBorder'):nl(2)

  for interface, mapping in pairs(mappings) do
    text:append(string.format(' %s ', interface) .. string.rep('─', 34), 'AssistantTitle'):nl()

    for mode, keys in pairs(mapping) do
      for k, v in pairs(keys) do
        local action_name = (type(v) == 'table' and type(v.get_name) == 'function' and v:get_name())
          or (type(v) == 'function' and '(custom)')
          or tostring(v)
        text
          :append('  ', 'AssistantBorder')
          :append(mode_map[mode] .. string.rep(' ', gap), 'AssistantBorder')
          :append('   ', 'AssistantHeading')
          :append(k .. string.rep(' ', 2 * gap - #k), 'AssistantHeading')
          :append(' 󱐌 ', 'String')
          :append(action_name, 'String')
          :nl()
      end
    end
    text:nl(2)
  end

  local cur_status = state.get_local_key 'status'
  if cur_status then
    cur_status.dialog = 'Which Key'
  end

  require('assistant.builtins.__dialog').standard:display(text, { prompt = 'Which Key ?' })
end

return require('assistant.lib.action').transform_mod(actions)
