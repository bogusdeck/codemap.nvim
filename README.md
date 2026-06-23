# codemap.nvim

`codemap.nvim` is a small competitive-programming/workspace helper for Neovim. It opens a two-pane layout around a fixed workspace, runs the current solution against `input.txt`, writes results to `output.txt`, and supports quick debugging for Go and Python through `nvim-dap`.

## Features

- Opens a Codemap workspace at `~/Projects/leet`.
- Maintains shared `input.txt` and `output.txt` files.
- Runs Go, Python, JavaScript, TypeScript, Java, C++, C, Rust, and Ruby files.
- Highlights common runtime and compiler errors in the output buffer.
- Provides quick debug entry points for Go and Python when `nvim-dap` is configured.
- Exposes commands and mappings for fast iteration.

## Requirements

- Neovim 0.10+ recommended.
- Runtime tools for the language you want to run, for example `go`, `python3`, `node`, `g++`, `rustc`, or `ruby`.
- Optional: `nvim-dap` for `:CodemapDebug`, `<leader>cd`, or `<F6>`.

## Installation With lazy.nvim

Use the local development path while you are actively editing the plugin:

```lua
return {
  {
    dir = "~/Projects/codemap.nvim",
    name = "codemap.nvim",
    lazy = false,
  },
}
```

After publishing to GitHub, switch to the remote repo:

```lua
return {
  {
    "YOUR_GITHUB_USERNAME/codemap.nvim",
    lazy = false,
  },
}
```

`lazy = false` is intentional because the `codemap` shell launcher starts Neovim and immediately calls `require("codemap")`.

## Usage

Open the shared Codemap workspace:

```vim
:Codemap
```

Run the current code buffer:

```vim
:Run
:CodemapRun
```

Select the language for an unnamed Codemap buffer:

```vim
:CodemapLanguage
```

Debug the current Go or Python buffer:

```vim
:CodemapDebug
```

Default mappings:

- `<leader>cr`: run current Codemap buffer.
- `<F5>`: run current Codemap buffer from normal or insert mode.
- `<leader>cd`: debug current Codemap buffer.
- `<F6>`: debug current Codemap buffer from normal or insert mode.

## Shell Launcher

Your existing launcher can stay as:

```zsh
codemap() {
  /Users/bogusdeck/.local/bin/codemap "$@"
}
```

The launcher starts Neovim in `~/Projects/leet` and calls `require("codemap")`. Keep the Lazy spec installed in your Neovim config so the module is available.

## Development Workflow

Work on the plugin here:

```sh
cd ~/Projects/codemap.nvim
```

Check Lua syntax:

```sh
luac -p lua/codemap/init.lua
```

Format Lua files:

```sh
stylua lua plugin
```

Commit changes:

```sh
git status
git add .
git commit -m "Update codemap"
git push
```

Create the GitHub repository once:

```sh
gh repo create codemap.nvim --public --source=. --remote=origin --push
```

If you do not use GitHub CLI, create an empty `codemap.nvim` repository on GitHub and run:

```sh
git remote add origin git@github.com:YOUR_GITHUB_USERNAME/codemap.nvim.git
git push -u origin main
```
