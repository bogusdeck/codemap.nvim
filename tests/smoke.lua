local codemap = require("codemap")

local workspace = vim.fn.tempname()

codemap.setup({
  workspace = workspace,
  keymaps = false,
  default_language = "python",
})

local expected_commands = {
  "Codemap",
  "Run",
  "CodemapRun",
  "CodemapLanguage",
  "CodemapDebug",
}

for _, command in ipairs(expected_commands) do
  assert(vim.fn.exists(":" .. command) == 2, "missing command: " .. command)
end

assert(vim.g.codemap_language == nil, "setup should not force a language before use")
