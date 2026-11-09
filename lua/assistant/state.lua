local state = {}
local HashTable = { local_data = {}, global_data = {} }

-- Persistent tracking of last active source file across buffer changes
local last_tracked = {
  filedir = nil,
  filename = nil,
  filepath = nil,
  extension = nil,
  filetype = nil,
  source_buf = nil,
}

function state.set_global_key(key, value)
  HashTable.global_data[key] = value
end

function state.get_global_key(key)
  return HashTable.global_data[key]
end

function state.set_local_key(key, value)
  HashTable.local_data[key] = value
  if last_tracked[key] ~= nil then
    last_tracked[key] = value
  end
end

function state.get_local_key(key)
  local val = HashTable.local_data[key]
  if val ~= nil then
    return val
  end
  return last_tracked[key]
end

---Track active source code buffer
---@param bufnr? integer
function state.track_source(bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  if not (bufnr and vim.api.nvim_buf_is_valid(bufnr)) then
    return
  end

  local name = vim.api.nvim_buf_get_name(bufnr)
  local ft = vim.bo[bufnr].filetype
  if name and name ~= '' and not string.match(name:lower(), 'assistant') and not string.match(ft:lower(), '^assistant') then
    last_tracked.filedir = vim.fn.fnamemodify(name, ':p:h')
    last_tracked.filename = vim.fn.fnamemodify(name, ':t:r')
    last_tracked.filepath = vim.fn.fnamemodify(name, ':p')
    last_tracked.extension = vim.fn.fnamemodify(name, ':e')
    last_tracked.filetype = ft
    last_tracked.source_buf = bufnr

    for k, v in pairs(last_tracked) do
      HashTable.local_data[k] = v
    end
  end
end

---Immediately save tests to disk
function state.persist()
  local tests = HashTable.global_data.tests
  if not tests or vim.tbl_isempty(tests) then
    return
  end

  local fs = require 'assistant.core.fs'
  local filepath = fs.get_state_filepath()
  if filepath and filepath ~= '' then
    fs.write(filepath, vim.json.encode(HashTable.global_data))
  end
end

function state.sync_and_clean()
  state.persist()

  -- Reset global data and ephemeral UI local data, keeping tracked file info
  HashTable.global_data = {}
  HashTable.local_data = {
    filedir = last_tracked.filedir,
    filename = last_tracked.filename,
    filepath = last_tracked.filepath,
    extension = last_tracked.extension,
    filetype = last_tracked.filetype,
    source_buf = last_tracked.source_buf,
  }
end

return state
