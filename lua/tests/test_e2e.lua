local test = require 'mini.test'
local assistant = require 'assistant'
local config = require 'assistant.config'
local fs = require 'assistant.core.fs'
local state = require 'assistant.state'
local utils = require 'assistant.utils'
local toolchain = require 'assistant.toolchain'
local actions = require 'assistant.actions'
local wizard_mod = require 'assistant.builtins.__wizard'
local Patcher = require 'assistant.lib.patcher'
local Canvas = require 'assistant.lib.canvas'

local T = test.new_set()

-- =========================================================================
-- Smart Toolchain Auto-Discovery
-- =========================================================================
T['smart toolchain auto-discovery'] = function()
  -- Reset config to auto-discovered defaults
  config.overwrite({})

  -- 1. Compiler discovery
  local cpp_cmd = config.values.commands.cpp
  test.expect.equality(type(cpp_cmd), 'table')
  test.expect.equality(type(cpp_cmd.compile.main), 'string')
  test.expect.equality(vim.fn.executable(cpp_cmd.compile.main), 1)

  -- 2. C++ standard detection
  local std_arg = cpp_cmd.compile.args[1]
  test.expect.equality(type(std_arg), 'string')
  test.expect.equality(string.match(std_arg, '^-std=c%+%+%d+') ~= nil, true)

  -- 3. Verify CP recommended flags
  local args_str = table.concat(cpp_cmd.compile.args, ' ')
  test.expect.equality(string.match(args_str, '%-Wall') ~= nil, true)
  test.expect.equality(string.match(args_str, '%-Wextra') ~= nil, true)
  test.expect.equality(string.match(args_str, '%-D_GLIBCXX_DEBUG') ~= nil, true)
  test.expect.equality(string.match(args_str, '%$OUT_DIR') ~= nil, true)

  -- 4. Test version mapping logic directly
  test.expect.equality(toolchain.detect_cpp_standard('g++-16'), '-std=c++26')
  test.expect.equality(toolchain.detect_cpp_standard('g++-14'), '-std=c++26')
  test.expect.equality(toolchain.detect_cpp_standard('g++-13'), '-std=c++23')
  test.expect.equality(toolchain.detect_cpp_standard('g++-11'), '-std=c++23')
  test.expect.equality(toolchain.detect_cpp_standard('g++-10'), '-std=c++20')
  test.expect.equality(toolchain.detect_cpp_standard('g++-9'), '-std=c++17')

  -- 5. Python discovery
  test.expect.equality(type(config.values.commands.python), 'table')
  test.expect.equality(type(config.values.commands.python.execute.main), 'string')
end

-- =========================================================================
-- Native Buffer Writing
-- =========================================================================
T['native buffer writing'] = function()
  local dummy_canvas = Canvas.new {
    fn = function(bufnr, content)
      if type(content) == 'string' then
        vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, vim.split(content, '\n'))
      end
    end,
  }
  local patcher = Patcher.new { canvas = dummy_canvas }

  local updated_content = nil
  patcher:update('initial_content', { prompt = 'input', testcase_id = 1 }, function(new_content)
    updated_content = new_content
  end)

  local pw = state.get_local_key 'assistant-patcher-window'
  test.expect.equality(pw ~= nil, true)
  test.expect.equality(vim.api.nvim_buf_is_valid(pw.bufnr), true)

  -- Verify buftype is 'acwrite'
  test.expect.equality(vim.bo[pw.bufnr].buftype, 'acwrite')

  -- Verify buffer name format
  local bname = vim.api.nvim_buf_get_name(pw.bufnr)
  test.expect.equality(string.match(bname, '^assistant://patcher/input_') ~= nil, true)

  -- Set new lines in patcher
  vim.api.nvim_buf_set_lines(pw.bufnr, 0, -1, false, { 'line 1', 'line 2' })

  -- Trigger native :write (BufWriteCmd)
  vim.api.nvim_exec_autocmds('BufWriteCmd', { buffer = pw.bufnr })

  -- Verify updated content and modified flag
  test.expect.equality(updated_content, 'line 1\nline 2')
  test.expect.equality(vim.bo[pw.bufnr].modified, false)

  -- Close window
  utils.remove_window(pw)
