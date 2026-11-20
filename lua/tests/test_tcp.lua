local test = require 'mini.test'
local config = require 'assistant.config'
local tcp = require 'assistant.core.tcp'
local luv = vim.uv or vim.loop

local T = test.new_set()

local function ensure_lock_dir()
  local path = tcp.get_lockfile_path()
  local dir = vim.fn.fnamemodify(path, ':h')
  if vim.fn.isdirectory(dir) == 0 then
    pcall(vim.fn.mkdir, dir, 'p')
  end
  return path
end

T['config defaults have auto_start_server and claim_port_on_focus'] = function()
  config.overwrite()
  test.expect.equality(config.values.core.auto_start_server, true)
  test.expect.equality(config.values.core.claim_port_on_focus, false)
  test.expect.equality(config.values.core.port, 10043)
end

T['lockfile management: get_path, write, read, delete'] = function()
  local path = ensure_lock_dir()
  test.expect.equality(type(path), 'string')
  test.expect.equality(string.match(path, 'assistant_server%.json$') ~= nil, true)

  -- Write lockfile
  local ok = tcp.write_lockfile(10043)
  test.expect.equality(ok, true)

  -- Read lockfile
  local data = tcp.read_lockfile()
  test.expect.equality(type(data), 'table')
  test.expect.equality(data.pid, vim.fn.getpid())
  test.expect.equality(data.port, 10043)
  test.expect.equality(data.cwd, vim.fn.getcwd())

  -- Delete lockfile for self
  local del_ok = tcp.delete_lockfile()
  test.expect.equality(del_ok, true)

  local after_del = tcp.read_lockfile()
  test.expect.equality(after_del, nil)
end

T['lockfile delete does not delete other PID unless forced'] = function()
  local path = ensure_lock_dir()

  local f = io.open(path, 'w')
  test.expect.equality(f ~= nil, true)
  f:write(vim.json.encode { pid = 9999999, port = 10043, cwd = '/tmp' })
  f:close()

  -- Non-matching PID: delete_lockfile() should not delete
  local del_ok = tcp.delete_lockfile(false)
  test.expect.equality(del_ok, false)

  local data = tcp.read_lockfile()
  test.expect.equality(type(data), 'table')
  test.expect.equality(data.pid, 9999999)

  -- Force delete
  local force_del = tcp.delete_lockfile(true)
  test.expect.equality(force_del, true)
  test.expect.equality(tcp.read_lockfile(), nil)
end

T['is_pid_running checks process existence'] = function()
  test.expect.equality(tcp.is_pid_running(vim.fn.getpid()), true)
  test.expect.equality(tcp.is_pid_running(9999999), false)
  test.expect.equality(tcp.is_pid_running(nil), false)
  test.expect.equality(tcp.is_pid_running(-1), false)
  test.expect.equality(tcp.is_pid_running(0), false)
end

T['server lifecycle: start, probe without shutdown, stop'] = function()
  local test_port = 10091
  config.overwrite { core = { port = test_port, auto_start_server = false } }
  ensure_lock_dir()

  -- Ensure server is stopped initially
  tcp.stop_server(nil, true)
  tcp.delete_lockfile(true)

  -- Start server
  local started = false
  tcp.bind_server({ silent = true }, function(success)
    started = success
  end)

  vim.wait(1000, function()
    return started and tcp.is_server_running()
  end)

  test.expect.equality(tcp.is_server_running(), true)

  -- Lockfile should exist with test_port
  local lock = tcp.read_lockfile()
  test.expect.equality(type(lock), 'table')
  test.expect.equality(lock.pid, vim.fn.getpid())
  test.expect.equality(lock.port, test_port)

  -- Probe port using a plain TCP connect (should NOT kill server)
  local probed = false
  local client = luv.new_tcp()
  client:connect('127.0.0.1', test_port, function(err)
    test.expect.equality(err, nil)
    client:close()
    probed = true
  end)

  vim.wait(1000, function()
    return probed
  end)
  test.expect.equality(probed, true)

  -- Crucial check: Server MUST still be running after client connection closes
  test.expect.equality(tcp.is_server_running(), true)

  -- Stop server cleanly
  local stopped = false
  tcp.stop_server(function(res)
    stopped = true
  end, true)

  vim.wait(1000, function()
    return stopped and not tcp.is_server_running()
  end)

  test.expect.equality(tcp.is_server_running(), false)
  test.expect.equality(tcp.read_lockfile(), nil)
end

T['cooperative stand-down when port is active in another instance'] = function()
  local test_port = 10092
  config.overwrite { core = { port = test_port, auto_start_server = false } }
  local path = ensure_lock_dir()

  -- 1. Create a dummy listening socket simulating another instance
  local fake_server = luv.new_tcp()
  fake_server:bind('127.0.0.1', test_port)
  fake_server:listen(128, function() end)

  -- Write a lockfile with pid 1 (init/systemd, always alive in Linux) to simulate another living PID
  local f = io.open(path, 'w')
  test.expect.equality(f ~= nil, true)
  f:write(vim.json.encode { pid = 1, port = test_port, cwd = '/tmp/other_nvim' })
  f:close()

  -- 2. Try to bind_server()
  local bound = nil
  local bound_msg = nil
  tcp.bind_server({ silent = true }, function(success, msg)
    bound = success
    bound_msg = msg
  end)

  vim.wait(1000, function()
    return bound ~= nil
  end)

  -- Must stand down cleanly: bound must be false
  test.expect.equality(bound, false)
  test.expect.equality(string.match(bound_msg, 'another instance') ~= nil, true)
  test.expect.equality(tcp.is_server_running(), false)

  -- 3. The other instance must NOT have been shut down!
  local check = luv.new_tcp()
  local still_alive = false
  check:connect('127.0.0.1', test_port, function(err)
    if not err then
      still_alive = true
    end
    check:close()
  end)

  vim.wait(1000, function()
    return still_alive
  end)
  test.expect.equality(still_alive, true)

  -- Cleanup dummy server and lockfile
  fake_server:close()
  tcp.delete_lockfile(true)
end

T['stale lockfile is reclaimed when port is free'] = function()
  local test_port = 10093
  config.overwrite { core = { port = test_port, auto_start_server = false } }
  local path = ensure_lock_dir()

  -- Write lockfile with a DEAD PID
  local f = io.open(path, 'w')
  test.expect.equality(f ~= nil, true)
  f:write(vim.json.encode { pid = 9999999, port = test_port, cwd = '/tmp/dead_nvim' })
  f:close()

  -- Port is free, but stale lockfile exists. bind_server should reclaim it!
  local bound = false
  tcp.bind_server({ silent = true }, function(success)
    bound = success
  end)

  vim.wait(1000, function()
    return bound and tcp.is_server_running()
  end)

  test.expect.equality(bound, true)
  test.expect.equality(tcp.is_server_running(), true)

  -- Lockfile should now belong to this PID
  local lock = tcp.read_lockfile()
  test.expect.equality(lock.pid, vim.fn.getpid())
  test.expect.equality(lock.port, test_port)

  -- Clean up
  tcp.stop_server(nil, true)
end

T['user commands are registered'] = function()
  require('assistant').setup { core = { auto_start_server = false } }

  local commands = vim.api.nvim_get_commands {}
  test.expect.equality(commands.Assistant ~= nil, true)
  test.expect.equality(commands.AssistantServerStart ~= nil, true)
  test.expect.equality(commands.AssistantServerStop ~= nil, true)
  test.expect.equality(commands.AssistantServerStatus ~= nil, true)
end

return T
