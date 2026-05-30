-- cairn/ui/list.lua
-- Renders the mark list buffer and manages cursor state.

local M = {}

local win_mod = require("cairn.ui.window")

-- Render ----------------------------------------------------------------------

--- Build display lines from filtered results.
--- @param results  table  list of {mark, idx, score} from marks.filter()
--- @return table   lines to set in buffer
function M.build_lines(results)
	if #results == 0 then
		return { "  (no marks)" }
	end
	local lines = {}
	for _, r in ipairs(results) do
		local rel = vim.fn.fnamemodify(r.mark.file, ":~:.")
		local line = ("[%d] %s :%d"):format(r.idx, rel, r.mark.line)
		table.insert(lines, "  " .. line)
	end
	return lines
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

--- Apply highlights to the list buffer for a given set of results.
--- Highlights the index number distinctly from the path.
function M.apply_highlights(buf, results)
	if not vim.api.nvim_buf_is_valid(buf) then
		return
	end
	local ns = vim.api.nvim_create_namespace("cairn_list")
	vim.api.nvim_buf_clear_namespace(buf, ns, 0, -1)

	if #results == 0 then
		return
	end

	for i, _ in ipairs(results) do
		-- Highlight the [N] index token (cols 2-4 typically)
		vim.hl.range(buf, ns, win_mod.HL.index, { i - 1, 2 }, { i - 1, 4 })
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
