-- cairn/ui/window.lua
-- Layout calculation and nvim_open_win helpers.
-- Nothing here knows about marks or filter state.

local M = {}

-- Highlight groups ------------------------------------------------------------

local HL = {
	border_normal = "CairnBorderNormal",
	border_active = "CairnBorderActive",
	cursor_line = "CairnCursorLine",
	index = "CairnIndex",
	filter_prefix = "CairnFilterPrefix",
	title = "CairnTitle",
}
M.HL = HL

function M.setup_highlights()
	-- Border: inactive uses Comment colour, active uses a bright accent
	vim.api.nvim_set_hl(0, HL.border_normal, { link = "Comment", default = true })
	vim.api.nvim_set_hl(0, HL.border_active, { link = "DiagnosticInfo", default = true })
	vim.api.nvim_set_hl(0, HL.cursor_line, { link = "CursorLine", default = true })
	vim.api.nvim_set_hl(0, HL.index, { link = "Number", default = true })
	vim.api.nvim_set_hl(0, HL.filter_prefix, { link = "DiagnosticInfo", default = true })
	vim.api.nvim_set_hl(0, HL.title, { link = "Title", default = true })
end

-- Layout ----------------------------------------------------------------------

--- Returns layout table or nil if terminal too small to show anything useful.
--- @param config table  the full cairn config
function M.calculate_layout(config)
	local total_w = vim.o.columns
	local total_h = vim.o.lines - vim.o.cmdheight - 1

	-- Minimum viable size for the left pane alone
	if total_w < 40 or total_h < 6 then
		return nil
	end

	local show_preview = total_w >= config.ui.min_width_for_preview

	-- Left pane dimensions
	local left_w
	if show_preview then
		left_w = math.floor(total_w * 0.35)
		left_w = math.max(left_w, 30)
		left_w = math.min(left_w, 50)
	else
		left_w = math.floor(total_w * 0.6)
		left_w = math.max(left_w, 30)
	end

	local filter_h = 3 -- 1 line content + 2 border
	local total_used_h = math.floor(total_h * 0.85)
	local list_h = total_used_h - filter_h

	-- Total picker width
	local total_picker_w
	if show_preview then
		local preview_w = total_w - left_w - 4 -- 4 = borders + gap
		total_picker_w = left_w + 2 + preview_w
	else
		total_picker_w = left_w
	end

	-- Center on screen
	local col = math.floor((total_w - total_picker_w) / 2)
	local row = math.floor((total_h - total_used_h) / 2)

	local layout = {
		show_preview = show_preview,

		list = {
			row = row,
			col = col,
			width = left_w,
			height = list_h,
		},

		filter = {
			row = row + list_h + 2, -- +2 for list border bottom
			col = col,
			width = left_w,
			height = 1,
		},
	}

	if show_preview then
		local preview_col = col + left_w + 2
		local preview_w = total_w - preview_col - col - 2
		layout.preview = {
			row = row,
			col = preview_col,
			width = math.max(preview_w, 20),
			height = list_h + filter_h,
		}
	end

	return layout
end

-- Window creation -------------------------------------------------------------

--- Create a floating window with a single-line border.
--- @param buf    number   buffer to display
--- @param opts   table    { row, col, width, height, title?, focusable? }
--- @param active boolean  whether to use the active border highlight
--- @return number  window id
function M.open_win(buf, opts, active)
	local border_hl = active and HL.border_active or HL.border_normal

	-- Build border with optional title
	local border = {
		{ "┌", border_hl },
		{ "─", border_hl },
		{ "┐", border_hl },
		{ "│", border_hl },
		{ "┘", border_hl },
		{ "─", border_hl },
		{ "└", border_hl },
		{ "│", border_hl },
	}

	local win = vim.api.nvim_open_win(buf, false, {
		relative = "editor",
		row = opts.row,
		col = opts.col,
		width = opts.width,
		height = opts.height,
		style = "minimal",
		border = border,
		title = opts.title and { { " " .. opts.title .. " ", HL.title } } or nil,
		title_pos = opts.title and "left" or nil,
		focusable = opts.focusable ~= false,
		zindex = 50,
	})

	return win
end

--- Update the border highlight of an existing window to reflect active state.
function M.set_win_active(win, active)
	if not vim.api.nvim_win_is_valid(win) then
		return
	end
	local border_hl = active and HL.border_active or HL.border_normal
	local border = {
		{ "┌", border_hl },
		{ "─", border_hl },
		{ "┐", border_hl },
		{ "│", border_hl },
		{ "┘", border_hl },
		{ "─", border_hl },
		{ "└", border_hl },
		{ "│", border_hl },
	}
	vim.api.nvim_win_set_config(win, { border = border })
end

--- Safely close a window if valid.
function M.close_win(win)
	if win and vim.api.nvim_win_is_valid(win) then
		vim.api.nvim_win_close(win, true)
	end
end

--- Safely delete a buffer if valid.
function M.close_buf(buf)
	if buf and vim.api.nvim_buf_is_valid(buf) then
		pcall(vim.api.nvim_buf_delete, buf, { force = true })
	end
end

return M
