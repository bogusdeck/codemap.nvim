# codemap.nvim

`codemap.nvim` is a small Neovim helper for competitive programming and scratch work. It opens a two-pane workspace, keeps shared `input.txt` and `output.txt` files, runs the current solution, and can hand Go or Python buffers off to `nvim-dap`.

## Features

- Opens a dedicated Codemap workspace with a code pane and output pane.
- Maintains shared `input.txt` and `output.txt` files inside the workspace.
- Runs Go, Python, JavaScript, TypeScript, Java, C++, C, Rust, and Ruby buffers.
- Highlights common runtime and compiler errors in the output buffer.
- Supports quick debugging for Go and Python through `nvim-dap`.
- Ships with user commands and optional default keymaps.

## Requirements

- Neovim 0.10 or newer.
- Language runtimes or compilers for the languages you plan to run.
- Optional: `nvim-dap` for `:CodemapDebug`.

## Installation

### lazy.nvim

```lua
return {
  {
    "bogusdeck/codemap.nvim",
    lazy = false,
    config = function()
      require("codemap").setup()
    end,
  },
}
```

## Configuration

Default configuration:

```lua
require("codemap").setup({
  workspace = vim.fn.stdpath("data") .. "/codemap",
  run_timeout_ms = 3000,
  default_language = "go",
  keymaps = true,
})
```

Options:

- `workspace`: directory used for shared `input.txt`, `output.txt`, and build artifacts.
- `run_timeout_ms`: timeout for code execution.
- `default_language`: fallback filetype for unnamed buffers.
- `keymaps`: enable or disable the built-in mappings.

Example with a custom workspace and no default mappings:

```lua
require("codemap").setup({
  workspace = "~/Projects/leet",
  keymaps = false,
})
```

## Commands

- `:Codemap` opens the shared two-pane workspace.
- `:Run` runs the current Codemap buffer.
- `:CodemapRun` runs the current Codemap buffer.
- `:CodemapLanguage` selects a language for the current unnamed Codemap buffer.
- `:CodemapDebug` starts a debug session for the current Go or Python buffer.

## Default Keymaps

- `<leader>cr`: run the current Codemap buffer.
- `<F5>`: run the current Codemap buffer from normal or insert mode.
- `<leader>cd`: debug the current Codemap buffer.
- `<F6>`: debug the current Codemap buffer from normal or insert mode.

## Workspace Layout

Codemap stores its files under the configured `workspace`:

- `input.txt`: stdin for the current run.
- `output.txt`: stdout and stderr from the current run.
- `.codemap-build/`: temporary sources, binaries, and debug helpers.

## Development

```sh
luac -p lua/codemap/init.lua
stylua lua plugin
nvim --headless -u NONE -i NONE -n +"set rtp+=." +"runtime plugin/codemap.lua" +"lua dofile('tests/smoke.lua')" +qa
```

## License

MIT. See [LICENSE](LICENSE).
