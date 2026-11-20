local luv = vim.uv or vim.loop
local tcp = {}
local server = nil ---@type uv.uv_tcp_t?
local active_clients = {} ---@type table<uv.uv_tcp_t, boolean>

---Get the absolute path to the assistant server lockfile
---@return string
function tcp.get_lockfile_path()
  return vim.fn.stdpath('state') .. '/assistant_server.json'
end

---Read and parse the lockfile contents if present
---@return table?
function tcp.read_lockfile()
  local path = tcp.get_lockfile_path()
  local ok, f = pcall(io.open, path, 'r')
  if not ok or not f then
    return nil
  end
  local content = f:read('*a')
  f:close()
  if not content or content == '' then
    return nil
  end
  local ok_dec, data = pcall(vim.json.decode, content)
  if ok_dec and type(data) == 'table' then
    return data
  end
  return nil
end

---Write server metadata to the lockfile
---@param port integer
---@return boolean
function tcp.write_lockfile(port)
  local path = tcp.get_lockfile_path()
  local dir = vim.fn.fnamemodify(path, ':h')
  if vim.fn.isdirectory(dir) == 0 then
    pcall(vim.fn.mkdir, dir, 'p')
  end
  local ok, f = pcall(io.open, path, 'w')
  if ok and f then
    local payload = {
      pid = vim.fn.getpid(),
      port = port,
      cwd = vim.fn.getcwd(),
    }
    f:write(vim.json.encode(payload))
    f:close()
    return true
  end
  return false
end

---Delete the lockfile if it belongs to the current process or if forced
---@param force? boolean
---@return boolean
function tcp.delete_lockfile(force)
  local path = tcp.get_lockfile_path()
  local lock = tcp.read_lockfile()
  if force or (lock and lock.pid == vim.fn.getpid()) then
    pcall(os.remove, path)
    return true
  end
  return false
end

---Check if a process with the given PID is currently alive
---@param pid? integer
---@return boolean
function tcp.is_pid_running(pid)
  if not pid or type(pid) ~= 'number' or pid <= 0 then
    return false
  end
  local ok = luv.kill(pid, 0)
  return ok == 0
end

---Check if a TCP port is currently listening (without sending shutdown or hostile payloads)
---@param host string
---@param port integer
---@param callback fun(in_use: boolean)
function tcp.is_port_in_use(host, port, callback)
  local check = luv.new_tcp()
  if not check then
    vim.schedule(function()
      callback(false)
    end)
    return
  end

  check:connect(host, port, function(err)
    if not luv.is_closing(check) then
      check:close()
    end
    vim.schedule(function()
      if err then
        callback(false)
      else
        callback(true)
      end
    end)
  end)
end

---Check if the TCP server is running in the current Neovim instance
---@return boolean
function tcp.is_server_running()
  return server ~= nil and not luv.is_closing(server)
end

---Stop the TCP server, close open client connections, and clean up lockfile
---@param callback? fun(stopped: boolean)
---@param silent? boolean
function tcp.stop_server(callback, silent)
  local utils = require 'assistant.utils'

  -- Close all active client handles to prevent leaks
  for client in pairs(active_clients) do
    if not luv.is_closing(client) then
      client:close()
    end
    active_clients[client] = nil
  end

  if server and not luv.is_closing(server) then
    local closing = server
    server = nil
    tcp.delete_lockfile()
    closing:close(function()
      vim.schedule(function()
        if not silent then
          utils.info 'Assistant server stopped'
        end
        if callback then
          callback(true)
        end
      end)
    end)
  else
    server = nil
    tcp.delete_lockfile()
    if not silent then
      local lock = tcp.read_lockfile()
      if lock and lock.pid and tcp.is_pid_running(lock.pid) and lock.pid ~= vim.fn.getpid() then
        utils.warn(string.format('Assistant server is running in another instance (PID: %d)', lock.pid))
      else
        utils.info 'Assistant server is not running'
      end
    end
    if callback then
      callback(false)
    end
  end
end

