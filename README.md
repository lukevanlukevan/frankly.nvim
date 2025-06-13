# frankly.nvim

A globally accessible pop-up buffer for managing tasks. (inspired by [vimichael](https://github.com/vimichael))

![frank-preview](/Frankly_overview.webp)

## Install

```lua
return {
  "lukevanlukevan/frankly.nvim",
  opts = {
    target_dir = "$TODOS"
    border = "single" -- single, rounded, etc.
    width = 0.8, -- width of window in % of screen size
    height = 0.8, -- height of window in % of screen size
    position = "center", -- topleft, topright, bottomleft, bottomright
  }
}
```

## Usage

The latest markdown file is loaded from the `target_dir` path. This can be set explicitly, or using an environment variable (case sensitive).

Environment variable is useful if you are storing the files on Dropbox or have files in different locations on different machines.
