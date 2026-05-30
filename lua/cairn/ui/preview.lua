-- cairn/ui/preview.lua
-- Loads a real file buffer into the preview window so treesitter,
-- syntax highlighting and LSP signs all work automatically.

local M = {}

local win_mod = require("cairn.ui.window")

-- We keep a single scratch buf for the "no preview" state
local _empty_buf = nil

local function get_empty_buf()
	if not _empty_buf or not vim.api.nvim_buf_is_valid(_empty_buf) then
		_empty_buf = vim.api.nvim_create_buf(false, true)
		vim.bo[_empty_buf].bufhidden = "wipe"
	end
	return _empty_buf
end

--- Load file into the preview window, scrolled to lnum.
--- We use a real buffer (not scratch) so filetype detection fires.
--- @param win    number   preview window id
--- @param file   string   absolute path
--- @param lnum   number   1-based line to centre on
function M.load(win, file, lnum)
	if not vim.api.nvim_win_is_valid(win) then
		return
	end

	-- Check file is readable
	if vim.fn.filereadable(file) == 0 then
		M.clear(win)
		return
	end

	-- Use a scratch buffer loaded with the file content so we don't pollute
	-- the buffer list but still get full highlighting.
	local buf = vim.api.nvim_create_buf(false, true)

	-- Read file contents
	local lines = vim.fn.readfile(file)
	vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)

	-- Detect filetype from the filename so treesitter kicks in
	local ft = vim.filetype.match({ filename = file, buf = buf })
	if ft then
		vim.bo[buf].filetype = ft
	end

	vim.bo[buf].modifiable = false
	vim.bo[buf].bufhidden = "wipe"
	vim.bo[buf].swapfile = false

	-- Swap the buffer in the preview window
	local prev_buf = vim.api.nvim_win_get_buf(win)
	vim.api.nvim_win_set_buf(win, buf)

	-- Clean up the old scratch buffer if it was one we created
	if prev_buf ~= get_empty_buf() then
		pcall(vim.api.nvim_buf_delete, prev_buf, { force = true })
	end

	-- Window-local options for a clean read-only view
	vim.wo[win].number = true
	vim.wo[win].relativenumber = false
	vim.wo[win].wrap = false
	vim.wo[win].signcolumn = "no"
	vim.wo[win].foldenable = false
	vim.wo[win].cursorline = true

	-- Scroll to marked line, centred
	local line_count = vim.api.nvim_buf_line_count(buf)
	local target = math.min(math.max(lnum, 1), line_count)
	vim.api.nvim_win_set_cursor(win, { target, 0 })

	-- Centre the view on the target line
	vim.api.nvim_win_call(win, function()
		vim.cmd("norm! zz")
	end)

	-- Highlight the marked line
	vim.hl.range(buf, 0, "CairnPreviewLine", { target - 1, 0 }, { target - 1, -1 })
end

--- Show empty state in preview window.
function M.clear(win)
	if not vim.api.nvim_win_is_valid(win) then
		return
	end
	local buf = get_empty_buf()
	vim.api.nvim_win_set_buf(win, buf)
end

--- Setup preview-specific highlights.
function M.setup_highlights()
	vim.api.nvim_set_hl(0, "CairnPreviewLine", { link = "Visual", default = true })
end

return M
