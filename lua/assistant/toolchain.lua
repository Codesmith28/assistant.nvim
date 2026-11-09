local toolchain = {}

local cached = {
  cpp_compiler = nil,
  cpp_standard = nil,
  c_compiler = nil,
  python = nil,
}

---Find the most modern C++ compiler available on the system
---Checks versioned GCC (g++-25 down to g++-11), Homebrew, system paths, and clang++
---@return string
function toolchain.find_cpp_compiler()
  if cached.cpp_compiler then
    return cached.cpp_compiler
  end

  -- Search versioned g++ binaries first (prefer modern GCC)
  for v = 25, 11, -1 do
    local versioned = {
      string.format('/opt/homebrew/bin/g++-%d', v),
      string.format('/usr/local/bin/g++-%d', v),
      string.format('/usr/bin/g++-%d', v),
      string.format('g++-%d', v),
    }
    for _, path in ipairs(versioned) do
      if vim.fn.executable(path) == 1 then
        cached.cpp_compiler = path
        return path
      end
    end
  end

  -- Fallbacks to standard g++ and clang++
  local fallbacks = {
    '/opt/homebrew/bin/g++',
    '/usr/local/bin/g++',
    '/usr/bin/g++',
    'g++',
    '/opt/homebrew/bin/clang++',
    '/usr/local/bin/clang++',
    '/usr/bin/clang++',
    'clang++',
  }

  for _, path in ipairs(fallbacks) do
    if vim.fn.executable(path) == 1 then
      cached.cpp_compiler = path
      return path
    end
  end

  cached.cpp_compiler = 'g++'
  return 'g++'
end

---Detect the highest supported modern C++ standard flag
---@param compiler? string
---@return string
function toolchain.detect_cpp_standard(compiler)
  if cached.cpp_standard and not compiler then
    return cached.cpp_standard
  end

  compiler = compiler or toolchain.find_cpp_compiler()

  -- If versioned name like g++-14, extract version number directly
  local ver_match = compiler:match('g%+%+%-?(%d+)')
  local major = tonumber(ver_match)

  -- Otherwise probe compiler dumpversion
  if not major and vim.fn.executable(compiler) == 1 then
    local out = vim.fn.system(string.format('%s -dumpversion 2>/dev/null', compiler))
    if out and out ~= '' then
      major = tonumber(out:match('^(%d+)'))
    end
  end

  local standard = '-std=c++20'
  if major then
    if major >= 14 then
      standard = '-std=c++26'
    elseif major >= 11 then
      standard = '-std=c++23'
    elseif major >= 10 then
      standard = '-std=c++20'
    else
      standard = '-std=c++17'
    end
  end

  if not compiler then
    cached.cpp_standard = standard
  end
  return standard
end

---Find the most modern C compiler available on the system
---@return string
function toolchain.find_c_compiler()
  if cached.c_compiler then
    return cached.c_compiler
  end

  for v = 25, 11, -1 do
    local versioned = {
      string.format('/opt/homebrew/bin/gcc-%d', v),
      string.format('/usr/local/bin/gcc-%d', v),
      string.format('/usr/bin/gcc-%d', v),
      string.format('gcc-%d', v),
    }
    for _, path in ipairs(versioned) do
      if vim.fn.executable(path) == 1 then
        cached.c_compiler = path
        return path
      end
    end
  end

  local fallbacks = {
    '/opt/homebrew/bin/gcc',
    '/usr/local/bin/gcc',
    '/usr/bin/gcc',
    'gcc',
    '/opt/homebrew/bin/clang',
    '/usr/local/bin/clang',
    '/usr/bin/clang',
    'clang',
  }

  for _, path in ipairs(fallbacks) do
    if vim.fn.executable(path) == 1 then
      cached.c_compiler = path
      return path
    end
  end

  cached.c_compiler = 'gcc'
  return 'gcc'
end

---Find python interpreter
---@return string
function toolchain.find_python()
  if cached.python then
    return cached.python
  end

  local candidates = {
    'python3',
    '/opt/homebrew/bin/python3',
    '/usr/local/bin/python3',
    '/usr/bin/python3',
    'python',
  }

  for _, path in ipairs(candidates) do
    if vim.fn.executable(path) == 1 then
      cached.python = path
      return path
    end
  end

  cached.python = 'python3'
  return 'python3'
end

---Build comprehensive default language configurations for competitive programming
---@param out_dir? string
---@return table<string, Assistant.Processor.SourceConfig>
function toolchain.get_default_commands(out_dir)
  out_dir = out_dir or '.bin'
  local cpp_compiler = toolchain.find_cpp_compiler()
  local cpp_std = toolchain.detect_cpp_standard(cpp_compiler)
  local c_compiler = toolchain.find_c_compiler()
  local py = toolchain.find_python()

  local commands = {
    cpp = {
      extension = 'cpp',
      compile = {
        main = cpp_compiler,
        args = {
          cpp_std,
          '-Wall',
          '-Wextra',
          '-D_GLIBCXX_DEBUG',
          '$FILENAME_WITH_EXTENSION',
          '-o',
          string.format('./%s/$FILENAME_WITHOUT_EXTENSION', out_dir),
        },
      },
      execute = {
        main = string.format('./%s/$FILENAME_WITHOUT_EXTENSION', out_dir),
        args = {},
      },
    },
    c = {
      extension = 'c',
      compile = {
        main = c_compiler,
        args = {
          '-std=c23',
          '-Wall',
          '-Wextra',
          '$FILENAME_WITH_EXTENSION',
          '-o',
          string.format('./%s/$FILENAME_WITHOUT_EXTENSION', out_dir),
        },
      },
      execute = {
        main = string.format('./%s/$FILENAME_WITHOUT_EXTENSION', out_dir),
        args = {},
      },
    },
    python = {
      extension = 'py',
      compile = nil,
      execute = {
        main = py,
        args = { '$FILENAME_WITH_EXTENSION' },
      },
    },
  }

  -- If rustc is available, add rust support automatically
  if vim.fn.executable('rustc') == 1 then
    commands.rust = {
      extension = 'rs',
      compile = {
        main = 'rustc',
        args = {
          '-O',
          '$FILENAME_WITH_EXTENSION',
          '-o',
          string.format('./%s/$FILENAME_WITHOUT_EXTENSION', out_dir),
        },
      },
      execute = {
        main = string.format('./%s/$FILENAME_WITHOUT_EXTENSION', out_dir),
        args = {},
      },
    }
  end

  return commands
end

return toolchain
