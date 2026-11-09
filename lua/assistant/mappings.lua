local actions = require 'assistant.actions'
local config = require 'assistant.config'
local mappings = {}

mappings.default_mappings = {
  picker = {
    n = {
      ['?'] = actions.which_key,
      ['q'] = actions.close_current,
      ['<ESC>'] = actions.close_current,
      ['<C-c>'] = actions.close_current,
    },
  },
  panel = {
    n = {
      ['?'] = actions.which_key,
      ['q'] = actions.close_current,
      ['<ESC>'] = actions.close_current,
      ['<C-c>'] = actions.close_current,
      ['<CR>'] = actions.patch_testcase,
      ['<cr>'] = actions.patch_testcase,
      ['i'] = actions.run_interactive,
      ['r'] = actions.run_testcases,
      ['s'] = actions.toggle_cur_selection,
      ['a'] = actions.toggle_all_selection,
      ['c'] = actions.create_new_testcase,
      ['o'] = actions.create_new_testcase,
      ['d'] = actions.remove_testcases,
      ['e'] = actions.patch_testcase,
      ['<C-l>'] = actions.focus_previewer,
    },
  },
  previewer = {
    n = {
      ['?'] = actions.which_key,
      ['q'] = actions.close_current,
      ['<ESC>'] = actions.close_current,
      ['<C-c>'] = actions.close_current,
      ['<CR>'] = actions.patch_testcase,
      ['<cr>'] = actions.patch_testcase,
      ['e'] = actions.patch_testcase,
      ['<C-h>'] = actions.focus_panel,
    },
  },
  dialog = {
    n = {
      ['?'] = actions.which_key,
      ['q'] = actions.close_current,
      ['<ESC>'] = actions.close_current,
      ['<C-c>'] = actions.close_current,
    },
  },
  patcher = {
    n = {
      ['?'] = actions.which_key,
      ['q'] = actions.close_current,
      ['<ESC>'] = function() end,
      ['<esc>'] = function() end,
      ['<C-c>'] = actions.close_current,
    },
  },
}

local user_mappings = (config.values and config.values.mappings) or {}
if not vim.tbl_isempty(user_mappings) then
  for window, map_group in pairs(user_mappings) do
    for mode, mapping in pairs(map_group) do
      for k, v in pairs(mapping) do
        mappings.default_mappings[window][mode][k] = v
      end
    end
  end
end

return mappings