---Internal: Start the TCP server listener and lockfile
---@param callback? fun(success: boolean, msg?: string)
---@param silent? boolean
local function start_server(callback, silent)
  local utils = require 'assistant.utils'
  local config = require 'assistant.config'
  local picker = require('assistant.builtins.__picker').standard
  local fs = require 'assistant.core.fs'
  local port = (config.values.core and config.values.core.port) or 10043
  local host = '127.0.0.1'

  if tcp.is_server_running() then
    if not silent then
      utils.warn 'Assistant server is already running'
    end
    if callback then
      callback(true, 'Assistant server is already running')
    end
    return
  end

  local new_server = luv.new_tcp()
  if not new_server then
    local msg = 'Failed to create TCP server handle'
    if not silent then utils.err(msg) end
    if callback then callback(false, msg) end
    return
  end

  local bind_ok, bind_err = pcall(function()
    new_server:bind(host, port)
  end)

  if not bind_ok or bind_err then
    if not luv.is_closing(new_server) then
      new_server:close()
    end
    local msg = 'Server bind error: ' .. tostring(bind_err)
    if not silent then utils.err(msg) end
    if callback then callback(false, msg) end
    return
  end

  local listen_ok, listen_err = pcall(function()
    new_server:listen(128, function(s_err)
      if s_err then
        utils.err('Server connection error: ' .. tostring(s_err))
        return
      end

      -- Scope client handle locally per accepted connection
      local client = luv.new_tcp()
      if not client then
        return
      end

      local accept_ok = pcall(function()
        new_server:accept(client)
      end)

      if not accept_ok then
        if not luv.is_closing(client) then
          client:close()
        end
        return
      end

      active_clients[client] = true
      local req_buffer = ''
      local handled = false

      local function close_client()
        active_clients[client] = nil
        if not luv.is_closing(client) then
          client:close()
        end
      end

      local function process_request(raw_data)
        if handled then
          return
        end
        handled = true

        -- Send HTTP 200 OK response and close client connection cleanly
        if not luv.is_closing(client) then
          local write_ok = pcall(function()
            client:write('HTTP/1.1 200 OK\r\nContent-Length: 0\r\nConnection: close\r\n\r\n', function()
              close_client()
            end)
          end)
          if not write_ok then
            close_client()
          end
        else
          close_client()
        end

        vim.schedule(function()
          local body = raw_data
          local body_start = string.find(body, '\r\n\r\n', 1, true)
          if body_start then
            body = string.sub(body, body_start + 4)
          else
            body_start = string.find(body, '\n\n', 1, true)
            if body_start then
              body = string.sub(body, body_start + 2)
            end
          end

          local ok_dec, data = pcall(vim.json.decode, body)
          if not ok_dec or not data or type(data) ~= 'table' then
            return
          end

          local task_class = (data.languages and data.languages.java and data.languages.java.taskClass) or data.name
          if not task_class or task_class == '' then
            return
          end

          vim.schedule(function()
            local sources = {}
            for key, _ in pairs(config.values.commands) do
              table.insert(sources, key)
            end

            local generator = config.values.core.filename_generator or utils.to_snake_case

            local function on_source(source)
              local testcase_class_snake = generator(task_class)
              local filepath = string.format('%s/.ast/%s.json', fs.find_root() or fs.make_root(), testcase_class_snake)
              fs.write(filepath, body)

              if not source then
                return
              end

              local extension = config.values.commands[source].extension
              vim.fn.execute(string.format('edit %s.%s | write', testcase_class_snake, extension))

              if not config.values.commands[source].template then
                return
              end

              utils.info('populating with ' .. config.values.commands[source].template)
              vim.fn.execute(string.format('0read %s', config.values.commands[source].template))
            end

            if config.values.core.default_source and config.values.commands[config.values.core.default_source] then
              on_source(config.values.core.default_source)
            elseif #sources == 1 then
              on_source(sources[1])
            else
              picker:pick(sources, { prompt = 'source' }, on_source)
            end
          end)
        end)
      end

      client:read_start(function(c_err, chunk)
        if c_err then
          close_client()
          return
        end

        if not chunk then
          -- Client closed connection (EOF): process if buffered and unhandled, then close
          if not handled and req_buffer ~= '' then
            process_request(req_buffer)
          else
            close_client()
          end
          return
        end

        req_buffer = req_buffer .. chunk

        -- Buffer until full HTTP payload is received
        local header_end = string.find(req_buffer, '\r\n\r\n', 1, true)
        local sep_len = 4
        if not header_end then
          header_end = string.find(req_buffer, '\n\n', 1, true)
          sep_len = 2
        end

        if header_end then
          local headers_str = string.sub(req_buffer, 1, header_end - 1)
          local cl_match = string.match(headers_str, '[Cc]ontent%-[Ll]ength:%s*(%d+)')
          if cl_match then
            local content_length = tonumber(cl_match)
            local body_len = #req_buffer - (header_end + sep_len - 1)
            if body_len >= content_length then
              process_request(req_buffer)
            end
          else
            local body = string.sub(req_buffer, header_end + sep_len)
            local ok_dec = pcall(vim.json.decode, body)
            if ok_dec then
              process_request(req_buffer)
            end
          end
        end
      end)
    end)
  end)

  if not listen_ok then
    if not luv.is_closing(new_server) then
      new_server:close()
    end
    local msg = 'Server listen error: ' .. tostring(listen_err)
    if not silent then utils.err(msg) end
    if callback then callback(false, msg) end
    return
  end

  server = new_server
  tcp.write_lockfile(port)

  if not silent then
    utils.info(string.format('Assistant server listening on 127.0.0.1:%d', port))
  end
  if callback then
    callback(true, string.format('Assistant server listening on 127.0.0.1:%d', port))
  end
