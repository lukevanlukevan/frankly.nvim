# frankly.nvim

A globally accessible pop-up buffer for managing tasks. (inspired by [vimichael](https://github.com/vimichael))

## Install

```lua
return {
  "lukevanlukevan/frankly.nvim",
  opts = {
    target_file = "~/notes/todo.md",
    border = "single" -- single, rounded, etc.
    width = 0.8, -- width of window in % of screen size
    height = 0.8, -- height of window in % of screen size
    position = "center", -- topleft, topright, bottomleft, bottomright
  }
}
```
