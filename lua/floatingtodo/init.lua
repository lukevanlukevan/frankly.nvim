local ts = vim.treesitter
local tsq = vim.treesitter.query

local M = {}

local win = nil

local default_opts = {
	target_dir = "~/todo",
	target_file = "~/notes/todo.md",
	border = "single",
	width = 0.8,
	height = 0.8,
	position = "center",
}

local function expand_path(path)
	if path:sub(1, 1) == "~" then
		return os.getenv("HOME") .. path:sub(2)
	end
	return path
end

local function calculate_position(position)
	local posx, posy = 0.5, 0.5
	if type(position) == "table" then
		posx, posy = position[1], position[2]
	elseif position == "center" then
		posx, posy = 0.5, 0.5
	elseif position == "topleft" then
		posx, posy = 0, 0
	elseif position == "topright" then
		posx, posy = 1, 0
	elseif position == "bottomleft" then
		posx, posy = 0, 1
	elseif position == "bottomright" then
		posx, posy = 1, 1
	end
	return posx, posy
end

local function win_config(opts)
	local width = math.min(math.floor(vim.o.columns * opts.width), 64)
	local height = math.floor(vim.o.lines * opts.height)
	local col = math.floor((vim.o.columns - width) * calculate_position(opts.position))
	local row = math.floor((vim.o.lines - height) * select(2, calculate_position(opts.position)))
	return {
		relative = "editor",
		width = width,
		height = height,
		col = col,
		row = row,
		border = opts.border,
	}
end

local function create_dated_file(opts)
	local date_str = os.date("%Y-%m-%d")
	return expand_path(opts.target_dir .. "/" .. date_str .. ".md")
end

local function get_previous_todo(opts)
	local target_dir = opts.target_dir or "."
	local days_back = 1
	local md_ext = ".md"

	while true do
		local timestamp = os.time() - (days_back * 86400)
		local date_str = os.date("%Y-%m-%d", timestamp)
		local filepath = expand_path(target_dir .. "/" .. date_str .. md_ext)
		if vim.fn.filereadable(filepath) == 1 then
			return filepath
		end
		days_back = days_back + 1
		if days_back > 365 then
			return nil
		end
	end
end

local function write_filtered_todos(src_path, dest_path)
	local lines = vim.fn.readfile(src_path)
	local filtered = {}

	for _, line in ipairs(lines) do
		if not line:match("%- %[x%]") then
			table.insert(filtered, line)
		end
	end

	vim.fn.writefile(filtered, dest_path)
end

local function open_floating_file(opts)
	if win ~= nil and vim.api.nvim_win_is_valid(win) then
		vim.api.nvim_set_current_win(win)
		return
	end

	local new_path = create_dated_file(opts)
	if vim.fn.filereadable(new_path) == 0 then
		local last_todo = expand_path(get_previous_todo(opts))
		write_filtered_todos(last_todo, new_path)
	end
	-- vim.cmd("e " .. new_path)

	local buf = vim.fn.bufnr(new_path, true)

	if buf == -1 then
		buf = vim.api.nvim_create_buf(false, false)
		vim.api.nvim_buf_set_name(buf, new_path)
	end

	vim.bo[buf].swapfile = false

	win = vim.api.nvim_open_win(buf, true, win_config(opts))

	vim.api.nvim_buf_set_keymap(buf, "n", "q", "", {
		noremap = true,
		silent = true,
		callback = function()
			if vim.api.nvim_get_option_value("modified", { buf = buf }) then
				vim.notify("save your changes pls", vim.log.levels.WARN)
			else
				vim.api.nvim_win_close(0, true)
				win = nil
			end
		end,
	})
end

local function setup_user_commands(opts)
	opts = vim.tbl_deep_extend("force", default_opts, opts)

	vim.api.nvim_create_user_command("Td", function()
		open_floating_file(opts)
	end, {})
	vim.keymap.set("n", "<leader>td", ":Td<cr>", { silent = true, desc = "Open To Do List" })
end

M.setup = function(opts)
	setup_user_commands(opts)
end

return M
