local M = {}

local function first_debuggable_line(code_buf)
  local lines = vim.api.nvim_buf_get_lines(code_buf, 0, -1, false)
  for i, line in ipairs(lines) do
    if line:match("^%s*func%s+") then
      for j = i + 1, #lines do
        local candidate = lines[j]
        if candidate:match("%S") and not candidate:match("^%s*[{]}%s*$") and not candidate:match("^%s*//") then
          return j
        end
      end
    end
  end

  return 1
end

local function is_debuggable_line(code_buf, line)
  local text = vim.api.nvim_buf_get_lines(code_buf, line - 1, line, false)[1]
  if not text then
    return false
  end

  return text:match("%S") and not text:match("^%s*[{]}%s*$") and not text:match("^%s*//")
end

local function next_debuggable_line_from(code_buf, start_line)
  local lines = vim.api.nvim_buf_get_lines(code_buf, 0, -1, false)
  for i = start_line, #lines do
    if is_debuggable_line(code_buf, i) then
      return i
    end
  end

  return nil
end

local function ensure_debug_breakpoint(code_buf)
  local ok, breakpoints_mod = pcall(require, "dap.breakpoints")
  if not ok then
    return
  end

  local breakpoints = breakpoints_mod.get()
  local fallback_from_line
  for _, breakpoint in ipairs(breakpoints[code_buf] or {}) do
    if is_debuggable_line(code_buf, breakpoint.line) then
      return
    end
    fallback_from_line = fallback_from_line or breakpoint.line
  end

  if next(breakpoints) ~= nil then
    vim.notify("Existing breakpoints were not runnable here; adding a fallback", vim.log.levels.WARN, {
      title = "Codemap Debug",
    })
  end

  local cursor_line = vim.api.nvim_get_current_buf() == code_buf and vim.api.nvim_win_get_cursor(0)[1] or nil
  local line = (cursor_line and is_debuggable_line(code_buf, cursor_line) and cursor_line)
    or (fallback_from_line and next_debuggable_line_from(code_buf, fallback_from_line))
    or (cursor_line and next_debuggable_line_from(code_buf, cursor_line))
    or first_debuggable_line(code_buf)

  if line and is_debuggable_line(code_buf, line) then
    breakpoints_mod.set(nil, code_buf, line)
    vim.notify("Added breakpoint on line " .. line, vim.log.levels.INFO, { title = "Codemap Debug" })
    return
  end

  vim.notify("No executable statement found for a breakpoint", vim.log.levels.WARN, {
    title = "Codemap Debug",
  })
end

function M.debug(ctx)
  local config = ctx.config
  local workspace = ctx.workspace
  local ui = ctx.ui

  workspace.ensure_workspace(config)

  local code_path = workspace.code_file_for_current_buffer(config)
  local code_buf = vim.api.nvim_get_current_buf()
  if not code_path then
    code_path, code_buf = workspace.code_file_in_current_tab(config)
  end

  if not code_path or not code_buf then
    vim.notify("No valid code file found in the Codemap workspace for debugging", vim.log.levels.WARN)
    return
  end

  local language = ctx.runner_language_for_buffer(code_buf)
  local ft = language.filetype
  if ft ~= "go" and ft ~= "python" then
    vim.notify("Debugger support is only available for Go and Python", vim.log.levels.WARN)
    return
  end

  local input_path, output_path = workspace.mapped_paths(config)
  workspace.ensure_file(input_path)
  workspace.ensure_file(output_path)
  workspace.autosave_codemap_buffers(config)
  ui.close_output_windows(workspace, output_path)

  if vim.bo[code_buf].modified then
    vim.api.nvim_buf_call(code_buf, function()
      vim.cmd("write")
    end)
  end

  local ok, dap = pcall(require, "dap")
  if not ok then
    vim.notify("nvim-dap is required for `:CodemapDebug`", vim.log.levels.ERROR)
    return
  end

  ensure_debug_breakpoint(code_buf)

  if ft == "go" then
    dap.run({
      type = "delve",
      request = "launch",
      name = "Codemap Debug Go",
      mode = "debug",
      program = code_path,
      cwd = vim.fn.fnamemodify(code_path, ":h"),
      stdin = input_path,
      outputMode = "remote",
    })
  else
    local wrapper_path = workspace.write_python_debug_wrapper(config, code_path, input_path)
    dap.run({
      type = "python",
      request = "launch",
      name = "Codemap Debug Python",
      program = wrapper_path,
      cwd = vim.fn.fnamemodify(code_path, ":h"),
      console = "internalConsole",
      justMyCode = false,
      redirectOutput = true,
      env = { PYTHONUNBUFFERED = "1" },
    })
  end

  vim.notify("Starting Codemap debugger for " .. language.label, vim.log.levels.INFO)
end

return M
