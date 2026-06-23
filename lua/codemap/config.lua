local M = {}

M.defaults = {
  workspace = vim.fn.stdpath("data") .. "/codemap",
  run_timeout_ms = 3000,
  default_language = "go",
  keymaps = true,
}

function M.new()
  return vim.deepcopy(M.defaults)
end

function M.merge(opts)
  return vim.tbl_deep_extend("force", vim.deepcopy(M.defaults), opts or {})
end

return M
