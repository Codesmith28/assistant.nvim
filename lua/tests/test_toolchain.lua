local test = require 'mini.test'
local toolchain = require 'assistant.toolchain'
local config = require 'assistant.config'

local T = test.new_set()

T['toolchain cpp compiler discovery'] = function()
  local compiler = toolchain.find_cpp_compiler()
  test.expect.equality(type(compiler), 'string')
  test.expect.equality(#compiler > 0, true)
end

T['toolchain standard detection'] = function()
  local std = toolchain.detect_cpp_standard()
  test.expect.equality(type(std), 'string')
  test.expect.equality(string.match(std, '^-std=c%+%+') ~= nil, true)
end

T['toolchain default commands'] = function()
  local commands = toolchain.get_default_commands('.ast/bin')
  test.expect.equality(type(commands.cpp), 'table')
  test.expect.equality(type(commands.cpp.compile), 'table')
  test.expect.equality(type(commands.cpp.compile.main), 'string')
  test.expect.equality(type(commands.cpp.compile.args), 'table')
  test.expect.equality(type(commands.cpp.execute), 'table')
  test.expect.equality(type(commands.python), 'table')
end

T['config auto defaults with toolchain'] = function()
  config.overwrite()
  test.expect.equality(config.values.core.default_source, 'cpp')
  test.expect.equality(config.values.core.out_dir, '.ast/bin')
  test.expect.equality(type(config.values.commands.cpp), 'table')
  test.expect.equality(type(config.values.commands.cpp.compile.args), 'table')
end

return T