end

---Attempt to cooperatively bind the server.
---If another instance is active, stands down cleanly without terminating it.
---If the port is free or the lockfile is stale, acquires the lock and binds.
---@param opts? table|fun(success: boolean, msg?: string)|boolean
---@param callback? fun(success: boolean, msg?: string)
function tcp.bind_server(opts, callback)
  local silent = true
  if type(opts) == 'function' then
    callback = opts
    silent = false
  elseif type(opts) == 'table' then
    if opts.silent ~= nil then
      silent = opts.silent
    end
  elseif type(opts) == 'boolean' then
    silent = opts
  end

  local utils = require 'assistant.utils'
  local config = require 'assistant.config'
  local port = (config.values.core and config.values.core.port) or 10043
  local host = '127.0.0.1'

  if tcp.is_server_running() then
    if not silent then
      utils.info(string.format('Assistant server is already running in this instance (PID: %d, Port: %d)', vim.fn.getpid(), port))
    end
    if callback then
      callback(true, 'Assistant server is already running in this instance')
    end
    return
  end

  local lock = tcp.read_lockfile()
  local lock_pid_alive = lock and lock.pid and tcp.is_pid_running(lock.pid)

  -- Probe port to see if another process is currently listening
  tcp.is_port_in_use(host, port, function(in_use)
    if in_use then
      if lock and lock_pid_alive and lock.pid ~= vim.fn.getpid() then
        -- Another instance is running, cleanly stand down without hostile shutdown
        local msg = string.format('Assistant server active in another instance (PID: %d)', lock.pid)
        if not silent then
          utils.info(msg)
        end
        if callback then
          callback(false, msg)
        end
        return
      else
        local msg = string.format('Port %d is in use by another process', port)
        if not silent then
          utils.warn(msg)
        end
        if callback then
          callback(false, msg)
        end
        return
      end
    end

    -- Port is free (or lockfile was stale). Acquire lock and start server!
    start_server(callback, silent)
  end)
end

---Get current status of server and lockfile
---@param callback? fun(status: table)
---@return table?
function tcp.get_status(callback)
  local config = require 'assistant.config'
  local port = (config.values.core and config.values.core.port) or 10043
  local host = '127.0.0.1'
  local lock = tcp.read_lockfile()
  local lock_alive = lock and lock.pid and tcp.is_pid_running(lock.pid)

  if tcp.is_server_running() then
    local st = {
      running = true,
      local_instance = true,
      pid = vim.fn.getpid(),
      port = port,
      cwd = vim.fn.getcwd(),
    }
    if callback then callback(st) end
    return st
  end

  tcp.is_port_in_use(host, port, function(in_use)
    local st = {
      running = in_use,
      local_instance = false,
      port = port,
    }
    if in_use and lock and lock_alive then
      st.pid = lock.pid
      st.cwd = lock.cwd
    elseif in_use then
      st.external = true
    end
    if callback then callback(st) end
  end)
end

---Print formatted server status message
function tcp.print_status()
  local utils = require 'assistant.utils'
  tcp.get_status(function(st)
    vim.schedule(function()
      if st.local_instance then
        utils.info(string.format('Assistant server running locally (PID: %d, Port: %d, CWD: %s)', st.pid, st.port, st.cwd or ''))
      elseif st.running and st.pid then
        utils.info(string.format('Assistant server running in another instance (PID: %d, Port: %d, CWD: %s)', st.pid, st.port, st.cwd or 'unknown'))
      elseif st.running then
        utils.warn(string.format('Port %d is in use by another process (no active Assistant lockfile)', st.port))
      else
        utils.info(string.format('Assistant server is not running (Port %d is free)', st.port))
      end
    end)
  end)
end

return tcp
