# cairn.nvim

> Stack your stones. Find your way back.

Cairn is a lightweight, workspace-scoped file mark system for Neovim with a
[Telescope](https://github.com/nvim-telescope/telescope.nvim) picker, inspired
by Harpoon. Marks remember **line and column**, are **scoped to your
project**, and re-marking a file **updates** its position rather than
duplicating it.

Think of it as tabs for the files that actually matter — without the clutter.



---

## Features

- **Workspace-scoped marks** — keyed by git root (or cwd fallback), so each project has its own independent list
- **Line + column memory** — marks land you exactly where you set them
- **Smart re-marking** — marking an already-marked file updates its position instead of adding a duplicate
- **Telescope picker** — preview scrolls to and highlights the marked line
- **In-picker management** — reorder and delete marks without leaving the picker
- **Index-based jumps** — `<leader>1` through `<leader>9` for instant navigation
- **Persistent storage** — marks survive restarts, reloads, and SSH reconnections (plain JSON on disk)
- **Zero setup required** — sane defaults out of the box

---

## Requirements

- Neovim `>= 0.9`
- [telescope.nvim](https://github.com/nvim-telescope/telescope.nvim) (for the picker)

---

## Installation

### [lazy.nvim](https://github.com/folke/lazy.nvim)

```lua
{
  "GooseRooser/cairn.nvim",
  dependencies = { "nvim-telescope/telescope.nvim" },
  config = function()
    require("cairn").setup()
  end,
}
```

### [packer.nvim](https://github.com/wbthomason/packer.nvim)

```lua
use {
  "GooseRooster/cairn.nvim",
  requires = { "nvim-telescope/telescope.nvim" },
  config = function()
    require("cairn").setup()
  end,
}
```

---

## Usage

### Marking files

Open any file and press `<leader>ma` to drop a mark at your current line and
column. The mark is saved immediately.

If the file is already marked, the existing mark is **updated** to your current
position — no duplicates.

### Jumping to marks

| Keymap       | Action                   |
|--------------|--------------------------|
| `<leader>1`  | Jump to first mark       |
| `<leader>2`  | Jump to second mark      |
| `<leader>3–9`| Jump to respective marks |

### Picker

Press `<leader>mm` to open the Telescope picker.

```
[1] src/server/api.lua:42
[2] src/db/queries.lua:108
[3] tests/api_spec.lua:17
```

The preview panel scrolls directly to and highlights the marked line.

**Picker keymaps:**

| Key       | Action              |
|-----------|---------------------|
| `<CR>`    | Open file at mark   |
| `<C-d>`   | Delete selected mark|
| `<C-S-j>` | Move mark down      |
| `<C-S-k>` | Move mark up        |

### Removing marks

- `<leader>md` — remove the mark for the current file
- `<C-d>` inside the picker — remove any selected mark

---

## Configuration

Call `setup()` with any overrides. All keys are optional.

```lua
require("cairn").setup({
  -- Where mark files are stored (one JSON file per workspace)
  data_dir = vim.fn.stdpath("data") .. "/cairn",

  -- Use git root as workspace key; falls back to cwd when not in a git repo
  use_git_root = true,

  -- Normal-mode keymaps
  keymaps = {
    add          = "<leader>ma",  -- add or update mark at cursor
    remove       = "<leader>md",  -- remove mark for current file
    picker       = "<leader>mm",  -- open Telescope picker
    index_prefix = "<leader>",    -- prefix for <leader>1 – <leader>9 jumps
  },

  -- Keymaps active inside the Telescope picker
  picker = {
    delete    = "<C-d>",   -- delete selected mark
    move_down = "<C-S-j>", -- move selected mark down
    move_up   = "<C-S-k>", -- move selected mark up
  },
})
```

### Disabling default keymaps

Pass empty strings to suppress any keymap:

```lua
require("cairn").setup({
  keymaps = {
    add          = "",
    remove       = "",
    picker       = "",
    index_prefix = "",
  },
})
```

Then wire up your own:

```lua
local cairn = require("cairn")
vim.keymap.set("n", "<C-a>",      cairn.add_mark,      { desc = "Cairn: mark" })
vim.keymap.set("n", "<C-e>",      cairn.picker,         { desc = "Cairn: picker" })
vim.keymap.set("n", "<C-1>",      function() cairn.goto_index(1) end)
```

---

### Wiring up for which-key
```lua
```
{
  "GooseRooster/cairn.nvim",
  dependencies = { 
    "nvim-telescope/telescope.nvim",
    "folke/which-key.nvim",
  },
  config = function()
    require("cairn").setup()

    require("which-key").add({
      { "<leader>m", group = "󰔷 cairn", icon = "󰔷" },
    })
  end,
}
```
```
## API

| Function                | Description                                      |
|-------------------------|--------------------------------------------------|
| `cairn.setup(opts)`     | Configure and initialise the plugin              |
| `cairn.add_mark()`      | Mark current file at cursor position             |
| `cairn.remove_current()`| Remove mark for the current file                 |
| `cairn.goto_index(n)`   | Jump to the nth mark                             |
| `cairn.picker()`        | Open the Telescope picker                        |
| `cairn.get_marks()`     | Return the current workspace mark list (table)   |
| `cairn.clear_marks()`   | Remove all marks for the current workspace       |

---

## Mark storage

Marks are stored as plain JSON in `data_dir`, one file per workspace:

```
~/.local/share/nvim/cairn/
  myapp.json
  myapp2.json
```

Each file contains an array of `{ file, line, col }` objects. You can inspect,
back up, or version-control them freely.

---

## License

MIT — see [LICENSE](LICENSE)

## Contributing
Improvements, suggestions, and pull requests are all welcome!
