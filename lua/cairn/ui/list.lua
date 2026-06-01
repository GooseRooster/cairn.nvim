-- cairn/ui/list.lua
-- Renders the mark list buffer and manages cursor state.
-- Knows about display format but not about windows or filter state.

local M = {}

local win_mod = require("cairn.ui.window")
local ok_devicons, devicons = pcall(require, "nvim-web-devicons")

-- Render ----------------------------------------------------------------------

--- Build display lines from filtered results.
--- Returns lines, icon_data where icon_data[i] = {hl, col_start, col_end} or nil.
--- @param results  table  list of {mark, idx, score} from marks.filter()
--- @param config   table  cairn config (used for ui.short_path)
function M.build_lines(results, config)
	if #results == 0 then
		return { "  (no marks)" }, {}
	end

	local short = not (config and config.ui and config.ui.short_path == false)
	local lines = {}
	local icon_data = {}

	for _, r in ipairs(results) do
		local name = vim.fn.fnamemodify(r.mark.file, short and ":t" or ":~:.")
		local prefix = ("  [%d] "):format(r.idx)
		local icon_str = ""
		local ihl = nil

		if ok_devicons then
			local icon, hl = devicons.get_icon(
				vim.fn.fnamemodify(r.mark.file, ":t"),
				vim.fn.fnamemodify(r.mark.file, ":e"),
				{ default = true }
			)
			if icon then
				local col_start = #prefix
				icon_str = icon .. " "
				ihl = { hl = hl, col_start = col_start, col_end = col_start + #icon }
			end
		end

		table.insert(lines, prefix .. icon_str .. name .. " :" .. r.mark.line)
		table.insert(icon_data, ihl)
	end

	return lines, icon_data
end

--- Write lines into the list buffer, preserving modifiable state.
function M.render(buf, lines)
	if not vim.api.nvim_buf_is_valid(buf) then
		return
	end
	vim.bo[buf].modifiable = true
	vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
	vim.bo[buf].modifiable = false
end

--- Apply highlights to the list buffer.
--- Highlights the index number and, when devicons is available, the file icon.
--- @param buf        number  list buffer
--- @param results    table   filtered results (used for index lengths)
--- @param icon_data  table   per-line icon highlight info from build_lines()
function M.apply_highlights(buf, results, icon_data)
	if not vim.api.nvim_buf_is_valid(buf) then
		return
	end
	local ns = vim.api.nvim_create_namespace("cairn_list")
	vim.api.nvim_buf_clear_namespace(buf, ns, 0, -1)

	if #results == 0 then
		return
	end

	for i, r in ipairs(results) do
		-- Highlight [N] — end col accounts for varying index digit count
		local idx_end = 2 + 1 + #tostring(r.idx) + 1
		vim.hl.range(buf, ns, win_mod.HL.index, { i - 1, 2 }, { i - 1, idx_end })

		-- Highlight file type icon if devicons provided one
		local id = icon_data and icon_data[i]
		if id and id.hl then
			vim.hl.range(buf, ns, id.hl, { i - 1, id.col_start }, { i - 1, id.col_end })
		end
	end
end

-- Cursor ----------------------------------------------------------------------

--- Clamp cursor to valid range for results list.
function M.clamp(cursor, results)
	if #results == 0 then
		return 1
	end
	return math.max(1, math.min(cursor, #results))
end

--- Move cursor to row in list window.
function M.set_cursor(win, row)
	if not vim.api.nvim_win_is_valid(win) then
		return
	end
	local line_count = vim.api.nvim_buf_line_count(vim.api.nvim_win_get_buf(win))
	local safe_row = math.max(1, math.min(row, line_count))
	pcall(vim.api.nvim_win_set_cursor, win, { safe_row, 0 })
end

--- Apply cursorline highlight to the active row.
--- We use a dedicated namespace so we can clear/redraw cheaply.
function M.highlight_cursor(buf, row, results)
	if not vim.api.nvim_buf_is_valid(buf) then
		return
	end
	if #results == 0 then
		return
	end
	local ns = vim.api.nvim_create_namespace("cairn_cursor")
	vim.api.nvim_buf_clear_namespace(buf, ns, 0, -1)
	vim.hl.range(buf, ns, win_mod.HL.cursor_line, { row - 1, 0 }, { row - 1, -1 })
end

-- Buffer setup ----------------------------------------------------------------

--- Create and configure the list scratch buffer.
function M.create_buf()
	local buf = vim.api.nvim_create_buf(false, true)
	vim.bo[buf].bufhidden = "wipe"
	vim.bo[buf].modifiable = false
	vim.bo[buf].buftype = "nofile"
	vim.bo[buf].swapfile = false
	return buf
end

return M
