local ts = vim.treesitter
local query = ts.query
local parsers = require("nvim-treesitter.parsers")

local function extract_tasks_and_headers()
	-- local bufnr = vim.api.nvim_get_current_buf()
	local bufnr = 10
	local lang = parsers.get_buf_lang(bufnr)
	local parser = parsers.get_parser(bufnr, lang)
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

	for id, node in q:iter_captures(root, bufnr, 0, -1) do
		local name = q.captures[id]
		local text = ts.get_node_text(node, bufnr)

		if name == "level" then
			heading_level = #text -- number of '#' characters
		elseif name == "heading" then
			-- Flush previous group if needed
			if current_heading and #current_tasks > 0 then
				-- table.insert(results, string.format("H%d: %s", heading_level or 1, current_heading))
				table.insert(results, string.rep("#", heading_level or 1) .. " " .. current_heading)
				for _, task in ipairs(current_tasks) do
					table.insert(results, task)
				end
				table.insert(results, "")
			end
			-- Start new group
			current_heading = text
			current_tasks = {}
		elseif name == "task" then
			table.insert(current_tasks, text)
			table.insert(results, "")
		end
	end

	-- Final flush after loop
	if current_heading and #current_tasks > 0 then
		table.insert(results, string.rep("#", heading_level or 1) .. " " .. current_heading)
		for _, task in ipairs(current_tasks) do
			table.insert(results, task)
		end
	end

	print(vim.inspect(results))

	-- Create a new buffer and write results
	local new_buf = vim.api.nvim_create_buf(false, true)
	vim.api.nvim_buf_set_lines(new_buf, 0, -1, false, results)
	vim.api.nvim_set_current_buf(new_buf)
end

extract_tasks_and_headers()

-- Run it with
-- :lua extract_tasks_and_headers()