end

-- =========================================================================
-- Seamless Testcase Creation
-- =========================================================================
T['seamless testcase creation'] = function()
  state.set_global_key('tests', {})
  test.expect.equality(#state.get_global_key('tests'), 0)

  -- Mock patcher standard update to simulate user saving input then output
  local patcher_mod = require 'assistant.builtins.__patcher'
  local original_update = patcher_mod.standard.update

  local step = 0
  patcher_mod.standard.update = function(self, content, opts, on_update)
    step = step + 1
    if opts.prompt == 'input' then
      on_update('42\n')
    elseif opts.prompt == 'output' then
      on_update('84\n')
    end
  end

  actions.create_new_testcase()

  -- Wait for scheduled sequential prompts to complete
  vim.wait(300, function()
    local tests = state.get_global_key 'tests'
    return tests and tests[1] and tests[1].input == '42\n' and tests[1].output == '84\n'
  end)

  local tests = state.get_global_key 'tests'
  test.expect.equality(#tests, 1)
  test.expect.equality(tests[1].input, '42\n')
  test.expect.equality(tests[1].output, '84\n')

  -- Restore original patcher update
  patcher_mod.standard.update = original_update
end

-- =========================================================================
-- Smart Root Detection
-- =========================================================================
T['smart root detection'] = function()
  local test_base = '/tmp/e2e_root_test_' .. tostring(os.time())
  local nested_dir = test_base .. '/contest/div2'
  vim.fn.mkdir(nested_dir, 'p')

  -- Test Case A: No .ast yet -> make_root creates .ast in source file directory
  state.set_local_key('filedir', nested_dir)
  state.set_local_key('filename', 'problemA')

  local resolved_dir = fs.make_root()
  test.expect.equality(resolved_dir, nested_dir)
  test.expect.equality(vim.fn.isdirectory(nested_dir .. '/.ast'), 1)
  test.expect.equality(vim.fn.isdirectory(nested_dir .. '/.ast/bin'), 1)

  local bin_path = fs.get_bin_dir()
  test.expect.equality(bin_path, nested_dir .. '/.ast/bin')

  local state_path = fs.get_state_filepath()
  test.expect.equality(state_path, nested_dir .. '/.ast/problemA.json')

  -- Test Case B: Existing .ast in ancestor directory
  local ancestor_dir = test_base .. '/contest'
  vim.fn.mkdir(ancestor_dir .. '/.ast', 'p')
  vim.fn.delete(nested_dir .. '/.ast', 'rf') -- remove nested .ast

  state.set_local_key('filedir', nested_dir)
  local found_root = fs.find_root()
  test.expect.equality(found_root, ancestor_dir)

  local ancestor_bin_path = fs.get_bin_dir()
  test.expect.equality(ancestor_bin_path, ancestor_dir .. '/.ast/bin')
  test.expect.equality(vim.fn.isdirectory(ancestor_dir .. '/.ast/bin'), 1)

  local ancestor_state_path = fs.get_state_filepath()
  test.expect.equality(ancestor_state_path, ancestor_dir .. '/.ast/problemA.json')

  -- Cleanup
  vim.fn.delete(test_base, 'rf')
end

-- =========================================================================
-- Native Binary Output Support
-- =========================================================================
T['native binary output support'] = function()
  local test_root = '/tmp/e2e_bin_test_' .. tostring(os.time())
  local sub_dir = test_root .. '/src'
  vim.fn.mkdir(sub_dir, 'p')

  local src_file = sub_dir .. '/solver.cpp'
  local code = '#include <iostream>\nint main() { std::cout << "E2E_BINARY_OK" << std::endl; return 0; }\n'
  local fd = io.open(src_file, 'w')
  fd:write(code)
  fd:close()

  -- Save current cwd and change into test_root
  local orig_cwd = vim.fn.getcwd()
  vim.api.nvim_set_current_dir(test_root)

  state.set_local_key('filedir', sub_dir)
  state.set_local_key('filename', 'solver')
  state.set_local_key('extension', 'cpp')
  state.set_local_key('filetype', 'cpp')

  config.overwrite({ core = { out_dir = '.ast/bin' } })

  -- 1. Verify ensure_out_dir creates .ast/bin in both sub_dir and cwd
  utils.ensure_out_dir('.ast/bin')
  test.expect.equality(vim.fn.isdirectory(sub_dir .. '/.ast/bin'), 1)
  test.expect.equality(vim.fn.isdirectory(test_root .. '/.ast/bin'), 1)

  -- 2. Verify get_source_config adjusts relative paths
  local cmd = utils.get_source_config()
  test.expect.equality(type(cmd), 'table')

  -- Compile binary using detected compiler within cmd.cwd
  local compile_cmd = string.format('cd %s && %s %s', vim.fn.shellescape(cmd.cwd), cmd.compile.main, table.concat(cmd.compile.args, ' '))
  local compile_res = vim.fn.system(compile_cmd)
  test.expect.equality(vim.v.shell_error, 0)

  -- 3. Verify binary exists in sub_dir/.ast/bin/solver
  test.expect.equality(vim.fn.filereadable(sub_dir .. '/.ast/bin/solver'), 1)

  -- 4. Execute binary within cmd.cwd and verify output
  local exec_cmd = string.format('cd %s && %s', vim.fn.shellescape(cmd.cwd), cmd.execute.main)
  local exec_res = vim.fn.system(exec_cmd)
  test.expect.equality(vim.v.shell_error, 0)
  test.expect.equality(string.match(exec_res, 'E2E_BINARY_OK') ~= nil, true)

  -- Restore cwd and cleanup
  vim.api.nvim_set_current_dir(orig_cwd)
  vim.fn.delete(test_root, 'rf')
end

-- =========================================================================
-- Competitive Companion Auto-Source
-- =========================================================================
T['competitive companion auto-source'] = function()
  config.overwrite({ core = { default_source = 'cpp' } })

  -- Verify picker:pick auto-selects if options.prompt == 'source' and default_source is set
  local picker = require('assistant.builtins.__picker').standard
  local chosen = nil
  picker:pick({ 'cpp', 'python' }, { prompt = 'source', auto_select = true }, function(sel)
    chosen = sel
  end)

  test.expect.equality(chosen, 'cpp')

  -- Single source candidate auto-select
  local single_chosen = nil
  picker:pick({ 'cpp' }, { prompt = 'source' }, function(sel)
    single_chosen = sel
  end)
  test.expect.equality(single_chosen, 'cpp')
end

-- =========================================================================
-- Buffer Safety
-- =========================================================================
T['buffer safety'] = function()
  local buf = vim.api.nvim_create_buf(false, false)
  vim.api.nvim_buf_set_name(buf, 'assistant://panel/test')
  vim.bo[buf].filetype = 'assistant-panel'
  vim.bo[buf].modifiable = false

  -- Trigger BufWinEnter event
  vim.api.nvim_exec_autocmds('BufWinEnter', { buffer = buf })

  test.expect.equality(vim.b[buf].autoformat, false)
  local clients = vim.lsp.get_clients({ bufnr = buf })
  test.expect.equality(#clients, 0)

  vim.api.nvim_buf_delete(buf, { force = true })
end

-- =========================================================================
-- Immediate Disk Persistence
-- =========================================================================
T['immediate disk persistence'] = function()
  local tmp_dir = '/tmp/e2e_persist_test_' .. tostring(os.time())
  vim.fn.mkdir(tmp_dir, 'p')

  state.set_local_key('filedir', tmp_dir)
  state.set_local_key('filename', 'persist_prob')

  -- Create and persist
  state.set_global_key('tests', { { input = 'in1', output = 'out1' } })
  state.persist()

  local filepath = fs.get_state_filepath()
  test.expect.equality(vim.fn.filereadable(filepath), 1)

  local raw = fs.read(filepath)
  local decoded = vim.json.decode(raw or '{}')
  test.expect.equality(#decoded.tests, 1)
  test.expect.equality(decoded.tests[1].input, 'in1')

  -- Update and persist
  decoded.tests[1].output = 'out_updated'
  state.set_global_key('tests', decoded.tests)
  state.persist()

  local raw_up = fs.read(filepath)
  local dec_up = vim.json.decode(raw_up or '{}')
  test.expect.equality(dec_up.tests[1].output, 'out_updated')

  vim.fn.delete(tmp_dir, 'rf')
end

-- =========================================================================
-- UI Polish (Empty State & Footer)
-- =========================================================================
T['ui polish'] = function()
  -- Show wizard with empty tests
  state.set_global_key('tests', {})
  state.set_local_key('filename', 'ui_test')

  wizard_mod.standard:show()

  local panel_w = state.get_local_key 'assistant-panel-window'
  test.expect.equality(panel_w ~= nil, true)
  test.expect.equality(vim.api.nvim_win_is_valid(panel_w.winid), true)

  -- Check footer configuration
  local win_cfg = vim.api.nvim_win_get_config(panel_w.winid)
  test.expect.equality(type(win_cfg.footer), 'table')
  -- Flatten footer
  local footer_text = ''
  for _, chunk in ipairs(win_cfg.footer) do
    footer_text = footer_text .. chunk[1]
  end
  test.expect.equality(string.match(footer_text, '%[c%] new') ~= nil, true)
  test.expect.equality(string.match(footer_text, '%[r%] run') ~= nil, true)
  test.expect.equality(string.match(footer_text, '%[d%] delete') ~= nil, true)

  -- Check empty state text rendered in buffer
  local lines = vim.api.nvim_buf_get_lines(panel_w.bufnr, 0, -1, false)
  local full_panel = table.concat(lines, '\n')
  test.expect.equality(string.match(full_panel, 'No testcases found') ~= nil, true)
  test.expect.equality(string.match(full_panel, 'Press c to create a testcase') ~= nil, true)
  test.expect.equality(string.match(full_panel, 'Press %? for keybindings') ~= nil, true)

  wizard_mod.standard:hide()
end

-- =========================================================================
-- Testcase Pane Focus Retention (Edit / Write Testcases)
-- =========================================================================
T['testcase pane focus retention'] = function()
  state.set_global_key('tests', {})
  state.set_local_key('filename', 'focus_test')

  wizard_mod.standard:show()

  local panel_w = state.get_local_key 'assistant-panel-window'
  test.expect.equality(panel_w ~= nil, true)
  test.expect.equality(vim.api.nvim_win_is_valid(panel_w.winid), true)

  -- Mock patcher standard update to simulate user saving input then output
  local patcher_mod = require 'assistant.builtins.__patcher'
  local original_update = patcher_mod.standard.update

  patcher_mod.standard.update = function(self, content, opts, on_update)
    if opts.prompt == 'input' then
      on_update('10\n', true)
    elseif opts.prompt == 'output' then
      on_update('20\n', true)
    end
  end

  -- 1. Verify create_new_testcase restores focus to panel
  actions.create_new_testcase()

  vim.wait(300, function()
    local tests = state.get_global_key 'tests'
    return tests and tests[1] and tests[1].input == '10\n' and tests[1].output == '20\n'
  end)

  test.expect.equality(vim.api.nvim_get_current_win(), panel_w.winid)

  -- 2. Verify patch_testcase restores focus to panel
  actions.patch_testcase()
  local picker_w = state.get_local_key 'assistant-picker-window'
  test.expect.equality(picker_w ~= nil, true)

  -- Select 'both' in picker (triggers mock patcher for input then output)
  actions.close_current()
  test.expect.equality(vim.api.nvim_get_current_win(), panel_w.winid)

  -- Restore original patcher update
  patcher_mod.standard.update = original_update

  wizard_mod.standard:hide()
end

return T
