local M = {}

local function normalize(path)
  return vim.fn.fnamemodify(path, ":p")
end

function M.normalize(path)
  return normalize(path)
end

function M.workspace_path(config)
  return normalize(vim.fn.expand(config.workspace))
end

function M.build_dir(config)
  return normalize(M.workspace_path(config) .. "/.codemap-build")
end

function M.mapped_paths(config)
  local root = M.workspace_path(config)
  return normalize(root .. "/input.txt"), normalize(root .. "/output.txt")
end

function M.is_workspace_file(config, path)
  local full_path = normalize(path)
  local root = M.workspace_path(config)
  return full_path:sub(1, #root) == root
end

function M.is_sidecar(path)
  return path:match("%.input%.txt$") ~= nil
end

function M.is_shared_io_file(config, path)
  local input_path, output_path = M.mapped_paths(config)
  local normalized = normalize(path)
  return normalized == input_path or normalized == output_path
end

function M.ensure_workspace(config)
  vim.fn.mkdir(M.workspace_path(config), "p")
  vim.fn.mkdir(M.build_dir(config), "p")
end

function M.ensure_file(path)
  if vim.fn.filereadable(path) == 0 then
    vim.fn.writefile({}, path)
  end
end

function M.code_file_for_current_buffer(config)
  local path = vim.api.nvim_buf_get_name(0)
  if path == "" then
    return nil
  end

  path = normalize(path)
  if not M.is_workspace_file(config, path) or M.is_sidecar(path) or M.is_shared_io_file(config, path) then
    return nil
  end

  return path
end

function M.code_file_in_current_tab(config)
  for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
    local buf = vim.api.nvim_win_get_buf(win)
    local name = vim.api.nvim_buf_get_name(buf)
    if name ~= "" then
      local path = normalize(name)
      if M.is_workspace_file(config, path) and not M.is_sidecar(path) and not M.is_shared_io_file(config, path) then
        return path, buf
      end
    end
  end

  return nil, nil
end

function M.autosave_codemap_buffers(config)
  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_loaded(buf) and vim.bo[buf].modified and vim.bo[buf].buftype == "" then
      local name = vim.api.nvim_buf_get_name(buf)
      if name ~= "" and M.is_workspace_file(config, name) then
        vim.api.nvim_buf_call(buf, function()
          vim.cmd("silent write")
        end)
      end
    end
  end
end

function M.temp_source_path(config, language)
  return normalize(M.build_dir(config) .. "/main." .. language.ext)
end

function M.temp_binary_path(config, name)
  return normalize(M.build_dir(config) .. "/" .. name)
end

function M.python_debug_wrapper_path(config)
  return normalize(M.build_dir(config) .. "/python-debug-wrapper.py")
end

function M.write_python_debug_wrapper(config, source_path, input_path)
  local wrapper_path = M.python_debug_wrapper_path(config)
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

return M
