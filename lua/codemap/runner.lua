local M = {}

local function shell_escape(path)
  return vim.fn.shellescape(path)
end

local function command_exists(bin)
  return vim.fn.executable(bin) == 1
end

local function write_output(path, lines)
  vim.fn.writefile(lines, path)
end

local function run_shell_command(config, command, stdin_data)
  if vim.system then
    local result = vim.system({ vim.o.shell, "-c", command }, {
      stdin = stdin_data,
      text = true,
      timeout = config.run_timeout_ms,
    }):wait()

    return {
      stdout = result.stdout or "",
      stderr = result.stderr or "",
      code = result.code or 0,
      timed_out = result.code == 124,
    }
  end

  local result = vim.fn.system(command, stdin_data)
  return {
    stdout = result,
    stderr = "",
    code = vim.v.shell_error,
    timed_out = false,
  }
end

local function runner_for(config, workspace, language, source_path)
  local escaped_source = shell_escape(source_path)
  local binary = workspace.temp_binary_path(config, "codemap-runner")
  local escaped_binary = shell_escape(binary)
  local escaped_build_dir = shell_escape(workspace.build_dir(config))
  local class_name = vim.fn.fnamemodify(source_path, ":t:r")

  if language.filetype == "python" then
    return command_exists("python3"), "python3 " .. escaped_source
  end

  if language.filetype == "go" then
    return command_exists("go"), "go run " .. escaped_source
  end

  if language.filetype == "javascript" then
    return command_exists("node"), "node " .. escaped_source
  end

  if language.filetype == "typescript" then
    if command_exists("tsx") then
      return true, "tsx " .. escaped_source
    end
    if command_exists("ts-node") then
      return true, "ts-node " .. escaped_source
    end
    return false, "Need `tsx` or `ts-node` to run TypeScript"
  end

  if language.filetype == "java" then
    if not (command_exists("javac") and command_exists("java")) then
      return false, "Need `javac` and `java` to run Java"
    end
    return true, "javac -d " .. escaped_build_dir .. " " .. escaped_source .. " && java -cp " .. escaped_build_dir .. " " .. class_name
  end

  if language.filetype == "cpp" then
    if not command_exists("g++") then
      return false, "Need `g++` to run C++"
    end
    return true, "g++ -std=c++17 " .. escaped_source .. " -o " .. escaped_binary .. " && " .. escaped_binary
  end

  if language.filetype == "c" then
    if not command_exists("cc") then
      return false, "Need `cc` to run C"
    end
    return true, "cc " .. escaped_source .. " -o " .. escaped_binary .. " && " .. escaped_binary
  end

  if language.filetype == "rust" then
    if not command_exists("rustc") then
      return false, "Need `rustc` to run Rust"
    end
    return true, "rustc " .. escaped_source .. " -o " .. escaped_binary .. " && " .. escaped_binary
  end

  if language.filetype == "ruby" then
    return command_exists("ruby"), "ruby " .. escaped_source
  end

  return false, "No Codemap runner configured for filetype `" .. language.filetype .. "`"
end

local function buffer_source_path(config, workspace, language, code_path, code_buf)
  local named_path = code_path or workspace.code_file_for_current_buffer(config)
  if named_path then
    return named_path
  end

  local source_path = workspace.temp_source_path(config, language)
  local source_buf = code_buf or vim.api.nvim_get_current_buf()
  local lines = vim.api.nvim_buf_get_lines(source_buf, 0, -1, false)
  vim.fn.writefile(lines, source_path)
  return source_path
end

function M.run(ctx)
  local config = ctx.config
  local workspace = ctx.workspace
  local ui = ctx.ui

  workspace.ensure_workspace(config)

  local code_path = workspace.code_file_for_current_buffer(config)
  local code_buf = vim.api.nvim_get_current_buf()
  if not code_path then
    code_path, code_buf = workspace.code_file_in_current_tab(config)
  end

  local language = ctx.runner_language_for_buffer(code_buf)
  local source_path = buffer_source_path(config, workspace, language, code_path, code_buf)
  local input_path, output_path = workspace.mapped_paths(config)

  workspace.ensure_file(input_path)
  workspace.ensure_file(output_path)
  workspace.autosave_codemap_buffers(config)
  ui.close_output_windows(workspace, output_path)

  local stdin_data = table.concat(vim.fn.readfile(input_path), "\n")
  local ok, command = runner_for(config, workspace, language, source_path)
  if not ok then
    write_output(output_path, { command })
    ui.open_output_buffer(workspace, output_path)
    ui.highlight_output(workspace, ctx.output_namespace, output_path)
    vim.notify(command, vim.log.levels.WARN, { title = "CodemapRun" })
    return
  end

  local result = run_shell_command(config, command, stdin_data)
  local combined_output = result.stdout
  if result.stderr ~= "" then
    combined_output = combined_output .. result.stderr
  end

  local lines = vim.split(combined_output, "\n", { plain = true })
  if lines[#lines] == "" then
    table.remove(lines, #lines)
  end

  if #lines == 0 then
    lines = { "" }
  end

  if result.timed_out then
    lines = {
      "[timeout]",
      "Execution stopped after " .. (config.run_timeout_ms / 1000) .. "s to avoid long-running process.",
    }
  elseif result.code ~= 0 then
    table.insert(lines, 1, "[exit " .. result.code .. "]")
  end

  write_output(output_path, lines)
  ui.open_output_buffer(workspace, output_path)
  ui.highlight_output(workspace, ctx.output_namespace, output_path)

  local message
  local level
  if result.timed_out then
    message = "Execution timed out after " .. (config.run_timeout_ms / 1000) .. "s"
    level = vim.log.levels.ERROR
  else
    message = "Ran " .. language.label .. " -> " .. vim.fn.fnamemodify(output_path, ":t")
    level = result.code == 0 and vim.log.levels.INFO or vim.log.levels.WARN
  end

  vim.notify(message, level, { title = "CodemapRun" })
end

return M
