local state = require 'assistant.state'
local M = {}

-- Prevent LSP and auto-formatters from hooking into assistant UI/patcher buffers
local function register_buffer_safety()
  local assistant_group = vim.api.nvim_create_augroup('assistant_buffers', { clear = true })
  vim.api.nvim_create_autocmd('BufWinEnter', {
    group = assistant_group,
    pattern = '*',
    callback = function(args)
      local buf_name = vim.api.nvim_buf_get_name(args.buf)
      local filetype = vim.api.nvim_get_option_value('filetype', { buf = args.buf })
      local is_modifiable = vim.api.nvim_get_option_value('modifiable', { buf = args.buf })

      if string.match(buf_name:lower(), 'assistant') or string.match(filetype:lower(), '^assistant') or not is_modifiable then
        vim.b[args.buf].autoformat = false
        for _, client in ipairs(vim.lsp.get_clients({ bufnr = args.buf })) do
          vim.lsp.buf_detach_client(args.buf, client.id)
        end
      end
    end,
  })
end

-- Automatically protect assistant buffers on load
register_buffer_safety()

---@param opts? Assistant.Config
function M.setup(opts)
  require('assistant.config').overwrite(opts)
  local config = require 'assistant.config'

  if config.values.core.auto_start_server then
    require('assistant.core.tcp').bind_server({ silent = true })
  end

  if config.values.core.claim_port_on_focus then
    vim.api.nvim_create_autocmd('FocusGained', {
      group = vim.api.nvim_create_augroup('assistant_focus', { clear = true }),
      callback = function()
        local tcp = require 'assistant.core.tcp'
        if not tcp.is_server_running() then
          tcp.bind_server({ silent = true })
        end
      end,
    })
  end

  register_buffer_safety()

  -- Ensure state is saved and TCP cleanly terminates on exit
  vim.api.nvim_create_autocmd('VimLeavePre', {
    group = vim.api.nvim_create_augroup('assistant_cleanup', { clear = true }),
    callback = function()
      pcall(state.persist)
      local ok_tcp, tcp = pcall(require, 'assistant.core.tcp')
      if ok_tcp and tcp.stop_server then
        pcall(tcp.stop_server, nil, true)
      end
    end,
  })

  vim.api.nvim_create_user_command('Assistant', function()
    state.track_source()
    require('assistant.utils').ensure_out_dir()
    require('assistant.builtins.__wizard').standard:show()
  end, { nargs = 0, force = true })

  vim.api.nvim_create_user_command('AssistantServerStart', function()
    require('assistant.core.tcp').bind_server(function(success, msg)
      if success then
        require('assistant.utils').info(msg or 'Assistant server started')
      else
        require('assistant.utils').warn(msg or 'Failed to start assistant server')
      end
    end)
  end, { desc = 'Start Assistant TCP server', force = true })

  vim.api.nvim_create_user_command('AssistantServerStop', function()
    require('assistant.core.tcp').stop_server(nil, false)
  end, { desc = 'Stop Assistant TCP server', force = true })

  vim.api.nvim_create_user_command('AssistantServerStatus', function()
    require('assistant.core.tcp').print_status()
  end, { desc = 'Show Assistant TCP server status', force = true })
end

---@return table
function M.status()
  return state.get_local_key 'status' or {}
end

return M
