local M = {}

local config_mod = require("codemap.config")
local languages = require("codemap.languages")
local workspace = require("codemap.workspace")
local ui = require("codemap.ui")
local runner = require("codemap.runner")
local debugger = require("codemap.debug")

local state = {
  config = config_mod.new(),
  output_namespace = vim.api.nvim_create_namespace("codemap-output"),
  commands_created = false,
  keymaps_created = false,
}

local function current_language()
  return languages.default_for(vim.g.codemap_language or state.config.default_language)
end

local function runner_language_for_buffer(buf)
  local by_filetype = languages.find_by_filetype(vim.bo[buf].filetype)
  if by_filetype then
    return by_filetype
  end

  return current_language()
end

local function open_shared_layout()
  workspace.ensure_workspace(state.config)
  vim.cmd("cd " .. vim.fn.fnameescape(workspace.workspace_path(state.config)))

  local _, output_path = workspace.mapped_paths(state.config)
  local code_win = ui.build_two_pane_layout(workspace, output_path)
  vim.api.nvim_set_current_win(code_win)
  ui.apply_language_to_current_buffer(current_language())

  if #vim.api.nvim_list_uis() > 0 then
    vim.schedule(function()
      if vim.api.nvim_win_is_valid(code_win) then
        vim.api.nvim_set_current_win(code_win)
        ui.select_language(languages.all)
      end
    end)
  end
end

local function open_for_code(code_path)
  workspace.ensure_workspace(state.config)
  vim.cmd("cd " .. vim.fn.fnameescape(workspace.workspace_path(state.config)))

  local _, output_path = workspace.mapped_paths(state.config)
  workspace.ensure_file(output_path)
  ui.build_two_pane_layout(workspace, output_path, code_path)
end

function M.open(code_path)
  local target_code = code_path or workspace.code_file_for_current_buffer(state.config)
  if target_code then
    open_for_code(target_code)
    return
  end

  open_shared_layout()
end

function M.run()
  runner.run({
    config = state.config,
    workspace = workspace,
    ui = ui,
    output_namespace = state.output_namespace,
    runner_language_for_buffer = runner_language_for_buffer,
  })
end

function M.debug()
  debugger.debug({
    config = state.config,
    workspace = workspace,
    ui = ui,
    runner_language_for_buffer = runner_language_for_buffer,
  })
end

local function create_commands()
  if state.commands_created then
    return
  end

  vim.api.nvim_create_user_command("Run", function()
    M.run()
  end, { desc = "Run current Codemap buffer" })

  vim.api.nvim_create_user_command("Codemap", function()
    M.open()
  end, { desc = "Open Codemap two-pane workspace" })

  vim.api.nvim_create_user_command("CodemapLanguage", function()
    ui.select_language(languages.all)
  end, { desc = "Select language for current Codemap buffer" })

  vim.api.nvim_create_user_command("CodemapRun", function()
    M.run()
  end, { desc = "Run current Codemap buffer with input.txt and write output.txt" })

  vim.api.nvim_create_user_command("CodemapDebug", function()
    M.debug()
  end, { desc = "Debug current Codemap buffer with nvim-dap" })

  state.commands_created = true
end

local function create_keymaps()
  if state.keymaps_created or not state.config.keymaps then
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

  state.keymaps_created = true
end

function M.setup(opts)
  state.config = config_mod.merge(opts)
  create_commands()
  create_keymaps()
end

return M
