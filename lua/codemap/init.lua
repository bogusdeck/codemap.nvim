local M = {}

local languages = {
  { label = "Go", filetype = "go", ext = "go" },
  { label = "Python", filetype = "python", ext = "py" },
  { label = "JavaScript", filetype = "javascript", ext = "js" },
  { label = "TypeScript", filetype = "typescript", ext = "ts" },
  { label = "Java", filetype = "java", ext = "java" },
  { label = "C++", filetype = "cpp", ext = "cpp" },
  { label = "C", filetype = "c", ext = "c" },
  { label = "Rust", filetype = "rust", ext = "rs" },
  { label = "Ruby", filetype = "ruby", ext = "rb" },
}

local defaults = {
  workspace = vim.fn.stdpath("data") .. "/codemap",
  run_timeout_ms = 3000,
  default_language = "go",
  keymaps = true,
}

local config = vim.deepcopy(defaults)
local output_namespace = vim.api.nvim_create_namespace("codemap-output")
local commands_created = false
local keymaps_created = false

local error_patterns = {
  "^%[exit %d+%]",
  "Traceback",
  "SyntaxError",
  "Error:",
  "error:",
  "Exception",
  "panic:",
  "failed",
}

local function normalize(path)
  return vim.fn.fnamemodify(path, ":p")
end

local function workspace_path()
  return normalize(vim.fn.expand(config.workspace))
end

local function build_dir()
  return normalize(workspace_path() .. "/.codemap-build")
end

local function mapped_paths()
  local root = workspace_path()
  return normalize(root .. "/input.txt"), normalize(root .. "/output.txt")
end

