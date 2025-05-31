local ts = vim.treesitter
local tsq = vim.treesitter.query

local M = {}

local state = {
	win = nil,
	buf = nil,
	file_index = 1,
}

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
		title = { { " Frankly - [meta-n]ext [meta-p]revious [q]uit ", "Normal" } },
		title_pos = "center",
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

-- Tree-sitter section parsing and writing

local function extract_heading_info(node, bufnr)
	local level = 0
	local text = nil

	for child in node:iter_children() do
		local type = child:type()
		if type:match("^atx_h%d+_marker$") then
			level = #vim.treesitter.get_node_text(child, bufnr)
		elseif type == "inline" then
			text = vim.treesitter.get_node_text(child, bufnr)
		end
	end

	return level, text or "Untitled"
end

local function get_heading_path(node, bufnr)
	local current = node
	local headings = {}

	while current do
		local sibling = current:prev_named_sibling()
		while sibling do
			if sibling:type() == "atx_heading" then
				local level, text = extract_heading_info(sibling, bufnr)
				while #headings > 0 and headings[#headings].level >= level do
					table.remove(headings)
				end
				table.insert(headings, { level = level, text = text })
			end
			sibling = sibling:prev_named_sibling()
		end
		current = current:parent()
	end

	table.sort(headings, function(a, b)
		return a.level < b.level
	end)

	local path = {}
	for _, h in ipairs(headings) do
		table.insert(path, h.text)
	end
	return path
end

local function insert_nested(tbl, path, value)
	for i = 1, #path - 1 do
		local key = path[i]
		tbl[key] = tbl[key] or {}
		tbl = tbl[key]
	end

	local last = path[#path]
	tbl[last] = tbl[last] or {}
	table.insert(tbl[last], value)
end

local function get_unchecked_tasks_by_heading(bufnr)
	local root = ts.get_parser(bufnr, "markdown"):parse()[1]:root()
	local query_string = [[
		(list_item
			(task_list_marker_unchecked) @unchecked)
	]]
	local q = tsq.parse("markdown", query_string)
	local results = {}

	for id, node in q:iter_captures(root, bufnr, 0, -1) do
		if q.captures[id] == "unchecked" then
			local list_item_node = node:parent()
			local text = vim.treesitter.get_node_text(list_item_node, bufnr)
			local path = get_heading_path(list_item_node, bufnr)
			if #path == 0 then
				path = { "No Heading" }
			end
			insert_nested(results, path, text)
		end
	end

	return results
end

local function flatten_tasks_by_heading(tree, indent)
	indent = indent or ""
	local lines = {}

	for k, v in pairs(tree) do
		if type(v) == "table" then
			table.insert(lines, indent .. "# " .. k)
			table.insert(lines, "")
			vim.list_extend(lines, flatten_tasks_by_heading(v, indent .. ""))
		else
			table.insert(lines, indent .. v)
			table.insert(lines, "")
		end
	end

	return lines
end

local function write_filtered_todos(src_path, dest_path)
	local buf = vim.fn.bufadd(src_path)
	vim.fn.bufload(buf)

	local task_tree = get_unchecked_tasks_by_heading(buf)
	local lines = flatten_tasks_by_heading(task_tree)
	vim.fn.writefile(lines, dest_path)
end

local function init_buf_keymaps()
	local buf = state.buf
	vim.api.nvim_buf_set_keymap(buf, "n", "q", "", {
		noremap = true,
		silent = true,
		callback = function()
			if vim.api.nvim_get_option_value("modified", { buf = buf }) then
				vim.notify("save your changes pls", vim.log.levels.WARN)
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
			M.walk_files(-1)
		end,
	})
	vim.api.nvim_buf_set_keymap(buf, "n", "<M-p>", "", {
		noremap = true,
		silent = true,
		callback = function()
			M.walk_files(1)
		end,
	})
end

--- @param dir number
M.walk_files = function(dir)
	local tdir = os.getenv("HOME") .. "/todo/"
	local cwdContent = vim.split(vim.fn.glob(tdir .. "/*"), "\n", { trimempty = true })
	state.file_index = state.file_index + dir
	state.file_index = math.min(#cwdContent, state.file_index)
	state.file_index = math.max(1, state.file_index)
	local new_path = cwdContent[state.file_index]
	print(new_path)

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
	if state.win ~= nil and vim.api.nvim_win_is_valid(state.win) then
		vim.api.nvim_set_current_win(state.win)
		return
	end

	local new_path = create_dated_file(opts)
	if vim.fn.filereadable(new_path) == 0 then
		local last_todo = expand_path(get_previous_todo(opts))
		write_filtered_todos(last_todo, new_path)
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
	setup_user_commands(opts)
end

return M
