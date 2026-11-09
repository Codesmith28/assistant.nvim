local state = require 'assistant.state'
local fs = {}
local luv = vim.uv or vim.loop

---@return string
function fs.get_file_dir()
  local filedir = state.get_local_key 'filedir'
  if filedir and filedir ~= '' and filedir ~= '/' and vim.fn.isdirectory(filedir) == 1 then
    return filedir
  end

  local filepath = state.get_local_key 'filepath'
  if filepath and filepath ~= '' then
    local pdir = vim.fn.fnamemodify(filepath, ':p:h')
    if pdir and pdir ~= '' and vim.fn.isdirectory(pdir) == 1 then
      return pdir
    end
  end

  local cur_buf_dir = vim.fn.expand '%:p:h'
  if cur_buf_dir and cur_buf_dir ~= '' and cur_buf_dir ~= '/' and vim.fn.isdirectory(cur_buf_dir) == 1 then
    return cur_buf_dir
  end

  local cwd = luv.cwd()
  return (cwd and cwd ~= '/') and cwd or vim.fn.expand '~'
end

---@return string|nil
function fs.find_root()
  local filedir = fs.get_file_dir()
  local start_dir = (filedir and filedir ~= '' and filedir ~= '/' and vim.fn.isdirectory(filedir) == 1) and filedir or luv.cwd()

  local current_dir = start_dir
  while current_dir and current_dir ~= '/' and current_dir ~= '.' do
    local ast_dir = string.format('%s/%s', current_dir, '.ast')
    if vim.fn.isdirectory(ast_dir) == 1 then
      return current_dir
    end
    local parent = vim.fn.fnamemodify(current_dir, ':h')
    if parent == current_dir or parent == '/' then
      break
    end
    current_dir = parent
  end

  return nil
end

---@return string
function fs.make_root()
  local target_dir = fs.get_file_dir()
  if not target_dir or target_dir == '' or target_dir == '/' then
    target_dir = luv.cwd() or vim.fn.expand '~'
  end

  local ast_path = string.format('%s/.ast', target_dir)
  if vim.fn.isdirectory(ast_path) == 0 then
    vim.fn.mkdir(ast_path, 'p')
  end

  return target_dir
end

---@return string|nil
function fs.get_state_filepath()
  local fname = state.get_local_key 'filename'
  if not fname or fname == '' then
    fname = vim.fn.expand '%:t:r'
  end

  if not fname or fname == '' or fname == '.' then
    return nil
  end

  local root_dir = fs.find_root() or fs.make_root()
  if not root_dir or root_dir == '/' then
    return nil
  end

  return string.format('%s/.ast/%s.json', root_dir, fname)
end

---@param path string
---@return string?
function fs.read(path)
  local fd, _ = luv.fs_open(path, 'r', 420)

  if not fd then
    return
  end

  local stat = luv.fs_fstat(fd)
  local file_size = stat and stat.size or 0
  local data = luv.fs_read(fd, file_size)
  luv.fs_close(fd)
  return data
end

---@param path string
---@param bytes string
function fs.write(path, bytes)
  local fd, _ = luv.fs_open(path, 'w', 438)

  if not fd then
    print('[ERROR]: can\'t open file', path)
    return
  end

  luv.fs_write(fd, bytes)
  luv.fs_close(fd)
end

return fs
