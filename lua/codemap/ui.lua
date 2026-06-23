local M = {}

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

function M.apply_language_to_current_buffer(language)
  vim.g.codemap_language = language.filetype
  vim.bo.buftype = ""
  vim.bo.bufhidden = ""
  vim.bo.swapfile = true
  vim.bo.filetype = language.filetype
  vim.bo.syntax = language.filetype
  vim.b.codemap_language = language.filetype
end

function M.select_language(languages, callback)
  vim.ui.select(languages, {
    prompt = "Codemap language",
    format_item = function(item)
      return string.format("%s (.%s)", item.label, item.ext)
    end,
  }, function(choice)
    if not choice then
      return
    end

    M.apply_language_to_current_buffer(choice)
    if callback then
      callback(choice)
    end
  end)
end

local function output_split_height()
  return math.max(5, math.floor(vim.o.lines * 0.30))
end

function M.open_output_split(workspace, output_path)
  workspace.ensure_file(output_path)
  local height = output_split_height()
  vim.cmd("botright " .. height .. "split " .. vim.fn.fnameescape(output_path))
  vim.api.nvim_win_set_height(0, height)
  vim.bo.bufhidden = "hide"
  vim.bo.buftype = ""
  vim.bo.swapfile = false
end

function M.build_two_pane_layout(workspace, output_path, code_path)
  workspace.ensure_file(output_path)
  vim.cmd("only")

  if code_path then
    vim.cmd("edit " .. vim.fn.fnameescape(code_path))
  else
    vim.cmd("enew")
  end

  local code_win = vim.api.nvim_get_current_win()
  M.open_output_split(workspace, output_path)
  vim.api.nvim_set_current_win(code_win)
  return code_win
end

function M.output_buffer(workspace, path)
  local target = workspace.normalize(path)
  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    local name = vim.api.nvim_buf_get_name(buf)
    if name ~= "" and workspace.normalize(name) == target then
      return buf
    end
  end

  return nil
end

function M.open_output_buffer(workspace, path)
  local buf = M.output_buffer(workspace, path)
  if not buf then
    return
  end

  vim.api.nvim_buf_call(buf, function()
    vim.cmd("silent edit")
  end)
end

function M.close_output_windows(workspace, path)
  local target = workspace.normalize(path)
  for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
    if #vim.api.nvim_tabpage_list_wins(0) == 1 then
      return
    end

    local buf = vim.api.nvim_win_get_buf(win)
    local name = vim.api.nvim_buf_get_name(buf)
    if name ~= "" and workspace.normalize(name) == target then
      pcall(vim.api.nvim_win_close, win, false)
    end
  end
end

function M.highlight_output(workspace, namespace, path)
  local buf = M.output_buffer(workspace, path)
  if not buf then
    return
  end

  vim.api.nvim_buf_clear_namespace(buf, namespace, 0, -1)
  local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  for i, line in ipairs(lines) do
    for _, pattern in ipairs(error_patterns) do
      if line:match(pattern) then
        vim.api.nvim_buf_add_highlight(buf, namespace, "DiagnosticError", i - 1, 0, -1)
        break
      end
    end
  end
end

return M
