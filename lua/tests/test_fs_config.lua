local test = require 'mini.test'
local config = require 'assistant.config'
local fs = require 'assistant.core.fs'
local state = require 'assistant.state'
local utils = require 'assistant.utils'

local T = test.new_set()

T['config initialization and overwrite'] = function()
  test.expect.equality(type(config.values), 'table')
  test.expect.equality(type(config.values.commands), 'table')

  config.overwrite {
    core = {
      default_source = 'cpp',
      out_dir = '.bin',
    },
    commands = {
      cpp = {
        extension = 'cpp',
        compile = {
          main = 'g++',
          args = { '$FILENAME_WITH_EXTENSION', '-o', '.bin/$FILENAME_WITHOUT_EXTENSION' },
        },
        execute = {
          main = './.bin/$FILENAME_WITHOUT_EXTENSION',
          args = {},
        },
      },
    },
  }

  test.expect.equality(config.values.core.default_source, 'cpp')
  test.expect.equality(config.values.core.out_dir, '.bin')
  test.expect.equality(config.values.commands.python, nil)
  test.expect.equality(type(config.values.commands.cpp), 'table')
end

T['state source tracking'] = function()
  local buf = vim.api.nvim_create_buf(false, false)
  vim.api.nvim_buf_set_name(buf, '/tmp/test_problem/solution.cpp')
  vim.bo[buf].filetype = 'cpp'

  state.track_source(buf)

  test.expect.equality(state.get_local_key 'filename', 'solution')
  test.expect.equality(state.get_local_key 'extension', 'cpp')
  test.expect.equality(state.get_local_key 'filedir', '/tmp/test_problem')
  test.expect.equality(state.get_local_key 'filetype', 'cpp')

  vim.api.nvim_buf_delete(buf, { force = true })
end

T['fs get_state_filepath'] = function()
  state.set_local_key('filename', 'problem_a')
  state.set_local_key('filedir', '/tmp/test_problem')
  local path = fs.get_state_filepath()
  test.expect.equality(type(path), 'string')
  test.expect.equality(string.match(path, 'problem_a%.json$') ~= nil, true)
end

T['utils get_source_config formatting'] = function()
  state.set_local_key('filename', 'test_solution')
  state.set_local_key('extension', 'cpp')
  state.set_local_key('filetype', 'cpp')

  local cmd = utils.get_source_config()
  test.expect.equality(type(cmd), 'table')
  test.expect.equality(type(cmd.compile), 'table')
  test.expect.equality(type(cmd.execute), 'table')
end

return T
