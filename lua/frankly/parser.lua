local ts = vim.treesitter
local query = ts.query

local M = {}

local function read_file(path)
	local f = io.open(path, "r")
	if not f then
		return nil
	end
	local content = f:read("*a")
	f:close()
	return content
end

function M.parse_todos(file)
	local usefile = file or ""
	-- local bufnr = 10
	-- local lang = parsers.get_buf_lang(bufnr)
	-- local parser = parsers.get_parser(bufnr, lang)
	-- local tree = parser:parse()[1]
	-- local root = tree:root()

	local content = read_file(file)
	if not content then
		print("Failed to read file:", file)
		return
	end

	local lang = "markdown"
	local parser = ts.get_string_parser(content, lang)
	local tree = parser:parse()[1]
	local root = tree:root()

	-- Load a query from file or use inline
	local q = query.parse(
		lang,
		[[
    (section
      (atx_heading
        [(atx_h1_marker) (atx_h2_marker) (atx_h3_marker)] @level
        (inline) @heading)
      (list
        (list_item
          (task_list_marker_unchecked) @unchecked_marker
          (paragraph (inline) @task))))
    ]]
	)

	local results = {}
	local current_heading = nil
	local heading_level = nil
	local current_tasks = {}

	table.insert(results, "# Todo")

	for id, node in q:iter_captures(root, content, 0, -1) do
		local name = q.captures[id]
		local text = ts.get_node_text(node, content)

		if name == "level" then
			heading_level = #text -- number of '#' characters
		elseif name == "heading" then
			-- Flush previous group if needed
			if current_heading and #current_tasks > 0 then
				table.insert(results, string.rep("#", heading_level or 1) .. " " .. current_heading)

				table.insert(results, "")
				for _, task in ipairs(current_tasks) do
					table.insert(results, task)
				end
				table.insert(results, "")
			end
			-- Start new group
			current_heading = text
			current_tasks = {}
		elseif name == "task" then
			table.insert(current_tasks, "- [ ] " .. text)
			table.insert(results, "")
		end
	end

	-- Final flush after loop
	if current_heading and #current_tasks > 0 then
		table.insert(results, string.rep("#", heading_level or 1) .. " " .. current_heading)
		table.insert(results, "")
		for _, task in ipairs(current_tasks) do
			table.insert(results, task)
		end
	end

	-- clean double empty lines
	local i = 2
	while i <= #results do
		if results[i] == results[i - 1] then
			table.remove(results, i)
		else
			i = i + 1
		end
	end

	return results

	-- Create a new buffer and write results
	-- local new_buf = vim.api.nvim_create_buf(false, true)
	-- vim.api.nvim_buf_set_lines(new_buf, 0, -1, false, results)
	-- vim.api.nvim_set_current_buf(new_buf)
end

return M

-- parse_todos("/Users/lukevan/todo/2025-05-30.md")

-- Run it with
-- :lua extract_tasks_and_headers()
