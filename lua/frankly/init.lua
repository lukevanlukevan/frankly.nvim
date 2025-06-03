local ts = vim.treesitter
local tsq = vim.treesitter.query
local tdparser = require("frankly.parser")

local M = {}

local state = {
	win = nil,
	buf = nil,
	file_index = 1,
	target_dir = "",
	opts = {},
}

local default_opts = {
	target_dir = "~/todo",
	border = "single",
	width = 100,
	height = 45,
}

local function expand_path(path)
	if path then
		-- if path:sub(1,1) == "$"
		if path:sub(1, 1) == "~" then
			return os.getenv("HOME") .. path:sub(2)
		end
		return path
	end
	return path
end

local function win_config(opts)
	local basew = vim.o.columns
	local baseh = vim.o.lines

	local width = math.min(basew, opts.width)
	local height = math.min(baseh - 5, opts.height)
	local col = (basew - width) / 2
	local row = math.max(((baseh - height) / 2) - 2, 1)
	-- local width = math.min(math.floor(vim.o.columns * opts.width), 64)
	-- local height = math.floor(vim.o.lines * opts.height)
	-- local col = math.floor((vim.o.columns - width) * calculate_position(opts.position))
	-- local row = math.floor((vim.o.lines - height) * select(2, calculate_position(opts.position)))
	return {
		relative = "editor",
		width = width,
		height = height,
		col = col,
		row = row,
		border = opts.border,
		title = { { " Frankly ", "Normal" } },
		title_pos = "center",
		footer = { { " Next [meta-n] - Previous [meta-p] - Fullscreen [f] - Quit [q] ", "Normal" } },
		footer_pos = "center",
	}
end

local function get_dated_file_path(opts)
	local date_str = os.date("%Y-%m-%d")
	return expand_path(opts.target_dir .. "/" .. date_str .. ".md")
end

local function handle_commit()
	os.execute("cd " .. state.target_dir)
	os.execute("git add .")
	os.execute("git commit -m '" .. os.date("%Y-%m-%d:%H-%M") .. "'")
	os.execute("git push")
	-- os.execute("git pull")
end

local function handle_fetch()
	os.execute("cd " .. state.target_dir .. " && git fetch")
	-- os.execute("git fetch")
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
			return filepath, true
		end
		days_back = days_back + 1
		if days_back > 365 then
			return nil, false
		end
	end
end

local function init_buf_keymaps()
	local buf = state.buf

	local cmdid = vim.api.nvim_create_autocmd("VimResized", {
		buffer = state.buf,
		callback = function()
			vim.api.nvim_win_set_config(state.win, win_config(state.opts))
		end,
	})
	vim.api.nvim_buf_set_keymap(buf, "n", "q", "", {
		noremap = true,
		silent = true,
		callback = function()
			if vim.api.nvim_get_option_value("modified", { buf = buf }) then
				vim.notify("Unsaved changes!", vim.log.levels.WARN)
			else
				vim.api.nvim_win_close(0, true)
				state.win = nil
				state.buf = nil
			end
		end,
	})
	vim.api.nvim_buf_set_keymap(buf, "n", "<M-n>", "", {
		noremap = true,
		silent = true,
		callback = function()
			vim.api.nvim_clear_autocmds({ buffer = buf })
			M.walk_files(1)
		end,
	})
	vim.api.nvim_buf_set_keymap(buf, "n", "<M-p>", "", {
		noremap = true,
		silent = true,
		callback = function()
			vim.api.nvim_clear_autocmds({ buffer = buf })
			M.walk_files(-1)
		end,
	})
	vim.api.nvim_buf_set_keymap(buf, "n", "f", "", {
		noremap = true,
		silent = true,
		callback = function()
			state.win = nil
			state.bug = true
			local fp = vim.api.nvim_buf_get_name(0)
			vim.api.nvim_win_close(0, true)
			vim.cmd("e " .. fp)
		end,
	})

	-- vim.api.nvim_create_autocmd("BufWritePost", {
	-- 	buffer = state.buf,
	-- 	callback = function()
	-- 		vim.schedule(function()
	-- 			handle_commit()
	-- 		end)
	-- 	end,
	-- })
	vim.api.nvim_create_autocmd("BufWinLeave", {
		buffer = state.buf,
		callback = function()
			vim.api.nvim_del_autocmd(cmdid)
		end,
	})
end

--- @param dir number
M.walk_files = function(dir)
	local tdir = state.target_dir
	local cwdContent = vim.split(vim.fn.glob(tdir .. "/*"), "\n", { trimempty = true })
	state.file_index = state.file_index + dir
	state.file_index = math.min(#cwdContent, state.file_index)
	state.file_index = math.max(1, state.file_index)
	local new_path = cwdContent[state.file_index]

	local buf = vim.fn.bufnr(new_path, true)

	if buf == -1 then
		buf = vim.api.nvim_create_buf(false, false)
		vim.api.nvim_buf_set_name(buf, new_path)
	end

	vim.bo[buf].swapfile = false

	state.buf = buf

	if state.win and vim.api.nvim_win_is_valid(state.win) then
		vim.api.nvim_win_set_buf(state.win, buf)
	end
	init_buf_keymaps()
end

local function open_floating_file(opts)
	-- handle_fetch()
	if state.win ~= nil and vim.api.nvim_win_is_valid(state.win) then
		vim.api.nvim_set_current_win(state.win)
		return
	end

	local new_path = get_dated_file_path(opts)
	if vim.fn.filereadable(new_path) == 0 then
		local dest_path = get_dated_file_path(opts)
		local raw_last, has_last = get_previous_todo(opts)
		if has_last then
			local last_todo = expand_path(raw_last)
			local clean_todos = tdparser.parse_todos(last_todo)
			vim.fn.writefile(clean_todos, dest_path)
		else
			vim.fn.writefile({ "# Todo", "" }, dest_path)
		end
	end

	local buf = vim.fn.bufnr(new_path, true)

	if buf == -1 then
		buf = vim.api.nvim_create_buf(false, false)
		vim.api.nvim_buf_set_name(buf, new_path)
	end

	vim.bo[buf].swapfile = false

	state.win = vim.api.nvim_open_win(buf, true, win_config(opts))
	state.buf = buf

	vim.cmd("set nonumber")
	vim.cmd("set norelativenumber")
	vim.cmd("set statuscolumn=")
	vim.cmd("set signcolumn=no")

	init_buf_keymaps()
end

local function setup_user_commands(opts)
	opts = vim.tbl_deep_extend("force", default_opts, opts)

	vim.api.nvim_create_user_command("Td", function()
		open_floating_file(opts)
	end, {})
	vim.keymap.set("n", "<leader>td", ":Td<cr>", { silent = true, desc = "Open To Do List" })
end

M.setup = function(opts)
	state.target_dir = opts.target_dir
	state.opts = opts
	setup_user_commands(opts)
end

return M