local function is_workspace_file(path)
  local full_path = normalize(path)
  local root = workspace_path()
  return full_path:sub(1, #root) == root
end

local function is_sidecar(path)
  return path:match("%.input%.txt$") ~= nil or path:match("%.output%.txt$") ~= nil
end

local function is_shared_io_file(path)
  local name = vim.fn.fnamemodify(path, ":t")
  return name == "input.txt" or name == "output.txt"
end

local function current_language()
  local selected = vim.g.codemap_language or config.default_language
  for _, language in ipairs(languages) do
    if language.filetype == selected then
      return language
    end
  end
  return languages[1]
end

local function language_for_filetype(filetype)
  for _, language in ipairs(languages) do
    if language.filetype == filetype then
      return language
    end
  end
  return nil
end

local function code_file_for_current_buffer()
  local path = vim.api.nvim_buf_get_name(0)
  if path == "" then
    return nil
  end

  path = normalize(path)
  if not is_workspace_file(path) or is_sidecar(path) or is_shared_io_file(path) then
    return nil
  end

  return path
end

local function code_file_in_current_tab()
  for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
    local buf = vim.api.nvim_win_get_buf(win)
    local name = vim.api.nvim_buf_get_name(buf)
    if name ~= "" then
      local path = normalize(name)
      if is_workspace_file(path) and not is_sidecar(path) and not is_shared_io_file(path) then
        return path, buf
      end
    end
  end
  return nil, nil
end

local function ensure_workspace()
  vim.fn.mkdir(workspace_path(), "p")
  vim.fn.mkdir(build_dir(), "p")
end

local function ensure_file(path)
  if vim.fn.filereadable(path) == 0 then
    vim.fn.writefile({}, path)
  end
end

local function apply_language_to_current_buffer(language)
  vim.g.codemap_language = language.filetype
  vim.bo.buftype = ""
  vim.bo.bufhidden = ""
  vim.bo.swapfile = true
  vim.bo.filetype = language.filetype
  vim.bo.syntax = language.filetype
  vim.b.codemap_language = language.filetype
end

local function current_runner_language()
  local by_filetype = language_for_filetype(vim.bo.filetype)
  if by_filetype then
    return by_filetype
  end
  return current_language()
end

local function runner_language_for_buffer(buf)
  local by_filetype = language_for_filetype(vim.bo[buf].filetype)
  if by_filetype then
    return by_filetype
  end
  return current_language()
end

local function select_language(callback)
  vim.ui.select(languages, {
    prompt = "Codemap language",
    format_item = function(item)
      return string.format("%s (.%s)", item.label, item.ext)
    end,
  }, function(choice)
    if not choice then
      return
    end

    apply_language_to_current_buffer(choice)
    if callback then
      callback(choice)
    end
  end)
end

local function output_split_height()
  return math.max(5, math.floor(vim.o.lines * 0.30))
end

local function open_output_split(output_path)
  ensure_file(output_path)
  local height = output_split_height()
  vim.cmd("botright " .. height .. "split " .. vim.fn.fnameescape(output_path))
  vim.api.nvim_win_set_height(0, height)
  vim.bo.swapfile = false
end

local function build_two_pane_layout(output_path, code_path)
  ensure_file(output_path)
  vim.cmd("only")

  if code_path then
    vim.cmd("edit " .. vim.fn.fnameescape(code_path))
  else
    vim.cmd("enew")
  end

  local code_win = vim.api.nvim_get_current_win()
  open_output_split(output_path)
  vim.api.nvim_set_current_win(code_win)
  return code_win
end

local function shell_escape(path)
  return vim.fn.shellescape(path)
end

local function command_exists(bin)
  return vim.fn.executable(bin) == 1
end

local function write_output(path, lines)
  vim.fn.writefile(lines, path)
end

local function output_buffer(path)
  local target = normalize(path)
  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    local name = vim.api.nvim_buf_get_name(buf)
    if name ~= "" and normalize(name) == target then
      return buf
    end
  end
  return nil
end

local function open_output_buffer(path)
  local buf = output_buffer(path)
  if not buf then
    return
  end

  vim.api.nvim_buf_call(buf, function()
    vim.cmd("silent edit")
  end)
end

local function close_output_windows(path)
  local target = normalize(path)
  for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
    if #vim.api.nvim_tabpage_list_wins(0) <= 1 then
      return
    end

    local buf = vim.api.nvim_win_get_buf(win)
    local name = vim.api.nvim_buf_get_name(buf)
    if name ~= "" and normalize(name) == target then
      pcall(vim.api.nvim_win_close, win, false)
    end
  end
end

local function highlight_output(path)
  local buf = output_buffer(path)
  if not buf then
    return
  end

  vim.api.nvim_buf_clear_namespace(buf, output_namespace, 0, -1)
  local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  for i, line in ipairs(lines) do
    for _, pattern in ipairs(error_patterns) do
      if line:match(pattern) then
        vim.api.nvim_buf_add_highlight(buf, output_namespace, "DiagnosticError", i - 1, 0, -1)
        break
      end
    end
  end
end

local function autosave_codemap_buffers()
  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_loaded(buf) and vim.bo[buf].modified and vim.bo[buf].buftype == "" then
      local name = vim.api.nvim_buf_get_name(buf)
      if name ~= "" and is_workspace_file(name) then
        vim.api.nvim_buf_call(buf, function()
          vim.cmd("silent write")
        end)
      end
    end
  end
end

local function temp_source_path(language)
  return normalize(build_dir() .. "/main." .. language.ext)
end

local function temp_binary_path(name)
  return normalize(build_dir() .. "/" .. name)
end

local function python_debug_wrapper_path()
  return normalize(build_dir() .. "/python-debug-wrapper.py")
end

local function write_python_debug_wrapper(source_path, input_path)
  local wrapper_path = python_debug_wrapper_path()
  vim.fn.writefile({
    "import os",
    "import runpy",
    "import sys",
    "",
    "source = " .. string.format("%q", source_path),
    "input_file = " .. string.format("%q", input_path),
    "",
    "os.chdir(os.path.dirname(source))",
    "sys.argv = [source]",
    "sys.path.insert(0, os.path.dirname(source))",
    "sys.stdin = open(input_file, 'r', encoding='utf-8')",
    "runpy.run_path(source, run_name='__main__')",
  }, wrapper_path)
  return wrapper_path
end

local function run_shell_command(command, stdin_data)
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

local function runner_for(language, source_path)
  local escaped_source = shell_escape(source_path)
  local binary = temp_binary_path("codemap-runner")
  local escaped_binary = shell_escape(binary)
  local escaped_build_dir = shell_escape(build_dir())
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

local function buffer_source_path(code_path, code_buf)
  local named_path = code_path or code_file_for_current_buffer()
  if named_path then
    return named_path
  end

  local language = code_buf and runner_language_for_buffer(code_buf) or current_runner_language()
  local source_path = temp_source_path(language)
  local source_buf = code_buf or vim.api.nvim_get_current_buf()
  local lines = vim.api.nvim_buf_get_lines(source_buf, 0, -1, false)
  vim.fn.writefile(lines, source_path)
  return source_path
end

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

  return text:match("%S")
    and not text:match("^%s*[{]}%s*$")
    and not text:match("^%s*//")
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
    vim.notify("Existing breakpoints are not runnable here; adding a fallback", vim.log.levels.WARN, {
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

  vim.notify("No executable statement found for a breakpoint", vim.log.levels.WARN, { title = "Codemap Debug" })
end

function M.run()
  ensure_workspace()

  local code_path = code_file_for_current_buffer()
  local code_buf = vim.api.nvim_get_current_buf()
  if not code_path then
    code_path, code_buf = code_file_in_current_tab()
  end

  local language = code_buf and runner_language_for_buffer(code_buf) or current_runner_language()
  local input_path, output_path = mapped_paths()
  ensure_file(input_path)
  ensure_file(output_path)
  autosave_codemap_buffers()

  if code_buf and vim.bo[code_buf].modified and code_path then
    vim.api.nvim_buf_call(code_buf, function()
      vim.cmd("write")
    end)
  end

  local source_path = buffer_source_path(code_path, code_buf)
  local ok, command = runner_for(language, source_path)
  if not ok then
    write_output(output_path, { command })
    open_output_buffer(output_path)
    vim.notify(command, vim.log.levels.ERROR, { title = "CodemapRun" })
    return
  end

  local stdin_data = table.concat(vim.fn.readfile(input_path), "\n")
  if stdin_data ~= "" then
    stdin_data = stdin_data .. "\n"
  end

  local result = run_shell_command(command, stdin_data)
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
      "Execution stopped after " .. (config.run_timeout_ms / 1000) .. "s to avoid a long-running process.",
    }
  elseif result.code ~= 0 then
    table.insert(lines, 1, "[exit " .. result.code .. "]")
  end

  write_output(output_path, lines)
  open_output_buffer(output_path)
  highlight_output(output_path)

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

function M.debug()
  ensure_workspace()

  local code_path = code_file_for_current_buffer()
  local code_buf = vim.api.nvim_get_current_buf()
  if not code_path then
    code_path, code_buf = code_file_in_current_tab()
  end

  if not code_path or not code_buf then
    vim.notify("No valid code file found in the Codemap workspace for debugging", vim.log.levels.WARN)
    return
  end

  local language = runner_language_for_buffer(code_buf)
  local ft = language.filetype
  if ft ~= "go" and ft ~= "python" then
    vim.notify("Debugger support is only available for Go and Python", vim.log.levels.WARN)
    return
  end

  local input_path, output_path = mapped_paths()
  ensure_file(input_path)
  ensure_file(output_path)
  autosave_codemap_buffers()
  close_output_windows(output_path)

  if vim.bo[code_buf].modified then
    vim.api.nvim_buf_call(code_buf, function()
      vim.cmd("write")
    end)
  end

  local ok, dap = pcall(require, "dap")
  if not ok then
    vim.notify("nvim-dap is required for :CodemapDebug", vim.log.levels.ERROR)
    return
  end

  ensure_debug_breakpoint(code_buf)
  if ft == "go" then
    dap.run({
      type = "go",
      name = "Codemap Debug Go",
      request = "launch",
      mode = "debug",
      program = code_path,
      cwd = vim.fn.fnamemodify(code_path, ":h"),
      stdin = input_path,
      outputMode = "remote",
    })
  else
    local wrapper_path = write_python_debug_wrapper(code_path, input_path)
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

function M.open_shared_layout()
  ensure_workspace()
  vim.cmd("cd " .. vim.fn.fnameescape(workspace_path()))

  local _, output_path = mapped_paths()
  local code_win = build_two_pane_layout(output_path)
  vim.api.nvim_set_current_win(code_win)
  apply_language_to_current_buffer(current_language())

  if #vim.api.nvim_list_uis() > 0 then
    vim.schedule(function()
      if vim.api.nvim_win_is_valid(code_win) then
        vim.api.nvim_set_current_win(code_win)
        select_language()
      end
    end)
  end
end

function M.open_for_code(code_path)
  ensure_workspace()
  vim.cmd("cd " .. vim.fn.fnameescape(workspace_path()))

  local _, output_path = mapped_paths()
  ensure_file(output_path)
  build_two_pane_layout(output_path, code_path)
end

function M.open(code_path)
  local target_code = code_path or code_file_for_current_buffer()
  if target_code then
    M.open_for_code(target_code)
    return
  end

  M.open_shared_layout()
end

local function create_commands()
  if commands_created then
    return
  end

  vim.api.nvim_create_user_command("Run", function()
    M.run()
  end, { desc = "Run the current Codemap buffer" })

  vim.api.nvim_create_user_command("Codemap", function()
    M.open()
  end, { desc = "Open the Codemap two-pane workspace" })

  vim.api.nvim_create_user_command("CodemapLanguage", function()
    select_language()
  end, { desc = "Select the language for the current Codemap buffer" })

  vim.api.nvim_create_user_command("CodemapRun", function()
    M.run()
  end, { desc = "Run the current Codemap buffer with input.txt and write output.txt" })

  vim.api.nvim_create_user_command("CodemapDebug", function()
    M.debug()
  end, { desc = "Debug the current Codemap buffer with nvim-dap" })

  commands_created = true
end

local function create_keymaps()
  if keymaps_created or not config.keymaps then
    return
  end

  vim.keymap.set("n", "<leader>cr", function()
    M.run()
  end, { desc = "Codemap Run" })

  vim.keymap.set({ "n", "i" }, "<F5>", function()
    M.run()
  end, { desc = "Codemap Run" })

  vim.keymap.set("n", "<leader>cd", function()
    M.debug()
  end, { desc = "Codemap Debug" })

  vim.keymap.set("n", "<F6>", function()
    M.debug()
  end, { desc = "Codemap Debug" })

  vim.keymap.set("i", "<F6>", function()
    vim.cmd("stopinsert")
    vim.schedule(M.debug)
  end, { desc = "Codemap Debug" })

  keymaps_created = true
end

function M.setup(opts)
  config = vim.tbl_deep_extend("force", vim.deepcopy(defaults), opts or {})
  create_commands()
  create_keymaps()
end

return M
