if vim.g.loaded_codemap_nvim then
  return
end

vim.g.loaded_codemap_nvim = true
require("codemap").setup()
