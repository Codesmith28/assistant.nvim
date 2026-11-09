# assistant.nvim

A fast, lightweight Neovim testcase companion for competitive programming, forked and enhanced from [A7Lavinraj/assistant.nvim](https://github.com/A7Lavinraj/assistant.nvim). It integrates with [Competitive Companion](https://github.com/jmerle/competitive-companion) to parse test cases, run them asynchronously, and inspect outputs side-by-side with minimal friction.

---

## ✨ Key Improvements in this Fork

- **Smart Toolchain Auto-Discovery**: Automatically discovers modern compilers (versioned `g++-14..g++`, `clang++`, `python3`, `rustc`), detects the highest supported C++ standard (`-std=c++26` down to `c++17`), and sets optimal CP flags with zero boilerplate.
- **Native Buffer Writing**: Full `:w`, `:wq`, and `<C-s>` support in the testcase patcher using `acwrite`, with real-time preview canvas updates.
- **Seamless Testcase Creation**: Pressing `c` or `o` sequentially prompts for testcase input followed immediately by expected output.
- **Smart Root Detection**: Automatically resolves `.ast/` testcase storage and `.ast/bin/` binary output relative to either the source file's directory or the current working directory.
- **Native Binary Output Support**: Built-in `.ast/bin/` support with automated directory creation and path resolution for subdirectories (using `$OUT_DIR`), cleanly isolating compiled binaries inside `.ast/` with no separate `.bin/` directory cluttering your repo.
- **Competitive Companion Auto-Source**: Automatically chooses the language without prompting when `default_source` is configured or only a single command exists.
- **Buffer Safety**: Automatically detaches active LSP clients and disables autoformatting (`b:autoformat = false`) on all assistant UI and patcher buffers.
- **Immediate Disk Persistence**: Changes to testcases persist to disk immediately across creation, editing, deletion, and on exit.
- **UI Polish**: Informative empty-state view and quick-reference keymap hints directly inside the panel footer.

---

## 📦 Requirements

- Neovim `>= 0.9.5`
- [Competitive Companion](https://github.com/jmerle/competitive-companion) browser extension (configured to port `10043`)

---

## 🚀 Installation

Using [lazy.nvim](https://github.com/folke/lazy.nvim):

```lua
{
  'Codesmith28/assistant.nvim',
  keys = {
    { '<leader>a', '<cmd>Assistant<cr>', desc = 'Assistant.nvim' },
  },
  opts = {
    -- configuration goes here (see below)
  },
}
```

---

## ⚙️ Configuration & Toolchain Discovery

`assistant.nvim` automatically discovers the modern compilers on your system (`g++`, `clang++`, `python3`, `rustc`), detects the highest supported standard (e.g. `-std=c++26`), enables recommended CP debug flags (`-Wall -Wextra -D_GLIBCXX_DEBUG`), and cleanly isolates binaries inside `.ast/bin/` without cluttering the repository.

**Zero configuration is required!** You can pass `{}` or customize options as desired:

```lua
require('assistant').setup({
  core = {
    port = 10043,            -- Competitive Companion listener port
    process_budget = 5000,   -- Execution timeout in milliseconds (TL)
    default_source = 'cpp',  -- Auto-select without prompting
    out_dir = '.ast/bin',    -- Auto-created directory for compiled binaries
  },
  ui = {
    border = 'rounded',
    diff_mode = false,
    title_components_separator = '',
  },
  -- Optional: customize or override any language command
  commands = {
    cpp = {
      compile = {
        args = {
          '$FILENAME_WITH_EXTENSION',
          '-std=c++26',
          '-O2',
          '-Wall',
          '-Wextra',
          '-o',
          './$OUT_DIR/$FILENAME_WITHOUT_EXTENSION',
        },
      },
    },
  },
})
```

### Available Placeholders

- `$FILENAME_WITH_EXTENSION` – Full file name (e.g., `solution.cpp`)
- `$FILENAME_WITHOUT_EXTENSION` – File name without extension (e.g., `solution`)
- `$OUT_DIR` – Configured binary output directory (default: `.ast/bin`)
- `$FILEDIR` – Directory containing the active source file

---

## ⌨️ Default Keybindings

### Panel (`assistant-panel`)

| Key | Action |
| --- | --- |
| `c`, `o` | Create new testcase (sequentially prompts for input then output) |
| `<CR>`, `e` | Edit / patch selected testcase |
| `r` | Run selected testcase(s) or current testcase |
| `s` | Toggle selection for current testcase |
| `a` | Toggle selection for all testcases |
| `d` | Delete selected testcase(s) |
| `i` | Open interactive terminal execution |
| `<C-l>` | Focus previewer window |
| `q`, `<C-c>`, `<Esc>` | Close Assistant |
| `?` | Show Which-Key dialog with all mappings |

### Previewer (`assistant-previewer`)

| Key | Action |
| --- | --- |
| `<CR>`, `e` | Edit testcase currently in preview |
| `<C-h>` | Focus back to panel window |
| `q`, `<C-c>`, `<Esc>` | Close Assistant |
| `?` | Show Which-Key dialog with all mappings |

### Patcher (`assistant-patcher`)

| Key | Action |
| --- | --- |
| `:w`, `<C-s>` | Save testcase buffer & refresh preview immediately |
| `:wq`, `<CR>` | Save changes and close patcher buffer |
| `:q`, `<C-c>` | Close patcher buffer without saving |
| `<Esc>` | Disallowed to prevent accidental closure without saving |
